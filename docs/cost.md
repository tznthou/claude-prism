# Cost Estimation

claude-prism is a local wrapper — it does not process or bill tokens itself. Each command may trigger one or more API calls to external providers (Codex, Gemini) via their CLIs. Claude Code's own orchestration tokens (reading files, building prompts, synthesizing results) are separate and covered by your Claude subscription or API plan.

[繁體中文](cost.zh-TW.md) · [← Back to README](../README.md)

---

## Token Consumption by Command

| Command | External Calls | Typical Input Tokens | Typical Output Tokens | Notes |
|---------|---------------|---------------------|----------------------|-------|
| `/pi-ask-codex` | 1 (Codex) | 500–2K | 500–2K | Scales with question complexity |
| `/pi-ask-gemini` | 1 (Gemini) | 500–2K | 500–2K | Scales with question complexity |
| `/pi-askall` | 2 (Codex + Gemini) | 500–2K each | 500–2K each | Both providers called in parallel |
| `/pi-fact-check` | 1 (Gemini) + N (WebSearch) | 1K–5K | 2K–8K | Scales with number of claims; WebSearch runs in parallel |
| `/pi-code-review` | 1 (Codex) | 2K–10K | 1K–4K | Scales with diff size |
| `/pi-ui-review` | 1 (Gemini) | 2K–10K | 1K–4K | Scales with file count |
| `/pi-ui-design` | 1 (Gemini) | 1K–3K | 3K–8K | Output-heavy (HTML generation) |
| `/pi-research` | 1 (Gemini) + 2–4 (WebSearch) | 1K–5K | 2K–8K | Dual-track search; scales with topic complexity |
| `/pi-multi-review` | 2 (Codex + Gemini) | Above ×2 | Above ×2 | Both providers called in parallel |
| `/pi-plan` | 0–2 (optional) | 1K–5K each | 1K–4K each | Providers consulted only if available |

Token ranges are approximate and vary with input size (diff length, file count, question complexity). Different providers use different tokenization methods — these figures are order-of-magnitude estimates, not billing-accurate counts.

## Controlling Costs

- **`--dry-run`** — test the request path without calling the provider (no tokens consumed)
- **`usage-summary.sh`** — review historical call counts and rough token volume:
  ```bash
  ~/.claude/scripts/usage-summary.sh --week
  ```
- **Provider pricing** — check current rates at your provider's pricing page:
  - [OpenAI API Pricing](https://openai.com/api/pricing/)
  - [Google AI Pricing](https://ai.google.dev/pricing)
