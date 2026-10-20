--[[
	Tungsten · base/explorer/insert
	Making new objects: the explorer's Object › Insert submenu and /insert.

		Insert.classes()                 -> every class Instance.new can make
		                                    (bundled class data + Classes.add)
		Insert.groups()                  -> { { Id, Title, Icon, Color, Classes } } in menu order
		Insert.into("Part", { parentA, parentB }) -> created, failures
		Insert.Inserted:Connect(function(created, className, parents) end)

	The menu shows Common first, then a submenu per group (Parts, Scripts,
	GUI, …). Long groups split into letter ranges, and "Search all
	classes…" opens a searchable list of every class.

	Plugins can shape the menu:
		Insert.addGroup({ Id = "vehicles", Title = "Vehicles", Icon = "class_part",
			Classes = { "VehicleSeat", "Seat" },       -- or Test = function(className) -> bool
			Order = 25 }, "myplugin")
		Insert.setCommon({ "Part", "Model", ... })     -- the Common list
		Insert.removeOwner("myplugin")
	A class only shows when it can be made (Classes.add(name, category,
	{ Creatable = true }) teaches Tungsten a new one).
]]

local T = ...
local signal = T.import("base/signal")
local Api = T.import("base/explorer/api")
local Classes = T.import("base/data/classes")

local Insert = {}
Insert.Inserted = signal.new() -- (created, className, parents)
Insert.SplitAt = 40 -- groups longer than this split into letter ranges

local COMMON = {
	"Part", "MeshPart", "Model", "Folder", "Script", "LocalScript", "ModuleScript", "RemoteEvent",
	"RemoteFunction", "BindableEvent", "ScreenGui", "Frame", "TextLabel", "TextButton", "ImageLabel",
	"Attachment", "WeldConstraint", "Sound", "ParticleEmitter", "PointLight", "Highlight", "Tool",
	"ProximityPrompt", "ClickDetector", "StringValue", "NumberValue", "BoolValue", "ObjectValue",
}
local common = table.clone(COMMON)

-- Built-in groups: display categories (base/data/classes) they cover.
local BUILTIN = {
	{ Id = "parts", Title = "Parts", Icon = "class_part", Categories = { "part" }, Order = 10 },
	{ Id = "models", Title = "Models & Folders", Icon = "class_model", Categories = { "model", "folder" }, Order = 20 },
	{ Id = "scripts", Title = "Scripts", Icon = "class_script", Categories = { "script", "localscript", "modulescript" }, Order = 30 },
	{ Id = "remotes", Title = "Remotes & Bindables", Icon = "class_remote", Categories = { "remote", "bindable" }, Order = 40 },
	{ Id = "values", Title = "Values", Icon = "class_value", Categories = { "value" }, Order = 50 },
	{ Id = "gui", Title = "GUI", Icon = "class_gui", Categories = { "gui", "frame", "text", "button", "image" }, Order = 60 },
	{ Id = "layout", Title = "UI Layout & Style", Icon = "class_layout", Categories = { "layout" }, Order = 70 },
	{ Id = "lights", Title = "Lights", Icon = "class_light", Categories = { "light" }, Order = 80 },
	{ Id = "sounds", Title = "Sounds", Icon = "class_sound", Categories = { "sound" }, Order = 90 },
	{ Id = "effects", Title = "Effects", Icon = "class_effect", Categories = { "effect" }, Order = 100 },
	{ Id = "constraints", Title = "Constraints & Physics", Icon = "class_constraint", Categories = { "constraint", "attachment" }, Order = 110 },
	{ Id = "characters", Title = "Characters", Icon = "class_humanoid", Categories = { "humanoid", "player" }, Order = 120 },
	{ Id = "animation", Title = "Animation", Icon = "class_animation", Categories = { "animation" }, Order = 130 },
	{ Id = "meshes", Title = "Meshes", Icon = "class_mesh", Categories = { "mesh" }, Order = 140 },
	{ Id = "tools", Title = "Tools & Interaction", Icon = "class_tool", Categories = { "tool", "camera" }, Order = 150 },
}
local custom: { any } = {} -- groups plugins added

-- Classes nothing else claims go to "Other"; deprecated ones to their own group.
local cachedClasses: { string }? = nil
local cachedVersion = -1

local function creatableByData(name: string): boolean
	local info = Api.class(name)
	return info ~= nil and not info.NotCreatable and not info.Service and not info.NotBrowsable
end

function Insert.classes(): { string }
	local Categories = T.import("base/data/categories")
	if cachedClasses and cachedVersion == Categories.Version then
		return table.clone(cachedClasses)
	end
	local seen, list = {}, {}
	for _, name in Api.classNames() do
		if creatableByData(name) then
			seen[name] = true
			table.insert(list, name)
		end
	end
	for _, name in Classes.creatable() do
		if not seen[name] and (not Api.isKnown(name) or creatableByData(name)) then
			seen[name] = true
			table.insert(list, name)
		end
	end
	table.sort(list)
	cachedClasses, cachedVersion = list, Categories.Version
	return table.clone(list)
end

function Insert.isDeprecated(name: string): boolean
	local info = Api.class(name)
	return info ~= nil and info.Deprecated == true
end

function Insert.canCreate(name: string): boolean
	return table.find(Insert.classes(), name) ~= nil
end

function Insert.common(): { string }
	local list = {}
	for _, name in common do
		if Insert.canCreate(name) then
			table.insert(list, name)
		end
	end
	return list
end

function Insert.setCommon(list: { string })
	assert(type(list) == "table", "setCommon takes a list of class names")
	common = table.clone(list)
end

function Insert.resetCommon()
	common = table.clone(COMMON)
end

function Insert.addGroup(group: { [string]: any }, owner: string?)
	assert(type(group) == "table" and type(group.Id) == "string", "a group needs an Id")
	assert(type(group.Classes) == "table" or type(group.Test) == "function", "a group needs Classes or Test")
	Insert.removeGroup(group.Id)
	local stored = table.clone(group)
	stored.Owner = owner or group.Owner or "core"
	stored.Title = stored.Title or stored.Id
	stored.Order = stored.Order or 1000
	table.insert(custom, stored)
	return stored.Id
end

function Insert.removeGroup(id: string): boolean
	for index, group in custom do
		if group.Id == id then
			table.remove(custom, index)
			return true
		end
	end
	return false
end

function Insert.removeOwner(owner: string): number
	local count = 0
	for index = #custom, 1, -1 do
		if custom[index].Owner == owner then
			table.remove(custom, index)
			count += 1
		end
	end
	return count
end

-- { { Id, Title, Icon, Classes } } in menu order (empty groups left out).
function Insert.groups(): { any }
	local all = Insert.classes()
	local groups = {}
	local function addGroup(def, classes)
		if #classes > 0 then
			table.sort(classes)
			local style = Classes.style(classes[1])
			table.insert(groups, {
				Id = def.Id,
				Title = def.Title,
				Icon = def.Icon or style.Icon,
				Color = def.Color or style.Color,
				Classes = classes,
				Order = def.Order or 1000,
				Owner = def.Owner,
			})
		end
	end
	-- Plugin groups take their classes first (a class may also stay in its
	-- built-in group).
	for _, def in custom do
		local list = {}
		if def.Classes then
			for _, name in def.Classes do
				if table.find(all, name) then
					table.insert(list, name)
				end
			end
		else
			for _, name in all do
				local ok, yes = pcall(def.Test, name)
				if ok and yes then
					table.insert(list, name)
				end
			end
		end
		addGroup(def, list)
	end
	local byCategory = {}
	for _, def in BUILTIN do
		for _, category in def.Categories do
			byCategory[category] = def
		end
	end
	local lists = {}
	local deprecated, other = {}, {}
	for _, name in all do
		if Insert.isDeprecated(name) then
			table.insert(deprecated, name)
		else
			local def = byCategory[Classes.category(name)]
			if def then
				lists[def.Id] = lists[def.Id] or {}
				table.insert(lists[def.Id], name)
			else
				table.insert(other, name)
			end
		end
	end
	for _, def in BUILTIN do
		addGroup(def, lists[def.Id] or {})
	end
	addGroup({ Id = "other", Title = "Other", Icon = "class_unknown", Order = 900 }, other)
	addGroup({ Id = "deprecated", Title = "Deprecated", Icon = "class_unknown", Order = 950 }, deprecated)
	table.sort(groups, function(a, b)
		if a.Order ~= b.Order then
			return a.Order < b.Order
		end
		return a.Title < b.Title
	end)
	return groups
end

-- Splits a long sorted list into letter ranges: { { Title = "A–C", Classes } }.
function Insert.split(classes: { string }, size: number?): { any }
	size = size or Insert.SplitAt
	if #classes <= (size :: number) then
		return { { Title = nil, Classes = classes } }
	end
	local chunks = {}
	local current = {}
	local index = 1
	while index <= #classes do
		-- Never split one first letter across two ranges.
		local letter = classes[index]:sub(1, 1):upper()
		local block = {}
		while index <= #classes and classes[index]:sub(1, 1):upper() == letter do
			table.insert(block, classes[index])
			index += 1
		end
		if #current > 0 and #current + #block > (size :: number) then
			table.insert(chunks, current)
			current = {}
		end
		for _, name in block do
			table.insert(current, name)
		end
	end
	if #current > 0 then
		table.insert(chunks, current)
	end
	local out = {}
	for _, chunk in chunks do
		local first = chunk[1]:sub(1, 1):upper()
		local last = chunk[#chunk]:sub(1, 1):upper()
		table.insert(out, { Title = if first == last then first else first .. "–" .. last, Classes = chunk })
	end
	return out
end

-- Makes one `className` inside each parent. Returns the new objects and
-- { { Parent, Error } } for the ones that failed.
function Insert.into(className: string, parents: { Instance }): ({ Instance }, { any })
	local created, failures = {}, {}
	for _, parent in parents do
		local ok, result = pcall(function()
			local object = Instance.new(className)
			object.Parent = parent
			return object
		end)
		if ok then
			table.insert(created, result)
		else
			table.insert(failures, { Parent = parent, Error = tostring(result):gsub("^.-:%d+: ", "") })
		end
	end
	if #created > 0 then
		Insert.Inserted:Fire(created, className, parents)
	end
	return created, failures
end

T.Bin:Add(function()
	table.clear(custom)
	Insert.Inserted:DisconnectAll()
end)

return Insert
