# Tungsten — upvalues fix checklist (14 items)

Install: run the web loader line (it updates only what changed):
`loadstring(request({ Url = "https://raw.githubusercontent.com/minimofie/tungsten/HEAD/loader.luau" }).Body)()`
or replace `workspace/Tungsten/` with the folder from `Tungsten_upvalues.zip`.
Report pass / fail per item; for a failure say what you saw (the Upvalues bar's
text), any `[x]` line (`/trace`) and the newest file in `Tungsten/logs/`.

## A. A script's upvalues
- **A1** Load a running LocalScript from `Players.<you>.PlayerScripts` (or your character): Script Viewer › Upvalues lists its running functions (a heading each) with their upvalues. If it is empty, send the bar's text.
- **A2** Change one of those upvalues (right-click › Change value…): it changes, `/undo` puts it back.
- **A3** A table upvalue opens into its entries (▸); change an entry: it changes.

## B. Tables
- **B1** Load a ModuleScript the game has required that returns a table of functions: Upvalues lists those functions first, named by their keys (`fire   Weapons.fire`), each with its upvalues; then its other running functions.
- **B2** Load that table itself (Contents › right-click › Inspect, or the path bar's `require()` part): the line under the title says `table · N entries · M functions`; Upvalues shows the same functions by key path.
- **B3** Right-click a table upvalue there › **Copy path**: `debug.getupvalues(require(game.….Mod).fire)[N]`. Open it, right-click an entry › Copy path: `…)[N].key`.
- **B4** **Inspect** that table upvalue: the path bar ends in `upvalue N`; ⌄ › Copy gives the same code.
- **B5** Contents: open a nested table and right-click a function in it › Copy path: `require(…).a.b`.

## C. Search all functions
- **C1** Upvalues › scope **Search all functions**: a row with a search box, **Search inside tables** and **Search** shows above the list; the list says to type and press Search.
- **C2** Type a word you expect in a string upvalue (e.g. a remote's or tool's name) + Search: each game function with a matching upvalue, its source and line in the heading; the bar says how many functions were looked at. No hitch longer than a moment.
- **C3** Search a number you expect (e.g. a walk speed): matching number upvalues.
- **C4** Turn on **Search inside tables**, search a key you expect in a table (e.g. `Damage`): table upvalues show "N matching entries" and open into just those entries.
- **C5** Change a result (an upvalue or a table entry): it changes and the row shows the new value.
- **C6** Back to **This function**: the search row hides and the loaded function's own upvalues show.
