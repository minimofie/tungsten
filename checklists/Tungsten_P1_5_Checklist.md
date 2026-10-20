# Tungsten — round 1, part 1.5 checklist (10 items)

Install: replace `workspace/Tungsten/` with the folder from `Tungsten_p1_5.zip`.
Keep the Script Viewer on. Report pass / fail per item; for a failure say what
you saw, any `[x]` line (`/trace`) and the newest file in `Tungsten/logs/`.

## A. Start
- **A1** Welcome line shows `46/46 executor functions` (filtergc added).

## B. Constants
- **B1** Load a function from the game: pick a required ModuleScript that returns a table of functions and run e.g. `> fn = require(game.ReplicatedStorage.SomeModule).SomeFunction` then `/load $fn` (functions you make in the console are the executor's and are left out of searches). Open Constants: a **References** area sits under the list with "select a constant or an upvalue".
- **B2** Select a string constant: "searching…", then a list of other functions using that constant, with Where (`constant N`) and Source (`script:line`). The function you're looking at is first, marked "(this one)".
- **B3** The game keeps running while it searches.
- **B4** Double-click a reference: that function is loaded; the viewer shows it.

## C. Upvalues
- **C1** Select a table upvalue: every function holding that same table is listed (`upvalue N`).
- **C2** Open the table and select one of its entries: the area says references are found for constants and upvalues.
- **C3** Select another row while a search is still running: only the newest selection's results end up shown.

## D. Other views
- **D1** Constants › Function view: selecting a constant under a nested function's heading searches for it too.
- **D2** Constants › Table view: the References area is hidden; back to Tree shows it again.
