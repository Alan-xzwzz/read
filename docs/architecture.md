# 架构说明

本文描述「轻阅读」服务端的模块边界、请求链路和扩展点。日常改动前先读仓库根目录的 [`AGENTS.md`](../AGENTS.md)。

## 1. 总览

项目是一个 Kotlin/JVM 服务端，运行时由 Solon 提供 HTTP、WebSocket、IoC、缓存、定时任务和模板渲染能力；书源规则引擎放在独立的 `book` 模块中，尽量保持与 Web 框架无关。

```text
Flutter Web / Android / iOS / Windows 客户端
                │  HTTP + WebSocket
                ▼
┌──────────────────────────────────────────────┐
│ web 模块（Solon 应用）                        │
│  controller ── mapper ── model               │
│  config / cron / notification / util          │
│  templates / static（Flutter Web 产物）       │
└──────────────────┬───────────────────────────┘
                   │ 直接调用
                   ▼
┌──────────────────────────────────────────────┐
│ book 模块（规则引擎）                         │
│  webBook：搜索/详情/目录/正文/RSS/本地书       │
│  analyzeRule：JS / XPath / JSONPath / 正则    │
│  model / util / http                          │
│  Android 兼容桩（android.*）                  │
└──────────────────────────────────────────────┘
```

依赖方向只有一个：`web -> book`。`book` 不依赖 Solon、MyBatis-Plus 或 `web` 包。需要反向通知客户端时，通过 `book.app.App` 中的函数变量由 `web` 注入实现。

## 2. 模块与包职责

### `book/`

| 路径 | 职责 |
| --- | --- |
| `book/src/main/kotlin/book/webBook/` | 书源执行入口：`WBook`、搜索、详情、目录、正文、RSS、本地书 |
| `book/.../webBook/analyzeRule/` | 规则解析：JS（Rhino）、Jsoup、XPath、JSONPath、正则、URL 分析 |
| `book/.../webBook/localBook/` | TXT / EPUB / UMD / CBZ 解析 |
| `book/.../model/` | 书源、书籍、章节、规则、RSS 等数据模型（与 legado 书源 JSON 兼容） |
| `book/.../util/` | 文件、编码、HTTP、Cookie、缓存、加解密、字符串工具 |
| `book/.../android/` | 让 legado 代码在 JVM 上运行的 Android API 桩，不要删除 |
| `book/src/lib/` | 本地 jar 依赖（Rhino、xmlpull） |
| `book/src/main/resources/defaultData/` | 内置默认数据，例如 `txtTocRule.json` |

### `src/main/kotlin/web/`

| 路径 | 职责 |
| --- | --- |
| `App.kt` | Solon 启动入口：Session、WebSocket、CORS、静态目录映射 |
| `config/` | 启动初始化：数据源/建表、缓存、书源引擎回调桥接 |
| `controller/api/` | 客户端 API，统一挂在 `/api/{v}` 下 |
| `controller/admin/` | 管理后台页面与后台接口，统一挂在 `/admin` 下 |
| `controller/HomeController.kt`、`QApiController.kt` | Web 首页/注册找回、`/qapi` 客户端管理接口 |
| `model/` | 数据库实体（AutoTable 注解） |
| `mapper/` | MyBatis-Plus Mapper，SQL 以注解为主 |
| `notification/` | 通过 WebSocket 通知客户端数据变更（md5 失效） |
| `cron/` | 定时任务：更新书架、清理缓存、GC、邀请码检查等 |
| `util/read/`、`util/` | 阅读业务辅助、缓存、分页、加解密、邮件、SVG 等 |
| `src/main/resources/templates/` | FreeMarker 模板：`admin/`、`qread/`、`errors/` |
| `src/main/resources/static/` | Flutter Web 构建产物和静态资源，不要手改 |

## 3. 启动流程

1. `web.AppKt.main` 启动 Solon，扫描 `web` 包。
2. 开启 Session 和 WebSocket；为封面/验证码静态资源加 CORS；把 `/assets/` 映射到 `storage/assets/`。
3. `web.config.InitConfig.cookieinit()` 创建运行时目录，并把 `book.app.App` 中的回调替换为 WebSocket 实现。
4. `web.config.DbConfig.autotable()` 注册实体类并调用 AutoTable 建表/改表。
5. `@EnableScheduling` 启动 `web.cron` 下的定时任务。
6. Solon 注册所有 `@Controller`、`@ServerEndpoint`，开始监听端口（默认 8080）。

## 4. 请求链路

### 4.1 客户端 API

```text
HTTP /api/{v}/xxx?accessToken=...
  -> web.controller.api.XxxController
  -> BaseController.getuserbytocken(accessToken)
  -> XxxMapper (MyBatis-Plus)
  -> JsonResponse / QJsonResponse / PageResponse
```

- 路由前缀常量：`web.controller.api.BaseController.routepath = "/api/{v}"`。
- `accessToken` 通过 `usertocken` 表映射到 `users`；失败抛 `DataThrowable().data(JsonResponse(false, NEED_LOGIN))`。
- 当前 `apiversion = 5`。部分接口用 `@Path v: Int` 校验版本，不是所有接口都校验。
- 客户端接口普遍带 `@CrossOrigin(origins = "*")`。

### 4.2 管理后台

```text
浏览器 /admin/xxx
  -> AdminAuthInterceptorImpl（Session 中的 username）
  -> web.controller.admin.XxxController
  -> ModelAndView("admin/xxx.html") 或 JsonResponse
```

- 登录：`/admin/login`，账号密码来自 `admin.username` / `admin.password`。
- 拦截器包含 `/admin`、`/admin/**`，排除 `/admin/login`。
- 模板由 `solon-view-freemarker` 渲染。

### 4.3 书源执行

```text
BookController / ReadController / SourceController
  -> WBook(json, userid, accessToken, ...)
  -> BookInfo / BookChapterList / BookContent / BookList / Rss
  -> AnalyzeRule + AnalyzeUrl
  -> Jsoup / JsoupXpath / JsonPath / Rhino JS / OkHttp
  -> book.model.*
```

- 书源 JSON 存在 `book_source.json`（共享书源）或 `user_book_source.json`（独立书源）字段里。
- `BaseSource` 是执行时使用的轻量结构，`BookSource` 是数据库实体。
- 规则引擎可能执行书源里的 JS。权限控制（`user.source`、`user.allow*`）是安全边界，改动时要特别小心。

### 4.4 WebSocket 与手机代理

WebSocket 端点：

| 端点 | 用途 |
| --- | --- |
| `/api/{v}/ws` | 客户端主连接、消息推送、手机代理请求 |
| `/api/{v}/debug` | 书源调试 |
| `/api/{v}/rssdebug` | RSS 调试 |
| `/api/{v}/checkdebug` | 书源校验 |

`book.app.App` 中的 `get`、`post`、`webview`、`startBrowserAwait`、`getVerificationCode` 等函数是规则引擎的扩展点。`InitConfig` 把它们实现为：

1. 生成 correlation id；
2. 通过 `ApiWebSocket` 发送消息给指定 token 的客户端；
3. 用 `ResponseManager` 等待客户端回包，超时返回空/403。

因此脱离 Solon 单独调用 `book` 引擎时，这些回调是默认空实现。

### 4.5 缓存与通知

- 默认缓存是 Solon 本地缓存（`app.yml` 中 `cache.driverType: local`），可切换 Redisson。
- Controller 上使用 `@Cache(key = "...", seconds = ...)`；key 中常用 `${accessToken}`、`${md5}` 等占位符。
- 数据变更后，`web.notification.*` 会更新 `users` 表中对应的 md5 字段（`bookmd5`、`sourcemd5`、`rssmd5`、`replacemd5`、`ttsmd5`、`groundmd5`），并通过 WebSocket 推送 `Md5Message`，客户端据此刷新。

## 5. 数据模型

| 实体 | 表 | 说明 |
| --- | --- | --- |
| `Users` | `users` | 用户、权限、各类 md5 |
| `Usertocken` | `usertocken` | 登录 token |
| `Booklist` | `booklist` | 书架、阅读进度 |
| `BookSource` | `book_source` | 共享书源 |
| `UserBookSource` | `user_book_source` | 用户独立书源 |
| `BookGroup` | `book_group` | 书架分组 |
| `BookCache` | `book_cache` | 缓存任务 |
| `Bookmark` | `bookmark` | 书签 |
| `ReplaceRule` | `replace_rule` | 净化规则 |
| `RssSource` | `rss_source` | 共享 RSS 源 |
| `UserRssSource` | `user_rss_source` | 用户独立 RSS 源 |
| `HttpTts` | `http_tts` | HTTP TTS |
| `Item` | `item` | 用户键值配置 |
| `Code` | `code` | 邀请码/验证码 |
| `BackGround` | `back_ground` | 背景图 |
| `Sgread` | `sgread` | 阅读相关数据 |

约定：

- Kotlin 属性使用 camelCase，数据库列使用 snake_case（MyBatis-Plus 默认映射）。
- 主键用 `@TableId` + `@PrimaryKey`；ID 常见为 UUID 或 `Md5(用户id + 业务key)`。
- 大文本字段显式标注 `@ColumnType("MEDIUMTEXT")` / `LONGTEXT`。
- 建表/改表由 AutoTable 在启动时完成；`DbConfig.models` 必须包含新实体，否则不会建表。
- 复杂对象通常序列化成 JSON 存在 `LONGTEXT` 字段中（如书源 `json`、`downloadUrls`）。

## 6. 运行时目录

所有相对路径都相对于**进程工作目录**（`System.getProperty("user.dir")`）：

```text
read.db                 SQLite 数据库（默认）
storage/
  assets/               静态资源（封面、验证码、JSON 等），映射到 /assets/
  cache/                规则缓存
  ruleData/             规则大数据缓存
  down/                 下载文件
cache/                  运行时缓存
bookcache/              书籍缓存
cookie/                 Cookie
local/                  本地上传书籍
logs/                   日志
libs/                   构建时复制的运行时依赖
```

macOS 特例：如果工作目录不在 `/Users/` 下，`book.util.getWorkDir()` 会把数据目录切到 `~/.reader`（见 `book/src/main/kotlin/book/util/VertExt.kt`）。

## 7. 配置

配置优先级：

1. `src/main/resources/app.yml`：应用默认值；
2. 工作目录下的 `conf.yml`：`solon.config.add: "./conf.yml"`，覆盖默认值；
3. 没有外部 `conf.yml` 时使用 jar 内的 `src/main/resources/conf.yml`。

部署模板见 [`conf/README.md`](../conf/README.md)。`conf/` 只是模板，不会被应用直接读取。

## 8. 扩展点

| 需求 | 首选位置 |
| --- | --- |
| 新增客户端接口 | `web/controller/api/`，继承 `BaseController` |
| 新增后台页面/接口 | `web/controller/admin/` + `resources/templates/admin/` |
| 新增数据库实体 | `web/model/` + `web/mapper/` + `DbConfig.models` |
| 新增定时任务 | `web/cron/`，实现 `Runnable` + `@Scheduled` |
| 新增通知类型 | `web/notification/` + `users` 的 md5 字段 + 客户端协议 |
| 新增书源 JS 函数 | `book/.../analyzeRule/JsExtensions.kt` 或 `AnalyzeRule.kt` |
| 新增需要客户端参与的能力 | `book/app/App.kt` 加回调 + `web/config/InitConfig.kt` 实现 + WebSocket 消息 |
| 新增配置项 | `@Inject("\${group.key:default}")` + `conf/conf.yml` + README 部署说明 |

## 9. 已知边界与技术债

- **没有自动化测试**。`book` 模块已配置 `kotlin-test` + JUnit Platform，但还没有测试用例；根模块也没有测试依赖。
- Controller 中大量使用 `runBlocking`，阻塞式调用较多；新增代码尽量把耗时逻辑放到协程/线程中，避免占满 HTTP 线程。
- `src/main/resources/static/` 是 Flutter Web 构建产物（约 66 MB），不要手改；更新前端应替换整个构建输出。
- `book` 模块保留了 Android API 桩和 legado 兼容代码，部分命名/结构与服务端风格不一致，改动时优先保持兼容。
- 数据库迁移依赖 AutoTable 的自动比对；破坏性变更需要手工迁移并备份 `read.db`。
- 配置在 `src/main/resources/` 和 `conf/` 中有多份，修改默认值时注意同步。
