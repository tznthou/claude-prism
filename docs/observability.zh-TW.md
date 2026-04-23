# 可觀測性

claude-prism 在本地留下的紀錄與診斷——使用量、review 趨勢、呼叫生命週期、以及 Claude Code 快取 TTL 行為的注意事項。

[English](observability.md) · [← 返回 README](../README.zh-TW.md)

---

## 使用量統計

追蹤 API 呼叫量和估算 token 消耗：

```bash
~/.claude/scripts/usage-summary.sh            # 今天
~/.claude/scripts/usage-summary.sh --week      # 過去 7 天
~/.claude/scripts/usage-summary.sh --all       # 全部
~/.claude/scripts/usage-summary.sh --date 2026-02-24  # 指定日期
```

輸出包含各 provider 呼叫次數、成功/失敗/dry-run 分佈、粗估 token 量（~4 字元/token）。

## Review 趨勢分析

每次 `/pi-code-review` 或 `/pi-multi-review` 結束時，Claude 會解讀 provider 的輸出——把 emoji 嚴重度對應為字串、推斷發現來源、依信心門檻過濾——再把結構化結果寫入 `~/.claude/logs/review-insights.jsonl`。底下的腳本用 `jq` 讀這個檔案產出純粹的計數，趨勢解讀則可請 Claude 接手：

```bash
~/.claude/scripts/review-insights.sh              # 計數統計（不含 AI 解讀）
~/.claude/scripts/review-insights.sh --recent 10  # 最近 10 次
~/.claude/scripts/review-insights.sh --project my-app  # 篩選專案
```

輸出包含：
- **分類分佈** — security、performance、design、logic 等（含長條圖）
- **嚴重度分佈** — critical / medium / suggestion
- **發現來源** — 共識 vs 單一 provider 發現
- **最常見問題** — 重複出現的模式會標記
- **近期 review 時間軸** — 最近 5 次 review 及問題數量

每筆 review 紀錄格式：

```json
{
  "date": "2026-02-24T10:30:00Z",
  "project": "my-app",
  "scope": "pr",
  "domain": "backend",
  "providers": ["codex", "gemini", "claude"],
  "issues": [
    {
      "category": "security",
      "severity": "critical",
      "confidence": 95,
      "title": "SQL injection in user input handler",
      "source": "consensus"
    }
  ]
}
```

分類：`security`、`performance`、`design`、`logic`、`maintainability`、`guideline`、`accessibility`、`other`。`guideline` 分類追蹤專案規範違規（`CLAUDE.md` / `Agents.md`）。

## 呼叫生命週期診斷

遇到狀況時——`/pi-*` 指令卡住、回傳空輸出、或 log 檔意外是 0 bytes——`analyze-log.sh` 會把 `multi-ai.log` 的事件依 pid 分組，告訴你每次呼叫是怎麼結束的：

```bash
~/.claude/scripts/analyze-log.sh              # 分析預設 log 檔
~/.claude/scripts/analyze-log.sh /path/to/log  # 指定 log 檔
```

每次呼叫會被歸類為五種結局之一：

- **SUCCESS** — 正常完成
- **ERROR** — CLI 回非零 exit code（會標示錯誤分類：`TIMEOUT`、`RATE_LIMIT`、`AUTH_ERROR`、`PERMISSION`、`SANDBOX`、`NETWORK`、`CLI_ERROR`、`CLI_NOT_FOUND`）
- **SIGNAL** — 執行中收到 `HUP` / `INT` / `TERM`（會附上當下卡在哪個執行階段）
- **SOFT_TIMEOUT**（v0.14.0+）— wrapper 的 `CLAUDE_PRISM_TIMEOUT` 掛鐘時限觸發；CLI 是被我們主動殺掉並留下結構化訊號，和下面 SILENT 的被動死亡可以明確區分
- **SILENT** — 有啟動但沒有任何完成事件——這是 `SIGKILL` 的特徵，通常發生在 Claude Code 的 Bash tool 把某次呼叫 auto-background 後直接把 child process 殺掉

SILENT death 是最有用的診斷訊號：看到就表示你的指令被提前終止。v0.12.3+ 的 `pi-*` commands 都在 preamble 指示 Claude 用前台同步方式呼叫 script，從源頭繞過這個 regression。完整背景見 [CHANGELOG.md](../CHANGELOG.md)，現行設計背後的分層實驗見 [Bash Tool Parallelism Research](research/bash-tool-parallelism.md)。

## 快取 TTL 行為

Claude Code 目前全員 5 分鐘 prompt cache TTL，不分 Pro 或 Max。當 `/pi-*` 指令超過 5 分鐘才回來（Codex、Gemini 跑大型任務時偶爾會碰到），Claude 下一輪對話就吃不到 cache read 的 10 倍折扣，等於原價重算一次。

這是 Claude Code 自己的行為，不是 claude-prism 的 bug——2026-03-08 前後，Claude Code 從原本 1 小時的 default 悄悄退回 5 分鐘（詳見 [GitHub issue #46829](https://github.com/anthropics/claude-code/issues/46829)）。Anthropic 的[官方 prompt caching 文件](https://platform.claude.com/docs/en/build-with-claude/prompt-caching)也明確寫了 TTL 不看訂閱層級——網路上流傳的「Max 使用者自動獲得 1 小時 TTL」是沒有官方背書的傳聞。

實測至今，這個 overhead 對 claude-prism 使用者沒造成明顯成本飆升。如果你遇到 token 消耗異常，歡迎開 issue 告訴我們。
