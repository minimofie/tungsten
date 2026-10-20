--[[
	Tungsten · base/explorer/api
	What Tungsten knows about classes and their properties, from the
	bundled data in base/data/api (no downloads).

		Api.Version                      -> client version of the data
		Api.class("Part")                -> { Name, Superclass, NotCreatable, Service, Deprecated, NotBrowsable }
		Api.superclasses("Part")         -> { "FormFactorPart", "BasePart", "PVInstance", "Instance" }
		Api.properties("Part")           -> every property, inherited ones too, by name
		Api.property("Part", "Anchored") -> one property
		Api.knownClass(instance)         -> the instance's class, or the nearest known
		                                    class it IsA (for classes newer than the data)
		Api.propertiesOf(instance)       -> properties for an instance
		Api.read(instance, "Anchored")   -> true, value | false, reason
		Api.write(instance, "Anchored", true) -> true | false, reason

	A property:
		Name, Class (where it is declared), Category ("Appearance", ...),
		Type     the Luau type of its value: "boolean", "number", "string",
		         "Vector3", "CFrame", "EnumItem", "Instance", ...
		DataType the type as the engine names it ("float", "int", "ContentId",
		         "Material" for enums, "BasePart" for references)
		Enum     the enum's name (EnumItem properties)
		ClassRef the class a reference property accepts (Instance properties)
		Integer  int / int64 numbers
		ReadOnly, Deprecated, Hidden, NotScriptable, WriteOnly
		Security "None", "PluginSecurity", "LocalUserSecurity", "RobloxScriptSecurity"
		Editable whether Tungsten has an editor for the type (and it isn't read only)

	Properties scripts can't see (NotScriptable) are read and written with
	Volt's gethiddenproperty / sethiddenproperty.
]]

local T = ...
local Data = T.import("base/data/api")

local Api = {}
Api.Version = Data.Version

-- Engine value types -> the type a Luau value of it has.
local PRIMITIVES = {
	b = { Type = "boolean", DataType = "bool" },
	f = { Type = "number", DataType = "float" },
	d = { Type = "number", DataType = "double" },
	i = { Type = "number", DataType = "int", Integer = true },
	l = { Type = "number", DataType = "int64", Integer = true },
	s = { Type = "string", DataType = "string" },
}

-- DataTypes whose Luau values have another typeof() name.
local DATATYPE_ALIASES = {
	ContentId = "string",
	BinaryString = "string",
	SharedString = "string",
	ProtectedString = "string",
	Color3uint8 = "Color3",
	OptionalCoordinateFrame = "CFrame",
	int = "number",
}

-- Value types with an editor (other types are shown, never edited).
Api.EditableTypes = {
	boolean = true, number = true, string = true, EnumItem = true, Instance = true,
	Vector2 = true, Vector3 = true, Vector2int16 = true, Vector3int16 = true,
	CFrame = true, Color3 = true, BrickColor = true, UDim = true, UDim2 = true,
	Rect = true, NumberRange = true, NumberSequence = true, ColorSequence = true,
	Faces = true, Axes = true, Font = true, PhysicalProperties = true, Ray = true,
	Content = true,
}
local OPAQUE = { BinaryString = true, SharedString = true, ProtectedString = true }

local SECURITY = { p = "PluginSecurity", L = "LocalUserSecurity", R = "RobloxScriptSecurity" }

-- Studio's category order; the rest follow by name.
Api.CategoryOrder = {
	"Appearance", "Data", "Text", "Image", "Transform", "Pivot", "Shape", "Size", "Behavior",
	"Collision", "Part", "Assembly", "Surface", "Surface Inputs", "Camera", "Scrolling", "State",
	"Control", "Input", "Localization", "Character", "Movement", "Animation", "Playback",
}
local CATEGORY_RANK = {}
for index, name in Api.CategoryOrder do
	CATEGORY_RANK[name] = index
end
function Api.categoryRank(name: string): number
	return CATEGORY_RANK[name] or 1000
end

local classCache: { [string]: any } = {}
local propCache: { [string]: any } = {} -- class -> { list = {}, byName = {} } (inherited too)

local function decodeProperty(text: string, className: string)
	local name, code, category, flags = text:match("^([^,]*),([^,]*),(%d+),(.*)$")
	if not name then
		return nil
	end
	local prop = {
		Name = name,
		Class = className,
		Category = Data.Categories[(tonumber(category) :: number) + 1] or "Data",
		ReadOnly = flags:find("r", 1, true) ~= nil,
		Deprecated = flags:find("d", 1, true) ~= nil,
		Hidden = flags:find("h", 1, true) ~= nil,
		NotScriptable = flags:find("n", 1, true) ~= nil,
		WriteOnly = flags:find("w", 1, true) ~= nil,
		WriteNeedsMore = flags:find("W", 1, true) ~= nil,
		Security = "None",
	}
	for letter, level in SECURITY do
		if flags:find(letter, 1, true) then
			prop.Security = level
		end
	end
	local primitive = PRIMITIVES[code]
	if primitive then
		prop.Type = primitive.Type
		prop.DataType = primitive.DataType
		prop.Integer = primitive.Integer == true
	elseif code:sub(1, 2) == "E:" then
		prop.Type = "EnumItem"
		prop.Enum = code:sub(3)
		prop.DataType = prop.Enum
	elseif code:sub(1, 2) == "C:" then
		prop.Type = "Instance"
		prop.ClassRef = code:sub(3)
		prop.DataType = prop.ClassRef
	else
		prop.DataType = code
		prop.Type = DATATYPE_ALIASES[code] or code
	end
	prop.Opaque = OPAQUE[prop.DataType] == true
	prop.Editable = not prop.ReadOnly and not prop.Opaque and Api.EditableTypes[prop.Type] == true
	return prop
end

local function decodeClass(name: string)
	local cached = classCache[name]
	if cached ~= nil then
		return cached or nil
	end
	local raw = Data.Classes[name]
	if not raw then
		classCache[name] = false
		return nil
	end
	local superclass, tags, props = raw:match("^([^|]*)|([^|]*)|(.*)$")
	local info = {
		Name = name,
		Superclass = if superclass ~= "" then superclass else nil,
		NotCreatable = tags:find("N", 1, true) ~= nil,
		Service = tags:find("S", 1, true) ~= nil,
		Deprecated = tags:find("D", 1, true) ~= nil,
		NotBrowsable = tags:find("B", 1, true) ~= nil,
		Own = {},
	}
	for text in (props :: string):gmatch("[^;]+") do
		local prop = decodeProperty(text, name)
		if prop then
			table.insert(info.Own, prop)
		end
	end
	classCache[name] = info
	return info
end

function Api.class(name: string)
	return decodeClass(name)
end

function Api.isKnown(name: string): boolean
	return Data.Classes[name] ~= nil
end

function Api.classNames(): { string }
	local names = {}
	for name in Data.Classes do
		table.insert(names, name)
	end
	table.sort(names)
	return names
end

function Api.superclasses(name: string): { string }
	local list = {}
	local info = decodeClass(name)
	local guard = 0
	while info and info.Superclass and guard < 64 do
		guard += 1
		table.insert(list, info.Superclass)
		info = decodeClass(info.Superclass)
	end
	return list
end

-- Whether class `name` is (or inherits from) `base`, by the data.
function Api.isA(name: string, base: string): boolean
	if name == base then
		return true
	end
	return table.find(Api.superclasses(name), base) ~= nil
end

local function merged(name: string)
	local cached = propCache[name]
	if cached then
		return cached
	end
	local result = { List = {}, ByName = {} }
	local chain = { name }
	for _, superclass in Api.superclasses(name) do
		table.insert(chain, superclass)
	end
	-- Base classes first, so a subclass's own declaration wins.
	for index = #chain, 1, -1 do
		local info = decodeClass(chain[index])
		if info then
			for _, prop in info.Own do
				local existing = result.ByName[prop.Name]
				if existing then
					local position = table.find(result.List, existing)
					if position then
						table.remove(result.List, position)
					end
				end
				result.ByName[prop.Name] = prop
				table.insert(result.List, prop)
			end
		end
	end
	table.sort(result.List, function(a, b)
		return a.Name:lower() < b.Name:lower()
	end)
	propCache[name] = result
	return result
end

-- Every property of a class (inherited too), sorted by name.
function Api.properties(name: string): { any }
	return merged(name).List
end

function Api.property(name: string, prop: string)
	return merged(name).ByName[prop]
end

----------------------------------------------------------------------
-- Instances
----------------------------------------------------------------------

local nearestCache: { [string]: string } = {}
local depthCache: { [string]: number } = {}

local function depthOf(name: string): number
	local cached = depthCache[name]
	if not cached then
		cached = #Api.superclasses(name)
		depthCache[name] = cached
	end
	return cached
end

-- The instance's class when the data knows it, otherwise the deepest
-- known class it IsA (checked once per class name).
function Api.knownClass(instance: Instance): string
	local ok, className = pcall(function()
		return instance.ClassName
	end)
	if not ok or type(className) ~= "string" then
		return "Instance"
	end
	if Data.Classes[className] then
		return className
	end
	local cached = nearestCache[className]
	if cached then
		return cached
	end
	local best, bestDepth = "Instance", 0
	for name in Data.Classes do
		local depth = depthOf(name)
		if depth > bestDepth then
			local okIs, is = pcall(function()
				return instance:IsA(name)
			end)
			if okIs and is then
				best, bestDepth = name, depth
			end
		end
	end
	nearestCache[className] = best
	return best
end

function Api.propertiesOf(instance: Instance): { any }
	return Api.properties(Api.knownClass(instance))
end

local function hiddenReader()
	return if type(gethiddenproperty) == "function" then gethiddenproperty else nil
end
local function hiddenWriter()
	return if type(sethiddenproperty) == "function" then sethiddenproperty else nil
end

-- Reads a property: plain indexing first, Volt's gethiddenproperty for
-- properties scripts can't see.
function Api.read(instance: Instance, name: string, prop: any?): (boolean, any)
	if prop and prop.WriteOnly then
		return false, "write only"
	end
	if not (prop and prop.NotScriptable) then
		local ok, value = pcall(function()
			return (instance :: any)[name]
		end)
		if ok then
			return true, value
		end
		if not hiddenReader() then
			return false, tostring(value)
		end
	end
	local get = hiddenReader()
	if not get then
		return false, "can't be read here (gethiddenproperty is missing)"
	end
	local ok, value = pcall(get, instance, name)
	if not ok then
		return false, tostring(value)
	end
	return true, value
end

function Api.write(instance: Instance, name: string, value: any, prop: any?): (boolean, string?)
	if not (prop and prop.NotScriptable) then
		local ok, err = pcall(function()
			(instance :: any)[name] = value
		end)
		if ok then
			return true, nil
		end
		if not (prop and prop.Hidden) or not hiddenWriter() then
			return false, (tostring(err):gsub("^.-:%d+: ", ""))
		end
	end
	local set = hiddenWriter()
	if not set then
		return false, "can't be changed here (sethiddenproperty is missing)"
	end
	local ok, err = pcall(set, instance, name, value)
	if not ok then
		return false, (tostring(err):gsub("^.-:%d+: ", ""))
	end
	return true, nil
end

--[[
	Properties the data doesn't list (newer than it), from Volt's
	getproperties: { name = value }. Only names not already known.
]]
function Api.extraProperties(instance: Instance): { [string]: any }
	if type(getproperties) ~= "function" then
		return {}
	end
	local ok, all = pcall(getproperties, instance)
	if not ok or type(all) ~= "table" then
		return {}
	end
	local known = merged(Api.knownClass(instance)).ByName
	local extra = {}
	for name, value in all do
		if type(name) == "string" and not known[name] then
			extra[name] = value
		end
	end
	return extra
end

T.Bin:Add(function()
	table.clear(classCache)
	table.clear(propCache)
	table.clear(nearestCache)
end)

return Api
