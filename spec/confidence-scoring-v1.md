# AI Code Review Confidence Scoring Framework v1.0

> **Status**: Draft
> **Authors**: claude-prism contributors
> **License**: MIT
> **Date**: 2026-03-09

---

## Abstract

AI code review tools generate a mix of actionable findings and noise. This document defines an **evidence-based scoring framework** that assigns a 0–100 confidence score to each issue raised by an AI reviewer. The goal is noise filtering: separating findings worth a developer's attention from false positives, stale observations, and subjective preferences.

The framework is deterministic, model-agnostic, and tool-agnostic. It can be applied as a post-processing layer on top of any AI code review tool's output.

---

## 1. Problem Statement

AI code review tools have a noise problem. Studies and industry reports consistently show:

- Developers ignore 40–70% of AI-generated review comments (CodeRabbit, Greptile benchmarks)
- Every vendor benchmarks itself and wins — there is no shared standard for measuring review quality ([DeepSource, 2025](https://deepsource.com/blog/notes-on-ai-code-review-benchmarks))
- Existing benchmarks focus on **recall** (did the tool find the bug?) but largely ignore **precision** (was the comment worth reading?)

The core issue: most AI reviewers optimize for coverage, not signal. They flag everything that *might* be wrong, leaving developers to sort signal from noise. This erodes trust and leads to "comment fatigue" — developers stop reading AI reviews entirely.

**This framework addresses precision, not recall.** It does not help tools find more bugs. It helps developers spend less time on comments that don't matter.

---

## 2. Design Principles

### 2.1 Evidence-based, not opinion-based

Scoring is determined by observable properties of the issue (does it cite a line number? does it reference a rule?), not by whether a reviewer "agrees" with the finding. A well-evidenced issue scores high even if the scoring system's operator disagrees with it.

**Rationale**: Opinion-based filtering reintroduces the single-reviewer blind spot that multi-provider review is designed to eliminate.

### 2.2 Deterministic core

The core scoring model (§3–4) is deterministic: given the same issue description and context, the score is always the same. No LLM-as-judge, no probabilistic matching. A human can compute the score by hand.

Extensions (§5) MAY introduce non-deterministic operations (e.g., semantic matching for consensus detection). When they do, this is explicitly noted. The core framework remains deterministic regardless of which extensions are active.

**Rationale**: LLM judges introduce variance and self-referential bias (§2.4 of [Martian Code Review Bench methodology](https://github.com/withmartian/code-review-benchmark)). Deterministic scoring is reproducible and auditable.

### 2.3 Model-agnostic and tool-agnostic

The framework works on any AI code review output that produces structured or semi-structured issue descriptions. It does not depend on a specific model, provider, or tool.

### 2.4 Conservative filtering

The framework is designed to filter out obvious noise, not to aggressively prune. False negatives (filtering out a real issue) are worse than false positives (letting noise through). The default threshold reflects this bias.

---

## 3. Scoring Model

### 3.1 Base Score

Every issue starts at **40** (slightly below midpoint).

### 3.2 Positive Factors (evidence of actionability)

| Factor | Impact | Rationale |
|--------|--------|-----------|
| References specific line numbers in the diff | **+25** | Localized issues are verifiable and actionable |
| Issue concerns code **introduced in this diff** | **+25** | New code is the PR author's responsibility; pre-existing issues are out of scope |
| Cites a concrete rule (OWASP, language spec, project guideline, linter rule) | **+20** | Rule-backed findings are objective and verifiable |
| Describes a reproducible scenario (steps, input, expected vs actual outcome) | **+15** | Reproducibility is the strongest evidence of a real bug |
| Multiple independent reviewers flagged the same issue | **+20** | Consensus among independent sources is a strong quality signal |

### 3.3 Negative Factors (evidence of noise)

| Factor | Impact | Rationale |
|--------|--------|-----------|
| Issue **solely** concerns code the diff removes, **with no impact on remaining code** | **-30** | Commenting on deleted code with no surviving effect is noise. Note: findings about risks introduced by a refactor or incomplete deletion are NOT penalized — only comments purely about removed code with no downstream impact. |
| Issue is something a linter or formatter would catch (and the project has such tooling configured) | **-25** | Linter-level issues should be caught by CI, not code review. If the project lacks linter enforcement, this factor does not apply. |
| Issue is a subjective style preference with no guideline backing | **-25** | Style debates without authority are noise in a code review context. Distinguish from: readability concerns backed by language idioms, maintainability issues with concrete impact, or team conventions documented in project files. |
| Issue references a file, symbol, or API that **does not exist** in the codebase | **-50** | Hallucinated references are the strongest noise signal. |

### 3.4 Calculation

```
score = clamp(40 + sum(applicable_factors), 0, 100)
```

- Factors are additive. Multiple positive factors can stack.
- The score is clamped to the [0, 100] range.
- Each factor is binary: it either applies or it doesn't. There are no partial weights. When evidence is ambiguous (e.g., "partially references a line number"), treat the factor as **not applicable**. Partial evidence does not earn partial credit.

### 3.5 Examples

**Example A — High confidence (score: 100)**

> "Line 42: `user_input` is interpolated directly into the SQL query without parameterization. This is a SQL injection vulnerability (OWASP A03:2021). An attacker could pass `'; DROP TABLE users; --` as input."

| Factor | Applies? | Impact |
|--------|----------|--------|
| References line numbers | Yes | +25 |
| New code in this diff | Yes | +25 |
| Cites rule (OWASP) | Yes | +20 |
| Reproducible scenario | Yes | +15 |
| Consensus | No | — |
| Removed code | No | — |
| Linter-catchable | No | — |
| Subjective style | No | — |
| Hallucinated reference | No | — |

Score: 40 + 25 + 25 + 20 + 15 = **125 → clamped to 100**

This is the ideal case: localized, new code, rule-backed, reproducible.

**Example B — Noise (score: 0)**

> "Consider using `const` instead of `let` for variables that aren't reassigned."

| Factor | Applies? | Impact |
|--------|----------|--------|
| References line numbers | No | — |
| New code in this diff | Unknown → treat as absent | — |
| Cites rule | No | — |
| Reproducible scenario | No | — |
| Consensus | No | — |
| Removed code | No | — |
| Linter-catchable | Yes (ESLint `prefer-const`) | -25 |
| Subjective style | Yes | -25 |
| Hallucinated reference | No | — |

Score: 40 - 25 - 25 = **0 → clamped to 0**

Note: If the project does not have ESLint configured, the linter-catchable factor would not apply, and the score would be 40 - 25 = **15** (still filtered).

**Example C — Borderline (score: 90)**

> "Line 15 of `api.ts`: the `fetchData` function doesn't handle HTTP 429. Under rate limiting, this silently returns `undefined` instead of retrying or throwing."

| Factor | Applies? | Impact |
|--------|----------|--------|
| References line numbers | Yes | +25 |
| New code in this diff | Yes | +25 |
| Cites rule | No | — |
| Reproducible scenario | No (describes consequence but no steps/input) | — |
| Consensus | No | — |

Score: 40 + 25 + 25 = **90**

This passes the default threshold (≥ 80) based on localization and newness alone. Without a rule citation or reproducible scenario, it scores 90 rather than 100 — the framework correctly ranks it below Example A.

**Example D — Hallucination (score: 0)**

> "The `validateUser()` function in `auth/permissions.ts` has a race condition when checking concurrent sessions."

But `auth/permissions.ts` does not exist in the codebase, and there is no `validateUser()` function.

| Factor | Applies? | Impact |
|--------|----------|--------|
| References line numbers | No | — |
| Hallucinated reference | Yes | -50 |

Score: 40 - 50 = **-10 → clamped to 0**

**Example E — Localized noise (score: 65, filtered)**

> "Line 8: consider renaming `data` to `userData` for clarity."

| Factor | Applies? | Impact |
|--------|----------|--------|
| References line numbers | Yes | +25 |
| New code in this diff | Yes | +25 |
| Subjective style | Yes (naming preference, no guideline) | -25 |

Score: 40 + 25 + 25 - 25 = **65**

This is a localized, new-code comment — but it's a subjective naming preference. The -25 penalty pulls it below the default threshold of 80. **This is the framework's key value proposition**: filtering noise even when the comment correctly identifies the right location.

---

## 4. Threshold

### 4.1 Default Threshold

**≥ 80 = actionable** — include in review output.
**< 80 = filtered** — omit by default, optionally available in verbose mode.

### 4.2 Rationale

An issue that references specific lines in newly introduced code scores 40 + 25 + 25 = **90**, which passes. An issue with no localization and no evidence scores **40**, which does not pass. A localized new-code comment that is also a subjective style preference scores 40 + 25 + 25 - 25 = **65**, which is filtered.

The threshold is set so that:
- Localized + new-code issues pass by default (developers should see these)
- Localized + new-code + noise-signal issues are filtered (the framework's primary value)
- Unlocalized issues need strong evidence (rule citation, consensus) to pass

**Important**: Confidence is not priority. A score of 95 does not mean "fix this before the 85." Confidence measures evidence quality, not issue severity. Implementations should use a separate severity dimension for prioritization.

### 4.3 Customization

Implementations MAY allow users to adjust the threshold:

- **Strict (≥ 90)**: Only issues with multiple evidence signals. Minimizes noise at the cost of potentially missing some real issues.
- **Default (≥ 80)**: Balanced filtering.
- **Lenient (≥ 60)**: Includes more borderline issues. Appropriate when thoroughness is more important than developer time.

---

## 5. Extensions

The core framework (§3–4) is intentionally minimal. Implementations MAY add the following extensions.

### 5.1 Guideline Compliance Scoring

When project-specific guidelines are available (e.g., `CLAUDE.md`, `agents.md`, `.eslintrc`, style guides):

| Factor | Impact |
|--------|--------|
| Violation explicitly mentioned in guideline text | +30 |
| Violation inferred but not explicitly stated | +10 |

Only apply when the issue references a **specific rule** from a guideline file.

**No double-dip**: If an issue already received +20 from "Cites a concrete rule" (§3.2) for the same guideline citation, do not apply both. Use the **higher** of the two bonuses (+30 for explicit guideline match), not their sum.

### 5.2 Multi-Provider Consensus Weighting

When multiple independent AI reviewers evaluate the same code:

- Two or more reviewers flag the same issue → apply the +20 consensus factor
- Issues flagged by only one reviewer → no bonus, but not penalized

**"Same issue" matching**: Two findings match if they describe the same underlying problem, regardless of wording. Semantic matching is acceptable; exact string matching is too strict.

**Note on determinism**: Consensus detection inherently requires semantic comparison, which is non-deterministic. Implementations using this extension should document their matching strategy (e.g., LLM-assisted, embedding similarity, keyword overlap). The core score calculation remains deterministic; only the consensus factor's applicability depends on the matching implementation.

**Independence requirement**: "Multiple reviewers" means distinct models or providers. Multiple runs of the same model with different prompts do not count as independent consensus.

### 5.3 Domain-Aware Authority

When the reviewer's domain expertise is known:

- A frontend-specialized reviewer's UI/accessibility finding carries more weight than a backend-specialized reviewer's
- A security-focused reviewer's OWASP finding carries more weight than a general-purpose reviewer's

**Implementation note**: Domain authority affects synthesis priority, not score calculation. It should not cause findings to be discarded.

---

## 6. Non-Goals

This framework explicitly does **not** address:

- **Recall**: Whether the reviewer found all bugs. That is a separate problem (see [Martian Code Review Bench](https://github.com/withmartian/code-review-benchmark) for recall-focused evaluation).
- **Fix quality**: Whether the suggested fix is correct.
- **Severity ranking**: How critical the issue is. A high-confidence low-severity issue (e.g., a confirmed minor style violation against a guideline) is still high confidence.
- **Review tone or explanation quality**: Whether the comment is well-written.

---

## 7. Comparison with Existing Approaches

| Approach | Method | Deterministic? | Problem |
|----------|--------|---------------|---------|
| **LLM-as-judge** (Martian, academic) | Another LLM decides if a comment is valid | No | Judge variance, self-referential bias, not reproducible |
| **Developer action rate** (CodeRabbit) | Track whether developers act on comments | N/A | Compliance bias — developers may fix things just to clear bot comments |
| **Human annotation** | Experts manually label each comment | Yes (per annotator) | Expensive, doesn't scale, inter-annotator disagreement |
| **This framework** | Evidence-based factor scoring | **Yes** | Cannot catch issues that are poorly described but substantively correct |

---

## 8. Limitations

1. **Penalizes poorly written findings**: A real bug described vaguely ("something might be wrong here") scores low. The framework measures evidence quality, not issue validity.

2. **Factors are not empirically calibrated**: The weights (+25, +20, etc.) are based on design judgment, not statistical analysis. Future versions should calibrate against developer action data.

3. **Binary factor application**: Each factor is all-or-nothing. "Partially references a line number" is not handled. This is a deliberate simplicity trade-off.

4. **No learning**: The framework is static. It does not adapt to project-specific patterns or individual developer preferences.

5. **Cross-file findings**: Issues about interactions between newly added code and pre-existing code in other files are hard to score — they may lack line numbers in the diff yet be substantively valid.

6. **Absence-based findings**: Comments like "missing auth check" or "no test coverage" identify the absence of code rather than the presence of a bug. These lack localization by nature and will score lower than they deserve.

7. **Hallucination detection requires codebase access**: The hallucination factor (-50) assumes the scorer can verify whether referenced symbols exist. Implementations without codebase access cannot apply this factor.

---

## 9. Input Schema

To score an issue deterministically, implementations need the following minimum input per issue:

```json
{
  "description": "string — the reviewer's comment text",
  "line_numbers": [42],
  "is_new_code": true,
  "rule_citation": "OWASP A03:2021",
  "has_reproduction": true,
  "references_removed_code_only": false,
  "is_linter_catchable": false,
  "project_has_linter": true,
  "is_subjective_style": false,
  "references_exist_in_codebase": true,
  "flagged_by_providers": ["codex", "gemini"]
}
```

Fields MAY be omitted. Omitted fields are treated as "not applicable" (no score impact). Implementations SHOULD extract these fields from the review output automatically where possible, and fall back to conservative defaults (not applicable) where extraction is ambiguous.

## 10. Pseudocode

```python
def score_issue(issue: dict) -> int:
    score = 40  # base score

    # Positive factors
    if issue.get("line_numbers"):
        score += 25
    if issue.get("is_new_code"):
        score += 25
    if issue.get("rule_citation"):
        score += 20
    if issue.get("has_reproduction"):
        score += 15
    if len(issue.get("flagged_by_providers", [])) >= 2:
        score += 20  # consensus (extension §5.2)

    # Negative factors
    if issue.get("references_removed_code_only"):
        score -= 30
    if issue.get("is_linter_catchable") and issue.get("project_has_linter", True):
        score -= 25
    if issue.get("is_subjective_style"):
        score -= 25
    if issue.get("references_exist_in_codebase") is False:
        score -= 50  # hallucination

    # Guideline extension (§5.1) — no double-dip with rule_citation
    guideline = issue.get("guideline_match")
    if guideline == "explicit":
        if issue.get("rule_citation"):
            score -= 20  # remove rule_citation bonus, apply guideline instead
        score += 30
    elif guideline == "inferred":
        score += 10

    return max(0, min(100, score))


def filter_issues(issues: list, threshold: int = 80) -> list:
    return [i for i in issues if score_issue(i) >= threshold]
```

## 11. Reference Implementation

A reference implementation is available in the [claude-prism](https://github.com/tznthou/claude-prism) project, where this framework is used as the filtering layer in the `/pi-multi-review` command.

---

## 12. Changelog

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2026-03-09 | Initial release — base score 40, 5 positive + 4 negative factors, input schema, pseudocode |

---

## Citation

```bibtex
@misc{confidence_scoring_framework,
  title   = {AI Code Review Confidence Scoring Framework},
  author  = {claude-prism contributors},
  url     = {https://github.com/tznthou/claude-prism/blob/main/spec/confidence-scoring-v1.md},
  year    = {2026},
  license = {MIT}
}
```
