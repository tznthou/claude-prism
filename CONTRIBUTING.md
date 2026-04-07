# Contributing to claude-prism

Thanks for your interest in contributing! claude-prism is a lightweight cross-provider AI orchestration toolkit for Claude Code, and we welcome contributions that align with this mission.

## Table of Contents

- [Code of Conduct](#code-of-conduct)
- [Getting Started](#getting-started)
- [Development Workflow](#development-workflow)
- [Code Standards](#code-standards)
- [Testing](#testing)
- [Submitting Changes](#submitting-changes)
- [Reporting Issues](#reporting-issues)
- [What We Look For](#what-we-look-for)
- [What We Don't Accept](#what-we-dont-accept)

## Code of Conduct

This project follows the [Contributor Covenant Code of Conduct](CODE_OF_CONDUCT.md). By participating, you are expected to uphold this code.

## Getting Started

### Prerequisites

| Tool | Required | Notes |
|------|----------|-------|
| Bash 3.2+ | Yes | macOS ships with 3.2 — all scripts must be compatible |
| [ShellCheck](https://www.shellcheck.net/) | For linting | `brew install shellcheck` or `apt install shellcheck` |
| [Claude Code](https://claude.com/claude-code) | For testing | The orchestrator that runs our commands |
| [Gemini CLI](https://github.com/google-gemini/gemini-cli) | Optional | For testing Gemini-related commands |
| [Codex CLI](https://github.com/openai/codex) | Optional | For testing Codex-related commands |

### Setup

```bash
# Fork and clone
git clone https://github.com/<your-username>/claude-prism.git
cd claude-prism

# Install locally
./install.sh

# Run smoke tests to verify
./tests/smoke-test.sh
```

## Development Workflow

1. **Create a branch** from `main`:
   ```bash
   git checkout -b feat/your-feature
   ```

2. **Make your changes** — edit scripts in `scripts/`, commands in `commands/`, or tests in `tests/`.

3. **Test locally**:
   ```bash
   # Run smoke tests
   ./tests/smoke-test.sh

   # Run ShellCheck on all scripts
   shellcheck scripts/*.sh tests/*.sh install.sh uninstall.sh
   ```

4. **Install and verify** — run `./install.sh` to deploy your changes to `~/.claude/`, then test the commands in Claude Code.

5. **Commit** using [conventional commits](#commit-convention).

6. **Open a PR** against `main`.

## Code Standards

### Bash 3.2 Compatibility

All shell scripts **must** work on macOS's built-in Bash 3.2. This means:

| Avoid (Bash 4+) | Use Instead |
|-----------------|-------------|
| `${var,,}` (lowercase) | `printf '%s' "$var" \| tr '[:upper:]' '[:lower:]'` |
| Associative arrays (`declare -A`) | Indexed arrays or separate variables |
| `readarray` / `mapfile` | `while IFS= read -r` loops |
| `|&` (pipe stderr) | `2>&1 \|` |

### ShellCheck

All scripts must pass [ShellCheck](https://www.shellcheck.net/) with zero warnings. CI enforces this automatically.

```bash
shellcheck scripts/*.sh tests/*.sh install.sh uninstall.sh
```

### Script Conventions

- Use `set -euo pipefail` at the top of every script
- Quote all variable expansions: `"$var"`, not `$var`
- Use `#!/usr/bin/env bash` as the shebang
- Log to stderr (`>&2`), output results to stdout
- Prefer `printf` over `echo` for portability

### Command Prompts (Markdown)

- Command definitions live in `commands/pi-*.md`
- Prompts are written in English; output language follows the user's Claude Code settings
- Include graceful degradation instructions for provider failures
- Reference the [Confidence Scoring Framework](spec/confidence-scoring-v1.md) where applicable

### Commit Convention

We use [Conventional Commits](https://www.conventionalcommits.org/):

```
feat: add new provider support
fix: handle timeout in call-gemini.sh
docs: update CLI compatibility table
refactor: simplify error classification logic
chore: update checksums
test: add smoke test for pi-research
```

- Commit messages in **English**
- Keep the subject line under 72 characters
- Use imperative mood ("add", not "added" or "adds")

## Testing

### Smoke Tests

The primary test suite is `tests/smoke-test.sh`. It validates:

- Script syntax and ShellCheck compliance
- Binary detection logic
- `--dry-run` mode for all wrapper scripts
- Domain detection (`detect-domain.sh`)
- Install/uninstall script behavior

```bash
./tests/smoke-test.sh
```

All tests must pass before submitting a PR. CI runs these automatically.

### Manual Testing

For changes to command prompts or provider interactions, manually test in Claude Code:

```bash
# Install your changes
./install.sh

# Test in Claude Code
# /pi-code-review --dry-run
# /pi-ask-gemini --dry-run "test prompt"
```

Use `--dry-run` to validate the request path without consuming API tokens.

## Submitting Changes

### Pull Requests

1. **One PR, one concern** — don't bundle unrelated changes
2. **Describe what and why** — the diff shows *what* changed; the PR description should explain *why*
3. **Update checksums** if you modified files tracked by `checksums.sha256`:
   ```bash
   shasum -a 256 scripts/*.sh commands/*.md install.sh uninstall.sh > checksums.sha256
   ```
4. **Update both READMEs** if your change affects user-facing behavior (both `README.md` and `README.zh-TW.md`)
5. **Keep CI green** — ShellCheck and smoke tests must pass

### Review Process

- PRs are reviewed by the maintainer
- Expect feedback on Bash compatibility, error handling, and prompt quality
- For significant changes, we may run the modified commands through `/pi-multi-review` before merging

## Reporting Issues

### Bug Reports

Please include:

- **What happened** vs. what you expected
- **Steps to reproduce** (the exact command you ran)
- **Environment**: OS, Bash version (`bash --version`), CLI versions
- **Logs**: relevant lines from `~/.claude/logs/multi-ai.log` (timestamps and byte lengths only, no sensitive content)

### Feature Requests

We welcome ideas! Before opening an issue:

- Check if it aligns with the project's scope (cross-provider orchestration for Claude Code)
- Explain the **use case**, not just the feature — *why* do you need this?

## What We Look For

- Bug fixes with clear reproduction steps
- New provider integrations (following existing `call-*.sh` patterns)
- Improvements to command prompts (better accuracy, fewer false positives)
- Test coverage improvements
- Documentation fixes and translations

## What We Don't Accept

- **Breaking Bash 3.2 compatibility** — macOS users are first-class citizens
- **Adding compile-time dependencies** — claude-prism is zero-compile-dependency by design
- **Hosted services or relay servers** — we are local-first, no intermediary
- **Telemetry or analytics** — no phone-home, no tracking
- **`postinstall` scripts in npm** — see [Supply Chain Security](README.md#supply-chain-security)

---

Thank you for helping make cross-provider AI review better for everyone!
