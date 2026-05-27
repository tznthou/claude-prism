# Reflections

Design notes and lessons learned while building claude-prism. These aren't user docs — they're the thinking behind the decisions.

[繁體中文](reflections.zh-TW.md) · [← Back to README](../README.md)

---

*First entry — 2026-03*

In the age of AI-assisted coding, most developers have access to the "big three" CLIs: Claude, Codex, and Gemini. After subscribing to Claude Code, I kept thinking: since I already have a powerful orchestrator at hand, why not leverage other providers' CLIs at the same time? Whether it's code review, technical research, or UI/UX design, having different AIs approach the same problem from different angles yields more comprehensive results than any single source.

I looked around, but the existing tools I found were either too heavy or didn't integrate well with Claude Code's workflow. So I decided to build my own.

It started as a few simple wrapper scripts to handle everyday review tasks. But as I kept building, more possibilities emerged: triple-provider adversarial review, review trend analysis, CI/CD automation... None of these were in the original plan, yet each one felt genuinely useful.

So here we are. I hope this tool helps you too.

---

*Update — 2026-04-03*

OpenAI released [codex-plugin-cc](https://github.com/openai/codex-plugin-cc). My first reaction was honestly a bit of a gut punch — wait, they're officially building a Codex plugin for Claude Code themselves?

But after studying it closely, I calmed down. The architectures are fundamentally different: theirs is a heavy-duty Node.js + JSONRPC + Unix socket broker setup; ours is a lightweight Bash shell script approach. The positioning is different too — they're deep single-provider integration, we're cross-provider orchestration. There's no replacement story here.

That said, one thing in their repo really caught my eye: `adversarial-review`. Instead of casting the AI as a neutral "Senior Reviewer," they explicitly tell it: "your job is to break confidence in this change, not to validate it." Seven attack surface categories, every finding must answer four questions, calibration rules demanding "prefer one strong finding over several weak ones" — this design philosophy gave me a lot of inspiration.

After all, we're just Vibe Coders — standing on the shoulders of giants to see a little further is nothing but a good thing. So I went ahead and reworked the prompt architecture for `pi-code-review` and `pi-multi-review`: adversarial stance, divided attack surfaces (Codex attacks security, Gemini attacks design/UX), finding bars, and calibration rules. The concepts were borrowed, but once they were fused with our existing confidence scoring framework and domain-aware weighting, they became something of our own.

That's the beauty of open source, I suppose.

---

*Update — 2026-04-03 (afternoon)*

Today I ran `npm install -g` on claude-prism myself, fully confident it was done — only to find that none of the commands had actually been deployed to `~/.claude/`. Turns out `npm install -g` only places the binary in your PATH; you still need to run `claud-prism-aireview` once to actually deploy everything.

This is probably the easiest pitfall for a Vibe Coder to stumble into: assuming `npm install` equals "fully installed." I even considered adding a `postinstall` script to auto-trigger `install.sh` and skip that extra step. But after digging into it, I learned that `postinstall` is now the #1 entry point for npm supply chain attacks — the March 2026 Axios incident (a North Korean state actor planted a RAT via postinstall; it was live for under three hours but reached millions of environments) is a sobering example. pnpm v10 and Bun now block all lifecycle scripts by default, and the entire ecosystem is systematically moving away from them.

So the final approach: no `postinstall`. Instead, make the README crystal clear that the two-step install is a deliberate security design, not laziness. In the process, I also realized we already had SHA256 checksum verification and npm OIDC provenance in place — the full security chain was more robust than I thought.

The upside of being a beginner is that every pitfall forces you to actually understand *why* things are designed a certain way, rather than just copying patterns without knowing the reason.

---

*Update — 2026-04 to 05*

Around late April, Claude Code started silently killing long-running Bash calls. No signal, no log, no trace — processes just vanished mid-execution. That's when we went from "wrapper scripts that call CLIs" to actually running controlled experiments.

We ran 36+ trials across five experiment groups to figure out what was happening. The punchline: Claude Code's main-conversation Bash is a structural FIFO queue — two "parallel" calls are secretly sequential, every single time. Sub-agent Bash, on the other hand, dispatches in genuine parallel. That one finding reshaped the entire architecture. (Details in [docs/research/bash-tool-parallelism.md](research/bash-tool-parallelism.md).)

Then came the soft-timeout mechanism — a six-layer defense so the wrapper exits cleanly before Claude Code's ~130s watchdog kills it. We built it, shipped it, and then ran efficacy experiments (N=9, ABA design) to see if it actually helped. It did — median 124 seconds faster. But along the way, we stumbled onto something weirder: Claude Code was padding sub-agent runtimes to match our timeout cap, 1:1. A 30-second call reported as 540 seconds. That one took a while to untangle.

Right now we're in a quieter phase — Phase A2, shipping a tri-state first-byte detector (`measured` / `fallback` / `na`) and watching real production data accumulate. Less drama, more instrumentation. The kind of work where you check a log file every few days and see if the numbers are saying anything you didn't expect. It's a different pace from the frantic experiment-running weeks, but probably the more honest way to build confidence in what we've made.
