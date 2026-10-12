# 运行架构

## 文件结构

```text
Dockerfile                 # 9router-go + Litestream profile
Dockerfile.9router         # 原版 9router + Litestream profile
entrypoint.sh              # 两个 profile 共用的 POSIX 入口
litestream.yml             # 单 SQLite 数据库的 Litestream 配置
README.md                  # 用户文档和快速开始
docs/
├── PROJECT.md             # 项目定位和设计边界
├── ARCHITECTURE.md        # 本文档
└── ROADMAP.md             # 演进路线和验收标准
tests/
├── entrypoint_test.sh     # 入口行为测试
├── config_test.sh          # Dockerfile/配置一致性测试
├── container_smoke_test.sh  # 已构建镜像的健康端点冒烟测试
└── container_replication_test.sh # file replica 恢复/停机同步测试
```

## 构建层次

两个 Dockerfile 都使用多阶段构建：

1. 从固定版本的 `litestream/litestream` 阶段提取二进制；
2. 从固定 digest 的应用镜像开始构建；
3. 复制共享配置和入口脚本；
4. 设置 profile 的数据目录、数据库路径、端口和应用用户。

当前 profile：

| 文件 | 应用镜像 | 默认端口 | 默认命令 | 运行用户 |
| --- | --- | ---: | --- | --- |
| `Dockerfile` | `luqmenul/9router-go:1.9.10` | `20130` | `9router-go` | 基础镜像默认用户（当前构建阶段为 root） |
| `Dockerfile.9router` | `decolua/9router:0.5.95` | `20128` | `node custom-server.js` | `node` |

## 入口流程

```text
容器启动
  │
  ├─ 读取 LITESTREAM_MODE、replica URL、数据库路径和配置路径
  ├─ 创建数据库父目录
  ├─ 处理 Docker CMD positional arguments
  ├─ disabled              ──────> 直接启动应用
  ├─ auto + 无 replica URL  ──────> 警告后直接启动应用
  ├─ required + 无 URL     ──────> 失败
  └─ 有 replica URL
       ├─ 校验 profile 的路径契约
       ├─ 构造安全的 -exec command string
       └─ litestream replicate -config ... -exec ...
```

Litestream 负责应用子进程生命周期和优雅停机同步。启用 `APP_USER` 时，入口会在自身以 root 运行时准备数据目录权限，并通过 `su-exec` 或 `gosu` 让 Litestream 与应用使用同一用户。这样即使 `/data` 被 root 所有的持久化卷覆盖，原版 `9router` 仍然会写入 `/data/db/data.sqlite`。

## 环境变量优先级

### 复制模式

```text
LITESTREAM_MODE=${LITESTREAM_MODE:-auto}
LITESTREAM_REPLICA_URL > REPLICA_URL
LITESTREAM_CONFIG=${LITESTREAM_CONFIG:-/etc/litestream.yml}
LITESTREAM_DB_PATH > DB_PATH > DATA_DIR/db/data.sqlite
```

入口会把最终值导出为 `LITESTREAM_REPLICA_URL` 和 `LITESTREAM_DB_PATH`，供 Litestream 配置文件展开。

### 三种模式

| 模式 | 行为 |
| --- | --- |
| `auto` | 有 replica URL 才复制；没有时直接运行应用。默认模式，兼容已有部署。 |
| `required` | 没有 replica URL 时直接失败，适合生产环境。 |
| `disabled` | 忽略 replica URL，直接运行应用，适合调试和临时操作。 |

## 数据库路径契约

两个 profile 的目标路径均为：

```text
/data/db/data.sqlite
```

启用复制时，profile 通过以下变量拒绝路径分叉：

```text
LITESTREAM_EXPECTED_DATA_DIR=/data
LITESTREAM_EXPECTED_DB_PATH=/data/db/data.sqlite
```

这些变量是 profile 的内部契约，不建议用户覆盖。未来 generic profile 可以不设置它们，改由用户明确提供 `LITESTREAM_DB_PATH`。

## 恢复和复制生命周期

`litestream.yml` 设置 `restore-if-db-not-exists: true`。Litestream 启动时：

1. 如果本地数据库存在，跳过恢复；
2. 如果本地数据库不存在且远端有副本，恢复数据库；
3. 如果本地数据库不存在且远端没有副本，创建新的复制源；
4. 启动应用并持续同步 WAL；
5. 收到停止信号时执行 shutdown sync。

`retention.enabled: false` 将远端旧 LTX 文件的删除交给对象存储生命周期规则。部署时应为对应副本前缀设置生命周期策略。

## 参数边界

Litestream 的 `-exec` 接收一个 shell command string，而 Docker 入口收到的是参数数组。`shell_quote` 对每个参数进行 POSIX 单引号转义，再拼成一个字符串，避免参数中的空格和单引号被重新拆分。

不建议使用 `APP_COMMAND` 传入未解析的命令字符串。应用镜像应继续使用 Docker `CMD` 传递默认命令，profile 只在测试或无 CMD 的场景使用 `APP_DEFAULT_COMMAND`。

## 部署模型

### 单容器

当前两个 profile 使用单容器模式，适合只允许一个 Web/worker 容器的托管平台。应用和 Litestream 共享同一个本地持久化卷。

### Sidecar

Docker 或 Kubernetes 能稳定共享本地卷时，也可以使用官方 Litestream 镜像作为 sidecar。sidecar 更符合“一容器一进程”，但不适用于所有平台，因此不是本仓库当前镜像的默认模式。

SQLite 数据目录应使用本地卷或本地块存储，避免 NFS、SMB 和其它不可靠的网络文件系统。
