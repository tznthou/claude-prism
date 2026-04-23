# 供應鏈安全

claude-prism 認真看待供應鏈安全。2025-2026 年間，`postinstall` scripts 已成為 npm 供應鏈攻擊的[頭號攻擊向量](https://snyk.io/articles/npm-security-best-practices-shai-hulud-attack/)——從 Shai-Hulud 蠕蟲（800+ 套件感染）到 [Axios RAT 入侵](https://www.microsoft.com/en-us/security/blog/2026/04/01/mitigating-the-axios-npm-supply-chain-compromise/)（北韓國家級駭客）。我們的安裝流程從設計上就避開了這些風險。

[English](supply-chain-security.md) · [← 返回 README](../README.zh-TW.md)

---

## 防禦層級

| 層級 | 防禦目標 | 機制 |
|------|---------|------|
| **不使用 `postinstall` scripts** | 安裝時靜默執行 | pnpm/Bun 使用者不會被擋；Socket.dev 不標記警告 |
| **使用者明確執行** | 未授權操作 | `npx` 或 `claud-prism-aireview` 都需要主動執行 |
| **SHA256 checksum 驗證** | 傳輸中檔案竄改 | `install.sh` 在部署前逐檔驗證，不符即中止 |
| **npm OIDC provenance** | 帳號劫持 | Package 只能從 GitHub Actions CI 發布，無法手動 `npm publish` |
| **安裝前自動備份** | 意外覆寫 | 現有檔案自動備份到 `~/.claude/.multi-ai-backup-*` |

## 自行驗證完整性

```bash
# Clone 後，驗證所有檔案的 checksum：
cd claude-prism
shasum -a 256 -c checksums.sha256

# 檢查 npm package provenance：
npm audit signatures
```
