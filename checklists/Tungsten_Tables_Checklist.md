# Tungsten — inside tables checklist (10 items)

Install: run the web loader line (it updates only what changed):
`loadstring(request({ Url = "https://raw.githubusercontent.com/minimofie/tungsten/HEAD/loader.luau" }).Body)()`
or replace `workspace/Tungsten/` with the folder from `Tungsten_tables.zip`.
Report pass / fail per item; for a failure say what you saw, any `[x]` line
(`/trace`) and the newest file in `Tungsten/logs/`.

Load a table with functions in it: e.g. a required ModuleScript's table
(path bar: click its `require()` part), called `Mod` below.

- **T1** Contents › view dropdown: **Tree, Deep, List, Table**. Deep is only on Contents.
- **T2** Deep: open a function row: **Constants**, **Upvalues** and **Nested functions** under it, each saying how many (empty ones are left out).
- **T3** Open Constants: its numbers and text. Right-click one › Change value…: it changes (`/undo` puts it back).
- **T4** Open Upvalues: its upvalues. Change a string or number upvalue: it changes. Open a table upvalue and change an entry: it changes.
- **T5** Right-click a table upvalue › Copy path: `debug.getupvalues(require(game.….Mod).fn)[N]`; an entry in it: `…)[N].key`.
- **T6** Open Nested functions › a nested function: its constants; change one: it changes. Copy path on the nested function: `debug.getproto(require(…).fn, N)`.
- **T7** Strings and numbers straight in the table (and in tables inside it) change with Change value… as before.
- **T8** Tree view: a function still opens into only its upvalues (Deep is the "everything" view).
- **T9** Constants sub-tab with the table loaded: a heading per function in the table, named by its keys (`fn   Weapons.fn`), with its constants, changeable.
- **T10** Functions sub-tab with the table loaded: its functions by key path; pick one: the details pane's Path is `require(…).Weapons.fn`.
