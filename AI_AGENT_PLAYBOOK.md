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

5. **Regression containment first**
   - when a spell has repeated API edge-case regressions, isolate it into spell-specific readiness logic instead of repeatedly changing shared helpers.

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

Release timing policy (strict):

- During active feature work, do **not** bump version, do **not** push, and do **not** tag.
- Batch feature work first; wait for user confirmation that work is complete.
- Only at the very end, after a concise feature summary, apply version/changelog/release actions when the user explicitly says to proceed.

Current collaboration preference (highest priority over generic policy):

- User frequently asks for immediate `master` pushes after each validated fix.
- User frequently asks: **"push no tags"**.
- When user says push/no tags, commit and push `master` only; do not create or push tags.
- Keep commit messages semantic and concise.

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
7. Do not push, tag, or bump version unless user explicitly requests final release execution.

## 11) Current Hotspots (March 2026)

### Renewing Mist (Mistweaver)

- Symptom history:
   - disappearing in combat,
   - `?` charge display in combat,
   - stale charge values not regenerating to max in combat.
- Current approach:
   - dedicated `isRenewingMistReady` path,
   - charge cache with recharge timing (`rechargeStart`, `rechargeDuration`),
   - cache estimation during unknown payloads.
- Guardrail:
   - avoid touching this path unless user reports new RM-specific regressions.

### Life Cocoon (custom tracked spell)

- Symptom history:
   - disappearing in combat,
   - then disappearing in/out of combat,
   - then permanently displayed.
- Current approach:
   - dedicated `isLifeCocoonReady` path,
   - deterministic cooldown evaluation first,
   - cached last-known fallback only when cooldown payload is indeterminate.
- Guardrail:
   - do not route Cocoon through generic permissive fail-open readiness.

### Shared-helper policy after repeated regressions

- Keep shared helpers generic and stable for most spells.
- Isolate exceptional spells with dedicated helpers (policy/override style).
- Prefer adding a narrow spell override over changing global readiness semantics.

## 12) Handoff Notes for New AI Sessions

- First read: `AI_AGENT_PLAYBOOK.md`, then `HealingPriorityMouse.lua` around readiness helpers and custom spell loop.
- Respect user preference to push quickly with **no tags** when requested.
- If a fix touches readiness helpers, explicitly state blast radius (shared vs spell-specific).
- For combat regressions, validate in this order:
   1. out-of-combat baseline not regressed,
   2. combat entry behavior,
   3. cooldown/charge transitions under spend+recharge.

## 13) Current Handoff State (Post 1.0.14 Release)

Where work currently stands:

- `Renewing Mist` logic is considered stable by user feedback in and out of combat.
- `Life Cocoon` remains a known unresolved issue and is deferred intentionally to the next patch cycle.

Open bug to carry forward:

- Cocoon readiness can still regress into either:
   - disappearing unexpectedly (combat and/or non-combat), or
   - persistent display when not truly ready.

Next-session execution guidance:

1. Treat Cocoon as an isolated bugfix task (do not broaden to shared readiness helpers unless required).
2. Do not modify `Renewing Mist` path unless a new RM-specific regression is reported.
3. Validate Cocoon against both combat entry and cooldown transition moments.
4. Keep release workflow aligned with user preference: fast push to `master`, usually no tags unless explicitly requested.

## 9) Bootstrap Prompt for New Conversations

Use/paste this into a fresh AI chat:

> You are working on HealingPriorityMouse (WoW Retail addon). Read `AI_AGENT_PLAYBOOK.md` first and follow it as the authoritative workflow and guardrails. Then read `README.md` and `CHANGELOG.md`, and proceed with the requested task using minimal, surgical changes while preserving established behavior.

## 10) Quick Notes for Future Maintainers

- If behavior appears inconsistent in combat, prefer safe/guarded logic over aggressive fail-open display.
- If a “fix” increases false positives (showing spells all the time), roll back and refine.
- Keep release scope explicit per version; avoid bundling unrelated changes.
