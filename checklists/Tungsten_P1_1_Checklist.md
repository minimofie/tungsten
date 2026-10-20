# Tungsten — round 1, part 1.1 checklist (16 items)

Install: replace `workspace/Tungsten/` with the folder from `Tungsten_p1_1.zip`
(it now holds `plugins/ScriptViewer/`). If the P0 test plugin `Viewer/` is
still in `plugins/`, remove it: it uses the same id (`scriptviewer`).

Report pass / fail per item; for a failure say what you saw, any `[x]` line
(`/trace` for details) and the newest file in `Tungsten/logs/`.

## A. Shipping and starting
- **A1** Start Tungsten: welcome shows `integrity ok` and `45/45 executor functions`. If anything is missing, copy the `[!]` line.
- **A2** Plugins tab: a **Script Viewer** card, state **off**, listed before other plugins.
- **A3** Turn it on, run `Tungsten.luau` again: the card says **on**; a Script Viewer tab is in the side bar.
- **A4** Open the tab with nothing loaded: one sub-tab **Overview** with "Nothing loaded" and how to load.

## B. Scripts
- **B1** Load a LocalScript that is running (e.g. from PlayerScripts or your character): Overview shows Class, Path, Hash, Running **yes**, Globals, Constants (main function), Nested functions, and the note "compiled again…".
- **B2** Load a LocalScript that isn't running (e.g. one in StarterPlayerScripts): Running **no**, no Globals row.
- **B3** Load a ModuleScript the game has required (`/find` with the `loadedmodules` search, or one in ReplicatedStorage): Required **yes**, Returns shows its type (and entries for a table).
- **B4** Load a ModuleScript that isn't required yet: Required **no** and the note "requiring it would run it"; the game shouldn't react in any way.

## C. Functions, tables, other values
- **C1** `> f = function(a, b, ...) return a end` then `/load $f`: Kind **Luau function**, Made by **the executor**, Parameters **2 + ...**, a Hash.
- **C2** `> p = print` then `/load $p`: Kind **C function** and the note about C functions; no Hash.
- **C3** `> t = setmetatable({1, 2, a = 1}, {})` then `/load $t`: Entries **3 (2 in order, 1 by key)**, Metatable **yes**, Read-only **no**.
- **C4** Load a Part: its Class and the note "load a script, a ModuleScript…".
- **C5** Load two scripts at once: the first is shown, with the note "2 things are loaded".

## D. Other tabs and stopping
- **D1** With the Console tab open, load a script; then open Script Viewer: it already shows that script.
- **D2** `/plugin off scriptviewer`, run `Tungsten.luau` again: the tab is gone; loading things still works, no `[x]` lines.
- **D3** Turn it back on for the next parts.
