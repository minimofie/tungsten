--[[
	Tungsten · base/types
	Describes any value for the console, lists and (later) the property
	editors: its type, class, base class, icon and a short display text.

		Types.tag(5)                      -> "<number>"
		Types.tag(workspace.Baseplate)    -> "Part <BasePart>"
		Types.short("hi")                 -> "\"hi\""
		Types.describe(value)             -> { Type, Class, Base, Icon, Color, Text, Tag }
		Types.path(instance)              -> game.Workspace.Baseplate
		Types.pretty(tbl)                 -> multi-line text for tables
		Types.display(value)              -> list-cell text (text without quotes)
		Types.isA(value, "BasePart")      -> class check for Instances, type check otherwise
		Types.classInfo("Part")           -> { Class, Category, Title, Icon, Color, Creatable }
		Types.option(value)               -> dropdown/list option with icon and type hint
		Types.signature(fn)               -> "function f(a, b, ...)"

	Editing (text <-> typed values; used by list cells, /setas, and the
	property editors later)
		Types.editText(Vector3.new(1, 2, 3))      -> "1, 2, 3"
		Types.parse("1, 2, 3", "Vector3")         -> true, Vector3.new(1, 2, 3)
		Types.parse("#ff8800", "Color3")          -> true, Color3
		Types.parse("game.Workspace.Baseplate", "Instance")
		Types.parse("Plastic", "EnumItem", { Enum = "Material" })
		Types.parse("5")                          -> true, 5   (no type: best guess)
		Types.default("Vector3")                  -> Vector3.zero
		Types.convert(value, "string")            -> true, "…"

	Icons and tints come from base/data/classes and base/data/categories,
	so a value looks the same here as in the type pickers.

	Value types of your own (plugins too) work everywhere values do: type
	pickers, list cells, the cell editor, /setas and /cast.
		Types.registerType("Money", {
			Is = function(value) return type(value) == "table" and value.__money end,
			Parse = function(text, opts) return true, makeMoney(text) end,   -- or false, reason
			EditText = function(value) return tostring(value.Amount) end,
			Display = function(value) return "$" .. value.Amount end,      -- optional
			Default = function() return makeMoney(0) end,                   -- optional
			Hint = "an amount, e.g. 12.50",                                 -- optional
			Icon = "type_number", Color = Color3.fromRGB(120, 200, 120),    -- optional
			Owner = "myplugin",
		})
		Types.typeName(value) -> "Money" (or typeof(value))
]]

local T = ...
local Classes = T.import("base/data/classes")
local Categories = T.import("base/data/categories")

local Types = {}

----------------------------------------------------------------------
-- Registered value types
----------------------------------------------------------------------

local custom: { [string]: any } = {}
local customOrder: { string } = {}

local BUILTIN_TYPES = {}
for _, name in Categories.ValueTypes do
	BUILTIN_TYPES[name] = true
end
BUILTIN_TYPES.any = true

function Types.registerType(name: string, definition: { [string]: any })
	assert(type(name) == "string" and name:match("^[%a_][%w_]*$"), "a type name is letters, digits and _")
	assert(not BUILTIN_TYPES[name], ("'%s' is a built-in type"):format(name))
	assert(type(definition) == "table", "a type needs a definition table")
	assert(type(definition.Is) == "function", "a type needs Is(value)")
	assert(type(definition.Parse) == "function", "a type needs Parse(text)")
	if not custom[name] then
		table.insert(customOrder, name)
	end
	custom[name] = table.clone(definition)
	Categories.addValueType(name, {
		Icon = definition.Icon,
		Color = definition.Color,
		Picker = definition.Picker ~= false,
		Owner = definition.Owner,
	})
end

function Types.unregisterType(name: string): boolean
	if not custom[name] then
		return false
	end
	custom[name] = nil
	local index = table.find(customOrder, name)
	if index then
		table.remove(customOrder, index)
	end
	Categories.removeValueType(name)
	return true
end

function Types.removeOwner(owner: string): number
	local count = 0
	for name, definition in table.clone(custom) do
		if definition.Owner == owner then
			Types.unregisterType(name)
			count += 1
		end
	end
	return count
end

function Types.registered(): { string }
	return table.clone(customOrder)
end

function Types.getType(name: string)
	return custom[name]
end

-- The registered type a value belongs to, if any.
local function customOf(value: any): (string?, any)
	if #customOrder == 0 then
		return nil, nil
	end
	for _, name in customOrder do
		local definition = custom[name]
		local ok, is = pcall(definition.Is, value)
		if ok and is then
			return name, definition
		end
	end
	return nil, nil
end

-- typeof, or the registered type's name.
function Types.typeName(value: any): string
	local name = customOf(value)
	return name or typeof(value)
end

-- Text shown under the cell editor for a type.
function Types.hint(typeName: string): string
	local definition = custom[typeName]
	if definition and definition.Hint then
		return typeName .. " · " .. tostring(definition.Hint)
	end
	if typeName == "string" then
		return "text"
	elseif typeName == "any" then
		return "any value"
	elseif typeName == "Instance" then
		return "Instance · a path like game.Workspace.Part, or $variable"
	elseif typeName == "Color3" then
		return "Color3 · r, g, b (0-255) or #rrggbb"
	end
	local hint = Types.Hints[typeName]
	if hint then
		return typeName .. " · " .. hint
	end
	return typeName
end

-- What to type for each type (shown under the cell editor).
Types.Hints = {
	number = "a number",
	boolean = "true or false",
	Vector2 = "x, y",
	Vector3 = "x, y, z",
	Vector2int16 = "x, y (whole numbers)",
	Vector3int16 = "x, y, z (whole numbers)",
	UDim = "scale, offset",
	UDim2 = "xScale, xOffset, yScale, yOffset",
	Rect = "minX, minY, maxX, maxY",
	NumberRange = "min, max",
	CFrame = "x, y, z (or x, y, z, rx, ry, rz in degrees, or all 12 parts)",
	BrickColor = "a BrickColor name or number",
	EnumItem = "an item name",
	NumberSequence = "a number, or time: value; time: value +- envelope",
	ColorSequence = "a color, or time: #rrggbb; time: #rrggbb",
	Faces = "faces: Right, Top, Back, Left, Bottom, Front",
	Axes = "axes: X, Y, Z",
	Font = "family, weight, style (e.g. SourceSansPro, Bold, Italic)",
	PhysicalProperties = "density, friction, elasticity[, frictionWeight, elasticityWeight], or a material",
	Ray = "origin x, y, z; direction x, y, z",
	Content = "an asset id, rbxassetid://…, or a path to an object",
	table = "a Luau table, e.g. { 1, 2, x = 3 }",
}

-- Base classes worth naming, most specific first. The first one a value
-- IsA (other than its own class) is shown as "<Base>".
Types.BaseClasses = {
	"BasePart", "GuiButton", "GuiObject", "LayerCollector", "GuiBase3d", "BaseScript", "LuaSourceContainer",
	"ValueBase", "Light", "Constraint", "JointInstance", "BodyMover", "PostEffect", "SoundEffect",
	"DataModelMesh", "FaceInstance", "Clothing", "BaseRemoteEvent", "UIComponent", "BackpackItem",
	"WorldRoot", "Model", "PVInstance", "Instance",
}

local MAX_SHORT = 120

----------------------------------------------------------------------
-- Basics
----------------------------------------------------------------------

function Types.typeOf(value: any): string
	return typeof(value)
end

function Types.isInstance(value: any): boolean
	return typeof(value) == "Instance"
end

-- ClassName, or nil (also for destroyed/locked instances that error).
function Types.classOf(value: any): string?
	if typeof(value) ~= "Instance" then
		return nil
	end
	local ok, name = pcall(function()
		return value.ClassName
	end)
	return if ok then name else nil
end

function Types.baseOf(value: any): string?
	local class = Types.classOf(value)
	if not class then
		return nil
	end
	for _, base in Types.BaseClasses do
		if base ~= class then
			local ok, is = pcall(function()
				return value:IsA(base)
			end)
			if ok and is then
				return base
			end
		end
	end
	return nil
end

-- Icon name and tint for a value.
function Types.icon(value: any): (string, Color3)
	local class = Types.classOf(value)
	if class then
		local style = Classes.style(class)
		return style.Icon, style.Color
	end
	local style = Categories.valueType(Types.typeName(value))
	return style.Icon, style.Color
end

----------------------------------------------------------------------
-- Text
----------------------------------------------------------------------

local function clip(text: string, limit: number?): string
	limit = limit or MAX_SHORT
	if #text > (limit :: number) then
		return text:sub(1, (limit :: number) - 1) .. "…"
	end
	return text
end

local function quote(text: string): string
	text = text:gsub("\\", "\\\\"):gsub("\n", "\\n"):gsub("\r", "\\r"):gsub("\t", "\\t"):gsub('"', '\\"')
	return '"' .. text .. '"'
end

local function isIdentifier(text: string): boolean
	return type(text) == "string" and text:match("^[%a_][%w_]*$") ~= nil
end
Types.isIdentifier = isIdentifier

local function nameOf(instance: Instance): string
	local ok, name = pcall(function()
		return instance.Name
	end)
	return if ok then tostring(name) else "<locked>"
end

local function countEntries(tbl): (number, number)
	local array = #tbl
	local total = 0
	for _ in tbl do
		total += 1
	end
	return array, total
end

-- One-line display of a value (no type tag).
function Types.short(value: any, limit: number?): string
	local customName, definition = customOf(value)
	if customName then
		local display = definition.Display or definition.EditText
		if display then
			local ok, text = pcall(display, value)
			if ok and text ~= nil then
				return clip(tostring(text), limit)
			end
		end
		return clip("<" .. customName .. ">", limit)
	end
	local kind = typeof(value)
	if kind == "string" then
		return clip(quote(value), limit)
	elseif kind == "Instance" then
		return clip(nameOf(value), limit)
	elseif kind == "table" then
		local ok, meta = pcall(getmetatable, value)
		if ok and type(meta) == "table" and rawget(meta, "__tostring") then
			local okText, text = pcall(tostring, value)
			if okText then
				return clip(tostring(text), limit)
			end
		end
		local array, total = countEntries(value)
		if total == 0 then
			return "{}"
		end
		-- Small tables inline, bigger ones as a count.
		local parts = {}
		local shown = 0
		if array == total then
			for index = 1, math.min(array, 6) do
				local item = value[index]
				table.insert(parts, if type(item) == "table" then "{…}" else Types.short(item, 24))
				shown += 1
			end
		else
			for key, item in value do
				if shown >= 4 then
					break
				end
				local keyText = if isIdentifier(key) then key else "[" .. Types.short(key, 16) .. "]"
				table.insert(parts, keyText .. " = " .. (if type(item) == "table" then "{…}" else Types.short(item, 24)))
				shown += 1
			end
		end
		local text = "{" .. table.concat(parts, ", ") .. (if total > shown then ", …" else "") .. "}"
		if total > shown then
			text ..= ("  (%d entries)"):format(total)
		end
		return clip(text, limit)
	elseif kind == "function" then
		return clip(Types.signature(value), limit)
	elseif kind == "EnumItem" then
		return clip(tostring(value), limit)
	end
	local ok, text = pcall(tostring, value)
	return clip(if ok then tostring(text) else "<" .. kind .. ">", limit)
end

-- "<number>", "Part <BasePart>", "Folder <Instance>".
function Types.tag(value: any): string
	local customName = customOf(value)
	if customName then
		return "<" .. customName .. ">"
	end
	local class = Types.classOf(value)
	if class then
		local base = Types.baseOf(value)
		return if base then ("%s <%s>"):format(class, base) else class
	end
	if typeof(value) == "Instance" then
		return "<Instance>"
	end
	return "<" .. typeof(value) .. ">"
end

-- "function name(a, b, ...)" from what debug.info can see. C functions
-- (the engine's and the executor's) have no parameter names: "(...)".
function Types.signature(fn: any): string
	if type(fn) ~= "function" then
		return Types.short(fn)
	end
	local okName, name = pcall(debug.info, fn, "n")
	local okArgs, count, vararg = pcall(debug.info, fn, "a")
	local okSource, source = pcall(debug.info, fn, "s")
	local isC = okSource and source == "[C]"
	local label = if okName and type(name) == "string" and name ~= "" then "function " .. name else "function"
	if isC or not okArgs or type(count) ~= "number" then
		return label .. "(...)"
	end
	local params = {}
	for index = 1, math.min(count, 8) do
		table.insert(params, "a" .. index)
	end
	if count > 8 then
		table.insert(params, "…")
	end
	if vararg then
		table.insert(params, "...")
	end
	return label .. "(" .. table.concat(params, ", ") .. ")"
end

-- Facts about a function value.
function Types.functionInfo(fn: any)
	if type(fn) ~= "function" then
		return nil
	end
	local okSource, source = pcall(debug.info, fn, "s")
	local okLine, line = pcall(debug.info, fn, "l")
	local okArgs, count, vararg = pcall(debug.info, fn, "a")
	return {
		Signature = Types.signature(fn),
		Kind = if okSource and source == "[C]" then "C" else "Luau",
		Source = if okSource then source else nil,
		Line = if okLine and type(line) == "number" and line > 0 then line else nil,
		Params = if okArgs then count else nil,
		Vararg = if okArgs then vararg == true else nil,
	}
end

-- Everything at once.
function Types.describe(value: any)
	local icon, color = Types.icon(value)
	return {
		Type = typeof(value),
		Class = Types.classOf(value),
		Base = Types.baseOf(value),
		Icon = icon,
		Color = color,
		Text = Types.short(value),
		Tag = Types.tag(value),
		Function = Types.functionInfo(value),
	}
end

-- Text for a list cell: like short(), but text without quotes and
-- Instances by name.
function Types.display(value: any, limit: number?): string
	if value == nil then
		return ""
	end
	if type(value) == "string" then
		return clip((value:gsub("[\r\n\t]", " ")), limit or 200)
	end
	if typeof(value) == "EnumItem" then
		return value.Name
	end
	return Types.short(value, limit or 200)
end

-- Class check for Instances (IsA), type check for everything else.
-- "any" matches everything; "Instance" matches every Instance.
function Types.isA(value: any, name: string): boolean
	if name == "any" then
		return true
	end
	local definition = custom[name]
	if definition then
		local ok, is = pcall(definition.Is, value)
		return ok and is == true
	end
	local kind = typeof(value)
	if kind == "Instance" then
		if name == "Instance" then
			return true
		end
		local ok, is = pcall(function()
			return value:IsA(name)
		end)
		return ok and is == true
	end
	return kind == name or type(value) == name
end

-- What Tungsten knows about a class without an instance of it.
function Types.classInfo(className: string)
	local category = Classes.category(className)
	local style = Categories.class(category)
	return {
		Class = className,
		Category = category,
		Title = style.Title,
		Icon = style.Icon,
		Color = style.Color,
		Creatable = Classes.isCreatable(className),
	}
end

-- An option for Dropdown / List rows showing a value.
function Types.option(value: any, text: string?)
	local icon, color = Types.icon(value)
	return {
		Value = value,
		Text = text or Types.display(value),
		Icon = icon,
		IconColor = color,
		Hint = Types.tag(value),
	}
end

-- Code that reaches an instance: game.Workspace.Baseplate,
-- game.Workspace["My Part"]. Instances outside the game start with
-- their topmost ancestor's name.
function Types.path(instance: Instance): string
	if typeof(instance) ~= "Instance" then
		return Types.short(instance)
	end
	local parts = {}
	local current: Instance? = instance
	local guard = 0
	while current and guard < 200 do
		guard += 1
		if current == game then
			table.insert(parts, 1, "game")
			break
		end
		local name = nameOf(current)
		local parent = current.Parent
		if parent == nil then
			table.insert(parts, 1, if isIdentifier(name) then name else quote(name))
			break
		end
		table.insert(parts, 1, if isIdentifier(name) then "." .. name else "[" .. quote(name) .. "]")
		current = parent
	end
	return table.concat(parts)
end

-- Multi-line view of a table (nested to `depth`), for /get and friends.
function Types.pretty(value: any, depth: number?, maxEntries: number?): { string }
	depth = depth or 2
	maxEntries = maxEntries or 60
	local lines = {}
	local seen = {}
	local count = 0

	local function walk(tbl, indent: string, level: number)
		seen[tbl] = true
		local keys = {}
		for key in tbl do
			table.insert(keys, key)
		end
		table.sort(keys, function(a, b)
			local ta, tb = type(a), type(b)
			if ta ~= tb then
				return ta < tb
			end
			if ta == "number" or ta == "string" then
				return a < b
			end
			return tostring(a) < tostring(b)
		end)
		for _, key in keys do
			if count >= (maxEntries :: number) then
				table.insert(lines, indent .. "…")
				return
			end
			count += 1
			local item = tbl[key]
			local keyText = if isIdentifier(key) then key else "[" .. Types.short(key, 30) .. "]"
			if type(item) == "table" and not seen[item] and level < (depth :: number) and next(item) ~= nil then
				table.insert(lines, ("%s%s = {"):format(indent, keyText))
				walk(item, indent .. "    ", level + 1)
				table.insert(lines, indent .. "}")
			else
				table.insert(lines, ("%s%s = %s  %s"):format(indent, keyText, Types.short(item, 80), Types.tag(item)))
			end
		end
	end

	if type(value) ~= "table" then
		return { Types.short(value) .. "  " .. Types.tag(value) }
	end
	if next(value) == nil then
		return { "{}" }
	end
	table.insert(lines, "{")
	walk(value, "    ", 1)
	table.insert(lines, "}")
	return lines
end

-- Luau source that recreates a value (as far as possible). Instances
-- become their path; things with no literal form become a comment.
local function num(n: number): string
	if n ~= n then
		return "0/0"
	elseif n == math.huge then
		return "math.huge"
	elseif n == -math.huge then
		return "-math.huge"
	elseif n == math.floor(n) and math.abs(n) < 2 ^ 53 then
		return ("%d"):format(n)
	end
	local short = ("%.6g"):format(n)
	return if tonumber(short) == n then short else ("%.17g"):format(n)
end

local LITERALS = {
	Vector2 = function(v) return ("Vector2.new(%s, %s)"):format(num(v.X), num(v.Y)) end,
	Vector3 = function(v) return ("Vector3.new(%s, %s, %s)"):format(num(v.X), num(v.Y), num(v.Z)) end,
	Vector2int16 = function(v) return ("Vector2int16.new(%s, %s)"):format(num(v.X), num(v.Y)) end,
	Vector3int16 = function(v) return ("Vector3int16.new(%s, %s, %s)"):format(num(v.X), num(v.Y), num(v.Z)) end,
	UDim = function(v) return ("UDim.new(%s, %s)"):format(num(v.Scale), num(v.Offset)) end,
	UDim2 = function(v)
		return ("UDim2.new(%s, %s, %s, %s)"):format(num(v.X.Scale), num(v.X.Offset), num(v.Y.Scale), num(v.Y.Offset))
	end,
	Color3 = function(v)
		return ("Color3.fromRGB(%d, %d, %d)"):format(math.floor(v.R * 255 + 0.5), math.floor(v.G * 255 + 0.5), math.floor(v.B * 255 + 0.5))
	end,
	BrickColor = function(v) return ("BrickColor.new(%s)"):format(quote(v.Name)) end,
	CFrame = function(v)
		local parts = { v:GetComponents() }
		for index, part in parts do
			parts[index] = num(part)
		end
		return "CFrame.new(" .. table.concat(parts, ", ") .. ")"
	end,
	NumberRange = function(v) return ("NumberRange.new(%s, %s)"):format(num(v.Min), num(v.Max)) end,
	Rect = function(v) return ("Rect.new(%s, %s, %s, %s)"):format(num(v.Min.X), num(v.Min.Y), num(v.Max.X), num(v.Max.Y)) end,
	EnumItem = function(v) return tostring(v) end,
	NumberSequence = function(v)
		local points = v.Keypoints
		if #points == 2 and points[1].Value == points[2].Value and points[1].Envelope == 0 and points[2].Envelope == 0 then
			return ("NumberSequence.new(%s)"):format(num(points[1].Value))
		end
		local parts = {}
		for _, point in points do
			table.insert(parts, if point.Envelope ~= 0
				then ("NumberSequenceKeypoint.new(%s, %s, %s)"):format(num(point.Time), num(point.Value), num(point.Envelope))
				else ("NumberSequenceKeypoint.new(%s, %s)"):format(num(point.Time), num(point.Value)))
		end
		return "NumberSequence.new({ " .. table.concat(parts, ", ") .. " })"
	end,
	ColorSequence = function(v)
		local function rgb(c)
			return ("Color3.fromRGB(%d, %d, %d)"):format(math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5))
		end
		local points = v.Keypoints
		if #points == 2 and points[1].Value == points[2].Value then
			return ("ColorSequence.new(%s)"):format(rgb(points[1].Value))
		end
		local parts = {}
		for _, point in points do
			table.insert(parts, ("ColorSequenceKeypoint.new(%s, %s)"):format(num(point.Time), rgb(point.Value)))
		end
		return "ColorSequence.new({ " .. table.concat(parts, ", ") .. " })"
	end,
	Faces = function(v)
		local parts = {}
		for _, name in Types.FaceNames do
			if v[name] then
				table.insert(parts, "Enum.NormalId." .. name)
			end
		end
		return "Faces.new(" .. table.concat(parts, ", ") .. ")"
	end,
	Axes = function(v)
		local parts = {}
		for _, name in { "X", "Y", "Z" } do
			if v[name] then
				table.insert(parts, "Enum.Axis." .. name)
			end
		end
		return "Axes.new(" .. table.concat(parts, ", ") .. ")"
	end,
	Font = function(v)
		return ("Font.new(%s, Enum.FontWeight.%s, Enum.FontStyle.%s)"):format(quote(v.Family), v.Weight.Name, v.Style.Name)
	end,
	PhysicalProperties = function(v)
		return ("PhysicalProperties.new(%s, %s, %s, %s, %s)"):format(
			num(v.Density), num(v.Friction), num(v.Elasticity), num(v.FrictionWeight), num(v.ElasticityWeight))
	end,
	Ray = function(v)
		local o, d = v.Origin, v.Direction
		return ("Ray.new(Vector3.new(%s, %s, %s), Vector3.new(%s, %s, %s))"):format(num(o.X), num(o.Y), num(o.Z), num(d.X), num(d.Y), num(d.Z))
	end,
	Content = function(v)
		local source = v.SourceType
		if source == Enum.ContentSourceType.Uri then
			return ("Content.fromUri(%s)"):format(quote(v.Uri))
		elseif source == Enum.ContentSourceType.Object then
			return ("Content.fromObject(%s)"):format(if v.Object then Types.path(v.Object) else "nil")
		end
		return "Content.none"
	end,
}

Types.FaceNames = { "Right", "Top", "Back", "Left", "Bottom", "Front" }

-- A font family's short name: "rbxasset://fonts/families/Arial.json" -> "Arial".
function Types.fontFamilyName(family: string): string
	return family:match("^rbxasset://fonts/families/([^/]+)%.json$") or family
end

----------------------------------------------------------------------
-- CFrame parts (what the properties panel edits)
----------------------------------------------------------------------

local function tidyAngle(degrees: number): number
	local rounded = math.floor(degrees * 1000 + 0.5) / 1000
	if rounded == 0 then
		return 0 -- no -0
	end
	return rounded
end

-- Position and orientation (degrees, the order Studio shows) of a CFrame.
function Types.cframeParts(cf: CFrame): (Vector3, Vector3)
	local rx, ry, rz = cf:ToOrientation()
	return cf.Position, Vector3.new(tidyAngle(math.deg(rx)), tidyAngle(math.deg(ry)), tidyAngle(math.deg(rz)))
end

-- A CFrame from a position and an orientation in degrees.
function Types.cframeFrom(position: Vector3, orientation: Vector3): CFrame
	return CFrame.new(position.X, position.Y, position.Z)
		* CFrame.fromOrientation(math.rad(orientation.X), math.rad(orientation.Y), math.rad(orientation.Z))
end

local KEYWORDS = {}
for _, word in { "and", "break", "do", "else", "elseif", "end", "false", "for", "function", "if", "in", "local", "nil", "not", "or", "repeat", "return", "then", "true", "until", "while", "continue" } do
	KEYWORDS[word] = true
end

function Types.literal(value: any, indent: string?, seen: { [any]: boolean }?): string
	indent = indent or ""
	local kind = typeof(value)
	if kind == "nil" or kind == "boolean" then
		return tostring(value)
	elseif kind == "number" then
		return num(value)
	elseif kind == "string" then
		return quote(value)
	elseif kind == "Instance" then
		return Types.path(value)
	elseif LITERALS[kind] then
		local ok, text = pcall(LITERALS[kind], value)
		return if ok then text else ("nil --[[ %s ]]"):format(kind)
	elseif kind == "table" then
		seen = seen or {}
		if (seen :: any)[value] then
			return "nil --[[ cycle ]]"
		end
		(seen :: any)[value] = true
		if next(value) == nil then
			return "{}"
		end
		local inner = (indent :: string) .. "\t"
		local parts = {}
		local array = #value
		for index = 1, array do
			table.insert(parts, inner .. Types.literal(value[index], inner, seen) .. ",")
		end
		local keys = {}
		for key in value do
			if not (type(key) == "number" and key >= 1 and key <= array and key == math.floor(key)) then
				table.insert(keys, key)
			end
		end
		table.sort(keys, function(a, b)
			return tostring(a) < tostring(b)
		end)
		for _, key in keys do
			local keyText = if isIdentifier(key) and not KEYWORDS[key] then key else "[" .. Types.literal(key, inner, seen) .. "]"
			table.insert(parts, ("%s%s = %s,"):format(inner, keyText, Types.literal(value[key], inner, seen)))
		end
		(seen :: any)[value] = nil
		return "{\n" .. table.concat(parts, "\n") .. "\n" .. (indent :: string) .. "}"
	end
	return ("nil --[[ %s ]]"):format(kind)
end

----------------------------------------------------------------------
-- Editing: values as text and back
----------------------------------------------------------------------

local function trimText(text: string): string
	return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- "Vector3.new(1, 2, 3)", "(1, 2, 3)", "{1, 2, 3}", "1 2 3" -> { 1, 2, 3 }
local function numbers(text: string): { number }?
	local body = trimText(text)
	body = body:gsub("^[%a_][%w_%.]*%s*%(", "("):gsub("^[%(%{%[]", ""):gsub("[%)%}%]]$", "")
	body = body:gsub("[{}()%[%]]", " ")
	local list = {}
	for piece in body:gmatch("[^,%s]+") do
		local lower = piece:lower()
		local number = tonumber(piece)
		if lower == "inf" or lower == "math.huge" then
			number = math.huge
		elseif lower == "-inf" or lower == "-math.huge" then
			number = -math.huge
		end
		if number == nil then
			return nil
		end
		table.insert(list, number)
	end
	return list
end

local function construct(name: string, ...): (boolean, any)
	local args = table.pack(...)
	return pcall(function()
		local library = (getfenv() :: any)[name]
		if library == nil then
			error(name .. " isn't available here", 0)
		end
		return library.new(table.unpack(args, 1, args.n))
	end)
end

-- Text a user edits for a value (inverse of Types.parse).
function Types.editText(value: any): string
	local customName, definition = customOf(value)
	if customName and definition.EditText then
		local ok, text = pcall(definition.EditText, value)
		if ok and text ~= nil then
			return tostring(text)
		end
	end
	local kind = typeof(value)
	if kind == "nil" then
		return "nil"
	elseif kind == "string" then
		return value
	elseif kind == "number" then
		return num(value)
	elseif kind == "boolean" then
		return tostring(value)
	elseif kind == "Vector2" or kind == "Vector2int16" then
		return ("%s, %s"):format(num(value.X), num(value.Y))
	elseif kind == "Vector3" or kind == "Vector3int16" then
		return ("%s, %s, %s"):format(num(value.X), num(value.Y), num(value.Z))
	elseif kind == "UDim" then
		return ("%s, %s"):format(num(value.Scale), num(value.Offset))
	elseif kind == "UDim2" then
		return ("%s, %s, %s, %s"):format(num(value.X.Scale), num(value.X.Offset), num(value.Y.Scale), num(value.Y.Offset))
	elseif kind == "Color3" then
		return ("%d, %d, %d"):format(math.floor(value.R * 255 + 0.5), math.floor(value.G * 255 + 0.5), math.floor(value.B * 255 + 0.5))
	elseif kind == "BrickColor" then
		return value.Name
	elseif kind == "CFrame" then
		local parts = { value:GetComponents() }
		local identity = parts[4] == 1 and parts[5] == 0 and parts[6] == 0 and parts[7] == 0 and parts[8] == 1 and parts[9] == 0
			and parts[10] == 0 and parts[11] == 0 and parts[12] == 1
		local count = if identity then 3 else 12
		local out = {}
		for index = 1, count do
			out[index] = num(parts[index])
		end
		return table.concat(out, ", ")
	elseif kind == "NumberRange" then
		return if value.Min == value.Max then num(value.Min) else ("%s, %s"):format(num(value.Min), num(value.Max))
	elseif kind == "Rect" then
		return ("%s, %s, %s, %s"):format(num(value.Min.X), num(value.Min.Y), num(value.Max.X), num(value.Max.Y))
	elseif kind == "EnumItem" then
		return value.Name
	elseif kind == "Instance" then
		return Types.path(value)
	elseif kind == "NumberSequence" then
		local points = value.Keypoints
		if #points == 2 and points[1].Value == points[2].Value and points[1].Envelope == 0 and points[2].Envelope == 0 then
			return num(points[1].Value)
		end
		local parts = {}
		for _, point in points do
			table.insert(parts, ("%s: %s"):format(num(point.Time), num(point.Value)) .. (if point.Envelope ~= 0 then " +- " .. num(point.Envelope) else ""))
		end
		return table.concat(parts, "; ")
	elseif kind == "ColorSequence" then
		local points = value.Keypoints
		if #points == 2 and points[1].Value == points[2].Value then
			return "#" .. points[1].Value:ToHex()
		end
		local parts = {}
		for _, point in points do
			table.insert(parts, ("%s: #%s"):format(num(point.Time), point.Value:ToHex()))
		end
		return table.concat(parts, "; ")
	elseif kind == "Faces" then
		local parts = {}
		for _, name in Types.FaceNames do
			if value[name] then
				table.insert(parts, name)
			end
		end
		return table.concat(parts, ", ")
	elseif kind == "Axes" then
		local parts = {}
		for _, name in { "X", "Y", "Z" } do
			if value[name] then
				table.insert(parts, name)
			end
		end
		return table.concat(parts, ", ")
	elseif kind == "Font" then
		return ("%s, %s, %s"):format(Types.fontFamilyName(value.Family), value.Weight.Name, value.Style.Name)
	elseif kind == "PhysicalProperties" then
		return ("%s, %s, %s, %s, %s"):format(num(value.Density), num(value.Friction), num(value.Elasticity), num(value.FrictionWeight), num(value.ElasticityWeight))
	elseif kind == "Ray" then
		local o, d = value.Origin, value.Direction
		return ("%s, %s, %s; %s, %s, %s"):format(num(o.X), num(o.Y), num(o.Z), num(d.X), num(d.Y), num(d.Z))
	elseif kind == "Content" then
		local source = value.SourceType
		if source == Enum.ContentSourceType.Uri then
			return value.Uri or ""
		elseif source == Enum.ContentSourceType.Object then
			return if value.Object then Types.path(value.Object) else ""
		end
		return ""
	elseif kind == "table" then
		return (Types.literal(value):gsub("\n%s*", " "))
	end
	return Types.short(value)
end

-- Finds an Instance from a path like game.Workspace["My Part"].Door,
-- workspace.Baseplate or game:GetService("Lighting"). Only walks
-- children; never runs code.
function Types.resolvePath(text: string): (Instance?, string?)
	local source = trimText(text)
	local position = 1
	local function skip()
		position = (source:find("[^%s]", position) or (#source + 1))
	end
	local function identifier(): string?
		skip()
		local name = source:match("^[%a_][%w_]*", position)
		if name then
			position += #name
		end
		return name
	end
	local function quoted(): string?
		skip()
		local quote = source:sub(position, position)
		if quote ~= '"' and quote ~= "'" then
			return nil
		end
		local out = {}
		local index = position + 1
		while index <= #source do
			local c = source:sub(index, index)
			if c == "\\" then
				table.insert(out, source:sub(index + 1, index + 1))
				index += 2
			elseif c == quote then
				position = index + 1
				return table.concat(out)
			else
				table.insert(out, c)
				index += 1
			end
		end
		return nil
	end

	local root = identifier()
	if not root then
		return nil, "a path starts with game or workspace"
	end
	local current: Instance
	if root == "game" then
		current = game
	elseif root == "workspace" then
		current = workspace
	else
		local ok, service = pcall(function()
			return game:GetService(root)
		end)
		if not ok or not service then
			return nil, ("\"%s\" is not game, workspace or a service"):format(root)
		end
		current = service
	end

	local function child(name: string): (Instance?, string?)
		local ok, found = pcall(function()
			return current:FindFirstChild(name)
		end)
		if ok and found then
			return found, nil
		end
		if current == game then
			local okService, service = pcall(function()
				return game:GetService(name)
			end)
			if okService and service then
				return service, nil
			end
		end
		return nil, ("%s has no child \"%s\""):format(Types.short(current), name)
	end

	while true do
		skip()
		if position > #source then
			return current, nil
		end
		local c = source:sub(position, position)
		local found, reason
		if c == "." then
			position += 1
			local name = identifier()
			if not name then
				return nil, "expected a name after ."
			end
			found, reason = child(name)
		elseif c == "[" then
			position += 1
			local name = quoted()
			skip()
			if not name or source:sub(position, position) ~= "]" then
				return nil, 'expected ["name"]'
			end
			position += 1
			found, reason = child(name)
		elseif c == ":" then
			position += 1
			local method = identifier()
			skip()
			if source:sub(position, position) ~= "(" then
				return nil, "expected ( after :" .. tostring(method)
			end
			position += 1
			local name = quoted()
			skip()
			if not name or source:sub(position, position) ~= ")" then
				return nil, 'expected ("name")'
			end
			position += 1
			if method == "GetService" or method == "FindFirstChild" or method == "WaitForChild" then
				found, reason = child(name)
			else
				return nil, ("only GetService and FindFirstChild work in a path, not %s"):format(tostring(method))
			end
		else
			return nil, ("unexpected \"%s\" in the path"):format(c)
		end
		if not found then
			return nil, reason
		end
		current = found
	end
end

local TRUE_WORDS = { ["true"] = true, yes = true, on = true, ["1"] = true }

-- Parsers for types that aren't a plain list of numbers. Filled in below
-- Types.parse (they use it for colors and paths).
local SPECIAL_PARSERS: { [string]: (string, any) -> (boolean, any) } = {}
local FALSE_WORDS = { ["false"] = true, no = true, off = true, ["0"] = true }

local function enumItem(enumName: string?, text: string): (boolean, any)
	local body = trimText(text):gsub("^Enum%.", "")
	local fromText, itemName = body:match("^([%a_][%w_]*)%.([%a_][%w_]*)$")
	enumName = fromText or enumName
	itemName = itemName or body
	if not enumName then
		return false, "say which enum, e.g. Material.Plastic"
	end
	local ok, items = pcall(function()
		return (Enum :: any)[enumName]:GetEnumItems()
	end)
	if not ok or type(items) ~= "table" then
		return false, ("no enum %s"):format(tostring(enumName))
	end
	local number = tonumber(itemName)
	for _, item in items do
		if item.Name:lower() == (itemName :: string):lower() or (number and item.Value == number) then
			return true, item
		end
	end
	return false, ("%s has no item \"%s\""):format(enumName, tostring(itemName))
end

local LITERAL_ENV_NAMES = {
	"Vector2", "Vector3", "Vector2int16", "Vector3int16", "CFrame", "Color3", "BrickColor", "UDim", "UDim2",
	"NumberRange", "NumberSequence", "ColorSequence", "Rect", "Enum", "math", "Font", "TweenInfo",
	"NumberSequenceKeypoint", "ColorSequenceKeypoint", "Faces", "Axes", "PhysicalProperties", "Ray", "Content",
}

-- A Luau table literal, evaluated with only datatype constructors visible.
local function tableLiteral(text: string): (boolean, any)
	local chunk, err = loadstring("return " .. text, "=value")
	if not chunk then
		return false, tostring(err)
	end
	local env = {}
	local base = getfenv()
	for _, name in LITERAL_ENV_NAMES do
		env[name] = (base :: any)[name]
	end
	if setfenv then
		setfenv(chunk, env)
	end
	local ok, result = pcall(chunk)
	if not ok then
		return false, tostring(result)
	end
	if type(result) ~= "table" then
		return false, "that is not a table"
	end
	return true, result
end

--[[
	Types.parse(text, typeName?, opts?) -> true, value | false, reason
	typeName: a typeof() name ("number", "Vector3", "Instance", "EnumItem",
	"table", ...) or nil / "any" for a best guess.
	opts.Enum: the enum's name for "EnumItem" (or write "Material.Plastic").
	"$name" gives a variable's value (when its type fits).
]]
function Types.parse(text: string, typeName: string?, opts: { [string]: any }?): (boolean, any)
	text = tostring(text or "")
	opts = opts or {}
	local trimmed = trimText(text)
	typeName = if typeName == nil or typeName == "" then "any" else typeName

	-- Variables work for every type.
	local varName = trimmed:match("^%$([%a_][%w_]*)$")
	if varName then
		local Variables = T.import("base/variables")
		local value, exists = Variables.get(varName)
		if not exists then
			return false, ("no variable $%s"):format(varName)
		end
		if typeName ~= "any" and not Types.isA(value, typeName :: string) then
			return false, ("$%s is %s, not %s"):format(varName, Types.tag(value), typeName)
		end
		return true, value
	end

	local kind = typeName :: string
	local definition = custom[kind]
	if definition then
		local ok, success, result = pcall(definition.Parse, text, opts)
		if not ok then
			return false, tostring(success)
		end
		if success then
			return true, result
		end
		return false, if result ~= nil then tostring(result) else ("can't read that as %s"):format(kind)
	end
	if kind == "any" then
		return Types.guess(trimmed)
	elseif kind == "string" then
		return true, text
	elseif kind == "nil" then
		if trimmed == "" or trimmed == "nil" then
			return true, nil
		end
		return false, "only nil fits here"
	elseif kind == "number" then
		local list = numbers(trimmed)
		if list and #list == 1 then
			return true, list[1]
		end
		return false, "type a number"
	elseif kind == "boolean" then
		local word = trimmed:lower()
		if TRUE_WORDS[word] then
			return true, true
		elseif FALSE_WORDS[word] then
			return true, false
		end
		return false, "type true or false"
	elseif kind == "EnumItem" then
		return enumItem(opts.Enum, trimmed)
	elseif kind == "Instance" then
		if trimmed == "nil" or trimmed == "" then
			return true, nil
		end
		local instance, reason = Types.resolvePath(trimmed)
		if not instance then
			return false, reason
		end
		return true, instance
	elseif kind == "table" then
		return tableLiteral(trimmed)
	elseif kind == "BrickColor" then
		local list = numbers(trimmed)
		local ok, value
		if list and #list == 1 then
			ok, value = construct("BrickColor", list[1])
		else
			ok, value = construct("BrickColor", (trimmed:gsub('^"(.*)"$', "%1")))
		end
		return ok, if ok then value else "not a BrickColor name or number"
	elseif kind == "Color3" then
		local hex = trimmed:match("^#?(%x%x%x%x%x%x)$")
		local r, g, b
		if hex then
			r, g, b = tonumber(hex:sub(1, 2), 16), tonumber(hex:sub(3, 4), 16), tonumber(hex:sub(5, 6), 16)
		else
			local list = numbers(trimmed)
			if not list or #list ~= 3 then
				return false, "type r, g, b (0-255) or #rrggbb"
			end
			-- "0.5, 0.2, 1" (with decimals, all ≤ 1) is 0-1; otherwise 0-255.
			local unit = trimmed:find("%.") ~= nil and list[1] <= 1 and list[2] <= 1 and list[3] <= 1
			if unit then
				r, g, b = list[1] * 255, list[2] * 255, list[3] * 255
			else
				r, g, b = list[1], list[2], list[3]
			end
		end
		for _, channel in { r, g, b } do
			if channel < 0 or channel > 255 then
				return false, "each channel is 0 to 255"
			end
		end
		local ok, value = pcall(function()
			return Color3.fromRGB(r, g, b)
		end)
		return ok, if ok then value else "could not make a Color3"
	end

	if SPECIAL_PARSERS[kind] then
		return SPECIAL_PARSERS[kind](trimmed, opts)
	end

	-- Number-list types.
	local list = numbers(trimmed)
	if not list then
		return false, ("can't read \"%s\" as %s"):format(trimmed, kind)
	end
	local count = #list
	local function need(...): boolean
		return table.find({ ... }, count) ~= nil
	end
	local ok, value
	if kind == "Vector2" or kind == "Vector2int16" then
		if not need(2) then
			return false, "type x, y"
		end
		ok, value = construct(kind, list[1], list[2])
	elseif kind == "Vector3" or kind == "Vector3int16" then
		if not need(3) then
			return false, "type x, y, z"
		end
		ok, value = construct(kind, list[1], list[2], list[3])
	elseif kind == "UDim" then
		if not need(2) then
			return false, "type scale, offset"
		end
		ok, value = construct("UDim", list[1], list[2])
	elseif kind == "UDim2" then
		if not need(4) then
			return false, "type xScale, xOffset, yScale, yOffset"
		end
		ok, value = construct("UDim2", list[1], list[2], list[3], list[4])
	elseif kind == "CFrame" then
		if count == 3 or count == 12 then
			ok, value = construct("CFrame", table.unpack(list))
		elseif count == 6 then
			ok, value = pcall(function()
				return CFrame.new(list[1], list[2], list[3]) * CFrame.Angles(math.rad(list[4]), math.rad(list[5]), math.rad(list[6]))
			end)
		else
			return false, "type x, y, z (or x, y, z, rx, ry, rz in degrees, or all 12 parts)"
		end
	elseif kind == "NumberRange" then
		if not need(1, 2) then
			return false, "type min, max"
		end
		ok, value = construct("NumberRange", list[1], list[2] or list[1])
	elseif kind == "Rect" then
		if not need(4) then
			return false, "type minX, minY, maxX, maxY"
		end
		ok, value = construct("Rect", list[1], list[2], list[3], list[4])
	else
		return false, ("editing %s values isn't supported"):format(kind)
	end
	if not ok then
		return false, tostring(value)
	end
	return true, value
end

----------------------------------------------------------------------
-- Parsers for the remaining types
----------------------------------------------------------------------

local function enumByName(enumName: string, name: string): EnumItem?
	local ok, items = pcall(function()
		return (Enum :: any)[enumName]:GetEnumItems()
	end)
	if not ok then
		return nil
	end
	local lower = name:lower()
	for _, item in items do
		if item.Name:lower() == lower then
			return item
		end
	end
	return nil
end

-- "0: 1; 0.5: 2 +- 0.1; 1: 0" -> { { Time, Text, Envelope } }
local function keypointList(text: string): ({ any }?, string?)
	local points = {}
	for piece in text:gmatch("[^;]+") do
		local body = trimText(piece)
		if body ~= "" then
			local time, rest = body:match("^([%-%d%.eE]+)%s*[:=]%s*(.+)$")
			if not time then
				return nil, ("\"%s\" isn't time: value"):format(body)
			end
			local value, envelope = rest, nil
			local before, after = rest:match("^(.-)%s*%+%-%s*(.+)$")
			if not before then
				before, after = rest:match("^(.-)%s*±%s*(.+)$")
			end
			if before then
				value, envelope = before, tonumber(after)
				if envelope == nil then
					return nil, ("\"%s\" isn't an envelope"):format(after)
				end
			end
			table.insert(points, { Time = tonumber(time), Text = trimText(value), Envelope = envelope or 0 })
		end
	end
	if #points < 2 then
		return nil, "a sequence needs keypoints at time 0 and time 1"
	end
	table.sort(points, function(a, b)
		return a.Time < b.Time
	end)
	if points[1].Time ~= 0 or points[#points].Time ~= 1 then
		return nil, "the first keypoint is at time 0 and the last at time 1"
	end
	return points, nil
end

SPECIAL_PARSERS.NumberSequence = function(text)
	local single = tonumber(text)
	if single then
		return construct("NumberSequence", single)
	end
	-- Studio's form: "time value envelope time value envelope …"
	if not text:find("[:;=]") then
		local list = numbers(text)
		if list and #list >= 6 and #list % 3 == 0 then
			local points = {}
			for index = 1, #list, 3 do
				table.insert(points, { Time = list[index], Text = tostring(list[index + 1]), Envelope = list[index + 2] })
			end
			text = ""
			for index, point in points do
				text ..= (if index > 1 then "; " else "") .. ("%s: %s +- %s"):format(point.Time, point.Text, point.Envelope)
			end
		end
	end
	local points, problem = keypointList(text)
	if not points then
		return false, problem
	end
	local keys = {}
	for _, point in points do
		local value = tonumber(point.Text)
		if value == nil then
			return false, ("\"%s\" isn't a number"):format(point.Text)
		end
		local ok, key = pcall(function()
			return NumberSequenceKeypoint.new(point.Time, value, point.Envelope)
		end)
		if not ok then
			return false, tostring(key)
		end
		table.insert(keys, key)
	end
	local ok, value = construct("NumberSequence", keys)
	return ok, if ok then value else tostring(value)
end

SPECIAL_PARSERS.ColorSequence = function(text)
	if not text:find("[:;]") then
		local ok, color = Types.parse(text, "Color3")
		if not ok then
			return false, color
		end
		return construct("ColorSequence", color)
	end
	local points, problem = keypointList(text)
	if not points then
		return false, problem
	end
	local keys = {}
	for _, point in points do
		local okColor, color = Types.parse(point.Text, "Color3")
		if not okColor then
			return false, ("%s: %s"):format(point.Text, tostring(color))
		end
		local ok, key = pcall(function()
			return ColorSequenceKeypoint.new(point.Time, color)
		end)
		if not ok then
			return false, tostring(key)
		end
		table.insert(keys, key)
	end
	local ok, value = construct("ColorSequence", keys)
	return ok, if ok then value else tostring(value)
end

local function nameList(text: string): { string }
	local names = {}
	for word in text:gmatch("[%a]+") do
		if word:lower() ~= "enum" and word:lower() ~= "normalid" and word:lower() ~= "axis" then
			table.insert(names, word)
		end
	end
	return names
end

SPECIAL_PARSERS.Faces = function(text)
	local items = {}
	if text:lower() ~= "none" then
		for _, word in nameList(text) do
			local item = enumByName("NormalId", word)
			if not item then
				return false, ("\"%s\" isn't a face (Right, Top, Back, Left, Bottom, Front)"):format(word)
			end
			table.insert(items, item)
		end
	end
	return construct("Faces", table.unpack(items))
end

SPECIAL_PARSERS.Axes = function(text)
	local items = {}
	if text:lower() ~= "none" then
		for _, word in nameList(text) do
			local item = enumByName("Axis", word) or enumByName("NormalId", word)
			if not item then
				return false, ("\"%s\" isn't an axis (X, Y, Z)"):format(word)
			end
			table.insert(items, item)
		end
	end
	return construct("Axes", table.unpack(items))
end

SPECIAL_PARSERS.Font = function(text)
	local parts = {}
	for piece in text:gmatch("[^,]+") do
		table.insert(parts, trimText(piece))
	end
	local family = parts[1]
	if not family or family == "" then
		return false, "type a font family, e.g. SourceSansPro"
	end
	family = family:gsub('^"(.*)"$', "%1")
	if tonumber(family) then
		family = "rbxassetid://" .. family
	elseif not family:find("://") then
		family = ("rbxasset://fonts/families/%s.json"):format(family)
	end
	local weight, style = Enum.FontWeight.Regular, Enum.FontStyle.Normal
	if parts[2] and parts[2] ~= "" then
		local item = enumByName("FontWeight", (parts[2]:gsub("^Enum%.FontWeight%.", "")))
		if not item then
			return false, ("\"%s\" isn't a weight (Thin … Heavy, e.g. Bold)"):format(parts[2])
		end
		weight = item
	end
	if parts[3] and parts[3] ~= "" then
		local item = enumByName("FontStyle", (parts[3]:gsub("^Enum%.FontStyle%.", "")))
		if not item then
			return false, ("\"%s\" isn't a style (Normal or Italic)"):format(parts[3])
		end
		style = item
	end
	return construct("Font", family, weight, style)
end

SPECIAL_PARSERS.PhysicalProperties = function(text)
	local lower = text:lower()
	if lower == "nil" or lower == "" or lower == "default" then
		return true, nil
	end
	local list = numbers(text)
	if list and (#list == 3 or #list == 5) then
		return construct("PhysicalProperties", table.unpack(list))
	end
	local material = enumByName("Material", (text:gsub("^Enum%.Material%.", "")))
	if material then
		return construct("PhysicalProperties", material)
	end
	return false, "type density, friction, elasticity (and frictionWeight, elasticityWeight), or a material"
end

SPECIAL_PARSERS.Ray = function(text)
	local list = numbers((text:gsub(";", ",")))
	if not list or #list ~= 6 then
		return false, "type origin x, y, z; direction x, y, z"
	end
	local ok, value = pcall(function()
		return Ray.new(Vector3.new(list[1], list[2], list[3]), Vector3.new(list[4], list[5], list[6]))
	end)
	return ok, if ok then value else tostring(value)
end

SPECIAL_PARSERS.Content = function(text)
	local ok, value = pcall(function()
		local lower = text:lower()
		if text == "" or lower == "none" or lower == "nil" then
			return Content.none
		end
		if tonumber(text) then
			return Content.fromUri("rbxassetid://" .. text)
		end
		if text:match("^game[%.:%[]") or text:match("^workspace[%.:%[]") then
			local object, reason = Types.resolvePath(text)
			if not object then
				error(reason, 0)
			end
			return Content.fromObject(object)
		end
		return Content.fromUri(text)
	end)
	return ok, if ok then value else tostring(value)
end

-- Best guess for untyped text.
function Types.guess(text: string): (boolean, any)
	local trimmed = trimText(text)
	local lower = trimmed:lower()
	if trimmed == "" or lower == "nil" then
		return true, nil
	elseif lower == "true" or lower == "false" then
		return true, lower == "true"
	end
	local number = tonumber(trimmed)
	if number then
		return true, number
	end
	local quoted = trimmed:match('^"(.*)"$') or trimmed:match("^'(.*)'$")
	if quoted then
		return true, quoted
	end
	if trimmed:match("^#%x%x%x%x%x%x$") then
		return Types.parse(trimmed, "Color3")
	end
	if trimmed:match("^game[%.:%[]") or trimmed:match("^workspace[%.:%[]") or trimmed == "workspace" or trimmed == "game" then
		local instance = Types.resolvePath(trimmed)
		if instance then
			return true, instance
		end
	end
	if trimmed:match("^Enum%.[%a_][%w_]*%.[%a_][%w_]*$") then
		local ok, item = enumItem(nil, trimmed)
		if ok then
			return true, item
		end
	end
	if trimmed:sub(1, 1) == "{" then
		local ok, value = tableLiteral(trimmed)
		if ok then
			return true, value
		end
	end
	local list = numbers(trimmed)
	if list and trimmed:find(",") then
		if #list == 2 then
			return Types.parse(trimmed, "Vector2")
		elseif #list == 3 then
			return Types.parse(trimmed, "Vector3")
		end
	end
	return true, text
end

-- A starting value for a type (when a type picker changes an entry's type).
function Types.default(typeName: string): any
	local definition = custom[typeName]
	if definition then
		if definition.Default then
			local ok, value = pcall(definition.Default)
			return if ok then value else nil
		end
		return nil
	end
	local makers = {
		number = function() return 0 end,
		string = function() return "" end,
		boolean = function() return false end,
		table = function() return {} end,
		Vector2 = function() return Vector2.new(0, 0) end,
		Vector3 = function() return Vector3.new(0, 0, 0) end,
		Vector2int16 = function() return Vector2int16.new(0, 0) end,
		Vector3int16 = function() return Vector3int16.new(0, 0, 0) end,
		UDim = function() return UDim.new(0, 0) end,
		UDim2 = function() return UDim2.new(0, 0, 0, 0) end,
		Color3 = function() return Color3.fromRGB(255, 255, 255) end,
		BrickColor = function() return BrickColor.new("Medium stone grey") end,
		CFrame = function() return CFrame.new() end,
		NumberRange = function() return NumberRange.new(0, 0) end,
		Rect = function() return Rect.new(0, 0, 0, 0) end,
		NumberSequence = function() return NumberSequence.new(0) end,
		ColorSequence = function() return ColorSequence.new(Color3.new(1, 1, 1)) end,
		Faces = function() return Faces.new() end,
		Axes = function() return Axes.new() end,
		Font = function() return Font.new("rbxasset://fonts/families/SourceSansPro.json") end,
		PhysicalProperties = function() return PhysicalProperties.new(Enum.Material.Plastic) end,
		Ray = function() return Ray.new(Vector3.new(0, 0, 0), Vector3.new(0, 0, -1)) end,
		Content = function() return Content.none end,
	}
	local maker = makers[typeName]
	if not maker then
		return nil
	end
	local ok, value = pcall(maker)
	return if ok then value else nil
end

-- Converts a value to another type through its text form. Values that
-- already fit are returned as they are.
function Types.convert(value: any, typeName: string, opts: { [string]: any }?): (boolean, any)
	if value ~= nil and Types.isA(value, typeName) then
		return true, value
	end
	if typeName == "string" then
		return true, if typeof(value) == "Instance" then Types.path(value) else Types.editText(value)
	end
	return Types.parse(Types.editText(value), typeName, opts)
end

-- Type picker kind that fits a value (used when editing list entries).
function Types.pickerKind(value: any): string
	local class = Types.classOf(value)
	if class then
		local base = Types.baseOf(value)
		return "isa:" .. (base or "Instance")
	end
	if typeof(value) == "EnumItem" then
		return "enum:" .. tostring(value.EnumType):gsub("^Enum%.", "")
	end
	return "valueType"
end

T.Bin:Add(function()
	table.clear(custom)
	table.clear(customOrder)
end)

return Types
