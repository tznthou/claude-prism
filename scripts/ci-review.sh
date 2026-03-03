#!/usr/bin/env bash
# ci-review.sh — Automated multi-provider code review for CI/CD
# Usage:
#   ci-review.sh --pr 123                    # review PR (auto-fetch diff, post comment)
#   ci-review.sh --diff path/to/file.diff    # review diff file
#   echo "diff" | ci-review.sh               # review from stdin
#   ci-review.sh --dry-run --pr 123          # test without calling APIs
#
# Required: at least one of GEMINI_API_KEY, OPENAI_API_KEY, or ANTHROPIC_API_KEY
# Optional: GH_TOKEN or GITHUB_TOKEN for posting PR comments

set -euo pipefail

# --- Dependencies ---
for cmd in curl jq; do
    command -v "$cmd" &>/dev/null || { echo "Error: $cmd is required but not found" >&2; exit 1; }
done

# --- Config ---
MAX_DIFF_CHARS="${MAX_DIFF_CHARS:-32000}"
GEMINI_MODEL="${GEMINI_MODEL:-gemini-2.0-flash}"
OPENAI_MODEL="${OPENAI_MODEL:-gpt-4o}"
ANTHROPIC_MODEL="${ANTHROPIC_MODEL:-claude-sonnet-4-20250514}"
LOG_DIR="${MULTI_AI_LOG_DIR:-$HOME/.claude/logs}"
LOG_FILE="$LOG_DIR/multi-ai.log"

DRY_RUN=false
PR_NUMBER=""
DIFF_FILE=""
DIFF=""

# --- Logging ---
mkdir -p "$LOG_DIR"
_log() {
    local level="$1"; shift
    echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) [ci-review] [$level] $*" >> "$LOG_FILE"
}

# --- Parse args ---
while [[ $# -gt 0 ]]; do
    case "$1" in
        --pr)
            [[ $# -ge 2 ]] || { echo "Error: --pr requires a number" >&2; exit 1; }
            PR_NUMBER="$2"; shift 2 ;;
        --diff)
            [[ $# -ge 2 ]] || { echo "Error: --diff requires a file path" >&2; exit 1; }
            DIFF_FILE="$2"; shift 2 ;;
        --dry-run)
            DRY_RUN=true; shift ;;
        -h|--help)
            echo "Usage: ci-review.sh [--pr NUMBER] [--diff FILE] [--dry-run]"
            echo ""
            echo "Options:"
            echo "  --pr NUMBER    Review PR (auto-fetch diff, post comment when GH_TOKEN set)"
            echo "  --diff FILE    Review a diff file"
            echo "  --dry-run      Test without calling APIs"
            echo ""
            echo "Environment variables:"
            echo "  GEMINI_API_KEY     Enable Gemini review"
            echo "  OPENAI_API_KEY     Enable OpenAI review"
            echo "  ANTHROPIC_API_KEY  Enable Claude synthesis"
            echo "  GH_TOKEN           Post PR comment (auto-set in GitHub Actions)"
            echo "  MAX_DIFF_CHARS     Diff truncation limit (default: 32000)"
            exit 0 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

# --- Detect available providers ---
PROVIDERS=()
[[ -n "${GEMINI_API_KEY:-}" ]]    && PROVIDERS+=(gemini)
[[ -n "${OPENAI_API_KEY:-}" ]]    && PROVIDERS+=(openai)
HAS_CLAUDE=false
[[ -n "${ANTHROPIC_API_KEY:-}" ]] && HAS_CLAUDE=true

if [[ ${#PROVIDERS[@]} -eq 0 ]] && [[ "$HAS_CLAUDE" == false ]] && [[ "$DRY_RUN" == false ]]; then
    echo "Error: at least one API key required (GEMINI_API_KEY, OPENAI_API_KEY, or ANTHROPIC_API_KEY)" >&2
    exit 1
fi

_log INFO "providers=${PROVIDERS[*]:-none} has_claude=$HAS_CLAUDE pr=$PR_NUMBER dry_run=$DRY_RUN"

# --- Dry run (exit early, no diff or API keys needed) ---
if [[ "$DRY_RUN" == true ]]; then
    echo "[DRY RUN] ci-review.sh"
    echo "[DRY RUN] Providers: ${PROVIDERS[*]:-none} | Claude synthesis: $HAS_CLAUDE"
    echo "[DRY RUN] PR: ${PR_NUMBER:-none} | Diff file: ${DIFF_FILE:-none}"
    echo "[DRY RUN] Models: gemini=$GEMINI_MODEL openai=$OPENAI_MODEL anthropic=$ANTHROPIC_MODEL"
    _log INFO "dry run complete"
    exit 0
fi

# --- Resolve GH_TOKEN once ---
GH_TOKEN="${GH_TOKEN:-${GITHUB_TOKEN:-}}"

# --- Get diff ---
if [[ -n "$PR_NUMBER" ]] && [[ -z "$DIFF_FILE" ]]; then
    if [[ -z "$GH_TOKEN" ]]; then
        echo "Error: GH_TOKEN or GITHUB_TOKEN required for --pr mode" >&2
        exit 1
    fi
    DIFF=$(GH_TOKEN="$GH_TOKEN" gh pr diff "$PR_NUMBER" 2>&1) || {
        echo "Error: failed to fetch PR diff: $DIFF" >&2
        exit 1
    }
elif [[ -n "$DIFF_FILE" ]]; then
    if [[ ! -f "$DIFF_FILE" ]]; then
        echo "Error: diff file not found: $DIFF_FILE" >&2
        exit 1
    fi
    DIFF=$(cat "$DIFF_FILE")
elif [[ ! -t 0 ]]; then
    DIFF=$(cat)
else
    echo "Error: provide --pr NUMBER, --diff FILE, or pipe diff via stdin" >&2
    exit 1
fi

if [[ -z "$DIFF" ]]; then
    echo "No changes to review." >&2
    exit 0
fi

# --- Truncate large diffs ---
ORIGINAL_LEN=${#DIFF}
if [[ $ORIGINAL_LEN -gt $MAX_DIFF_CHARS ]]; then
    DIFF="${DIFF:0:$MAX_DIFF_CHARS}

... [truncated: ${ORIGINAL_LEN} chars total, showing first ${MAX_DIFF_CHARS}]"
    _log INFO "diff truncated from $ORIGINAL_LEN to $MAX_DIFF_CHARS chars"
fi

_log INFO "diff_len=${#DIFF}"

# --- Review prompt ---
REVIEW_PROMPT="You are a senior code reviewer. Review the following code diff for:
- Security vulnerabilities
- Performance issues
- Logic errors
- Design and maintainability concerns
- Accessibility issues (if UI code)

For each issue found, indicate severity:
- 🔴 Critical — must fix before merge
- 🟡 Medium — should fix, but not blocking
- 🟢 Suggestion — nice to have

Be specific: reference file names and line numbers from the diff.
If the code looks good, say so briefly.

---
DIFF:
$DIFF"

# --- API call functions ---

call_gemini_api() {
    local prompt="$1"
    local body
    body=$(jq -n --arg p "$prompt" '{contents:[{parts:[{text:$p}]}]}') || {
        echo "ERROR: Gemini JSON body construction failed"
        return 1
    }
    local response rc=0
    response=$(curl -sS --max-time 120 \
        "https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent" \
        -H "x-goog-api-key: $GEMINI_API_KEY" \
        -H "Content-Type: application/json" \
        -d "$body") || rc=$?
    if [[ $rc -ne 0 ]]; then
        echo "ERROR: Gemini API call failed (curl exit $rc)"
        return 1
    fi
    local text
    text=$(echo "$response" | jq -r '.candidates[0].content.parts[0].text // empty' 2>/dev/null)
    if [[ -z "$text" ]]; then
        local error
        error=$(echo "$response" | jq -r '.error.message // empty' 2>/dev/null)
        echo "ERROR: Gemini returned no content${error:+: $error}"
        return 1
    fi
    echo "$text"
}

call_openai_api() {
    local prompt="$1"
    local body
    body=$(jq -n --arg p "$prompt" --arg m "$OPENAI_MODEL" \
        '{model:$m,messages:[{role:"user",content:$p}]}') || {
        echo "ERROR: OpenAI JSON body construction failed"
        return 1
    }
    local response rc=0
    response=$(curl -sS --max-time 120 \
        "https://api.openai.com/v1/chat/completions" \
        -H "Authorization: Bearer $OPENAI_API_KEY" \
        -H "Content-Type: application/json" \
        -d "$body") || rc=$?
    if [[ $rc -ne 0 ]]; then
        echo "ERROR: OpenAI API call failed (curl exit $rc)"
        return 1
    fi
    local text
    text=$(echo "$response" | jq -r '.choices[0].message.content // empty' 2>/dev/null)
    if [[ -z "$text" ]]; then
        local error
        error=$(echo "$response" | jq -r '.error.message // empty' 2>/dev/null)
        echo "ERROR: OpenAI returned no content${error:+: $error}"
        return 1
    fi
    echo "$text"
}

call_claude_api() {
    local prompt="$1"
    local body
    body=$(jq -n --arg p "$prompt" --arg m "$ANTHROPIC_MODEL" \
        '{model:$m,max_tokens:4096,messages:[{role:"user",content:$p}]}') || {
        echo "ERROR: Anthropic JSON body construction failed"
        return 1
    }
    local response rc=0
    response=$(curl -sS --max-time 120 \
        "https://api.anthropic.com/v1/messages" \
        -H "x-api-key: $ANTHROPIC_API_KEY" \
        -H "anthropic-version: 2023-06-01" \
        -H "Content-Type: application/json" \
        -d "$body") || rc=$?
    if [[ $rc -ne 0 ]]; then
        echo "ERROR: Anthropic API call failed (curl exit $rc)"
        return 1
    fi
    local text
    text=$(echo "$response" | jq -r '.content[0].text // empty' 2>/dev/null)
    if [[ -z "$text" ]]; then
        local error
        error=$(echo "$response" | jq -r '.error.message // empty' 2>/dev/null)
        echo "ERROR: Claude returned no content${error:+: $error}"
        return 1
    fi
    echo "$text"
}

# --- Parallel provider calls ---
TMPDIR_REVIEW=$(mktemp -d)
trap 'rm -rf "$TMPDIR_REVIEW"' EXIT

PIDS=()

for provider in "${PROVIDERS[@]}"; do
    case "$provider" in
        gemini)
            call_gemini_api "$REVIEW_PROMPT" > "$TMPDIR_REVIEW/gemini.txt" 2>"$TMPDIR_REVIEW/gemini.err" &
            PIDS+=($!)
            ;;
        openai)
            call_openai_api "$REVIEW_PROMPT" > "$TMPDIR_REVIEW/openai.txt" 2>"$TMPDIR_REVIEW/openai.err" &
            PIDS+=($!)
            ;;
    esac
done

# Wait for all providers
for pid in "${PIDS[@]}"; do
    wait "$pid" || _log WARN "provider job $pid exited with $?"
done

# --- Collect results ---
GEMINI_RESULT=""
OPENAI_RESULT=""
RESPONDED=()

if [[ -f "$TMPDIR_REVIEW/gemini.txt" ]]; then
    GEMINI_RESULT=$(< "$TMPDIR_REVIEW/gemini.txt")
    if [[ "$GEMINI_RESULT" != ERROR:* ]]; then
        RESPONDED+=(gemini)
        _log INFO "gemini success response_len=${#GEMINI_RESULT}"
    else
        _log ERROR "gemini failed: ${GEMINI_RESULT:0:200}"
        [[ -s "$TMPDIR_REVIEW/gemini.err" ]] && _log ERROR "gemini stderr: $(head -c 500 "$TMPDIR_REVIEW/gemini.err")"
    fi
fi

if [[ -f "$TMPDIR_REVIEW/openai.txt" ]]; then
    OPENAI_RESULT=$(< "$TMPDIR_REVIEW/openai.txt")
    if [[ "$OPENAI_RESULT" != ERROR:* ]]; then
        RESPONDED+=(openai)
        _log INFO "openai success response_len=${#OPENAI_RESULT}"
    else
        _log ERROR "openai failed: ${OPENAI_RESULT:0:200}"
        [[ -s "$TMPDIR_REVIEW/openai.err" ]] && _log ERROR "openai stderr: $(head -c 500 "$TMPDIR_REVIEW/openai.err")"
    fi
fi

# --- Build output ---
OUTPUT=""

if [[ "$HAS_CLAUDE" == true ]] && [[ ${#RESPONDED[@]} -gt 0 ]]; then
    # Claude synthesis mode
    SYNTHESIS_PROMPT="You are a senior code reviewer synthesizing multiple AI code reviews.

Below are reviews from different AI providers for the same code diff. Your job:
1. Identify **Consensus** — issues flagged by multiple providers (high confidence, fix first)
2. Identify **Divergence** — issues only one provider found (judge validity)
3. Add **Your Own Findings** — issues no provider caught
4. Create a prioritized **Action Items** list

Format as clean Markdown suitable for a GitHub PR comment.
Use 🔴 Critical / 🟡 Medium / 🟢 Suggestion severity markers.

"
    for provider in "${RESPONDED[@]}"; do
        case "$provider" in
            gemini) SYNTHESIS_PROMPT+="## Gemini Review
$GEMINI_RESULT

" ;;
            openai) SYNTHESIS_PROMPT+="## OpenAI Review
$OPENAI_RESULT

" ;;
        esac
    done

    CLAUDE_RESULT=$(call_claude_api "$SYNTHESIS_PROMPT") || true

    if [[ -n "$CLAUDE_RESULT" ]] && [[ "$CLAUDE_RESULT" != ERROR:* ]]; then
        _log INFO "claude synthesis success response_len=${#CLAUDE_RESULT}"
        OUTPUT="## 🔍 AI Code Review — Multi-Provider Synthesis

> **Providers**: ${RESPONDED[*]} + claude (synthesis) | **Model**: $ANTHROPIC_MODEL

$CLAUDE_RESULT"
    else
        _log ERROR "claude synthesis failed, falling back to concatenation"
        HAS_CLAUDE=false
    fi
fi

if [[ -z "$OUTPUT" ]]; then
    # Simple concatenation mode (no Claude or Claude failed)
    OUTPUT="## 🔍 AI Code Review

> **Providers**: ${RESPONDED[*]:-none}
"
    if [[ ${#RESPONDED[@]} -eq 0 ]]; then
        if [[ "$HAS_CLAUDE" == true ]]; then
            # Claude-only review
            CLAUDE_RESULT=$(call_claude_api "$REVIEW_PROMPT") || true
            if [[ -n "$CLAUDE_RESULT" ]] && [[ "$CLAUDE_RESULT" != ERROR:* ]]; then
                _log INFO "claude solo review response_len=${#CLAUDE_RESULT}"
                OUTPUT="## 🔍 AI Code Review — Claude Only

> ⚠️ No external providers available. Single-perspective review.

$CLAUDE_RESULT"
            else
                echo "Error: all providers failed" >&2
                exit 1
            fi
        else
            echo "Error: no providers returned results" >&2
            exit 1
        fi
    else
        for provider in "${RESPONDED[@]}"; do
            case "$provider" in
                gemini) OUTPUT+="
### Gemini Review ($GEMINI_MODEL)

$GEMINI_RESULT
" ;;
                openai) OUTPUT+="
### OpenAI Review ($OPENAI_MODEL)

$OPENAI_RESULT
" ;;
            esac
        done
    fi
fi

# --- Footer ---
OUTPUT+="
---
*Generated by [claude-prism](https://github.com/tznthou/claude-prism) CI*"

# --- Output ---
echo "$OUTPUT"

# --- Post PR comment ---
if [[ -n "$PR_NUMBER" ]]; then
    if [[ -n "$GH_TOKEN" ]]; then
        echo "$OUTPUT" > "$TMPDIR_REVIEW/comment.md"
        GH_TOKEN="$GH_TOKEN" gh pr comment "$PR_NUMBER" --body-file "$TMPDIR_REVIEW/comment.md" 2>&1 || {
            _log ERROR "failed to post PR comment"
            echo "Warning: failed to post PR comment" >&2
        }
        _log INFO "PR comment posted to #$PR_NUMBER"
    else
        _log INFO "no GH_TOKEN, skipping PR comment"
    fi
fi

_log INFO "ci-review complete providers=${RESPONDED[*]:-none} claude=$HAS_CLAUDE"
