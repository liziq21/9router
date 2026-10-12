#!/bin/sh
set -e

MODE=${LITESTREAM_MODE:-auto}
REPLICA=${LITESTREAM_REPLICA_URL:-${REPLICA_URL:-}}
CONFIG=${LITESTREAM_CONFIG:-/etc/litestream.yml}
APP_DATA_DIR=${DATA_DIR:-/data}
APP_DB_PATH=${DB_PATH:-${APP_DATA_DIR}/db/data.sqlite}
DB_PATH_TO_REPLICATE=${LITESTREAM_DB_PATH:-$APP_DB_PATH}
EXPECTED_DATA_DIR=${LITESTREAM_EXPECTED_DATA_DIR:-}
EXPECTED_DB_PATH=${LITESTREAM_EXPECTED_DB_PATH:-}
APP_GROUP=${APP_GROUP:-${APP_USER:-}}

case "$MODE" in
    auto|required|disabled)
        ;;
    *)
        echo "[Error] LITESTREAM_MODE must be auto, required, or disabled." >&2
        exit 1
        ;;
esac

case "$DB_PATH_TO_REPLICATE" in
    */*)
        DB_DIR=${DB_PATH_TO_REPLICATE%/*}
        [ -n "$DB_DIR" ] || DB_DIR=/
        ;;
    *)
        DB_DIR=.
        ;;
esac

exec_as_app() {
    if [ -n "${APP_USER:-}" ] && [ "$APP_USER" != "root" ]; then
        if command -v su-exec >/dev/null 2>&1; then
            exec su-exec "$APP_USER" "$@"
        elif command -v gosu >/dev/null 2>&1; then
            exec gosu "$APP_USER" "$@"
        else
            echo "[Error] APP_USER=$APP_USER requires su-exec or gosu." >&2
            exit 1
        fi
    fi

    exec "$@"
}

prepare_app_data() {
    [ -n "${APP_USER:-}" ] || return 0
    [ "$APP_USER" = "root" ] && return 0

    mkdir -p "$APP_DATA_DIR"
    if [ "$(id -u)" -eq 0 ]; then
        if ! command -v chown >/dev/null 2>&1; then
            echo "[Error] APP_USER=$APP_USER requires chown when the entrypoint runs as root." >&2
            exit 1
        fi
        chown -R "$APP_USER:${APP_GROUP:-$APP_USER}" "$APP_DATA_DIR"
    fi
}

# 如果没有传入参数，则默认执行原镜像的主程序 9router-go。
# 保留 positional parameters，避免参数中的空格或特殊字符被破坏。
if [ "$#" -eq 0 ]; then
    set -- "${APP_DEFAULT_COMMAND:-9router-go}"
fi

if [ "$MODE" = "required" ] && [ -z "$REPLICA" ]; then
    echo "[Error] LITESTREAM_MODE=required needs LITESTREAM_REPLICA_URL or REPLICA_URL." >&2
    exit 1
fi

if [ "$MODE" = "disabled" ]; then
    echo "[Litestream] Replication disabled."
    prepare_app_data
    exec_as_app "$@"
fi

if [ -z "$REPLICA" ]; then
    echo "[Warning] Replica URL is not set. Running without Litestream replication."
    prepare_app_data
    exec_as_app "$@"
fi

# Profile images can pin the application and Litestream to one known path. This
# prevents a platform override from silently putting the application's SQLite
# file outside Litestream's coverage. Generic images can leave these unset.
if [ -n "$EXPECTED_DATA_DIR" ] && [ "$APP_DATA_DIR" != "$EXPECTED_DATA_DIR" ]; then
    echo "[Error] DATA_DIR must be $EXPECTED_DATA_DIR when replication is enabled." >&2
    exit 1
fi
if [ -n "$EXPECTED_DB_PATH" ] && {
    [ "$APP_DB_PATH" != "$EXPECTED_DB_PATH" ] ||
    [ "$DB_PATH_TO_REPLICATE" != "$EXPECTED_DB_PATH" ]
}; then
    echo "[Error] DB_PATH and LITESTREAM_DB_PATH must be $EXPECTED_DB_PATH when replication is enabled." >&2
    exit 1
fi

mkdir -p "$DB_DIR"
prepare_app_data

export LITESTREAM_DB_PATH="$DB_PATH_TO_REPLICATE"
export LITESTREAM_REPLICA_URL="$REPLICA"

# Litestream 的 -exec 接收一个 shell command string，而不是参数数组。
# 将每个参数安全地转换为单引号包裹的 shell word，供 Litestream 再解析。
shell_quote() {
    QUOTED="'"
    VALUE=$1

    while [ -n "$VALUE" ]; do
        CHAR=${VALUE%"${VALUE#?}"}
        VALUE=${VALUE#?}
        if [ "$CHAR" = "'" ]; then
            QUOTED="${QUOTED}'\\''"
        else
            QUOTED="${QUOTED}${CHAR}"
        fi
    done

    QUOTED="${QUOTED}'"
}

echo "[Litestream] Remote backup enabled."

APP_CMD=""
for ARG do
    shell_quote "$ARG"
    if [ -n "$APP_CMD" ]; then
        APP_CMD="${APP_CMD} "
    fi
    APP_CMD="${APP_CMD}${QUOTED}"
done

# Litestream 负责接管子进程生命周期并处理优雅停机同步。应用和
# Litestream 使用同一用户，避免 SQLite 与 Litestream 元数据权限不一致。
exec_as_app litestream replicate -config "$CONFIG" -exec "$APP_CMD"
