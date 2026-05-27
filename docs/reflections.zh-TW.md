# 隨想

打造 claude-prism 過程中的設計筆記與心得。不是使用手冊，是決策背後的思考脈絡。

[English](reflections.md) · [← 返回 README](../README.zh-TW.md)

---

*初版 — 2026-03*

在 AI Coding 的時代，大部分開發者都會使用御三家（Claude、Codex、Gemini）的 CLI。我自己訂閱了 Claude Code 之後，就一直在想：既然已經有一個強大的 orchestrator 在手上，為什麼不能同時調度其他家的 CLI 來協助我完成更多事情？不管是 Code Review、技術研究，還是 UI/UX 設計，讓不同 AI 各自從不同角度切入，結果一定比單一來源更全面。

但我找了一圈，發現網路上現有的工具用起來都不太順手，不是太重、就是跟 Claude Code 的工作流整合得不好。所以我決定自己做一個。

本來只打算寫幾個簡單的 wrapper script，解決日常 review 的需求就好。沒想到做著做著，越來越多可能性冒出來：三方對抗式審查、review 趨勢分析、CI/CD 自動化⋯⋯這些方向都不在原本的計畫裡，但每一個都讓我覺得「欸，這好像真的有用」。

所以就變成了現在這個樣子。希望這個工具也能幫到你。

---

*更新 — 2026-04-03*

OpenAI 出了 [codex-plugin-cc](https://github.com/openai/codex-plugin-cc)。第一眼看到的時候，說實話有一種被暗算的感覺——什麼，官方自己下場做 Claude Code 的 Codex 插件了？

但仔細研究之後就冷靜了。底層架構完全不同：他們是 Node.js + JSONRPC + Unix socket broker 的重量級方案，我們是 Bash shell script 的輕量路線。定位也不一樣，他們是單一 provider 的深度整合，我們是 cross-provider orchestration。沒有誰取代誰的問題。

不過，裡面有個很有意思的東西：`adversarial-review`。他們不是讓 AI 當中性的 "Senior Reviewer"，而是明確告訴它「你的任務是打破對這份改動的信心，不是驗證它」。七類攻擊面、每個 finding 必須回答四個問題、校準規則要求「寧可一個強 finding，不要多個弱 finding」——這套設計哲學讓我很受啟發。

畢竟我們只是 Vibe Coder，能站在巨人的肩膀上看遠一點，何樂而不為。所以就著手改進了 `pi-code-review` 和 `pi-multi-review` 的 prompt 架構：引入 adversarial stance、定義分工攻擊面（Codex 攻擊 security、Gemini 攻擊 design/UX）、加入 finding bar 和校準規則。概念是借來的，但融入我們既有的 confidence scoring framework 和 domain-aware weighting 之後，反而變成了我們自己的東西。

開源的美好大概就是這樣吧。

---

*更新 — 2026-04-03（下午）*

今天自己用 `npm install -g` 安裝了 claude-prism，裝完信心滿滿地以為搞定了——結果 commands 根本沒進到 `~/.claude/`。才發現 `npm install -g` 只是把 binary 放進 PATH，你還得手動跑一次 `claud-prism-aireview` 才會真正部署。

這大概是 Vibe Coder 新手最容易踩的坑：以為 `npm install` 就等於安裝完成。我甚至一度想加 `postinstall` 來自動觸發 install.sh，省掉這一步。但研究之後才知道，`postinstall` 現在是 npm 供應鏈攻擊的頭號入口——2026 年 3 月的 Axios 事件（北韓駭客透過 postinstall 植入 RAT，上線不到三小時就影響了數百萬環境）就是血淋淋的例子。pnpm v10 和 Bun 已經預設封鎖所有 lifecycle scripts，整個生態系正在系統性地淘汰它。

最後的做法是：不加 postinstall，改把 README 的安裝說明寫清楚，讓使用者知道兩步驟是刻意的安全設計，不是偷懶。順便才想起來我們其實有 SHA256 checksum 驗證和 npm OIDC provenance，整條安全鏈比我自己以為的還完整。

身為菜鳥的好處是，踩過的坑會讓你認真去理解「為什麼要這樣設計」，而不是照抄別人的做法卻不知道原因。

---

*更新 — 2026-04 至 05*

四月下旬，Claude Code 開始殺掉跑太久的 Bash 呼叫。沒有訊號、沒有 log、沒有痕跡，process 在執行中途直接蒸發。光寫 wrapper script 不夠了，得認真跑對照實驗才搞得清楚怎麼回事。

五組實驗、36 場以上的測試。結果蠻扯的：Claude Code 主對話的 Bash tool 根本是 FIFO 佇列，你以為兩個呼叫在「平行」，其實在排隊，每次都是。Sub-agent 的 Bash 才是真平行。就這一個發現，整個分派架構從 parallel Bash 改成 sub-agent fan-out。（細節在 [docs/research/bash-tool-parallelism.md](research/bash-tool-parallelism.md)。）

接著做了 soft-timeout，六層防禦，讓 wrapper 在 Claude Code 的 ~130 秒看門狗動手之前先自己退場。上線後跑效能實驗（N=9，ABA 設計），中位數快了 124 秒，有感。但過程中撞到一件更離譜的事：Claude Code 把 sub-agent 回報的執行時間灌水到跟 timeout 上限 1:1。30 秒跑完的呼叫，它報 540 秒。這個 padding regression 花了好幾輪才摸到根因。

現在比較安靜了。Phase A2 上了三態 first-byte detector（`measured` / `fallback` / `na`），在真實環境慢慢看數據累積。沒有之前那幾週瘋狂跑實驗的刺激感，但這才是比較誠實的做法吧。每隔幾天翻一下 log，看數字有沒有在說什麼你沒預期到的事。
