# Changelog

All notable changes to this project are documented in this file.

## [1.0.13-beta.7] - 2026-03-12

### Fixed
- Fixed login-time `ADDON_ACTION_FORBIDDEN` involving protected `Frame:RegisterEvent()` calls.

### Changed
- Runtime event registration now initializes during addon startup (`ADDON_LOADED`) instead of in the main chunk.

## [1.0.13-beta.6] - 2026-03-12

### Fixed
- Prevented Discipline `Power Word: Shield` readiness from dropping to false during combat when cooldown payload fields are redacted (`startTime=nil`, `duration=nil`).
- Added combat fallback for Discipline `Atonement` count using combat-log aura tracking when live aura reads under-report in combat.

### Changed
- Added additional throttled diagnostics for PW:S missing-payload fallback decisions and Atonement live-vs-cached count summaries.

## [1.0.13-beta.5] - 2026-03-12

### Fixed
- Improved Discipline `Atonement` combat counting reliability by adding robust aura-detection fallbacks.
- Reduced cases where icon decisions flicker or disappear in combat due to fragile aura API reads.

### Changed
- Reduced PW:S debug log spam with stronger per-message throttling and entry-state-change logging.

## [1.0.13-beta.4] - 2026-03-12

### Fixed
- Fixed Discipline `Power Word: Shield` readiness false negatives when in-combat cooldown payloads return missing (`startTime=nil`, `duration=nil`) values.

### Changed
- Added resilient cooldown fallback order for missing payloads: cache -> legacy `GetSpellCooldown` -> `IsUsableSpell`.
- Added `missingPayload` flag to PW:S debug logs for clearer combat diagnostics.

## [1.0.13-beta.3] - 2026-03-12

### Fixed
- Fixed startup/runtime crash caused by calling `resolveSpellID` before local declaration in PW:S debug instrumentation.

### Notes
- Hotfix beta release to restore addon loading and allow PW:S debug capture.

## [1.0.13-beta.2] - 2026-03-12

### Added
- Added `/hpm debug on|off|dump [n]|clear` internal logging tools for combat troubleshooting.
- Added PW:S-focused decision tracing (live cooldown read, cache fallback, usability fallback, and entry decision logging).

### Notes
- This beta is intended to capture high-signal diagnostics for in-combat Power Word: Shield icon suppression.

## [1.0.13-beta.1] - 2026-03-12

### Changed
- Added event-driven internal cooldown caching for Discipline `Power Word: Shield` to improve icon readiness stability during combat.

### Fixed
- Reduced cases where `Power Word: Shield` icon incorrectly disappears in combat despite the spell being available.

### Notes
- This is a beta pipeline validation release focused on combat cooldown-read consistency.

## [1.0.12] - 2026-03-11

### Added
- Added `/hpm options` in-game options window while preserving existing slash command workflow.
- Added scale controls with both slider and numeric input, and expanded supported range to `0.6-3.0`.
- Added icon opacity controls (slider + numeric input, `0-100%`) and `/hpm opacity` command.
- Added spell-name visibility and position controls (`under/above icon`) in UI, plus `/hpm names` and `/hpm namepos` commands.
- Added drag-to-move behavior for the options window.

### Changed
- Option changes now stay synchronized between the options window controls and slash command updates.

### Fixed
- Increased options window height so controls no longer render outside the panel.
- Removed blue icon-border square artifact visible at low opacity.

## [1.0.11] - 2026-03-10

### Fixed
- CurseForge automatic packaging now uses this file (`CHANGELOG.md`) as the published changelog instead of commit history.

### Security/Privacy
- Prevents commit metadata (such as author email addresses) from appearing in the CurseForge app changelog feed.

## [1.0.10] - 2026-03-09

### Added
- Added `/hpm version` command to print the currently running addon version in chat.

### Notes
- This release is intentionally scoped to version reporting command availability and release alignment.

## [1.0.8] - 2026-03-08

### Fixed
- Improved `Power Word: Shield` display consistency for Discipline Priest when the spell is available.

### Changed
- Reworked spell known-state checks to use override-aware APIs first, with guarded fallbacks.
- Hardened cooldown readiness logic with safer fallbacks to `IsUsableSpell` when cooldown data is missing or unreliable.
- Updated related known-state checks used by talent fallback and `/hpm audit` reporting.

## [1.0.7] - 2026-03-08

### Changed
- Removed spell name text under icons for a cleaner icon-only display.
- Kept in-icon overlay information intact (including Atonement count and charge/unknown overlays).

## [1.0.6] - 2026-03-08

### Changed
- Discipline Atonement entry now keeps the label as `Atonement` and displays the active Atonement count inside the icon overlay.
- Added entry-level icon counter support so future spec-specific counters can be shown in-icon without changing label text.

## [1.0.5] - 2026-03-08

### Added
- Discipline `Power Word: Shield` priority tracking and display.

### Changed
- Discipline Atonement behavior now always displays and tracks active Atonement count.
- Preservation Evoker `Reversion` and `Echo` logic no longer relies strictly on mouseover; group-aware fallback is used when no friendly mouseover exists.

### Fixed
- Resolved missing `Power Word: Shield` display for Discipline Priest.
- Reduced unintuitive Preservation behavior where core entries only appeared while hovering friendly unit frames.

## [1.0.4] - 2026-03-08

### Added
- Midnight-safe protected value handling helpers for numbers, booleans, comparisons, and nil checks.
- Safe cooldown and charge parsing paths that tolerate protected/secret return values.
- Charge fallback display (`?`) when charge values are not safely readable.

### Changed
- Hardened cooldown readiness logic to avoid direct comparisons on raw API fields.
- Hardened talent node rank checks to avoid direct arithmetic/comparison on raw node values.
- Hardened icon cooldown and charge display conditions to use guarded comparisons.
- Updated aura lookup and charge detection paths to avoid unsafe direct nil comparisons on raw API values.

### Fixed
- Resolved runtime taint/crash paths caused by comparing protected/secret numeric values (for example cooldown `duration`).
- Reduced repeat taint risk in UI refresh and charge rendering code by coercing and validating values before use.

## [1.0.3] - 2026-03-08

### Added
- `/hpm audit` output improvements to report `known` vs `exists, not known` spell status.

### Changed
- `Undergrowth` auto detection updated to use talent node data when available, with legacy spell fallback.

## [1.0.2] - 2026-03-08

### Changed
- Updated healer priority logic to align with current Retail/Midnight behavior.
- Removed/disabled obsolete behavior paths (including `Cloudburst Totem` on 12.0.0+ clients).
- Kept addon strictly display-only (no protected actions, no targeting automation).

## [1.0.1] - 2026-03-08

### Changed
- Standardized aura and cooldown checks on modern Retail APIs (`C_UnitAuras`, `C_Spell`).
- Improved mouse-anchor display stability for icon row rendering.

## [1.0.0] - 2026-03-08

### Added
- Initial release of `HealingPriorityMouse` as a display-only addon inspired by the WeakAura concept.
- Compact mouse-following icon row with healer spell priority prompts.
- Slash command controls for toggle, scale, undergrowth mode, and charge display.
