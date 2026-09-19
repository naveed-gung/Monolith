<!-- AGENT NOTE: This file IS the contract. Do not weaken it. If you change it,
record why in SESSIONS.md. -->
---
doc: PROTOCOL
last-verified: 2026-09-19
verified-by: claude-code
---

# Agent maintenance protocol — Monolith

Any agent (Claude Code, Cursor, Codex, Copilot, human) that modifies this repository
MUST leave `docs/agent/` current before ending its session. For Claude Code this is
enforced by global hooks (SessionStart context injection + a Stop hook that blocks
session end); for everyone else it is a hard convention carried by AGENTS.md/CLAUDE.md.

## 1. Session start

1. Read `docs/agent/00-INDEX.md` — doc map + current top priorities.
2. If your work relates to an existing task ID, set it `IN-PROGRESS` in its doc's
   Status table when you start (not when you finish).
3. Respect `HUMAN-GATE:` prefixes everywhere — those steps are never yours to run.

## 2. Session end (MANDATORY when the repo was modified)

1. **Status tables** — update the summary table at the top of every doc your work
   touched. Status lives ONLY there, never in task bodies.
2. **Frontmatter** — bump `last-verified:` + `verified-by:` in every doc whose facts
   you re-verified this session. Unverified docs keep their old date — no lying.
3. **SESSIONS.md** — append ONE line at the TOP:
   `YYYY-MM-DD | <agent> | <task IDs or 5-word summary> | <commit sha | uncommitted>`
   Keep ≤ 30 entries; delete the oldest overflow.
4. **New findings become tasks** — every bug/risk/idea you discovered gets a new row
   with the next free ID. Never leave findings only in the chat transcript.
5. **git add** any new files you created — the Stop hook ignores untracked files, so
   an un-added file is invisible to enforcement AND to the next session's diff.
6. **Priorities** — refresh 00-INDEX "Current top priorities" if the picture changed.

## 3. Task lifecycle

- IDs: `<PREFIX>-<NN>`, stable forever, never reused. Won't-do → status `DROPPED`.
- Status enum: `TODO | IN-PROGRESS | BLOCKED | DONE | DROPPED`.
- `DONE` requires the task's **Verification** steps to have actually been run and
  passed this session. No verification, no DONE.
- `BLOCKED` requires a one-line reason in the task body (`Blocked: waiting on X`).
- Priority: `P0` drop-everything · `P1` next up · `P2` planned · `P3` nice-to-have.
- Effort: `S` <1 h · `M` 1–4 h · `L` multi-session (MUST have checkpointed
  acceptance criteria so sessions can stop mid-task cleanly).

## 4. Task block template

```markdown
### TASK-01 Short imperative title
Priority: P1 · Effort: M · Depends: — · Files: path/one, path/two

**Why**: 1–3 sentences with evidence (exact paths, numbers, error strings).
**Acceptance criteria**:
- [ ] checkbox per criterion — tick as you land them
**Agent instructions**: numbered executable steps; `HUMAN-GATE:` prefix on any step
an agent must not run (consoles, key rotation, force-push, money, deploys).
**Verification**: exact commands/checks proving completion.
**Risks/rollback**: what can break; how to undo.
```

## 5. Honesty & drift rules

- Wrong doc content is a P1 bug in itself: fix it, note the correction in SESSIONS.md.
- Never duplicate status, dates, or counts in two places; derive, don't copy.
- Do not "tidy" tasks you don't understand — ask or leave a note in the task body.
- The docs describe the repo as it IS, plus work as it SHOULD BE — never aspirational
  descriptions of unbuilt things stated as fact.

## 6. HUMAN-GATE (never autonomous)

Cloud-console operations · credential/key rotation · git history rewrite or
force-push · anything costing money · production deploys/publishes · deleting user
data · sending external communications. Surface these to the user; do not execute.

## 7. Opt-out

A `.no-agent-docs` file in the repo root disables this protocol for the repo.
Creating or deleting that file is a user decision (HUMAN-GATE).
