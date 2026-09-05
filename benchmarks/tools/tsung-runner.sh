#!/usr/bin/env bash
# Sprint 12 Slice 6 — Tsung runner wrapper.
#
# Usage:
#   ./benchmarks/tools/tsung-runner.sh search-baseline
#   TSUNG_TARGET=guildfordvue.fly.dev:443 ./benchmarks/tools/tsung-runner.sh ws-fanout
#
# Pre-requisites:
#   * tsung 1.8+ installed (apt install tsung / brew install tsung)
#   * Target host reachable + capable of serving the load (prod release;
#     don't load-test dev `mix phx.server`, you'll just measure
#     code-reload latency).
#
# Behaviour:
#   * Resolves TSUNG_TARGET=host:port (default localhost:4000) and
#     injects it into a temp copy of the XML before invoking tsung.
#   * Writes Tsung logs to benchmarks/results/tsung-<name>-<ts>/
#   * On exit, prints the report path so the operator can `xdg-open` it.

set -euo pipefail

readonly REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
readonly TSUNG_DIR="$REPO_ROOT/benchmarks/tsung"
readonly RESULTS_DIR="$REPO_ROOT/benchmarks/results"

if [[ $# -lt 1 ]]; then
  echo "usage: $0 <scenario>" >&2
  echo "scenarios:" >&2
  ls "$TSUNG_DIR"/*.xml 2>/dev/null | xargs -n1 basename | sed 's/\.xml$//' | sed 's/^/  /' >&2
  exit 1
fi

readonly SCENARIO="$1"
readonly SOURCE_XML="$TSUNG_DIR/${SCENARIO}.xml"

if [[ ! -f "$SOURCE_XML" ]]; then
  echo "no such scenario: $SCENARIO (expected $SOURCE_XML)" >&2
  exit 2
fi

if ! command -v tsung &>/dev/null; then
  echo "tsung not found in PATH — install tsung 1.8+ first." >&2
  exit 3
fi

readonly TARGET="${TSUNG_TARGET:-localhost:4000}"
readonly TARGET_HOST="${TARGET%:*}"
readonly TARGET_PORT="${TARGET#*:}"
readonly TS=$(date -u +%Y-%m-%dT%H-%M-%S)
readonly OUT_DIR="$RESULTS_DIR/tsung-${SCENARIO}-${TS}"
readonly TMP_XML="$OUT_DIR/run.xml"

mkdir -p "$OUT_DIR"

# Replace localhost:4000 with the target.
sed -E \
  -e "s|host=\"localhost\" port=\"4000\"|host=\"$TARGET_HOST\" port=\"$TARGET_PORT\"|g" \
  "$SOURCE_XML" > "$TMP_XML"

echo "→ Running Tsung scenario '$SCENARIO' against $TARGET"
echo "  XML: $TMP_XML"
echo "  Logs: $OUT_DIR"
echo ""

tsung -l "$OUT_DIR" -f "$TMP_XML" start

# After tsung exits, generate the HTML report.
readonly RUN_DIR=$(find "$OUT_DIR" -maxdepth 2 -type d -name '20*' | head -n 1)
if [[ -n "$RUN_DIR" ]]; then
  (cd "$RUN_DIR" && tsung_stats.pl 2>/dev/null || echo "tsung_stats.pl not found; skipping report")
  echo ""
  echo "→ Report: $RUN_DIR/report.html"
fi
