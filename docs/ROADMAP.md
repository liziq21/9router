# 演进路线

## Phase 1：双应用 profile（已完成 CI 验收）

目标是扩展现有 `9router-go-litestream`，同时提供原版 `9router` 的兼容镜像。

- [x] 抽取共享 POSIX 入口脚本；
- [x] 使用环境变量配置 Litestream 数据库路径和 replica URL；
- [x] 保留 `REPLICA_URL` 兼容；
- [x] 增加 `auto`、`required`、`disabled` 三种模式；
- [x] 增加 `Dockerfile.9router`；
- [x] 统一两个 profile 的 `/data/db/data.sqlite` 路径；
- [x] 在 CI 中配置两个 amd64 镜像构建验证；
- [x] 在 CI 中配置两个构建镜像的健康端点冒烟测试；
- [x] 通过 CI 实际完成两个 amd64 镜像构建和冒烟测试；
- [x] 在 CI 中发布两个多架构镜像；
- [x] 用隔离的 Litestream file replica 验证两个 profile 的恢复和停机同步；
- [ ] 使用真实 S3 兼容对象存储验证两个 profile 的恢复和停机同步。

### Phase 1 验收标准

```sh
sh -n entrypoint.sh tests/entrypoint_test.sh tests/config_test.sh tests/container_smoke_test.sh tests/container_replication_test.sh
sh tests/entrypoint_test.sh
sh tests/config_test.sh
shellcheck entrypoint.sh tests/entrypoint_test.sh tests/config_test.sh tests/container_smoke_test.sh tests/container_replication_test.sh
docker buildx build --platform linux/amd64 --file ./Dockerfile --tag 9router-go-litestream:ci --load .
docker buildx build --platform linux/amd64 --file ./Dockerfile.9router --tag 9router-litestream:ci --load .
```

## Phase 2：通用 SQLite wrapper

在两个 profile 运行稳定后，抽取可独立发布的 generic wrapper/base image。

- [ ] 定义 generic 应用契约：数据库路径、启动用户、启动命令和数据目录；
- [ ] 允许 generic 应用显式设置 `LITESTREAM_DB_PATH`；
- [ ] 增加自定义用户的可靠权限初始化流程；
- [ ] 增加一个最小 SQLite 示例应用；
- [ ] 增加 generic Dockerfile 和 Compose 示例；
- [ ] 单独发布 `litestream-wrapper` 镜像并独立版本化；
- [ ] 明确 generic 镜像不负责应用数据库迁移。

## Phase 3：部署和生态扩展

- [ ] 增加更多经过验证的 SQLite 应用 profile；
- [ ] 增加 sidecar 部署示例；
- [ ] 支持多数据库配置；
- [ ] 评估 Litestream 客户端加密；
- [ ] 增加复制健康检查、metrics 和 dead-man heartbeat 示例；
- [ ] 提供从旧 profile 到 generic wrapper 的迁移指南；
- [ ] 建立应用版本、Litestream 版本和 profile 版本的兼容矩阵。

## 不纳入近期计划的方向

- 运行时根据镜像内容自动发现数据库；
- 用 `latest` 代替固定 digest；
- 让多个应用实例同时写入同一个 SQLite 数据库；
- 在入口脚本中实现应用专属 schema 迁移；
- 用环境变量动态改变 Docker 基础镜像。
