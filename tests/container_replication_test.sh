#!/bin/sh
set -eu

IMAGE=${1:?usage: container_replication_test.sh IMAGE PORT HEALTH_PATH}
PORT=${2:?usage: container_replication_test.sh IMAGE PORT HEALTH_PATH}
HEALTH_PATH=${3:?usage: container_replication_test.sh IMAGE PORT HEALTH_PATH}
NAME="litestream-replication-${PORT}-$$"
DATA_DIR=$(mktemp -d)
REPLICA_DIR=$(mktemp -d)
chmod 777 "$DATA_DIR" "$REPLICA_DIR"
HOST_UID=$(id -u)
HOST_GID=$(id -g)

trap 'docker rm -f "$NAME" >/dev/null 2>&1 || true; docker run --rm -v "$DATA_DIR:/data" alpine:3.20 sh -c "find /data -mindepth 1 -maxdepth 1 -exec rm -rf {} +; chown $HOST_UID:$HOST_GID /data" >/dev/null 2>&1 || true; docker run --rm -v "$REPLICA_DIR:/replica" alpine:3.20 sh -c "find /replica -mindepth 1 -maxdepth 1 -exec rm -rf {} +; chown $HOST_UID:$HOST_GID /replica" >/dev/null 2>&1 || true; rm -rf "$DATA_DIR" "$REPLICA_DIR"' EXIT HUP INT TERM

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

docker run -d \
    --name "$NAME" \
    -p "127.0.0.1:${PORT}:${PORT}" \
    -v "$DATA_DIR:/data" \
    -v "$REPLICA_DIR:/replica" \
    -e LITESTREAM_MODE=required \
    -e LITESTREAM_REPLICA_URL=file:///replica/backup \
    "$IMAGE" >/dev/null

wait_for_health

# Stop before writing the marker so an application-specific migration or an
# in-memory SQLite adapter cannot overwrite the marker during shutdown.
docker stop --time 30 "$NAME" >/dev/null
docker rm "$NAME" >/dev/null

sqlite_exec "CREATE TABLE IF NOT EXISTS litestream_test_marker (id TEXT PRIMARY KEY, value TEXT NOT NULL); INSERT OR REPLACE INTO litestream_test_marker(id, value) VALUES ('marker', 'phase1');"

# Start once more with the marker present, then stop gracefully so the marker
# is included in the replica before the local database is removed.
docker run -d \
    --name "$NAME" \
    -p "127.0.0.1:${PORT}:${PORT}" \
    -v "$DATA_DIR:/data" \
    -v "$REPLICA_DIR:/replica" \
    -e LITESTREAM_MODE=required \
    -e LITESTREAM_REPLICA_URL=file:///replica/backup \
    "$IMAGE" >/dev/null

wait_for_health
docker stop --time 30 "$NAME" >/dev/null
docker rm "$NAME" >/dev/null

# Remove only the local database. The replica remains available for restore.
docker run --rm \
    -v "$DATA_DIR:/data" \
    alpine:3.20 \
    sh -c 'rm -rf /data/db'

docker run -d \
    --name "$NAME" \
    -p "127.0.0.1:${PORT}:${PORT}" \
    -v "$DATA_DIR:/data" \
    -v "$REPLICA_DIR:/replica" \
    -e LITESTREAM_MODE=required \
    -e LITESTREAM_REPLICA_URL=file:///replica/backup \
    "$IMAGE" >/dev/null

wait_for_health

MARKER=$(sqlite_exec "SELECT value FROM litestream_test_marker WHERE id = 'marker';")
if [ "$MARKER" != "phase1" ]; then
    echo "Restored marker mismatch: expected phase1, got '$MARKER'" >&2
    docker logs "$NAME" >&2 || true
    exit 1
fi

echo "container replication test: PASS ($IMAGE:$PORT$HEALTH_PATH)"
