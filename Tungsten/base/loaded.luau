--[[
	Tungsten · base/loaded
	The one loaded target every tab works on. Explorer › Load, the path
	bar (its arrow, a crumb, a typed path), /load and plugins all load
	through here; every tab is told, and the path bar shows it.

	What can be loaded
		Instances, or other values wrapped as a target:
			Loaded.target(value, { Kind?, Label?, Origin?, Access?, Info? }) -> target
		Kind is "function", "table", "thread", "connection", "call" or
		"value" (worked out from the value when left out). Label is what
		the path bar shows ("function onTouched"); Origin is the Instance
		it came from (a script), shown as the crumbs before it. Access
		(base/access) is how it is reached inside a script, e.g.
		require(game.ReplicatedStorage.Util).Sub.fn; the path bar shows it
		(and searches for one when none is given). Info is a table the tab
		that made the target may keep facts in (e.g. where a nested function
		came from); Tungsten doesn't read it.

		Loaded.load(items, opts?) -> handled   items: a list, or one item
			opts.By     who loaded it ("you" by default, or a plugin id)
		Loaded.clear(by?)
		Loaded.get()   -> the first item (Instance or target) or nil
		Loaded.list()  -> every item (a copy)
		Loaded.value() -> the first item's value (the Instance itself, or
		                  the target's Value)
		Loaded.values() -> every item's value
		Loaded.isTarget(x) -> boolean
		Loaded.Changed:Connect(function(items, by) end)   -- loads and clears

	Tabs: OnLoad(values, tab, items) runs on EVERY tab for each load (the
	open tab first). values holds Instances and raw values; items the same
	with targets kept whole (for Label / Origin). A tab that errors is
	reported under its owner; the others still run.

	A destroyed Instance drops out of the loaded list (Changed fires; when
	nothing is left the list is cleared).

	Going back (the path bar's back button):
		Loaded.back(by?) -> boolean    -- loads what was loaded before
		Loaded.canGoBack() -> boolean
		Loaded.previous()  -> the list Loaded.back would load, or nil
		Loaded.history()   -> earlier lists, newest last (copies)
		Loaded.clearHistory()
	Every load and clear remembers what it replaced (up to 50; the same
	list again isn't remembered twice). Lists whose Instances were all
	destroyed are skipped.

	Loading again (the path bar's reload button):
		Loaded.reload(by?) -> ok, problem?
	Loads the same list again: a value reached inside a script (its
	Access) is read again, so a changed upvalue or entry shows its new
	value; Instances and other values load as they are. A path that no
	longer resolves keeps its old value and the reason comes back as
	problem. Not remembered for back. Every tab is told, like any load.
]]

local T = ...
local signal = T.import("base/signal")
local Access = T.import("base/access")

local Loaded = {}
Loaded.Changed = signal.new() -- (items, by)

local TARGET = {} -- metatable marking targets
TARGET.__index = TARGET
TARGET.__tostring = function(self)
	return self.Label
end

local KINDS = { ["function"] = true, table = true, thread = true, connection = true, call = true, value = true }
local MAX_PASSES = 8 -- loads made while tabs are being told, run after (no endless loops)

local items: { any } = {}
local MAX_HISTORY = 50
local history: { { any } } = {} -- earlier lists, newest last
local destroyed = setmetatable({}, { __mode = "k" }) -- Instances seen destroyed
local watchers: { any } = {}
local loading = false
local queued: { any }? = nil

----------------------------------------------------------------------
-- Targets
----------------------------------------------------------------------

function Loaded.isTarget(x: any): boolean
	return type(x) == "table" and getmetatable(x) == TARGET
end

local function kindOf(value: any): string
	local kind = typeof(value)
	if kind == "function" or kind == "table" or kind == "thread" then
		return kind
	elseif kind == "RBXScriptConnection" then
		return "connection"
	end
	return "value"
end

local function nameOfFunction(fn: any): string
	local ok, name = pcall(debug.info, fn, "n")
	if ok and type(name) == "string" and name ~= "" then
		return name
	end
	return "(anonymous)"
end

local function defaultLabel(kind: string, value: any): string
	if kind == "function" then
		return "function " .. nameOfFunction(value)
	elseif kind == "table" then
		return "table"
	elseif kind == "thread" then
		return "thread"
	elseif kind == "connection" then
		return "connection"
	elseif kind == "call" then
		return "call"
	end
	local ok, text = pcall(tostring, value)
	return typeof(value) .. " " .. (if ok then text else "?")
end

function Loaded.target(value: any, opts: { [string]: any }?): any
	local o = opts or {}
	if Loaded.isTarget(value) then
		return value
	end
	assert(typeof(value) ~= "Instance", "an Instance is loaded as itself, not as a target")
	assert(value ~= nil, "a target needs a value")
	local kind = o.Kind or kindOf(value)
	assert(KINDS[kind], ("unknown target kind '%s'"):format(tostring(kind)))
	assert(o.Origin == nil or typeof(o.Origin) == "Instance", "a target's Origin must be an Instance")
	assert(o.Access == nil or Access.is(o.Access), "a target's Access comes from base/access")
	local label = if type(o.Label) == "string" and o.Label ~= "" then o.Label else defaultLabel(kind, value)
	return table.freeze(setmetatable({
		Kind = kind,
		Value = value,
		Label = label,
		Origin = o.Origin or (if o.Access then o.Access.Script else nil),
		Access = o.Access,
		Info = if type(o.Info) == "table" then table.freeze(table.clone(o.Info)) else nil,
	}, TARGET))
end

local function valueOf(item: any): any
	if Loaded.isTarget(item) then
		return item.Value
	end
	return item
end

----------------------------------------------------------------------
-- What is loaded
----------------------------------------------------------------------

function Loaded.get(): any
	return items[1]
end

function Loaded.list(): { any }
	return table.clone(items)
end

function Loaded.value(): any
	return if items[1] ~= nil then valueOf(items[1]) else nil
end

function Loaded.values(): { any }
	local out = table.create(#items)
	for index, item in items do
		out[index] = valueOf(item)
	end
	return out
end

local function unwatch()
	for _, connection in watchers do
		pcall(function()
			connection:Disconnect()
		end)
	end
	table.clear(watchers)
end

-- A destroyed Instance drops out (its target's Origin too: the target stays).
local function watch()
	unwatch()
	for _, item in items do
		if typeof(item) == "Instance" then
			pcall(function()
				table.insert(watchers, item.Destroying:Connect(function()
					destroyed[item] = true
					local index = table.find(items, item)
					if index then
						table.remove(items, index)
						task.defer(function()
							watch()
							Loaded.Changed:Fire(Loaded.list(), "tungsten")
						end)
					end
				end))
			end)
		end
	end
end

local function normalize(given: any): { any }
	local list
	if typeof(given) == "Instance" or Loaded.isTarget(given) then
		list = { given }
	elseif type(given) == "table" then
		list = given
	else
		error("Loaded.load takes an Instance, a target (Loaded.target) or a list of them", 3)
	end
	local out = {}
	for index, item in list do
		if typeof(item) == "Instance" or Loaded.isTarget(item) then
			if not table.find(out, item) then
				table.insert(out, item)
			end
		else
			error(("item %s is a %s: wrap values with Loaded.target"):format(tostring(index), typeof(item)), 3)
		end
	end
	return out
end

local function fault(tab, err)
	if (tab.Owner == nil or tab.Owner == "core") and T.Explorer and T.Explorer.report then
		-- Tungsten's own tabs: an error line from the explorer (it loaded)
		T.Explorer.report("error", ("OnLoad of tab '%s' failed: %s"):format(tab.Id, tostring(err)))
		return
	end
	local okR, Reporter = pcall(T.import, "console/reporter")
	if okR and Reporter.ownerFault then
		Reporter.ownerFault(tab.Owner or "core", ("OnLoad of tab '%s'"):format(tab.Id), err)
	end
end

-- Every tab, the open one first, then in side-bar order.
local function tabsToTell(): { any }
	local registry = T.Registry
	if not registry then
		return {}
	end
	local all = registry.allTabs() -- side-bar order (hidden tabs too)
	local open = T.Tabs and T.Tabs.Selected
	for index, tab in all do
		if tab.Id == open then
			table.remove(all, index)
			table.insert(all, 1, tab)
			break
		end
	end
	return all
end

-- Tells every tab; returns whether the open tab handled it.
local function tell(list: { any }): boolean
	local values = table.create(#list)
	for index, item in list do
		values[index] = valueOf(item)
	end
	local open = T.Tabs and T.Tabs.Selected
	local handled = false
	for _, tab in tabsToTell() do
		if type(tab.OnLoad) == "function" then
			local ok, result = pcall(tab.OnLoad, table.clone(values), tab, table.clone(list))
			if not ok then
				fault(tab, result)
			elseif tab.Id == open then
				handled = result ~= false
			end
		end
	end
	return handled
end

----------------------------------------------------------------------
-- History (back)
----------------------------------------------------------------------

local function sameList(a: { any }, b: { any }): boolean
	if #a ~= #b then
		return false
	end
	for index, item in a do
		if not rawequal(item, b[index]) then
			return false
		end
	end
	return true
end

-- Remembers the list being replaced.
local function remember(replacing: { any }, incoming: { any })
	if #replacing == 0 or sameList(replacing, incoming) then
		return
	end
	local last = history[#history]
	if last and sameList(last, replacing) then
		return
	end
	table.insert(history, table.clone(replacing))
	while #history > MAX_HISTORY do
		table.remove(history, 1)
	end
end

-- A remembered list without its destroyed Instances (nil when nothing is left).
local function alive(list: { any }): { any }?
	local out = {}
	for _, item in list do
		if not (typeof(item) == "Instance" and destroyed[item]) then
			table.insert(out, item)
		end
	end
	return if #out > 0 then out else nil
end

function Loaded.previous(): { any }?
	for index = #history, 1, -1 do
		local list = alive(history[index])
		if list and not sameList(list, items) then
			return list
		end
	end
	return nil
end

function Loaded.canGoBack(): boolean
	return Loaded.previous() ~= nil
end

function Loaded.history(): { { any } }
	local out = {}
	for index, list in history do
		out[index] = table.clone(list)
	end
	return out
end

function Loaded.clearHistory()
	table.clear(history)
	Loaded.Changed:Fire(Loaded.list(), "tungsten")
end

function Loaded.load(given: any, opts: { [string]: any }?): boolean
	local list = normalize(given)
	if #list == 0 then
		return false
	end
	local by = (opts and opts.By) or "you"
	-- going back or loading again: what is replaced isn't remembered
	local goingBack = opts ~= nil and (opts.Back == true or opts.Reload == true)
	if loading then
		-- A tab loaded something while being told: run it after.
		queued = { List = list, By = by }
		return false
	end
	loading = true
	local handled = false
	local ok, err = pcall(function()
		local passes = 0
		local nextList, nextBy = list, by
		while nextList and passes < MAX_PASSES do
			passes += 1
			if not (goingBack and passes == 1) then
				remember(items, nextList)
			end
			items = nextList
			watch()
			Loaded.Changed:Fire(Loaded.list(), nextBy)
			local result = tell(nextList)
			if passes == 1 then
				handled = result
			end
			local pending = queued
			queued = nil
			nextList, nextBy = if pending then pending.List else nil, if pending then pending.By else nil
		end
	end)
	loading = false
	queued = nil
	if not ok then
		T.Log.error("loaded", "load failed: " .. tostring(err))
	end
	return handled
end

function Loaded.clear(by: string?)
	if #items == 0 then
		return
	end
	remember(items, {})
	items = {}
	unwatch()
	Loaded.Changed:Fire({}, by or "you")
end

-- Loads the same list again, values inside scripts read again.
function Loaded.reload(by: string?): (boolean, string?)
	if #items == 0 then
		return false, "nothing is loaded"
	end
	local list, problem = {}, nil
	for _, item in items do
		if Loaded.isTarget(item) and item.Access then
			local ok, value = Access.resolve(item.Access)
			if ok and value ~= nil then
				if typeof(value) == "Instance" then
					table.insert(list, value)
				else
					table.insert(list, Loaded.target(value, { Access = item.Access, Label = item.Label, Origin = item.Origin, Info = item.Info }))
				end
			else
				problem = problem or (if ok then Access.code(item.Access) .. " is nil now" else tostring(value))
				table.insert(list, item)
			end
		elseif not (typeof(item) == "Instance" and destroyed[item]) then
			table.insert(list, item)
		end
	end
	if #list == 0 then
		return false, "what was loaded is gone"
	end
	Loaded.load(list, { By = by or "you", Reload = true })
	return true, problem
end

-- Loads what was loaded before; false when there is nothing to go back to.
function Loaded.back(by: string?): boolean
	for index = #history, 1, -1 do
		local list = alive(history[index])
		table.remove(history, index)
		if list and not sameList(list, items) then
			Loaded.load(list, { By = by or "you", Back = true })
			return true
		end
	end
	return false
end

T.Bin:Add(function()
	unwatch()
	items = {}
	table.clear(history)
	queued = nil
	loading = false
	Loaded.Changed:DisconnectAll()
end)

return Loaded
