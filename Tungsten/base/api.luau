--[[
	Tungsten · base/api
	What a plugin gets to work with. The plugin host (base/plugins) gives
	each plugin in Tungsten/plugins one of these; console code can make
	one too (for trying things out), except for an id a plugin folder uses:

		local api = tungsten.api("myplugin", { Name = "My Plugin" })

	Everything made through it belongs to the plugin (Owner = its id), so
	api:remove() takes it all away again: commands, variables it set,
	explorer functions, menu entries, tabs, docs topics, undo steps, its
	owned connections and threads. The host calls it after Unload.

	Console
		api.console.register({ Name = "hello", Usage = "/hello [name]",
			Description = "say hello", Run = function(ctx) ctx.success("hi") end })
		                                  -- runs as :myplugin.hello (and /hello while no
		                                  -- core command or other plugin has that name)
		api.console.unregister("hello")
		api.console.print(text)           -- [plugin] My Plugin: text   (also info, success,
		api.console.warn(text) ; api.console.error(text)                  -- warn, error, value)
		api.console.run("/select remotes")
		api.console.onLine(function(line) end)   -- every new output line
		api.console.reporter              -- the full reporter (try, wrap, detail, …)

	Variables (read all of them, $sel / $last / $err included; change only its own)
		api.variables.get("sel")          -> value, exists
		api.variables.ref("list1")        -> like var("list1") in console code
		api.variables.set("hits", 3)      -- the plugin owns $hits; a name you or
		                                  -- another plugin has -> false, "$hits belongs to …"
		api.variables.unset("hits")       -- only its own
		api.variables.list() ; api.variables.names() ; api.variables.owner("hits")
		api.variables.watch("sel", function(value, old, removed, by) end) -> connection
		api.variables.selection()         -> the explorer selection as a list
		api.variables.Changed:Connect(function(name, value, old, removed, by) end)
		                                  -- by: who changed it ("console" / "explorer" =
		                                  -- you, or a plugin id). Watches and Changed
		                                  -- connections end when the plugin stops.

	Explorer (read-only: no setting the selection or writing properties)
		api.explorer.getSelection() ; api.explorer.SelectionChanged:Connect(fn)  (owned)
		api.explorer.getProperties(instance) ; api.explorer.find(query, limit)
		api.explorer.addFunction({ Id, Text, Icon, AppliesTo(list), Run(list) })
		api.explorer.isFrozen() ; api.explorer.frozenState(instance) ; api.explorer.FrozenChanged:Connect(fn)
		api.tabs.add(definition)          -- another side-bar tab (prefer sub-tabs)
		api.undo.record(entry)            -- so /undo can take its change back

	Settings (the plugin's own, shown on its page in the Plugins tab)
		api.settings.get("speed") ; api.settings.set("speed", 20)
		api.settings.reset("speed") ; api.settings.all()
		api.settings.items()              -- the declared items (Id, Kind, Text, Default, …)
		api.settings.Changed              -- (key, value)
		Saved in Tungsten/plugins/<Folder>/settings.json (through
		base/datastore) for a plugin the host loaded; kept in memory for an
		api made in the console.

	The loaded target (base/loaded: one for every tab; Explorer › Load,
	the path bar, /load and plugins all change it)
		api.loaded.get()                  -> the first item (Instance or target) or nil
		api.loaded.list() ; api.loaded.value() ; api.loaded.values()
		api.loaded.set(item | { items })  -- load for every tab (by = the plugin)
		api.loaded.target(value, { Kind?, Label?, Origin? })  -- wrap a function,
		                                  -- table, connection… to load it
		api.loaded.clear()
		api.loaded.Changed:Connect(function(items, by) end)   (owned)
		A tab's OnLoad(values, tab, items) runs for every load, whichever
		tab is open.

	Other plugins (the prime plugins it lists in Requires or Uses)
		api.plugins.get("scanner")        -> that plugin's Exports, or nil + why
		api.plugins.open("scriptviewer", focus?) -> ok, why
		                                  -- opens that plugin's tab and calls its
		                                  -- Exports.reveal(focus)
		api.plugins.isOn("scanner")       -> boolean
		Requires: it can't start without them. Uses: it starts anyway, and
		get / open answer nil + why while the other one is off.

	Owned helpers (stopped when the plugin stops; a fault in one prints
	under the plugin's name and nothing else stops)
		api.connect(signal, fn)           -> connection
		api.spawn(fn, ...) ; api.delay(seconds, fn, ...)   -> thread
		api.every(seconds, fn)            -> { Stop() }   (fn runs every `seconds`)
		api.bin                           -- a bin cleaned on remove (bin:Add(thing))
		Anything the plugin connects or starts itself (raw :Connect,
		task.spawn) is its own to stop, in Unload.

	Files (paths inside the plugin's folder; the whole Tungsten folder is
	open to plugins too through readfile and the rest)
		api.files.read("data/log.txt") ; api.files.write(rel, text) ; api.files.append(rel, text)
		api.files.exists(rel) ; api.files.isFolder(rel) ; api.files.list(rel?) -> names
		api.files.makeFolder(rel) ; api.files.delete(rel) ; api.files.path(rel) -> full path

	Everything else a plugin registers carries its id (Owner / Origin set
	for it) and goes when it stops:
		api.ui.new(name, props) ; api.ui.on / filter(…)          (Origin / Owner = the plugin)
		api.ui.page / section / row / field / placeholder / panes  (layout pieces, base/ui/components/page)
		api.ui.subtabs({ Tabs = { { Id, Title, Build(view) } } })  (views inside its one tab)
		api.tab.select() ; api.tab.badge(n) ; api.tab.update(fields) ; api.tab.isOpen()
		api.pathbar.show(instance)        -- = api.loaded.set (one path bar for all tabs)
		api.menus.add / addMany / define / remove / open / addRowKind
		api.prompt.confirm / input / choice / form / custom / popover / await / registerFieldKind
		api.notify.show(opts | text) ; api.notify.registerKind(name, def)
		api.tooltip.attach(target, text, opts) ; api.tooltip.show(text, pos, size, side)
		api.icons.register ; api.editors.register(key, def) ; api.types.register(name, def)
		api.classes.add(name, category, opts) ; api.picker.registerKind(name, def)
		api.explorer.addInsertGroup(group) ; api.explorer.addFilterGroup(id, def)
		api.docs.add / addSection / addDirective / open

		api:remove()                      -- undo everything above; the api
		                                  -- can't register anything after that
]]

local T = ...
local signal = T.import("base/signal")

local Api = {}
local made: { [string]: any } = {}
local locks: { [string]: { Key: any, Folder: string } } = {}

--[[
	Ids that belong to a plugin folder are locked: only the plugin host
	(which holds the key) can make an api for them, so a test api made in
	the console can't replace a loaded plugin by accident.
		local key = Api.lock(id, folder) ; Api.new(id, { Key = key, … })
		Api.unlock(id, key) ; Api.lockedBy(id) -> folder?
]]
function Api.lock(id: string, folder: string): any
	local entry = locks[id]
	if entry then
		return entry.Key
	end
	local key = {} -- only its identity matters
	locks[id] = { Key = key, Folder = folder }
	return key
end

function Api.unlock(id: string, key: any): boolean
	local entry = locks[id]
	if entry and entry.Key == key then
		locks[id] = nil
		return true
	end
	return false
end

function Api.lockedBy(id: string): string?
	local entry = locks[id]
	return if entry then entry.Folder else nil
end

-- The kinds a plugin setting can be, and the Lua type its value has.
Api.SettingKinds = {
	toggle = "boolean",
	number = "number",
	choice = "any",
	color = "table",
	action = false, -- a button, no value
}

local function copy(value)
	if type(value) == "table" then
		local result = {}
		for key, item in value do
			result[key] = copy(item)
		end
		return result
	end
	return value
end

-- Checks a declared settings list; returns the problem, if any.
function Api.checkSettings(items: any): string?
	if items == nil then
		return nil
	end
	if type(items) ~= "table" then
		return "Settings must be a list"
	end
	local seen = {}
	for index, item in items do
		if type(item) ~= "table" then
			return ("Settings[%d] is not a table"):format(index)
		end
		if type(item.Id) ~= "string" or item.Id == "" then
			return ("Settings[%d] needs an Id"):format(index)
		end
		if seen[item.Id] then
			return ("Settings: '%s' is there twice"):format(item.Id)
		end
		seen[item.Id] = true
		local kind = Api.SettingKinds[item.Kind]
		if kind == nil then
			return ("Settings '%s': Kind must be toggle, number, choice, color or action"):format(item.Id)
		end
		if item.Kind == "action" then
			if type(item.Run) ~= "function" then
				return ("Settings '%s': an action needs Run"):format(item.Id)
			end
		elseif item.Default == nil then
			return ("Settings '%s' needs a Default"):format(item.Id)
		elseif kind ~= "any" and type(item.Default) ~= kind then
			return ("Settings '%s': Default must be a %s"):format(item.Id, kind)
		elseif item.Kind == "choice" and type(item.Options) ~= "table" then
			return ("Settings '%s': a choice needs Options"):format(item.Id)
		elseif item.Kind == "color" and #item.Default ~= 3 then
			return ("Settings '%s': a color Default is { r, g, b }"):format(item.Id)
		end
	end
	return nil
end

-- What plugins/<Folder>/plugin.luau returns (base/plugins loads it):
--	{ Name, Id?, Version?, Author?, Description?, Icon?, Order?,
--	  Settings? = { item }, Commands? = { command }, Functions? = { function },
--	  Tab? = { Title, Icon?, Build(page, api), OnLoad?(values, api, items),
--	           OnSelect?(api), OnDeselect?(api) },
--	  Docs? = "file.md" | { topic },
--	  Requires? = { prime plugin ids }, Uses? = { prime plugin ids },
--	  Exports? = table | function(api),
--	  Load?(api), Unload?(api) }
local OPTIONAL_STRINGS = { "Id", "Version", "Author", "Description", "Icon" }
local OPTIONAL_LISTS = { "Commands", "Functions" }
local OPTIONAL_FUNCTIONS = { "Load", "Unload" }

-- The id a plugin goes by: its Id, else the folder name made safe.
function Api.idFor(definition: any, folder: string?): string?
	local id = if type(definition) == "table" then definition.Id else nil
	if type(id) ~= "string" and folder then
		id = folder:lower():gsub("[^%w_%-]", "_")
		if not id:match("^[%a_]") then
			id = "_" .. id
		end
	end
	return id
end

-- Returns the problem with a plugin definition, or nil when it is fine.
function Api.checkDefinition(definition: any, folder: string?): string?
	if type(definition) ~= "table" then
		return "plugin.luau must return a table"
	end
	if type(definition.Name) ~= "string" or definition.Name == "" then
		return "Name is missing"
	end
	for _, key in OPTIONAL_STRINGS do
		if definition[key] ~= nil and type(definition[key]) ~= "string" then
			return key .. " must be text"
		end
	end
	local id = Api.idFor(definition, folder)
	if type(id) ~= "string" or not id:match("^[%a_][%w_%-]*$") then
		return "Id may only use letters, digits, _ and -"
	end
	if id == "core" or id == "tungsten" then
		return ("'%s' is Tungsten's own id"):format(id)
	end
	for _, key in OPTIONAL_LISTS do
		local list = definition[key]
		if list ~= nil then
			if type(list) ~= "table" then
				return key .. " must be a list"
			end
			for index, item in list do
				if type(item) ~= "table" or type(item.Run) ~= "function" then
					return ("%s[%d] needs Run"):format(key, index)
				end
			end
		end
	end
	if definition.Order ~= nil and type(definition.Order) ~= "number" then
		return "Order must be a number"
	end
	for _, key in { "Requires", "Uses" } do
		local list = definition[key]
		if list ~= nil then
			if type(list) ~= "table" then
				return key .. " must be a list of plugin ids"
			end
			for index, other in list do
				if type(other) ~= "string" then
					return ("%s[%s] must be a plugin id"):format(key, tostring(index))
				end
			end
		end
	end
	if definition.Prime ~= nil and type(definition.Prime) ~= "boolean" then
		return "Prime must be true or false"
	end
	local exports = definition.Exports
	if exports ~= nil and type(exports) ~= "table" and type(exports) ~= "function" then
		return "Exports must be a table or a function"
	end
	local docs = definition.Docs
	if docs ~= nil and type(docs) ~= "string" and type(docs) ~= "table" then
		return "Docs must be a file name or a topic table"
	end
	for _, key in OPTIONAL_FUNCTIONS do
		if definition[key] ~= nil and type(definition[key]) ~= "function" then
			return key .. " must be a function"
		end
	end
	local tab = definition.Tab
	if tab ~= nil and (type(tab) ~= "table" or type(tab.Title) ~= "string" or type(tab.Build) ~= "function") then
		return "Tab needs Title and Build"
	end
	if tab ~= nil then
		for _, key in { "OnLoad", "OnSelect", "OnDeselect" } do
			if tab[key] ~= nil and type(tab[key]) ~= "function" then
				return ("Tab.%s must be a function"):format(key)
			end
		end
	end
	return Api.checkSettings(definition.Settings)
end

-- One plugin's settings: declared items with defaults, saved as JSON
-- when there is a path, in memory otherwise.
local function settingsStore(id: string, items: { any }?, path: string?)
	local DataStore = T.import("base/datastore")
	local file = if path then DataStore.open(path, { Name = "plugins" }) else nil
	local store = { Changed = signal.new() }
	local declared = {}
	local order = {}
	for _, item in items or {} do
		declared[item.Id] = item
		table.insert(order, item)
	end
	local values = {}
	for key, item in declared do
		if item.Kind ~= "action" then
			values[key] = copy(item.Default)
		end
	end
	if file then
		local decoded, problem = file:read()
		if decoded then
			for key, value in decoded do
				local item = declared[key]
				if not item or item.Kind == "action" then
					values[key] = value -- undeclared keys are the plugin's own business
				elseif type(value) == type(item.Default) then
					values[key] = value
				end
			end
		elseif problem then
			T.Log.warn("plugins", ("%s: settings.json could not be read; defaults used"):format(id))
		end
	end

	local function snapshot()
		return values
	end
	local function queue()
		if file then
			file:queue(snapshot)
		end
	end
	store.flush = function()
		if file then
			file:flush()
		end
	end

	-- Fits a value to its declared item; nil when it can't.
	local function fit(item, value)
		if item.Kind == "toggle" then
			return if type(value) == "boolean" then value else nil
		elseif item.Kind == "number" then
			value = tonumber(value)
			if not value or value ~= value then
				return nil
			end
			if item.Min then
				value = math.max(value, item.Min)
			end
			if item.Max then
				value = math.min(value, item.Max)
			end
			return value
		elseif item.Kind == "choice" then
			for _, option in item.Options do
				local optionValue = if type(option) == "table" then option.Value else option
				if optionValue == value then
					return value
				end
			end
			return nil
		elseif item.Kind == "color" then
			if typeof(value) == "Color3" then
				return { math.floor(value.R * 255 + 0.5), math.floor(value.G * 255 + 0.5), math.floor(value.B * 255 + 0.5) }
			end
			return if type(value) == "table" and #value == 3 then copy(value) else nil
		end
		return value
	end

	function store.get(key: string): any
		return copy(values[key])
	end
	function store.set(key: string, value: any): boolean
		local item = declared[key]
		if item then
			if item.Kind == "action" then
				return false
			end
			value = fit(item, value)
			if value == nil then
				return false
			end
		end
		if type(value) ~= "table" and values[key] == value then
			return true
		end
		values[key] = copy(value)
		queue()
		store.Changed:Fire(key, copy(value))
		return true
	end
	function store.reset(key: string): boolean
		local item = declared[key]
		if not item or item.Kind == "action" then
			return false
		end
		return store.set(key, copy(item.Default))
	end
	function store.all(): { [string]: any }
		return copy(values)
	end
	function store.items(): { any }
		return table.clone(order)
	end
	function store.item(key: string)
		return declared[key]
	end
	store.Path = path
	return store
end
Api.settingsStore = settingsStore

function Api.new(id: string, opts: { [string]: any }?)
	assert(type(id) == "string" and id:match("^[%a_][%w_%-]*$"), "a plugin id is letters, digits, _ and -")
	assert(id ~= "core", "core is Tungsten's own id")
	opts = opts or {}
	local lock = locks[id]
	if lock and (opts :: any).Key ~= lock.Key then
		error(("'%s' belongs to the plugin in plugins/%s"):format(id, lock.Folder), 2)
	end
	local name = (opts :: any).Name or id
	if made[id] then
		made[id]:remove() -- a second api for the same id replaces the first
	end
	local Console = T.Console
	local Variables = T.import("base/variables")
	local Commands = T.import("console/commands")
	local reporter = Console.reporter(id, { Label = name })

	local api = { Id = id, Name = name }
	local alive = true
	-- Registering through a removed api would leave things nobody owns.
	local function live()
		if not alive then
			error(("%s was unloaded; its api can't add anything now"):format(name), 3)
		end
	end
	local function owned(definition: { [string]: any }, owner: string)
		live()
		local copied = table.clone(definition)
		copied.Owner = owner
		return copied
	end

	api.console = {
		reporter = reporter,
		register = function(definition)
			return Commands.register(owned(definition, id))
		end,
		unregister = function(commandName: string)
			return Commands.unregister(id, commandName)
		end,
		print = function(...)
			return reporter:info(...)
		end,
		info = function(...)
			return reporter:info(...)
		end,
		success = function(...)
			return reporter:success(...)
		end,
		warn = function(...)
			return reporter:warn(...)
		end,
		error = function(...)
			return reporter:error(...)
		end,
		value = function(...)
			return reporter:value(...)
		end,
		run = function(input: string)
			return Console.run(input)
		end,
		onLine = function(fn)
			return Console.LineAdded:Connect(fn)
		end,
	}

	-- Listeners the plugin makes through the api; disconnected on remove.
	local connections = {}
	local function track(connection)
		table.insert(connections, connection)
		return connection
	end

	api.variables = {
		Changed = {
			Connect = function(_, fn)
				live()
				return track(Variables.Changed:Connect(fn))
			end,
		},
		owner = Variables.owner,
		get = Variables.get,
		has = Variables.has,
		ref = Variables.ref,
		group = Variables.group,
		info = Variables.info,
		frozenState = Variables.frozenState,
		list = Variables.list,
		names = Variables.names,
		watch = function(varName: string, fn)
			live()
			return track(Variables.watch(varName, fn))
		end,
		isReserved = Variables.isReserved,
		set = function(varName: string, value: any)
			live()
			return Variables.set(varName, value, { Source = id })
		end,
		unset = function(varName: string)
			live()
			return Variables.unset(varName, { Source = id })
		end,
		selection = function(): { Instance }
			local value = Variables.get("sel")
			if typeof(value) == "Instance" then
				return { value }
			end
			return if type(value) == "table" then table.clone(value) else {}
		end,
	}

	-- Owned helpers ------------------------------------------------------
	local threads = {}
	api.bin = signal.bin()

	-- fn guarded: a fault prints under the plugin's name (console/reporter).
	local function guarded(fn, what: string)
		assert(type(fn) == "function", what .. " needs a function")
		return function(...)
			local ok, err = xpcall(fn, function(message)
				return tostring(message) .. "\n" .. debug.traceback(tostring(message), 2)
			end, ...)
			if not ok then
				T.import("console/reporter").ownerFault(id, what, err)
			end
		end
	end

	function api.connect(source, fn)
		live()
		assert(source ~= nil and source.Connect ~= nil, "api.connect needs a signal")
		return track(source:Connect(guarded(fn, "a connection")))
	end

	function api.spawn(fn, ...)
		live()
		local thread = task.spawn(guarded(fn, "a thread"), ...)
		table.insert(threads, thread)
		return thread
	end

	function api.delay(seconds: number, fn, ...)
		live()
		local thread = task.delay(seconds, guarded(fn, "a delayed call"), ...)
		table.insert(threads, thread)
		return thread
	end

	function api.every(seconds: number, fn)
		live()
		assert(type(seconds) == "number" and seconds > 0, "api.every needs a time in seconds")
		local step = guarded(fn, "a repeating call")
		local handle = { Running = true }
		local thread = task.spawn(function()
			while handle.Running and alive do
				task.wait(seconds)
				if not (handle.Running and alive) then
					break
				end
				step()
			end
		end)
		function handle.Stop()
			handle.Running = false
			if coroutine.running() ~= thread then
				pcall(task.cancel, thread)
			end
		end
		table.insert(threads, thread)
		return handle
	end

	-- A signal a plugin may connect to; the connections are its own.
	local function ownedSignal(source)
		if source == nil then
			return nil
		end
		return {
			Connect = function(_, fn)
				return api.connect(source, fn)
			end,
		}
	end

	local Explorer = T.Explorer
	api.explorer = {
		SelectionChanged = Explorer and ownedSignal(Explorer.SelectionChanged),
		getSelection = function()
			return T.Explorer.getSelection()
		end,
		getProperties = function(instance, propOpts)
			return T.Explorer.getProperties(instance, propOpts)
		end,
		find = function(query: string, limit: number?)
			return T.Explorer.find(query, limit)
		end,
		addFunction = function(definition)
			return T.Explorer.addFunction(owned(definition, id))
		end,
		addInsertGroup = function(group)
			live()
			return T.import("base/explorer/insert").addGroup(group, id)
		end,
		addFilterGroup = function(groupId: string, definition)
			return T.import("base/explorer/filter").addGroup(groupId, owned(definition, id))
		end,
		-- freeze (read-only): is the tree frozen, and what it shows for an object
		FrozenChanged = Explorer and ownedSignal(Explorer.FrozenChanged),
		isFrozen = function(): boolean
			return T.Explorer.isFrozen()
		end,
		frozenState = function(instance)
			return T.Explorer.frozenState(instance)
		end,
	}

	-- The one loaded target (base/loaded), shared by every tab.
	local Loaded = T.Loaded or T.import("base/loaded")
	api.loaded = {
		Changed = ownedSignal(Loaded.Changed),
		get = function()
			return Loaded.get()
		end,
		list = function()
			return Loaded.list()
		end,
		value = function()
			return Loaded.value()
		end,
		values = function()
			return Loaded.values()
		end,
		isTarget = function(x)
			return Loaded.isTarget(x)
		end,
		-- what was loaded before (the path bar's back button)
		back = function()
			live()
			return Loaded.back(id)
		end,
		canGoBack = function()
			return Loaded.canGoBack()
		end,
		previous = function()
			return Loaded.previous()
		end,
		target = function(value, targetOpts)
			return Loaded.target(value, targetOpts)
		end,
		-- how a value inside a script is reached (base/access): pass it as
		-- target{ Access = ... } and the path bar shows it
		access = T.Access and {
			root = T.Access.root,
			key = T.Access.key,
			upvalue = T.Access.upvalue,
			code = T.Access.code,
			parse = T.Access.parse,
			resolve = T.Access.resolve,
			find = T.Access.find,
			findFrom = T.Access.findFrom,
			is = T.Access.is,
		} or nil,
		set = function(items)
			live()
			return Loaded.load(items, { By = id })
		end,
		clear = function()
			return Loaded.clear(id)
		end,
	}

	-- The path bar shows what is loaded: show(x) loads x for every tab.
	-- (Earlier tab / sub-tab arguments are ignored: one path bar for all.)
	api.pathbar = {
		show = function(instance: any, ...: any)
			if instance == nil then
				return Loaded.clear(id)
			end
			live()
			return Loaded.load({ instance }, { By = id })
		end,
		clear = function(...: any)
			return Loaded.clear(id)
		end,
	}

	-- The plugin's own tab in the side bar (its Tab in the definition).
	api.tab = {
		select = function()
			if T.Tabs then
				T.Tabs:Select(id)
			end
		end,
		badge = function(value: any)
			return T.Registry.updateTab(id, { Badge = value })
		end,
		update = function(changes)
			return T.Registry.updateTab(id, changes)
		end,
		isOpen = function(): boolean
			return T.Tabs ~= nil and T.Tabs.Selected == id
		end,
	}

	api.menus = {
		add = function(menuId: string, entry)
			live()
			return T.Menus.add(menuId, entry, id)
		end,
		define = function(menuId: string, definition)
			return T.Menus.define(menuId, owned(definition, id))
		end,
		addMany = function(menuId: string, entries)
			live()
			return T.Menus.addMany(menuId, entries, id)
		end,
		remove = function(menuId: string, entryId: string)
			return T.Menus.remove(menuId, entryId, id)
		end,
		open = function(menuId: string, ctx, menuOpts)
			return T.Menus.open(menuId, ctx, menuOpts)
		end,
		addRowKind = function(kindName: string, definition)
			return T.import("base/ui/components/contextmenu").addKind(kindName, owned(definition, id))
		end,
	}

	api.tabs = {
		add = function(definition)
			return T.Registry.addTab(owned(definition, id))
		end,
		update = function(tabId: string, changes)
			return T.Registry.updateTab(tabId, changes)
		end,
	}

	api.docs = {
		add = function(topic)
			return T.Docs.addTopic(owned(topic, id))
		end,
		addSection = function(topicId: string, section)
			return T.Docs.addSection(topicId, owned(section, id))
		end,
		addDirective = function(directiveName: string, definition)
			return T.Docs.addDirective(directiveName, owned(definition, id))
		end,
		open = function(topicId: string)
			if T.Tabs then
				T.Tabs:Select("documentation")
			end
			return T.Docs.open(topicId)
		end,
	}

	api.undo = {
		record = function(entry)
			return T.Undo.record(owned(entry, id))
		end,
	}

	api.icons = {
		register = function(iconName: string, source: any, iconOpts)
			live()
			local merged = table.clone(iconOpts or {})
			merged.Owner = id
			return T.Icons.register(iconName, source, merged)
		end,
	}

	api.settings = settingsStore(id, (opts :: any).Settings, (opts :: any).SettingsPath)
	api.Folder = (opts :: any).Folder -- set for plugins the manager loaded

	-- The UI framework with the plugin as Origin / Owner.
	local function withOrigin(o)
		local copied = table.clone(o or {})
		copied.Origin = id
		return copied
	end
	local function withOwner(o)
		local copied = table.clone(o or {})
		copied.Owner = id
		return copied
	end
	local Page = T.import("base/ui/components/page")
	local SubTabs = T.import("base/ui/components/subtabs")
	api.ui = setmetatable({
		new = function(componentName: string, props)
			live()
			return T.UI.new(componentName, withOrigin(props))
		end,
		-- layout pieces for its tab (base/ui/components/page)
		page = function(props)
			live()
			return Page.new(withOrigin(props))
		end,
		section = Page.section,
		row = Page.row,
		field = Page.field,
		placeholder = Page.placeholder,
		panes = Page.panes,
		-- views inside its one tab (P10)
		subtabs = function(props)
			live()
			local options = withOrigin(props)
			options.TabId = options.TabId or id
			return SubTabs.new(options)
		end,
		on = function(component: string, event: string, fn, hookOpts)
			live()
			return T.UI.on(component, event, fn, withOwner(hookOpts))
		end,
		filter = function(component: string, stage: string, fn, hookOpts)
			live()
			return T.UI.filter(component, stage, fn, withOwner(hookOpts))
		end,
	}, { __index = T.UI })

	local Prompt = T.import("base/ui/components/prompt")
	api.prompt = {
		await = Prompt.await,
		registerFieldKind = function(kindName: string, definition)
			return Prompt.registerFieldKind(kindName, owned(definition, id))
		end,
	}
	for _, kind in { "confirm", "input", "choice", "form", "custom", "popover" } do
		api.prompt[kind] = function(promptOpts)
			live()
			return Prompt[kind](withOrigin(promptOpts))
		end
	end

	local Notify = T.import("base/ui/components/notify")
	api.notify = {
		show = function(notice)
			live()
			if type(notice) ~= "table" then
				notice = { Text = tostring(notice) }
			end
			return Notify.show(withOrigin(notice))
		end,
		registerKind = function(kindName: string, definition)
			return Notify.registerKind(kindName, owned(definition, id))
		end,
	}

	local Tooltip = T.import("base/ui/components/tooltip")
	api.tooltip = {
		attach = function(target, text, tipOpts)
			live()
			return Tooltip.attach(target, text, withOrigin(tipOpts))
		end,
		show = function(text: string, anchorPos, anchorSize, side)
			return Tooltip.show(text, anchorPos, anchorSize, side, id)
		end,
		hide = Tooltip.hide,
	}

	api.editors = {
		register = function(key: string, definition)
			return T.import("base/explorer/editors").register(key, owned(definition, id))
		end,
	}
	local Types = T.import("base/types")
	api.types = setmetatable({
		register = function(typeName: string, definition)
			return Types.registerType(typeName, owned(definition, id))
		end,
	}, { __index = Types })
	api.classes = {
		add = function(className: string, category: string?, classOpts)
			live()
			return T.import("base/data/classes").add(className, category, withOwner(classOpts))
		end,
	}
	api.picker = {
		registerKind = function(kindName: string, definition)
			return T.import("base/ui/components/typepicker").registerKind(kindName, owned(definition, id))
		end,
	}
	api.insert = { addGroup = api.explorer.addInsertGroup }

	-- Files inside the plugin's folder.
	local folderPath = if (opts :: any).Folder then T.Root .. "/plugins/" .. (opts :: any).Folder else nil
	local function pathOf(rel: string?): string
		if not folderPath then
			error("this api has no plugin folder (it was made in the console)", 3)
		end
		local cleaned = tostring(rel or ""):gsub("\\", "/"):gsub("^/+", "")
		return if cleaned == "" then folderPath else folderPath .. "/" .. cleaned
	end
	api.files = {
		path = function(rel: string?): string
			return pathOf(rel)
		end,
		read = function(rel: string): string
			return readfile(pathOf(rel))
		end,
		write = function(rel: string, data: any)
			live()
			writefile(pathOf(rel), tostring(data))
		end,
		append = function(rel: string, data: any)
			live()
			local path = pathOf(rel)
			if isfile(path) then
				appendfile(path, tostring(data))
			else
				writefile(path, tostring(data))
			end
		end,
		exists = function(rel: string): boolean
			local path = pathOf(rel)
			return isfile(path) or isfolder(path)
		end,
		isFolder = function(rel: string): boolean
			return isfolder(pathOf(rel))
		end,
		list = function(rel: string?): { string }
			local base = pathOf(rel)
			local names = {}
			for _, entry in listfiles(base) do
				table.insert(names, (tostring(entry):gsub("\\", "/"):match("([^/]+)$")))
			end
			table.sort(names)
			return names
		end,
		makeFolder = function(rel: string)
			live()
			makefolder(pathOf(rel))
		end,
		delete = function(rel: string)
			live()
			local path = pathOf(rel)
			if isfolder(path) then
				delfolder(path)
			elseif isfile(path) then
				delfile(path)
			end
		end,
	}

	-- The prime plugins this one lists in Requires or Uses (base/plugins).
	local function host()
		local plugins = T.Plugins
		if type(plugins) ~= "table" or type(plugins.exportsFor) ~= "function" then
			return nil
		end
		return plugins
	end
	api.plugins = {
		get = function(other: string)
			local plugins = host()
			if not plugins then
				return nil, "no plugin host"
			end
			return plugins.exportsFor(id, other)
		end,
		open = function(other: string, focus: any?)
			local plugins = host()
			if not plugins or type(plugins.open) ~= "function" then
				return false, "no plugin host"
			end
			return plugins.open(id, other, focus)
		end,
		isOn = function(other: string): boolean
			local plugins = host()
			local record = plugins and plugins.get(other)
			return record ~= nil and record.State == "on"
		end,
	}

	-- Takes away everything this plugin added.
	function api.remove(_self)
		if made[id] ~= api then
			return 0 -- already removed (or replaced)
		end
		made[id] = nil
		alive = false
		for _, connection in connections do
			pcall(function()
				connection:Disconnect()
			end)
		end
		table.clear(connections)
		local current = coroutine.running()
		for _, thread in threads do
			if thread ~= current and coroutine.status(thread) ~= "dead" then
				pcall(task.cancel, thread)
			end
		end
		table.clear(threads)
		pcall(api.bin.Clean, api.bin)
		pcall(api.settings.flush)
		local count = 0
		local ok, removed = pcall(T.UI.removeOwner, id)
		if ok and type(removed) == "number" then
			count += removed
		end
		return count
	end

	made[id] = api
	return api
end

function Api.get(id: string)
	return made[id]
end

function Api.isAlive(api): boolean
	return type(api) == "table" and made[api.Id] == api
end

T.Bin:Add(function()
	table.clear(made)
	table.clear(locks)
end)

return Api
