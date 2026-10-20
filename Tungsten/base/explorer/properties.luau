--[[
	Tungsten · base/explorer/properties
	The data behind the properties panel (no UI here): which properties a
	selection shares, their values, writing them, attributes and tags.

		Properties.collect(instances, opts) -> entries
			opts.ShowDeprecated, opts.ShowHidden, opts.Filter (text in the name)
			entry: { Name, Prop, Category, Value, Same, Readable, Reason }
			With several objects only the properties all of them have are
			listed; Same is false when their values differ (the first
			Properties.MaxCompare objects are compared).
		Properties.set(instances, prop, value)      -> changed, failures
		Properties.setField(instances, prop, field, fieldValue)
		Properties.display(value, prop)             -> text for the panel
		Properties.fields(prop)                     -> sub-rows of a value (X, Y, Z …)
		Properties.attributes(instances)            -> { { Name, Value, Same, Type } }
		Properties.setAttribute / renameAttribute / removeAttribute
		Properties.tags(instances)                  -> tag names all of them have

	A failure is { Instance, Reason }.
]]

local T = ...
local Api = T.import("base/explorer/api")
local Types = T.import("base/types")
local Settings = T.import("base/settings")
local Undo = T.import("base/undo")

local Properties = {}
Properties.MaxCompare = 50

----------------------------------------------------------------------
-- Values
----------------------------------------------------------------------

function Properties.equal(a: any, b: any): boolean
	if rawequal(a, b) then
		return true
	end
	if typeof(a) ~= typeof(b) then
		return false
	end
	if type(a) == "table" or type(a) == "function" or type(a) == "thread" then
		return false
	end
	local ok, same = pcall(function()
		return a == b
	end)
	return ok and same == true
end

function Properties.read(instance: Instance, prop: any): (boolean, any)
	return Api.read(instance, prop.Name, prop)
end

local function round(number: number, decimals: number): string
	if number ~= number then
		return "NaN"
	elseif number == math.huge then
		return "inf"
	elseif number == -math.huge then
		return "-inf"
	end
	local text = ("%." .. decimals .. "f"):format(number)
	if text:find("%.") then
		text = text:gsub("0+$", ""):gsub("%.$", "")
	end
	if text == "-0" then
		text = "0"
	end
	return text
end
Properties.round = round

function Properties.decimals(): number
	local value = Settings.get("PropertyDecimals")
	return if type(value) == "number" then value else 3
end

-- Text a value shows in the panel (numbers rounded to the setting).
function Properties.display(value: any, prop: any?): string
	local decimals = Properties.decimals()
	local kind = typeof(value)
	if value == nil then
		return ""
	elseif kind == "number" then
		if prop and prop.Integer then
			return ("%d"):format(value)
		end
		return round(value, decimals)
	elseif kind == "string" then
		return (value:gsub("[\r\n\t]", " "))
	elseif kind == "boolean" then
		return tostring(value)
	elseif kind == "EnumItem" then
		return value.Name
	elseif kind == "Instance" then
		local ok, name = pcall(function()
			return value.Name
		end)
		return if ok then tostring(name) else "<locked>"
	elseif kind == "BrickColor" then
		return value.Name
	elseif kind == "CFrame" then
		local position = value.Position
		return ("%s, %s, %s"):format(round(position.X, decimals), round(position.Y, decimals), round(position.Z, decimals))
	elseif kind == "Font" then
		return ("%s · %s%s"):format(Types.fontFamilyName(value.Family), value.Weight.Name, if value.Style.Name ~= "Normal" then " " .. value.Style.Name else "")
	end
	local text = Types.editText(value)
	return (text:gsub("%-?%d+%.%d+", function(number)
		return round(tonumber(number) :: number, decimals)
	end))
end

----------------------------------------------------------------------
-- Sub-rows of composite values
----------------------------------------------------------------------

local function make(name: string, ...): any
	return ((getfenv() :: any)[name]).new(...)
end

local function vectorFields(kind: string, axes: { string }, integer: boolean)
	local list = {}
	for index, axis in axes do
		table.insert(list, {
			Name = axis,
			Type = "number",
			Integer = integer,
			Get = function(v)
				return v[axis]
			end,
			Set = function(v, x)
				local parts = {}
				for i, a in axes do
					parts[i] = if i == index then x else v[a]
				end
				return make(kind, table.unpack(parts))
			end,
		})
	end
	return list
end

local FIELDS = {}
FIELDS.Vector2 = vectorFields("Vector2", { "X", "Y" }, false)
FIELDS.Vector3 = vectorFields("Vector3", { "X", "Y", "Z" }, false)
FIELDS.Vector2int16 = vectorFields("Vector2int16", { "X", "Y" }, true)
FIELDS.Vector3int16 = vectorFields("Vector3int16", { "X", "Y", "Z" }, true)
FIELDS.UDim = {
	{ Name = "Scale", Type = "number", Get = function(v) return v.Scale end, Set = function(v, x) return UDim.new(x, v.Offset) end },
	{ Name = "Offset", Type = "number", Integer = true, Get = function(v) return v.Offset end, Set = function(v, x) return UDim.new(v.Scale, x) end },
}
FIELDS.UDim2 = {
	{ Name = "X Scale", Type = "number", Get = function(v) return v.X.Scale end, Set = function(v, x) return UDim2.new(x, v.X.Offset, v.Y.Scale, v.Y.Offset) end },
	{ Name = "X Offset", Type = "number", Integer = true, Get = function(v) return v.X.Offset end, Set = function(v, x) return UDim2.new(v.X.Scale, x, v.Y.Scale, v.Y.Offset) end },
	{ Name = "Y Scale", Type = "number", Get = function(v) return v.Y.Scale end, Set = function(v, x) return UDim2.new(v.X.Scale, v.X.Offset, x, v.Y.Offset) end },
	{ Name = "Y Offset", Type = "number", Integer = true, Get = function(v) return v.Y.Offset end, Set = function(v, x) return UDim2.new(v.X.Scale, v.X.Offset, v.Y.Scale, x) end },
}
FIELDS.Rect = {
	{ Name = "Min X", Type = "number", Get = function(v) return v.Min.X end, Set = function(v, x) return Rect.new(x, v.Min.Y, v.Max.X, v.Max.Y) end },
	{ Name = "Min Y", Type = "number", Get = function(v) return v.Min.Y end, Set = function(v, x) return Rect.new(v.Min.X, x, v.Max.X, v.Max.Y) end },
	{ Name = "Max X", Type = "number", Get = function(v) return v.Max.X end, Set = function(v, x) return Rect.new(v.Min.X, v.Min.Y, x, v.Max.Y) end },
	{ Name = "Max Y", Type = "number", Get = function(v) return v.Max.Y end, Set = function(v, x) return Rect.new(v.Min.X, v.Min.Y, v.Max.X, x) end },
}
FIELDS.NumberRange = {
	{ Name = "Min", Type = "number", Get = function(v) return v.Min end, Set = function(v, x) return NumberRange.new(x, math.max(x, v.Max)) end },
	{ Name = "Max", Type = "number", Get = function(v) return v.Max end, Set = function(v, x) return NumberRange.new(math.min(x, v.Min), x) end },
}
-- Position and Orientation, the way Studio shows a CFrame. Orientation
-- comes from ToOrientation (never from the look direction alone, which
-- loses the roll).
FIELDS.CFrame = {
	{
		Name = "Position",
		Type = "Vector3",
		Get = function(v)
			return (Types.cframeParts(v))
		end,
		Set = function(v, x)
			local _, orientation = Types.cframeParts(v)
			return v.Rotation + x
		end,
	},
	{
		Name = "Orientation",
		Type = "Vector3",
		Get = function(v)
			local _, orientation = Types.cframeParts(v)
			return orientation
		end,
		Set = function(v, x)
			return Types.cframeFrom(v.Position, x)
		end,
	},
}
FIELDS.PhysicalProperties = {}
for _, name in { "Density", "Friction", "Elasticity", "FrictionWeight", "ElasticityWeight" } do
	table.insert(FIELDS.PhysicalProperties, {
		Name = name,
		Type = "number",
		Get = function(v)
			return v[name]
		end,
		Set = function(v, x)
			local parts = { v.Density, v.Friction, v.Elasticity, v.FrictionWeight, v.ElasticityWeight }
			local order = { Density = 1, Friction = 2, Elasticity = 3, FrictionWeight = 4, ElasticityWeight = 5 }
			parts[order[name]] = x
			return PhysicalProperties.new(table.unpack(parts))
		end,
	})
end
FIELDS.Ray = {
	{ Name = "Origin", Type = "Vector3", Get = function(v) return v.Origin end, Set = function(v, x) return Ray.new(x, v.Direction) end },
	{ Name = "Direction", Type = "Vector3", Get = function(v) return v.Direction end, Set = function(v, x) return Ray.new(v.Origin, x) end },
}
FIELDS.Font = {
	{
		Name = "Family",
		Type = "string",
		Get = function(v)
			return Types.fontFamilyName(v.Family)
		end,
		Set = function(v, x)
			local ok, font = Types.parse(("%s, %s, %s"):format(x, v.Weight.Name, v.Style.Name), "Font")
			if not ok then
				error(font, 0)
			end
			return font
		end,
	},
	{ Name = "Weight", Type = "EnumItem", Enum = "FontWeight", Get = function(v) return v.Weight end, Set = function(v, x) return Font.new(v.Family, x, v.Style) end },
	{ Name = "Style", Type = "EnumItem", Enum = "FontStyle", Get = function(v) return v.Style end, Set = function(v, x) return Font.new(v.Family, v.Weight, x) end },
}
FIELDS.Faces = {}
for _, face in Types.FaceNames do
	table.insert(FIELDS.Faces, {
		Name = face,
		Type = "boolean",
		Get = function(v)
			return v[face]
		end,
		Set = function(v, x)
			local items = {}
			for _, name in Types.FaceNames do
				if (name == face and x) or (name ~= face and v[name]) then
					table.insert(items, (Enum.NormalId :: any)[name])
				end
			end
			return Faces.new(table.unpack(items))
		end,
	})
end
FIELDS.Axes = {}
for _, axis in { "X", "Y", "Z" } do
	table.insert(FIELDS.Axes, {
		Name = axis,
		Type = "boolean",
		Get = function(v)
			return v[axis]
		end,
		Set = function(v, x)
			local items = {}
			for _, name in { "X", "Y", "Z" } do
				if (name == axis and x) or (name ~= axis and v[name]) then
					table.insert(items, (Enum.Axis :: any)[name])
				end
			end
			return Axes.new(table.unpack(items))
		end,
	})
end
Properties.Fields = FIELDS

-- Sub-rows for a property (or a type name), or nil.
function Properties.fields(prop: any): { any }?
	local typeName = if type(prop) == "table" then prop.Type else prop
	local Editors = T.import("base/explorer/editors")
	local custom = Editors.fieldsFor(prop)
	if custom then
		return custom
	end
	return FIELDS[typeName]
end

----------------------------------------------------------------------
-- Collecting
----------------------------------------------------------------------

local function visible(prop, opts): boolean
	if prop.Deprecated and not opts.ShowDeprecated then
		return false
	end
	if (prop.Hidden or prop.NotScriptable) and not opts.ShowHidden then
		return false
	end
	if prop.WriteOnly then
		return false
	end
	local filter = opts.Filter
	if filter and filter ~= "" then
		local lower = filter:lower()
		if not prop.Name:lower():find(lower, 1, true) and not prop.Category:lower():find(lower, 1, true) then
			return false
		end
	end
	return true
end

-- Properties every instance has (same name and type), by the data.
function Properties.shared(instances: { Instance }): { any }
	if #instances == 0 then
		return {}
	end
	local classes = {}
	local seen = {}
	for _, instance in instances do
		local class = Api.knownClass(instance)
		if not seen[class] then
			seen[class] = true
			table.insert(classes, class)
		end
	end
	local list = Api.properties(classes[1])
	if #classes == 1 then
		return list
	end
	local result = {}
	for _, prop in list do
		local everywhere = true
		for index = 2, #classes do
			local other = Api.property(classes[index], prop.Name)
			if not other or other.Type ~= prop.Type then
				everywhere = false
				break
			end
		end
		if everywhere then
			table.insert(result, prop)
		end
	end
	return result
end

local function compared(instances: { Instance }): { Instance }
	if #instances <= Properties.MaxCompare then
		return instances
	end
	return table.move(instances, 1, Properties.MaxCompare, 1, {})
end
Properties.compared = compared

-- Reads one property from the compared instances.
function Properties.entry(instances: { Instance }, prop: any)
	local entry = { Name = prop.Name, Prop = prop, Category = prop.Category, Same = true, Readable = false }
	local first = true
	for _, instance in compared(instances) do
		local ok, value = Properties.read(instance, prop)
		if ok then
			if not entry.Readable then
				entry.Readable = true
				entry.Value = value
			elseif not Properties.equal(entry.Value, value) then
				entry.Same = false
			end
		elseif first then
			entry.Reason = tostring(value)
		end
		first = false
	end
	if not entry.Readable then
		entry.Same = true
	end
	return entry
end

function Properties.collect(instances: { Instance }, opts: { [string]: any }?): { any }
	opts = opts or {}
	local entries = {}
	if #instances == 0 then
		return entries
	end
	for _, prop in Properties.shared(instances) do
		if visible(prop, opts) then
			local entry = Properties.entry(instances, prop)
			if entry.Readable or opts.ShowHidden then
				table.insert(entries, entry)
			end
		end
	end
	-- Properties newer than the bundled data (one object, hidden ones shown).
	if (opts :: any).ShowHidden and #instances == 1 then
		for name, value in Api.extraProperties(instances[1]) do
			local prop = {
				Name = name,
				Class = "?",
				Category = "Other",
				Type = Types.typeName(value),
				DataType = Types.typeName(value),
				NotScriptable = true,
				Hidden = true,
				Unknown = true,
				Security = "None",
			}
			prop.Editable = Api.EditableTypes[prop.Type] == true
			if prop.Type == "EnumItem" then
				prop.Enum = (tostring(value.EnumType):gsub("^Enum%.", ""))
			end
			if visible(prop, opts) then
				table.insert(entries, { Name = name, Prop = prop, Category = "Other", Value = value, Same = true, Readable = true })
			end
		end
	end
	table.sort(entries, function(a, b)
		if a.Category ~= b.Category then
			local ra, rb = Api.categoryRank(a.Category), Api.categoryRank(b.Category)
			if ra ~= rb then
				return ra < rb
			end
			return a.Category < b.Category
		end
		return a.Name:lower() < b.Name:lower()
	end)
	return entries
end

-- A property by name for these instances (nil: not shared).
function Properties.find(instances: { Instance }, name: string)
	local lower = name:lower()
	for _, prop in Properties.shared(instances) do
		if prop.Name:lower() == lower then
			return prop
		end
	end
	return nil
end

----------------------------------------------------------------------
-- Writing
----------------------------------------------------------------------

local function checkValue(prop, value): (boolean, string?)
	if prop.ReadOnly then
		return false, prop.Name .. " is read only"
	end
	if prop.Integer and type(value) == "number" and value ~= math.floor(value) then
		return false, prop.Name .. " takes whole numbers"
	end
	return true, nil
end


----------------------------------------------------------------------
-- Undo (base/undo): every change below is recorded so /undo can put the
-- old values back.
----------------------------------------------------------------------

local undoIds = setmetatable({}, { __mode = "k" })
local nextUndoId = 0
-- The same objects give the same key (edits in one popup fold together).
function Properties.undoKey(kind: string, name: string, instances: { Instance }): string
	local ids = {}
	for _, instance in instances do
		local id = undoIds[instance]
		if not id then
			nextUndoId += 1
			id = nextUndoId
			undoIds[instance] = id
		end
		table.insert(ids, id)
	end
	table.sort(ids)
	return ("%s:%s:%s"):format(kind, name, table.concat(ids, ","))
end

local function recordProperty(instances: { Instance }, prop: any, saved: { any })
	if #saved == 0 then
		return
	end
	local changed = {}
	for _, item in saved do
		table.insert(changed, item[1])
	end
	Undo.record({
		Text = ("set %s on %s"):format(prop.Name, Undo.describe(changed)),
		Merge = Properties.undoKey("prop", prop.Name, instances),
		Undo = function()
			local problem = nil
			for _, item in saved do
				local ok, reason = Api.write(item[1], prop.Name, item[2], prop)
				if not ok then
					problem = reason
				end
			end
			if problem then
				error(problem, 0)
			end
		end,
	})
end

local function recordAttributes(instances: { Instance }, label: string, mergeName: string, saved: { any })
	if #saved == 0 then
		return
	end
	Undo.record({
		Text = label,
		Merge = Properties.undoKey("attr", mergeName, instances),
		Undo = function()
			local problem = nil
			for _, item in saved do
				local ok, err = pcall(item[1], item[2])
				if not ok then
					problem = err
				end
			end
			if problem then
				error(problem, 0)
			end
		end,
	})
end

function Properties.set(instances: { Instance }, prop: any, value: any): (number, { any })
	local failures = {}
	local okValue, problem = checkValue(prop, value)
	if not okValue then
		return 0, { { Reason = problem } }
	end
	local changed = 0
	local saved = {}
	for _, instance in instances do
		local okOld, old = Properties.read(instance, prop)
		local ok, reason = Api.write(instance, prop.Name, value, prop)
		if ok then
			changed += 1
			if okOld then
				table.insert(saved, { instance, old })
			end
		else
			table.insert(failures, { Instance = instance, Reason = reason })
		end
	end
	recordProperty(instances, prop, saved)
	return changed, failures
end

-- Changes one part of a composite value (X of a Vector3, …) on every
-- instance, keeping each one's other parts.
function Properties.setField(instances: { Instance }, prop: any, field: any, fieldValue: any): (number, { any })
	if prop.ReadOnly then
		return 0, { { Reason = prop.Name .. " is read only" } }
	end
	if field.Integer and type(fieldValue) == "number" and fieldValue ~= math.floor(fieldValue) then
		return 0, { { Reason = field.Name .. " takes whole numbers" } }
	end
	local changed, failures = 0, {}
	local saved = {}
	for _, instance in instances do
		local okRead, current = Properties.read(instance, prop)
		if not okRead then
			table.insert(failures, { Instance = instance, Reason = tostring(current) })
		else
			local okMake, newValue = pcall(field.Set, current, fieldValue)
			if not okMake then
				table.insert(failures, { Instance = instance, Reason = (tostring(newValue):gsub("^.-:%d+: ", "")) })
			else
				local ok, reason = Api.write(instance, prop.Name, newValue, prop)
				if ok then
					changed += 1
					table.insert(saved, { instance, current })
				else
					table.insert(failures, { Instance = instance, Reason = reason })
				end
			end
		end
	end
	recordProperty(instances, prop, saved)
	return changed, failures
end

-- The field's value on the compared instances: value, same.
function Properties.fieldValue(instances: { Instance }, prop: any, field: any): (any, boolean)
	local value, have, same = nil, false, true
	for _, instance in compared(instances) do
		local ok, current = Properties.read(instance, prop)
		if ok and current ~= nil then
			local okGet, part = pcall(field.Get, current)
			if okGet then
				if not have then
					value, have = part, true
				elseif not Properties.equal(value, part) then
					same = false
				end
			end
		end
	end
	return value, same
end

----------------------------------------------------------------------
-- Attributes and tags
----------------------------------------------------------------------

-- Attributes all instances have: { Name, Value, Same, Type }.
function Properties.attributes(instances: { Instance }): { any }
	local list = compared(instances)
	if #list == 0 then
		return {}
	end
	local okFirst, first = pcall(function()
		return list[1]:GetAttributes()
	end)
	if not okFirst or type(first) ~= "table" then
		return {}
	end
	local result = {}
	for name, value in first do
		local entry = { Name = name, Value = value, Same = true, Type = Types.typeName(value) }
		local everywhere = true
		for index = 2, #list do
			local ok, other = pcall(function()
				return list[index]:GetAttribute(name)
			end)
			if not ok or other == nil then
				everywhere = false
				break
			end
			if not Properties.equal(value, other) then
				entry.Same = false
			end
		end
		if everywhere then
			table.insert(result, entry)
		end
	end
	table.sort(result, function(a, b)
		return a.Name:lower() < b.Name:lower()
	end)
	return result
end

-- Roblox's rules for attribute names.
function Properties.validAttributeName(name: string): (boolean, string?)
	if type(name) ~= "string" or name == "" then
		return false, "an attribute needs a name"
	elseif #name > 100 then
		return false, "attribute names are at most 100 characters"
	elseif not name:match("^[%w_]+$") then
		return false, "attribute names use letters, digits and _ only"
	elseif name:sub(1, 3) == "RBX" then
		return false, "attribute names can't start with RBX"
	end
	return true, nil
end

function Properties.setAttribute(instances: { Instance }, name: string, value: any): (number, { any })
	local okName, problem = Properties.validAttributeName(name)
	if not okName then
		return 0, { { Reason = problem } }
	end
	local changed, failures = 0, {}
	local saved = {}
	for _, instance in instances do
		local okOld, old = pcall(function()
			return instance:GetAttribute(name)
		end)
		local ok, err = pcall(function()
			instance:SetAttribute(name, value)
		end)
		if ok then
			changed += 1
			if okOld then
				table.insert(saved, {
					function(previous)
						instance:SetAttribute(name, previous)
					end,
					old,
				})
			end
		else
			table.insert(failures, { Instance = instance, Reason = (tostring(err):gsub("^.-:%d+: ", "")) })
		end
	end
	recordAttributes(instances, ("set @%s on %s"):format(name, Undo.describe(instances)), name, saved)
	return changed, failures
end

function Properties.removeAttribute(instances: { Instance }, name: string): (number, { any })
	local changed, failures = 0, {}
	local saved = {}
	for _, instance in instances do
		local okOld, old = pcall(function()
			return instance:GetAttribute(name)
		end)
		local ok, err = pcall(function()
			instance:SetAttribute(name, nil)
		end)
		if ok then
			changed += 1
			if okOld and old ~= nil then
				table.insert(saved, {
					function(previous)
						instance:SetAttribute(name, previous)
					end,
					old,
				})
			end
		else
			table.insert(failures, { Instance = instance, Reason = tostring(err) })
		end
	end
	recordAttributes(instances, ("remove @%s from %s"):format(name, Undo.describe(instances)), "remove:" .. name, saved)
	return changed, failures
end

-- Renames an attribute, keeping each instance's own value.
function Properties.renameAttribute(instances: { Instance }, old: string, new: string): (number, { any })
	local okName, problem = Properties.validAttributeName(new)
	if not okName then
		return 0, { { Reason = problem } }
	end
	if old == new then
		return 0, {}
	end
	local changed, failures = 0, {}
	local saved = {}
	for _, instance in instances do
		local ok, err = pcall(function()
			local value = instance:GetAttribute(old)
			if instance:GetAttribute(new) ~= nil then
				error(("it already has an attribute %s"):format(new), 0)
			end
			instance:SetAttribute(new, value)
			instance:SetAttribute(old, nil)
			table.insert(saved, {
				function(previous)
					instance:SetAttribute(old, previous)
					instance:SetAttribute(new, nil)
				end,
				value,
			})
		end)
		if ok then
			changed += 1
		else
			table.insert(failures, { Instance = instance, Reason = (tostring(err):gsub("^.-:%d+: ", "")) })
		end
	end
	recordAttributes(instances, ("rename @%s to @%s"):format(old, new), "rename:" .. old, saved)
	return changed, failures
end

-- Tags all instances have.
function Properties.tags(instances: { Instance }): { string }
	local list = compared(instances)
	if #list == 0 then
		return {}
	end
	local ok, first = pcall(function()
		return list[1]:GetTags()
	end)
	if not ok or type(first) ~= "table" then
		return {}
	end
	local result = {}
	for _, tag in first do
		local everywhere = true
		for index = 2, #list do
			local okHas, has = pcall(function()
				return list[index]:HasTag(tag)
			end)
			if not okHas or not has then
				everywhere = false
				break
			end
		end
		if everywhere then
			table.insert(result, tag)
		end
	end
	table.sort(result)
	return result
end

return Properties
