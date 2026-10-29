# 示例数据

本目录保存用于本地调试、导入演示和回归验证的**示例数据**，应用运行时不会读取这里的内容。

```
samples/
├── book-sources/        # 书源导出 JSON，可在后台「书源管理 -> 导入」中上传
│   ├── 69主站.json
│   ├── 天天看小说.json
│   ├── 本地书仓.json
│   ├── 本地书仓支持分页版.json
│   └── 霹雳书屋.json
└── bookshelf/
    └── bookshelf.json   # 书架/阅读进度示例，字段与客户端备份格式一致
```

## 注意

- 书源会访问第三方网站，规则可能随时失效；示例仅用于验证解析引擎，不代表可用性。
- `本地书仓*.json` 中的 `bookSourceUrl` 是作者机器上的绝对路径（如 `/Users/q9uo11/Downloads/book`），导入后必须改成自己的目录。
- 书源可以执行 JavaScript 并调用部分 Java 能力。只导入你信任的书源，不要在共享后端随意开放书源编辑权限。
- 示例数据可能包含第三方站点地址和书籍元数据，仅作技术演示，请遵守目标站点的服务条款和当地法律。
- 不要把运行时产生的数据（`read.db`、`storage/`、`cache/` 等）放回本目录；它们已被 `.gitignore` 忽略。

## 相关代码

- 书源导入：`src/main/kotlin/web/controller/admin/BookSourceController.kt`
- 书源解析：`book/src/main/kotlin/book/webBook/`
- 默认 TXT 目录规则：`book/src/main/resources/defaultData/txtTocRule.json`
