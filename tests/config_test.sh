#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
GO_DOCKERFILE="$ROOT_DIR/Dockerfile"
ROUTER_DOCKERFILE="$ROOT_DIR/Dockerfile.9router"
GENERIC_DOCKERFILE="$ROOT_DIR/Dockerfile.generic"
ENTRYPOINT="$ROOT_DIR/entrypoint.sh"
LITESTREAM_CONFIG="$ROOT_DIR/litestream.yml"

assert_contains() {
    EXPECTED=$1
    FILE=$2
    if ! grep -Fqx "$EXPECTED" "$FILE"; then
        echo "Expected '$EXPECTED' in $FILE" >&2
        exit 1
    fi
}

# Both profiles must use the same application and Litestream database path.
assert_contains "    DB_PATH=/data/db/data.sqlite \\" "$GO_DOCKERFILE"
assert_contains "    LITESTREAM_DB_PATH=/data/db/data.sqlite \\" "$GO_DOCKERFILE"
assert_contains "    LITESTREAM_EXPECTED_DB_PATH=/data/db/data.sqlite \\" "$GO_DOCKERFILE"
assert_contains "    DB_PATH=/data/db/data.sqlite \\" "$ROUTER_DOCKERFILE"
assert_contains "    LITESTREAM_DB_PATH=/data/db/data.sqlite \\" "$ROUTER_DOCKERFILE"
assert_contains "    LITESTREAM_EXPECTED_DB_PATH=/data/db/data.sqlite \\" "$ROUTER_DOCKERFILE"
assert_contains "  - path: \${LITESTREAM_DB_PATH}" "$LITESTREAM_CONFIG"
assert_contains "      url: \${LITESTREAM_REPLICA_URL}" "$LITESTREAM_CONFIG"

# The shared entrypoint must expose the supported mode and URL compatibility.
assert_contains "MODE=\${LITESTREAM_MODE:-auto}" "$ENTRYPOINT"
assert_contains "REPLICA=\${LITESTREAM_REPLICA_URL:-\${REPLICA_URL:-}}" "$ENTRYPOINT"
assert_contains '    auto|required|disabled)' "$ENTRYPOINT"

# Profile ports, application images, and pinned digests are explicit.
assert_contains 'EXPOSE 20130' "$GO_DOCKERFILE"
assert_contains 'EXPOSE 20128' "$ROUTER_DOCKERFILE"
assert_contains 'CMD ["9router-go"]' "$GO_DOCKERFILE"
assert_contains 'CMD ["node", "custom-server.js"]' "$ROUTER_DOCKERFILE"
assert_contains "    APP_USER=node \\" "$ROUTER_DOCKERFILE"
assert_contains '    APP_GROUP=node' "$ROUTER_DOCKERFILE"
assert_contains 'FROM decolua/9router:0.5.104@sha256:5fc7020f3cf1ca6831bffe80314ecab9dde915d27ee3c479a4bb66f45dabbc27' "$ROUTER_DOCKERFILE"
assert_contains 'FROM luqmenul/9router-go:1.9.14@sha256:e82906a21c77e6bd71e82bbd16119a35c2641c941de7af21a6921176567cac35' "$GO_DOCKERFILE"

# The generic example has an explicit app contract but requires the operator to
# provide LITESTREAM_DB_PATH when replication is enabled.
assert_contains 'FROM python:3.15-alpine@sha256:2699b90f4d562a22e2dd076c82f964032f64814204bff36d271a54ba4cc2c7e2' "$GENERIC_DOCKERFILE"
assert_contains "    DATA_DIR=/var/lib/generic-sqlite \\" "$GENERIC_DOCKERFILE"
assert_contains "    APP_USER=sqlite \\" "$GENERIC_DOCKERFILE"
assert_contains 'EXPOSE 8080' "$GENERIC_DOCKERFILE"
assert_contains 'CMD ["python", "/opt/generic-sqlite/app.py"]' "$GENERIC_DOCKERFILE"
if grep -Fq 'LITESTREAM_DB_PATH=' "$GENERIC_DOCKERFILE"; then
    echo "Generic Dockerfile must not provide a silent database path" >&2
    exit 1
fi

# Keep a recent full snapshot so a fresh instance does not need to replay a
# long remote history before the application can bind its health-check port.
assert_contains 'snapshot:' "$LITESTREAM_CONFIG"
assert_contains '  interval: 1h' "$LITESTREAM_CONFIG"
assert_contains '  retention: 1h' "$LITESTREAM_CONFIG"
# Remote deletion remains delegated to the object-store lifecycle policy; the
# L0 listing check is throttled to reduce requests against capped providers.
assert_contains 'retention:' "$LITESTREAM_CONFIG"
assert_contains '  enabled: false' "$LITESTREAM_CONFIG"
assert_contains 'l0-retention-check-interval: 1h' "$LITESTREAM_CONFIG"

echo 'configuration tests: PASS'
