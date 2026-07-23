#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PORT="${MODEL_GATEWAY_PORT:-8008}"
PIDFILE="$ROOT/server.pid"

# Kill only running model-gateway server processes
PIDS=$(pgrep -x "model-gateway" 2>/dev/null || true)
if [ -n "$PIDS" ]; then
    echo "Stopping existing gateway (PIDs: $PIDS)..."
    echo "$PIDS" | xargs kill 2>/dev/null || true
    sleep 1
    PIDS=$(pgrep -x "model-gateway" 2>/dev/null || true)
    if [ -n "$PIDS" ]; then
        echo "$PIDS" | xargs kill -9 2>/dev/null || true
        sleep 1
    fi
fi
rm -f "$PIDFILE"

# Wait for port to be free
for i in $(seq 1 15); do
    if ! lsof -iTCP:"$PORT" -sTCP:LISTEN >/dev/null 2>&1; then
        break
    fi
    echo "Waiting for port $PORT... ($i)"
    sleep 0.5
done

exec "$ROOT/scripts/start-server.sh" "$@"
