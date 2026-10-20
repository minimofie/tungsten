# Explorer

The explorer sits on the window's right edge: a search bar, the tree of everything in the game and, under it, the selection's properties. It moves with the window, is just as tall and 200 px wide at the default window size (it grows and shrinks with the window, like everything else at another **window size**).

The **explorer button** at the right end of the title bar (minimize sits to its left) opens and closes it: the explorer slides left underneath the window until it is hidden behind it, and slides back out to the right. The button stays in the title bar and its icon is lit while the explorer is open. Clicking again mid-way reverses from where it is. `/explorer open` and `/explorer close` do the same. Tungsten always starts with the explorer open. While it is open the explorer is joined to the window with no gap: one outline runs around both, and a thin line marks where the window ends and the explorer begins.

## The tree

- Services come first (Workspace, Players, Lighting, …), then everything by name. `/explorer sort off` shows the game's own order instead.
- Click the arrow (or double-click the row) to open an object. Children load the first time an object is opened, and the tree follows the game live: new, removed, renamed and moved objects update by themselves.
- Each row has its class icon. A small badge such as `$door` shows a variable that holds the object.
- **Nil Instances**, at the bottom, lists objects that exist but have no parent. Right-click it to refresh or hide the list.
- Tungsten's own windows are left out.
- Rows wider than the explorer scroll sideways: **Shift+wheel**, a sideways wheel or touchpad, or the scrollbar along the bottom. It reaches the very end of the longest name (and its badge).

## Selecting

| Do this | What happens |
|---|---|
| Click | select one object |
| **Ctrl+click** | add or remove an object |
| **Shift+click** | select every row between the last click and this one |
| **Ctrl+A** | select every row |
| Click empty space | clear the selection |

The selection is always in `$sel`: the object itself when one is selected, a table of objects when several are, and empty when nothing is. Use it anywhere in the console: `= $sel`, `> $sel.Transparency = 1`, `/path $sel`.

From the console: `/select game.Workspace.Door`, `/select $door`, `/select remotes` (every match of a search), `/select none`.

## Moving objects (drag and drop)

Drag a row onto another row to move the object into it (its Parent becomes that object). Drag one of several selected rows to move them all.

- A label follows the mouse with the object's name and, over a row it can go into, `→ Target`. That row lights up in the accent color.
- Over a row it can't go into, the label says why: an object can't go inside itself or its own descendants, and rows it is already in are skipped.
- Hold the mouse near the top or bottom of the tree to scroll. Rest on a closed row for a moment and it opens.
- **Escape** cancels the drag. Letting go anywhere that isn't a row does nothing.
- Datamodels (the top-level services: Workspace, Lighting, ReplicatedStorage, …) cannot be moved: their rows can't be picked up, Cut is greyed out for them, and `/move` refuses them.
- The moved objects stay selected, and the console says what moved (`[+] Explorer: moved Door into game.Workspace.House`). Objects the game won't let you move say so.

From the console: `/move game.Workspace.House` moves the selection into House; `/move $house $door` moves `$door`.

## Keys

After clicking in the tree (and while no text box is focused):

| Key | What it does |
|---|---|
| **Up** / **Down** | move the selection; with **Shift** the range grows |
| **Right** | open the object, or go to its first child |
| **Left** | close the object, or go to its parent |
| **Home** / **End** | first / last row |
| **Enter** | open or close |
| **F2** | rename |
| **Delete** | delete the selected objects |
| **Ctrl+D** | duplicate |
| **Ctrl+X** / **Ctrl+C** / **Ctrl+V** | cut / copy / paste into the selected object |
| **Ctrl+G** | group into a Model |
| **Ctrl+Z** | undo the last change (`/undo`) |

## Search

Type in the search bar; results appear as you type, with their parents opened so you see where they are. The tree keeps updating while a search is open: new objects that match appear by themselves (unless the tree is frozen, see **Freeze**).

Words are combined: every word must match.

| Search | Finds |
|---|---|
| `door` | names containing "door" (any case) |
| `"Door"` | names that are exactly `Door` (case matters) |
| `isa:BasePart` | objects of that class or a class based on it |
| `class:Part` | objects of exactly that class |
| `remotes` | RemoteEvent, RemoteFunction and UnreliableRemoteEvent |
| `bindables` | BindableEvent and BindableFunction |
| `scripts` | LocalScript, ModuleScript and Script |
| `players` | Player objects |
| `loadedmodules` | ModuleScripts that have been required |
| `nil` | objects outside the game (no parent) |
| `rad:50` | parts within 50 studs of your character |
| `!word` | anything that does **not** match the word |

For example `isa:BasePart rad:30 !"Baseplate"` finds parts near you except ones named Baseplate.

Right-click the search bar to insert a filter word. Very broad searches stop at 3000 results; the footer says so. **Clear Search and Jump to** (right-click a result) clears the search and keeps the object selected with its parents open.

`/find <search>` runs the same search from the console and lists the first matches there too.

## Freeze

The snowflake button, right of the filter button, **freezes** the tree so nothing in it moves while you work on objects:

- The explorer keeps following the game, it just doesn't show the changes yet. New objects are noted but not shown, even when you open a folder for the first time or select one.
- Objects that are **deleted** keep their row in **red**. What was inside them stays on show in **light red**: it went with them.
- Objects that are **moved** somewhere else (reparented) keep their row in **light blue**, and so does what moved with them. A child taken out of something before that was deleted is light blue too: it still exists.
- The colours follow the objects: one that is moved and then deleted turns red, one that comes back to the same place goes back to normal.
- Renames change the text but not the order.
- Selecting, editing and the right-click menu work as usual.

The button is lit while the tree is frozen, and the status line under the tree says what happened, e.g. `frozen · 1 deleted · 2 moved` (what was inside them isn't counted again). Click it again to **unfreeze**: the tree catches up with the game at once. New objects appear, deleted objects disappear with everything inside them, moved objects go to their new place (and stay selected), and everything is sorted again. Variables keep working while frozen: `/select $door` selects the object's row (red or light blue), and selecting a row sets `$sel` as usual. `/vars` adds `deleted (frozen)`, `deleted with its parent (frozen)`, `moved (frozen)` or `moved with its parent (frozen)` after the variables whose objects changed (counts for lists and groups), and **View in console** says it too, with where a moved object is now. Plugins get it as `api.explorer.isFrozen()`, `api.explorer.frozenState(instance)` and `api.variables.info(name).Frozen`.

From the console: `/explorer freeze`, `/explorer freeze on` / `off`, `/explorer unfreeze`. Tungsten always starts unfrozen.

## Filter

The funnel button beside the search box opens the **filter**: what the explorer shows while you browse, kept until you clear it.

- **Show only**: tick groups (Parts, Models, Scripts, Remotes, GUI, Values, Lights, Sounds, Effects, …) or add classes. Only those objects show, with the parents that lead to them. Nothing ticked shows everything.
- **Hide**: classes that never show, together with what is inside them (Camera, Terrain, …).
- **Clear** turns the filter off. The button is lit while a filter is on, and the footer says what it does.

The filter works in **every search**: the search box searches inside it, and `/find`, `/select <search>`, the path bar's child lists and plugins' `Explorer.find` follow it too. An object you select or highlight that the filter leaves out is shown anyway; one the filter **hides** says so instead.

`/filter` shows the filter; `/filter show parts`, `/filter show Tool`, `/filter hide Camera`, `/filter unhide Camera`, `/filter clear`, `/filter groups`, `/filter open`. The filter lasts until you clear it or Tungsten closes; it starts empty every time.

{{filter-groups}}

## The path bar

The strip under the title bar shows the path of what is **loaded**. There is one loaded target for all of Tungsten: every tab (built-in and plugin, and every sub-tab) works on it and is told when it changes.

```
game › Workspace › Map › Door
```

Selecting in the explorer does **not** change it. Something gets there only by loading it: **Load** in the explorer's right-click menu, the arrow on the right of the bar, a part of the path, a typed path, `/load`, or a plugin.

- With several objects loaded, the bar shows the first and `+N` after it; tabs get the whole list.
- A plugin can load a value that isn't an object (a function, a table, a connection). A function or table **inside a script** shows by how it is reached: the script's path, then `require()` for a ModuleScript (what it returns) or `getsenv()` for a running script (its globals), then the keys and upvalues down to it:
  ```
  game › ReplicatedStorage › Combat › require() › Weapons › Sword › swing
  ```
  The path comes with the load (the Script Viewer's **Inspect** passes it on) or is searched for: the tables of the ModuleScripts the game has required, then running scripts' globals (a few levels deep, the shortest path wins). Click a part to load that table; **Copy** gives the code, `require(game.ReplicatedStorage.Combat).Weapons.Sword.swing`, and **Highlight** selects the script. A value nothing reaches shows as one part, as before, with Copy and Highlight greyed.
- A **nested function** (a function defined inside another) shows as `nested 1`, and one of its running copies as `nested 1 · running 2`; their code is `debug.getproto(f, 1)` and `debug.getproto(f, 1, true)[2]`.
- Typed paths and `/load` take that code too: `require(path).key`, `getsenv(path).key`, `["odd key"]`, `[3]`, `debug.getupvalues(…)[n]`, `debug.getproto(…, n)` and `debug.getproto(…, n, true)[k]`. Typing `$name` loads that variable. They are only walked, never run, and a ModuleScript the game hasn't required isn't required (that would run it).
- **The back button** (←, right of the ⌄ button) loads what was loaded before: an object, several, or a value. Press it again to go further back. It is greyed when there is nothing to go back to; hovering it shows where it goes. Every load and clear is remembered (the last 50), objects that were destroyed are skipped, and pressing it while typing a path stops typing.
- **The arrow** loads the explorer selection, the same as **Load**. With nothing selected it starts typing a path.
- **The reload button** (⟳, right of the arrow) loads what is loaded again: a value inside a script is read again, so a changed upvalue or entry shows its new value, and every tab redraws. It isn't remembered for ←. When a path no longer reaches anything (e.g. the script stopped), the old value stays loaded and the reason shows under the bar. It is greyed when nothing is loaded.
- Click the empty part of the bar to type a path. Enter or the arrow loads it; Escape cancels. Paths are only walked, never run, so `game.Workspace["My Part"]`, `Workspace.Map` and `game:GetService("Lighting")` work, but code doesn't. A path that doesn't exist says why under the bar, and the box stays open so you can fix it. Long paths slide along as you type.
- Click a part of the path to load that object. Right-click it for **Copy** and **Highlight** of that part.
- Click a `›` to see that object's children; the list can be searched. Pick one to load it.
- The button on the left has **Copy** and **Highlight**:
  - **Copy** copies the path as code, ready to paste into a script.
  - **Highlight** selects the object in the explorer. It opens the explorer if it is collapsed, opens the object's parents, clears a search that hides it, scrolls to the object and makes its row pulse in the accent color for about 3 seconds. Clicking the row stops the pulsing at once.
- Long paths scroll sideways with the mouse wheel.
- An object that is destroyed drops out of what is loaded; when nothing is left the bar is empty.
- `/load <path | $var>` loads from the console (`/load` alone says what is loaded, `/load none` unloads).

## Properties

The lower part of the explorer shows the properties of what is selected, grouped by category (Appearance, Data, Behavior, …) the way Studio shows them. Click a category to fold it; folded categories stay folded until Tungsten closes.

Drag the line between the tree and the properties to give either more room. It is the only part of Tungsten you resize with the mouse, and the split is remembered.

| Value | Click it to |
|---|---|
| true / false | flip the switch |
| a list (Material, …) | pick an item |
| Color3 | click the color square for a picker (square, hue bar, hex, R G B, **Cancel** / **Accept**); click the text to type `255, 128, 0` or `#ff8000` |
| BrickColor | click the square for the palette (click a color, then **Accept**), or type a name |
| NumberSequence / ColorSequence | click ⋯ for the keypoint editor (with **Cancel** / **Accept**), or type `0: 1; 0.5: 2 +- 0.1; 1: 0` |
| an object (Parent, Part0, …) | type a path or `$variable`, pick a variable, **Pick in explorer** (then click the object in the tree; Esc cancels), **Set to nil** or **Go to** |
| anything else | type a new value in a box over the cell. The box is at least 170 px wide, wider than the cell when needed, and shows the whole value: a long one scrolls along with the cursor. Enter saves, Escape cancels. Nothing is shown under the box unless the value can't be used: then the reason shows there until you type again |

The color picker, the palette and the keypoint editor show each change on the object straight away. **Accept** keeps it; **Cancel** (or **Escape**) puts back the value the property had when the popup opened. Clicking somewhere else keeps the change, like Accept.

Values with parts have an arrow: Vector3 opens into X, Y and Z, UDim2 into its scales and offsets, CFrame into **Position** and **Orientation** (degrees, like Studio), Font into family, weight and style, Faces and Axes into switches, PhysicalProperties into its five numbers. Changing a part keeps the rest.

- Read-only properties are grey and can't be changed. Numbers show 3 decimals (the ⋯ button changes that); editing shows the full value.
- With several objects selected only the properties they all have are listed. Where their values differ the row says `— (3 values)`; a change goes to every selected object (the first 50 are compared, all of them are changed).
- The values update while you watch: changes made by the game or by scripts show up straight away.
- The box at the top filters by name or category. The ⋯ button can also show deprecated and hidden properties.
- **Attributes** come after the properties: edit them like properties, **Add attribute…** (name, type and value), and right-click one to rename or remove it. **Tags** lists the CollectionService tags the objects have.

Right-click a property for **Copy value**, **Copy name**, **Copy as code** (`game.Workspace.Door.Transparency = 0.5`, one line per object), **Save value as variable…**, **Set from variable** (variables whose value fits), and for values with a picker **Type a value…**.

From the console: `/props` lists the selection's properties (`/props $door trans` only the matching ones), `/setprop Transparency 0.5` sets one on the selection (`/setprop $door Color #ff0000`, `/setprop $door @Health 100` for an attribute) and `/attrs` lists attributes and tags.

Tungsten knows the properties of every class from a list it carries (no downloads). Properties newer than that list show under **Other** when hidden properties are shown.

## Messages

The explorer writes what it did and what went wrong to the console with its name in front: `[+] Explorer: deleted 2 objects`, `[*] Explorer: 14 objects without a parent`, `[x] Explorer: couldn't delete Terrain: …`. Its errors are listed by `/errors explorer`.

## Right-click menu

Right-click a row for a menu with the number of selected objects at the top, **Load**, and four groups:

- **Load** (highlighted) loads the selection for **every tab**: the path bar shows it and each tab decides what loading means. The Console puts it in `$loaded` and prints it; Documentation turns to the object's class page (its base classes and every property by category) without opening; a plugin's tab gets the objects.

- **Object ›** acts on the objects. Entries that only fit some objects (scripts, remotes, players, …) show only when such an object is selected:

| Entry | What it does |
|---|---|
| **Insert ›** | a new object inside (see below) |
| **Rename** | edit the name in the row (F2) |
| **Duplicate** | a copy next to each object (Ctrl+D) |
| **Delete** / **Delete Children** | takes the objects (or what is inside them) out of the game; `/undo` brings them back |
| **Cut** / **Copy** / **Paste Into** | the explorer's own clipboard (not your computer's): Copy then Paste Into puts a copy inside the selected object; Cut then Paste Into moves it there. Cut objects are faded in the tree until they are pasted or the clipboard is cleared |
| **Show Clipboard** / **Clear Clipboard** | print what is on the clipboard in the console (the same as `/clipboard`); empty it (cut objects stay where they are, the same as `/clearclipboard`) |
| **Group** / **Group in Folder** / **Ungroup** | put the objects in a new Model or Folder where the first one was; Ungroup moves a Model's or Folder's children up and removes it |
| **Select Children**, **Jump to Parent**, **Expand All**, **Collapse All**, **Clear Search and Jump to** | move around the tree |
| **Copy Path** | the path as code |
| **Dump Functions** | scripts: the script's functions (name and parameters, nested ones indented) printed in the console |
| **Play Tween** | play a Tween |
| **Load Animation** / **Stop Animations** | play an Animation on your character, and stop the ones Tungsten started |
| **Fire ClickDetector / ProximityPrompt / TouchInterest** | trigger it without walking up to it |
| **Block** / **Unblock** | remotes and bindables: the game's FireServer / InvokeServer / Fire / Invoke calls on it go nowhere (your own calls still work); the entry shows how many calls were stopped; closing Tungsten unblocks everything |
| **Select Character** | players: selects their character |
| **Refresh** / **Hide Nil Instances** | the Nil Instances row |
- **Object › Insert ›** makes a new object inside the object you right-clicked (inside each one when several are selected). It lists **Search all classes…** (a searchable list of every class that can be made), the **Common** classes (Part, Model, Folder, the scripts, remotes, GUI basics, …), then every class Instance.new can make, grouped: Parts, Models & Folders, Scripts, Remotes & Bindables, Values, GUI, UI Layout & Style, Lights, Sounds, Effects, Constraints & Physics, Characters, Animation, Meshes, Tools & Interaction, Other and Deprecated. Long groups split into letter ranges (A–C, D–F, …). The new object is selected. From the console: `/insert Part` (into the selection) or `/insert Folder game.Workspace.Map`.
- **Function ›** starts with **Documentation** (opens the Documentation tab on the object's class page) and **View in console** (prints each object with its class and base classes, path, parent, children and descendants, and the variables that hold it). Below them are the actions plugins add for the selected classes; when none apply it says so.
- **Variable ›** keeps the selection in the console: **Set variable…** (one object, or a table for several), **Add to list…** (adds them to a list variable, making it if needed), **Copy variable** (copies the variable that holds the object, e.g. `$door`, ready to paste into the console), **Watch** (prints a line whenever a property of the object changes; **Stop watching** ends it) and **Unset** the variables that hold the objects.
- **Save ›** writes files to `Tungsten/saved/`: **Save to File** (`saveinstance`, `<Name>.rbxm`; several objects go into one file), and for scripts **Save Script** (the decompiled source, `<Name>.lua`) and **Save Bytecode** (`<Name>.luac`).

Entries that don't apply to the whole selection are greyed out. Every change these entries make (and renames, moves, inserts and property edits) can be taken back with `/undo` or **Ctrl+Z** in the tree.

### The clipboard from the console

`/clipboard` prints what Cut or Copy put on the explorer's clipboard: whether it was cut or copied, and each object's path and class. Objects deleted since are noted and left out; the rest become `$last`. With a word after it, it works the clipboard too:

| Command | What it does |
|---|---|
| `/clipboard` (or `/clip`) | show what is on it |
| `/clipboard clear`, `/clearclipboard` | empty it; cut objects stay where they are |
| `/clipboard cut [$var \| path]` | cut the selection, a variable or a path |
| `/clipboard copy [$var \| path]` | copy them |
| `/clipboard paste [$var \| path]` | Paste Into the selection (or the object given) |

These work on the same clipboard as Ctrl+X / Ctrl+C / Ctrl+V and the right-click menu. `/copy` is different: it puts text on your computer's clipboard.

From the console: `/decompile` saves the source of the selected scripts (or `/decompile $s myscript.lua`), `/save` saves objects to a `.rbxm` file (`/save game.Workspace.Map map`), `/move` and `/insert` move and make objects. Files go to `Tungsten/saved/` unless the name has a folder in it.

## For plugins

- `tungsten.Explorer.getProperties(instance)` returns `{ Name, Value, Type, Category, ReadOnly, Deprecated, Hidden, … }` for each property.
- `tungsten.Explorer.pick("set the target", function(instance) … end)` lets the user click an object in the tree.
- Editors for a value type or a single property, see **UI framework**.
- `tungsten.Explorer.load(instances)` does what **Load** does; `Explorer.Loaded:Connect(function(instances, openTabId) end)`. `tungsten.Loaded` is the loaded target itself: `get()`, `list()`, `value()`, `values()`, `load(items, { By })`, `clear()`, `target(value, { Kind, Label, Origin })`, `Changed:Connect(function(items, by) end)`. Every tab handles loads with `OnLoad = function(values, tab, items) end` (the open tab first); `values` holds objects and raw values, `items` keeps loaded values whole (their `Label` and `Origin`).
- `tungsten.Explorer.Filter`: `Filter.set({ Only, Classes, Hide })`, `Filter.addGroup("doors", { Text = "Doors", Classes = { … } or Test = function(obj) … end, Owner = "myplugin" })`, `Filter.Changed`.
- `tungsten.Explorer.find(text, limit, { NoFilter = true })` searches past the filter.
- `tungsten.Explorer.Actions` holds every right-click action (`duplicate`, `delete`, `group`, `saveToFile`, `fire`, `watch`, …) for code that wants to do the same.
- `tungsten.Explorer.addFunction({ Id, Text, Icon, AppliesTo = function(list) … end, Run = function(list) … end, Owner = "myplugin" })` adds an entry to **Function ›** (see **Plugins**).

A plugin reaches all of this through its `api.explorer` (`getSelection`, `getProperties`, `find`, `isFrozen`, `frozenState`, `SelectionChanged:Connect`, `addFunction`, `addFilterGroup`, `addInsertGroup`), which sets the plugin as owner. The explorer is read-only for plugins: they read the selection, objects and properties, but don't set the selection or write properties through it.
