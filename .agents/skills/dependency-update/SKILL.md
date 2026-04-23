# Dependency Update Skill

This skill automates the process of checking for outdated dependencies and creating pull requests to update them in the `openai-agents-python` project.

## Overview

The dependency update skill performs the following tasks:

1. **Scan dependencies** — Reads `pyproject.toml` and `requirements*.txt` files to identify all project dependencies.
2. **Check for updates** — Queries PyPI to find newer versions of each dependency.
3. **Validate compatibility** — Runs the test suite against updated dependencies to ensure nothing breaks.
4. **Report results** — Outputs a structured summary of available updates, including breaking-change indicators based on semver.

## Usage

### Running the skill

**Linux / macOS:**
```bash
bash .agents/skills/dependency-update/scripts/run.sh
```

**Windows (PowerShell):**
```powershell
.agents/skills/dependency-update/scripts/run.ps1
```

## Inputs

| Variable | Description | Default |
|---|---|---|
| `TARGET_ENV` | Python environment to use (`dev`, `prod`) | `dev` |
| `DRY_RUN` | If `true`, only report — do not modify files | `true` |
| `INCLUDE_PRE_RELEASES` | Whether to consider alpha/beta/rc versions | `false` |
| `MAX_UPDATES` | Maximum number of dependencies to update at once | `10` |

## Outputs

The skill writes a JSON report to `dependency-update-report.json` in the project root with the following structure:

```json
{
  "scanned_at": "<ISO 8601 timestamp>",
  "dependencies": [
    {
      "name": "openai",
      "current_version": "1.30.0",
      "latest_version": "1.35.2",
      "update_type": "minor",
      "compatible": true
    }
  ],
  "summary": {
    "total": 12,
    "up_to_date": 8,
    "outdated": 4,
    "breaking": 1
  }
}
```

## Compatibility

- Python 3.9+
- Requires `pip`, `pip-audit`, and internet access to PyPI
- Works in GitHub Actions, local dev environments, and CI/CD pipelines

## Notes

- Always run with `DRY_RUN=true` first to review proposed changes before applying them.
- The skill respects version constraints defined in `pyproject.toml` and will not suggest updates that violate pinned ranges.
- Breaking changes (major version bumps) are flagged but not automatically applied.
