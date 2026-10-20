--[[
	Tungsten · base/data/categories
	Icon and tint for each class category and each value type.
	Icons are files in base/data/icons/ (drawn white, tinted here).

		Categories.class("part")   -> { Icon = "class_part", Color = Color3 }
		Categories.valueType("Vector3") -> { Icon = "type_vector", Color = Color3, Name = "Vector3" }

	Extending (plugins too; Owner is used for cleanup):
		Categories.addClassCategory("vehicle", { Icon = "class_model", Color = Color3, Title = "Vehicles", Owner = "myplugin" })
		Categories.addValueType("Money", { Icon = "type_number", Color = Color3, Picker = true, Owner = "myplugin" })
	Categories.Version goes up on every change (pickers rebuild their lists).
]]

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

local Categories = {}

Categories.Class = {
	part = { Icon = "class_part", Color = rgb(110, 168, 240), Title = "Parts" },
	model = { Icon = "class_model", Color = rgb(156, 142, 240), Title = "Models" },
	folder = { Icon = "class_folder", Color = rgb(222, 178, 92), Title = "Folders" },
	script = { Icon = "class_script", Color = rgb(120, 200, 140), Title = "Scripts" },
	localscript = { Icon = "class_localscript", Color = rgb(96, 180, 230), Title = "Local scripts" },
	modulescript = { Icon = "class_modulescript", Color = rgb(200, 140, 230), Title = "Modules" },
	gui = { Icon = "class_gui", Color = rgb(240, 150, 60), Title = "GUI containers" },
	frame = { Icon = "class_frame", Color = rgb(222, 166, 118), Title = "GUI frames" },
	text = { Icon = "class_text", Color = rgb(222, 222, 230), Title = "GUI text" },
	button = { Icon = "class_button", Color = rgb(240, 186, 104), Title = "GUI buttons" },
	image = { Icon = "class_image", Color = rgb(120, 210, 200), Title = "Images" },
	layout = { Icon = "class_layout", Color = rgb(168, 168, 180), Title = "GUI layout" },
	remote = { Icon = "class_remote", Color = rgb(236, 110, 110), Title = "Remotes" },
	bindable = { Icon = "class_bindable", Color = rgb(236, 160, 110), Title = "Bindables" },
	value = { Icon = "class_value", Color = rgb(176, 206, 112), Title = "Values" },
	light = { Icon = "class_light", Color = rgb(250, 220, 110), Title = "Lights" },
	sound = { Icon = "class_sound", Color = rgb(120, 190, 250), Title = "Sounds" },
	effect = { Icon = "class_effect", Color = rgb(230, 140, 200), Title = "Effects" },
	constraint = { Icon = "class_constraint", Color = rgb(176, 176, 196), Title = "Constraints" },
	attachment = { Icon = "class_attachment", Color = rgb(110, 220, 170), Title = "Attachments" },
	camera = { Icon = "class_camera", Color = rgb(150, 184, 214), Title = "Cameras" },
	player = { Icon = "class_player", Color = rgb(120, 200, 240), Title = "Players" },
	humanoid = { Icon = "class_humanoid", Color = rgb(230, 190, 150), Title = "Characters" },
	service = { Icon = "class_service", Color = rgb(164, 164, 178), Title = "Services" },
	mesh = { Icon = "class_mesh", Color = rgb(140, 204, 160), Title = "Meshes" },
	animation = { Icon = "class_animation", Color = rgb(222, 132, 172), Title = "Animation" },
	tool = { Icon = "class_tool", Color = rgb(206, 172, 132), Title = "Tools" },
	unknown = { Icon = "class_unknown", Color = rgb(140, 140, 152), Title = "Other" },
}

-- Luau / Roblox value types (typeof names).
local TYPE_STYLE = {
	["nil"] = { "type_nil", rgb(140, 140, 152) },
	boolean = { "type_boolean", rgb(246, 150, 96) },
	number = { "type_number", rgb(246, 190, 96) },
	string = { "type_string", rgb(166, 222, 128) },
	table = { "type_table", rgb(132, 168, 238) },
	["function"] = { "type_function", rgb(240, 216, 128) },
	thread = { "type_thread", rgb(200, 140, 230) },
	userdata = { "type_userdata", rgb(168, 168, 180) },
	buffer = { "type_userdata", rgb(168, 168, 180) },
	Instance = { "class_part", rgb(110, 168, 240) },
	Vector2 = { "type_vector", rgb(110, 196, 240) },
	Vector3 = { "type_vector", rgb(110, 196, 240) },
	Vector2int16 = { "type_vector", rgb(110, 196, 240) },
	Vector3int16 = { "type_vector", rgb(110, 196, 240) },
	CFrame = { "type_cframe", rgb(120, 200, 180) },
	Color3 = { "type_color", rgb(236, 120, 140) },
	BrickColor = { "type_color", rgb(236, 120, 140) },
	ColorSequence = { "type_color", rgb(236, 120, 140) },
	ColorSequenceKeypoint = { "type_color", rgb(236, 120, 140) },
	UDim = { "type_udim", rgb(222, 166, 118) },
	UDim2 = { "type_udim", rgb(222, 166, 118) },
	Rect = { "type_udim", rgb(222, 166, 118) },
	NumberRange = { "type_range", rgb(246, 190, 96) },
	NumberSequence = { "type_range", rgb(246, 190, 96) },
	NumberSequenceKeypoint = { "type_range", rgb(246, 190, 96) },
	EnumItem = { "type_enum", rgb(214, 140, 230) },
	Enum = { "type_enum", rgb(214, 140, 230) },
	Enums = { "type_enum", rgb(214, 140, 230) },
	Ray = { "type_vector", rgb(110, 196, 240) },
	Region3 = { "type_cframe", rgb(120, 200, 180) },
	Region3int16 = { "type_cframe", rgb(120, 200, 180) },
	TweenInfo = { "type_misc", rgb(168, 168, 180) },
	Font = { "type_misc", rgb(168, 168, 180) },
	PhysicalProperties = { "type_misc", rgb(168, 168, 180) },
	Axes = { "type_misc", rgb(168, 168, 180) },
	Faces = { "type_misc", rgb(168, 168, 180) },
	DateTime = { "type_misc", rgb(168, 168, 180) },
	Random = { "type_misc", rgb(168, 168, 180) },
	RBXScriptSignal = { "type_function", rgb(240, 216, 128) },
	RBXScriptConnection = { "type_function", rgb(240, 216, 128) },
	Content = { "type_misc", rgb(168, 168, 180) },
}

-- The value types offered by type pickers, in a sensible order.
Categories.ValueTypes = {
	"nil", "boolean", "number", "string", "table", "function", "thread", "buffer", "userdata",
	"Instance", "Vector2", "Vector3", "Vector2int16", "Vector3int16", "CFrame",
	"Color3", "BrickColor", "ColorSequence", "ColorSequenceKeypoint",
	"UDim", "UDim2", "Rect", "NumberRange", "NumberSequence", "NumberSequenceKeypoint",
	"EnumItem", "Enum", "Ray", "Region3", "Region3int16", "TweenInfo", "Font",
	"PhysicalProperties", "Axes", "Faces", "DateTime", "Random",
	"RBXScriptSignal", "RBXScriptConnection", "Content",
}

-- Attribute values allow only these.
Categories.AttributeTypes = {
	"string", "boolean", "number", "UDim", "UDim2", "BrickColor", "Color3", "Vector2", "Vector3",
	"CFrame", "NumberSequence", "ColorSequence", "NumberRange", "Rect", "Font", "EnumItem",
}

local MISC = { Icon = "type_misc", Color = rgb(168, 168, 180) }

Categories.Version = 0
local BUILTIN_CLASS = {}
for name in Categories.Class do
	BUILTIN_CLASS[name] = true
end
local addedTypes = {} -- name -> owner
local addedClasses = {} -- category -> owner

function Categories.addClassCategory(name: string, style: { [string]: any })
	assert(type(name) == "string" and name ~= "", "a category needs a name")
	assert(not BUILTIN_CLASS[name], ("'%s' is a built-in category"):format(name))
	Categories.Class[name] = {
		Icon = style.Icon or "class_unknown",
		Color = style.Color or MISC.Color,
		Title = style.Title or name,
	}
	addedClasses[name] = style.Owner or "core"
	Categories.Version += 1
end

function Categories.addValueType(name: string, style: { [string]: any })
	assert(type(name) == "string" and name ~= "", "a value type needs a name")
	assert(TYPE_STYLE[name] == nil or addedTypes[name] ~= nil, ("'%s' is a built-in value type"):format(name))
	TYPE_STYLE[name] = { style.Icon or MISC.Icon, style.Color or MISC.Color }
	addedTypes[name] = style.Owner or "core"
	local listed = table.find(Categories.ValueTypes, name)
	if style.Picker ~= false and not listed then
		table.insert(Categories.ValueTypes, name)
	end
	if style.Attribute and not table.find(Categories.AttributeTypes, name) then
		table.insert(Categories.AttributeTypes, name)
	end
	Categories.Version += 1
end

function Categories.removeValueType(name: string)
	if addedTypes[name] == nil then
		return false
	end
	addedTypes[name] = nil
	TYPE_STYLE[name] = nil
	for _, list in { Categories.ValueTypes, Categories.AttributeTypes } do
		local index = table.find(list, name)
		if index then
			table.remove(list, index)
		end
	end
	Categories.Version += 1
	return true
end

function Categories.removeOwner(owner: string): number
	local count = 0
	for name, who in table.clone(addedTypes) do
		if who == owner then
			Categories.removeValueType(name)
			count += 1
		end
	end
	for name, who in table.clone(addedClasses) do
		if who == owner then
			addedClasses[name] = nil
			Categories.Class[name] = nil
			count += 1
		end
	end
	if count > 0 then
		Categories.Version += 1
	end
	return count
end

function Categories.class(category: string)
	return Categories.Class[category] or Categories.Class.unknown
end

function Categories.valueType(typeName: string)
	local style = TYPE_STYLE[typeName]
	if not style then
		return { Name = typeName, Icon = MISC.Icon, Color = MISC.Color }
	end
	return { Name = typeName, Icon = style[1], Color = style[2] }
end

return Categories
