# HealingPriorityMouse

Display-only addon version of the `Healing Priority @ Mouse - FredJones` WeakAura. 

> Warning: This addon was completly vibecoded for fun, so not everything is going to make sense, I don't know a single thing about proper addon development or LUA.

## What It Does

- Shows a compact icon row near your cursor for healer priorities.
- Adds a movable minimap button for opening the in-game options window quickly.
- Lets you add your own additional tracked spells from an in-game class spell dropdown or by manual spell ID / shift-clicked spell link / exact spell name.
- Adds optional borders for the main cursor-following spell icons.
- Keeps custom tracked spell lists character-specific to avoid cross-character bleed.
- Uses modern Retail APIs (`C_UnitAuras`, `C_Spell`) suitable for current patch lines.
- Does not perform protected actions (no auto-cast, no targeting automation).

## Slash Commands

- `/hpm` or `/healingprioritymouse`: print status and active options
- `/hpm options`: open in-game options window
- `/hpm version`: print current addon version
- `/hpm toggle`: enable/disable addon display
- `/hpm scale <number>`: set icon scale from `0.6` to `3.0` (example: `/hpm scale 1.2`)
- `/hpm opacity <0-100>`: set icon opacity percentage
- `/hpm names on|off`: show or hide spell names under/over icons
- `/hpm namepos top|bottom`: set spell name position
- `/hpm charges on|off`: toggle charge count overlay on icons
- `/hpm borders on|off`: toggle icon borders
- `/hpm glow on|off`: toggle conditional icon glow highlights
- `/hpm glowdebug on|off`: toggle glow condition debug messages
- `/hpm audit`: verify which tracked spell IDs resolve on your current client build
- `/hpm apidump <spellID> [moreSpellIDs]`: print cooldown/charges/duration-object diagnostics for one or more spells

## Minimap Icon

- Left-drag the minimap button to move it around the minimap edge.
- Right-click the minimap button to open the options window.
- To use a custom icon, place a square texture at `Interface/AddOns/HealingPriorityMouse/Media/MinimapIcon`.
- The addon will try that custom texture first, then fall back to the built-in gold cross icon if the file is missing.
