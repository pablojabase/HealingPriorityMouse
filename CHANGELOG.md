# Changelog

All notable changes to this project are documented in this file.

## [Unreleased]

### Added
- Added a minimap button that opens the in-game options window on left click.

## [1.0.15-beta.2] - 2026-03-22

### Added
- Added `/hpm apidump <spellID> [moreSpellIDs]` to print grouped API diagnostics for cooldown, charges, duration object, and addon-side readiness/cache state in one pass.

### Changed
- Introduced `SPELL_POLICIES`-driven core entry evaluation so major healer spells can be migrated toward clearer spell-specific behavior without expanding shared readiness semantics everywhere.
- Moved core spec recommendation assembly off the large per-spec branch block and onto policy evaluation while keeping dedicated overrides for high-regression spells such as `Renewing Mist` and `Life Cocoon`.
- Extended charge cache handling to retain enough state for full recharge estimation and to respect `chargeModRate` when estimating missing charges.

### Fixed
- Refreshed charge-driven updates on `SPELL_UPDATE_CHARGES` so `Renewing Mist` charge overlays and max-charge cues do not lag behind gained charges.
- Hardened `Life Cocoon` combat cooldown handling by marking the spell spent immediately on cast and preferring charge/cooldown evidence that keeps the icon hidden until the cooldown really returns.
- Fixed `Life Cocoon` staying hidden through the rest of combat after recharging by allowing single-charge cached recharge state to estimate back to ready in combat.
- Tightened `Life Cocoon` dedicated combat fallback so cache/charge state only proves readiness when a stored cooldown timer has actually elapsed, reducing always-visible false positives.
- Fixed `Life Cocoon` early combat reappearance caused by `rechargeStart=0` payloads being mistaken for an active elapsed timer.
- Improved charge-overlay responsiveness for `Renewing Mist` by preferring timer-estimated charge state when it is newer than stale live charge payloads.
- Fixed a Lua scoping regression that could error on UI initialization when the new charge-display resolver called `getSafeCharges` before its local binding existed.
- Fixed the remaining Lua scoping regression in the same charge-display resolver so it binds shared numeric helpers locally instead of falling back to missing globals.
- Reworked custom tracked-spell management so the add/remove UI only manages user-added spells, not built-in core recommendation spells.
- Tightened Discipline charge handling so `Penance` and `Power Word: Radiance` no longer remain visible with zero charges when charge payloads become fuzzy.
- Tightened Discipline `Power Word: Shield` targeting so the icon only appears for an actual friendly mouseover target instead of treating no mouseover as a missing-shield signal.
- Improved charge-spend cache updates for `Penance`, `Power Word: Radiance`, and other multi-charge spells so spent charges disappear immediately even when the live API lags behind the cast event.
- Stopped cooldown swipe/countdown rendering for multi-charge spells such as `Power Word: Radiance` so the icon row does not show the classic cooldown clock overlay there.
- Tightened cooldown end-time checks so spells like `Power Word: Shield` can reappear closer to Blizzard's own UI timing when cooldown payloads linger briefly.

### Known Issues
- `Renewing Mist` charge overlays can still lag behind the game by a few seconds in some combat recharge scenarios, even after recent responsiveness improvements.

## [1.0.14] - 2026-03-22

### Added
- Added conditional glow system with options + slash control (`/hpm glow on|off`) and guarded glow diagnostics (`/hpm glowdebug on|off`).
- Added Devtools tab with live recommendation logging and in-game debug log viewer.
- Added class-spell custom tracking UI (add/remove tracked spells) with character-scoped persistence.
- Added Restoration Shaman `Healing Stream Totem` support with active-totem detection.

### Changed
- Consolidated all `1.0.14-beta.1` through `1.0.14-beta.8` work plus subsequent untagged `master` hotfixes into this stable release.
- Reworked recommendation readiness/cooldown hardening for combat API edge cases and protected-value safety.
- Split `Renewing Mist` and `Life Cocoon` into dedicated spell-specific readiness paths to reduce cross-spell regressions.
- Reworked glow visuals (outside/clearer/brighter) and aligned glow rendering behavior for compact icon layout.

### Fixed
- Multiple Discipline regressions across combat visibility/readiness and charge-based glow behavior (`Penance`, `Power Word: Radiance`, `Power Word: Shield`, `Atonement` stability).
- Multiple Mistweaver regressions affecting `Renewing Mist` charge display/regen and combat fallback behavior.
- Combat-entry runtime crash from cached charge estimation (`numberGT` nil path) fixed.
- Several false-hide and false-show regressions in custom tracked spell readiness handling.

### Known Issues
- `Life Cocoon` readiness is still unstable in some user combat scenarios (reported as disappearing or persistently shown depending on state transitions).
- This is intentionally deferred for a follow-up patch release with targeted Cocoon-only validation.

### Release Notes
- This stable release includes a long sequence of untagged hotfix commits made directly to `master` at user request (`push no tags` workflow).
- For historical detail of intermediate beta checkpoints, see the `1.0.14-beta.*` entries below.

## [1.0.14-beta.8] - 2026-03-22

### Added
- Added Restoration Shaman `Healing Stream Totem` support to tracked/core spell logic and spell audit output.
- Added active-totem detection so `Healing Stream Totem` is recommended when ready but not already active.

### Fixed
- Hardened Discipline combat visibility so core entries do not collapse unexpectedly during combat state changes.
- Updated Disc `Penance` and `Power Word: Radiance` readiness checks to use charge-aware availability.

## [1.0.14-beta.7] - 2026-03-22

### Fixed
- Updated Discipline `Penance` and `Power Word: Radiance` glow conditions to trigger only at max charges.
- Prevented constant glow on those Disc entries when charges are not capped.

## [1.0.14-beta.6] - 2026-03-22

### Fixed
- Added explicit Discipline Priest core tracking and glow-rule wiring for `Penance` and `Power Word: Radiance`.
- Added `alwaysWhenShown` glow mode and applied it to Disc `Penance`/`Radiance` so glow behavior is consistent when those entries are active.
- Extended `/hpm audit` spell reporting to include Disc `Penance` and `Power Word: Radiance` resolution.

## [1.0.14-beta.5] - 2026-03-22

### Changed
- Tuned glow visuals to sit further outside the icon bounds for clearer edge separation.
- Increased glow brightness and pulse floor so highlights stay more visible in combat.

## [1.0.14-beta.4] - 2026-03-22

### Fixed
- Reworked icon glow rendering to use an icon-local border glow so the effect is properly aligned on compact icon sizes.

### Added
- Added a General options checkbox (`Show glows`) to enable/disable glow highlights in the UI.
- Synced `/hpm glow on|off` with options controls so the checkbox state updates immediately.

## [1.0.14-beta.3] - 2026-03-22

### Fixed
- Switched icon glow rendering to Blizzard's native overlay glow API with compatibility fallback.
- Prevented partial/clipped glow visuals by improving glow show/hide lifecycle handling.

## [1.0.14-beta.2] - 2026-03-22

### Added
- Added a Devtools tab in options with live recommendation logging toggle.
- Added an in-game debug log window with live tail, clear, and close controls.

### Changed
- Improved recommendation consistency for aura-maintenance and charge-based spells across healer specs.
- Refined options layout with clearer two-section organization (General and Devtools).

### Removed
- Removed obsolete Undergrowth mode logic and related command/UI paths for current Retail behavior.

## [1.0.14-beta.1] - 2026-03-21

### Added
- Added conditional icon glow support for threshold-based readiness cues.
- Added `Renewing Mist` glow condition when charges are fully capped (all uses available).
- Added `Lightweaver` glow condition when player aura stacks reach threshold.
- Added `/hpm glow on|off` to enable/disable conditional glow highlights.
- Added `/hpm glowdebug on|off` for guarded glow decision diagnostics.
- Added options UI controls to add/remove custom tracked spells using a class-spell dropdown and `Add` button.
- Added custom tracked spell rendering to the icon row when those spells are known and ready.

### Changed
- Glow condition evaluators use secret/protected-safe coercion and fail-safe defaults to avoid PW:S-style restricted-value regressions.
- Added persistence sanitization and deduplication for custom tracked spell IDs.
- Custom tracked spell configuration is now character-specific.

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
