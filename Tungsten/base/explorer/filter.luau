--[[
	Tungsten · base/explorer/filter
	The explorer's filter: which objects the tree shows, kept while you
	browse and search (the search words narrow it further).

		Filter.set({
			Only = { "parts", "scripts" },   -- groups to show (none: everything)
			Classes = { "Tool" },            -- more classes to show (and subclasses)
			Hide = { "Camera" },             -- classes never shown, with what is inside
		})
		Filter.get() -> { Only, Classes, Hide } (copies)
		Filter.active() / Filter.showsOnly() / Filter.hides()
		Filter.onlyTest() -> function(instance) -> boolean, or nil
		Filter.hidden(instance) -> true when it (or a parent) is a hidden class
		Filter.clear()
		Filter.Changed:Connect(function(state) end)

	Groups (plugins add their own):
		Filter.addGroup("vehicles", { Text = "Vehicles", Classes = { "VehicleSeat" }, Owner = "myplugin" })
		Filter.addGroup("doors", { Text = "Doors", Test = function(obj) return obj.Name:find("Door") ~= nil end })
	The filter is saved with the settings (ExplorerFilter).
]]

local T = ...
local signal = T.import("base/signal")
local Settings = T.import("base/settings")
local Api = T.import("base/explorer/api")

local Filter = {}
Filter.Changed = signal.new() -- (state)

local BUILTIN = {
	{ Id = "parts", Text = "Parts", Classes = { "BasePart" } },
	{ Id = "models", Text = "Models", Classes = { "Model" } },
	{ Id = "folders", Text = "Folders", Classes = { "Folder", "Configuration" } },
	{ Id = "scripts", Text = "Scripts", Classes = { "LuaSourceContainer" } },
	{ Id = "remotes", Text = "Remotes", Classes = { "BaseRemoteEvent", "RemoteFunction" } },
	{ Id = "bindables", Text = "Bindables", Classes = { "BindableEvent", "BindableFunction" } },
	{ Id = "gui", Text = "GUI", Classes = { "GuiBase" } },
	{ Id = "values", Text = "Values", Classes = { "ValueBase" } },
	{ Id = "lights", Text = "Lights", Classes = { "Light" } },
	{ Id = "sounds", Text = "Sounds", Classes = { "Sound", "SoundGroup", "SoundEffect" } },
	{ Id = "effects", Text = "Effects", Classes = { "ParticleEmitter", "Trail", "Beam", "Fire", "Smoke", "Sparkles", "PostEffect" } },
	{ Id = "constraints", Text = "Constraints", Classes = { "Constraint", "JointInstance", "WeldConstraint", "NoCollisionConstraint", "Attachment" } },
	{ Id = "humanoids", Text = "Humanoids", Classes = { "Humanoid" } },
	{ Id = "animation", Text = "Animation", Classes = { "Animation", "AnimationController", "Animator", "KeyframeSequence" } },
}

local groups: { any } = {}
for index, group in BUILTIN do
	group.Owner = "core"
	group.Order = index * 10
	table.insert(groups, group)
end

local state = { Only = {}, Classes = {}, Hide = {} }
local onlyCache: { [string]: boolean } = {} -- ClassName -> shown (class-only groups)
local hideCache: { [string]: boolean } = {} -- ClassName -> hidden

local function stringList(value): { string }
	local list = {}
	if type(value) == "table" then
		for _, item in value do
			if type(item) == "string" and item ~= "" and not table.find(list, item) then
				table.insert(list, item)
			end
		end
	end
	return list
end

function Filter.groups(): { any }
	local list = table.clone(groups)
	table.sort(list, function(a, b)
		if a.Order ~= b.Order then
			return a.Order < b.Order
		end
		return a.Id < b.Id
	end)
	return list
end

function Filter.group(id: string)
	for _, group in groups do
		if group.Id == id then
			return group
		end
	end
	return nil
end

-- A group by id or text, any case ("Parts", "parts").
function Filter.findGroup(word: string)
	local lower = tostring(word):lower()
	for _, group in groups do
		if group.Id:lower() == lower or group.Text:lower() == lower then
			return group
		end
	end
	return nil
end

local function invalidate()
	table.clear(onlyCache)
	table.clear(hideCache)
end

local function announce(save: boolean?)
	invalidate()
	if save ~= false then
		Settings.set("ExplorerFilter", { Only = table.clone(state.Only), Classes = table.clone(state.Classes), Hide = table.clone(state.Hide) })
	end
	Filter.Changed:Fire(Filter.get())
end

function Filter.addGroup(id: string, definition: { [string]: any })
	assert(type(id) == "string" and id:match("^[%w_%-]+$"), "a filter group needs a plain id")
	assert(type(definition) == "table", "a filter group needs a definition")
	assert(type(definition.Classes) == "table" or type(definition.Test) == "function", "a filter group needs Classes or Test")
	Filter.removeGroup(id)
	table.insert(groups, {
		Id = id,
		Text = tostring(definition.Text or id),
		Classes = definition.Classes,
		Test = definition.Test,
		Owner = definition.Owner or "core",
		Order = tonumber(definition.Order) or 1000,
	})
	announce(false)
end

function Filter.removeGroup(id: string): boolean
	for index, group in groups do
		if group.Id == id then
			table.remove(groups, index)
			local at = table.find(state.Only, id)
			if at then
				table.remove(state.Only, at)
			end
			announce(at ~= nil)
			return true
		end
	end
	return false
end

function Filter.removeOwner(owner: string): number
	local count = 0
	for _, group in table.clone(groups) do
		if group.Owner == owner then
			Filter.removeGroup(group.Id)
			count += 1
		end
	end
	return count
end

function Filter.get()
	return { Only = table.clone(state.Only), Classes = table.clone(state.Classes), Hide = table.clone(state.Hide) }
end

-- Replaces the filter (missing fields keep their value).
function Filter.set(new: { [string]: any }, save: boolean?)
	new = new or {}
	if new.Only ~= nil then
		state.Only = {}
		for _, id in stringList(new.Only) do
			if Filter.group(id) or Filter.findGroup(id) then
				table.insert(state.Only, (Filter.group(id) or Filter.findGroup(id)).Id)
			end
		end
	end
	if new.Classes ~= nil then
		state.Classes = stringList(new.Classes)
	end
	if new.Hide ~= nil then
		state.Hide = stringList(new.Hide)
	end
	announce(save)
end

function Filter.clear()
	Filter.set({ Only = {}, Classes = {}, Hide = {} })
end

-- Turns a group on or off.
function Filter.toggleGroup(id: string, on: boolean?)
	local at = table.find(state.Only, id)
	if on == nil then
		on = at == nil
	end
	if on and not at then
		table.insert(state.Only, id)
	elseif not on and at then
		table.remove(state.Only, at)
	else
		return
	end
	announce()
end

local function editList(list: { string }, className: string, add: boolean)
	local at = table.find(list, className)
	if add and not at then
		table.insert(list, className)
	elseif not add and at then
		table.remove(list, at)
	else
		return
	end
	announce()
end

function Filter.showClass(className: string, add: boolean?)
	editList(state.Classes, className, add ~= false)
end

function Filter.hideClass(className: string, add: boolean?)
	editList(state.Hide, className, add ~= false)
end

function Filter.showsOnly(): boolean
	return #state.Only > 0 or #state.Classes > 0
end

function Filter.hides(): boolean
	return #state.Hide > 0
end

function Filter.active(): boolean
	return Filter.showsOnly() or Filter.hides()
end

-- Whether a class is (or inherits from) another: the bundled data first,
-- the object itself for classes the data doesn't know.
local function classIs(obj: Instance, className: string, base: string): boolean
	if className == base then
		return true
	end
	if Api.isKnown(className) then
		return Api.isA(className, base)
	end
	local ok, is = pcall(function()
		return obj:IsA(base)
	end)
	return ok and is == true
end

local function classOf(obj: Instance): string?
	local ok, className = pcall(function()
		return obj.ClassName
	end)
	return if ok then className else nil
end

-- The "show only" test, or nil when it shows everything.
function Filter.onlyTest(): ((Instance) -> boolean)?
	if not Filter.showsOnly() then
		return nil
	end
	local classes = table.clone(state.Classes)
	local tests = {}
	for _, id in state.Only do
		local group = Filter.group(id)
		if group then
			for _, className in group.Classes or {} do
				table.insert(classes, className)
			end
			if group.Test then
				table.insert(tests, group.Test)
			end
		end
	end
	return function(obj: Instance): boolean
		local className = classOf(obj)
		if not className then
			return false
		end
		local cached = onlyCache[className]
		if cached == nil then
			cached = false
			for _, base in classes do
				if classIs(obj, className, base) then
					cached = true
					break
				end
			end
			onlyCache[className] = cached
		end
		if cached then
			return true
		end
		for _, test in tests do
			local ok, result = pcall(test, obj)
			if ok and result then
				return true
			end
		end
		return false
	end
end

-- Whether the object's own class is hidden.
function Filter.hiddenClass(obj: Instance, className: string?): boolean
	if #state.Hide == 0 then
		return false
	end
	className = className or classOf(obj)
	if not className then
		return false
	end
	local cached = hideCache[className]
	if cached == nil then
		cached = false
		for _, base in state.Hide do
			if classIs(obj, className, base) then
				cached = true
				break
			end
		end
		hideCache[className] = cached
	end
	return cached
end

-- Whether the object or one of its parents is a hidden class.
function Filter.hidden(obj: Instance): boolean
	if #state.Hide == 0 then
		return false
	end
	local current: Instance? = obj
	local guard = 0
	while current and current ~= game and guard < 200 do
		guard += 1
		if Filter.hiddenClass(current) then
			return true
		end
		local ok, parent = pcall(function()
			return (current :: Instance).Parent
		end)
		if not ok then
			return false
		end
		current = parent
	end
	return false
end

-- A short description for the footer and /filter.
function Filter.describe(): string
	local parts = {}
	local shown = {}
	for _, id in state.Only do
		local group = Filter.group(id)
		table.insert(shown, if group then group.Text else id)
	end
	for _, className in state.Classes do
		table.insert(shown, className)
	end
	if #shown > 0 then
		table.insert(parts, "only " .. table.concat(shown, ", "))
	end
	if #state.Hide > 0 then
		table.insert(parts, "hiding " .. table.concat(state.Hide, ", "))
	end
	return table.concat(parts, " · ")
end

-- Loads the saved filter.
function Filter.load()
	local saved = Settings.get("ExplorerFilter")
	if type(saved) == "table" then
		Filter.set(saved, false)
	end
end

T.Bin:Add(function()
	Filter.Changed:DisconnectAll()
end)

return Filter
