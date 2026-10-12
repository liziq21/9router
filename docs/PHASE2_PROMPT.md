# Phase 2 新会话提示词

下面的内容可以直接复制到新的 coding agent 会话中。

```text
你正在继续维护仓库：liziq21/9router-go-litestream。

请先阅读并遵守：

- AGENTS.md
- docs/PROJECT.md
- docs/ARCHITECTURE.md
- docs/ROADMAP.md
- README.md

## 当前项目状态

项目第一阶段已经完成：

- `Dockerfile`：9router-go profile，默认端口 20130；
- `Dockerfile.9router`：原版 9router profile，默认端口 20128；
- 两个 profile 共用 `entrypoint.sh` 和 `litestream.yml`；
- 两个 profile 统一监控 `/data/db/data.sqlite`；
- 入口支持 `auto`、`required`、`disabled`；
- `LITESTREAM_REPLICA_URL` 优先于旧变量 `REPLICA_URL`；
- 支持 `LITESTREAM_DB_PATH`、`LITESTREAM_CONFIG`、`APP_USER`、`APP_GROUP`；
- 原版 9router 的 `/data` 挂载卷权限已在入口启动时处理；
- CI 已验证两个 amd64 镜像构建；
- CI 已启动两个镜像并检查健康端点：
  - 9router-go：`/health`
  - 原版 9router：`/api/health`
- CI 已成功发布两个 linux/amd64 和 linux/arm64 GHCR 镜像；
- 最新通过的 CI 运行记录见仓库 GitHub Actions；
- Dependabot 的 metadata-action v6 PR 已被主分支直接包含并自动关闭；
- CI 已使用隔离的 Litestream file replica 验证两个 profile 的停机同步、删除本地数据库后的恢复和 marker 持久化；
- 当前尚未使用真实 S3 兼容对象存储完成恢复/停机同步测试；不要把这项说成已经通过。

当前主分支已经有成功 CI，不要回退已有双 profile 改造。

## Phase 2 目标

把当前“共享入口 + 两个应用 profile”进一步抽象为一个可复用的 generic SQLite/Litestream wrapper，同时保持两个现有 9Router profile 的行为和兼容变量不变。

目标不是让入口自动猜测任何应用的数据库，也不是用运行时环境变量替换 Docker 基础镜像。

## 必须完成的工作

### 1. 先设计 generic 应用契约

在写代码前，明确并写入 `docs/ARCHITECTURE.md`：

- 应用启动命令由 Docker `CMD` 的 positional arguments 提供；
- generic profile 不依赖固定的 `9router-go` 默认命令；
- generic profile 启用复制时必须显式提供 `LITESTREAM_DB_PATH`；
- 不要根据 `/data`、文件名或目录扫描猜测 SQLite 文件；
- 应用数据目录、SQLite 路径、应用用户和组必须是显式契约；
- `APP_COMMAND` 这种未解析的命令字符串不能作为主要接口；
- 应用镜像、基础镜像和端口仍属于构建期 profile 契约；
- generic wrapper 不负责应用专属 schema migration。

保留并记录变量优先级：

```text
LITESTREAM_MODE=${LITESTREAM_MODE:-auto}
LITESTREAM_REPLICA_URL > REPLICA_URL
LITESTREAM_CONFIG=${LITESTREAM_CONFIG:-/etc/litestream.yml}
```

generic 模式下，数据库路径契约应优先使用：

```text
LITESTREAM_DB_PATH
```

只有经过明确设计和测试的应用 profile 才能设置默认路径或 `LITESTREAM_EXPECTED_*` 校验。

### 2. 重构共享入口，但不能破坏两个现有 profile

根据契约改造 `entrypoint.sh`，要求：

- 继续保持 POSIX `/bin/sh`；
- 继续保留参数边界，包括空格、单引号和特殊字符；
- 继续支持 `auto`、`required`、`disabled`；
- 继续支持 `REPLICA_URL`、`LITESTREAM_ACCESS_KEY_ID`、`LITESTREAM_SECRET_ACCESS_KEY`；
- 继续支持 `LITESTREAM_REPLICA_URL` 优先级；
- 复制模式仍使用 `litestream replicate -config ... -exec ...`；
- 应用和 Litestream 在设置 `APP_USER` 时使用同一用户；
- root 启动入口时继续正确准备应用数据目录权限；
- profile 的固定路径校验继续有效；
- generic 模式不能静默回退到一个猜测的数据库路径；
- 没有复制时，应用仍然可以直接运行。

如果发现当前入口同时承担了 profile 默认行为和 generic 行为，优先用显式变量/契约区分，不要复制两套互相漂移的入口脚本。

### 3. 增加 generic 示例

设计并实现一个最小 generic SQLite 示例，建议包含：

- 一个极小的应用进程，能创建或更新 SQLite 文件；
- 一个 generic Dockerfile 或可复用 base/runtime 示例；
- 一个 Compose 示例；
- 明确的 `LITESTREAM_DB_PATH`、`LITESTREAM_REPLICA_URL`、`APP_USER` 和 `CMD` 用法；
- 不包含真实对象存储 URL、凭据或访问密钥。

如果 generic wrapper 的发布形式存在多个合理方案，请先比较：

1. 可被应用 Dockerfile `FROM` 的 base image；
2. 复制 Litestream 二进制和入口的 runtime layer；
3. 单独 sidecar；
4. 本仓库内的 generic 示例镜像。

选择一个最小、可验证、不会误导用户的方案，并把取舍写进 `docs/PROJECT.md` 或 `docs/ARCHITECTURE.md`。

不要为了“通用”而发布一个无法知道应用命令、SQLite 路径、用户或端口的黑盒镜像。

### 4. 测试

扩展或新增测试覆盖：

- generic 模式缺少显式 `LITESTREAM_DB_PATH` 时的行为；
- generic 模式使用显式数据库路径时的 Litestream 参数；
- `auto`、`required`、`disabled`；
- `LITESTREAM_REPLICA_URL` 覆盖 `REPLICA_URL`；
- 空格、单引号和特殊字符参数；
- `APP_USER` / `APP_GROUP` 权限准备；
- 现有 9router-go profile 路径契约；
- 现有 9router profile 路径契约；
- 两个现有 profile 的 container smoke test 健康端点；
- generic 示例的本地启动/健康检查（如果示例提供 HTTP 服务）。

不要写只重复实现细节的低价值测试。测试应验证路径契约、模式切换、参数边界、用户权限或容器生命周期。

### 5. 文档和路线图

同步更新：

- `docs/PROJECT.md`：generic wrapper 的最终定位、适用范围和非目标；
- `docs/ARCHITECTURE.md`：generic 契约、入口流程、变量优先级和权限模型；
- `docs/ROADMAP.md`：将已完成项目标记为完成，记录仍未完成的真实对象存储恢复测试；
- `README.md`：增加 generic 示例的使用说明，并保持两个 9Router profile 的现有文档准确；
- `AGENTS.md`：增加 generic wrapper 的维护约定和验证命令。

### 6. CI

保持现有双 profile CI：

- Shell syntax；
- config test；
- ShellCheck；
- entrypoint behavior test；
- 两个现有 profile 的 amd64 构建；
- 两个现有 profile 的健康端点冒烟；
- main/tag 上的两个多架构发布。

如果新增 generic 示例镜像：

- 在 PR 验证中构建并测试它；
- 不要让 generic 示例的失败阻塞既有 profile 的行为测试信息；
- 只有真正稳定后才考虑单独发布 generic wrapper 镜像；
- 所有基础镜像和 action 版本继续固定或使用仓库现有 Dependabot 约定。

## 明确禁止

- 不要删除 `Dockerfile` 或 `Dockerfile.9router`；
- 不要改回只支持 `9router-go`；
- 不要移除旧的 `REPLICA_URL` 兼容；
- 不要把 `latest` 作为 Docker 构建输入；
- 不要把真实凭据、访问密钥或真实 bucket URL 写入仓库；
- 不要根据猜测自动选择数据库文件；
- 不要让 generic wrapper 静默覆盖用户传入的数据库路径；
- 不要用未解析的 `APP_COMMAND` 字符串替代 Docker `CMD` 参数；
- 不要引入 Bash 专有语法；
- 不要修改 `__agent__/`；
- 不要把尚未执行的对象存储恢复测试写成已通过。

## 开始前的检查

先运行并检查：

```sh
git status --short
git log --oneline -10
sh -n entrypoint.sh tests/entrypoint_test.sh tests/config_test.sh tests/container_smoke_test.sh
sh tests/entrypoint_test.sh
sh tests/config_test.sh
shellcheck entrypoint.sh tests/entrypoint_test.sh tests/config_test.sh tests/container_smoke_test.sh
```

然后阅读现有实现，给出简短实施计划，再开始修改。

## 完成标准

交付前必须：

1. 运行全部本地可用 Shell 检查；
2. 检查 `git diff --check`；
3. 检查没有凭据或真实对象存储 URL；
4. 检查现有两个 profile 的行为没有回退；
5. 尽可能完成 Docker 构建/冒烟；没有 Docker 时明确说明；
6. 更新项目文档和 `docs/ROADMAP.md`；
7. 汇总修改文件、测试结果和未完成的真实对象存储验收项。
```
