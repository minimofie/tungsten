# Plugins

## Installing and turning on

Put a plugin's folder in `Tungsten/plugins/` (it holds a `plugin.luau`), then **Rescan** in the Plugins tab (or `/plugins rescan`). A new plugin starts **off**: nothing in it runs until you turn it on, with its **Enabled** switch in the Plugins tab or from the console:

| Command | What it does |
|---|---|
| `/plugins` | every plugin: id, name, version and state |
| `/plugins rescan` | find folders added since Tungsten started |
| `/plugin on <id>` | start it from the next start |
| `/plugin off <id>` | stop it from the next start (it keeps running until then) |
| `/plugin reload <id>` | read its files again and start it again (for one that ran into a problem) |
| `/plugin info <id>` | everything about one plugin: what it adds, its faults, its problem |

Turning a plugin on or off takes effect the next time Tungsten starts. Which plugins are on is kept in `Tungsten/base/plugins.json`; **Reset all settings** doesn't change it.

A plugin is **on**, **off**, **failed** (it threw while starting, or its `Load` took longer than 5 seconds; its error is in the console under its name) or has a **problem** (its `plugin.luau` doesn't compile or is incomplete, its id is taken, or it needs a prime plugin that isn't on). The welcome line counts the plugins that are on and how long they took, apart from Tungsten's own time.

Plugins run with the executor's own rights: anything Tungsten can do, a plugin can do. Install only plugins you trust.

When something a plugin hands Tungsten breaks (a command, a menu entry, its tab, a hook), the error appears as `[x] <Plugin>: … failed: …` and is counted on the plugin (`/plugin info`). Tungsten keeps running, and so does the plugin.

## The Plugins tab

The first entry, **tungsten**, isn't a plugin: it holds the program's own settings (see **Console › Settings that are kept**). Below it, every plugin has a card: its icon, name, a line (version and description, why it didn't start, or what changes at the next start) and a chip: **on** (green), **off** (grey), **failed** or **problem** (red). The Plugins tab's icon shows how many didn't start. With more than a few plugins a search box appears; it matches names, ids and descriptions.

Click a card to see its page; **Ctrl**+click adds cards to the selection and **Shift**+click selects a range. Right-click for **Turn on**, **Turn off**, **Reload**, **Open its tab**, **Documentation**, **Copy id** and **Reset its settings…**; they act on every selected plugin.

A plugin's page:

| Part | What it shows |
|---|---|
| Header | icon, name, version and author, and the **Enabled** switch (on or off from the next start) |
| State | on / off / failed / problem, what changes at the next start, how long it took to load |
| Buttons | **Open tab**, **Reload**, **Docs** (its topic), **Copy id** |
| Adds | what it has registered: tabs, commands, explorer functions, menu entries, docs topics, variables |
| Settings | a row per setting, and **Reset** |
| Problems | why it can't run or failed (**Details** prints the trace in the console), its faults, warnings |

With no plugins installed, the tab offers **Rescan** and this guide.

## Writing a plugin

A plugin is a folder in `Tungsten/plugins/`. Folders whose names start with `_` are skipped, so you can keep drafts there.

| In the folder | What it is |
|---|---|
| `plugin.luau` | required: returns the plugin's definition |
| `lib/*.luau` | optional: your own modules, loaded with `P.import("lib/name")` |
| `icon.png` | optional: its icon (or set `Icon` to a built-in icon name or a file in the folder) |
| `docs.md` | optional: its documentation topic (`Docs = "docs.md"`) |
| `settings.json` | written by Tungsten: the plugin's saved settings |

Anything else in the folder is the plugin's own (`api.files` reads and writes there).

## The definition

`plugin.luau` returns a table. Only `Name` is required.

| Field | What it is |
|---|---|
| `Name` | shown in the Plugins tab and before its console lines |
| `Id` | letters, digits, `_` and `-`; the folder name if missing (set it, so renaming the folder keeps the plugin on) |
| `Version`, `Author`, `Description` | shown on its card and page |
| `Icon` | a built-in icon name, or a `.png` in its folder |
| `Order` | load order among plugins, lower first (default 100) |
| `Settings` | its settings (see **Settings**) |
| `Commands` | console commands, each as in `api.console.register` |
| `Functions` | explorer **Function ›** entries, each as in `api.explorer.addFunction` |
| `Tab` | `{ Title, Icon?, Build = function(page, api) end, OnLoad? = function(values, api, items) end, OnSelect? = function(api) end, OnDeselect? = function(api) end }`: its tab in the side bar; `OnLoad` runs for every load, `OnSelect` / `OnDeselect` each time it opens or another tab does |
| `Docs` | `"docs.md"` (a file in its folder) or a topic table |
| `Requires` | prime plugins it can't work without: `{ "scanner" }` (missing or off: a problem) |
| `Uses` | prime plugins it links to when they are on: `{ "scriptviewer" }` (it starts without them) |
| `Exports` | prime plugins only: what they share (a table, or `function(api)` returning one) |
| `Load(api)` | its work starts here |
| `Unload(api)` | before everything it added is taken away |

Taken ids: `tungsten`, `core`, `console`, `plugins`, `documentation`, and the prime plugins' ids (`scriptviewer`, `instanceviewer`, `scanner`), which only the prime plugins themselves use.

`plugin.luau` gets `P` as `...`:

| `P.` | |
|---|---|
| `Folder`, `Path` | its folder's name, and `Tungsten/plugins/<Folder>` |
| `Version` | Tungsten's version |
| `import("lib/util")` | runs `lib/util.luau` once (it gets `P` too) and returns what it returns |
| `read("data.txt")`, `file("icon.png")` | a file's text, and a full path in the folder |

## Lifecycle

1. **Read.** Tungsten runs `plugin.luau` to read the definition, also while the plugin is off (to show it in the Plugins tab). Its top level only builds the table; nothing else happens there.
2. **Start.** When Tungsten starts with the plugin on, it makes the plugin's `api`, registers its `Commands`, `Functions`, `Tab` and `Docs`, then runs `Load(api)` in a thread of its own. `Load` may wait (`task.wait`), up to 5 seconds; past that the plugin counts as **failed** and Tungsten goes on.
3. **Running.** Its tab is built the first time it opens. Faults in anything it handed Tungsten print as `[x] <Name>: … failed: …` and are counted; the plugin keeps running.
4. **Stop.** On shutdown, a re-run of Tungsten, or a reload: `Unload(api)` runs, then `api:remove()` takes away everything the plugin registered, its owned listeners and threads, and its variables, and saves its settings. The api can't register anything after that.
5. **Reload** (Reload button, `/plugin reload`): stop, read the files again, start again. Settings stay; variables start over.

Turning a plugin on or off takes effect at the next start. Only settings are kept between runs: its tab, variables and what it showed start fresh each time.

## Settings

Each setting has an `Id`, a `Kind` and a `Text`, plus an optional `Hint`.

| Kind | Default | Also |
|---|---|---|
| `toggle` | true / false | |
| `number` | a number | `Min`, `Max`, `Step`, `Decimals` |
| `choice` | one of `Options` | `Options` (values, or `{ Value, Text }`) |
| `color` | `{ r, g, b }` | |
| `action` | none | `Run(api)`, `Button` (its label), `Danger` |

They show on the plugin's page in the Plugins tab, with **Reset**. The plugin reads and changes them through `api.settings`: `get(id)`, `set(id, value)`, `reset(id)`, `all()`, `items()`, `item(id)` and `Changed:Connect(fn(id, value))`. A number is kept between `Min` and `Max`, a choice must be one of its options, a `Color3` is stored as `{ r, g, b }`, a value of the wrong type is refused. They are saved in its folder's `settings.json`.

## The api

Everything a plugin registers through its `api` carries its id and goes when it stops.

| Part | What it gives |
|---|---|
| `api.console` | `register{…}`, `unregister(name)`; `print`, `success`, `warn`, `error`, `value` (lines start with its name); `run(input)`; `onLine(fn)`; `reporter` |
| `api.variables` | read every variable; `set` / `unset` its own; `get`, `ref`, `owner`, `list`, `names`, `info`, `selection()`, `watch(name, fn)`, `Changed:Connect(fn)` |
| `api.explorer` | read-only: `getSelection()`, `SelectionChanged:Connect`, `getProperties`, `find`, `isFrozen`, `frozenState`, `FrozenChanged:Connect`; `addFunction`, `addInsertGroup`, `addFilterGroup` |
| `api.loaded` | the one loaded target every tab works on: `get()`, `list()`, `value()`, `values()`, `set(items)`, `clear()`, `target(value, { Kind?, Label?, Origin?, Access? })`, `access` (`root(script)`, `key(a, k)`, `upvalue(a, n)`, `code(a)`, `parse(text)`, `resolve(a)`, `find(value)`, `findFrom(a, value)`: how a value is reached inside a script, shown by the path bar), `isTarget(x)`, `back()` / `canGoBack()` / `previous()` (what was loaded before), `Changed:Connect(function(items, by) end)` |
| `api.pathbar` | `show(x)` = `api.loaded.set(x)`; `clear()` (one path bar for every tab) |
| `api.tab` | its own tab: `select()`, `badge(n)`, `update(fields)`, `isOpen()` |
| `api.tabs` | `add{…}` more side-bar tabs (prefer sub-tabs), `update(id, …)` |
| `api.ui` | components (`new(name, props)`), hooks and filters (`on`, `filter`), and the tab pieces: `page`, `section`, `row`, `field`, `placeholder`, `panes`, `subtabs` |
| `api.menus` | `define`, `add`, `addMany`, `remove`, `open`, `addRowKind` (see **Menus**) |
| `api.prompt` | `confirm`, `input`, `choice`, `form`, `custom`, `popover`, `await`, `registerFieldKind` |
| `api.notify` | `show(text or { Title, Text, Kind, Actions })`, `registerKind` |
| `api.tooltip` | `attach(target, text)`, `show`, `hide` |
| `api.editors`, `api.types`, `api.classes`, `api.picker` | property editors, value types, classes and picker kinds of its own |
| `api.docs` | `add` a topic, `addSection` to any topic, `addDirective`, `open(id)` |
| `api.undo` | `record{ Text, Undo = function() end }` so `/undo` can take its changes back |
| `api.icons` | `register(name, source)` |
| `api.settings` | its settings |
| `api.files` | files in its folder: `read`, `write`, `append`, `exists`, `isFolder`, `list`, `makeFolder`, `delete`, `path` |
| `api.connect`, `spawn`, `delay`, `every`, `bin` | listeners and threads that stop with it (see **Listeners and threads**) |
| `api.plugins` | `get(id)`: a prime plugin's `Exports`; `open(id, focus)`: its tab, at `focus` (its `Exports.reveal`); `isOn(id)` (only for ids in `Requires` or `Uses`) |

Console code can make a test api: `> api = tungsten.api("try", { Name = "Try" })`, except with an id a plugin folder uses.

## Building its tab

`Tab.Build(page, api)` runs the first time the tab opens. Build from Tungsten's own pieces so the tab looks like the rest of Tungsten; plugins can't restyle them. Let things stretch: **window size** makes the window bigger or smaller like resizing it, and stretching layouts get the room (see **UI framework › Scale**).

```
Tab = {
	Title = "Spawner",
	Build = function(page, api)
		local view = api.ui.page({ Parent = page, Toolbar = true })
		api.ui.new("Button", { Parent = view.Toolbar, Text = "Spawn", OnClick = function() end })
		api.ui.subtabs({
			Parent = view.Body,
			Tabs = {
				{ Id = "make", Title = "Make", Build = function(holder)
					local left, right = api.ui.panes(holder, { Split = 0.4 })
					api.ui.section(right, "Options")
					api.ui.field(right, api.settings.item("speed"), api.settings)
					local row = api.ui.row(right, { Text = "Anchored", Hint = "new parts don't fall" })
					api.ui.new("Toggle", { Parent = row.Control })
				end },
				{ Id = "list", Title = "Spawned", Build = function(holder)
					api.ui.placeholder(holder, "Nothing spawned yet")
				end },
			},
		})
	end,
},
```

A plugin has one tab in the side bar; more views go in **sub-tabs** across the top of it. Each sub-tab is built the first time it shows. `tabs:Badge("list", 4)` puts a count on a sub-tab (`nil` or `0` takes it away). There is one path bar for all tabs: `api.loaded.set(part)` loads the part for every tab, and `Tab.OnLoad` (or `api.loaded.Changed`) tells the plugin when something else is loaded.

## Console commands

```
api.console.register({
	Name = "spawn",
	Usage = "/spawn <class>",
	Description = "make an object in front of you",
	Run = function(ctx)
		local part = Instance.new(ctx.Args[1] or "Part")
		part.Parent = workspace
		ctx.success("made " .. part.Name)
		return part             -- becomes $last
	end,
	Complete = function(ctx, argIndex) return { "Part", "Model" } end,
})
```

A plugin's command runs as `:spawner.spawn`, and as `/spawn` while no Tungsten command or other plugin has that name. Inside `Run`, `ctx` has `Args`, `Raw`, `resolve("$x")`, `eval(code)`, `info` / `success` / `warn`, `fail(message)` and `usage()`, the same as Tungsten's own commands. Commands from plugins are listed here:

{{plugin-commands}}

## Explorer actions

```
api.explorer.addFunction({
	Id = "launch", Text = "Launch", Icon = "class_part",
	AppliesTo = function(list) return list[1]:IsA("BasePart") end,
	Run = function(list)
		for _, part in list do part.AssemblyLinearVelocity = Vector3.new(0, 200, 0) end
	end,
})
```

The entry shows under **Function ›**, below **Documentation** and **View in console**, only when `AppliesTo` says it fits. The explorer is read-only for plugins: they read the selection, objects and properties, but don't set the selection or write properties through it.

## Variables

A plugin reads every variable but changes only its own; a name you or another plugin has is refused (`set` returns `false` and why). Its variables show `owned by <id>` in `/vars` and go with it. Its watches get who changed a variable (`by`), so it can tell you did. See **Variables › For plugins**.

## Listeners and threads

| Call | What it does |
|---|---|
| `api.connect(signal, fn)` | connect; ends when the plugin stops |
| `api.spawn(fn, …)` | a thread; cancelled when it stops |
| `api.delay(seconds, fn, …)` | later, unless it stopped first |
| `api.every(seconds, fn)` | again and again; `:Stop()` ends it |
| `api.bin:Add(thing)` | cleaned when it stops (connections, instances, functions) |

A fault in any of them prints under the plugin's name and nothing else stops. Connections and threads a plugin makes itself (`:Connect`, `task.spawn`) are its own job: end them in `Unload`.

## Files

`api.files` works inside the plugin's folder: `api.files.write("data/log.txt", text)`, `read`, `append`, `exists`, `isFolder`, `list("data")`, `makeFolder`, `delete`, `path(rel)`. Plugins can also use Volt's `readfile` and the rest anywhere in the Tungsten folder; keep to your own folder so plugins don't step on each other.

## Prime plugins

`scriptviewer` (script and module viewer / editor), `instanceviewer` (instance viewer / editor) and `scanner` (universal scanner / spy) are the prime plugins, loaded first in that order. They ship with Tungsten in `Tungsten/plugins/` (ScriptViewer, InstanceViewer, Scanner) and start off like any plugin: turn them on in the Plugins tab. They are the only plugins another plugin may depend on:

- `Requires = { "scanner" }`: it can't work without it. A plugin whose required prime plugin is missing or off has a problem and doesn't start.
- `Uses = { "scriptviewer" }`: it links to it when it is on. It starts anyway; `get` and `open` answer `nil` / `false` and why while the other one is off, so show those links greyed.

`api.plugins.get("scanner")` gives what the scanner shares (its `Exports`). `api.plugins.open("scriptviewer", focus)` opens the script viewer's tab and calls its `Exports.reveal(focus)`, so a click in one plugin can take you to the right place in another. A prime plugin that can be opened at something exports `reveal`.

## Rules

- Plugins run with the executor's own rights: anything Tungsten can do, a plugin can do. Install only plugins you trust.
- The top level of `plugin.luau` only builds the definition; work starts in `Load`.
- Use Tungsten's components and pieces; don't restyle Tungsten's UI (filters change data, not the look).
- Prefer the owned helpers; anything else you start, stop in `Unload`.
- Keep files to your own folder; only settings are kept between runs.
- Everything is local: the api has no way to download, and Tungsten never fetches anything for a plugin.
- If you hook `__namecall` (Tungsten's remote blocking does), chain to the original so both keep working. `/plugin info` notes plugins whose code mentions `hookmetamethod` or `hookfunction`.

## Template

Copy this into `Tungsten/plugins/MyPlugin/plugin.luau`, change the names, then **Rescan** in the Plugins tab and switch it on (it starts at the next run of Tungsten):

```
local P = ...

return {
	Name = "My Plugin",
	Id = "myplugin",
	Version = "1.0",
	Author = "you",
	Description = "what it does, in one line",
	Settings = {
		{ Id = "greeting", Kind = "choice", Text = "Greeting", Default = "hello", Options = { "hello", "hi" } },
		{ Id = "count", Kind = "number", Text = "Count", Hint = "how many", Default = 3, Min = 1, Max = 10 },
	},
	Commands = {
		{
			Name = "greet",
			Usage = "/greet [name]",
			Description = "say hello",
			Run = function(ctx)
				ctx.success(("%s %s"):format("hello", ctx.Args[1] or "there"))
			end,
		},
	},
	Functions = {
		{
			Id = "name",
			Text = "Print name",
			Run = function(list)
				print(list[1].Name)
			end,
		},
	},
	Tab = {
		Title = "My Plugin",
		Build = function(page, api)
			local view = api.ui.page({ Parent = page, Scroll = true })
			api.ui.section(view.Body, "Settings")
			api.ui.field(view.Body, api.settings.item("count"), api.settings)
		end,
	},
	Load = function(api)
		api.console.print("loaded from " .. P.Path)
		api.connect(api.settings.Changed, function(id, value)
			api.console.print(("%s is now %s"):format(id, tostring(value)))
		end)
	end,
	Unload = function(api)
		-- end anything you started yourself (the api's helpers end on their own)
	end,
}
```
