---
command: pi-fact-check
description: "Fact-check content via Gemini search + Claude verification — cross-provider claim validation"
---

# Fact-Check via Cross-Provider Verification

Verify factual claims using Gemini (Google search) for source discovery and Claude for cross-verification. **Two providers, two roles: Gemini finds evidence, Claude judges it.**

## Execution

### 1. Obtain content

Use `$ARGUMENTS` as the content to verify.

- **File path**: Read the file and use its content
- **URL**: Fetch with WebFetch
- **Conversation reference**: Claude extracts relevant content from history
- **Inline text**: Use directly
- **Empty**: Ask what to fact-check

### 2. Extract claims (Claude)

Scan the content. Identify every factual claim — statements that can be verified against external sources (data, events, quotes, attributions).

Skip opinions, predictions, and vague assertions ("many believe...").

For each claim, assess: **how important is it if this is wrong?** Focus effort on high-impact claims. Flag anything suspicious — too-precise numbers, vague sourcing, absolute language.

Output a numbered list of claims to verify, each with the exact text and suggested search terms.

If no verifiable claims found, report and stop.

### 3. Source search (Gemini)

Bundle all claims into a single Gemini call (split if >12,000 chars):

```bash
echo "$CLAIMS_PROMPT" | timeout 90 ~/.claude/scripts/call-gemini.sh "fact-check source search"
```

Prompt sent via stdin:

```
Fact-check these claims. For each, find the closest primary source.

CLAIMS:
$NUMBERED_CLAIMS_LIST

For each claim, return:
1. Verdict: SUPPORTED / CONTRADICTED / UNVERIFIABLE
2. Best source found (prefer: official records > peer-reviewed > major media > other)
3. Source URL
4. Key finding (one sentence)
5. Source date
6. Any contradicting evidence

Prioritize primary sources. Search both English and Chinese for international topics. Look for BOTH supporting and contradicting evidence. When available, search for adversarial sources (court filings, regulatory actions, competitor analyses) — facts confirmed under hostile scrutiny are strongest.

Return numbered list matching input. No editorializing.
```

**Fallback** (if Gemini fails):
1. WebSearch per claim. Note degradation.
2. Claude's training data only. Note degradation.

**Never abort.** Always produce a report.

### 4. Cross-verification (Claude)

This is where cross-provider adds value. Claude independently evaluates Gemini's findings — not re-searching, but applying judgment Gemini cannot:

**Source quality** — Is the cited source actually authoritative? A blog post cited as "official report" gets downgraded.

**Knowledge cross-check** — Does Claude's training data agree or conflict with Gemini's finding?

**Internal consistency** — Do independently verified claims contradict each other?

**Precision check** — Is the claim wrong, or just imprecise? ("47% market share" reported as "about half" is imprecise, not incorrect.)

**Adversarial evidence** — Can the claim be confirmed through its opponents? Court rulings, regulatory filings, or competitor analyses that implicitly acknowledge a fact are high-confidence signals — they've survived hostile scrutiny.

Assign final verdict per claim:

| Verdict | Meaning |
|---------|---------|
| ✅ Verified | Reliable source confirms the claim |
| ⚠️ Imprecise | Core idea correct, details off |
| ❌ Incorrect | Reliable source directly contradicts |
| ❓ Unverifiable | No reliable source found either way |

Single-source claims: note "single source" regardless of verdict.

### 5. Report

```markdown
## Fact-Check Report

**X claims checked** · ✅ X verified · ⚠️ X imprecise · ❌ X incorrect · ❓ X unverifiable

### Results

| # | Claim | Verdict | Source | Notes |
|---|-------|---------|--------|-------|

### Issues

(Detail each ⚠️/❌/❓ claim)

#### [verdict] #N: "[claim]"
- **Source**: [what Gemini found]
- **Analysis**: [Claude's cross-verification]
- **Fix**: [suggested correction]

### Sources

| # | Source | URL | Date |
|---|--------|-----|------|

### Confidence
- X/Y claims backed by primary sources
- X/Y claims have 2+ independent sources
- Gaps: [areas where search was insufficient]
```

### 6. Save (optional)

Ask: **"Save the report?"** If yes, save to `.claude/pi-fact-check/<slug>.md`.

### Notes

- **No Codex** — fact-checking needs search, not more LLM opinions. For opinion-based review, use `/pi-multi-review`
- Keep Gemini input under 12,000 chars
- Works with any language
