--[[
	Tungsten · base/explorer/attributeform
	The "Add attribute" popup of the properties panel: a name, the
	attribute's type and a value (empty: the type's default). Adds it to
	every selected object.

		AttributeForm.open({ View = propView, AnchorPos = pos, AnchorSize = size })
]]

local T = ...
local signal = T.import("base/signal")
local Theme = T.import("base/theme")
local Types = T.import("base/types")
local Create = T.import("base/ui/create")
local Overlay = T.import("base/ui/overlay")
local Input = T.import("base/ui/components/input")
local Button = T.import("base/ui/components/button")
local TypePicker = T.import("base/ui/components/typepicker")
local Properties = T.import("base/explorer/properties")

local new = Create.new
local Sizes = Theme.Sizes

local WIDTH = 280
local PAD = 10

local AttributeForm = {}

function AttributeForm.open(opts: { [string]: any })
	local view = opts.View
	local origin = opts.Origin or "core"
	local height = PAD + 18 + 4 + (Sizes.Control + 8) * 3 + 18 + 6 + Sizes.Control + PAD
	local size = Vector2.new(WIDTH, height)
	local position = Overlay.place(size, opts.AnchorPos, opts.AnchorSize, { Side = "below", Gap = 2 })
	local frame = Overlay.panel(size, position)
	frame.Name = "AttributeForm"
	local bin = signal.bin()
	local handle

	local count = #view.Instances
	new("TextLabel", {
		Name = "Title",
		Position = UDim2.fromOffset(PAD, PAD),
		Size = UDim2.new(1, -PAD * 2, 0, 18),
		Text = if count == 1 then "New attribute" else ("New attribute · %d objects"):format(count),
		FontFace = Theme.Fonts.Medium,
		Theme = { TextColor3 = "Text" },
		Parent = frame,
	})
	local y = PAD + 18 + 4
	local labelWidth = 52
	local function label(text: string, at: number)
		new("TextLabel", {
			Name = text .. "Label",
			Position = UDim2.fromOffset(PAD, at),
			Size = UDim2.fromOffset(labelWidth, Sizes.Control),
			Text = text,
			TextSize = Sizes.TextSmall,
			Theme = { TextColor3 = "TextDim" },
			Parent = frame,
		})
	end
	local fieldX = PAD + labelWidth
	local fieldWidth = WIDTH - fieldX - PAD

	label("Name", y)
	local nameBox = Input.new({
		Name = "AttrName",
		Parent = frame,
		Origin = origin,
		Mono = true,
		Placeholder = "Health",
		Position = UDim2.fromOffset(fieldX, y),
		Size = UDim2.fromOffset(fieldWidth, Sizes.Control),
	})
	bin:Add(nameBox)
	y += Sizes.Control + 8

	label("Type", y)
	local chosenType = "string"
	local typePicker = TypePicker.new({
		Name = "AttrType",
		Parent = frame,
		Origin = origin,
		Kind = "attribute",
		Value = chosenType,
		Position = UDim2.fromOffset(fieldX, y),
		Size = UDim2.fromOffset(fieldWidth, Sizes.Control),
		OnChanged = function(value)
			chosenType = value
		end,
	})
	bin:Add(typePicker)
	y += Sizes.Control + 8

	label("Value", y)
	local valueBox = Input.new({
		Name = "AttrValue",
		Parent = frame,
		Origin = origin,
		Mono = true,
		Placeholder = "empty: the type's default",
		Position = UDim2.fromOffset(fieldX, y),
		Size = UDim2.fromOffset(fieldWidth, Sizes.Control),
	})
	bin:Add(valueBox)
	y += Sizes.Control + 8

	local problem = new("TextLabel", {
		Name = "Problem",
		Position = UDim2.fromOffset(PAD, y),
		Size = UDim2.new(1, -PAD * 2, 0, 18),
		Text = "",
		TextSize = Sizes.TextSmall,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Theme = { TextColor3 = "Danger" },
		Parent = frame,
	})
	y += 18 + 6

	local function add(): boolean
		local name = nameBox:GetText():gsub("^%s+", ""):gsub("%s+$", "")
		local okName, reason = Properties.validAttributeName(name)
		if not okName then
			problem.Text = reason
			return false
		end
		local text = valueBox:GetText()
		local value
		if text:match("^%s*$") then
			if chosenType == "EnumItem" then
				problem.Text = "an EnumItem needs a value, e.g. Material.Plastic"
				return false
			end
			value = Types.default(chosenType)
		else
			local ok, parsed = Types.parse(text, chosenType)
			if not ok then
				problem.Text = tostring(parsed)
				return false
			end
			value = parsed
		end
		if value == nil then
			problem.Text = ("can't make a %s value"):format(chosenType)
			return false
		end
		local changed, failures = Properties.setAttribute(view.Instances, name, value)
		if changed == 0 then
			problem.Text = if failures[1] then tostring(failures[1].Reason) else "nothing changed"
			return false
		end
		view:Rebuild()
		if view.Explorer then
			view.Explorer.report("success", ("added attribute %s (%s) to %d object%s"):format(name, chosenType, changed, if changed == 1 then "" else "s"))
		end
		handle:Close("committed")
		return true
	end

	local addButton = Button.new({
		Name = "Add",
		Parent = frame,
		Origin = origin,
		Text = "Add",
		Icon = "add",
		Style = "accent",
		Position = UDim2.fromOffset(PAD, y),
		OnClick = add,
	})
	bin:Add(addButton)
	bin:Add(nameBox.Box:GetPropertyChangedSignal("Text"):Connect(function()
		problem.Text = ""
	end))
	bin:Add(valueBox.Box.FocusLost:Connect(function(enter)
		if enter then
			add()
		end
	end))

	handle = Overlay.open(frame, {
		Owner = opts.Owner,
		OnClose = function()
			bin:Clean()
		end,
	})
	handle.Kind = "attribute"
	handle.NameBox, handle.TypePicker, handle.ValueBox, handle.Problem = nameBox, typePicker, valueBox, problem
	handle.SetType = function(typeName: string)
		chosenType = typeName
		typePicker:SetValue(typeName, true)
	end
	handle.Add = add
	task.defer(function()
		if not handle.Closed then
			nameBox:Focus()
		end
	end)
	return handle
end

return AttributeForm
