# 成本估算

claude-prism 是本地端 wrapper——它本身不處理也不計費 token。每個指令可能透過 CLI 觸發一或多次外部 provider（Codex、Gemini）的 API 呼叫。Claude Code 自身的調度 token（讀取檔案、組建 prompt、合成結果）是獨立計算的，由你的 Claude 訂閱方案或 API 方案承擔。

[English](cost.md) · [← 返回 README](../README.zh-TW.md)

---

## 各指令 Token 消耗

| 指令 | 外部呼叫 | 典型 Input Tokens | 典型 Output Tokens | 備註 |
|------|---------|-------------------|-------------------|------|
| `/pi-ask-codex` | 1 (Codex) | 500–2K | 500–2K | 隨問題複雜度增減 |
| `/pi-ask-gemini` | 1 (Gemini) | 500–2K | 500–2K | 隨問題複雜度增減 |
| `/pi-askall` | 2 (Codex + Gemini) | 各 500–2K | 各 500–2K | 兩個 provider 並行呼叫 |
| `/pi-fact-check` | 1 (Gemini) + N (WebSearch) | 1K–5K | 2K–8K | 隨聲明數量增減；WebSearch 平行執行 |
| `/pi-code-review` | 1 (Codex) | 2K–10K | 1K–4K | 隨 diff 大小增減 |
| `/pi-ui-review` | 1 (Gemini) | 2K–10K | 1K–4K | 隨檔案數量增減 |
| `/pi-ui-design` | 1 (Gemini) | 1K–3K | 3K–8K | 產出較重（HTML 生成） |
| `/pi-research` | 1 (Gemini) + 2–4 (WebSearch) | 1K–5K | 2K–8K | 雙軌搜尋；隨主題複雜度增減 |
| `/pi-multi-review` | 2 (Codex + Gemini) | 上述 ×2 | 上述 ×2 | 兩個 provider 並行呼叫 |
| `/pi-plan` | 0–2（可選） | 各 1K–5K | 各 1K–4K | 僅在 provider 可用時諮詢 |

Token 範圍為近似值，隨輸入大小（diff 長度、檔案數、問題複雜度）變動。不同 provider 使用不同的 tokenization 方法——這些數字是數量級估算，非帳單精確值。

## 控制成本

- **`--dry-run`** — 測試請求路徑但不呼叫 provider（不消耗 token）
- **`usage-summary.sh`** — 檢視歷史呼叫次數與粗估 token 用量：
  ```bash
  ~/.claude/scripts/usage-summary.sh --week
  ```
- **Provider 定價** — 至各 provider 定價頁面查詢目前費率：
  - [OpenAI API Pricing](https://openai.com/api/pricing/)
  - [Google AI Pricing](https://ai.google.dev/pricing)
