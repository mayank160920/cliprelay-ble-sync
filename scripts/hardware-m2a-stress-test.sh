#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

DEFAULT_ARGS=(
  --stability-seconds 8
  --m2a-stress-count 25
  --m2a-stress-timeout 12
)

exec "$SCRIPT_DIR/hardware-smoke-test.sh" "${DEFAULT_ARGS[@]}" "$@"
