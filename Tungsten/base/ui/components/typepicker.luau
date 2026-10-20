--[[
	Tungsten · base/ui/components/typepicker
	A searchable dropdown of classes, value types or enum items, each with
	its icon.

		TypePicker.new({
			Parent = row, Width = 200,
			Kind = "class",        -- every known class
			     | "creatable"     -- classes Instance.new can make (Insert Object)
			     | "isa:BasePart"  -- classes that are a BasePart (object references)
			     | "valueType"     -- Luau/Roblox value types
			     | "attribute"     -- types an attribute may hold
			     | "enum:Material" -- items of an enum
			Value = "Part",        -- enum kinds take/return EnumItems
			OnChanged = function(value) end,
		})

	TypePicker.options(kind) returns the option list on its own, and
	TypePicker.iconFor(kind, value) the icon + tint for a single value
	(lists use these for typed columns). iconFor("value", anyValue) works
	on real values: an Instance gets its class icon, a Vector3 the vector
	icon, and so on. TypePicker.isPickerKind(kind) tells whether a kind
	has an option list.

	More kinds (plugins too):
		TypePicker.registerKind("team", {
			Options = function(arg) return { { Value = ..., Text = ..., Icon = ... } } end,
			Icon = function(arg, value) return "class_player", Color3 end,   -- optional
			Dynamic = true,   -- build the options every time (default: once)
			Owner = "myplugin",
		})
		-- "team" or "team:Red" (arg = "Red"); usable in List columns and
		-- TypePicker.new({ Kind = "team" }).
]]

local T = ...
local Classes = T.import("base/data/classes")
local Categories = T.import("base/data/categories")
local Dropdown = T.import("base/ui/components/dropdown")
local UI = T.import("base/ui/ui")

local TypePicker = {}

local cache = {}
local custom: { [string]: any } = {}

local function splitKind(kind: string): (string, string?)
	local name, arg = kind:match("^([^:]+):(.*)$")
	if name then
		return name, arg
	end
	return kind, nil
end

local BUILTIN = { class = true, creatable = true, isa = true, valueType = true, attribute = true, enum = true, value = true }

function TypePicker.registerKind(name: string, definition: { [string]: any })
	assert(type(name) == "string" and name:match("^[%a_][%w_%-]*$"), "a picker kind needs a plain name")
	assert(not BUILTIN[name], ("'%s' is a built-in picker kind"):format(name))
	assert(type(definition) == "table" and type(definition.Options) == "function", "a picker kind needs Options(arg)")
	custom[name] = definition
	for key in table.clone(cache) do
		if splitKind(key) == name then
			cache[key] = nil
		end
	end
end

function TypePicker.removeKind(name: string)
	custom[name] = nil
	for key in table.clone(cache) do
		if splitKind(key) == name then
			cache[key] = nil
		end
	end
end

-- Removes every kind an owner registered (a plugin being disabled).
function TypePicker.removeOwner(owner: string): number
	local count = 0
	for name, definition in table.clone(custom) do
		if definition.Owner == owner then
			TypePicker.removeKind(name)
			count += 1
		end
	end
	return count
end

T.Bin:Add(function()
	table.clear(custom)
end)

-- Whether className is (or inherits from) baseName, using a throwaway
-- instance when the class can be created.
local isaCache = {}
local function classIsA(className: string, baseName: string): boolean
	if className == baseName then
		return true
	end
	local key = className .. ">" .. baseName
	local cached = isaCache[key]
	if cached ~= nil then
		return cached
	end
	local result = false
	if Classes.isCreatable(className) then
		local ok, instance = pcall(Instance.new, className)
		if ok and instance then
			result = instance:IsA(baseName)
			instance:Destroy()
		end
	end
	isaCache[key] = result
	return result
end

local function classOption(name: string)
	local style = Classes.style(name)
	return {
		Value = name,
		Text = name,
		Icon = style.Icon,
		IconColor = style.Color,
		Hint = Categories.class(Classes.category(name)).Title,
	}
end

-- Options for a kind, after the UI framework's "Options" filters
-- (which may add to built-in kinds too). origin: who asks (see base/ui/ui).
function TypePicker.options(kind: string, origin: string?): { any }
	local base = TypePicker._options(kind)
	if not UI.has("TypePicker", "Options") then
		return base
	end
	return Dropdown.normalize(UI.apply("TypePicker", "Options", origin, table.clone(base), kind))
end

local cacheVersion = Categories.Version

function TypePicker._options(kind: string): { any }
	-- Classes or value types were added or removed: rebuild the lists.
	if Categories.Version ~= cacheVersion then
		cacheVersion = Categories.Version
		table.clear(cache)
		table.clear(isaCache)
	end
	local cached = cache[kind]
	if cached then
		return cached
	end
	local customName, customArg = splitKind(kind)
	local definition = custom[customName]
	if definition then
		local ok, list = pcall(definition.Options, customArg)
		if not ok or type(list) ~= "table" then
			local problem = if ok then "Options didn't return a list" else list
			T.Log.warn("typepicker", ("picker kind '%s' failed: %s"):format(customName, tostring(problem)))
			local okImport, Reporter = pcall(T.import, "console/reporter")
			if okImport then
				Reporter.ownerFault(definition.Owner, ("picker kind '%s'"):format(customName), problem)
			end
			list = {}
		end
		local options = Dropdown.normalize(list)
		if not definition.Dynamic then
			cache[kind] = options
		end
		return options
	end
	local options = {}
	if kind == "class" or kind == "creatable" then
		-- creatable: every class Instance.new can make (base/explorer/insert:
		-- the bundled class data plus classes taught with Classes.add).
		for _, name in (if kind == "class" then Classes.list() else T.import("base/explorer/insert").classes()) do
			table.insert(options, classOption(name))
		end
	elseif kind:sub(1, 4) == "isa:" then
		local base = kind:sub(5)
		for _, name in Classes.list() do
			if classIsA(name, base) then
				table.insert(options, classOption(name))
			end
		end
	elseif kind == "valueType" or kind == "attribute" then
		for _, name in (if kind == "valueType" then Categories.ValueTypes else Categories.AttributeTypes) do
			local style = Categories.valueType(name)
			table.insert(options, { Value = name, Text = name, Icon = style.Icon, IconColor = style.Color })
		end
	elseif kind:sub(1, 5) == "enum:" then
		local enumName = kind:sub(6)
		local ok, items = pcall(function()
			return (Enum :: any)[enumName]:GetEnumItems()
		end)
		if ok and items then
			local style = Categories.valueType("EnumItem")
			for _, item in items do
				table.insert(options, {
					Value = item,
					Text = item.Name,
					Icon = style.Icon,
					IconColor = style.Color,
					Hint = tostring(item.Value),
				})
			end
		else
			T.Log.warn("typepicker", "unknown enum " .. enumName)
		end
	else
		error(("unknown type picker kind '%s'"):format(kind), 2)
	end
	cache[kind] = options
	return options
end

function TypePicker.iconFor(kind: string, value: any): (string?, Color3?)
	if value == nil then
		return nil, nil
	end
	if kind == "value" then
		-- A real value (number, Vector3, Instance, ...): icon by its type or class.
		return T.import("base/types").icon(value)
	end
	local customName, customArg = splitKind(kind)
	local definition = custom[customName]
	if definition then
		if definition.Icon then
			local ok, icon, color = pcall(definition.Icon, customArg, value)
			if ok then
				return icon, color
			end
		end
		for _, option in TypePicker._options(kind) do
			if option.Value == value then
				return option.Icon, option.IconColor
			end
		end
		return nil, nil
	end
	if kind == "class" or kind == "creatable" or kind:sub(1, 4) == "isa:" then
		local style = Classes.style(tostring(value))
		return style.Icon, style.Color
	elseif kind == "valueType" or kind == "attribute" then
		local style = Categories.valueType(tostring(value))
		return style.Icon, style.Color
	elseif kind:sub(1, 5) == "enum:" then
		local style = Categories.valueType("EnumItem")
		return style.Icon, style.Color
	end
	return nil, nil
end

function TypePicker.isPickerKind(kind: string?): boolean
	if type(kind) ~= "string" then
		return false
	end
	return kind == "class" or kind == "creatable" or kind == "valueType" or kind == "attribute"
		or kind:sub(1, 4) == "isa:" or kind:sub(1, 5) == "enum:" or custom[(splitKind(kind))] ~= nil
end

function TypePicker.new(props: { [string]: any })
	local kind = props.Kind or "class"
	local dropdownProps = table.clone(props)
	dropdownProps.Kind = nil
	dropdownProps.Options = TypePicker.options(kind, props.Origin)
	dropdownProps.Searchable = true
	dropdownProps.Multi = false
	dropdownProps.PopupWidth = props.PopupWidth or 240
	local definition = custom[(splitKind(kind))]
	dropdownProps.Placeholder = props.Placeholder
		or (if definition then definition.Placeholder or "Choose…"
			elseif kind:sub(1, 5) == "enum:" then "Choose an item…"
			elseif kind == "valueType" or kind == "attribute" then "Choose a type…"
			else "Choose a class…")
	local picker = Dropdown.new(dropdownProps)
	picker.Kind = kind
	UI.fire("TypePicker", "Created", props.Origin or "core", picker, props)
	return picker
end

return UI.register("TypePicker", TypePicker, {
	Description = "searchable pickers of classes, value types, enum items and registered kinds",
	Events = {
		Created = "picker, props · a picker (a Dropdown with Kind) was made",
	},
	Filters = {
		Options = "options, kind · the options of any kind, built-in ones too",
	},
})
