#!/bin/sh
set -eu

IMAGE=${1:?usage: container_replication_test.sh IMAGE PORT HEALTH_PATH}
PORT=${2:?usage: container_replication_test.sh IMAGE PORT HEALTH_PATH}
HEALTH_PATH=${3:?usage: container_replication_test.sh IMAGE PORT HEALTH_PATH}
NAME="litestream-replication-${PORT}-$$"
DATA_DIR=$(mktemp -d)
REPLICA_DIR=$(mktemp -d)
REPLICA_ENV_FILE=$(mktemp)
chmod 777 "$DATA_DIR" "$REPLICA_DIR"
HOST_UID=$(id -u)
HOST_GID=$(id -g)

REPLICA_BASE_URL=${LITESTREAM_TEST_REPLICA_URL:-${REPLICA_URL:-${LITESTREAM_REPLICA_URL:-file:///replica/backup}}}
REPLICA_PREFIX=${LITESTREAM_TEST_REPLICA_PREFIX:-}

build_replica_url() {
    BASE_URL=$1
    SUFFIX=$2

    case "$BASE_URL" in
        *\?*)
            BASE_PATH=${BASE_URL%%\?*}
            QUERY=${BASE_URL#*\?}
            ;;
        *)
            BASE_PATH=$BASE_URL
            QUERY=
            ;;
    esac

    BASE_PATH=${BASE_PATH%/}
    SUFFIX=${SUFFIX#/}
    if [ -n "$SUFFIX" ]; then
        BASE_PATH="${BASE_PATH}/${SUFFIX}"
    fi

    if [ -n "$QUERY" ]; then
        printf '%s?%s\n' "$BASE_PATH" "$QUERY"
    else
        printf '%s\n' "$BASE_PATH"
    fi
}

REPLICA_URL_FOR_TEST=$(build_replica_url "$REPLICA_BASE_URL" "$REPLICA_PREFIX")

case "$REPLICA_URL_FOR_TEST" in
    s3://*)
        [ -n "${LITESTREAM_ACCESS_KEY_ID:-}" ] || {
            echo "LITESTREAM_ACCESS_KEY_ID is required for an S3 replica test" >&2
            exit 1
        }
        [ -n "${LITESTREAM_SECRET_ACCESS_KEY:-}" ] || {
            echo "LITESTREAM_SECRET_ACCESS_KEY is required for an S3 replica test" >&2
            exit 1
        }
        ;;
esac

printf 'LITESTREAM_REPLICA_URL=%s\n' "$REPLICA_URL_FOR_TEST" > "$REPLICA_ENV_FILE"
if [ -n "${LITESTREAM_ACCESS_KEY_ID:-}" ]; then
    printf 'LITESTREAM_ACCESS_KEY_ID=%s\n' "$LITESTREAM_ACCESS_KEY_ID" >> "$REPLICA_ENV_FILE"
fi
if [ -n "${LITESTREAM_SECRET_ACCESS_KEY:-}" ]; then
    printf 'LITESTREAM_SECRET_ACCESS_KEY=%s\n' "$LITESTREAM_SECRET_ACCESS_KEY" >> "$REPLICA_ENV_FILE"
fi

run_app() {
    docker run --env-file "$REPLICA_ENV_FILE" "$@"
}

trap 'docker rm -f "$NAME" >/dev/null 2>&1 || true; docker run --rm -v "$DATA_DIR:/data" alpine:3.20 sh -c "find /data -mindepth 1 -maxdepth 1 -exec rm -rf {} +; chown $HOST_UID:$HOST_GID /data" >/dev/null 2>&1 || true; docker run --rm -v "$REPLICA_DIR:/replica" alpine:3.20 sh -c "find /replica -mindepth 1 -maxdepth 1 -exec rm -rf {} +; chown $HOST_UID:$HOST_GID /replica" >/dev/null 2>&1 || true; rm -rf "$DATA_DIR" "$REPLICA_DIR" "$REPLICA_ENV_FILE"' EXIT HUP INT TERM

wait_for_health() {
    ATTEMPTS=0
    while [ "$ATTEMPTS" -lt 45 ]; do
        if curl --fail --silent --show-error "http://127.0.0.1:${PORT}${HEALTH_PATH}" >/dev/null 2>&1; then
            return 0
        fi
        ATTEMPTS=$((ATTEMPTS + 1))
        sleep 2
    done

    echo "Container did not become healthy: $IMAGE:$PORT$HEALTH_PATH" >&2
    docker logs "$NAME" >&2 || true
    return 1
}

sqlite_exec() {
    SQL=$1
    docker run --rm \
        -v "$DATA_DIR:/data" \
        alpine:3.20 \
        sh -c 'apk add --no-cache sqlite >/dev/null && sqlite3 /data/db/data.sqlite "$1"' \
        sh "$SQL"
}

run_app -d \
    --name "$NAME" \
    -p "127.0.0.1:${PORT}:${PORT}" \
    -v "$DATA_DIR:/data" \
    -v "$REPLICA_DIR:/replica" \
    -e LITESTREAM_MODE=required \
    "$IMAGE" >/dev/null

wait_for_health

# Stop before writing the marker so an application-specific migration or an
# in-memory SQLite adapter cannot overwrite the marker during shutdown.
docker stop --time 30 "$NAME" >/dev/null
docker rm "$NAME" >/dev/null

sqlite_exec "CREATE TABLE IF NOT EXISTS litestream_test_marker (id TEXT PRIMARY KEY, value TEXT NOT NULL); INSERT OR REPLACE INTO litestream_test_marker(id, value) VALUES ('marker', 'phase1');"

# Start once more with the marker present, then stop gracefully so the marker
# is included in the replica before the local database is removed.
run_app -d \
    --name "$NAME" \
    -p "127.0.0.1:${PORT}:${PORT}" \
    -v "$DATA_DIR:/data" \
    -v "$REPLICA_DIR:/replica" \
    -e LITESTREAM_MODE=required \
    "$IMAGE" >/dev/null

wait_for_health
docker stop --time 30 "$NAME" >/dev/null
docker rm "$NAME" >/dev/null

# Remove only the local database. The replica remains available for restore.
docker run --rm \
    -v "$DATA_DIR:/data" \
    alpine:3.20 \
    sh -c 'rm -rf /data/db'

run_app -d \
    --name "$NAME" \
    -p "127.0.0.1:${PORT}:${PORT}" \
    -v "$DATA_DIR:/data" \
    -v "$REPLICA_DIR:/replica" \
    -e LITESTREAM_MODE=required \
    "$IMAGE" >/dev/null

wait_for_health

MARKER=$(sqlite_exec "SELECT value FROM litestream_test_marker WHERE id = 'marker';")
if [ "$MARKER" != "phase1" ]; then
    echo "Restored marker mismatch: expected phase1, got '$MARKER'" >&2
    docker logs "$NAME" >&2 || true
    exit 1
fi

echo "container replication test: PASS ($IMAGE:$PORT$HEALTH_PATH)"
