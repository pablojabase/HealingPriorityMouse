# Changelog

All notable changes to this project are documented in this file.

## [Unreleased]

### Changed
- Coalesced back-to-back `SPELL_UPDATE_COOLDOWN` and `SPELL_UPDATE_CHARGES` events into a single queued refresh pass to reduce redundant recomputation during high event churn.
- Coalesced Cooldown Viewer metadata update events (`COOLDOWN_VIEWER_*`) behind a versioned deferred refresh so stale callbacks cannot trigger duplicate refresh work.

### Fixed
- Reworked minimap-button dragging/positioning to follow the LibDBIcon-style behavior used by addons like VuhDo and KeystonePolaris (more consistent hover-ring movement around minimap shapes).

## [2.1.1] - 2026-04-23

### Changed
- Refined tracked-spell options layout so manual-add controls and helper text stay within the options window bounds on resize.

### Fixed
- Added explicit shift-click spell-link insertion support for the manual tracked-spell input when that box is focused.
- Improved manual spell-name resolution by using direct spell identifier/name APIs before class-option fallback.

## [2.1.0] - 2026-04-23

### Added
- Added a new CDM-hybrid cooldown provider layer that builds spell-ID alias maps from Blizzard Cooldown Viewer metadata (`C_CooldownViewer`) while keeping native spell API fallback paths.
- Added a coalesced refresh queue with timer-based wake scheduling so icon refreshes can be batched and woken near predicted cooldown/charge completion times.
- Added optional developer CPU/memory sampling controls in Devtools and slash commands (`/hpm perf on|off|sample`) backed by safe addon metrics snapshots.
- Added provider diagnostics and runtime service diagnostics to `/hpm apidump`, including provider status, queue state, and latest perf sample fields.

### Changed
- Extended runtime candidate spell resolution to merge native override/base discovery with provider-sourced alias relationships for more stable cooldown-source matching.
- Added provider mode controls (`CDM Hybrid` vs `Native`) to Devtools and slash commands (`/hpm provider native|cdm-hybrid`).
- Moved new migration service state onto a shared runtime table to stay under Lua top-level local limits and avoid `main function has more than 200 local variables` warnings.

### Fixed
- Hardened cast-time readiness transitions for tracked single-cooldown spells (for example `Lay on Hands`) so combat cast events immediately fail closed instead of briefly reusing stale ready cache state.
- Reduced multi-charge icon flicker after spending one charge by reusing cached/estimated charge state during transient unknown payloads and mirroring cast-updated charge cache across runtime candidate spell IDs.

## [2.0.4] - 2026-04-22

### Fixed
- Hardened additional secret/tainted-value read paths beyond the initial `2.0.3` scope, including cooldown/charge table normalization, duration-object diagnostic reads, and Atonement cache key access.
- Added guarded equality and unit-resolution checks in aura ownership matching to reduce new 12.0.5 secret-value comparison/indexing errors reported by users.

## [2.0.3] - 2026-04-22

### Added
- Promoted `2.0.3-beta.1` tracked-spell and icon-border improvements to full release.

### Fixed
- Hardened AuraData field reads in the Atonement cache/count paths to avoid `12.0.5` secret-key indexing errors in combat/encounter-restricted contexts.

### Changed
- Updated addon compatibility metadata for Retail `12.0.5` by setting TOC `Interface` to `120005`.

## [2.0.3-beta.1] - 2026-04-18

### Added
- Expanded the native tracked-spell picker to include the current class's healer spell pool instead of only the active healer spec, making off-spec setup easier.
- Added manual tracked-spell entry in the options panel via spell ID, shift-clicked spell link, or exact spell name so missing spells no longer require Lua edits.
- Added optional borders for the main cursor-following spell icons, with both options-panel and slash-command control.
- Added `Verdant Embrace` to the Preservation Evoker tracked-spell pool.

## [2.0.2] - 2026-04-03

### Fixed
- Removed the remaining Atonement aura-name fallback from the combat cache matcher so secret-string clients stop throwing comparison errors during `UNIT_AURA` processing.

## [2.0.1] - 2026-04-03

### Fixed
- Reduced Priest combat CPU and allocation pressure by moving `Atonement` counting onto a cached `UNIT_AURA`-driven path instead of rescanning group auras during normal refreshes.
- Stopped invalidating the shared spell runtime cache on group aura, mouseover, roster, and power events that do not actually change cooldown state.

## [2.0.0] - 2026-04-03

### Added
- Added a movable minimap button with custom texture fallback support for quick access to the in-game options window.
- Expanded the addable tracked-spell pool for Restoration Druids with `Nature's Cure`, `Nature's Swiftness`, `Convoke the Spirits`, `Incarnation: Tree of Life`, and `Innervate`.
- Expanded the addable tracked-spell pool for Mistweaver Monks with `Rushing Wind Kick` and `Rising Sun Kick`.
- Added a `Remove All` tracked-spells button in the options panel to clear the current character's tracked list in one action.

### Changed
- Rebuilt the internal spell cooldown runtime around normalized cooldown/charge reads, override-aware spell ID resolution, cached per-spell runtime state, and duration-object support while keeping the addon's recommendation capabilities the same.
- Routed shared readiness checks, charge display decisions, combat cache handling, and icon cooldown swipe rendering through the new canonical spell runtime instead of ad hoc direct API reads.
- Updated the minimap button interaction model so left-drag moves the icon and right-click opens options.
- Converted built-in healer defaults into pre-populated tracked spells that can be removed by the user, instead of treating them as untouchable core-managed entries.
- Allowed tracked class spells such as `Innervate` to be added and shown from non-healer specs as long as the character knows the spell.
- Made policy-driven counter entries such as `Atonement` addable through the tracked-spell picker even when they are not treated as normal known castable spells.

### Fixed
- Reduced the risk of spell display regressions caused by override spell IDs, GCD contamination, mismatched cooldown sources, and desynced cooldown-vs-charge reads.
- Improved cooldown swipe fidelity by preferring Blizzard duration objects for real cooldowns when available instead of relying only on raw start/duration pairs.
- Hardened Disc `Atonement` counting by matching player-owned aura variants more reliably instead of assuming a single aura identity and a single player unit token.
- Added a Disc-specific Atonement combat fallback that uses raid-combat-aware aura scans and event-driven cache updates so the in-icon count does not stick at `0` during combat.
- Reworked the Atonement combat fallback to use `UNIT_AURA` update info instead of direct combat-log event registration, avoiding reload-time protected-call failures on current clients.
- Removed direct secret-string comparisons from the Atonement aura-matching path so contingent aura scans fail closed instead of throwing Midnight taint errors.

### Known Issues
- `Renewing Mist` charge overlays can still lag behind the game by a few seconds in some combat recharge scenarios, even after recent responsiveness improvements.
- Discipline `Atonement` in-combat counting has been substantially hardened for `2.0.0`, but may still need follow-up if live aura payloads stay inconsistent on some clients.

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
