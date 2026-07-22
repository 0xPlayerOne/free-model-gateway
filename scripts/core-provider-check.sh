#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
ENV_FILE=${1:-"$ROOT/.env.local"}

if [ ! -f "$ENV_FILE" ]; then
    printf 'Environment file not found: %s\n' "$ENV_FILE" >&2
    exit 1
fi

set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

failures=0
for config in gateway.core.example.toml gateway.secondary.example.toml gateway.optional.example.toml; do
    printf 'Checking %s\n' "$config"
    if ! MODEL_GATEWAY_CONFIG="$ROOT/$config" \
        MODEL_GATEWAY_SECRET_STORE=environment \
            cargo run --quiet --manifest-path "$ROOT/Cargo.toml" -- config check --online; then
        failures=$((failures + 1))
    fi
done
if [ "$failures" -gt 0 ]; then
    printf '%s configuration group(s) reported failures\n' "$failures" >&2
    exit 1
fi
