# Dependency Update Skill - PowerShell Script
# Checks for outdated dependencies and creates a PR with updates

param(
    [string]$Branch = "dependency-updates",
    [string]$CommitMessage = "chore: update dependencies",
    [switch]$DryRun = $false,
    [switch]$SkipTests = $false
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ── Helpers ──────────────────────────────────────────────────────────────────

function Write-Info  { param([string]$msg) Write-Host "[INFO]  $msg" -ForegroundColor Cyan }
function Write-Ok    { param([string]$msg) Write-Host "[OK]    $msg" -ForegroundColor Green }
function Write-Warn  { param([string]$msg) Write-Host "[WARN]  $msg" -ForegroundColor Yellow }
function Write-Fail  { param([string]$msg) Write-Host "[FAIL]  $msg" -ForegroundColor Red }

function Invoke-Command-Safe {
    param([string]$Cmd, [string[]]$Args)
    $result = & $Cmd @Args 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Fail "Command failed: $Cmd $($Args -join ' ')"
        Write-Fail $result
        exit 1
    }
    return $result
}

# ── Environment checks ────────────────────────────────────────────────────────

Write-Info "Checking required tools..."

foreach ($tool in @("python", "pip", "git")) {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
        Write-Fail "Required tool not found: $tool"
        exit 1
    }
}

$repoRoot = git rev-parse --show-toplevel 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Fail "Not inside a git repository."
    exit 1
}
Set-Location $repoRoot
Write-Ok "Repository root: $repoRoot"

# ── Detect package manager ────────────────────────────────────────────────────

$useUv = $false
$usePip = $false

if (Test-Path "pyproject.toml") {
    Write-Info "Detected pyproject.toml"
    if (Get-Command "uv" -ErrorAction SilentlyContinue) {
        $useUv = $true
        Write-Info "Using uv for dependency management"
    } else {
        $usePip = $true
        Write-Warn "uv not found, falling back to pip"
    }
} elseif (Test-Path "requirements.txt") {
    $usePip = $true
    Write-Info "Detected requirements.txt — using pip"
} else {
    Write-Fail "No pyproject.toml or requirements.txt found."
    exit 1
}

# ── Capture outdated packages ─────────────────────────────────────────────────

Write-Info "Checking for outdated packages..."

$outdatedJson = ""
if ($useUv) {
    # uv doesn't have a native 'list --outdated' yet; fall back to pip inside venv
    $outdatedJson = pip list --outdated --format=json 2>&1
} else {
    $outdatedJson = pip list --outdated --format=json 2>&1
}

try {
    $outdated = $outdatedJson | ConvertFrom-Json
} catch {
    Write-Warn "Could not parse outdated package list. Output was:"
    Write-Host $outdatedJson
    $outdated = @()
}

if ($outdated.Count -eq 0) {
    Write-Ok "All dependencies are up to date. Nothing to do."
    exit 0
}

Write-Info "Found $($outdated.Count) outdated package(s):"
$outdated | ForEach-Object {
    Write-Host "  $($_.name): $($_.version) -> $($_.latest_version)"
}

if ($DryRun) {
    Write-Warn "Dry-run mode enabled — skipping updates and PR creation."
    exit 0
}

# ── Create / switch to update branch ─────────────────────────────────────────

$currentBranch = git rev-parse --abbrev-ref HEAD
Write-Info "Current branch: $currentBranch"

$branchExists = git branch --list $Branch
if ($branchExists) {
    Write-Info "Branch '$Branch' already exists — switching to it."
    Invoke-Command-Safe git @("checkout", $Branch)
} else {
    Write-Info "Creating branch '$Branch'."
    Invoke-Command-Safe git @("checkout", "-b", $Branch)
}

# ── Apply updates ─────────────────────────────────────────────────────────────

Write-Info "Upgrading packages..."

if ($useUv) {
    Invoke-Command-Safe uv @("lock", "--upgrade")
    Invoke-Command-Safe uv @("sync")
} else {
    $packageNames = $outdated | ForEach-Object { $_.name }
    Invoke-Command-Safe pip @(@("install", "--upgrade") + $packageNames)

    if (Test-Path "requirements.txt") {
        Write-Info "Freezing updated requirements..."
        $frozen = pip freeze 2>&1
        Set-Content -Path "requirements.txt" -Value $frozen
    }
}

# ── Run tests ─────────────────────────────────────────────────────────────────

if (-not $SkipTests) {
    Write-Info "Running tests to verify updates..."
    if (Get-Command "pytest" -ErrorAction SilentlyContinue) {
        $testResult = pytest --tb=short -q 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Fail "Tests failed after dependency update:"
            Write-Host $testResult
            Write-Warn "Reverting branch and aborting."
            Invoke-Command-Safe git @("checkout", $currentBranch)
            Invoke-Command-Safe git @("branch", "-D", $Branch)
            exit 1
        }
        Write-Ok "All tests passed."
    } else {
        Write-Warn "pytest not found — skipping test run."
    }
} else {
    Write-Warn "Test run skipped (--SkipTests)."
}

# ── Commit changes ────────────────────────────────────────────────────────────

$status = git status --porcelain
if (-not $status) {
    Write-Ok "No file changes detected after upgrade — nothing to commit."
    exit 0
}

Invoke-Command-Safe git @("add", "-A")
Invoke-Command-Safe git @("commit", "-m", $CommitMessage)
Write-Ok "Changes committed: $CommitMessage"

# ── Push branch ───────────────────────────────────────────────────────────────

Write-Info "Pushing branch '$Branch' to origin..."
Invoke-Command-Safe git @("push", "--set-upstream", "origin", $Branch, "--force-with-lease")
Write-Ok "Branch pushed. Open a PR from '$Branch' into '$currentBranch'."
