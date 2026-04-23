# CI/CD Integration

Automate multi-provider reviews on every PR via GitHub Actions. The CI path uses REST APIs directly (no CLI installation needed on runners).

[繁體中文](ci-cd.zh-TW.md) · [← Back to README](../README.md)

---

## Quick Setup

1. Copy the workflow file to your project:

```bash
mkdir -p .github/workflows
cp path/to/claude-prism/.github/workflows/ai-review.yml .github/workflows/
cp path/to/claude-prism/scripts/ci-review.sh scripts/
```

2. Add API keys as GitHub Secrets (at least one required):

| Secret | Provider | Required? |
|--------|----------|-----------|
| `GEMINI_API_KEY` | Gemini review | Optional |
| `OPENAI_API_KEY` | OpenAI review | Optional |
| `ANTHROPIC_API_KEY` | Claude synthesis | Optional |

3. Add the `ai-review` label to a PR to trigger the review.

## Trigger Modes

**Label trigger (default):** Add `ai-review` label to a PR → workflow runs. Best for cost control.

**Auto trigger:** Uncomment the `pull_request: [opened, synchronize]` block in the workflow file → runs on every PR update.

## How It Works (CI)

1. GitHub Actions checks out the PR and fetches the diff
2. `ci-review.sh` auto-discovers `CLAUDE.md` / `Agents.md` for guideline context
3. Historical PR comments on the same files are queried via GraphQL (single API call) and included as recurring-issue context
4. Diff is sent to available providers (Gemini API, OpenAI API) in parallel, with inline annotation compliance checks and false-positive exclusion rules
5. If `ANTHROPIC_API_KEY` is set, Claude synthesizes with confidence scoring (only issues ≥ 80 posted)
6. If not, results are concatenated directly
7. If the review includes concrete code fixes, they are posted as **inline PR review comments** with GitHub suggestion blocks (one-click accept). Remaining output is posted as the review body. Falls back to a regular PR comment if the Reviews API is unavailable

## CI Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `GEMINI_MODEL` | `gemini-2.0-flash` | Gemini model for CI review |
| `OPENAI_MODEL` | `gpt-4o` | OpenAI model for CI review |
| `ANTHROPIC_MODEL` | `claude-sonnet-4-20250514` | Claude model for synthesis |
| `MAX_DIFF_CHARS` | `32000` | Diff truncation limit |

## Security Notes

- **Fork PRs**: The workflow uses `pull_request` (not `pull_request_target`), so fork PRs cannot access your secrets. This is intentional — fork PRs are skipped.
- **API keys**: Use GitHub repository secrets. Never commit API keys to the repo.
- **Concurrency**: Only one review runs per PR at a time; new pushes cancel in-progress reviews.
- **Checksums**: `checksums.sha256` verifies file integrity against transit corruption or accidental modification. It does **not** protect against a compromised repository — for that, verify against the GitHub Release artifacts page.

## CLI Version Compatibility

The wrapper scripts depend on specific CLI behaviors that are not part of official stable APIs:

| CLI | Behavior Used | Verified Range |
|-----|---------------|----------------|
| Gemini CLI | `-p " "` headless mode (stdin + prompt) | v0.1.x – v0.3.x |
| Codex CLI | `codex exec - ` stdin mode | v0.100.x – v0.106.x |

If a CLI update breaks functionality, pin the working version or open an issue. For the March 25, 2026 Gemini service update, see the notice in the main README's Prerequisites section.
