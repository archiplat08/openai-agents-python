#!/usr/bin/env bash
# examples-auto-run/scripts/run.sh
# Automatically discovers and runs all examples in the repository,
# capturing output and reporting pass/fail status.

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
EXAMPLES_DIR="${REPO_ROOT}/examples"
LOG_DIR="${REPO_ROOT}/.agents/skills/examples-auto-run/logs"
TIMEOUT_SECONDS="${EXAMPLES_TIMEOUT:-60}"
PYTHON="${PYTHON_BIN:-python}"
PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0
FAILED_EXAMPLES=()

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
log()  { echo "[examples-auto-run] $*"; }
warn() { echo "[examples-auto-run] WARNING: $*" >&2; }
err()  { echo "[examples-auto-run] ERROR: $*" >&2; }

require_command() {
  if ! command -v "$1" &>/dev/null; then
    err "Required command not found: $1"
    exit 1
  fi
}

# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------
require_command "$PYTHON"
require_command timeout

mkdir -p "$LOG_DIR"

if [[ ! -d "$EXAMPLES_DIR" ]]; then
  err "Examples directory not found: $EXAMPLES_DIR"
  exit 1
fi

# ---------------------------------------------------------------------------
# Discover examples
# ---------------------------------------------------------------------------
# Collect all top-level Python files and subdirectory entry points.
mapfile -t EXAMPLE_FILES < <(
  find "$EXAMPLES_DIR" -maxdepth 2 -name '*.py' \
    ! -name '__init__.py' \
    ! -name 'conftest.py' \
    | sort
)

if [[ ${#EXAMPLE_FILES[@]} -eq 0 ]]; then
  warn "No example files discovered under $EXAMPLES_DIR"
  exit 0
fi

log "Discovered ${#EXAMPLE_FILES[@]} example file(s)."

# ---------------------------------------------------------------------------
# Run each example
# ---------------------------------------------------------------------------
for example in "${EXAMPLE_FILES[@]}"; do
  rel_path="${example#"${REPO_ROOT}/"}"
  log_file="${LOG_DIR}/$(echo "$rel_path" | tr '/' '_').log"

  # Skip examples that declare they need live credentials unless explicitly
  # enabled via environment variable.
  if grep -qE '^#\s*SKIP_IN_CI' "$example" 2>/dev/null; then
    if [[ "${CI:-false}" == "true" && "${FORCE_RUN_ALL:-false}" != "true" ]]; then
      log "SKIP  $rel_path  (marked SKIP_IN_CI)"
      (( SKIP_COUNT++ )) || true
      continue
    fi
  fi

  log "RUN   $rel_path"

  set +e
  timeout "$TIMEOUT_SECONDS" \
    "$PYTHON" "$example" \
    > "$log_file" 2>&1
  exit_code=$?
  set -e

  if [[ $exit_code -eq 124 ]]; then
    err "TIMEOUT $rel_path (exceeded ${TIMEOUT_SECONDS}s)"
    FAILED_EXAMPLES+=("$rel_path (timeout)")
    (( FAIL_COUNT++ )) || true
  elif [[ $exit_code -ne 0 ]]; then
    err "FAIL  $rel_path (exit $exit_code)"
    err "      See log: $log_file"
    FAILED_EXAMPLES+=("$rel_path (exit $exit_code)")
    (( FAIL_COUNT++ )) || true
  else
    log "PASS  $rel_path"
    (( PASS_COUNT++ )) || true
  fi
done

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
log "================================================"
log "Results: ${PASS_COUNT} passed, ${FAIL_COUNT} failed, ${SKIP_COUNT} skipped"
log "================================================"

if [[ ${FAIL_COUNT} -gt 0 ]]; then
  err "The following examples failed:"
  for f in "${FAILED_EXAMPLES[@]}"; do
    err "  - $f"
  done
  exit 1
fi

log "All examples completed successfully."
