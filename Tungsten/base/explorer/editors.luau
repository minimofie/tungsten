--[[
	Tungsten · base/explorer/editors
	How the properties panel shows and edits each kind of value. Editors
	are registered by value type ("Color3") or for one property of a
	class ("BasePart.Color", which subclasses share); plugins add their
	own the same way and they are removed with the plugin.

		Editors.register("Color3", {
			Inline = "swatch",            -- what the value cell shows:
			                              -- "text" (default), "toggle", "dropdown",
			                              -- "swatch" (color square + text),
			                              -- "popup" (text + a … button)
			Display = function(value, prop) return "text" end,   -- optional
			Swatch = function(value) return Color3 end,          -- swatch color
			Options = function(ctx) return { options } end,      -- dropdown items
			Open = function(ctx) return overlayHandle end,       -- swatch / … / click
			Fields = { … } or function(prop) return { … } end,   -- sub-rows
			Parse = function(text, prop) return true, value end, -- text editing
			EditText = function(value, prop) return "text" end,
			Hint = "what to type",
			Owner = "myplugin",
		})
		Editors.register("Part.Material", { … })   -- one property

	ctx for Open / Options:
		Prop, Value, Same (all selected objects agree), Instances,
		AnchorPos, AnchorSize (the value cell), Origin,
		Apply(newValue) -> ok, reason   (writes to every selected object)
	A field (sub-row) is { Name, Type, Enum?, Integer?, Get(value), Set(value, part) }.
]]

local T = ...
local Types = T.import("base/types")
local Variables = T.import("base/variables")
local Theme = T.import("base/theme")
local Create = T.import("base/ui/create")
local Icons = T.import("base/data/icons")
local Animate = T.import("base/ui/animate")
local Overlay = T.import("base/ui/overlay")
local signal = T.import("base/signal")
local Input = T.import("base/ui/components/input")
local Button = T.import("base/ui/components/button")
local TypePicker = T.import("base/ui/components/typepicker")
local ColorPicker = T.import("base/ui/components/colorpicker")
local SequenceEditor = T.import("base/ui/components/sequenceeditor")
local Api = T.import("base/explorer/api")

local new = Create.new
local Sizes = Theme.Sizes

local Editors = {}
Editors.Changed = signal.new() -- (key)

local registry: { [string]: any } = {}
local builtin: { [string]: boolean } = {}

local INLINE = { text = true, toggle = true, dropdown = true, swatch = true, popup = true }

function Editors.register(key: string, definition: { [string]: any })
	assert(type(key) == "string" and key ~= "", "an editor needs a type or Class.Property")
	assert(type(definition) == "table", "an editor needs a definition table")
	assert(definition.Inline == nil or INLINE[definition.Inline], "Inline is text, toggle, dropdown, swatch or popup")
	local owner = definition.Owner or "core"
	if registry[key] and builtin[key] and owner ~= "core" then
		-- A plugin's editor goes on top of the built-in one; removing the
		-- plugin brings the built-in one back.
		local entry = table.clone(definition)
		entry.Owner = owner
		entry._Under = registry[key]
		registry[key] = entry
	else
		local entry = table.clone(definition)
		entry.Owner = owner
		registry[key] = entry
	end
	Editors.Changed:Fire(key)
end

local function unwrap(key: string, owner: string): boolean
	local entry = registry[key]
	local removed = false
	local previous = nil
	while entry do
		if entry.Owner == owner then
			removed = true
			if previous then
				previous._Under = entry._Under
			else
				registry[key] = entry._Under
			end
		else
			previous = entry
		end
		entry = entry._Under
	end
	return removed
end

function Editors.unregister(key: string, owner: string?): boolean
	local removed = unwrap(key, owner or "core")
	if removed then
		Editors.Changed:Fire(key)
	end
	return removed
end

function Editors.removeOwner(owner: string): number
	local count = 0
	for key in table.clone(registry) do
		while unwrap(key, owner) do
			count += 1
		end
	end
	if count > 0 then
		Editors.Changed:Fire(nil)
	end
	return count
end

function Editors.list(): { any }
	local list = {}
	for key, entry in registry do
		table.insert(list, { Key = key, Owner = entry.Owner, Inline = entry.Inline or "text" })
	end
	table.sort(list, function(a, b)
		return a.Key < b.Key
	end)
	return list
end

local DEFAULT = { Inline = "text", Owner = "core" }

-- The editor for a property: Class.Property (this class or a base class),
-- then the value type, then plain text.
function Editors.get(prop: any)
	if type(prop) ~= "table" then
		return registry[tostring(prop)] or DEFAULT
	end
	local className = prop.Class
	if className and className ~= "?" then
		local chain = { className }
		for _, base in Api.superclasses(className) do
			table.insert(chain, base)
		end
		for _, name in chain do
			local entry = registry[name .. "." .. prop.Name]
			if entry then
				return entry
			end
		end
	end
	if prop.ViewClass then
		local entry = registry[prop.ViewClass .. "." .. prop.Name]
		if entry then
			return entry
		end
	end
	return registry[prop.Type] or DEFAULT
end

function Editors.fieldsFor(prop: any): { any }?
	local entry = Editors.get(prop)
	local fields = entry.Fields
	if type(fields) == "function" then
		local ok, result = pcall(fields, prop)
		if ok and type(result) == "table" then
			return result
		end
		return nil
	end
	return fields
end

----------------------------------------------------------------------
-- Text editing helpers (used by the panel's cell editor)
----------------------------------------------------------------------

function Editors.parse(prop: any, text: string): (boolean, any)
	local entry = Editors.get(prop)
	if entry.Parse then
		local ok, success, value = pcall(entry.Parse, text, prop)
		if not ok then
			return false, tostring(success)
		end
		return success, value
	end
	local ok, value = Types.parse(text, prop.Type, { Enum = prop.Enum })
	if ok and prop.Integer and type(value) == "number" and value ~= math.floor(value) then
		return false, "type a whole number"
	end
	if ok and prop.Type == "Instance" and value ~= nil and prop.ClassRef and prop.ClassRef ~= "Instance" then
		local okIs, is = pcall(function()
			return value:IsA(prop.ClassRef)
		end)
		if not (okIs and is) then
			return false, ("%s needs a %s, not a %s"):format(prop.Name, prop.ClassRef, Types.classOf(value) or "?")
		end
	end
	return ok, value
end

function Editors.editText(prop: any, value: any): string
	local entry = Editors.get(prop)
	if entry.EditText then
		local ok, text = pcall(entry.EditText, value, prop)
		if ok and text ~= nil then
			return tostring(text)
		end
	end
	if value == nil then
		return ""
	end
	return Types.editText(value)
end

function Editors.hint(prop: any): string
	local entry = Editors.get(prop)
	if entry.Hint then
		return tostring(entry.Hint)
	end
	if prop.DataType == "ContentId" then
		return "an asset id or rbxassetid://…"
	end
	if prop.Integer then
		return "a whole number"
	end
	if prop.Type == "Instance" then
		return ("a path or $variable (%s)"):format(prop.ClassRef or "Instance")
	end
	local hint = Types.Hints[prop.Type]
	return hint or prop.Type
end

----------------------------------------------------------------------
-- Built-in editors
----------------------------------------------------------------------

local function core(key: string, definition)
	definition.Owner = "core"
	registry[key] = definition
	builtin[key] = true
end

core("boolean", { Inline = "toggle" })

core("EnumItem", {
	Inline = "dropdown",
	Options = function(ctx)
		local enumName = ctx.Prop.Enum
		if not enumName and typeof(ctx.Value) == "EnumItem" then
			enumName = (tostring(ctx.Value.EnumType):gsub("^Enum%.", ""))
		end
		if not enumName then
			return {}
		end
		return TypePicker.options("enum:" .. enumName, ctx.Origin)
	end,
})

core("Color3", {
	Inline = "swatch",
	Swatch = function(value)
		return value
	end,
	Open = function(ctx)
		return ColorPicker.open({
			Origin = ctx.Origin,
			AnchorPos = ctx.AnchorPos,
			AnchorSize = ctx.AnchorSize,
			Value = ctx.Value,
			Owner = ctx.Owner,
			OnChange = function(color)
				ctx.Apply(color)
			end,
		})
	end,
})

core("BrickColor", {
	Inline = "swatch",
	Swatch = function(value)
		return value.Color
	end,
	Open = function(ctx)
		return ColorPicker.palette({
			Origin = ctx.Origin,
			AnchorPos = ctx.AnchorPos,
			AnchorSize = ctx.AnchorSize,
			Value = ctx.Value,
			Owner = ctx.Owner,
			OnChange = function(brick)
				ctx.Apply(brick)
			end,
		})
	end,
})

local function sequenceEditor(kind: string)
	return function(ctx)
		return SequenceEditor.open({
			Origin = ctx.Origin,
			AnchorPos = ctx.AnchorPos,
			AnchorSize = ctx.AnchorSize,
			Value = ctx.Value,
			Kind = kind,
			Owner = ctx.Owner,
			OnChange = function(sequence)
				ctx.Apply(sequence)
			end,
		})
	end
end

core("NumberSequence", { Inline = "popup", Open = sequenceEditor("number") })
core("ColorSequence", {
	Inline = "popup",
	Swatch = function(value)
		return value.Keypoints[1].Value
	end,
	Open = sequenceEditor("color"),
})

-- ContentId strings: a plain number becomes rbxassetid://number.
core("string", {
	Inline = "text",
	Parse = function(text, prop)
		if prop.DataType == "ContentId" then
			local trimmed = text:gsub("^%s+", ""):gsub("%s+$", "")
			if trimmed:match("^%d+$") then
				return true, "rbxassetid://" .. trimmed
			end
			return true, trimmed
		end
		return true, text
	end,
})

----------------------------------------------------------------------
-- Object references
----------------------------------------------------------------------

local REF_WIDTH = 280

-- Instances held by variables that fit a class.
local function variableChoices(className: string): { any }
	local list = {}
	for _, entry in Variables.list() do
		local value = entry.Value
		if typeof(value) == "Instance" then
			local ok, is = pcall(function()
				return value:IsA(className)
			end)
			if ok and is then
				table.insert(list, { Name = entry.Name, Value = value })
			end
		end
	end
	return list
end

function Editors.openReference(ctx)
	local prop = ctx.Prop
	local className = prop.ClassRef or "Instance"
	local choices = variableChoices(className)
	local shown = math.min(#choices, 6)
	local height = 10 + 18 + 6 + Sizes.Control + 8 + Sizes.Control + (if shown > 0 then 8 + 18 + shown * 24 else 0) + 10
	local size = Vector2.new(REF_WIDTH, height)
	local position = Overlay.place(size, ctx.AnchorPos, ctx.AnchorSize, { Side = "below", Gap = 4 })
	local frame = Overlay.panel(size, position)
	frame.Name = "ReferenceEditor"
	local bin = signal.bin()
	local handle

	local current = if ctx.Same then ctx.Value else nil
	local title = new("TextLabel", {
		Name = "Current",
		Position = UDim2.fromOffset(10, 10),
		Size = UDim2.new(1, -20, 0, 18),
		Text = ("%s · %s"):format(prop.Name, if not ctx.Same then "different objects" elseif current then Types.path(current) else "nil"),
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextSize = Sizes.TextSmall,
		Theme = { TextColor3 = "TextDim" },
		Parent = frame,
	})
	local y = 10 + 18 + 6
	local problem = nil
	local box = Input.new({
		Name = "Path",
		Parent = frame,
		Origin = ctx.Origin,
		Mono = true,
		Icon = "object",
		Placeholder = ("path or $variable (%s)"):format(className),
		Text = if current then Types.path(current) else "",
		Position = UDim2.fromOffset(10, y),
		Size = UDim2.new(1, -20, 0, Sizes.Control),
	})
	bin:Add(box)
	bin:Add(box.Box.FocusLost:Connect(function(enter)
		if not enter then
			return
		end
		local ok, value = Editors.parse(prop, box:GetText())
		if not ok then
			title.Text = tostring(value)
			Theme.bind(title, "TextColor3", "Danger")
			return
		end
		local applied, reason = ctx.Apply(value)
		if applied == false then
			title.Text = tostring(reason)
			Theme.bind(title, "TextColor3", "Danger")
			return
		end
		handle:Close("committed")
	end))
	y += Sizes.Control + 8

	local actions = {
		{ "Pick", "target", "Pick in explorer", function()
			handle:Close("pick")
			if ctx.Pick then
				ctx.Pick()
			end
		end },
		{ "Clear", "close", "Set to nil", function()
			local applied, reason = ctx.Apply(nil)
			if applied == false then
				title.Text = tostring(reason)
				Theme.bind(title, "TextColor3", "Danger")
				return
			end
			handle:Close("committed")
		end },
		{ "GoTo", "arrow_right", "Go to", function()
			if current and ctx.Highlight then
				handle:Close("goto")
				ctx.Highlight(current)
			end
		end },
	}
	local buttonWidth = math.floor((REF_WIDTH - 20 - 12) / 3)
	local buttons = {}
	for index, action in actions do
		local button = Button.new({
			Name = action[1],
			Parent = frame,
			Origin = ctx.Origin,
			Text = action[3],
			Icon = action[2],
			Style = "ghost",
			Size = UDim2.fromOffset(buttonWidth, Sizes.Control),
			Position = UDim2.fromOffset(10 + (index - 1) * (buttonWidth + 6), y),
			OnClick = action[4],
		})
		bin:Add(button)
		buttons[action[1]] = button
	end
	if not current then
		buttons.GoTo:SetEnabled(false)
	end
	y += Sizes.Control

	if shown > 0 then
		y += 8
		new("TextLabel", {
			Name = "VariablesTitle",
			Position = UDim2.fromOffset(10, y),
			Size = UDim2.new(1, -20, 0, 18),
			Text = "Variables",
			TextSize = Sizes.TextSmall,
			Theme = { TextColor3 = "TextMuted" },
			Parent = frame,
		})
		y += 18
		for index = 1, shown do
			local choice = choices[index]
			local row = new("TextButton", {
				Name = "Var_" .. choice.Name,
				Position = UDim2.fromOffset(6, y + (index - 1) * 24),
				Size = UDim2.new(1, -12, 0, 24),
				BackgroundTransparency = 1,
				Theme = { BackgroundColor3 = "SurfaceHover" },
				Parent = frame,
			})
			Create.corner(row, 4)
			local icon, color = Types.icon(choice.Value)
			local image = Icons.new(icon, 14, color)
			image.AnchorPoint = Vector2.new(0, 0.5)
			image.Position = UDim2.new(0, 6, 0.5, 0)
			image.Parent = row
			new("TextLabel", {
				Name = "Text",
				Position = UDim2.fromOffset(26, 0),
				Size = UDim2.new(1, -30, 1, 0),
				Text = ("$%s  %s"):format(choice.Name, Types.path(choice.Value)),
				TextTruncate = Enum.TextTruncate.AtEnd,
				Theme = { TextColor3 = "Text" },
				Parent = row,
			})
			Animate.hover(row, bin, function(hovered)
				row.BackgroundTransparency = if hovered then 0 else 1
			end)
			bin:Add(row.Activated:Connect(function()
				local applied, reason = ctx.Apply(choice.Value)
				if applied == false then
					title.Text = tostring(reason)
					Theme.bind(title, "TextColor3", "Danger")
					return
				end
				handle:Close("committed")
			end))
		end
	end

	handle = Overlay.open(frame, {
		Owner = ctx.Owner,
		OnClose = function()
			bin:Clean()
		end,
	})
	handle.Kind = "reference"
	handle.Box = box
	handle.Buttons = buttons
	handle.Title = title
	return handle
end

core("Instance", {
	Inline = "popup",
	Open = function(ctx)
		return Editors.openReference(ctx)
	end,
})

T.Bin:Add(function()
	Editors.Changed:DisconnectAll()
end)

return Editors
