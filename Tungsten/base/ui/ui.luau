--[[
	Tungsten · base/ui/ui
	The UI framework: every component (List, Dropdown, TypePicker,
	ContextMenu, CellEditor, ColorPicker, SequenceEditor, Prompt, Notify,
	Tooltip, Input, Button, Toggle, Label, TextEditor, Scroll) registers
	here. Plugins use it to

	- make components by name:     UI.new("Dropdown", { ... })
	- listen to what they do:      UI.on("List", "SelectionChanged", fn, opts)
	- adjust the data they show:   UI.filter("Dropdown", "Options", fn, opts)

	The look of a component never changes: filters adjust data (which
	options, which menu items, the text in a cell), events report what
	happened. Each component's events and filters are listed with
	UI.describe(name) and the /ui command.

		UI.on(component, event, function(...) end, {
			Owner = "myplugin",   -- for cleanup (UI.removeOwner)
			Scope = "own",        -- "own": only components this owner made
		})                        -- "all": every component, Tungsten's too
		UI.filter(component, stage, function(value, ...) return newValue end, opts)
		    -- return nil to keep the value; a value of another type is ignored

	Who made a component: props.Origin ("core" by default; plugins get
	their id). Hooks with Scope "own" only see their owner's components.

	Components call (internally)
		UI.fire(component, event, origin, ...)
		UI.apply(component, stage, origin, value, ...) -> value
]]

local T = ...

local UI = {}
UI.Components = {} :: { [string]: any }

-- A plugin's failing hook prints under its name (console/reporter);
-- Tungsten's own go to the log.
local function fault(owner: string, what: string, err: any)
	T.Log.error("ui", ("[%s] %s failed:\n%s"):format(owner, what, tostring(err)))
	if owner ~= "core" then
		local ok, Reporter = pcall(T.import, "console/reporter")
		if ok then
			Reporter.ownerFault(owner, what, err)
		end
	end
end

local hooks: { [string]: { [string]: { any } } } = {} -- component -> event -> list
local filters: { [string]: { [string]: { any } } } = {} -- component -> stage -> list
local seq = 0

----------------------------------------------------------------------
-- Registry
----------------------------------------------------------------------

--[[
	UI.register(name, module, info)
	info.Constructor  "new" (default), "open", or a function(props)
	info.Events       { name = "what it passes" }
	info.Filters      { name = "value · extra arguments" }
	info.Description  one line
]]
function UI.register(name: string, module: any, info: { [string]: any }?)
	assert(type(name) == "string" and name ~= "", "a component needs a name")
	info = info or {}
	local events = table.clone((info :: any).Events or {})
	events.Created = events.Created or "component, props · a new one was made"
	UI.Components[name] = {
		Name = name,
		Module = module,
		Constructor = (info :: any).Constructor or "new",
		Events = events,
		Filters = (info :: any).Filters or {},
		Description = (info :: any).Description or "",
		Owner = (info :: any).Owner or "core",
	}
	return module
end

function UI.get(name: string): any
	local entry = UI.Components[name]
	return if entry then entry.Module else nil
end

function UI.list(): { string }
	local names = {}
	for name in UI.Components do
		table.insert(names, name)
	end
	table.sort(names)
	return names
end

-- { Name, Description, Events = { {Name, Info, Hooks} }, Filters = { ... } }
function UI.describe(name: string)
	local entry = UI.Components[name]
	if not entry then
		return nil
	end
	local function listOf(map, store)
		local out = {}
		for key, text in map do
			local owners = {}
			for _, hook in (store[name] or {})[key] or {} do
				table.insert(owners, hook.Owner .. (if hook.Scope == "all" then " (all)" else ""))
			end
			table.insert(out, { Name = key, Info = text, Hooks = owners })
		end
		table.sort(out, function(a, b)
			return a.Name < b.Name
		end)
		return out
	end
	return {
		Name = name,
		Description = entry.Description,
		Constructor = entry.Constructor,
		Events = listOf(entry.Events, hooks),
		Filters = listOf(entry.Filters, filters),
	}
end

-- Makes a component by name. props.Origin says who made it.
function UI.new(name: string, props: { [string]: any }?)
	local entry = UI.Components[name]
	if not entry then
		error(("no UI component '%s' · UI.list() has them"):format(tostring(name)), 2)
	end
	props = props or {}
	local constructor = entry.Constructor
	if type(constructor) == "function" then
		return constructor(props)
	end
	local fn = entry.Module[constructor]
	assert(type(fn) == "function", ("%s has no %s function"):format(name, tostring(constructor)))
	return fn(props)
end

----------------------------------------------------------------------
-- Hooks and filters
----------------------------------------------------------------------

local Handle = {}
Handle.__index = Handle
function Handle:Remove()
	local list = self.Store[self.Component] and self.Store[self.Component][self.Key]
	if list then
		local index = table.find(list, self.Entry)
		if index then
			table.remove(list, index)
			return true
		end
	end
	return false
end

local function attach(store, kindLabel: string, component: string, key: string, fn: any, opts)
	local entry = UI.Components[component]
	if not entry then
		error(("no UI component '%s'"):format(tostring(component)), 3)
	end
	local declared = if kindLabel == "event" then entry.Events else entry.Filters
	if declared[key] == nil then
		error(("%s has no %s '%s'"):format(component, kindLabel, tostring(key)), 3)
	end
	assert(type(fn) == "function", "expected a function")
	opts = opts or {}
	local owner = opts.Owner or "core"
	local scope = opts.Scope or (if owner == "core" then "all" else "own")
	assert(scope == "own" or scope == "all", "Scope is \"own\" or \"all\"")
	seq += 1
	local record = { Fn = fn, Owner = owner, Scope = scope, Seq = seq, Order = tonumber(opts.Order) or 100 }
	store[component] = store[component] or {}
	store[component][key] = store[component][key] or {}
	local list = store[component][key]
	table.insert(list, record)
	table.sort(list, function(a, b)
		if a.Order ~= b.Order then
			return a.Order < b.Order
		end
		return a.Seq < b.Seq
	end)
	return setmetatable({ Store = store, Component = component, Key = key, Entry = record }, Handle)
end

function UI.on(component: string, event: string, fn: (...any) -> (), opts: { [string]: any }?)
	return attach(hooks, "event", component, event, fn, opts)
end

function UI.filter(component: string, stage: string, fn: (...any) -> any, opts: { [string]: any }?)
	return attach(filters, "filter", component, stage, fn, opts)
end

local function applies(record, origin: string?): boolean
	return record.Scope == "all" or record.Owner == (origin or "core")
end

-- Whether anything listens (lets components skip work on hot paths).
function UI.has(component: string, key: string): boolean
	local a = hooks[component] and hooks[component][key]
	local b = filters[component] and filters[component][key]
	return (a ~= nil and #a > 0) or (b ~= nil and #b > 0)
end

function UI.fire(component: string, event: string, origin: string?, ...)
	local list = hooks[component] and hooks[component][event]
	if not list or #list == 0 then
		return
	end
	for _, record in table.clone(list) do
		if applies(record, origin) then
			local ok, err = xpcall(record.Fn, debug.traceback, ...)
			if not ok then
				fault(record.Owner, ("%s.%s handler"):format(component, event), err)
			end
		end
	end
end

function UI.apply(component: string, stage: string, origin: string?, value: any, ...): any
	local list = filters[component] and filters[component][stage]
	if not list or #list == 0 then
		return value
	end
	for _, record in table.clone(list) do
		if applies(record, origin) then
			local ok, result = xpcall(record.Fn, debug.traceback, value, ...)
			if not ok then
				fault(record.Owner, ("%s.%s filter"):format(component, stage), result)
			elseif result ~= nil then
				if type(result) == type(value) or value == nil then
					value = result
				else
					fault(record.Owner, ("%s.%s filter"):format(component, stage), ("it returned a %s instead of a %s, so it was ignored"):format(type(result), type(value)))
				end
			end
		end
	end
	return value
end

----------------------------------------------------------------------
-- Cleanup
----------------------------------------------------------------------

-- Everything an owner added to the UI: hooks, filters, menus and menu
-- entries, row kinds, picker kinds, value types, classes and property
-- editors.
function UI.removeOwner(owner: string): number
	local removed = 0
	for _, store in { hooks, filters } do
		for _, byKey in store do
			for _, list in byKey do
				for index = #list, 1, -1 do
					if list[index].Owner == owner then
						table.remove(list, index)
						removed += 1
					end
				end
			end
		end
	end
	for name, entry in table.clone(UI.Components) do
		if entry.Owner == owner then
			UI.Components[name] = nil
			removed += 1
		end
	end
	local cascade = {
		{ "base/ui/menus", "removeOwner" },
		{ "base/ui/components/contextmenu", "removeOwner" },
		{ "base/ui/components/typepicker", "removeOwner" },
		{ "base/types", "removeOwner" },
		{ "base/data/classes", "removeOwner" },
		{ "base/explorer/editors", "removeOwner" },
		{ "base/explorer/filter", "removeOwner" },
		{ "base/registry", "removeOwner" },
		{ "base/ui/components/prompt", "removeOwner" },
		{ "base/ui/components/notify", "removeOwner" },
		{ "documentation/docs", "removeOwner" },
		{ "base/data/icons", "removeOwner" },
		{ "base/undo", "removeOwner" },
		{ "base/explorer/insert", "removeOwner" },
		{ "console/commands", "unregisterOwner" },
		{ "base/variables", "removeOwner" },
		{ "console/reporter", "remove" },
	}
	for _, step in cascade do
		local ok, module = pcall(T.import, step[1])
		if ok and type(module) == "table" and type(module[step[2]]) == "function" then
			local okRemove, count = pcall(module[step[2]], owner)
			if okRemove and type(count) == "number" then
				removed += count
			end
		end
	end
	return removed
end

T.Bin:Add(function()
	table.clear(hooks)
	table.clear(filters)
	table.clear(UI.Components)
end)

return UI
