# HealingPriorityMouse — AI Agent Playbook

Use this file as the single source of truth when onboarding a new AI coding agent (Codex/Copilot/other) to this project.

## 1) Mission and Scope

- Project: `HealingPriorityMouse` (WoW Retail addon, Lua).
- Goal: maintain a **display-only** healer-priority helper anchored near mouse.
- Non-goals:
  - no protected gameplay actions,
  - no targeting automation,
  - no auto-cast behavior.

## 2) Current Project Files

- `HealingPriorityMouse.lua` — main logic, UI, slash commands.
- `HealingPriorityMouse.toc` — addon metadata (version currently hardcoded).
- `README.md` — user-facing docs + warning.
- `CHANGELOG.md` — release notes history.
- `CURSEFORGE_AUTOPACKAGING_SETUP.md` — CurseForge packaging setup notes.

## 3) Working Principles (Modus Operandi)

1. **Surgical changes only**
   - touch only what is needed for the request.
   - avoid broad refactors unless explicitly requested.

2. **Midnight/Retail safety first**
   - treat API-returned values as potentially unsafe/protected.
   - avoid direct arithmetic/comparison on raw returns when uncertain.
   - prefer guarded coercion and fail-safe display behavior.

3. **UI behavior continuity**
   - icon-first UI (labels intentionally removed).
   - keep useful overlays (Atonement count, charge/unknown markers).
   - avoid changing visual style/placement unless asked.

4. **Preserve release hygiene**
   - every behavior change updates `CHANGELOG.md`.
   - keep `README.md` command list accurate.
   - version bump must match release intent.

## 4) Established Behavioral Decisions

These are intentional and should not be changed accidentally:

- Addon remains display-only.
- `/hpm version` exists and should print current addon version.
- Discipline priorities include `Power Word: Shield` tracking.
- Atonement count is shown **inside icon overlay**, not as label text.
- Spell-name labels under icons are removed by design.
- Preservation behavior should not rely only on strict mouseover availability.

## 5) Coding Rules for This Addon

- Keep compatibility with modern Retail APIs already used in the project.
- Favor small helper-based hardening over inline risky comparisons.
- Do not add noisy debug spam to chat unless user asked for diagnostics.
- Keep naming clear; avoid one-letter locals except very short loop indices.
- Do not introduce new dependencies/frameworks.

## 6) Release and Versioning Workflow

When making a release-ready change:

1. Update addon version in:
   - `HealingPriorityMouse.lua` (if version constant exists there),
   - `HealingPriorityMouse.toc` (`## Version:`).
2. Add a dated entry in `CHANGELOG.md` with concise bullets.
3. Ensure `README.md` matches current slash commands/behavior.
4. Commit with semantic-style message if possible (`fix:`, `feat:`, `docs:`).
5. Push to `master` (or active release branch).
6. Tag release (`vX.Y.Z`) when packaging is desired.

## 7) CurseForge Packaging Notes

- Project is intended for tag-driven packaging.
- Changelog should come from `CHANGELOG.md` (not raw commit feed).
- If CurseForge app shows commit history instead of curated changelog:
  - verify packager metadata and project settings,
  - cut a new tag after fixing metadata/settings.

## 8) Standard Agent Checklist (Run Every Task)

1. Read this file first.
2. Read `README.md` and `CHANGELOG.md` before edits.
3. Implement minimal code changes.
4. Re-check for accidental behavior drift in the decisions listed above.
5. Update docs/changelog/version when applicable.
6. Report exactly what changed and where.

## 9) Bootstrap Prompt for New Conversations

Use/paste this into a fresh AI chat:

> You are working on HealingPriorityMouse (WoW Retail addon). Read `AI_AGENT_PLAYBOOK.md` first and follow it as the authoritative workflow and guardrails. Then read `README.md` and `CHANGELOG.md`, and proceed with the requested task using minimal, surgical changes while preserving established behavior.

## 10) Quick Notes for Future Maintainers

- If behavior appears inconsistent in combat, prefer safe/guarded logic over aggressive fail-open display.
- If a “fix” increases false positives (showing spells all the time), roll back and refine.
- Keep release scope explicit per version; avoid bundling unrelated changes.
