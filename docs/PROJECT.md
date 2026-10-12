# 项目定位

## 当前定位

本项目是一个面向 SQLite 应用的 Litestream 容器包装方案，当前提供两个经过验证的应用 profile：

- `9router-go`：Go 版本 9Router，默认端口 `20130`；
- `9router`：原版 Node.js 版本 9Router，默认端口 `20128`。

两个 profile 共用 POSIX `/bin/sh` 入口、Litestream 配置、对象存储凭据约定和 SQLite 恢复流程。应用镜像仍在构建阶段固定，运行时环境变量负责配置复制，而不是动态替换应用。

## 为什么这样定位

Litestream 官方已经支持通过 `replicate -exec` 在同一容器中管理应用，但不同应用仍然有自己的：

- 启动命令；
- 数据库路径和环境变量；
- 运行用户；
- 端口；
- 文件权限和迁移行为。

因此本项目采用“共享 wrapper + 应用 profile”，而不是声称一个镜像可以无条件适配所有 SQLite 应用。这样可以复用备份逻辑，同时让每个 profile 的数据库路径和用户模型保持可验证。

## 数据库兼容范围

原版 `9router` 和 `9router-go` 都使用 `$DATA_DIR/db/data.sqlite`。本项目的两个容器 profile 统一设置为：

```text
DATA_DIR=/data
DB_PATH=/data/db/data.sqlite
LITESTREAM_DB_PATH=/data/db/data.sqlite
```

`9router-go` 官方说明其数据库结构与原版 9Router 兼容，可以在停止写入进程后切换运行时并复用数据库。兼容性仍以具体应用版本和 schema 为准；升级前应保留完整 SQLite 数据目录备份。

## 配置原则

### 可复现构建

Litestream、应用基础镜像及多架构 manifest digest 均固定。更新版本时必须同时修改 tag、digest 和变更说明，不使用 `latest` 作为构建输入。

### 显式数据库路径

profile 在启用复制时校验 `DATA_DIR`、`DB_PATH` 和 `LITESTREAM_DB_PATH`。如果平台覆盖了应用路径，容器会失败，而不会静默复制错误的 SQLite 文件。

### 安全传参

入口脚本将 Docker positional arguments 安全转换为 Litestream 的 `-exec` shell command string，保留空格、单引号和特殊字符的参数边界。

### 凭据不入仓库

副本 URL 和凭据只通过环境变量或平台 Secret 注入。文档、测试和提交记录只使用占位符。

## 非目标

当前版本不承诺：

- 运行时自动识别任意应用的 SQLite 文件；
- 仅通过环境变量替换 Docker 基础镜像；
- 自动修复任意应用的数据库迁移或 schema 不兼容；
- 多个应用进程同时写入同一个 SQLite 数据库；
- 将网络文件系统作为 SQLite 数据目录。

## 参考项目

- [Litestream Docker guide](https://litestream.io/guides/docker/)：官方同容器和 sidecar 模式；
- [litestream-docker-example](https://github.com/benbjohnson/litestream-docker-example)：官方 `-exec` 示例；
- [fly-apps/litestream-base](https://github.com/fly-apps/litestream-base)：把 Litestream 注入现有镜像的 base image 思路；
- [sqlite-litestream](https://github.com/fabiocicerchia/sqlite-litestream)：独立的 SQLite + Litestream 发行镜像。

本项目复用这些项目验证过的运行模式，但保留 9Router 特有的 profile 和数据库路径校验。
