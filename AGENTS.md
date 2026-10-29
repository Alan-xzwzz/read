# AGENTS.md

本文件面向在本仓库中工作的 AI 编码代理、自动化和人类开发者。开始改动前请先读完本文件；更深入的背景见 [`docs/architecture.md`](docs/architecture.md)，常见功能落地步骤见 [`docs/adding-features.md`](docs/adding-features.md)。

> 项目：轻阅读（qread）服务端。Kotlin/JVM + Solon，提供书源解析、书架同步、阅读进度、RSS、TTS、本地书和 Web 管理后台。

---

## 0. 快速规则（TL;DR）

1. **依赖方向只能是 `web -> book`**。`book` 模块不要 import Solon、MyBatis-Plus 或 `web` 包；需要通知客户端时走 `book.app.App` 回调。
2. **新增数据库实体必须同时更新 `web/config/DbConfig.kt` 的 `models` 数组**，否则不会建表。
3. **新增 API 放在 `web/controller/api/`，继承 `BaseController`，使用 `JsonResponse`**；错误用 `DataThrowable().data(...)`。
4. **新增后台页面/接口放在 `web/controller/admin/` + `resources/templates/admin/`**，`/admin/**` 已被登录拦截器保护。
5. **不要提交运行时数据**：`read.db`、`storage/`、`cache/`、`bookcache/`、`cookie/`、`local/`、`logs/`、根目录 `conf.yml`、keystore。
6. **不要手改 `src/main/resources/static/` 下的 Flutter 构建产物**（`main.dart.js*`、`canvaskit/`、`flutter_service_worker.js` 等）。
7. **运行目录决定数据目录**。请从仓库根目录启动；换工作目录会导致数据库和缓存跑到别处（macOS 还有 `~/.reader` 特例）。
8. **当前没有自动化测试**。改完至少运行 `./gradlew build`，并按第 12 节做手工验证。不要声称“测试通过”而没有实际执行。
9. **保持 API 字段兼容**。Gson 直接序列化模型，重命名字段会破坏客户端。
10. **改动架构、配置项或部署方式时同步更新文档**：`AGENTS.md`、`docs/`、`README.md`、`conf/README.md`。

---

## 1. 项目速览

- 服务端入口：`src/main/kotlin/web/App.kt`（`web.AppKt`）。
- 默认端口：`8080`。
- Web 阅读端：`/`。
- 管理后台：`/admin`，默认账号 `admin` / `adminadmin`（来自配置）。
- 客户端 API：`/api/{v}`，当前 `apiversion = 5`，`appversion = "3.1.0"`。
- 客户端管理接口：`/qapi`。
- 静态资源：`/assets/` 映射到工作目录下的 `storage/assets/`。
- WebSocket：`/api/{v}/ws`、`/api/{v}/debug`、`/api/{v}/rssdebug`、`/api/{v}/checkdebug`。
- 默认数据库：SQLite（`read.db`），可切换 MySQL。
- 主要语言：Kotlin；少量 Java（编码检测、Base64、TTF 查询等）。
- 注释、日志、错误文案以中文为主，保持一致。

---

## 2. 技术栈

| 类别 | 选型 |
| --- | --- |
| 语言/JVM | Kotlin 2.1.0，JDK 19+（`book` 模块声明 `jvmToolchain(19)`，部署镜像常用 JDK 22） |
| Web 框架 | Solon 3.3.2-M1（`solon-web`、`solon-view-freemarker`、`solon-web-staticfiles`、`solon-scheduling-simple`、`solon-cache-redisson`） |
| 数据库 | MyBatis-Plus 3.5.9、AutoTable 2.1.4、HikariCP、SQLite / MySQL、P6Spy（开发） |
| 序列化 | Gson、Jackson（部分依赖） |
| HTTP | OkHttp 4.12 |
| 规则解析 | Jsoup、JsoupXpath、JsonPath、Rhino JS、正则 |
| 模板 | FreeMarker |
| 前端 | Flutter Web 构建产物（仓库内为生成文件） |
| 构建 | Gradle 8.10 Wrapper，Kotlin DSL |

---

## 3. 仓库地图

```text
read/
├── AGENTS.md                  # 本文件
├── README.md                  # 项目介绍、部署、客户端说明
├── docs/                      # 架构与开发文档
├── samples/                   # 示例书源/书架数据（运行时不读取）
├── conf/                      # 部署配置模板（运行时不直接读取）
├── png/                       # README 截图
├── book/                      # 规则引擎模块（不依赖 Solon）
│   ├── src/lib/               # 本地 jar 依赖
│   └── src/main/
│       ├── kotlin/book/       # webBook、analyzeRule、model、util、localBook、rss
│       └── resources/defaultData/  # 内置默认数据
├── src/main/
│   ├── kotlin/web/            # Solon 服务端
│   │   ├── App.kt             # 启动入口
│   │   ├── config/            # 数据源/建表、缓存、书源回调桥接
│   │   ├── controller/api/    # 客户端 API + WebSocket
│   │   ├── controller/admin/  # 管理后台
│   │   ├── controller/        # 首页、注册、/qapi
│   │   ├── model/             # 数据库实体
│   │   ├── mapper/            # MyBatis-Plus Mapper
│   │   ├── notification/      # WebSocket 数据变更通知
│   │   ├── cron/              # 定时任务
│   │   ├── filter/            # 全局错误处理
│   │   ├── interceptor/       # 后台登录拦截
│   │   └── util/              # 阅读、缓存、分页、加解密、邮件等
│   └── resources/
│       ├── app.yml            # 应用默认配置
│       ├── conf.yml           # 开发默认配置（SQLite + P6Spy）
│       ├── confmysql.yml      # 开发 MySQL 配置
│       ├── templates/         # FreeMarker 模板
│       └── static/            # Flutter Web 产物（不要手改）
├── build.gradle.kts           # 根构建（application）
├── book/build.gradle.kts      # book 模块构建
├── settings.gradle.kts        # rootProject.name = solon-read
├── build.sh                   # 构建脚本
└── run.sh                     # 开发启动脚本
```

关键入口：

- 启动：`src/main/kotlin/web/App.kt`
- API 基类/路由常量：`src/main/kotlin/web/controller/api/BaseController.kt`
- 书源引擎入口：`book/src/main/kotlin/book/webBook/WBook.kt`
- 规则解析：`book/src/main/kotlin/book/webBook/analyzeRule/AnalyzeRule.kt`
- 书源回调桥接：`src/main/kotlin/web/config/InitConfig.kt`
- 建表：`src/main/kotlin/web/config/DbConfig.kt`
- 数据变更通知：`src/main/kotlin/web/notification/NotifyBase.kt`
- 客户端 WebSocket：`src/main/kotlin/web/controller/api/ApiWebSocket.kt`

---

## 4. 构建、运行与部署

### 4.1 环境要求

- JDK 19 或更高（推荐 19/21/22）。
- 使用仓库自带 Gradle Wrapper（8.10），不需要单独安装 Gradle。
- 首次构建需要能访问 Maven Central / 腾讯云镜像（见 `build.gradle.kts`）。

### 4.2 常用命令

| 目的 | 命令 |
| --- | --- |
| 完整构建 | `./gradlew clean build` |
| 只编译 | `./gradlew build -x test` |
| 开发启动 | `./gradlew run` 或 `./run.sh` |
| 构建脚本 | `./build.sh` |
| 只构建 book 模块 | `./gradlew :book:build` |
| 运行测试 | `./gradlew test`（当前没有测试用例） |
| 清理 | `./gradlew clean` |
| Windows | 把 `./gradlew` 换成 `gradlew.bat` |

### 4.3 构建产物

- 可执行 jar：`build/libs/solon-read-1.0-SNAPSHOT.jar`
- 运行时依赖：`libs/`（`jar` 任务会复制 `runtimeClasspath`，并通过 manifest 的 `Class-Path` 引用）
- 启动：`java -jar build/libs/solon-read-1.0-SNAPSHOT.jar`
- 如需指定端口：`java -Dserver.port=8081 -jar build/libs/solon-read-1.0-SNAPSHOT.jar`

`build.sh` 会先 `clean` 再 `build`。`libs/` 是构建产物，已被 `.gitignore` 忽略。

### 4.4 运行位置

请从**仓库根目录**或部署目录（包含 `conf.yml` 的目录）启动：

```bash
cd /path/to/read
./gradlew run
# 或
java -jar build/libs/solon-read-1.0-SNAPSHOT.jar
```

数据库、缓存、日志都相对于进程工作目录创建。换目录启动会得到一套新的数据。

### 4.5 Docker / 部署

见 `README.md` 的「快速部署」「Docker Compose 部署方式」「反向代理」章节。部署时通常：

- 工作目录：`/app`
- jar：`/app/read.jar`
- 配置：`/app/conf.yml`
- 数据：`/app/read.db`、`/app/storage/` 等

反向代理必须支持 WebSocket，四个端点见第 1 节。

---

## 5. 配置与运行时数据

### 5.1 配置优先级

1. `src/main/resources/app.yml`：应用默认值。
2. 工作目录下的 `conf.yml`：通过 `solon.config.add: "./conf.yml"` 覆盖默认值。
3. 没有外部 `conf.yml` 时，使用 jar 内的 `src/main/resources/conf.yml`（开发默认，SQLite + P6Spy）。

`conf/` 目录只是部署模板，应用不会直接读取。详见 [`conf/README.md`](conf/README.md)。

主要配置段：

- `admin.*`：`username`、`password`、`gonggao`、`update`、`code`、`cron`
- `user.*`：`allowchange`、`allowuptxt`、`allowcache`、`allowimg`、`allowcheck`、`source`、`maxsource`、`timeout`、`proxypng`、`index`
- `smtp.*`：验证码邮件
- `default.*`：默认 TTS、净化规则
- `server.http.*`：HTTP 线程
- `cache.*`：缓存驱动与默认过期时间
- `mybatis.*` / `mybatis-plus.*`：Mapper/实体扫描与二级缓存

运行期可变的配置通常用 `@Inject(value = "\${...}", autoRefreshed = true)` 注入；数据源、端口等启动期配置需要重启。

### 5.2 运行时目录

相对于进程工作目录：

```text
read.db                 SQLite 数据库
storage/assets/         静态资源，映射到 /assets/
storage/cache/          规则缓存
storage/ruleData/       规则大数据缓存
storage/down/           下载文件
cache/                  运行时缓存
bookcache/              书籍缓存
cookie/                 Cookie
local/                  本地上传书籍
logs/                   日志
libs/                   构建时复制的依赖
```

macOS 特例：如果工作目录不在 `/Users/` 下，`book.util.getWorkDir()` 会把数据目录切到 `~/.reader`（见 `book/src/main/kotlin/book/util/VertExt.kt`）。

### 5.3 数据库

- 默认 SQLite：`jdbc:sqlite:read.db`，`maxPoolSize: 1`。
- MySQL 模板：`conf/mysqlconf.yml`。
- 开发默认使用 P6Spy 包装：`jdbc:p6spy:sqlite:read.db`（见 `src/main/resources/conf.yml` 和 `spy.properties`）。
- 建表/改表由 AutoTable 在启动时完成，实体列表在 `web/config/DbConfig.kt`。
- 破坏性 schema 变更前备份 `read.db`。`DbConfig` 对 `users` 表有一段“select 失败就 drop 并回填”的兜底逻辑，改用户表时要格外小心。

---

## 6. 架构摘要

完整说明见 [`docs/architecture.md`](docs/architecture.md)。

### 6.1 模块边界

- `web`：HTTP、WebSocket、IoC、数据库、缓存、定时任务、模板。
- `book`：书源规则引擎、模型、HTTP、工具、本地书解析。保持与 Web 框架无关。
- 反向调用：`book.app.App` 中的函数变量由 `web.config.InitConfig` 注入为 WebSocket 实现。

### 6.2 客户端 API 请求流

```text
HTTP /api/{v}/xxx?accessToken=...
  -> XxxController (web/controller/api)
  -> BaseController.getuserbytocken(accessToken)
  -> XxxMapper (web/mapper)
  -> JsonResponse / QJsonResponse / PageResponse
```

- 认证：`accessToken` -> `usertocken` -> `users`。
- 失败：`throw DataThrowable().data(JsonResponse(false, NEED_LOGIN))`。
- 版本：当前 `apiversion = 5`；部分接口用 `@Path v: Int` 校验。

### 6.3 书源执行流

```text
BookController / ReadController / SourceController
  -> WBook(json, userid, accessToken, ...)
  -> BookInfo / BookChapterList / BookContent / BookList / Rss
  -> AnalyzeRule + AnalyzeUrl
  -> Jsoup / JsoupXpath / JsonPath / Rhino JS / OkHttp
```

书源 JS 可以调用 Java 能力。`user.source` 和 `user.allow*` 是安全边界，改动权限逻辑时要特别谨慎。

### 6.4 WebSocket 桥接

`book.app.App` 中的 `get`、`post`、`webview`、`startBrowserAwait`、`getVerificationCode` 等函数由 `InitConfig` 实现为：

1. 生成 correlation id；
2. 通过 `ApiWebSocket` 发给指定 token 的客户端；
3. 用 `ResponseManager` 等待回包，超时返回空/403。

脱离 Solon 单独调用 `book` 引擎时，这些回调是默认空实现。

### 6.5 缓存与通知

- 默认 Solon 本地缓存，可用 Redisson。
- Controller 使用 `@Cache(key = "...", seconds = ...)`。
- 数据变更后更新 `users` 的 md5 字段（`bookmd5`、`sourcemd5`、`rssmd5`、`replacemd5`、`ttsmd5`、`groundmd5`），并通过 WebSocket 推送 `Md5Message`。

---

## 7. 数据与响应约定

### 7.1 数据库实体

| 实体 | 表 |
| --- | --- |
| `Users` | `users` |
| `Usertocken` | `usertocken` |
| `Booklist` | `booklist` |
| `BookSource` | `book_source` |
| `UserBookSource` | `user_book_source` |
| `BookGroup` | `book_group` |
| `BookCache` | `book_cache` |
| `Bookmark` | `bookmark` |
| `ReplaceRule` | `replace_rule` |
| `RssSource` | `rss_source` |
| `UserRssSource` | `user_rss_source` |
| `HttpTts` | `http_tts` |
| `Item` | `item` |
| `Code` | `code` |
| `BackGround` | `back_ground` |
| `Sgread` | `sgread` |

约定：

- Kotlin 属性 camelCase，数据库列 snake_case（MyBatis-Plus 默认映射）。
- 主键：`@TableId` + `@PrimaryKey`；ID 常用 UUID 或 `Md5(用户id + 业务key)`。
- 大文本：`@ColumnType("MEDIUMTEXT")` / `LONGTEXT`。
- 复杂对象序列化成 JSON 存 `LONGTEXT`。
- 新增实体后必须加入 `DbConfig.models`。

### 7.2 响应结构

```kotlin
// 成功
JsonResponse(true).Data(payload)
// 失败
throw DataThrowable().data(JsonResponse(false, ERROR_CONSTANT))
```

- `JsonResponse`：`{ isSuccess, errorMsg, data }`
- `QJsonResponse`：`{ code, msg, data }`
- `PageResponse`：`{ count, page, data, code: 0 }`

错误文案常量在 `src/main/kotlin/web/response/static.kt`。新增通用错误时优先复用/追加常量，不要在 Controller 里散落字符串。

### 7.3 分页

使用 `web/util/page/page.kt`：

```kotlin
PageByAjax(mapper, queryWrapper, page, limit, order)
```

`order` 只允许“字段名 [ASC|DESC]”形式，避免 SQL 注入。

---

## 8. 认证与权限

### 8.1 客户端

- 登录：`/api/{v}/login`，返回 `accessToken`。
- 后续请求携带 `accessToken`。
- `BaseController.getuserbytocken(accessToken)` 完成 token -> user 解析。
- 登录设备超过 20 个会清空旧 token（见 `UserController.login`）。

### 8.2 管理后台

- 登录：`/admin/login`，账号密码来自 `admin.username` / `admin.password`。
- Session key：`username`。
- 拦截器：`AdminAuthInterceptorImpl`，保护 `/admin`、`/admin/**`，排除 `/admin/login`。

### 8.3 用户权限

- `user.source`：
  - `0`：不允许修改书源；
  - `1`：允许修改后台共享书源；
  - `2`：使用用户独立书源。
- `user.allowchange`：是否允许自助修改权限。
- `user.allowuptxt`：是否允许上传 TXT/EPUB。
- `user.allowcache`：是否允许添加缓存任务。
- `user.allowimg`：是否允许图片解密。
- `user.allowcheck`：是否允许校验书源。
- `user.maxsource`：最大书源数量，0 为不限制。
- `user.timeout`：超时禁用书源阈值。

书源可以执行 JS 和部分 Java 能力。给予权限时务必谨慎，不要把共享后端配置成任意用户可编辑书源。

---

## 9. 编码约定

- Kotlin 官方风格，4 空格缩进，UTF-8，LF。
- 保持现有文件风格；不要顺手格式化无关代码，避免巨大 diff。
- Controller 保持薄：参数校验 -> 调 Mapper/服务 -> 返回响应。
- SQL 优先用 Mapper 注解；复杂查询再考虑 XML。
- 使用 `logger.info/error`，不要 `println`。
- 异常用 `DataThrowable().data(...)` 表达业务错误；不要吞掉异常后返回成功。
- 协程：现有 Controller 大量使用 `runBlocking`；新增耗时逻辑尽量放到 `Dispatchers.IO` 或后台线程，避免阻塞 HTTP 线程。
- 非 DI 上下文需要 Mapper 时，使用现有的 `web.util.mapper.mapper.get()`；不要新增全局单例。
- 不要删除 `book/src/main/kotlin/android/` 下的 Android 兼容桩，也不要删除 `book/src/lib/` 下的本地 jar。
- 不要手改 Flutter 生成文件；前端更新应整体替换 `src/main/resources/static/` 构建输出。
- 修改配置/协议/部署方式时同步更新文档。

---

## 10. 新增功能怎么落地

详细步骤和代码片段见 [`docs/adding-features.md`](docs/adding-features.md)。速查：

| 需求 | 位置 |
| --- | --- |
| 新客户端 API | `web/controller/api/`，继承 `BaseController` |
| 新后台页面/接口 | `web/controller/admin/` + `resources/templates/admin/` |
| 新数据表 | `web/model/` + `web/mapper/` + `DbConfig.models` |
| 新定时任务 | `web/cron/`，`Runnable` + `@Scheduled` |
| 新配置项 | `@Inject("\${group.key:default}")` + `conf/conf.yml` + README |
| 新通知类型 | `web/notification/` + `users` md5 字段 + 客户端协议 |
| 新书源 JS 函数 | `book/.../analyzeRule/JsExtensions.kt` 或 `AnalyzeRule.kt` |
| 需要客户端参与的能力 | `book/app/App.kt` 回调 + `web/config/InitConfig.kt` + WebSocket 消息 |

---

## 11. 测试与验证

### 11.1 现状

- 仓库当前**没有测试用例**。
- `book` 模块已配置 `kotlin-test` 和 JUnit Platform；根模块没有测试依赖。
- `./gradlew test` 会成功执行，但不会运行任何测试。

### 11.2 新增测试

- 纯逻辑/规则解析优先放 `book/src/test/kotlin/`。
- 根模块需要测试时，在 `build.gradle.kts` 增加 `testImplementation(kotlin("test"))` 和 `tasks.test { useJUnitPlatform() }`。
- 规则解析测试使用固定 HTML/JSON fixture，不要依赖外网和真实书源。
- 可参考 `samples/` 中的书源结构，但不要在网络测试中直接请求第三方站点。

### 11.3 手工验收

```bash
./gradlew build
./gradlew run
```

1. `/admin/login` 用 `admin/adminadmin` 登录。
2. `/api/5/appversion` 返回 `3.1.0`。
3. 注册/登录客户端账号，拿 `accessToken`。
4. 调用 `/api/5/getBookshelf?accessToken=...`、`/api/5/getBookSources?accessToken=...`。
5. 后台导入 `samples/book-sources/` 的书源，测试搜索、详情、目录、正文。
6. 连接 `/api/5/ws?id=<accessToken>` 验证 WebSocket 和通知。
7. 检查 `logs/` 是否有异常堆栈。

---

## 12. 常见坑

1. **工作目录不对，数据全丢**：`read.db`、`storage/`、`cache/` 都是相对路径。请从仓库根目录或部署目录启动。macOS 不在 `/Users/` 下时会切到 `~/.reader`。
2. **外部 `conf.yml` 覆盖默认值**：根目录一旦存在 `conf.yml`，就会覆盖 jar 内的开发配置。排查配置问题时先确认当前工作目录是否有 `conf.yml`。
3. **新实体没建表**：忘了把实体加入 `DbConfig.models`，AutoTable 不会处理它。
4. **`users` 表兜底逻辑**：`DbConfig.autotable` 在 `select` 失败时会 drop `users` 表并回填。改 `Users` 结构前先备份数据库。
5. **书源回调没生效**：`InitConfig.cookieinit()` 负责把 `book.app.App` 的回调接到 WebSocket。脱离 Solon 调用 `book` 时回调是默认空实现（403/空字符串）。
6. **`mapper.get()` 为空**：`web.util.mapper.mapper` 的静态实例由 Solon `@Bean` 初始化；非 Solon 上下文调用会 NPE。
7. **本地书仓接口只允许本机**：`web/controller/LocalBookController.kt` 校验 `ctx.realIp() == "127.0.0.1"`。
8. **定时任务打爆书源**：共享后端不要开启 `admin.update`；批量任务要限流并加防重入。
9. **SQLite 单连接**：默认 `maxPoolSize: 1`，不要在请求里做长事务/长时间阻塞。
10. **P6Spy 日志很吵**：开发默认配置会打印 SQL；生产模板没有 P6Spy。
11. **不要改 API 字段名**：Gson 直接序列化，客户端依赖 `isSuccess`、`errorMsg`、`data` 等字段。
12. **不要手改 Flutter 产物**：`static/main.dart.js*`、`canvaskit/` 等是生成文件。
13. **路由前缀带版本**：`/api/{v}`，当前 `v=5`。部分接口会校验版本，部分不会；新增接口时明确是否需要校验。
14. **`book` 模块的 Android 桩和本地 jar 不是冗余**：删除会导致规则引擎编译失败。
15. **部分历史文件可能使用非 UTF-8 或 CRLF**：修改时保持原编码/换行风格，避免整文件 diff。

---

## 13. 文档维护

- 架构/模块边界变化：更新 `docs/architecture.md`。
- 新增功能套路变化：更新 `docs/adding-features.md`。
- 配置项/部署方式变化：更新 `conf/README.md`、`README.md` 和本文件第 5 节。
- 新增示例数据：放 `samples/` 并在 `samples/README.md` 说明来源和限制。
- 本文件是代理的默认入口；保持“命令、路径、约束”准确，比写长篇背景更重要。
