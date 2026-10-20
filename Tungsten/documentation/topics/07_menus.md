# Menus

Every right-click menu and button menu in Tungsten is a **named menu**. A named menu is a list of sections that entries are added to. It is built fresh each time it opens, from a **context**: what was clicked, what is selected and so on. Each entry can then decide its own text, whether it is shown, and whether it is greyed out. All menus look the same, whoever made them.

Tungsten's own menus are built this way, and plugins use the same calls. Menus sit on top of the general **UI framework**. `/menus` lists every menu, and `/menus <id>` lists one menu's sections and entries, showing who added each entry.

## Tungsten's menus

Every menu there is right now, live:

{{menus}}

The menus Tungsten ships with:

| Menu | Opens on | Context | Plugins |
|---|---|---|---|
| `explorer` | right-click a tree row | `Explorer`, `Nodes`, `Node`, `Instances`, `Count`, `Classes`, `NilNode`, `Point` | fixed |
| `explorer.object` | Explorer › Object | same as `explorer` | fixed |
| `explorer.function` | Explorer › Function | same as `explorer` | **add actions here** |
| `explorer.variable` | Explorer › Variable | same as `explorer` | fixed |
| `explorer.search` | right-click the search bar | `Explorer`, `Input`, `Text` | may add |
| `explorer.property` | right-click a property, attribute or tag | `View`, `Row`, `Kind`, `Name`, `Prop`, `Value`, `Same`, `Instances`, `Count`, `Point` | may add |
| `explorer.properties` | the properties panel's ⋯ button | `View`, `Explorer` | may add |
| `tabbar` | right-click a tab (or the empty side bar) | `TabBar`, `Tab`, `Point` | may add; a tab's own entries come from its `MenuItems` |
| `pathbar` | the path bar's ⌄ button | `Instance` | fixed (Copy and Highlight only) |
| `console.output` | right-click the console output | `Output`, `Console`, `Line`, `Selected`, `Record` | may add |
| `editor` | right-click a code editor | `Editor` | may add |
| `docs.code` | right-click a code block | `View`, `Text`, `Runnable`, `Single` | may add |
| `docs.page` | right-click a topic page | `View`, `Topic` | may add |
| `docs.topics` | right-click the topic list | `List`, `Selected`, `Item`, `Point`, `View` | may add |
| `plugins.entry` | right-click a plugin card in the Plugins tab | `Ids` (the selected plugins), `Manager` | may add |

A plugin adds to menus through its `api.menus` (`add`, `addMany`, `define`, `remove`), which sets it as the owner; the examples below call `Menus` directly and pass the owner by hand, as console code would. A **fixed** menu can't be changed by plugins. The explorer and path bar menus are fixed because their contents are part of how Tungsten works. A plugin adds explorer actions through the Function category.

## A menu of your own

```
local Menus = tungsten.import("base/ui/menus")

Menus.define("myplugin.items", {
	Title = "My plugin item list",
	Owner = "myplugin",
	Header = function(ctx) return #ctx.Selected .. " items" end,
	Sections = { "main", { Id = "danger", Header = "Careful" } },
	Empty = "Nothing to do here",
})

Menus.add("myplugin.items", {
	Id = "refresh", Section = "main", Order = 10,
	Text = "Refresh", Icon = "refresh",
	Callback = function(ctx) refresh() end,
}, "myplugin")

Menus.open("myplugin.items", { Selected = picked }, { Position = point })
```

A list opens its menu by itself when it is given `Menu = "myplugin.items"`. Its context is then `List`, `Selected`, `Item` and `Point`, plus whatever `MenuContext(ctx)` adds. A code editor takes `Menu = "…"` the same way. Put `{ Include = "editor" }` in your own editor menu to keep Copy, Cut, Undo and the rest.

## Entries

| Field | Meaning |
|---|---|
| `Id` | name of the entry; the same Id from the same owner replaces it |
| `Section`, `Order` | where it goes: sections in the menu's order, then by Order (lowest first) |
| `Text`, `Icon`, `Shortcut` | what it shows; the shortcut is only a hint on the right |
| `IconColor` | the icon's tint: a Color3 or a theme color name (class icons use their class color) |
| `When(ctx)` | return true to show the entry at all |
| `Disabled` | true (or a function) to grey it out |
| `Danger` | red text, for things that destroy or remove |
| `Emphasis` | accent text on a soft accent band, for the main action of a menu (like Explorer › Load) |
| `Checked` | a check item: it flips in place, the menu stays open, `item.Checked` is the new state |
| `Callback(ctx, item)` | runs when it is chosen; errors go to the log, not the screen |
| `Menu = "id"` | a submenu that is another named menu (same context) |
| `Items` | a submenu: a list of entries, or `function(ctx)` that returns one |
| `Provide(ctx)` | several entries at once, built when the menu opens |
| `Include = "id"` | every entry of another menu, at this spot |
| `Kind = "name"` | a custom row (see below) |
| `{ Separator = true }`, `{ Header = "text" }` | a line or a small heading |

`Text`, `Icon`, `IconColor`, `Shortcut`, `Disabled`, `Danger`, `Emphasis` and `Checked` can each be a value or a `function(ctx)`. Separators between sections are added for you. Empty sections and doubled lines are left out.

`Menus.removeOwner("myplugin")` removes a plugin's entries from every menu, along with the menus it defined. It runs when the plugin is turned off.

## Explorer actions

```
tungsten.Explorer.addFunction({
	Id = "anchor", Text = "Anchor parts", Icon = "object",
	AppliesTo = function(instances)
		for _, obj in instances do
			if not obj:IsA("BasePart") then return false end
		end
		return true
	end,
	Run = function(instances)
		for _, part in instances do part.Anchored = true end
	end,
	Owner = "myplugin",
})
```

The action shows under **Function ›** only when `AppliesTo` says yes for the selection. When nothing applies, the category says `No plugin actions for <Class>`.

## Custom rows

```
local ContextMenu = tungsten.import("base/ui/components/contextmenu")
ContextMenu.addKind("swatch", {
	Height = 30,
	Width = function(item) return 180 end,
	Build = function(row, item, menu)
		-- fill `row` (a Frame); menu:Close() closes the menu
	end,
})
Menus.add("myplugin.items", { Kind = "swatch", Color = Color3.new(1, 0, 0) }, "myplugin")
```

If a custom row fails to build, it shows the entry's text with "(failed)" and the details go to the log.

## Choices in lists and pickers

Value dropdowns (class, type and enum pickers, and choices when editing a list cell) can have new kinds too:

```
local TypePicker = tungsten.import("base/ui/components/typepicker")
TypePicker.registerKind("team", {
	Options = function(arg) return { { Value = "Red", Text = "Red", Icon = "class_player" } } end,
	Dynamic = true,
	Owner = "myplugin",
})
```

Lists can then use `Type = "team"` (or `"team:extra"`) for a column, and `TypePicker.new({ Kind = "team" })` makes a picker.
