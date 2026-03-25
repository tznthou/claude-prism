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

### 3. Source search (dual-track)

Launch **both tracks simultaneously** in a single response to eliminate dead-wait time:

```
                    ┌─ Track A: Gemini (search grounding) ─┐
  Claims ──split──→│                                       │──merge──→ Step 4
                    └─ Track B: WebSearch (reliable URLs)  ─┘
```

#### Track A — Gemini

Split claims into batches of **max 2 claims** each. Each batch call uses the Bash tool's timeout parameter (90 seconds):

```bash
# Use Bash tool with timeout: 90000
echo "$BATCH_PROMPT" | ~/.claude/scripts/call-gemini.sh "fact-check batch N"
```

Prompt sent via stdin. **Preserve original claim numbers** — if a batch contains claims #4, #5, Gemini must return results numbered 4, 5 (not 1, 2):

```
Fact-check these claims. For each, find supporting and contradicting sources.

CLAIMS:
$NUMBERED_CLAIMS_IN_THIS_BATCH

For each claim, return:
1. Verdict: SUPPORTED / CONTRADICTED / UNVERIFIABLE
2. Sources found (list ALL relevant sources, not just the best one; prefer: official records > peer-reviewed > major media > other)
3. Source URLs (one per line)
4. Key finding per source (one sentence each)
5. Source dates
6. Any contradicting evidence with its own source URL

Prioritize primary sources. Search both English and Chinese for international topics. Look for BOTH supporting and contradicting evidence. When available, search for adversarial sources (court filings, regulatory actions, competitor analyses) — facts confirmed under hostile scrutiny are strongest.

Return numbered list matching input. No editorializing.
```

#### Track B — WebSearch

One WebSearch call per claim, all in parallel. Use the suggested search terms from Step 2 as query.

#### Merge rules

For each claim, merge sources from both tracks. If one track fails (timeout, auth, quota, CLI not found, non-zero exit), use the other. If both fail, fall back to Claude's training data and note the degradation.

- Collapse same-editorial-chain sources (e.g., AP wire republished by 5 outlets = 1 independent source, not 5) — this affects convergence counting in Step 5
- When Gemini and WebSearch URLs conflict, prefer WebSearch (lower hallucination risk)

**Never abort.** Always produce a report, even if both tracks fail for some claims.

### 4. Cross-verification (Claude)

This is where cross-provider adds value. Claude independently evaluates the merged search results (from Gemini and/or WebSearch) — not re-searching, but applying judgment the search tools cannot:

**Source quality** — Is the cited source actually authoritative? A blog post cited as "official report" gets downgraded.

**Knowledge cross-check** — Does Claude's training data agree or conflict with the search findings?

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

### 4.5 Source validation

Sample URLs from search results for existence and content verification. Focus on **Gemini-sourced URLs** (higher hallucination risk) and any unrecognized domains. WebSearch URLs from major outlets (CNN, Bloomberg, etc.) can be trusted without verification. **Prioritize ✅ verdict claims with high impact** — these are the ones readers will cite and click.

**Sampling rules (cap: ~8 URLs per run):**
- Priority 1: ❌ claims — verify contradicting sources (catching false contradictions is highest value)
- Priority 2: ✅ high-impact claims — verify their primary URL (these get cited by readers)
- Priority 3: ⚠️ claims with Gemini-only sources — spot-check for hallucination
- Skip: ❓ (no URL to verify), WebSearch URLs from major outlets (already reliable)
- If eligible URLs exceed cap, stop at the cap — lower-priority URLs appear as `(unverified)`

**For each sampled URL:**

1. **WebFetch** the URL
2. **Validation failure** — any of: unreachable/4xx/5xx, content doesn't match the claimed finding, or URL is obviously fabricated → mark source as `(unverified)`, do NOT use as evidence, downgrade the claim's verdict one level (✅→⚠️, ⚠️→❓, ❌→❓), and note the reason

**Batch failure threshold:** If >50% of sampled URLs fail (4xx/5xx, fabricated, or content mismatch):
- Mark ALL Gemini-sourced claims (including unsampled) as `(unverified)` in the report
- Re-search **all** claims via WebSearch (not just the failed ones — the high failure rate indicates systemic hallucination)
- Replace Gemini URLs with WebSearch results in the final report
- Note in the report: `⚠️ Gemini source validation: X/Y URLs failed. Full WebSearch fallback triggered.`

**URLs not sampled** (skipped due to cap or low priority) must appear with `(unverified)` in the Sources table.

### 5. Report

> Fact-check aims for transparency, not authority. The report shows what evidence exists and where gaps remain — the reader decides.

#### Source tier reference

| Tier | Type | Examples |
|------|------|----------|
| L1 | Official records | IR reports, SEC filings, official announcements |
| L2 | Adversarial sources | Court rulings, regulatory actions, competitor analyses |
| L3 | Major media | Bloomberg, Reuters, WSJ, CNN (editorial review process) |
| L4 | Industry analysis | Named analyst reports (Goldman Sachs, Cantor Fitzgerald) |
| L5 | Tech media | TechCrunch, The Verge, Ars Technica |
| L6 | Community/blogs | Medium, Substack, Reddit (signal, not evidence) |

An L1 single source outweighs three L6 sources citing each other.

#### Convergence-based confidence

| Marker | Condition |
|--------|-----------|
| 🟢 High | 3+ independent sources (different outlets/authors) converge on the same conclusion |
| 🟡 Medium | 2 independent sources agree |
| 🟠 Single source | Only 1 source, or multiple sources that trace back to the same origin |
| 🔴 Conflicting | Sources directly contradict each other |

"Independent" means different editorial chains. Three articles all citing the same Reuters wire count as 🟠, not 🟢.

#### Report format

```markdown
## Fact-Check Report

**X claims checked** · ✅ X verified · ⚠️ X imprecise · ❌ X incorrect · ❓ X unverifiable

### Results

| # | Claim | Verdict | Confidence | Source tier | Notes |
|---|-------|---------|------------|-------------|-------|
| 1 | ... | ✅ | 🟢 3 sources | L3+L4 | ... |
| 2 | ... | ⚠️ | 🟠 single source | L6 | ... |
| 3 | ... | ❌ | 🔴 conflicting | L3 vs L5 | ... |

### Issues

(Detail each ⚠️/❌/❓ claim)

#### [verdict] #N: "[claim]"
- **Source**: [what search found — note which track: Gemini / WebSearch / both]
- **Analysis**: [Claude's cross-verification]
- **Convergence**: [how many independent sources, what tiers, any same-origin chains detected]
- **Fix**: [suggested correction]

### Sources

| # | Source | Tier | URL | Verified | Date |
|---|--------|------|-----|----------|------|

### Confidence Summary

- **Strong claims** (🟢): X/Y — backed by 3+ independent sources
- **Adequate claims** (🟡): X/Y — 2 independent sources
- **Weak claims** (🟠): X/Y — single source or same-origin chain
- **Disputed claims** (🔴): X/Y — sources contradict
- **Highest tier reached**: LN ([type])
- **Gaps**: [topics where only L5-L6 sources were found, or no sources at all]
```

### 6. Save (optional)

Ask: **"Save the report?"** If yes, save to `.claude/pi-fact-check/<slug>.md`.

### Notes

- **No Codex** — fact-checking needs search, not more LLM opinions. For opinion-based review, use `/pi-multi-review`
- Gemini batches auto-split at 2 claims each (search grounding serializes internally — small batches finish faster). If a single batch exceeds ~10,000 chars, split further
- Works with any language
