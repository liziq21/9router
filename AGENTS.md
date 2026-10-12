# AGENTS.md

## 项目概览

本项目是面向 SQLite 应用的 Litestream 容器包装方案。当前提供两个固定版本的应用 profile：

- `9router-go`，默认端口 `20130`；
- 原版 `9router`，默认端口 `20128`。

两个 profile 共用 POSIX `/bin/sh` 入口和 Litestream 配置，统一监控 `/data/db/data.sqlite`，并通过环境变量适配 S3 兼容对象存储。项目没有应用源代码或包管理器配置。

长期定位、架构和演进计划分别见 `docs/PROJECT.md`、`docs/ARCHITECTURE.md` 和 `docs/ROADMAP.md`。

## 目录与关键文件

- `Dockerfile`：`9router-go` profile。Litestream 和应用版本及多架构 manifest digest 均需固定。
- `Dockerfile.9router`：原版 `9router` profile。与主 Dockerfile 共用 Litestream 版本和入口。
- `entrypoint.sh`：共享容器入口，支持 `auto`、`required`、`disabled` 三种复制模式，并安全传递应用参数。
- `litestream.yml`：Litestream v0.5 通用单数据库配置，路径通过 `LITESTREAM_DB_PATH` 展开。
- `tests/entrypoint_test.sh`：不依赖真实镜像和对象存储的入口行为测试。
- `tests/config_test.sh`：检查两个 profile、应用路径和 Litestream 配置的一致性。
- `tests/container_smoke_test.sh`：启动已构建的 profile 并检查 `/health`，不连接对象存储。
- `docs/PROJECT.md`：项目定位、支持范围和设计边界。
- `docs/ARCHITECTURE.md`：构建层次、入口流程、变量优先级和权限模型。
- `docs/ROADMAP.md`：分阶段演进路线和验收标准。
- `.github/workflows/docker-publish.yml`：Shell 语法检查、ShellCheck、入口测试、双 profile 构建和 GHCR 发布。
- `README.md`：用户配置、运行、恢复和验证说明。

## 修改约定

- `entrypoint.sh` 必须保持 POSIX `/bin/sh` 兼容；不要引入 Bash 专有语法。
- 入口脚本必须保留命令参数边界，包括空格、单引号和其它特殊字符；变量应适当引用。
- 两个 9Router profile 启用复制时必须使用 `/data/db/data.sqlite`，并拒绝 `DATA_DIR`、`DB_PATH` 与 Litestream 路径分叉。
- 新增 generic wrapper 时，数据库路径必须通过显式应用契约提供；不要根据猜测静默选择数据库文件。
- 继续支持已有的 `REPLICA_URL`、`LITESTREAM_ACCESS_KEY_ID` 和 `LITESTREAM_SECRET_ACCESS_KEY` 变量。
- `LITESTREAM_REPLICA_URL` 优先于旧的 `REPLICA_URL`；新的通用变量统一使用 `LITESTREAM_*` 前缀。
- 不要把凭据、访问密钥或真实对象存储 URL 写入源码、测试、文档或提交记录。使用占位符。
- 修改 Litestream 或基础镜像版本时，同时更新 tag 与 digest，并在变更说明中注明原因；不要改用未固定的 `latest`。
- `Dockerfile`（大写 D）是现有 `9router-go` CI profile；`Dockerfile.9router` 是新增原版 profile。不要恢复旧版小写 `dockerfile`。
- 不要修改与当前任务无关的 `__agent__/` 内容。
- 应用基础镜像、应用命令、运行用户和端口属于 profile 构建契约，不要仅依赖运行时环境变量替换基础镜像。

## 本地验证

提交前至少运行：

```sh
sh -n entrypoint.sh tests/entrypoint_test.sh tests/config_test.sh tests/container_smoke_test.sh
sh tests/entrypoint_test.sh
sh tests/config_test.sh
```

如果本机安装了 ShellCheck，再运行：

```sh
shellcheck entrypoint.sh tests/entrypoint_test.sh tests/config_test.sh tests/container_smoke_test.sh
```

验证两个镜像构建时使用：

```sh
docker buildx build --platform linux/amd64 --file ./Dockerfile --tag 9router-go-litestream:ci --load .
docker buildx build --platform linux/amd64 --file ./Dockerfile.9router --tag 9router-litestream:ci --load .
sh tests/container_smoke_test.sh 9router-go-litestream:ci 20130
sh tests/container_smoke_test.sh 9router-litestream:ci 20128 /api/health
```

CI 还会在 Alpine 容器中运行入口测试，并在合并或发布流程中执行两个 profile 的多架构构建。涉及 Dockerfile、入口脚本或 Litestream 配置的改动，应尽可能完成对应的 Docker 构建验证。

## 提交前检查

1. 用 `git diff` 检查只包含预期修改；
2. 确认测试和 ShellCheck 均通过；若因本地缺少 Docker、网络或其它依赖导致未执行，应在交付说明中明确指出；
3. 检查文档中的环境变量、端口、镜像路径和 profile 行为与实际配置一致；
4. 涉及数据库路径、应用版本或 profile 行为时，同步更新对应设计文档和 `docs/ROADMAP.md`。
