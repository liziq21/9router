# 9Router / 9router-go with Litestream

这是一个面向 SQLite 应用的 Litestream 容器包装方案。当前提供两个固定版本的镜像 profile：

| 镜像构建文件 | 应用 | 端口 | 数据库路径 |
| --- | --- | ---: | --- |
| `Dockerfile` | `9router-go` | `20130` | `/data/db/data.sqlite` |
| `Dockerfile.9router` | 原版 `9router` | `20128` | `/data/db/data.sqlite` |

两个 profile 使用相同的 POSIX 入口和 Litestream 配置，把 SQLite WAL 实时复制到 S3 兼容对象存储，并在本地数据库不存在时尝试恢复。

项目定位、架构和演进计划见：

- [`docs/PROJECT.md`](docs/PROJECT.md)：项目定位、边界和设计原则；
- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)：入口流程、变量优先级和数据路径；
- [`docs/ROADMAP.md`](docs/ROADMAP.md)：阶段目标与验收标准；
- [`docs/PHASE2_PROMPT.md`](docs/PHASE2_PROMPT.md)：下一阶段 generic wrapper 会话的可复制提示词。

## 为什么支持两个 9Router

原版 `9router` 和 `9router-go` 都使用 `$DATA_DIR/db/data.sqlite`。`9router-go` 官方项目说明其数据库 schema 与原版 9Router 兼容，因此可以在停止写入进程后切换运行时并继续使用已有 provider、connection、combo、API key 和 usage 数据。

兼容性仍取决于具体版本。升级应用或切换实现前，请停止应用并备份整个 SQLite 数据目录，包括 `data.sqlite`、`data.sqlite-wal`、`data.sqlite-shm` 和 Litestream 元数据目录。

## 获取或构建镜像

GHCR 发布镜像：

```text
ghcr.io/<YOUR_GITHUB_USERNAME>/9router-go-litestream:latest
ghcr.io/<YOUR_GITHUB_USERNAME>/9router-litestream:latest
```

构建 Go profile：

```sh
docker build -f Dockerfile -t 9router-go-litestream:local .
```

构建原版 profile：

```sh
docker build -f Dockerfile.9router -t 9router-litestream:local .
```

两个 Dockerfile 都固定了应用基础镜像和 Litestream 的 tag/digest，不使用 `latest` 作为构建输入。

## 环境变量

### Litestream

| 变量 | 默认值 | 说明 |
| --- | --- | --- |
| `LITESTREAM_MODE` | `auto` | `auto`、`required` 或 `disabled`。 |
| `LITESTREAM_REPLICA_URL` | 未设置 | 副本地址，优先于旧变量 `REPLICA_URL`。 |
| `REPLICA_URL` | 未设置 | 旧版兼容变量，例如 `s3://<BUCKET_NAME>/db?endpoint=https://<ENDPOINT_HOST>`。 |
| `LITESTREAM_DB_PATH` | 应用 `DB_PATH` | Litestream 监控的 SQLite 文件；两个 profile 固定为 `/data/db/data.sqlite`。 |
| `LITESTREAM_CONFIG` | `/etc/litestream.yml` | 自定义 Litestream 配置路径。 |
| `LITESTREAM_ACCESS_KEY_ID` | 未设置 | S3 access key。 |
| `LITESTREAM_SECRET_ACCESS_KEY` | 未设置 | S3 secret key。 |
| `AWS_ACCESS_KEY_ID` | 未设置 | Litestream 支持的标准 AWS 变量。 |
| `AWS_SECRET_ACCESS_KEY` | 未设置 | Litestream 支持的标准 AWS 变量。 |

模式说明：

- `auto`：设置副本地址时启用复制，否则直接运行应用。默认模式，兼容已有部署；
- `required`：没有副本地址时直接失败，适合生产环境；
- `disabled`：忽略副本地址，直接运行应用，适合调试或临时恢复。

两个 9Router profile 在启用复制时会校验 `DATA_DIR`、`DB_PATH` 和 `LITESTREAM_DB_PATH`。不要把它们覆盖到其它路径，否则容器会直接失败，避免产生未备份的数据库。

### 应用

原版 profile 的默认端口是 `20128`，Go profile 的默认端口是 `20130`。应用自身的其它变量继续由基础镜像提供，例如 `PORT`、`HOSTNAME`、`INITIAL_PASSWORD` 和 provider 配置变量。

## Docker CLI 示例

### 9router-go

```sh
docker run -d \
  --name 9router-go \
  --restart unless-stopped \
  -p 20130:20130 \
  -v 9router-go-data:/data \
  -e LITESTREAM_MODE=required \
  -e LITESTREAM_REPLICA_URL="s3://<BUCKET_NAME>/db?endpoint=https://<ENDPOINT_HOST>" \
  -e LITESTREAM_ACCESS_KEY_ID="<YOUR_ACCESS_KEY_ID>" \
  -e LITESTREAM_SECRET_ACCESS_KEY="<YOUR_SECRET_ACCESS_KEY>" \
  ghcr.io/<YOUR_GITHUB_USERNAME>/9router-go-litestream:latest
```

### 原版 9router

```sh
docker run -d \
  --name 9router \
  --restart unless-stopped \
  -p 20128:20128 \
  -v 9router-data:/data \
  -e INITIAL_PASSWORD="<YOUR_INITIAL_PASSWORD>" \
  -e LITESTREAM_MODE=required \
  -e LITESTREAM_REPLICA_URL="s3://<BUCKET_NAME>/db?endpoint=https://<ENDPOINT_HOST>" \
  -e LITESTREAM_ACCESS_KEY_ID="<YOUR_ACCESS_KEY_ID>" \
  -e LITESTREAM_SECRET_ACCESS_KEY="<YOUR_SECRET_ACCESS_KEY>" \
  ghcr.io/<YOUR_GITHUB_USERNAME>/9router-litestream:latest
```

如果只是本地运行而不需要复制，可以省略 replica 变量；默认 `auto` 模式会直接启动应用。也可以显式设置 `LITESTREAM_MODE=disabled`。

## Docker Compose 示例

```yaml
services:
  9router-go:
    image: ghcr.io/<YOUR_GITHUB_USERNAME>/9router-go-litestream:latest
    restart: unless-stopped
    ports:
      - "20130:20130"
    volumes:
      - 9router-go-data:/data
    environment:
      LITESTREAM_MODE: required
      LITESTREAM_REPLICA_URL: s3://<BUCKET_NAME>/db?endpoint=https://<ENDPOINT_HOST>
      LITESTREAM_ACCESS_KEY_ID: <YOUR_ACCESS_KEY_ID>
      LITESTREAM_SECRET_ACCESS_KEY: <YOUR_SECRET_ACCESS_KEY>

volumes:
  9router-go-data:
```

请将真实凭据放在 Compose secrets、平台 Secret 或 `.env` 管理系统中，不要提交到仓库。

## 恢复机制

`litestream.yml` 启用了 `restore-if-db-not-exists: true`：

1. 本地数据库存在时，Litestream 直接开始复制；
2. 本地数据库不存在但远端有备份时，先恢复再启动应用；
3. 本地数据库和远端备份都不存在时，作为首次安装启动并创建新副本；
4. 容器停止时执行最终同步。

当前关闭了 Litestream 主动删除远端旧 LTX 文件，清理由对象存储生命周期规则负责。请为副本前缀配置生命周期策略，否则旧文件会持续累积。

## 数据卷与 SQLite 注意事项

- 使用 Docker named volume、本地 bind mount 或本地块存储；
- 不要将 SQLite 数据目录放在 NFS、SMB 或其它网络文件系统上；
- 数据库备份应包含 WAL、SHM 和 Litestream 元数据；
- 同一个 SQLite 数据库只运行一个主要写入实例；
- 原版 9router 和 9router-go 切换前先停止原进程，避免同时修改相同配置。

## 验证

本地 Shell 验证：

```sh
sh -n entrypoint.sh tests/entrypoint_test.sh tests/config_test.sh tests/container_smoke_test.sh tests/container_replication_test.sh
sh tests/entrypoint_test.sh
sh tests/config_test.sh
shellcheck entrypoint.sh tests/entrypoint_test.sh tests/config_test.sh tests/container_smoke_test.sh tests/container_replication_test.sh
```

镜像验证：

```sh
docker buildx build --platform linux/amd64 --file ./Dockerfile --tag 9router-go-litestream:ci --load .
docker buildx build --platform linux/amd64 --file ./Dockerfile.9router --tag 9router-litestream:ci --load .
sh tests/container_smoke_test.sh 9router-go-litestream:ci 20130
sh tests/container_smoke_test.sh 9router-litestream:ci 20128 /api/health
sh tests/container_replication_test.sh 9router-go-litestream:ci 20130 /health
sh tests/container_replication_test.sh 9router-litestream:ci 20128 /api/health
```

完整的 CI 还会执行 Alpine 容器中的入口测试、两个构建镜像的健康端点冒烟测试（Go profile 使用 `/health`，原版 profile 使用 `/api/health`）和 amd64/arm64 构建。
