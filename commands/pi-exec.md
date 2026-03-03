---
command: pi-exec
description: Execute a structured plan file step by step — supports resume from interruption
---

# Plan Execution

Read a structured plan file and execute it step by step, updating progress as you go. Supports resuming from where you left off.

## Execution

### 1. Read the plan file

`$ARGUMENTS` must be a path to a plan file (typically `.claude/pi-plans/<name>.md`).

Read the file using the Read tool. If the file doesn't exist, tell the user and suggest: "Run `/pi-plan <task description>` first to generate a plan."

### 2. Validate plan status

Check the `**Status**` field in the Metadata section:

- **`draft`** → Ask the user: "This plan is still in draft. Would you like to execute it as-is, or review and modify it first?" Wait for confirmation before proceeding.
- **`approved`** → Proceed to execution.
- **`in-progress`** → Scan for the first unchecked step (`- [ ]`). Report: "Resuming from step N — M of K steps already completed." Then continue from that step.
- **`completed`** → Tell the user the plan is already done. Ask if they want to re-execute from scratch.

### 3. Update status to in-progress

Use the Edit tool to update the plan file's Status:

Change `- **Status**: draft` (or `approved`) to `- **Status**: in-progress`

### 4. Execute steps sequentially

For each unchecked step (`- [ ]`) in the Steps section:

1. **Announce** the step to the user before executing
2. **Execute** the step using appropriate tools (Read, Edit, Write, Bash, Glob, Grep, etc.)
3. **Verify** the step succeeded — run tests, check for syntax errors, confirm file changes
4. **Update** the plan file — use Edit tool to change `- [ ]` to `- [x]` for the completed step
5. **Report** progress: "Step N/K complete: <brief description>"

**If a step fails:**
- Do NOT continue to the next step automatically
- Report the failure with details (error message, what was attempted)
- Use AskUserQuestion to ask how to proceed:
  - Retry the step
  - Skip and continue
  - Abort execution
- If the user chooses to abort, leave the Status as `in-progress` so they can resume later

### 5. Run verification

After all Steps are checked off, execute each item in the Verification section:
- Run listed test commands
- Check acceptance criteria
- Mark each verification item as `[x]` when passed

If any verification fails, report the failure and ask the user how to proceed.

### 6. Update final status

When all steps and verification items are complete, use Edit tool to change:
`- **Status**: in-progress` to `- **Status**: completed`

### 7. Summary

Output a completion summary:
- Steps completed: X/Y
- Verification results: passed/failed
- Key files created or modified during execution
- Any issues encountered and how they were resolved

### Notes

- The plan file is the single source of truth for progress
- If the Claude Code session ends mid-execution, running `/pi-exec` again on the same plan file will resume from the first unchecked step (Step 2 handles this)
- The `Domain` field in the plan metadata can inform a subsequent `/pi-multi-review` if the user wants a review after execution
- Do not modify the plan's Steps, Key Files, or Risks sections during execution — they are the original spec. If you discover the plan needs changes, tell the user and let them decide
