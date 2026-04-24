# PR Review Skill

This skill automates pull request review by analyzing code changes, checking for common issues, and providing structured feedback.

## Overview

The PR Review skill performs the following tasks:
1. Analyzes diff content for potential issues
2. Checks code style and formatting compliance
3. Validates test coverage for changed files
4. Identifies security concerns or anti-patterns
5. Posts a structured review comment summarizing findings

## Usage

This skill is triggered automatically on pull request creation or update events.

### Inputs

| Variable | Description | Required |
|----------|-------------|----------|
| `PR_NUMBER` | The pull request number to review | Yes |
| `GITHUB_TOKEN` | GitHub token with PR read/write access | Yes |
| `REPO` | Repository in `owner/repo` format | Yes |
| `BASE_BRANCH` | Base branch for comparison (default: `main`) | No |
| `OPENAI_API_KEY` | OpenAI API key for AI-assisted review | No |

### Outputs

- A review comment posted to the pull request
- Exit code `0` on success, non-zero on failure
- A JSON summary file at `pr-review-summary.json`

## Configuration

Create a `.agents/skills/pr-review/config.yaml` to customize behavior:

```yaml
review:
  check_tests: true
  check_types: true
  check_style: true
  max_diff_lines: 2000
  severity_threshold: warning  # info | warning | error
```

## Examples

### GitHub Actions

```yaml
- name: Run PR Review
  env:
    PR_NUMBER: ${{ github.event.pull_request.number }}
    GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
    REPO: ${{ github.repository }}
    OPENAI_API_KEY: ${{ secrets.OPENAI_API_KEY }}
  run: bash .agents/skills/pr-review/scripts/run.sh
```

## Notes

- The skill requires `gh` CLI to be available in the environment
- Large diffs (> `max_diff_lines`) will be summarized rather than fully analyzed
- Security findings are always reported regardless of `severity_threshold`
