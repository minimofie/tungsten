# Tungsten — round 1, part 1.4 checklist (11 items)

Install: replace `workspace/Tungsten/` with the folder from `Tungsten_p1_4.zip`.
Keep the Script Viewer on. Report pass / fail per item; for a failure say what
you saw, any `[x]` line (`/trace`) and the newest file in `Tungsten/logs/`.

Set up (paste into the console, one line):
`> local t = { speed = 3, tag = "a" } ; t.self = t ; local function helper() return t end ; f = function(a) print("Touched", 5, a) return helper end`
then `/load $f` and open the Script Viewer tab.

## A. The views
- **A1** The sub-tab that was "Table" is now **Contents**.
- **A2** Constants, Upvalues and Contents offer **Tree, List, Table, Function**; Functions offers Tree, List, Table.

## B. Table view
- **B1** Constants › **Table**: the constants written as a Luau table (`{ "Touched", 5, … }`), with colours; can be selected, not typed into.
- **B2** Upvalues › **Table**: `helper` shows as `KEEP --[[ function helper ]]` (functions can't be written as text).
- **B3** Load the table itself (`> tt = { speed = 3, sub = { a = 1 } }`, `/load $tt`), Contents › **Table**: `speed = 3`, `sub = { a = 1, }`.
- **B4** A table that holds itself shows `KEEP --[[ a table shown earlier … ]]` where it repeats.

## C. Function view
- **C1** `/load $f`, Constants › **Function**: a heading for `f` (main) with its constants under it, then a heading per nested function (if any) with theirs.
- **C2** Upvalues › **Function**: `f`'s upvalues, then a `helper` heading with helper's own upvalues (the table `t`).
- **C3** Double-click a heading: it closes; again: it opens. Tables under a heading still open with ▸.
- **C4** Load a required ModuleScript that returns a table of functions: Contents › **Function** lists each function (by its key, e.g. `Sub.Helper`) with its upvalues.

## D. Kept
- **D1** Run `Tungsten.luau` again: each sub-tab keeps its view; the plugin's page shows the four view settings.
