--[[
	Tungsten · base/variables
	Session-only variables: any value, Instances included. Nothing here is
	saved; a new session (or a re-run) starts empty.

		Variables.set("a", 5)                        -- source "console"
		Variables.set("hit", part, { Source = "myplugin" })
		Variables.get("a")         -> 5, true
		Variables.unset("a")
		Variables.list()           -> { { Name, Value, Source, Reserved }, ... } sorted
		Variables.Changed:Connect(function(name, value, oldValue, removed) end)

	Referring to variables by name (console code: var("name"); plugins:
	Variables.ref):
		Variables.ref("door")      -> the value ($door), an error if there is none
		Variables.ref("list1")     -> a list of Instances comes back as a group:
		    group:Destroy()            calls Destroy on every object (results in a table)
		    group.Transparency = 1     sets it on every object
		    group.Name                 -> { each object's Name }
		    group[2], #group, for _, obj in group do … end
		Variables.group(list)      -> the same group for any list of Instances
		Variables.watch("door", function(value, old, removed) end) -> connection

	Reserved names
		last  the latest console result (set by the console)
		sel   the explorer selection: the Instance, or a table of them when
		      several are selected (set by the explorer)
		err   the newest console error record (see console/errors)
	Reserved names can't be set or unset by commands, code or plugins;
	their owners use Variables.setReserved.

	Owners
		Every variable has an owner: you (Source "console", "explorer" or
		"tungsten") or the plugin that made it (Source = its id).
		- You may change or unset any variable; a plugin's stays the
		  plugin's (its owner is told, with by = "console" / "explorer").
		- A plugin may change or unset only its own. A name someone else
		  has is refused (false, "$hits belongs to …"), never overwritten.
		- Every plugin can read every variable.
		Variables.set(name, value, { Source = writer }) ; Variables.unset(name, { Source = writer })
		Variables.owner(name) -> "you" | plugin id | nil ; Variables.canWrite(name, writer)
		Changed / watch get a 5th argument: who made the change (by).
]]

local T = ...
local signal = T.import("base/signal")
local Undo = T.import("base/undo")

local Variables = {}
Variables.Changed = signal.new() -- (name, value, oldValue, removed: boolean, by: string)
Variables.Reserved = { last = true, sel = true, err = true }
Variables.MaxNameLength = 48

local store: { [string]: { Value: any, Source: string } } = {}

-- Sources that are you (not a plugin).
local USER = { console = true, explorer = true, tungsten = true, core = true }
Variables.UserSources = USER

function Variables.isUser(source: string?): boolean
	return source == nil or USER[source] == true
end

-- "you" for your variables, the plugin's id for a plugin's, nil if none.
function Variables.owner(name: string): string?
	local entry = store[name]
	if not entry then
		return nil
	end
	return if USER[entry.Source] then "you" else entry.Source
end

-- May `writer` change or unset this variable? (true, or false + why)
function Variables.canWrite(name: string, writer: string?): (boolean, string?)
	local entry = store[name]
	if not entry or Variables.isUser(writer) or entry.Source == writer then
		return true, nil
	end
	local owner = if USER[entry.Source] then "you" else entry.Source
	return false, ("$%s belongs to %s"):format(name, owner)
end

local function checkName(name: any): (boolean, string?)
	if type(name) ~= "string" then
		return false, "a variable name must be text"
	end
	if not name:match("^[%a_][%w_]*$") then
		return false, ("'%s' is not a valid name · use letters, digits and _, not starting with a digit"):format(name)
	end
	if #name > Variables.MaxNameLength then
		return false, ("names are limited to %d characters"):format(Variables.MaxNameLength)
	end
	return true, nil
end

function Variables.validName(name: any): (boolean, string?)
	return checkName(name)
end

function Variables.isReserved(name: string): boolean
	return Variables.Reserved[name] == true
end

local function write(name: string, value: any, source: string, by: string?)
	local entry = store[name]
	local old = if entry then entry.Value else nil
	store[name] = { Value = value, Source = source }
	Variables.Changed:Fire(name, value, old, false, by or source)
end

-- Returns true, or false and a reason.
function Variables.set(name: string, value: any, opts: { [string]: any }?): (boolean, string?)
	local ok, reason = checkName(name)
	if not ok then
		return false, reason
	end
	if Variables.Reserved[name] then
		return false, ("$%s is reserved"):format(name)
	end
	if value == nil then
		return false, "the value is nil · use unset to remove a variable"
	end
	local writer = (opts and opts.Source) or "console"
	local allowed, why = Variables.canWrite(name, writer)
	if not allowed then
		return false, why
	end
	-- You changing a plugin's variable leaves it the plugin's.
	local entry = store[name]
	local owner = if entry and not USER[entry.Source] and USER[writer] then entry.Source else writer
	if USER[writer] and opts and type(opts.Owner) == "string" then
		owner = opts.Owner -- /undo puts back who had it
	end
	-- Recorded for /undo (opts.Undo = false: not recorded). A plugin's own
	-- steps belong to it and go when it does.
	local restore = if not (opts and opts.Undo == false) and Undo.isRecording() then Undo.rememberVariables({ name }) else nil
	write(name, value, owner, writer)
	if restore then
		Undo.record({ Text = "set $" .. name, Undo = restore, Owner = if USER[writer] then nil else writer })
	end
	return true, nil
end

-- Owners of reserved names (console: last, explorer: sel). nil clears.
function Variables.setReserved(name: string, value: any, source: string?)
	assert(Variables.Reserved[name], "not a reserved variable: " .. tostring(name))
	if value == nil then
		local entry = store[name]
		if entry then
			store[name] = nil
			Variables.Changed:Fire(name, nil, entry.Value, true, source or "tungsten")
		end
		return
	end
	write(name, value, source or "tungsten")
end

function Variables.unset(name: string, opts: { [string]: any }?): (boolean, string?)
	if Variables.Reserved[name] then
		return false, ("$%s is reserved"):format(tostring(name))
	end
	local entry = store[name]
	if not entry then
		return false, ("no variable $%s"):format(tostring(name))
	end
	local writer = (opts and opts.Source) or "console"
	local allowed, why = Variables.canWrite(name, writer)
	if not allowed then
		return false, why
	end
	local restore = if Undo.isRecording() then Undo.rememberVariables({ name }) else nil
	store[name] = nil
	Variables.Changed:Fire(name, nil, entry.Value, true, writer)
	if restore then
		Undo.record({ Text = "unset $" .. name, Undo = restore, Owner = if USER[writer] then nil else writer })
	end
	return true, nil
end

function Variables.get(name: string): (any, boolean)
	local entry = store[name]
	if entry then
		return entry.Value, true
	end
	return nil, false
end

function Variables.has(name: string): boolean
	return store[name] ~= nil
end

function Variables.source(name: string): string?
	local entry = store[name]
	return if entry then entry.Source else nil
end

-- Sorted: reserved names first, then alphabetical.
function Variables.list(): { any }
	local list = {}
	for name, entry in store do
		table.insert(list, {
			Name = name,
			Value = entry.Value,
			Source = entry.Source,
			Reserved = Variables.Reserved[name] == true,
		})
	end
	table.sort(list, function(a, b)
		if a.Reserved ~= b.Reserved then
			return a.Reserved
		end
		return a.Name:lower() < b.Name:lower()
	end)
	return list
end

function Variables.names(): { string }
	local names = {}
	for _, entry in Variables.list() do
		table.insert(names, entry.Name)
	end
	return names
end

function Variables.count(): number
	local count = 0
	for _ in store do
		count += 1
	end
	return count
end

-- Removes every non-reserved variable (or only one source's).
function Variables.clear(source: string?): number
	local removed = 0
	local names = {}
	for name, entry in store do
		if not Variables.Reserved[name] and (source == nil or entry.Source == source) then
			table.insert(names, name)
		end
	end
	local restore = if #names > 0 and Undo.isRecording() then Undo.rememberVariables(names) else nil
	for name, entry in table.clone(store) do
		if not Variables.Reserved[name] and (source == nil or entry.Source == source) then
			store[name] = nil
			removed += 1
			Variables.Changed:Fire(name, nil, entry.Value, true, source or "console")
		end
	end
	if restore and removed > 0 then
		Undo.record({ Text = ("clear %d variable%s"):format(removed, if removed == 1 then "" else "s"), Undo = restore })
	end
	return removed
end

----------------------------------------------------------------------
-- By name (var("name") in console code, and plugins)
----------------------------------------------------------------------

local GroupMeta = {}

-- A list of Instances that answers like one object: method calls and
-- property writes go to every object, property reads give a table.
function Variables.group(list: { Instance })
	local items = {}
	for _, item in list do
		table.insert(items, item)
	end
	return setmetatable({ [GroupMeta] = items }, GroupMeta)
end

function Variables.isGroup(value: any): boolean
	return type(value) == "table" and getmetatable(value) == GroupMeta
end

-- The list inside a group.
function Variables.items(group): { Instance }
	return table.clone(rawget(group, GroupMeta) or {})
end

GroupMeta.__index = function(group, key)
	local items = rawget(group, GroupMeta)
	if type(key) == "number" then
		return items[key]
	end
	if #items == 0 then
		return nil
	end
	local ok, member = pcall(function()
		return (items[1] :: any)[key]
	end)
	if ok and type(member) == "function" then
		-- group:Method(...) runs it on every object
		return function(self, ...)
			local results = {}
			for index, item in items do
				results[index] = (item :: any)[key](item, ...)
			end
			return results
		end
	end
	local values = {}
	for index, item in items do
		values[index] = (item :: any)[key]
	end
	return values
end
GroupMeta.__newindex = function(group, key, value)
	for _, item in rawget(group, GroupMeta) do
		(item :: any)[key] = value
	end
end
GroupMeta.__len = function(group)
	return #rawget(group, GroupMeta)
end
GroupMeta.__iter = function(group)
	return next, table.clone(rawget(group, GroupMeta))
end
GroupMeta.__tostring = function(group)
	return ("group of %d objects"):format(#rawget(group, GroupMeta))
end

local function instanceList(value: any): boolean
	if type(value) ~= "table" or getmetatable(value) ~= nil or #value == 0 then
		return false
	end
	for key, item in value do
		if type(key) ~= "number" or typeof(item) ~= "Instance" then
			return false
		end
	end
	return true
end

-- A variable by name ($ optional). Lists of Instances come back as a
-- group (see the top of this file); anything else as it is.
function Variables.ref(name: string): any
	name = tostring(name):gsub("^%$", "")
	local value, exists = Variables.get(name)
	if not exists then
		if name == "sel" then
			error("$sel is empty · select something in the explorer first", 2)
		end
		error(("unknown variable $%s"):format(name), 2)
	end
	if instanceList(value) then
		return Variables.group(value)
	end
	return value
end

-- Calls fn(value, oldValue, removed, by) whenever the variable changes
-- (by: who changed it, see Owners at the top).
function Variables.watch(name: string, fn: (any, any, boolean, string?) -> ())
	name = tostring(name):gsub("^%$", "")
	return Variables.Changed:Connect(function(changed, value, old, removed, by)
		if changed == name then
			fn(value, old, removed, by)
		end
	end)
end

-- Removes a plugin's variables (when it is turned off; not an undo step).
function Variables.removeOwner(owner: string): number
	if owner == "core" or owner == "console" then
		return 0
	end
	return Undo.quiet(function()
		return Variables.clear(owner)
	end)
end

-- What a plugin may want to show about a variable.
-- While the explorer is frozen: what happened to the objects a value
-- holds (Explorer.frozenState). One object -> its state ("deleted",
-- "inside_deleted", "moved", "inside_moved") or nil; a list or group ->
-- { [state] = count } or nil when nothing happened to any of them.
function Variables.frozenState(value: any): any
	local Explorer = T.Explorer
	if not Explorer or not Explorer.frozenState or not Explorer.isFrozen() then
		return nil
	end
	if typeof(value) == "Instance" then
		return Explorer.frozenState(value)
	end
	if type(value) ~= "table" then
		return nil
	end
	local counts, any = {}, false
	for _, item in (if Variables.isGroup(value) then Variables.items(value) else value) do
		if typeof(item) == "Instance" then
			local state = Explorer.frozenState(item)
			if state then
				counts[state] = (counts[state] or 0) + 1
				any = true
			end
		end
	end
	return if any then counts else nil
end

function Variables.info(name: string)
	local entry = store[name]
	if not entry then
		return nil
	end
	return {
		Name = name,
		Value = entry.Value,
		Source = entry.Source,
		Owner = if USER[entry.Source] then "you" else entry.Source,
		Reserved = Variables.Reserved[name] == true,
		Frozen = Variables.frozenState(entry.Value), -- see Variables.frozenState
	}
end

T.Bin:Add(function()
	table.clear(store)
	Variables.Changed:DisconnectAll()
end)

return Variables
