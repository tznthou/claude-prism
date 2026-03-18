---
command: pi-fact-check
description: "Fact-check content via Gemini search + Claude verification — cross-provider claim validation"
---

# Fact-Check via Cross-Provider Verification

Verify factual claims using Gemini (Google search) for source discovery and Claude for analytical verification. **Evidence-based task — Gemini searches for sources, Claude validates against them.**

## Execution

### 1. Obtain content to fact-check

`$ARGUMENTS` is the content or reference to fact-check.

**If `$ARGUMENTS` is inline text**: use it directly as the content to verify.

**If `$ARGUMENTS` references a file path** (e.g., `article.md`, `./draft.txt`):
- Read the file with the Read tool
- Use the file content as the material to fact-check

**If `$ARGUMENTS` references conversation context** (e.g., "the article we just discussed"):
- Claude extracts the relevant content from conversation history

**If `$ARGUMENTS` is a URL**:
- Fetch the content with WebFetch
- Use the fetched content as material

**If `$ARGUMENTS` is empty**, ask: "What content should I fact-check? Paste text, give a file path, or reference something from our conversation."

### 2. Phase 1 — Extract and classify claims (Claude)

Scan the content and extract ALL factual claims. For each claim:

**Classify**:
- ✅ **Verifiable**: factual statements, data citations, historical events, quotes
- ❌ **Not verifiable**: opinions, predictions, subjective feelings, vague assertions ("many people believe...")

**Prioritize** using the impact × suspicion matrix:

|  | High suspicion | Low suspicion |
|--|----------------|---------------|
| **High impact** | 🔴 Must verify | 🟡 Should verify |
| **Low impact** | 🟡 Should verify | 🟢 Optional |

**Suspicion red flags** 🚩:
- Numbers too precise or too round ("exactly 1 million")
- Vague attribution ("studies show", "experts say")
- Conflicts with common knowledge
- Absolute language ("only", "first ever", "never")
- Multi-hop retelling (3+ hand sources)

Output a numbered list of verifiable claims (🔴 and 🟡 only), each with:
- The exact claim text
- Claim type: data / quote / event
- Suggested search keywords (English AND Chinese if international topic)

If **zero verifiable claims** are found, report "No verifiable factual claims found in the provided content" and stop — do not proceed to Phase 2.

### 3. Phase 2 — Source search (Gemini)

Bundle all claims from Phase 1 into a single Gemini call. If the claims list exceeds 12,000 chars, split into multiple calls.

```bash
echo "$CLAIMS_PROMPT" | timeout 90 ~/.claude/scripts/call-gemini.sh "fact-check source search"
```

The `$CLAIMS_PROMPT` sent via stdin:

```
You are a fact-checking research assistant. Find primary sources to verify or refute these claims.

CLAIMS:
$NUMBERED_CLAIMS_LIST

FOR EACH CLAIM, provide:
1. Verdict: SUPPORTED / CONTRADICTED / UNVERIFIABLE
2. Primary source found (official report, financial filing, court document, peer-reviewed paper)
3. Source URL
4. Source tier: T1 (official primary) / T2 (peer-reviewed) / T3 (major media) / T4 (industry report) / T5 (general media) / T6 (social/blog — unreliable)
5. Key finding (one sentence)
6. Source date
7. Contradicting evidence (if any)

SEARCH STRATEGY:
- Search BOTH English AND Chinese for international topics
- Prioritize primary sources over media coverage
- Find BOTH supporting AND contradicting evidence
- For numbers: find the ORIGINAL data source
- For quotes: find the ORIGINAL speech/interview/document

Return a numbered list matching the input claims. Report only what sources say — no editorializing.
```

**Timeout and fallback**:

If Gemini fails (timeout after 90s, CLI not found, or non-zero exit):
1. **First fallback**: Use WebSearch to search for each claim individually. Note in output: "Gemini unavailable — sources found via WebSearch (reduced depth)."
2. **Second fallback**: If WebSearch also fails, use Claude's training data. Note: "No external search available — verification based on Claude's knowledge only (lower confidence)."

**Never abort.** Always produce a report, with degradation clearly labeled.

### 4. Phase 3 — Cross-verification (Claude)

Claude adds what Gemini cannot: analytical judgment, inconsistency detection, and training-data cross-reference. Do NOT re-search — work from Gemini's results.

For each claim, map Gemini's verdict to the final verdict:

| Gemini says | Claude assigns | When |
|-------------|---------------|------|
| SUPPORTED | ✅ Verified | Source is T1-T3 and matches claim |
| SUPPORTED | ⚠️ Partially verified | Source supports the gist but details differ |
| CONTRADICTED | ❌ Incorrect | T1-T3 source directly conflicts |
| CONTRADICTED | ⚠️ Partially verified | Contradiction is minor (rounding, date range) |
| UNVERIFIABLE | ❓ Unverifiable | No reliable source found |
| UNVERIFIABLE | 🔍 Needs further checking | Claim is important, may need domain expertise |

**Claude's unique checks** (what Gemini can't do):
- Does Gemini's cited source tier match the actual source? (e.g., claimed T1 but it's actually a blog)
- Does Claude's training data contradict Gemini's finding?
- Are there logical inconsistencies between claims that Gemini verified independently?
- Single-source claims: label "single source, pending further verification"
- Distinguish "factual error" from "imprecise wording" — do NOT treat "unverifiable" as "incorrect"

### 5. Phase 4 — Report

Output the structured report in this format:

```markdown
## 核查報告

### 總覽
- 總聲明：X 條 | 可核查：X 條 | 已核查：X 條
- ✅ 已驗證：X | ⚠️ 部分驗證：X | ❓ 無法驗證：X | ❌ 有誤：X

### 核查結果

| # | 聲明 | 結果 | 來源層級 | 說明 |
|---|------|------|----------|------|

### 問題聲明詳析

(Expand ONLY ⚠️/❓/❌/🔍 claims with full evidence chain)

#### ⚠️ #N："[claim text]"
- **Gemini 搜尋結果**：[source and finding]
- **Claude 驗證**：[analysis]
- **建議修改**：[suggested fix]

### 未核查聲明
(Low-priority or not-verifiable claims, with classification reason)

### 來源清單

| # | 來源 | 層級 | URL | 日期 |
|---|------|------|-----|------|

### 核查品質自評
- 來源覆蓋度：X/Y 聲明有 T1-T3 來源
- 三角驗證率：X/Y 聲明有 ≥2 獨立來源
- 搜尋盲區：[areas where search was insufficient]
- 降級說明：[if Gemini was unavailable, note fallback used]
```

### 6. Save results (optional)

After presenting the report, ask: **"Save the fact-check report?"**

If yes, save to `.claude/pi-fact-check/<slug>.md` with a metadata header:

```markdown
# Fact-Check: <topic>
- **Date**: <ISO 8601>
- **Source**: <gemini+claude | websearch+claude | claude-only>
- **Content**: <file path, URL, or "inline">
```

Create the directory if it doesn't exist.

### Notes

- **Evidence-based task** — value comes from independent sources, not LLM opinions. No Codex (no web search = no verification value). For opinion-based review, use `/pi-multi-review`
- Keep content sent to Gemini under 12,000 chars — summarize longer texts but preserve all factual claims verbatim
- Works with any language; search strategy adapts to topic language
- Pairs well with TZ-writer → TZ-editor → `/pi-fact-check` workflow
