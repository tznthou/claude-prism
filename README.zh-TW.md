# claude-prism v0.3.1

[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](https://opensource.org/licenses/MIT)
[![Bash](https://img.shields.io/badge/Bash-4.0+-4EAA25.svg)](https://www.gnu.org/software/bash/)
[![Claude Code](https://img.shields.io/badge/Claude_Code-Plugin-7C3AED.svg)](https://claude.com/claude-code)

[English](README.md)

Claude Code 的跨 Provider AI 調度工具 — 消除同源盲點。

---

## 核心概念

### 問題

當 Claude Code 寫你的程式碼**同時也** review 它時，你會得到同源盲點。就像自己改自己的考卷——同一個模型有相同的知識缺口，某些類型的 bug、設計缺陷和安全問題會持續漏掉。

### 解法

讓 Claude Code 當**調度者**，把 review 和研究任務分派給 **Gemini** 和 **Codex**。三個不同的 AI provider、三組不同的訓練資料、三種不同的視角。

---

## 指令一覽

| 指令 | Provider | 說明 |
|------|----------|------|
| `/ask-codex` | Codex | 直接提問 — 取得 OpenAI 觀點 |
| `/ask-gemini` | Gemini | 直接提問 — 取得 Google 觀點 |
| `/code-review` | Codex | 跨 Provider 程式碼審查 |
| `/ui-design` | Gemini | 從設計規格產生 HTML mockup |
| `/ui-review` | Gemini | UI/UX 無障礙與設計審查 |
| `/research` | Gemini | 結構化技術研究 |
| `/multi-review` | Codex + Gemini + Claude | 三方對抗式審查 |

### `/ask-codex` — 詢問 OpenAI

直接向 Codex 提問，取得 OpenAI 的觀點。

```
/ask-codex React Query v5 中處理 optimistic updates 的最佳做法？
```

### `/ask-gemini` — 詢問 Google

直接向 Gemini 提問，利用 Google 的生態廣度。

```
/ask-gemini 比較 Bun vs Deno vs Node.js 作為 2026 年新後端專案的選擇
```

### `/code-review` — 跨 Provider Code Review

Codex review Claude 寫的程式碼。核心用例——**不同 AI 寫、不同 AI 審**。

```
/code-review                    # review staged changes
/code-review src/auth.ts        # review 指定檔案
/code-review --diff             # review unstaged changes
/code-review --pr               # review 整個 PR
```

### `/ui-design` — 從設計規格產生 HTML Mockup

Gemini 讀取設計規格文件，產出可在瀏覽器預覽的自包含 HTML mockup（Tailwind CDN）。確認設計後再讓 Claude Code 實作到專案。

```
/ui-design design-spec.md              # 從設計規格產生 HTML mockup
/ui-design "一個 SaaS dashboard"        # 沒有設計檔 → Gemini 先產規格再產 mockup
```

### `/ui-review` — UI/UX 審查

Gemini 審查前端程式碼的無障礙、響應式設計、元件結構和 UX 模式。

```
/ui-review src/components/Header.tsx
/ui-review src/app/(public)/
/ui-review --screenshot ./screenshot.png   # 改用 Claude 視覺分析
```

### `/research` — 技術研究

Gemini 進行結構化技術研究，包含比較表、推薦方案和學習資源。

```
/research Next.js App Router 最佳認證方案
/research Monorepo 工具比較：Turborepo vs Nx vs Moon
```

### `/multi-review` — 三方對抗式 Review

旗艦指令。同一份程式碼**同時**送給 Codex 和 Gemini，Claude 整合分析：

1. **共識區** — 雙方都指出的問題（高信心度，優先修復）
2. **分歧區** — 只有一方發現的問題（Claude 判斷有效性）
3. **Claude 補充** — 雙方都沒抓到但值得注意的問題

```
/multi-review                   # review staged changes
/multi-review --pr              # review 整個 PR
```

---

## 系統架構

```mermaid
flowchart LR
    User["👤 使用者"] <--> Claude["🟣 Claude Code\n(調度者)"]
    Claude -->|"/ask-codex\n/code-review\n/multi-review"| Codex["🟢 Codex CLI"]
    Claude -->|"/ask-gemini\n/ui-design\n/ui-review\n/research\n/multi-review"| Gemini["🔵 Gemini CLI"]
```

### 運作原理

1. 使用者在 Claude Code 輸入 slash command（如 `/code-review src/auth.ts`）
2. Claude Code 讀取 command 定義（含指示的 Markdown）
3. Claude 讀取相關程式碼，組裝 prompt
4. Claude 透過 Bash tool 呼叫 shell script → script 調用外部 CLI
5. 外部 AI 處理請求並回傳結果
6. Claude 呈現結果，適時加入自己的觀點

---

## 技術棧

| 技術 | 用途 | 備註 |
|------|------|------|
| Bash | CLI 包裝腳本 | 負責 binary 偵測、logging、stdin 管線 |
| Markdown | Slash command 定義 | Claude Code 讀取這些檔案作為指令 |
| Claude Code | 調度者 | 讀取 command，分派至外部 CLI |
| Codex CLI | OpenAI 存取 | Code review 與 Q&A（模型可設定） |
| Gemini CLI | Google 存取 | 研究、UI 審查、Q&A（模型可設定） |

---

## 快速開始

### 前置需求

| 工具 | 必要性 | 安裝方式 |
|------|--------|----------|
| [Claude Code](https://claude.com/claude-code) | 必要 | `npm install -g @anthropic-ai/claude-code` |
| [Gemini CLI](https://github.com/google-gemini/gemini-cli) | Gemini 相關指令需要 | `npm install -g @google/gemini-cli` |
| [Codex CLI](https://github.com/openai/codex) | Codex 相關指令需要 | `npm install -g @openai/codex` |

### 安裝

```bash
git clone https://github.com/tznthou/claude-prism.git
cd claude-prism
./install.sh
```

安裝程式會：
- 檢查前置需求並回報可用狀態
- 覆寫前自動備份現有檔案
- 複製 commands 到 `~/.claude/commands/`，scripts 到 `~/.claude/scripts/`

### 驗證安裝

```bash
./tests/smoke-test.sh
```

### 移除

```bash
./uninstall.sh
```

---

## 專案結構

```
claude-prism/
├── commands/                   # Slash command 定義（Markdown）
│   ├── ask-codex.md
│   ├── ask-gemini.md
│   ├── code-review.md
│   ├── multi-review.md
│   ├── research.md
│   ├── ui-design.md
│   └── ui-review.md
├── scripts/                    # CLI 包裝腳本（Bash）
│   ├── call-codex.sh
│   └── call-gemini.sh
├── tests/
│   └── smoke-test.sh
├── install.sh
├── uninstall.sh
├── README.md
└── README.zh-TW.md
```

安裝後的位置：

```
~/.claude/
├── commands/                   # ← command 定義複製到此
├── scripts/                    # ← 包裝腳本複製到此
└── logs/
    └── multi-ai.log            # 呼叫紀錄（可稽核）
```

---

## 設定

### 環境變數

| 變數 | 預設值 | 說明 |
|------|--------|------|
| `GEMINI_MODEL` | （CLI 預設） | 覆蓋 Gemini 模型（如 `gemini-3-pro-preview`） |
| `CODEX_MODEL` | （CLI 預設） | 覆蓋 Codex 模型（如 `gpt-5.3-codex`） |
| `GEMINI_BIN` | （自動偵測） | Gemini 執行檔路徑 |
| `CODEX_BIN` | （自動偵測） | Codex 執行檔路徑 |
| `MULTI_AI_LOG_DIR` | `~/.claude/logs` | 紀錄檔目錄 |

預設不指定模型，由各 CLI 使用內建預設值——零設定即可用。CLI 更新時自動使用最新模型。如需指定模型：

```bash
# Shell 設定檔（~/.zshrc 或 ~/.bashrc）
export GEMINI_MODEL="gemini-3-pro-preview"
export CODEX_MODEL="gpt-5.3-codex"

# 或單次呼叫時用 -m flag
~/.claude/scripts/call-gemini.sh -m gemini-3-flash-preview "your prompt"
```

### Script 功能

兩個包裝腳本都支援：

| 功能 | 說明 |
|------|------|
| **Binary 偵測** | 自動搜尋多個路徑找 CLI 執行檔 |
| **Logging** | 每次呼叫記錄到 `~/.claude/logs/multi-ai.log`（含時間戳） |
| **`--dry-run`** | 測試模式，不呼叫 API（不消耗 token） |
| **Stdin 管線** | `echo "code" \| call-gemini.sh "review"` 處理長輸入 |
| **Model 切換** | `-m model-name` 指定不同模型 |

### 自訂

**新增 Provider：**

1. 建立 `scripts/call-newprovider.sh`，參考現有 script 格式
2. 建立 `commands/ask-newprovider.md`，寫 command 定義
3. 執行 `./install.sh` 部署

**修改 Review Prompt：**

編輯 `commands/` 下的 `.md` 檔案，prompt 模板內嵌其中，直接改就好。

**輸出語言：**

Command 的 prompt 預設英文。要改成繁體中文輸出：

```diff
- "You are a Senior Code Reviewer. Review the following code."
+ "你是資深 Code Reviewer，用繁體中文 review 以下程式碼。"
```

---

## FAQ

**Q: Claude 真的有呼叫外部 CLI 嗎？還是自編自導？**

Logging 預設開啟，檢查 `~/.claude/logs/multi-ai.log` 即可驗證。每次呼叫都有時間戳、模型名稱和 prompt/response 長度。

**Q: 如果我只裝了 Gemini CLI？**

沒問題。需要 Codex 的指令（`/ask-codex`、`/code-review`）會顯示錯誤訊息。Gemini 相關指令（`/ask-gemini`、`/ui-design`、`/ui-review`、`/research`）正常運作。`/multi-review` 只會拿到一方觀點。

**Q: 費用多少？**

每個指令對外部 provider 發一次 API call，費用取決於你的 Gemini/OpenAI 計費方案。用 script 的 `--dry-run` 可以測試但不消耗 token。

**Q: 可以搭配其他 Claude Code 設定使用嗎？**

可以。Commands 和 scripts 是獨立的，只依賴 Claude Code 的 `~/.claude/` 目錄慣例。

---

## 更新紀錄

### v0.3.1 (2026-02-24)

- **`/ui-design` 重新設計** — 從設計規格檔產生可預覽的 HTML mockup（Tailwind CDN）
- 工作流程：設計規格 → HTML mockup → 瀏覽器預覽 → 確認 → Claude Code 實作
- 純文字輸入（無規格檔）觸發兩步流程：先產規格 → 再產 mockup
- 完成後以選項呈現下一步（調整、實作、或 `/ui-review`）

### v0.3.0 (2026-02-24)

- 新增指令：`/ui-design` — 透過 Gemini 生成 UI/UX 設計規格（資訊架構、wireframe、元件拆解、視覺方向）
- 可選 `--html` 旗標產出自包含 HTML 原型（Tailwind CDN）
- 自動偵測專案技術棧以提供更貼合的設計建議

### v0.2.1 (2026-02-24)

**Script 強化** — 透過 `/multi-review`（Codex + Gemini + Claude 三方對抗式審查）發現並修復：

- **`-m` flag 防護**：`-m` 未帶值時顯示明確錯誤，不再因 `set -u` 報 unbound variable crash
- **合併重複執行邏輯**：if/else 兩個分支的錯誤處理合併為單一 `|| { ... }` 區塊
- **清理錯誤日誌**：error log 不再記錄 response 內容（可能含原始碼或 token），僅記錄 exit code

### v0.2.0 (2026-02-24)

- 首次公開發佈
- 6 個 slash commands：`/ask-codex`、`/ask-gemini`、`/code-review`、`/ui-review`、`/research`、`/multi-review`
- 模型預設值交由 CLI 內建（不寫死版本號）
- dry-run 在 binary 檢查前退出（無需安裝 CLI 即可測試）

---

## 授權

本專案採用 [MIT](LICENSE) 授權。

---

## 作者

**tznthou** — [service@tznthou.com](mailto:service@tznthou.com)
