# CI/CD 整合

透過 GitHub Actions 自動化多方 provider PR review。CI 路徑直接使用 REST API（不需在 runner 上安裝 CLI）。

[English](ci-cd.md) · [← 返回 README](../README.zh-TW.md)

---

## 快速設定

1. 複製 workflow 檔案到你的專案：

```bash
mkdir -p .github/workflows
cp path/to/claude-prism/.github/workflows/ai-review.yml .github/workflows/
cp path/to/claude-prism/scripts/ci-review.sh scripts/
```

2. 在 GitHub Secrets 設定 API key（至少一個）：

| Secret | Provider | 必要？ |
|--------|----------|--------|
| `GEMINI_API_KEY` | Gemini review | 選配 |
| `OPENAI_API_KEY` | OpenAI review | 選配 |
| `ANTHROPIC_API_KEY` | Claude 綜合分析 | 選配 |

3. 在 PR 加上 `ai-review` label 即可觸發 review。

## 觸發模式

**Label 觸發（預設）：** 在 PR 加上 `ai-review` label → workflow 執行。適合控制成本。

**自動觸發：** 取消 workflow 檔案中 `pull_request: [opened, synchronize]` 區塊的註解 → 每次 PR 更新自動執行。

## CI 運作原理

1. GitHub Actions checkout PR 並取得 diff
2. `ci-review.sh` 自動偵測 `CLAUDE.md` / `Agents.md` 作為規範 context
3. 透過 GraphQL（單次 API 呼叫）查詢同檔案的歷史 PR 評論，作為反覆問題的 context
4. Diff 並行送給可用 provider（Gemini API、OpenAI API），含 inline annotation 合規檢查和 false positive 排除規則
5. 若有設定 `ANTHROPIC_API_KEY`，Claude 進行信心度評分綜合分析（只有 ≥ 80 分的 issue 會被貼出）
6. 若無，直接串接各方結果
7. 若 review 包含具體修正建議，會以 **inline PR review comment** 搭配 GitHub suggestion block 發佈（一鍵接受修改）。其餘內容作為 review body。若 Reviews API 不可用，退回一般 PR comment

## CI 環境變數

| 變數 | 預設值 | 說明 |
|------|--------|------|
| `GEMINI_MODEL` | `gemini-2.0-flash` | CI review 用的 Gemini 模型 |
| `OPENAI_MODEL` | `gpt-4o` | CI review 用的 OpenAI 模型 |
| `ANTHROPIC_MODEL` | `claude-sonnet-4-20250514` | 綜合分析用的 Claude 模型 |
| `MAX_DIFF_CHARS` | `32000` | Diff 截斷上限 |

## 安全注意事項

- **Fork PR**：Workflow 使用 `pull_request`（不是 `pull_request_target`），fork PR 無法存取你的 secrets。這是設計如此——fork PR 會被跳過。
- **API key**：使用 GitHub repository secrets，切勿將 API key commit 到 repo。
- **Concurrency**：同一 PR 同時只跑一個 review；新 push 會取消進行中的 review。
- **Checksums**：`checksums.sha256` 驗證檔案完整性，防止傳輸損壞或意外修改。但**無法**防禦 repo 本身被入侵——如需更強保護，請從 GitHub Release artifacts 頁面下載並比對。

## CLI 版本相容性

Wrapper scripts 依賴 CLI 的特定行為，這些行為不屬於官方穩定 API：

| CLI | 使用的行為 | 已驗證範圍 |
|-----|-----------|-----------|
| Gemini CLI | `-p " "` headless 模式（stdin + prompt） | v0.1.x – v0.3.x |
| Codex CLI | `codex exec - ` stdin 模式 | v0.100.x – v0.106.x |

若 CLI 更新導致功能異常，請固定使用已驗證版本或開 issue 回報。關於 2026-03-25 Gemini 服務更新，詳見主 README 的前置需求章節。
