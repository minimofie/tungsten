# Script Viewer

The Script Viewer inspects what is loaded (the path bar shows it): a LocalScript, a ModuleScript, a function, a nested function or a table. It ships with Tungsten and starts off; turn it on in the **Plugins** tab.

Changes are made in the game's memory for this session only: nothing is written to a script's source, nothing replicates, and a rejoin resets them. Every change can be undone with `/undo`.

## What you can load

| Loaded | What the sub-tabs show |
|---|---|
| a LocalScript | its source, the constants of its bytecode, its running functions' upvalues, its running functions and nested functions |
| a ModuleScript | the same, and under **Contents** the table it returned (once the game has required it) |
| a function | its constants, upvalues and nested functions |
| a nested function | its constants (shared by every copy of it), its running copies' upvalues, its own nested functions |
| a table | its entries under **Contents** |

The line under the title says what it is (hover it for notes).

## Sub-tabs

- **Source**: the decompiled script, read-only. It decompiles when you open the sub-tab. **Copy** copies it; **Decompile again** runs it once more.
- **Constants**: the numbers, text and other fixed values in the bytecode.
- **Upvalues**: the variables a function captured from around it. A script's are in its running functions (the viewer finds them in memory), one heading per function. A loaded table (or what a ModuleScript returned) shows the upvalues of every function inside it, named by its keys (`fire   Weapons.fire`).
- **Functions**: the functions, with a details pane (below).
- **Contents**: a table's entries.

The pill on each sub-tab counts its rows.

## Views

Each data sub-tab has a view dropdown on its toolbar (it is remembered):

| View | Use it to |
|---|---|
| **Tree** | explore and change things in place: rows open into tables, functions and their upvalues |
| **List** | find things: every row flat with its full path, a **search** box (keys, paths and values) and a **type filter** (string, number, boolean, table, function, Instance, other), with an "N of M" count. For example: every number constant (tuning values), or a remote's name |
| **Table** | bulk changes and copying: the rows as a Luau table. Edit the text and press **Apply** (only what changed is written, all or nothing), or **Revert**. Values that can't be written as text show as `KEEP` and stay as they are. Very long tables stop at 20,000 entries; the rest are `KEEP` |

The work area scrolls when the window is small, so the list keeps a useful height.

## Scope

**Constants** and **Upvalues** have a scope dropdown:

- **This function**: only its own.
- **With nested functions**: also every nested function's constants, or the upvalues of the running copies of its nested functions, each under a heading. Click a heading to close or open it.

## Searching every function

Upvalues › scope **Search all functions** looks through every function the game has in memory (Tungsten's and the executor's own are left out) for upvalues that match what you type: text (any part of it, any case), a number, or the name of a function or an object. Press **Search** (or Enter). Turn on **Search inside tables** to look at the keys and values of table upvalues too: a matching table opens into just the entries that matched. Each function found is a heading with its source and line; its upvalues can be changed, inspected and copied like any other row. At most 200 functions are listed.

## References

The **References** toggle on the toolbar shows, under the list, the other functions that use the selected constant or hold the selected upvalue. Double-click one to load it. It is off by default (it searches memory).

## Functions and the details pane

The **Functions** list shows a function's nested functions (with their line, parameters, upvalue, constant and nested counts). For a script it shows **Running** (its running functions) and **In the bytecode** (the nested functions of its bytecode).

Pick a row to see its details: kind, source and line, parameters, counts, hash, how many running copies it has, and its path. The buttons:

| Button | What it does |
|---|---|
| **Inspect** | loads it and opens Constants |
| **Load** | loads it and stays on Functions |
| **Running copy…** | a nested function: loads one of its running copies (asks which when there are several) and opens Upvalues |
| **Keep in a variable…** | puts it in a `$variable` |
| **Copy path** | copies the code that reaches it, e.g. `debug.getproto(require(game.ReplicatedStorage.Combat).swing, 1)` |
| **Copy hash** | copies its hash |

## Nested functions and running copies

A nested function is the function a function defines inside itself. Its prototype (the compiled code) holds its constants and its own nested functions; every copy the game made of it shares them, so changing one changes them for all. The **running copies** are the functions the game made from it; each has its own upvalues. Load one with **Running copy…**, or see them all under **Upvalues** when the nested function is loaded.

A nested function from a script's bytecode is a copy compiled again from the bytecode: changes to it go to the script's running functions that match it, and are refused when none runs.

## Changing values

Right-click a row for its menu, or double-click a row that doesn't open:

- **Change value…**: a form with one value field: a **Type** dropdown that offers only the types that fit, and the value. A constant keeps its type unless **Constants may change type** is on (Plugins › Script Viewer). Pick **variable** as the type to take a `$variable`'s value instead (the box turns into a list of variables); that is also how an upvalue or entry changes to another type.
- **Set to nil** / **Remove entry** (in red).
- **Add entry to …**: a key and a value (from text, or a variable).
- **Rename key…**.
- **Inspect**: loads a table, function, nested function or Instance and opens the sub-tab that fits. The path bar shows where it is: through tables, upvalues and nested functions, e.g. `debug.getupvalues(require(game.ReplicatedStorage.Mod).fire)[2].Damage`.
- **Load (stay here)** and **Inspect running copy…** on Functions rows.
- **Keep in a variable…** (it suggests a name), **Copy value**, and **Copy path** where code can reach the value.

A read-only table is made writable only after you confirm, and read-only again straight after.

## Settings

Plugins › Script Viewer: the view of each sub-tab, the scope of Constants and Upvalues, **Show references**, **Show empty constant slots** and **Constants may change type**.
