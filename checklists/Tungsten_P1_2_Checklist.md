# Tungsten — round 1, part 1.2 checklist (14 items)

Install: replace `workspace/Tungsten/` with the folder from `Tungsten_p1_2.zip`.
Keep the Script Viewer on (Plugins tab). Report pass / fail per item; for a
failure say what you saw, any `[x]` line (`/trace`) and the newest file in
`Tungsten/logs/`.

Set up a function to look at (paste into the console, one line):
`> local t = { speed = 3, nested = { a = 1 } } ; t.self = t ; local function helper() return t end ; f = function(a) print("Touched", 5, a) return helper end`
then `/load $f` and open the Script Viewer tab.

## A. Pills and counts
- **A1** Four sub-tabs: Overview, Constants, Upvalues, Functions. Constants, Upvalues and Functions show counts in orange badges before you open them.

## B. Constants
- **B1** Constants lists the function's constants ("Touched", 5, print…) with Type and Value; the bar says how many.
- **B2** Plugins › Script Viewer page › "Show empty constant slots" on: any empty slots appear marked `(empty slot)`; off hides them again.

## C. Upvalues (Tree)
- **C1** Upvalues shows `helper` as a function row with ▸; double-click opens it into its own upvalues (the table `t`).
- **C2** Double-click the table: its entries appear under it (`nested`, `self`, `speed`), indented.
- **C3** `self` is marked `(cycle)` and doesn't open.
- **C4** Double-click an open row again: it closes.

## D. List view
- **D1** Switch the Upvalues dropdown to **List**: every row shows its path (e.g. `upvalue 1↑1.speed`) instead of indentation.
- **D2** Run `Tungsten.luau` again, load `$f` again: Upvalues is still in List (the view is saved).
- **D3** The plugin's page shows the three view settings; changing one there switches the open panel.

## E. Functions and other things
- **E1** Load a running LocalScript: Functions lists its nested functions with Params / Upvalues / Constants / Nested; ones with nested functions open with ▸.
- **E2** Its Upvalues bar says the main function is compiled again (no running upvalues).
- **E3** `> p = print` then `/load $p`: the three panels are empty and say why; no badges.
- **E4** Load a big ModuleScript-returned table or anything with hundreds of entries in an upvalue: it opens without freezing, with a "… N more" row past 500.
