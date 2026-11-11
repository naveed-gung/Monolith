<!-- AGENT NOTE: Append your session line at the TOP (newest first). Max 30 entries —
delete the oldest beyond 30. Format: date | agent | tasks touched | commit-sha-or-"uncommitted".
Rules: docs/agent/PROTOCOL.md -->
---
doc: SESSIONS
last-verified: 2026-11-10
verified-by: devin
---

# Session journal (newest first, max 30)

| Date | Agent | Work | Commit |
|------|-------|------|--------|
| 2026-11-10 | devin | TASK-17 scoped-storage fix: stage all in-progress downloads privately, artwork to private Art dir (both downloader pipelines); 1.5.2+18 | uncommitted |
| 2026-11-10 | devin | TASK-13 LAN song sharing (UDP discovery + TLS 1.3 pinned framed protocol, send+receive, desktop-compatible wire v1) and TASK-14 player shared-element open/close; v1.5.0+16; opened TASK-15 Bluetooth RFCOMM | uncommitted |
| 2026-09-29 | codex | Planned TASK-10 editable Up Next and TASK-11 sleep timer; recorded TASK-12 listening sessions as an unapproved proposal; corrected current source version in index | uncommitted |
| 2026-09-20 | claude-code | Released 1.4.5+14 (tag `v1.4.5`); TASK-06 DONE — gated release publishing to `v*` tags after finding main pushes had overwritten the `v1.4.4` assets; corrected the false "no android.yml" fact in 00-INDEX/01-roadmap/docs/ci.md (TASK-04 DONE, it has existed since `39a2654`); opened TASK-07/08/09. Tag `v1.4.5` NOT pushed — HUMAN-GATE, left to the owner | 314e9ea |
| 2026-09-19 | claude-code | Reviewed and shipped the download-history / playback-order batch (16 changes); analyze clean for lib+test, 27 targeted tests green; scaffolded this KB and seeded TASK-01..05 | bd83488 |
