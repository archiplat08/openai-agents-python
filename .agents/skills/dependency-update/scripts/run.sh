#!/bin/bash
# Dependency Update Skill - Automated dependency management script
# Checks for outdated dependencies and creates update PRs

set -euo pipefail

# ─── Configuration ────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"
LOG_PREFIX="[dependency-update]"

# Colours
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Colour

# ─── Helpers ──────────────────────────────────────────────────────────────────
log_info()    { echo -e "${BLUE}${LOG_PREFIX} INFO${NC}  $*"; }
log_success() { echo -e "${GREEN}${LOG_PREFIX} OK${NC}    $*"; }
log_warn()    { echo -e "${YELLOW}${LOG_PREFIX} WARN${NC}  $*"; }
log_error()   { echo -e "${RED}${LOG_PREFIX} ERROR${NC} $*" >&2; }

die() { log_error "$*"; exit 1; }

# ─── Dependency checks ────────────────────────────────────────────────────────
check_requirements() {
    log_info "Checking required tools…"
    for cmd in python3 pip git; do
        command -v "$cmd" &>/dev/null || die "Required command not found: $cmd"
    done

    # uv is preferred but optional
    if command -v uv &>/dev/null; then
        log_success "uv detected – will use uv for faster resolution"
        USE_UV=true
    else
        log_warn "uv not found – falling back to pip"
        USE_UV=false
    fi
}

# ─── Core logic ───────────────────────────────────────────────────────────────
fetch_outdated_pip() {
    log_info "Fetching outdated pip packages…"
    if [[ "$USE_UV" == true ]]; then
        uv pip list --outdated --format=json 2>/dev/null || pip list --outdated --format=json
    else
        pip list --outdated --format=json
    fi
}

update_pyproject_deps() {
    local pyproject="${PROJECT_ROOT}/pyproject.toml"
    [[ -f "$pyproject" ]] || { log_warn "pyproject.toml not found – skipping"; return 0; }

    log_info "Checking pyproject.toml for upgradeable dependencies…"
    if [[ "$USE_UV" == true ]]; then
        uv lock --upgrade 2>&1 | tee /tmp/uv_lock_output.txt || true
        if grep -q 'Updated' /tmp/uv_lock_output.txt 2>/dev/null; then
            log_success "uv.lock refreshed with latest compatible versions"
        else
            log_info "No lock-file changes required"
        fi
    else
        log_warn "uv not available; manual pyproject.toml update required"
    fi
}

check_security_advisories() {
    log_info "Running security advisory check (pip-audit)…"
    if command -v pip-audit &>/dev/null; then
        pip-audit --format=json --output=/tmp/pip_audit_report.json 2>/dev/null || true
        local vuln_count
        vuln_count=$(python3 -c "
import json, sys
try:
    data = json.load(open('/tmp/pip_audit_report.json'))
    vulns = [d for d in data.get('dependencies', []) if d.get('vulns')]
    print(len(vulns))
except Exception:
    print(0)
")
        if [[ "$vuln_count" -gt 0 ]]; then
            log_warn "${vuln_count} package(s) with known vulnerabilities found – review /tmp/pip_audit_report.json"
        else
            log_success "No known vulnerabilities detected"
        fi
    else
        log_warn "pip-audit not installed – skipping security check (run: pip install pip-audit)"
    fi
}

generate_update_summary() {
    local outdated_json="$1"
    log_info "Generating update summary…"

    python3 - <<'PYEOF' "$outdated_json"
import json, sys, textwrap

raw = sys.argv[1] if len(sys.argv) > 1 else '[]'
try:
    packages = json.loads(raw)
except json.JSONDecodeError:
    packages = []

if not packages:
    print("  No outdated packages found.")
    sys.exit(0)

print(f"  {'Package':<30} {'Current':<15} {'Latest':<15} {'Type'}")
print("  " + "-" * 70)
for pkg in packages:
    print(f"  {pkg.get('name','?'):<30} {pkg.get('version','?'):<15} "
          f"{pkg.get('latest_version','?'):<15} {pkg.get('latest_filetype','?')}")
PYEOF
}

create_git_branch() {
    local branch_name="deps/auto-update-$(date +%Y%m%d)"
    log_info "Creating branch: ${branch_name}"
    cd "$PROJECT_ROOT"
    git checkout -b "$branch_name" 2>/dev/null || git checkout "$branch_name"
    echo "$branch_name"
}

commit_changes() {
    local branch_name="$1"
    cd "$PROJECT_ROOT"
    if git diff --quiet && git diff --cached --quiet; then
        log_info "No file changes to commit"
        return 0
    fi
    git add -A
    git commit -m "chore(deps): automated dependency update $(date +%Y-%m-%d)"
    log_success "Changes committed on branch '${branch_name}'"
}

# ─── Entry point ──────────────────────────────────────────────────────────────
main() {
    log_info "Starting dependency update skill"
    log_info "Project root: ${PROJECT_ROOT}"

    check_requirements

    local outdated_json
    outdated_json=$(fetch_outdated_pip)
    generate_update_summary "$outdated_json"

    update_pyproject_deps
    check_security_advisories

    # Only create a branch + commit when running in CI / explicitly requested
    if [[ "${CI:-false}" == "true" || "${CREATE_BRANCH:-false}" == "true" ]]; then
        local branch
        branch=$(create_git_branch)
        commit_changes "$branch"
        log_success "Dependency update branch ready: ${branch}"
    else
        log_info "Set CREATE_BRANCH=true or run in CI to auto-commit changes"
    fi

    log_success "Dependency update skill completed"
}

main "$@"
