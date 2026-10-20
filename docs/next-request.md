# Next task: the Script Viewer revamp (12 items)

**Status: built (20 Oct 2026)** in six steps, each committed with every suite green; delivered as `Tungsten_revamp.zip` with `checklists/Tungsten_Revamp_Checklist.md`. What was built follows the proposed design below; differences: References is a toolbar toggle that is off by default; the variable picker lists every variable for upvalues and entries (a variable is how one changes type) and only constant-shaped ones for constants. Hooks (`hookfunction`, `hookproto`) are left for round 3 (Q13).

## The request (word for word, 19 Oct 2026)

> 1. the ui workspace in the view modes on the editor tabs (upvalues, constants, etc) are too small. increase their size and make the subtabs' workspace scrollable to increase space to work with them
> 2. the dropdown for the view mode selector breaks if a large function with many values is loaded. fix this
> 3. there seems to be no difference between the function and tree view modes. either add different functionality to the function view mode or remove it if redundant.
> 4. the copy path dropdowns in certain instances do not do anything or just copy a number. either make them work or remove them if they are not necessary. make sure that if a copy path option exists, an inspect option exists which functions similarly to the "look into" option
> 5. add a refresh button to the right of the path enter button on the path bar which reloads the currently loaded path.
> 6. differentiate the view modes so that they actually have a use and arent redundant. think of possible use cases for viewing different elements in a script/module.
> 7. change "look into" to "inspect" across all tabs
> 8. revamp the functions tab to actually display useful information, and give them the proper links such as "load" or "inspect". i want to be able to look inside a function and view or edit any info i need to. this will be expanded upon in the next entry.
> 9. add the ability to inspect functions and edit constants,  upvalues, and any other relevant changes that hydroxide makes. make sure that type selectors remain usable and display only relevant types whenever editing values.
> 10. perform a pass and make sure that a broad spectrum of editing and viewing all elements of scripts/modules are available to the user.
> 11. make sure that variables also have functionality where necessary in all functions. this is important.
> 12. streamline the user experience, deprecate redundancies, and perform a bug fix pass
>
> find a good stopping point and pause if usage approaches a limit.

Item 9 names a reference project. It is there for feature ideas only, and **its name must never appear in Tungsten's code, UI, docs, logs or file names.** Describe the features in Tungsten's own words, e.g. "edit a running closure's upvalues" or "nested functions and their running copies".

## What the current code does (so the items make sense)

- **Data sub-tabs:** Constants, Upvalues, Functions and Contents have a mode dropdown with Tree / List / Table / Function.
  - **Function** groups rows under headings per function:
    - Constants: main plus nested protos
    - Upvalues: the function plus functions held as upvalues
    - Contents: functions in the table with their upvalues
  - For a function without nested functions it looks the same as Tree. That is item 3.
- **Panel layout:** each panel has a fixed-height References area (150 px) under the list. The panel body doesn't scroll. That is item 1.
- **Mode switching:** a mode change runs synchronously from the Dropdown's `OnChanged`: `api.settings.set`, then `settings.Changed`, then `_makeList` and `_fill`.
  - For a big function the Function/Table work is heavy. If it errors, the dropdown is left inconsistent ("dropdown callback failed" in the log). That is item 2's likely cause; it wasn't reproduced offline.
  - List and TextEditor are virtualized, so the row count alone isn't the problem.
- **Copy path (item 4):** copies `node.Path`, which for constants and upvalues is text like `constant 3` or a bare index.
  - "Look into it" exists only for tables and Luau functions.
  - `Actions.accessOf` already works out real paths for the path bar, through `base/access`.
- **Edit forms:** Change value… offers a Type dropdown.
  - Constants offer their own type only, or string, number and boolean with the setting "Constants may change type" on.
  - Upvalues and entries offer 15 types: string, number, boolean, nil, table, Vector3, Vector2, Color3, CFrame, UDim2, UDim, BrickColor, EnumItem, Instance, function.
  - `$variables` are accepted in the value text for most types (`Types.parse`) and are required for functions. There is no variable picker.

## Proposed design (not yet confirmed by the user)

### 1. Layout
- The data panel body becomes a vertical `Scroll` whose content has a minimum height (about 560–620 px), so small windows scroll the sub-tab rather than squash it.
- The list gets most of the height (a minimum of about 420 px).
- References becomes a toolbar toggle ("References"). When it is off, the list takes the full height. When on, it is about 180–220 px.

### 2. Mode switching that can't break
- Defer the work out of the dropdown callback (`task.defer`) and guard it with `pcall`.
- On failure, show the reason in the panel's info line and keep the dropdown in step with `panel.Mode`.
- Add a stale-guard token so a newer switch wins.
- Cap the Table text at a sensible size, with a note when it is capped.

### 3 and 6. Distinct view modes, each with a use
| Mode | Use | What's different |
| --- | --- | --- |
| Tree | explore and edit in place | rows open into tables, functions and upvalues |
| List | find things | flat rows with full paths, a **search box** (key, path, value text) and a **type filter** (any, string, number, boolean, table, function, Instance, other), plus a "N of M" count; e.g. "find every number" (tuning values) or "find a remote name" |
| Table | bulk edit and copy | the Luau literal, editable, Apply / Revert |

- Remove the **Function** mode.
- Replace it with a **Scope** choice on Constants and Upvalues: "This function" or "With nested functions".
  - Constants: main plus every nested proto, under headings.
  - Upvalues: the function's own plus the upvalues of the **running copies of its nested functions**, from `debug.getproto(f, i, true)`.
  - For scripts, Upvalues already shows the running functions under headings.
- Remove the Contents "by function" view.

### 4 and 7. Menus
- Rename "Look into it" to **"Inspect"** everywhere: code, docs, checklists text, tests.
- Inspect applies to tables, Luau functions, nested functions (ProtoProxy) and Instances.
  - It keeps the current sub-tab when that sub-tab applies to the new kind; otherwise a function opens on Constants and a table on Contents.
- **Copy path** shows only when Inspect applies and a real path exists. It copies the code from `base/access`, e.g. `require(game.ReplicatedStorage.M).Sub.fn`.
- Otherwise only **Copy value** is offered.
- Extend `base/access` with steps for nested functions:
  - `{Kind="proto", Index}`: `debug.getproto(f, i)`
  - `{Kind="closure", Index, Copy}`: `debug.getproto(f, i, true)[k]`
  - Include parse, resolve and code for them, plus crumbs ("nested 2", "nested 2 · running 1").

### 5. Path bar refresh button
- Add ⟳ to the right of → (so → moves one slot left).
- It calls a new `Loaded.reload()`:
  - targets with an `Access` are resolved again to their current value
  - Instances reload as they are
  - it does not push back-history
- Typed `$name` in the path bar loads that variable (Instance, or value as target).

### 8, 9 and 10. Functions sub-tab revamp and function inspector
- **Left side:** a list of functions.
  - For a script or module: a "Running" heading (`Rows.liveFunctions`) and an "In the bytecode" heading (the copy's nested protos tree).
  - For a function: its nested protos, recursive.
  - Columns: Name, Line, Params, Upvalues, Constants, Nested.
- **Right side:** a details pane for the selected row.
  - Facts: name, kind (running closure / nested function prototype / C function / made by the executor), source and line, params and vararg, upvalue, constant and nested counts, `getfunctionhash`, and the number of running copies (for protos, from `debug.getproto(owner, i, true)`, computed only when selected because it scans memory).
  - Its path code, when known.
- **Actions:** Inspect (load it and open Constants), Load (load it and stay), Inspect running copy (for a proto), Keep in a variable…, Copy path, Copy hash.
- **New subject kind "proto"** (a ProtoProxy) in `lib/inspect`:
  - Constants: readable and editable with `debug.setconstant(proxy, …)`.
  - Upvalues: shows its running copies' upvalues, which are editable.
  - Functions: its nested protos.
  - Track where a proxy came from (owner and index, and whether it came from a script's recompiled copy). Protos from a copy map edits to the running functions, like `Edit.constantTargets`.
- **Hooks** (`hookfunction`, `hookproto`) belong to round 3 (scanner/spy, decision Q13). Say so instead of adding them here.

### 9 and 11. Forms, types and variables
- Register a plugin field kind (e.g. `scriptviewer.value`) through `api.prompt.registerFieldKind`. It is one row with a Type dropdown plus a value box that turns into a **variable picker** (dropdown of `api.variables.names()`) when the type is "variable". The value box shows a hint per type (`Types.hint`).
- Relevant types only:
  - constant: its type and "variable"; or string, number, boolean (and vector if current) plus "variable" when the setting is on
  - string, number or boolean: string, number, boolean, nil, variable
  - table: table, nil, variable
  - function: function, nil, variable
  - Instance: Instance, nil, variable
  - a datatype (Vector3 etc.): that type, nil, variable
  - a new entry: string, number, boolean, table, Instance, Vector3, CFrame, Color3, UDim2, EnumItem, function, variable
- "Keep in a variable…" on every row and in the function details pane.

### 12. Streamline and bug pass
- Remove redundancies: the Function mode, the contents-by-function view, duplicate buttons.
- Check reload and re-run, empty states and long text truncation.
- Re-run every suite in both modes.
- Update old tests that use the Function mode or "Look into it": `test_p1d`, `test_p1e`, `test_p1f`, `test_p1g`, `test_access`.

### Suggested order and stopping points
1. Path bar refresh, plus Access proto/closure steps, plus `$var` typed paths (small, platform). Tests.
2. Layout, modes and scope, plus the dropdown fix (`lib/view` rewrite of the data panels). Tests updated.
3. Menus: Inspect, Copy path, Load. Tests.
4. Functions sub-tab, details pane and proto subject. Tests.
5. Forms: field kind, relevant types, variable picker. Tests.
6. Bug pass, docs (topics 06, 09 and a Script Viewer docs page or `docs.md`), package, checklist, then stop.

Each step leaves all suites green, so any step boundary is a clean pause point.

Volt pages to re-check before step 4: `debug.getproto` (activated closures), `debug.getprotos`, `debug.getinfo` (accepts ProtoProxy), `debug.setconstant` (accepts ProtoProxy) and `getfunctionhash` (functions only). Notes are in `docs/volt-api-notes.md`.
