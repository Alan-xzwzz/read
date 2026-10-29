# 配置模板

`conf/` 只存放**部署模板**，应用不会直接读取这个目录。

| 文件 | 用途 |
| --- | --- |
| `conf/conf.yml` | SQLite 部署模板（生产默认） |
| `conf/mysqlconf.yml` | MySQL 部署模板 |
| `conf/redis.yml` | Redis 缓存配置片段，合并到 `conf.yml` 的 `cache` 段使用，不是独立配置文件 |

## 使用方式

在应用的工作目录（通常是仓库根目录，或 Docker 中的 `/app`）放一份 `conf.yml`：

```bash
cp conf/conf.yml ./conf.yml
# 按需修改数据库、管理员账号、SMTP、用户权限等配置
```

`src/main/resources/app.yml` 中通过下面的配置加载外部文件：

```yaml
solon.config.add: "./conf.yml"
```

因此：

1. `src/main/resources/app.yml` 提供应用默认值；
2. 工作目录下的 `conf.yml` 会覆盖同名配置；
3. 没有外部 `conf.yml` 时，使用打包在 jar 内的 `src/main/resources/conf.yml`（开发默认，SQLite + P6Spy）。

## 注意

- 根目录的 `conf.yml` 已被 `.gitignore` 忽略。不要提交包含数据库密码、SMTP 密码或管理员密码的配置文件。
- `conf/redis.yml` 只是 `cache` 段的示例；需要 Redis 时把其中的配置合并进 `conf.yml`，不要直接改这个文件。
- `src/main/resources/conf.yml` 和 `src/main/resources/confmysql.yml` 是打包进 jar 的开发默认值；修改部署配置请改工作目录下的 `conf.yml`。
- 修改 `admin.cron`、`admin.update`、`user.*` 等配置后，多数通过 `@Inject(autoRefreshed = true)` 自动生效；涉及数据源、端口的配置需要重启。
- 共享后端不要开启 `admin.update`（定时更新全部书架），否则会持续请求第三方书源。
