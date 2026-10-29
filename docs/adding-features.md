# 新增功能配方

本文给出常见改动的落地步骤。架构背景见 [`architecture.md`](architecture.md)，仓库级约束见 [`AGENTS.md`](../AGENTS.md)。

## 0. 通用检查清单

- [ ] 改动是否跨越 `book` 和 `web`？如果 `book` 需要通知客户端，走 `book.app.App` 回调，不要让 `book` 依赖 Solon。
- [ ] 新增数据库实体是否加入了 `web.config.DbConfig.models`？
- [ ] 新增接口是否使用了统一的 `JsonResponse` / `PageResponse`？
- [ ] 是否保持了现有字段名和响应结构（Gson 直接序列化，改名即破坏客户端）？
- [ ] 是否处理了 `accessToken` 为空、用户不存在、权限不足？
- [ ] 是否避免在 HTTP 线程里做长时间阻塞？
- [ ] 是否更新了 `conf/conf.yml`、`conf/mysqlconf.yml` 和 README 中的部署配置？
- [ ] 是否运行了 `./gradlew build` 并做了手工验证？

---

## 1. 新增一个客户端 API

**位置**：`src/main/kotlin/web/controller/api/FooController.kt`

```kotlin
package web.controller.api

import org.noear.solon.annotation.Controller
import org.noear.solon.annotation.Inject
import org.noear.solon.annotation.Mapping
import org.noear.solon.core.util.DataThrowable
import org.noear.solon.web.cors.annotation.CrossOrigin
import web.mapper.FooMapper
import web.response.JsonResponse
import web.response.NOT_BANK

@Controller
@Mapping(routepath)
@CrossOrigin(origins = "*")
open class FooController : BaseController() {

    @Inject
    lateinit var fooMapper: FooMapper

    @Mapping("/getFoo")
    open fun getFoo(accessToken: String?, id: String?) = run {
        val user = getuserbytocken(accessToken)
        if (id.isNullOrBlank()) {
            throw DataThrowable().data(JsonResponse(false, NOT_BANK))
        }
        val foo = fooMapper.getById(user.id!!, id)
        JsonResponse(true).Data(foo)
    }
}
```

要点：

- `routepath` 是 `BaseController` 中的常量 `/api/{v}`，所以最终路径是 `/api/5/getFoo`。
- 不需要手动注册 Controller，Solon 会扫描 `web` 包。
- 需要校验 API 版本时，在方法参数加 `@Path v: Int`，并比较 `apiversion`（当前为 5）。
- 错误统一用 `DataThrowable().data(JsonResponse(false, 常量))`；错误文案常量在 `web/response/static.kt`。
- 需要分页时用 `web/util/page/page.kt` 的 `PageByAjax`。

---

## 2. 新增数据库实体

### 2.1 实体

**位置**：`src/main/kotlin/web/model/Foo.kt`

```kotlin
package web.model

import com.baomidou.mybatisplus.annotation.TableId
import org.dromara.autotable.annotation.AutoTable
import org.dromara.autotable.annotation.ColumnType
import org.dromara.autotable.annotation.Index
import org.dromara.autotable.annotation.PrimaryKey
import java.util.UUID

@AutoTable(value = "foo")
class Foo {

    @TableId
    @PrimaryKey
    var id: String? = null

    @Index
    var userid: String? = null

    @ColumnType(value = "LONGTEXT")
    var value: String? = null

    fun create(): Foo {
        id = UUID.randomUUID().toString()
        return this
    }
}
```

### 2.2 Mapper

**位置**：`src/main/kotlin/web/mapper/FooMapper.kt`

```kotlin
package web.mapper

import com.baomidou.mybatisplus.core.mapper.BaseMapper
import org.apache.ibatis.annotations.Param
import org.apache.ibatis.annotations.Select
import web.model.Foo

interface FooMapper : BaseMapper<Foo> {
    @Select("SELECT * FROM foo WHERE userid = #{userid} AND id = #{id} LIMIT 1")
    fun getById(@Param("userid") userid: String, @Param("id") id: String): Foo?
}
```

### 2.3 注册建表

在 `src/main/kotlin/web/config/DbConfig.kt` 的 `models` 数组中加入：

```kotlin
private val models = arrayOf(
    // ...
    Foo::class.java,
)
```

要点：

- 不注册就不会建表。
- Mapper 放在 `web.mapper` 包、实体放在 `web.model` 包，`app.yml` 已配置扫描。
- SQL 以注解为主，复杂查询再考虑 XML。
- 大文本字段显式写 `@ColumnType("LONGTEXT")` / `MEDIUMTEXT`。
- AutoTable 负责增量建表/改表；删除字段、改类型等破坏性变更需要备份并手工迁移。
- `DbConfig` 启动时有一段 `users` 表的兜底逻辑（select 失败会 drop 后重建并回填用户），改 `Users` 结构时务必先备份 `read.db`。

---

## 3. 新增定时任务

**位置**：`src/main/kotlin/web/cron/FooJob.kt`

```kotlin
package web.cron

import kotlinx.coroutines.runBlocking
import org.noear.solon.annotation.Inject
import org.noear.solon.scheduling.annotation.Scheduled
import org.slf4j.LoggerFactory

@Scheduled(fixedRate = 1000L * 60 * 10)
class FooJob : Runnable {

    @Inject(value = "\${admin.cron:true}", autoRefreshed = true)
    var cron: Boolean = true

    private val logger = LoggerFactory.getLogger(FooJob::class.java)

    companion object {
        private var running = false
    }

    override fun run() = runBlocking {
        if (!cron || running) return@runBlocking
        running = true
        try {
            // 业务逻辑
        } catch (e: Exception) {
            logger.error("FooJob failed", e)
        } finally {
            running = false
        }
    }
}
```

要点：

- `App` 上已有 `@EnableScheduling`，不需要额外注册。
- 用 `admin.cron` 作为总开关，避免共享部署时误跑。
- 用静态 `running` 标记防止任务重叠。
- 批量任务注意限流，避免把第三方书源打挂。

---

## 4. 新增配置项

1. 在代码中用默认值注入：

```kotlin
@Inject(value = "\${foo.bar:false}", autoRefreshed = true)
var fooBar: Boolean = false
```

2. 在 `conf/conf.yml` 和 `conf/mysqlconf.yml` 增加同名配置。
3. 如果该配置有应用级默认值，也加到 `src/main/resources/app.yml`。
4. 如果 Docker 部署需要环境变量，更新 `README.md` 的 Docker Compose 示例。
5. 运行期可变的配置使用 `autoRefreshed = true`；数据源、端口等启动期配置需要重启。

---

## 5. 新增管理后台页面

1. 新建模板：`src/main/resources/templates/admin/foo.html`。
2. 在 `src/main/kotlin/web/controller/admin/HomeController.kt` 增加页面路由：

```kotlin
@get:Get
@get:Mapping("/foo")
val foo = ModelAndView("admin/foo.html").also {
    it.put("foo", "layui-this")
}
```

3. 在 `src/main/resources/templates/admin/header.html` 增加导航项。
4. 后台接口放在 `src/main/kotlin/web/controller/admin/FooController.kt`：

```kotlin
@Controller
@Mapping("/admin")
class FooController {

    @Inject
    lateinit var fooMapper: FooMapper

    @Get
    @Mapping("/getFoo")
    fun getFoo(id: String?) = run {
        JsonResponse(true).Data(fooMapper.selectById(id))
    }
}
```

要点：

- `/admin/**` 已被 `AdminAuthInterceptorImpl` 保护，`/admin/login` 除外。
- 后台接口和页面都挂在 `/admin` 下。
- 模板使用 FreeMarker，参考现有 `admin/*.html`。

---

## 6. 扩展书源规则引擎

### 6.1 纯服务端能力

- 新增 JS 函数：`book/src/main/kotlin/book/webBook/analyzeRule/JsExtensions.kt`。
- 新增规则解析能力：`AnalyzeRule.kt`、`AnalyzeUrl.kt`、`AnalyzeByJSoup.kt` 等。
- 新增书源字段：`book/src/main/kotlin/book/model/BookSource.kt` 及对应 `model/rule/*`。
- 保持对 legado 书源 JSON 的兼容：新增字段给默认值，未知字段由 Gson 忽略。

### 6.2 需要手机/客户端参与的能力

如果函数需要 WebView、验证码、手机代理等客户端能力：

1. 在 `book/src/main/kotlin/book/app/App.kt` 增加函数变量（默认返回空/403）。
2. 在 `src/main/kotlin/web/config/InitConfig.kt` 的 `cookieinit()` 中实现该回调。
3. 在 `web/src/main/kotlin/web/controller/api/ApiWebSocket.kt` 中处理客户端回包。
4. 如需要新的消息类型，在 `book/src/main/kotlin/book/app/Message.kt` 增加数据类。
5. 同步更新客户端协议（本仓库只包含服务端，客户端需要另行适配）。

要点：

- `book` 模块不能 import Solon 或 `web` 包。
- 回调默认实现必须安全失败（返回空或 403），不能抛异常影响规则解析。
- 书源 JS 可以调用 Java 能力，新增能力时要做输入校验和超时控制。

---

## 7. 新增数据变更通知

如果新增的数据需要实时同步到客户端：

1. 在 `web/model/Users.kt` 增加对应的 md5 字段。
2. 在 `web/mapper/UsersMapper.kt` 增加更新该字段的 SQL。
3. 在 `web/notification/NotifyBase.kt` 的 `sendNotification` 中增加类型分支。
4. 在业务变更处调用对应的 `web.notification.*.sendNotification(...)`。
5. 客户端收到 `Md5Message` 后重新拉取数据。

参考现有 `bookmd5`、`sourcemd5`、`rssmd5`、`replacemd5`、`ttsmd5`、`groundmd5`。

---

## 8. 修改 API 响应

- `JsonResponse` 结构：`{ "isSuccess": Boolean, "errorMsg": String, "data": Any? }`。
- `QJsonResponse` 结构：`{ "code": Int, "msg": String, "data": Any? }`。
- `PageResponse` 结构：`{ "count": Long, "page": Int, "data": Any, "code": 0 }`。

新增字段通常兼容；**重命名或删除字段会破坏客户端**。如果必须改协议，优先新增字段并保留旧字段，或提升 `apiversion` 并同步客户端。

---

## 9. 新增测试

当前没有测试用例。`book` 模块已配置：

```kotlin
testImplementation(kotlin("test"))
tasks.test { useJUnitPlatform() }
```

新增测试：

```text
book/src/test/kotlin/book/.../FooTest.kt
```

根模块如果要加测试，需要在 `build.gradle.kts` 增加 `testImplementation(kotlin("test"))` 和 `tasks.test { useJUnitPlatform() }`。

建议优先测试纯函数和规则解析：

- 规则解析（XPath / JSONPath / 正则 / JS）用固定 HTML/JSON fixture，不要依赖外网。
- 字符串、编码、URL、加解密工具。
- 数据模型的 JSON 序列化/反序列化兼容性。

运行：

```bash
./gradlew test
./gradlew :book:test
```

---

## 10. 手工验收清单

```bash
./gradlew build
./gradlew run
```

1. 打开 `http://127.0.0.1:8080/admin/login`，用 `admin/adminadmin` 登录。
2. 访问 `http://127.0.0.1:8080/api/5/appversion`，确认返回 `3.1.0`。
3. 注册/登录客户端账号，拿到 `accessToken`。
4. 调用 `/api/5/getBookshelf?accessToken=...`、`/api/5/getBookSources?accessToken=...`。
5. 在后台导入 `samples/book-sources/` 中的书源，测试搜索、详情、目录、正文。
6. 打开 `/api/5/ws?id=<accessToken>` 测试 WebSocket 连接和通知。
7. 检查 `logs/` 是否有异常堆栈。
