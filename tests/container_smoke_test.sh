#!/bin/sh
set -eu

IMAGE=${1:?usage: container_smoke_test.sh IMAGE PORT}
PORT=${2:?usage: container_smoke_test.sh IMAGE PORT}
NAME="litestream-smoke-${PORT}-$$"

trap 'docker rm -f "$NAME" >/dev/null 2>&1 || true' EXIT HUP INT TERM

docker run -d \
    --name "$NAME" \
    -p "127.0.0.1:${PORT}:${PORT}" \
    -e LITESTREAM_MODE=disabled \
    "$IMAGE" >/dev/null

ATTEMPTS=0
while [ "$ATTEMPTS" -lt 30 ]; do
    if curl --fail --silent --show-error "http://127.0.0.1:${PORT}/health" >/dev/null 2>&1; then
        echo "container smoke test: PASS ($IMAGE:$PORT)"
        exit 0
    fi
    ATTEMPTS=$((ATTEMPTS + 1))
    sleep 2
done

echo "Container did not become healthy: $IMAGE:$PORT" >&2
docker logs "$NAME" >&2 || true
exit 1
