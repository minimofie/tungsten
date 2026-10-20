# Tungsten — Script Viewer revamp checklist (32 items)

Install: replace `workspace/Tungsten/` with the folder from `Tungsten_revamp.zip`
(or run the web loader line in `README.md`:
`loadstring(request({ Url = "https://raw.githubusercontent.com/minimofie/tungsten/HEAD/loader.luau" }).Body)()`). Turn on the Script Viewer in the Plugins tab if it is off.
Report pass / fail per item; for a failure say what you saw, any `[x]` line
(`/trace`) and the newest file in `Tungsten/logs/`.

Below, `game.ReplicatedStorage.Mod` is a ModuleScript the game has required
that returns a table with a function `Mod.fn` that has nested functions;
use your own names. A LocalScript that is running is `<Script>`.

## A. Path bar
- **A1** The path bar has ⟳ right of →. With nothing loaded it is greyed; hovering says "Nothing loaded".
- **A2** Load anything, press ⟳: it loads again (the Script Viewer redraws); ← still goes to what was before, not to the same thing.
- **A3** Load an upvalue (Script Viewer › Upvalues › right-click a table upvalue › **Inspect**), change that upvalue in the game (or with Change value…), press ⟳: the new value shows.
- **A4** `> door = workspace.<a part>` then type `$door` in the path bar + Enter: the part is loaded. `$nope`: the bar says it doesn't exist.
- **A5** Type `debug.getproto(require(game.ReplicatedStorage.Mod).fn, 1)` + Enter: loaded; the bar ends in `nested 1`; ⌄ › Copy gives that code. `/load` takes the same text.

## B. Work area and views
- **B1** Constants, Upvalues, Contents: the list fills the sub-tab (no fixed strip under it). Make the window small (window size setting): the work area scrolls instead of squashing the list.
- **B2** The **References** toggle on the toolbar shows the References area under the list (the list keeps a good height); off again hides it. The setting is remembered (Plugins › Script Viewer › Show references).
- **B3** The view dropdown offers **Tree, List, Table** only (no Function).
- **B4** Load a big function or module (many constants / entries). Switch between Tree, List and Table quickly several times: the dropdown always shows the view that is shown; nothing breaks; no `dropdown callback failed` in the log.
- **B5** **List**: rows are flat with full paths and a search box, a type dropdown and a count. Type part of a key or value: only matching rows, "N of M". Type **number**: only numbers.
- **B6** **Table** on a very long table: a note at the top says the text stops at 20,000 entries; Apply still works on what is shown.
- **B7** Constants › scope **With nested functions**: a heading per function (main, then each nested one) with its constants; click a heading to close / open it. Upvalues › the same scope adds the running copies of nested functions under headings.

## C. Menus
- **C1** Nowhere says "Look into it"; tables, functions and objects have **Inspect**.
- **C2** Right-click a number or string constant: no Copy path (only Change value…, Keep in a variable…, Copy value).
- **C3** Right-click a table upvalue › **Copy path**: `debug.getupvalues(…)[N]` (real code, never a number). An object upvalue's Copy path: its path (`game.Workspace.…`).
- **C4** **Inspect** a table: Contents opens with it. Inspect a function from Upvalues: Upvalues stays open; from Contents: Constants opens. The path bar shows where it is.

## D. Functions
- **D1** Load `Mod.fn`, open Functions: its nested functions with Line, Params, Upvalues, Constants, Nested; a details pane on the right ("Select a function").
- **D2** Pick a row: the pane shows kind, source:line, parameters, counts, code hash, running copies and its path.
- **D3** **Copy path** gives `debug.getproto(require(game.ReplicatedStorage.Mod).fn, N)`; **Copy hash** copies a number.
- **D4** **Load**: it is loaded and Functions stays open. **Inspect**: it is loaded and Constants opens; the line under the title says "nested function".
- **D5** A loaded nested function: Constants shows its constants; **Change value…** on one works (and `/undo` puts it back).
- **D6** A loaded nested function: Upvalues shows each running copy ("running 1", …) with its upvalues; changing one works.
- **D7** **Running copy…** on a nested function with copies: loads it (asks which when there are several), Upvalues opens, the bar ends in `nested N · running K`.
- **D8** Load `<Script>`, Functions: **Running** (its running functions) and **In the bytecode** (its nested functions). A bytecode one's path says "no path reaches it"; its running copies count is shown.
- **D9** Inspect a bytecode nested function and change a constant: it is written to its running copy (or refused with why when none runs).

## E. Forms and variables
- **E1** Change value… on a string constant: one Value row: a Type dropdown with **string** and **variable** only.
- **E2** Change value… on a number upvalue: types are string, number, boolean, nil, variable. On a table upvalue: table, nil, variable. On an object: Instance, nil, variable.
- **E3** Pick **variable**: the text box turns into a list of your `$variables` with their types. Pick one + OK: the value is set from it.
- **E4** Add entry… on a table: the value can be a variable too.
- **E5** Keep in a variable… suggests a name from the row's key.

## F. General
- **F1** Docs tab: a **Script Viewer** page describes all of the above. The explorer page mentions ⟳, `$name` and nested paths.
- **F2** Re-run Tungsten with the Script Viewer open: no errors, no doubled rows or menus.
