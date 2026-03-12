# HealingPriorityMouse

Display-only addon version of the `Healing Priority @ Mouse - FredJones` WeakAura. 

> Warning: This addon was completly vibecoded for fun, so not everything is going to make sense, I don't know a single thing about proper addon development or LUA.

## What It Does

- Shows a compact icon row near your cursor for healer priorities.
- Uses modern Retail APIs (`C_UnitAuras`, `C_Spell`) suitable for current patch lines.
- Does not perform protected actions (no auto-cast, no targeting automation).

## Slash Commands

- `/hpm` or `/healingprioritymouse`: print status and active options
- `/hpm options`: open in-game options window
- `/hpm version`: print current addon version
- `/hpm toggle`: enable/disable addon display
- `/hpm undergrowth on|off|auto`: control Lifebloom target count logic
- `/hpm scale <number>`: set icon scale from `0.6` to `3.0` (example: `/hpm scale 1.2`)
- `/hpm opacity <0-100>`: set icon opacity percentage
- `/hpm names on|off`: show or hide spell names under/over icons
- `/hpm namepos top|bottom`: set spell name position
- `/hpm charges on|off`: toggle charge count overlay on icons
- `/hpm audit`: verify which tracked spell IDs resolve on your current client build
