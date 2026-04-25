# Changelog Generator Skill

Automatically generates and updates the CHANGELOG.md file based on git commit history, pull request descriptions, and semantic versioning conventions.

## Overview

This skill analyzes recent git commits since the last release tag, categorizes changes by type (feat, fix, chore, docs, etc.), and produces a well-formatted changelog entry following the [Keep a Changelog](https://keepachangelog.com/en/1.0.0/) format.

## Trigger Conditions

This skill should be invoked when:
- A new version tag is being prepared
- A release PR is being created or merged
- Manually requested via workflow dispatch
- After a batch of PRs have been merged to the main branch

## Inputs

| Input | Required | Description |
|-------|----------|-------------|
| `version` | Yes | The new version string (e.g., `1.2.0`) |
| `since_tag` | No | The git tag to generate changelog from (defaults to latest tag) |
| `output_file` | No | Path to the changelog file (defaults to `CHANGELOG.md`) |
| `dry_run` | No | If `true`, prints the changelog without writing to file |

## Outputs

- Updated `CHANGELOG.md` with a new version section prepended
- Summary of changes grouped by category
- List of contributors for the release

## Change Categories

Commits are automatically categorized based on conventional commit prefixes:

- **Added** — `feat:` commits
- **Fixed** — `fix:` commits
- **Changed** — `refactor:`, `perf:` commits
- **Deprecated** — commits with `deprecated` in the body
- **Removed** — commits with `remove` or `delete` in the subject
- **Security** — `security:` or commits referencing CVEs
- **Documentation** — `docs:` commits
- **Maintenance** — `chore:`, `ci:`, `build:` commits

## Usage

```bash
# Generate changelog for version 1.2.0
bash .agents/skills/changelog-generator/scripts/run.sh --version 1.2.0

# Generate from a specific tag
bash .agents/skills/changelog-generator/scripts/run.sh --version 1.2.0 --since-tag v1.1.0

# Dry run to preview
bash .agents/skills/changelog-generator/scripts/run.sh --version 1.2.0 --dry-run
```

## Notes

- Merge commits are automatically excluded from the changelog
- Commits with `[skip changelog]` in the message are ignored
- The skill preserves existing CHANGELOG.md content and prepends new entries
- GitHub PR references (e.g., `#123`) are automatically linked if `GITHUB_REPOSITORY` is set
