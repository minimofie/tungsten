--[[
	Tungsten · base/explorer/filterpanel
	The popup under the explorer's filter button: groups to show (Parts,
	Scripts, …), extra classes to show, and classes to hide. Every change
	applies straight away; Clear turns the whole filter off.

		FilterPanel.open({ AnchorPos = pos, AnchorSize = size, Owner = button })
]]

local T = ...
local signal = T.import("base/signal")
local Theme = T.import("base/theme")
local Create = T.import("base/ui/create")
local Animate = T.import("base/ui/animate")
local Icons = T.import("base/data/icons")
local Classes = T.import("base/data/classes")
local Overlay = T.import("base/ui/overlay")
local Scroll = T.import("base/ui/components/scroll")
local Dropdown = T.import("base/ui/components/dropdown")
local TypePicker = T.import("base/ui/components/typepicker")
local Filter = T.import("base/explorer/filter")

local new = Create.new
local Sizes = Theme.Sizes

local WIDTH = 280
local PAD = 10
local ROW = 26
local MAX_HEIGHT = 440

local FilterPanel = {}

-- A small clickable row: check box (or icon) and text.
local function chip(parent: Instance, name: string, text: string, on: boolean, bin)
	local button = new("TextButton", {
		Name = name,
		Size = UDim2.new(0.5, -3, 0, ROW - 4),
		BackgroundTransparency = if on then 0 else 1,
		Theme = { BackgroundColor3 = if on then "AccentSoft" else "SurfaceHover" },
		Parent = parent,
	})
	Create.corner(button, 5)
	local box = new("Frame", {
		Name = "Box",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 6, 0.5, 0),
		Size = UDim2.fromOffset(13, 13),
		Theme = { BackgroundColor3 = if on then "Accent" else "Chrome" },
		Parent = button,
	})
	Create.corner(box, 3)
	Create.stroke(box, if on then "Accent" else "BorderStrong", 1, 0)
	if on then
		local check = Icons.new("check", 10, "OnAccent")
		check.AnchorPoint = Vector2.new(0.5, 0.5)
		check.Position = UDim2.fromScale(0.5, 0.5)
		check.Parent = box
	end
	new("TextLabel", {
		Name = "Text",
		Position = UDim2.fromOffset(25, 0),
		Size = UDim2.new(1, -28, 1, 0),
		Text = text,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Theme = { TextColor3 = if on then "Text" else "TextDim" },
		Parent = button,
	})
	Animate.hover(button, bin, function(hovered)
		if not on then
			button.BackgroundTransparency = if hovered then 0.3 else 1
		end
	end)
	return button
end

function FilterPanel.open(opts: { [string]: any })
	local origin = opts.Origin or "core"
	local size = Vector2.new(WIDTH, 200)
	local position = Overlay.place(size, opts.AnchorPos, opts.AnchorSize, { Side = "below", Gap = 4 })
	local frame = Overlay.panel(size, position)
	frame.Name = "FilterPanel"
	local bin = signal.bin()
	local rowBin = signal.bin()
	bin:Add(rowBin)
	local handle
	local picker = nil

	local scroll = Scroll.new({
		Name = "Body",
		Origin = origin,
		Position = UDim2.fromOffset(0, 0),
		Size = UDim2.fromScale(1, 1),
		Parent = frame,
	})
	bin:Add(scroll)
	Create.padding(scroll.Content, PAD, PAD, PAD, PAD)
	Create.list(scroll.Content, Enum.FillDirection.Vertical, 4)

	local order = 0
	local function row(name: string, height: number?)
		order += 1
		return new("Frame", {
			Name = name,
			Size = UDim2.new(1, 0, 0, height or ROW),
			LayoutOrder = order,
			BackgroundTransparency = 1,
			Parent = scroll.Content,
		})
	end
	local function heading(text: string, hint: string?)
		local holder = row("Heading_" .. text, 20)
		new("TextLabel", {
			Name = "Text",
			Size = UDim2.new(1, 0, 1, 0),
			Text = text,
			FontFace = Theme.Fonts.Medium,
			TextSize = Sizes.TextSmall,
			Theme = { TextColor3 = "TextMuted" },
			Parent = holder,
		})
		if hint then
			new("TextLabel", {
				Name = "Hint",
				Size = UDim2.new(1, 0, 1, 0),
				Text = hint,
				TextSize = Sizes.TextSmall,
				TextXAlignment = Enum.TextXAlignment.Right,
				Theme = { TextColor3 = "TextMuted" },
				Parent = holder,
			})
		end
	end

	-- A class row with a remove button.
	local function classRow(prefix: string, className: string, onRemove)
		local holder = row(prefix .. className, ROW - 2)
		local style = Classes.style(className)
		local icon = Icons.new(style.Icon, 14, style.Color)
		icon.AnchorPoint = Vector2.new(0, 0.5)
		icon.Position = UDim2.new(0, 6, 0.5, 0)
		icon.Parent = holder
		new("TextLabel", {
			Name = "Text",
			Position = UDim2.fromOffset(26, 0),
			Size = UDim2.new(1, -56, 1, 0),
			Text = className,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Theme = { TextColor3 = "Text" },
			Parent = holder,
		})
		local remove = new("TextButton", {
			Name = "Remove",
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -2, 0.5, 0),
			Size = UDim2.fromOffset(22, 22),
			BackgroundTransparency = 1,
			Theme = { BackgroundColor3 = "SurfaceHover" },
			Parent = holder,
		})
		Create.corner(remove, 5)
		local x = Icons.new("close", 12, "TextMuted")
		x.AnchorPoint = Vector2.new(0.5, 0.5)
		x.Position = UDim2.fromScale(0.5, 0.5)
		x.Parent = remove
		Animate.hover(remove, rowBin, function(hovered)
			remove.BackgroundTransparency = if hovered then 0 else 1
			Icons.tint(x, if hovered then "Danger" else "TextMuted", Animate.Fast)
		end)
		rowBin:Add(remove.Activated:Connect(onRemove))
	end

	-- "+ Add class" style button that opens a class list.
	local function addButton(name: string, text: string, onPick)
		local holder = row(name, ROW - 2)
		local button = new("TextButton", {
			Name = "Button",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Theme = { BackgroundColor3 = "SurfaceHover" },
			Parent = holder,
		})
		Create.corner(button, 5)
		local icon = Icons.new("add", 13, "Accent")
		icon.AnchorPoint = Vector2.new(0, 0.5)
		icon.Position = UDim2.new(0, 6, 0.5, 0)
		icon.Parent = button
		new("TextLabel", {
			Name = "Text",
			Position = UDim2.fromOffset(26, 0),
			Size = UDim2.new(1, -30, 1, 0),
			Text = text,
			Theme = { TextColor3 = "Accent" },
			Parent = button,
		})
		Animate.hover(button, rowBin, function(hovered)
			button.BackgroundTransparency = if hovered then 0.3 else 1
		end)
		rowBin:Add(button.Activated:Connect(function()
			if picker and not picker.Closed then
				picker:Close("replaced")
			end
			picker = Dropdown.popup({
				Origin = origin,
				Options = TypePicker.options("class", origin),
				AnchorPos = button.AbsolutePosition,
				AnchorSize = button.AbsoluteSize,
				Width = WIDTH - PAD * 2,
				Searchable = true,
				Owner = button,
				IsSelected = function()
					return false
				end,
				OnPick = function(option)
					onPick(option.Value)
				end,
			})
			handle.Picker = picker
		end))
		return button
	end

	local function render()
		rowBin:Clean()
		for _, child in scroll.Content:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		order = 0
		local state = Filter.get()

		-- Title + Clear
		local top = row("Top", 24)
		new("TextLabel", {
			Name = "Title",
			Size = UDim2.new(1, -70, 1, 0),
			Text = "Filter",
			FontFace = Theme.Fonts.Medium,
			Theme = { TextColor3 = "Text" },
			Parent = top,
		})
		local clear = new("TextButton", {
			Name = "Clear",
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.fromScale(1, 0),
			Size = UDim2.fromOffset(60, 22),
			BackgroundTransparency = 1,
			Theme = { BackgroundColor3 = "SurfaceHover" },
			Parent = top,
		})
		Create.corner(clear, 5)
		new("TextLabel", {
			Name = "Text",
			Size = UDim2.fromScale(1, 1),
			Text = "Clear",
			TextXAlignment = Enum.TextXAlignment.Center,
			Theme = { TextColor3 = if Filter.active() then "Accent" else "TextMuted" },
			Parent = clear,
		})
		Animate.hover(clear, rowBin, function(hovered)
			clear.BackgroundTransparency = if hovered then 0.3 else 1
		end)
		rowBin:Add(clear.Activated:Connect(function()
			Filter.clear()
		end))

		heading("Show only", "none ticked: everything")
		local groups = Filter.groups()
		local index = 1
		while index <= #groups do
			local line = row("Groups" .. index, ROW - 2)
			for column = 0, 1 do
				local group = groups[index + column]
				if group then
					local on = table.find(state.Only, group.Id) ~= nil
					local button = chip(line, "Group_" .. group.Id, group.Text, on, rowBin)
					button.Position = UDim2.new(column * 0.5, column * 3, 0, 0)
					rowBin:Add(button.Activated:Connect(function()
						Filter.toggleGroup(group.Id)
					end))
				end
			end
			index += 2
		end

		heading("Show classes", if #state.Classes == 0 then "and their subclasses" else nil)
		for _, className in state.Classes do
			classRow("Show_", className, function()
				Filter.showClass(className, false)
			end)
		end
		addButton("AddShow", "Add class", function(className)
			Filter.showClass(className, true)
		end)

		heading("Hide", if #state.Hide == 0 then "with what is inside" else nil)
		for _, className in state.Hide do
			classRow("Hide_", className, function()
				Filter.hideClass(className, false)
			end)
		end
		addButton("AddHide", "Hide class", function(className)
			Filter.hideClass(className, true)
		end)

		-- Fit the content (up to a limit; the rest scrolls).
		local height = PAD * 2
		local count = 0
		for _, child in scroll.Content:GetChildren() do
			if child:IsA("GuiObject") then
				height += child.Size.Y.Offset
				count += 1
			end
		end
		height += math.max(0, count - 1) * 4
		height = math.min(height, MAX_HEIGHT, Overlay.maxHeight())
		local placed = Overlay.place(Vector2.new(WIDTH, height), opts.AnchorPos, opts.AnchorSize, { Side = "below", Gap = 4 })
		frame.Position = UDim2.fromOffset(placed.X, placed.Y)
		frame.Size = UDim2.fromOffset(WIDTH, height)
	end

	bin:Add(Filter.Changed:Connect(function()
		task.defer(function()
			if handle and not handle.Closed then
				render()
			end
		end)
	end))

	handle = Overlay.open(frame, {
		Owner = opts.Owner,
		OnClose = function()
			if picker and not picker.Closed then
				picker:Close("parent")
			end
			bin:Clean()
		end,
	})
	handle.Kind = "filter"
	handle.Body = scroll.Content
	render()
	return handle
end

return FilterPanel
