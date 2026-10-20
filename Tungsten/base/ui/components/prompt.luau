--[[
	Tungsten · base/ui/components/prompt
	Dialogs: a card in the middle of the main window (on the overlay, so
	it is never cut off). The screen isn't darkened; clicks on the window
	outside the card do nothing; Escape cancels.
	opts.Dim = true darkens the window behind the card; opts.Screen = true
	centres the card on the whole screen instead of the window (also what
	happens while the window is minimized).

		Prompt.confirm({ Title = "Delete 3 objects?", Text = "This can't be undone.",
			ConfirmText = "Delete", Danger = true,
			OnConfirm = function() end, OnCancel = function() end })

		Prompt.input({ Title = "Rename", Default = "Part", Placeholder = "name",
			Type = "string",                       -- any value type: parsed with Types.parse
			Validate = function(text) return true, text end,   -- or false, reason
			OnSubmit = function(value) return true end })       -- or false, reason (stays open)

		Prompt.choice({ Title = "Pick a team", Options = { "Red", "Blue" }, Multi = false,
			OnChoose = function(value or values) end })

		Prompt.form({ Title = "New remote spy rule", Fields = {
				{ Key = "name", Label = "Name", Kind = "text", Default = "Rule" },
				{ Key = "max", Label = "Max calls", Kind = "number", Default = 10, Min = 1 },
				{ Key = "on", Label = "Enabled", Kind = "toggle", Default = true },
				{ Key = "mode", Label = "Mode", Kind = "dropdown", Options = { "Log", "Block" } },
				{ Key = "class", Label = "Class", Kind = "class" },      -- any TypePicker kind
				{ Key = "value", Label = "Value", Kind = "value", ValueType = "Vector3" },
			},
			OnSubmit = function(values) return true end })

		Prompt.custom({ Title = "…", Build = function(body, handle) end, Buttons = { … } })

	Every kind takes Title, Text, Icon, Width, Buttons (extra buttons:
	{ Text, Style = "default"|"accent"|"ghost"|"danger", Callback(handle) }),
	Origin and Owner. A handle has :Close(reason), .Finished (signal:
	result…), and Prompt.await(handle) waits (in a thread that may yield)
	and returns the result: confirm -> true/false, input -> value or nil,
	choice -> value(s) or nil, form -> values or nil.

	Field kinds of your own (plugins too):
		Prompt.registerFieldKind("color", {
			Build = function(holder, field, form) -> { Get = fn, Set = fn, Focus = fn? }
			Height = 26, Owner = "myplugin",
		})
]]

local T = ...
local signal = T.import("base/signal")
local Theme = T.import("base/theme")
local Types = T.import("base/types")
local Create = T.import("base/ui/create")
local Animate = T.import("base/ui/animate")
local Icons = T.import("base/data/icons")
local Overlay = T.import("base/ui/overlay")
local Input = T.import("base/ui/components/input")
local Button = T.import("base/ui/components/button")
local Toggle = T.import("base/ui/components/toggle")
local Dropdown = T.import("base/ui/components/dropdown")
local TypePicker = T.import("base/ui/components/typepicker")
local UI = T.import("base/ui/ui")

local new = Create.new
local Sizes = Theme.Sizes

local PAD = 14
local WIDTH = 340
local LABEL = 92

local Prompt = {}

local fieldKinds: { [string]: any } = {}
local BUILTIN_KINDS = {}

----------------------------------------------------------------------
-- The card
----------------------------------------------------------------------

local function call(handle, fn, ...)
	if fn then
		local ok, a, b = pcall(fn, ...)
		if not ok then
			T.Log.error("ui", "prompt callback failed: " .. tostring(a))
			if handle.Origin ~= "core" then
				T.import("console/reporter").ownerFault(handle.Origin, "prompt callback", a)
			end
			return false, (tostring(a):gsub("^.-:%d+: ", ""))
		end
		return a, b
	end
	return nil, nil
end

local function textHeight(text: string, width: number, size: number): number
	local lines = 0
	for line in (text .. "\n"):gmatch("(.-)\n") do
		lines += math.max(1, math.ceil(Create.textWidth(line, size) / math.max(1, width)))
	end
	return lines * (size + 4)
end

--[[
	Builds the dimmed backdrop + card; returns handle, body (a vertical
	list where content rows go) and helpers.
]]
local function open(kind: string, opts: { [string]: any })
	local origin = opts.Origin or "core"
	local width = opts.Width or WIDTH
	local backdrop = new("Frame", {
		Name = "Prompt",
		Size = UDim2.fromScale(1, 1),
		Active = true,
		BackgroundTransparency = 1,
		Theme = { BackgroundColor3 = "Background" },
	})
	-- Over the main window (not the whole screen) unless asked otherwise.
	local window = T.Window
	if not opts.Screen and window and window.Root and window.Root.Visible and not window.Minimized then
		local root = window.Root
		-- on-screen rectangle -> layout pixels of the popup layer
		local at = Overlay.toLayout(root.AbsolutePosition)
		local size = root.AbsoluteSize / Overlay.factor()
		backdrop.Position = UDim2.fromOffset(at.X, at.Y)
		backdrop.Size = UDim2.fromOffset(size.X, size.Y)
		Create.corner(backdrop, Sizes.Radius)
	end
	if opts.Dim then
		Animate.tween(backdrop, { BackgroundTransparency = 0.45 }, Animate.Fast)
	end
	local card = new("Frame", {
		Name = "Card",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.45),
		Size = UDim2.fromOffset(width, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Active = true,
		Theme = { BackgroundColor3 = "Surface" },
		Parent = backdrop,
	})
	Create.corner(card, Sizes.Radius)
	-- With nothing darkened behind it, an accent outline sets it apart.
	Create.stroke(card, if opts.Dim then "BorderStrong" else "Accent", 1, if opts.Dim then 0 else 0.35)
	Create.padding(card, PAD, PAD, PAD, PAD)
	Create.list(card, Enum.FillDirection.Vertical, 10)
	local scale = new("UIScale", { Scale = 0.96, Parent = card })
	Animate.tween(scale, { Scale = 1 }, Animate.Fast)

	local inner = width - PAD * 2
	local order = 0
	local function row(name: string, height: number?)
		order += 1
		return new("Frame", {
			Name = name,
			Size = UDim2.new(1, 0, 0, height or Sizes.Control),
			LayoutOrder = order,
			BackgroundTransparency = 1,
			Parent = card,
		})
	end

	local handle = { Kind = kind, Origin = origin, Card = card, Backdrop = backdrop, Finished = signal.new(), Result = nil, Bin = signal.bin() }

	-- Title (with an optional icon)
	if opts.Title then
		local titleRow = row("Title", 20)
		local x = 0
		if opts.Icon then
			local icon = Icons.new(opts.Icon, 18, if opts.Danger then "Danger" else "Accent")
			icon.AnchorPoint = Vector2.new(0, 0.5)
			icon.Position = UDim2.new(0, 0, 0.5, 0)
			icon.Parent = titleRow
			x = 26
		end
		new("TextLabel", {
			Name = "Text",
			Position = UDim2.fromOffset(x, 0),
			Size = UDim2.new(1, -x, 1, 0),
			Text = tostring(opts.Title),
			FontFace = Theme.Fonts.Bold,
			TextSize = Sizes.Title,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Theme = { TextColor3 = "Text" },
			Parent = titleRow,
		})
	end
	if opts.Text and opts.Text ~= "" then
		local text = tostring(opts.Text)
		local holder = row("Message", textHeight(text, inner, Sizes.Text))
		new("TextLabel", {
			Name = "Text",
			Size = UDim2.fromScale(1, 1),
			Text = text,
			TextWrapped = true,
			TextYAlignment = Enum.TextYAlignment.Top,
			Theme = { TextColor3 = "TextDim" },
			Parent = holder,
		})
	end

	handle.Row = row
	handle.Inner = inner

	function handle:Finish(...)
		if self.Closed then
			return
		end
		self.Result = table.pack(...)
		self:Close("finished")
	end

	function handle:_buttons(list: { any })
		local holder = row("Buttons", Sizes.Control)
		local layout = Create.list(holder, Enum.FillDirection.Horizontal, 8, {
			HorizontalAlignment = Enum.HorizontalAlignment.Right,
			VerticalAlignment = Enum.VerticalAlignment.Center,
		})
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		self.Buttons = {}
		for index, spec in list do
			local button = Button.new({
				Name = spec.Name or ("Button" .. index),
				Parent = holder,
				Origin = origin,
				Text = spec.Text,
				Icon = spec.Icon,
				Style = spec.Style or "default",
				LayoutOrder = index,
				OnClick = function()
					call(self, spec.Callback, self)
				end,
			})
			self.Bin:Add(button)
			self.Buttons[spec.Name or spec.Text] = button
		end
	end

	handle.Overlay = Overlay.open(backdrop, {
		Owner = opts.Owner,
		Modal = true,
		OnClose = function(reason)
			handle.Closed = true
			handle.Bin:Clean()
			local result = handle.Result or table.pack(handle.CancelValue)
			if handle.Result == nil and handle.OnCancel then
				call(handle, handle.OnCancel, reason)
			end
			UI.fire("Prompt", "Closed", origin, handle, reason)
			handle.Finished:Fire(table.unpack(result, 1, result.n))
			handle.Finished:DisconnectAll()
		end,
	})
	function handle:Close(reason: string?)
		if not self.Overlay.Closed then
			self.Overlay:Close(reason or "closed")
		end
	end
	return handle
end

-- The problem line (hidden while empty).
local function problemRow(handle)
	local holder = handle.Row("Problem", 16)
	holder.Visible = false
	local label = new("TextLabel", {
		Name = "Text",
		Size = UDim2.fromScale(1, 1),
		Text = "",
		TextSize = Sizes.TextSmall,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Theme = { TextColor3 = "Danger" },
		Parent = holder,
	})
	handle.Problem = label
	function handle:SetProblem(text: string?)
		label.Text = text or ""
		holder.Visible = text ~= nil and text ~= ""
	end
	return label
end

local function extraButtons(opts, list)
	for _, spec in opts.Buttons or {} do
		table.insert(list, 1, spec)
	end
	return list
end

local function finishOpen(handle, opts)
	UI.fire("Prompt", "Created", handle.Origin, handle, opts)
	UI.fire("Prompt", "Opened", handle.Origin, handle, opts)
	return handle
end

----------------------------------------------------------------------
-- Kinds
----------------------------------------------------------------------

function Prompt.confirm(opts: { [string]: any })
	local handle = open("confirm", opts)
	handle.CancelValue = false
	handle.OnCancel = opts.OnCancel
	handle:_buttons(extraButtons(opts, {
		{ Name = "Cancel", Text = opts.CancelText or "Cancel", Style = "ghost", Callback = function(h)
			h:Close("cancel")
		end },
		{ Name = "Confirm", Text = opts.ConfirmText or "OK", Style = if opts.Danger then "danger" else "accent", Callback = function(h)
			h.Result = table.pack(true)
			call(h, opts.OnConfirm)
			h:Close("confirmed")
		end },
	}))
	return finishOpen(handle, opts)
end

function Prompt.input(opts: { [string]: any })
	local handle = open("input", opts)
	handle.OnCancel = opts.OnCancel
	local holder = handle.Row("Field", Sizes.Control)
	local box = Input.new({
		Name = "Box",
		Parent = holder,
		Origin = handle.Origin,
		Text = if opts.Default ~= nil then (if type(opts.Default) == "string" then opts.Default else Types.editText(opts.Default)) else "",
		Placeholder = opts.Placeholder or (if opts.Type and opts.Type ~= "string" then Types.hint(opts.Type) else ""),
		Mono = opts.Mono or (opts.Type ~= nil and opts.Type ~= "string"),
		Size = UDim2.fromScale(1, 1),
	})
	handle.Bin:Add(box)
	handle.Box = box
	problemRow(handle)
	local function submit()
		local text = box:GetText()
		local ok, value = true, text
		if opts.Type and opts.Type ~= "string" then
			ok, value = Types.parse(text, opts.Type, { Enum = opts.Enum })
		end
		if ok and opts.Validate then
			local okCall, a, b = pcall(opts.Validate, text)
			if not okCall then
				ok, value = false, tostring(a)
			elseif a == false then
				ok, value = false, b
			elseif a == true and b ~= nil then
				value = b
			end
		end
		if not ok then
			handle:SetProblem(tostring(value or "not accepted"))
			return false
		end
		if opts.OnSubmit then
			local accepted, reason = call(handle, opts.OnSubmit, value)
			if accepted == false then
				handle:SetProblem(tostring(reason or "not accepted"))
				return false
			end
		end
		handle.Result = table.pack(value)
		handle:Close("submitted")
		return true
	end
	handle.Submit = submit
	handle.Bin:Add(box.Box.FocusLost:Connect(function(enter)
		if enter then
			submit()
		end
	end))
	handle.Bin:Add(box.Box:GetPropertyChangedSignal("Text"):Connect(function()
		handle:SetProblem(nil)
	end))
	handle:_buttons(extraButtons(opts, {
		{ Name = "Cancel", Text = opts.CancelText or "Cancel", Style = "ghost", Callback = function(h)
			h:Close("cancel")
		end },
		{ Name = "Submit", Text = opts.SubmitText or "OK", Style = "accent", Callback = function()
			submit()
		end },
	}))
	task.defer(function()
		if not handle.Closed then
			box:Focus()
		end
	end)
	return finishOpen(handle, opts)
end

function Prompt.choice(opts: { [string]: any })
	local handle = open("choice", opts)
	handle.OnCancel = opts.OnCancel
	local options = Dropdown.normalize(opts.Options or {})
	if UI.has("Prompt", "Options") then
		options = Dropdown.normalize(UI.apply("Prompt", "Options", handle.Origin, options, opts))
	end
	local chosen = {}
	local rowsShown = math.min(#options, 8)
	local holder = handle.Row("Options", rowsShown * 28)
	local Scroll = T.import("base/ui/components/scroll")
	local scroll = Scroll.new({ Name = "List", Origin = handle.Origin, Size = UDim2.fromScale(1, 1), Parent = holder })
	handle.Bin:Add(scroll)
	Create.list(scroll.Content, Enum.FillDirection.Vertical, 2)
	local buttons = {}
	local function paint()
		for index, button in buttons do
			local on = chosen[index] == true
			Theme.bind(button, "BackgroundColor3", if on then "AccentSoft" else "SurfaceHover")
			button.BackgroundTransparency = if on then 0 else 1
		end
	end
	local function done()
		local values = {}
		for index, option in options do
			if chosen[index] then
				table.insert(values, option.Value)
			end
		end
		local result = if opts.Multi then values else values[1]
		handle.Result = table.pack(result)
		call(handle, opts.OnChoose, result)
		handle:Close("chosen")
	end
	for index, option in options do
		local button = new("TextButton", {
			Name = "Option" .. index,
			Size = UDim2.new(1, 0, 0, 26),
			LayoutOrder = index,
			BackgroundTransparency = 1,
			Theme = { BackgroundColor3 = "SurfaceHover" },
			Parent = scroll.Content,
		})
		Create.corner(button, 5)
		local x = 10
		if option.Icon then
			local icon = Icons.new(option.Icon, 14, option.IconColor or "TextDim")
			icon.AnchorPoint = Vector2.new(0, 0.5)
			icon.Position = UDim2.new(0, 8, 0.5, 0)
			icon.Parent = button
			x = 30
		end
		new("TextLabel", {
			Name = "Text",
			Position = UDim2.fromOffset(x, 0),
			Size = UDim2.new(1, -x - 8, 1, 0),
			Text = option.Text,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Theme = { TextColor3 = if option.Disabled then "TextMuted" else "Text" },
			Parent = button,
		})
		if option.Hint then
			new("TextLabel", {
				Name = "Hint",
				Size = UDim2.new(1, -8, 1, 0),
				Text = option.Hint,
				TextSize = Sizes.TextSmall,
				TextXAlignment = Enum.TextXAlignment.Right,
				Theme = { TextColor3 = "TextMuted" },
				Parent = button,
			})
		end
		buttons[index] = button
		handle.Bin:Add(button.Activated:Connect(function()
			if option.Disabled then
				return
			end
			if opts.Multi then
				chosen[index] = not chosen[index] or nil
				paint()
			else
				chosen = { [index] = true }
				done()
			end
		end))
	end
	handle.OptionButtons = buttons
	if opts.Multi then
		for index, option in options do
			if opts.Values and table.find(opts.Values, option.Value) then
				chosen[index] = true
			end
		end
		paint()
	end
	local list = { { Name = "Cancel", Text = opts.CancelText or "Cancel", Style = "ghost", Callback = function(h)
		h:Close("cancel")
	end } }
	if opts.Multi then
		table.insert(list, { Name = "Done", Text = opts.SubmitText or "Done", Style = "accent", Callback = function()
			done()
		end })
	end
	handle:_buttons(extraButtons(opts, list))
	handle.Choose = function(index: number)
		if opts.Multi then
			chosen[index] = not chosen[index] or nil
			paint()
		else
			chosen = { [index] = true }
			done()
		end
	end
	handle.Done = done
	return finishOpen(handle, opts)
end

----------------------------------------------------------------------
-- Forms
----------------------------------------------------------------------

function Prompt.registerFieldKind(name: string, definition: { [string]: any })
	assert(type(name) == "string" and name:match("^[%a_][%w_]*$"), "a field kind needs a plain name")
	assert(not BUILTIN_KINDS[name], ("'%s' is a built-in field kind"):format(name))
	assert(type(definition) == "table" and type(definition.Build) == "function", "a field kind needs Build(holder, field, form)")
	fieldKinds[name] = { Build = definition.Build, Height = definition.Height, Owner = definition.Owner or "core" }
end

function Prompt.removeFieldKind(name: string): boolean
	if fieldKinds[name] and not BUILTIN_KINDS[name] then
		fieldKinds[name] = nil
		return true
	end
	return false
end

function Prompt.removeOwner(owner: string): number
	local count = 0
	for name, kind in table.clone(fieldKinds) do
		if kind.Owner == owner and not BUILTIN_KINDS[name] then
			fieldKinds[name] = nil
			count += 1
		end
	end
	return count
end

function Prompt.fieldKinds(): { string }
	local list = {}
	for name in fieldKinds do
		table.insert(list, name)
	end
	table.sort(list)
	return list
end

local function builtin(name: string, definition)
	definition.Owner = "core"
	fieldKinds[name] = definition
	BUILTIN_KINDS[name] = true
end

builtin("text", {
	Build = function(holder, field, form)
		local box = Input.new({
			Name = "Input",
			Parent = holder,
			Origin = form.Origin,
			Text = if field.Default ~= nil then tostring(field.Default) else "",
			Placeholder = field.Placeholder or "",
			Mono = field.Mono,
			Size = UDim2.fromScale(1, 1),
		})
		form.Bin:Add(box)
		return {
			Get = function()
				return box:GetText()
			end,
			Set = function(value)
				box:SetText(tostring(value or ""))
			end,
			Focus = function()
				box:Focus()
			end,
			Control = box,
		}
	end,
})

builtin("number", {
	Build = function(holder, field, form)
		local box = Input.new({
			Name = "Input",
			Parent = holder,
			Origin = form.Origin,
			Numeric = true,
			Value = tonumber(field.Default) or 0,
			Min = field.Min,
			Max = field.Max,
			Step = field.Step,
			Decimals = field.Decimals,
			Size = UDim2.fromScale(1, 1),
		})
		form.Bin:Add(box)
		return {
			Get = function()
				return tonumber(box:GetText()) or box.Value
			end,
			Set = function(value)
				box:SetValue(tonumber(value) or 0)
			end,
			Focus = function()
				box:Focus()
			end,
			Control = box,
		}
	end,
})

builtin("toggle", {
	Build = function(holder, field, form)
		local toggle = Toggle.new({ Name = "Toggle", Parent = holder, Origin = form.Origin, Value = field.Default == true, Text = field.Text })
		form.Bin:Add(toggle)
		return {
			Get = function()
				return toggle.Value
			end,
			Set = function(value)
				toggle:Set(value == true, true)
			end,
			Control = toggle,
		}
	end,
})

builtin("dropdown", {
	Build = function(holder, field, form)
		local dropdown = Dropdown.new({
			Name = "Dropdown",
			Parent = holder,
			Origin = form.Origin,
			Options = field.Options or {},
			Value = field.Default,
			Multi = field.Multi,
			Values = field.Values,
			Placeholder = field.Placeholder,
			Match = field.Match,
			Size = UDim2.fromScale(1, 1),
		})
		form.Bin:Add(dropdown)
		return {
			Get = function()
				return if field.Multi then dropdown:GetValues() else dropdown:GetValue()
			end,
			Set = function(value)
				if field.Multi then
					dropdown:SetValues(value or {}, true)
				else
					dropdown:SetValue(value, true)
				end
			end,
			Control = dropdown,
		}
	end,
})

-- A value of any type, typed as text (Types.parse) with a type picker
-- when ValueType isn't fixed.
builtin("value", {
	Build = function(holder, field, form)
		local valueType = field.ValueType or "any"
		local box = Input.new({
			Name = "Input",
			Parent = holder,
			Origin = form.Origin,
			Mono = true,
			Text = if field.Default ~= nil then Types.editText(field.Default) else "",
			Placeholder = field.Placeholder or Types.hint(valueType),
			Size = UDim2.fromScale(1, 1),
		})
		form.Bin:Add(box)
		return {
			Get = function()
				local ok, value = Types.parse(box:GetText(), valueType, { Enum = field.Enum })
				if not ok then
					error(value, 0)
				end
				return value
			end,
			Set = function(value)
				box:SetText(Types.editText(value))
			end,
			Focus = function()
				box:Focus()
			end,
			Control = box,
		}
	end,
})

-- Static text in the form.
builtin("label", {
	Height = 18,
	Build = function(holder, field)
		new("TextLabel", {
			Name = "Text",
			Size = UDim2.fromScale(1, 1),
			Text = tostring(field.Text or field.Default or ""),
			TextSize = Sizes.TextSmall,
			TextWrapped = true,
			Theme = { TextColor3 = "TextMuted" },
			Parent = holder,
		})
		return {
			Get = function()
				return nil
			end,
			Set = function() end,
		}
	end,
})

-- Any TypePicker kind as a field kind: "class", "creatable", "valueType",
-- "attribute", "isa:BasePart", "enum:Material", or a registered picker kind.
local function pickerField(holder, field, form)
	local picker = TypePicker.new({
		Name = "Picker",
		Parent = holder,
		Origin = form.Origin,
		Kind = field.Kind,
		Value = field.Default,
		Size = UDim2.fromScale(1, 1),
	})
	form.Bin:Add(picker)
	return {
		Get = function()
			return picker:GetValue()
		end,
		Set = function(value)
			picker:SetValue(value, true)
		end,
		Control = picker,
	}
end

function Prompt.form(opts: { [string]: any })
	local handle = open("form", opts)
	handle.OnCancel = opts.OnCancel
	local fields = opts.Fields or {}
	if UI.has("Prompt", "Fields") then
		fields = UI.apply("Prompt", "Fields", handle.Origin, table.clone(fields), opts)
	end
	local controls = {}
	local labelWidth = opts.LabelWidth or LABEL
	for index, field in fields do
		local kind = fieldKinds[field.Kind or "text"]
		local isPicker = kind == nil and TypePicker.isPickerKind(field.Kind)
		if not kind and not isPicker then
			error(("unknown form field kind '%s'"):format(tostring(field.Kind)), 2)
		end
		local height = (kind and kind.Height) or field.Height or Sizes.Control
		local line = handle.Row("Field_" .. tostring(field.Key or index), height)
		local x = 0
		if field.Label then
			new("TextLabel", {
				Name = "Label",
				Size = UDim2.new(0, labelWidth - 6, 1, 0),
				Text = tostring(field.Label),
				TextSize = Sizes.TextSmall,
				TextTruncate = Enum.TextTruncate.AtEnd,
				Theme = { TextColor3 = "TextDim" },
				Parent = line,
			})
			x = labelWidth
		end
		local holder = new("Frame", {
			Name = "Holder",
			Position = UDim2.fromOffset(x, 0),
			Size = UDim2.new(1, -x, 1, 0),
			BackgroundTransparency = 1,
			Parent = line,
		})
		local ok, control = pcall(if kind then kind.Build else pickerField, holder, field, handle)
		if not ok or type(control) ~= "table" then
			T.Log.error("ui", ("form field '%s' failed: %s"):format(tostring(field.Key), tostring(control)))
			if kind and kind.Owner ~= "core" then
				T.import("console/reporter").ownerFault(kind.Owner, ("form field kind '%s'"):format(tostring(field.Kind)), control)
			end
			control = { Get = function() return field.Default end, Set = function() end }
		end
		control.Field = field
		controls[field.Key or index] = control
	end
	handle.Fields = controls
	problemRow(handle)

	-- Values by Key; a field's own Validate(value, values) may refuse.
	local function collect(): (boolean, any)
		local values = {}
		for key, control in controls do
			local ok, value = pcall(control.Get)
			if not ok then
				return false, ("%s: %s"):format(tostring(control.Field.Label or key), tostring(value))
			end
			values[key] = value
		end
		for key, control in controls do
			local field = control.Field
			if field.Required and (values[key] == nil or values[key] == "") then
				return false, ("%s is needed"):format(tostring(field.Label or key))
			end
			if field.Validate then
				local ok, accepted, reason = pcall(field.Validate, values[key], values)
				if not ok then
					return false, tostring(accepted)
				end
				if accepted == false then
					return false, ("%s: %s"):format(tostring(field.Label or key), tostring(reason or "not accepted"))
				end
			end
		end
		return true, values
	end
	local function submit()
		local ok, values = collect()
		if not ok then
			handle:SetProblem(values)
			return false
		end
		if opts.OnSubmit then
			local accepted, reason = call(handle, opts.OnSubmit, values)
			if accepted == false then
				handle:SetProblem(tostring(reason or "not accepted"))
				return false
			end
		end
		handle.Result = table.pack(values)
		handle:Close("submitted")
		return true
	end
	handle.Submit = submit
	handle.Values = function()
		return collect()
	end
	handle:_buttons(extraButtons(opts, {
		{ Name = "Cancel", Text = opts.CancelText or "Cancel", Style = "ghost", Callback = function(h)
			h:Close("cancel")
		end },
		{ Name = "Submit", Text = opts.SubmitText or "OK", Style = "accent", Callback = function()
			submit()
		end },
	}))
	task.defer(function()
		if handle.Closed then
			return
		end
		for _, field in fields do
			local control = controls[field.Key]
			if control and control.Focus then
				control.Focus()
				break
			end
		end
	end)
	return finishOpen(handle, opts)
end

-- A card with content of your own: Build(body, handle) fills it.
function Prompt.custom(opts: { [string]: any })
	local handle = open("custom", opts)
	handle.OnCancel = opts.OnCancel
	local body = handle.Row("Body", opts.Height or 120)
	if opts.Build then
		local ok, err = pcall(opts.Build, body, handle)
		if not ok then
			T.Log.error("ui", "prompt Build failed: " .. tostring(err))
			if handle.Origin ~= "core" then
				T.import("console/reporter").ownerFault(handle.Origin, "prompt Build", err)
			end
		end
	end
	handle.Body = body
	problemRow(handle)
	local list = {}
	for _, spec in opts.Buttons or {} do
		table.insert(list, spec)
	end
	if #list == 0 then
		list = { { Name = "Close", Text = opts.CloseText or "Close", Style = "accent", Callback = function(h)
			h:Close("closed")
		end } }
	end
	handle:_buttons(list)
	return finishOpen(handle, opts)
end

--[[
	Prompt.popover({ AnchorPos, AnchorSize, Width, Height, Side = "below",
		Build = function(frame, handle) end }) -> overlay handle
	A plain panel next to something (not modal: a click outside closes it),
	for small editors and previews of your own.
]]
function Prompt.popover(opts: { [string]: any })
	local size = Vector2.new(opts.Width or 240, opts.Height or 160)
	local position = Overlay.place(size, opts.AnchorPos or Overlay.mouse(), opts.AnchorSize, { Side = opts.Side or "below", Gap = 4 })
	local frame = Overlay.panel(size, position)
	frame.Name = "Popover"
	local handle = Overlay.open(frame, { Owner = opts.Owner, Parent = opts.Parent, OnClose = opts.OnClose })
	handle.Kind = "popover"
	if opts.Build then
		local ok, err = pcall(opts.Build, frame, handle)
		if not ok then
			T.Log.error("ui", "popover Build failed: " .. tostring(err))
			if opts.Origin and opts.Origin ~= "core" then
				T.import("console/reporter").ownerFault(opts.Origin, "popover Build", err)
			end
		end
	end
	UI.fire("Prompt", "Opened", opts.Origin or "core", handle, opts)
	return handle
end

-- Waits for a prompt to close and returns its result (call from a thread
-- that may yield, e.g. a command or task.spawn).
function Prompt.await(handle)
	if handle.Closed then
		local result = handle.Result or table.pack(handle.CancelValue)
		return table.unpack(result, 1, result.n)
	end
	local thread = coroutine.running()
	handle.Finished:Once(function(...)
		task.spawn(thread, ...)
	end)
	return coroutine.yield()
end

T.Bin:Add(function()
	for name in table.clone(fieldKinds) do
		if not BUILTIN_KINDS[name] then
			fieldKinds[name] = nil
		end
	end
end)

return UI.register("Prompt", Prompt, {
	Description = "dialogs: confirm, input, choice, form and custom cards",
	Constructor = function(props)
		local kind = props.Kind or "confirm"
		local fn = Prompt[kind]
		assert(type(fn) == "function" and kind ~= "await", ("no prompt kind '%s'"):format(tostring(kind)))
		return fn(props)
	end,
	Events = {
		Created = "handle, opts · (same as Opened)",
		Opened = "handle, opts",
		Closed = "handle, reason",
	},
	Filters = {
		Options = "options, opts · the choices of Prompt.choice",
		Fields = "fields, opts · the fields of Prompt.form",
	},
})
