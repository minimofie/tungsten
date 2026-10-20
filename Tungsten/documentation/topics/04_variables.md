# Variables

Variables hold any value for this session: numbers, text, tables, functions and Instances. They are never saved; a rejoin (or running Tungsten again) starts with none.

## Making variables

```
/set a = 5
/set name = "Tungsten"
/text greeting hello there
/set base = workspace.Baseplate
> parts = workspace:GetChildren()
/push list 10
```

- `/set` takes a Luau value, so text needs quotes. `/text` takes the rest of the line as text.
- In `>` and `=` code, assigning a new global makes a variable; assigning `nil` removes it.
- Names use letters, digits and `_`, and don't start with a digit.

`/setas` reads text as a given type, so no Luau is needed:

```
/setas home Vector3 0, 10, 0
/setas tint Color3 #ff8800
/setas floor Material Neon
/setas door Instance game.Workspace.Door
```

## Using variables

| Where | Example |
|---|---|
| Luau code | `> a * 2`, `> $a * 2`, `> base.Size` |
| Command values | `/get a`, `/scale $size`, `/inc kills $bonus` |
| Text | `/echo score: $score`, `/text msg hi $who` |

`$name` and the plain name both work in code; in commands and text use `$name`. An unknown `$name` is an error, so typos don't silently become `nil`.

In command arguments, `$base.Size` or `$list[2]` is worked out as code, and in text `${code}` is replaced by the result: `/echo twice: ${$a * 2}`.

> A variable named like a global (`game`, `workspace`, `math`) hides that global in console code. The console warns when that happens; `/unset` the variable to get the global back. `print`, `warn` and `tungsten` belong to the console and can't be replaced.

`local x = 1` only lasts for that one input; write `x = 1` to keep `x` as a variable.

### var("name")

In Luau code, `var("name")` is the variable called `name` (with or without the `$`), handy when the name is in a string or clashes with a global: `> var("door").Transparency = 1`.

When the variable holds a list of objects, `var` gives it back as a **group** that answers like one object:

| Code | What it does |
|---|---|
| `> var("list1"):Destroy()` | calls `Destroy` on every object in the list |
| `> var("list1").Transparency = 0.5` | sets it on every object |
| `= var("list1").Name` | a table with each object's name |
| `> var("list1")[2]`, `#var("list1")`, `for _, obj in var("list1") do … end` | the objects one by one |

Anything else comes back unchanged. `var("sel")` works the same way, so `> var("sel"):Destroy()` deletes everything selected in the explorer.

## Reserved names

| Name | Holds |
|---|---|
| `$last` | the newest result from code or a command |
| `$sel` | the explorer selection: the object itself, or a table when several are selected; empty when nothing is |
| `$err` | the newest error record: `$err.Message`, `$err.Input`, `$err.Hints` (see **Errors**) |

Reserved names can't be set or removed with commands or code.

## Looking at variables

- `/vars` lists every variable with its value and type. `/vars number` or `/vars Part` filters by name or type.
- `/get a` shows one; tables are expanded and Instances show their path.
- `/type $a` describes the type, class, base class and path.
- `/keys t` lists a table's keys or an Instance's children; `/len t` counts them.
- `/watch a` prints a `[$]` line every time `$a` changes, including changes from plugins.

## Changing variables

| Command | Does |
|---|---|
| `/rename a b` | `$a` becomes `$b` |
| `/dup a b` | `$b` is a copy of `$a` (`deep` copies nested tables too) |
| `/swap a b` | swaps the two values |
| `/inc a 5` / `/dec a` | adds or subtracts (1 by default) |
| `/push t v` / `/pop t` | adds to or takes from the end of a table |
| `/unset a b` / `/unset *` | removes some or all |

## Functions

Functions are values too. Make one in code and keep it in a variable:

```
> double = function(n) return n * 2 end
> double(4)
/call double 21
/vars function
```

- `/call name arguments` calls it; the arguments are Luau (`/call f 1, "x", $a`). Each result is shown with its type and the first becomes `$last`.
- Functions made in the console keep seeing variables when they run later, also when a command or a plugin calls them.
- `/vars` and `/type` show a function's parameters, for example `function double(a1)`. Built-in functions show `(...)`.

## Converting

`/cast name type` changes a variable's type through its text form: `/cast n number` turns `"5"` into `5`, `/cast v string` turns a Vector3 into `"1, 2, 3"`, `/cast p Instance` turns a path into the Instance.

## Lists

Lists in Tungsten show values with their type icon. Editable cells open the right editor:

| Cell holds | Editor |
|---|---|
| a class name | a searchable class picker |
| a type name | a searchable type picker |
| an enum item or a boolean | a choice of its items |
| any other value | a text box that reads the text as the cell's type; `$name` works too |

Double-click a cell or press **F2** to edit it. When several rows are selected, the new value goes to all of them. A value that doesn't fit the type keeps the box open and says why.

## Tungsten from code

Console code can reach Tungsten itself as `tungsten`: `tungsten.Variables`, `tungsten.Types`, `tungsten.Console`, `tungsten.Scale`, `tungsten.Settings` and the rest. For example `> tungsten.Types.parse("1, 2, 3", "Vector3")`.

## Exporting

`/export a b` copies Luau code that recreates the variables, for example:

```
local a = 5
local spawn = game.Workspace.SpawnLocation
local size = Vector3.new(4, 1, 2)
```

Instances become their path; values with no written form become a comment.

## For plugins

Plugins see every variable, the reserved ones (`$sel`, `$last`, `$err`) included, through the plugin API (`api.variables`, see **Plugins**):

| Call | What it does |
|---|---|
| `get("sel")` | the value and whether it exists |
| `ref("list1")` | like `var("list1")` in console code (lists of objects as a group) |
| `set("hits", 3)` | makes or changes the plugin's own `$hits` |
| `unset("hits")` | removes one of its own |
| `owner("door")` | `"you"`, a plugin's id, or nil |
| `list()`, `names()`, `info("door")` | the rest of the store |
| `watch("sel", function(value, old, removed, by) … end)` | runs whenever that variable changes |
| `Changed:Connect(function(name, value, old, removed, by) … end)` | every change |
| `selection()` | the explorer selection as a list |

**Owners.** Every variable has an owner: you, or the plugin that made it (`/vars` shows `owned by <id>`). A plugin can change or remove only its own; a name you or another plugin already has is refused (`set` returns `false, "$hits belongs to you"`), never overwritten. You can change or unset any variable, a plugin's included; it stays the plugin's, and its watches see `by = "console"` (or `"explorer"`), so a plugin can tell you changed it. Plugins share data on purpose by reading each other's variables.

Reserved names can be read but not changed. When a plugin stops, the variables it owns are removed, its `watch` and `Changed` connections end, and `/undo` forgets its own steps. Undoing one of your steps that brings back a variable of a plugin that isn't running gives it to you instead (the console says so).

## While the explorer is frozen

When the explorer is frozen (the snowflake button, see **Explorer › Freeze**), `/vars` marks the variables whose objects were deleted or moved since: `deleted (frozen)`, `deleted with its parent (frozen)`, `moved (frozen)`, `moved with its parent (frozen)`, with counts for lists and groups. The variables keep holding their objects; the marks go away when the explorer is unfrozen.
