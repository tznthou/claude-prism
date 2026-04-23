# Supply Chain Security

claude-prism takes supply chain security seriously. In 2025-2026, `postinstall` scripts became the [#1 attack vector](https://snyk.io/articles/npm-security-best-practices-shai-hulud-attack/) for npm supply chain attacks — from the Shai-Hulud worm (800+ packages infected) to the [Axios RAT compromise](https://www.microsoft.com/en-us/security/blog/2026/04/01/mitigating-the-axios-npm-supply-chain-compromise/) (North Korean state actor). We designed our install pipeline to avoid these risks entirely.

[繁體中文](supply-chain-security.zh-TW.md) · [← Back to README](../README.md)

---

## Defense Layers

| Layer | Protects Against | How |
|-------|-----------------|-----|
| **No `postinstall` scripts** | Silent execution on install | pnpm/Bun users aren't blocked; Socket.dev raises no flags |
| **Explicit user execution** | Unauthorized operations | `npx` or `claud-prism-aireview` requires deliberate action |
| **SHA256 checksums** | File tampering in transit | `install.sh` verifies every file before deploying; aborts on mismatch |
| **npm OIDC provenance** | Account hijacking | Packages can only be published from GitHub Actions CI, not manually |
| **Pre-install backup** | Accidental overwrites | Existing files backed up to `~/.claude/.multi-ai-backup-*` |

## Verify Integrity Yourself

```bash
# After cloning, verify all files match their checksums:
cd claude-prism
shasum -a 256 -c checksums.sha256

# Check npm package provenance:
npm audit signatures
```
