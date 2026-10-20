# Tungsten — round 1, part 1.3 checklist (13 items)

Install: replace `workspace/Tungsten/` with the folder from `Tungsten_p1_3.zip`.
Keep the Script Viewer on. Report pass / fail per item; for a failure say what
you saw, any `[x]` line (`/trace`) and the newest file in `Tungsten/logs/`.

## A. Source
- **A1** Six sub-tabs now: Overview, Constants, Upvalues, Functions, Source, Table.
- **A2** Load a LocalScript while on the Overview: nothing decompiles yet (no hitch).
- **A3** Open Source: "Decompiling…", then the code with line numbers and syntax colours. The game keeps running while it decompiles.
- **A4** The code can be selected and scrolled but not typed into.
- **A5** Switch to Overview and back: the code is there straight away (not decompiled again).
- **A6** **Copy**: the console says `copied the source of <name> (N lines)`; pasting elsewhere gives the full source.
- **A7** **Decompile again** decompiles it once more.
- **A8** Load a big script, and while it says "Decompiling…" load a different script: only the second one's code ends up shown.
- **A9** Load something that can't be decompiled (e.g. a server Script in ServerScriptService, if one is visible): the reason shows in place of the code, Copy is greyed.

## B. Table
- **B1** Load a ModuleScript the game has required that returns a table: the Table pill shows a count; the sub-tab lists its entries (numbers first, then names). Tables inside open with ▸ on double-click.
- **B2** Switch Table to **List**: every entry with its path (e.g. `Settings.Speed`).
- **B3** A module the game hasn't required: Table says it isn't required yet (and nothing runs).
- **B4** `> t = { a = 1, b = { c = 2 } }` then `/load $t`: Table shows `a` and `b`; Source says a table has no source.
