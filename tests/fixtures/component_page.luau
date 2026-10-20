--[[
	test fixture · component page
	Offline test fixture: the former Component Test page (never shipped).
	Shows every UI component so each can be checked in-game.
]]

local T = ...
local Theme = T.import("base/theme")
local Scale = T.import("base/scale")
local Create = T.import("base/ui/create")
local Animate = T.import("base/ui/animate")
local Overlay = T.import("base/ui/overlay")
local Classes = T.import("base/data/classes")
local Categories = T.import("base/data/categories")
local Scroll = T.import("base/ui/components/scroll")
local Button = T.import("base/ui/components/button")
local Toggle = T.import("base/ui/components/toggle")
local Input = T.import("base/ui/components/input")
local Label = T.import("base/ui/components/label")
local Dropdown = T.import("base/ui/components/dropdown")
local TypePicker = T.import("base/ui/components/typepicker")
local ContextMenu = T.import("base/ui/components/contextmenu")
local List = T.import("base/ui/components/list")
local TextEditor = T.import("base/ui/components/texteditor")

local new = Create.new
local Sizes = Theme.Sizes

local SAMPLE = [==[
--!strict
-- Syntax colour sample: keywords, strings, numbers, comments, calls.
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Door = {}
Door.__index = Door

export type Door = typeof(setmetatable({} :: { Part: BasePart, Open: boolean }, Door))

function Door.new(part: BasePart): Door
	local self = setmetatable({ Part = part, Open = false }, Door)
	part.Touched:Connect(function(hit)
		local player = Players:GetPlayerFromCharacter(hit.Parent)
		if player and not self.Open then
			self:Toggle()
		end
	end)
	return self
end

function Door:Toggle()
	self.Open = not self.Open
	local goal = { CFrame = self.Part.CFrame * CFrame.Angles(0, math.rad(if self.Open then 90 else -90), 0) }
	TweenService:Create(self.Part, TweenInfo.new(0.35, Enum.EasingStyle.Quint), goal):Play()
	print(`door is now {if self.Open then "open" else "closed"}`, 0x1F, 1e-3, 2.5)
end

--[[ A long comment
     spanning several lines ]]
local message = [[a long
string over two lines]]
return Door
]==]

local function bigSample(lines: number): string
	local out = {}
	for index = 1, lines do
		out[index] = ("local value%d = Vector3.new(%d, %d, %d) -- line %d of a long file, with a fairly wide line to scroll sideways"):format(
			index, index, index * 2, index * 3, index
		)
	end
	return table.concat(out, "\n")
end

local function row(parent: Instance, order: number, height: number?): Frame
	local frame = new("Frame", {
		Name = "Row" .. order,
		Size = UDim2.new(1, 0, 0, height or Sizes.Control),
		BackgroundTransparency = 1,
		LayoutOrder = order,
		Parent = parent,
	})
	Create.list(frame, Enum.FillDirection.Horizontal, 8, { VerticalAlignment = Enum.VerticalAlignment.Center })
	return frame
end

----------------------------------------------------------------------
-- Pages
----------------------------------------------------------------------

local function buildBasics(page: Frame, status: (string) -> ())
	local scroll = Scroll.new({ Parent = page, Direction = "Y" })
	local content = scroll.Content
	Create.padding(content, 12, 16, 16, 14)
	Create.list(content, Enum.FillDirection.Vertical, 8)
	local order = 0
	local function nextOrder(): number
		order += 1
		return order
	end

	Label.section({ Parent = content, Text = "Buttons", LayoutOrder = nextOrder() })
	local buttons = row(content, nextOrder())
	Button.new({ Parent = buttons, Text = "Default", OnClick = function() status("clicked Default") end })
	Button.new({ Parent = buttons, Text = "Accent", Icon = "console", Style = "accent", OnClick = function() status("clicked Accent") end })
	Button.new({ Parent = buttons, Text = "Ghost", Style = "ghost", OnClick = function() status("clicked Ghost") end })
	Button.new({ Parent = buttons, Text = "Danger", Icon = "trash", Style = "danger", OnClick = function() status("clicked Danger") end })
	local disabled = Button.new({ Parent = buttons, Text = "Disabled", OnClick = function() status("this should never show") end })
	disabled:SetEnabled(false)

	Label.section({ Parent = content, Text = "Toggles", LayoutOrder = nextOrder() })
	local toggles = row(content, nextOrder())
	Toggle.new({ Parent = toggles, Text = "Option A", OnChanged = function(on) status("Option A " .. (if on then "on" else "off")) end })
	Toggle.new({ Parent = toggles, Text = "Option B", Value = true, OnChanged = function(on) status("Option B " .. (if on then "on" else "off")) end })

	Label.section({ Parent = content, Text = "Text and number inputs", LayoutOrder = nextOrder() })
	local inputs = row(content, nextOrder())
	Input.new({ Parent = inputs, Placeholder = "Type, then Enter…", Width = 190, OnCommit = function(text) status(("text: %q"):format(text)) end })
	Input.new({ Parent = inputs, Placeholder = "Search…", Icon = "search", Width = 170, OnTyping = function(text) status("typing: " .. text) end })

	local scaleRow = row(content, nextOrder())
	Label.new({ Parent = scaleRow, Text = "Window scale", Style = "dim", Size = UDim2.fromOffset(92, Sizes.Control), Wrap = false })
	local scaleBox
	Button.new({ Parent = scaleRow, Text = "−", Size = UDim2.fromOffset(Sizes.Control, Sizes.Control), OnClick = function()
		Scale.step(-Scale.KeyStep)
	end })
	scaleBox = Input.new({
		Parent = scaleRow, Numeric = true, Width = 70, Value = Scale.effective(),
		Min = Scale.Min, Max = Scale.Max, Step = Scale.Step, Decimals = 2,
		OnCommit = function(value)
			local applied = Scale.set(value)
			scaleBox:SetValue(applied)
			status(("scale %.2f (screen allows up to %.2f)"):format(applied, Scale.limit()))
		end,
	})
	Button.new({ Parent = scaleRow, Text = "+", Size = UDim2.fromOffset(Sizes.Control, Sizes.Control), OnClick = function()
		Scale.step(Scale.KeyStep)
	end })
	Label.new({ Parent = scaleRow, Text = "Up/Down arrows step while the box is focused", Style = "muted", Size = UDim2.fromOffset(260, Sizes.Control), Wrap = false })
	T.Bin:Add(Scale.Changed:Connect(function(value)
		scaleBox:SetValue(value)
	end))

	Label.section({ Parent = content, Text = "Dropdowns", LayoutOrder = nextOrder() })
	local drops = row(content, nextOrder())
	Dropdown.new({
		Parent = drops, Width = 150, Options = { "Low", "Medium", "High", "Ultra" }, Value = "Medium",
		OnChanged = function(value) status("single: " .. tostring(value)) end,
	})
	Dropdown.new({
		Parent = drops, Width = 170, Multi = true, Placeholder = "Pick several…",
		Options = { "Workspace", "Players", "Lighting", "ReplicatedStorage", "StarterGui", "SoundService", "Teams", "Chat" },
		Values = { "Workspace" },
		OnChanged = function(values) status("multi: " .. table.concat(values, ", ")) end,
	})
	local long = {}
	for index = 1, 250 do
		table.insert(long, { Value = index, Text = ("Option %03d"):format(index), Hint = if index % 10 == 0 then "tens" else nil })
	end
	Dropdown.new({
		Parent = drops, Width = 170, Options = long, Placeholder = "250 options (search)",
		OnChanged = function(value) status("long list: " .. tostring(value)) end,
	})

	Label.section({ Parent = content, Text = "Type pickers", LayoutOrder = nextOrder() })
	local pickers = row(content, nextOrder())
	TypePicker.new({ Parent = pickers, Kind = "class", Width = 170, Value = "Part", OnChanged = function(v) status("class: " .. tostring(v)) end })
	TypePicker.new({ Parent = pickers, Kind = "valueType", Width = 150, Value = "Vector3", OnChanged = function(v) status("value type: " .. tostring(v)) end })
	TypePicker.new({ Parent = pickers, Kind = "enum:Material", Width = 150, OnChanged = function(v) status("enum: " .. tostring(v)) end })
	local pickers2 = row(content, nextOrder())
	TypePicker.new({ Parent = pickers2, Kind = "creatable", Width = 170, Placeholder = "Insert object…", OnChanged = function(v) status("creatable: " .. tostring(v)) end })
	TypePicker.new({ Parent = pickers2, Kind = "isa:BasePart", Width = 170, Placeholder = "Any BasePart…", OnChanged = function(v) status("BasePart class: " .. tostring(v)) end })
	TypePicker.new({ Parent = pickers2, Kind = "attribute", Width = 150, Placeholder = "Attribute type…", OnChanged = function(v) status("attribute type: " .. tostring(v)) end })

	Label.section({ Parent = content, Text = "Labels", LayoutOrder = nextOrder() })
	Label.new({ Parent = content, LayoutOrder = nextOrder(), Text = "Body text. <b>Tags</b> show literally because labels are plain text." })
	Label.new({ Parent = content, LayoutOrder = nextOrder(), Style = "dim", Text = "Dim text for secondary information." })
	Label.new({ Parent = content, LayoutOrder = nextOrder(), Style = "mono", Text = "Mono: workspace.Baseplate.Size = Vector3.new(512, 20, 512)" })
end

local showGrid = true -- remembered between menu openings (demo of a check item)

local function sampleMenu(status: (string) -> (), extra: { any }?)
	local items = {
		{ Header = "Edit" },
		{ Text = "Copy", Icon = "copy", Shortcut = "Ctrl+C", Callback = function() status("menu: Copy") end },
		{ Text = "Cut", Icon = "cut", Shortcut = "Ctrl+X", Callback = function() status("menu: Cut") end },
		{ Text = "Rename", Icon = "edit", Shortcut = "F2", Callback = function() status("menu: Rename") end },
		{ Text = "Delete", Icon = "trash", Danger = true, Callback = function() status("menu: Delete") end },
		{ Text = "Disabled item", Disabled = true },
		{ Separator = true },
		{ Header = "More" },
		{ Text = "Insert object", Icon = "plugins", Items = function()
			local list = {}
			for _, name in { "Part", "Model", "Folder", "Script", "LocalScript", "ModuleScript", "RemoteEvent", "Sound" } do
				local style = Classes.style(name)
				table.insert(list, { Text = name, Icon = style.Icon, Callback = function() status("insert " .. name) end })
			end
			return list
		end },
		{ Text = "Nested", Items = {
			{ Text = "Level 2 · A", Callback = function() status("menu: 2A") end },
			{ Text = "Level 2 · More", Items = {
				{ Text = "Level 3 · A", Callback = function() status("menu: 3A") end },
				{ Text = "Level 3 · B", Callback = function() status("menu: 3B") end },
			} },
		} },
		{ Text = "Show grid", Checked = showGrid, Callback = function(item)
			showGrid = item.Checked
			status("menu: show grid " .. (if showGrid then "on" else "off"))
		end },
		{ Text = "Long submenu (40)", Items = function()
			local list = {}
			for index = 1, 40 do
				table.insert(list, { Text = "Item " .. index, Callback = function() status("long submenu item " .. index) end })
			end
			return list
		end },
	}
	for _, item in extra or {} do
		table.insert(items, item)
	end
	return items
end

local function buildList(page: Frame, status: (string) -> ())
	local top = new("Frame", {
		Name = "Toolbar",
		Size = UDim2.new(1, -24, 0, Sizes.Control),
		Position = UDim2.fromOffset(12, 10),
		BackgroundTransparency = 1,
		Parent = page,
	})
	Create.list(top, Enum.FillDirection.Horizontal, 8, { VerticalAlignment = Enum.VerticalAlignment.Center })
	local count = Label.new({ Parent = top, Text = "0 selected", Style = "dim", Size = UDim2.fromOffset(110, Sizes.Control), Wrap = false, LayoutOrder = 1 })

	local classes = Classes.list()
	local Types = T.import("base/types")
	-- Real values of several types, so the Value column shows type icons
	-- and edits parse into the right type.
	local samples = {
		function(i) return i * 37 % 1000 end,
		function(i) return "text " .. i end,
		function(i) return i % 2 == 0 end,
		function(i) return Vector3.new(i % 10, i % 7, i % 5) end,
		function(i) return Color3.fromRGB(i % 255, 150, 60) end,
		function(i) return UDim2.new(0, i % 300, 0, 24) end,
		function() return Enum.Material.Plastic end,
		function() return workspace end,
	}
	local items = {}
	for index = 1, 10000 do
		local class = classes[(index * 7) % #classes + 1]
		local value = samples[index % #samples + 1](index)
		table.insert(items, {
			Name = ("Item %05d"):format(index),
			Class = class,
			Kind = typeof(value),
			Value = value,
		})
	end

	local list
	list = List.new({
		Parent = page,
		Position = UDim2.fromOffset(12, 10 + Sizes.Control + 8),
		Size = UDim2.new(1, -24, 1, -(10 + Sizes.Control + 8 + 12)),
		Columns = {
			{ Key = "Name", Title = "Name", Flex = true, Min = 150 },
			{ Key = "Class", Title = "Class", Width = 170, Type = "class", Editable = true },
			{ Key = "Kind", Title = "Type", Width = 130, Type = "valueType", Editable = true },
			{ Key = "Value", Title = "Value", Width = 150, Type = "value", Mono = true, Editable = true },
		},
		-- Changing the type converts the value; a value keeps its row's type.
		OnEdit = function(item, key, value, old)
			if key == "Kind" then
				local ok, converted = Types.convert(item.Value, value)
				if not ok or converted == nil then
					converted = Types.default(value)
				end
				if converted == nil and value ~= "nil" then
					return false, ("no %s value to start from"):format(value)
				end
				item.Value = converted
			elseif key == "Value" then
				item.Kind = typeof(value)
			end
			status(("%s: %s -> %s"):format(key, Types.display(old), Types.display(value)))
			return true
		end,
		OnSelectionChanged = function(selected)
			count.Text = ("%d selected"):format(#selected)
		end,
		OnActivate = function(item)
			status("double-clicked " .. item.Name)
		end,
		OnContextMenu = function(selected, item, point)
			local n = #selected
			local menu = {
				{ Header = if n > 0 then ("%d selected"):format(n) else "List" },
				{ Text = "Copy names", Icon = "copy", Disabled = n == 0, Callback = function()
					local names = {}
					for _, entry in selected do
						table.insert(names, entry.Name)
					end
					pcall(setclipboard, table.concat(names, "\n"))
					status(("copied %d names"):format(n))
				end },
				{ Text = "Set type", Disabled = n == 0, Items = function()
					local options = {}
					for _, typeName in { "number", "string", "boolean", "Vector3", "CFrame", "Color3", "Instance" } do
						local style = Categories.valueType(typeName)
						table.insert(options, { Text = typeName, Icon = style.Icon, Callback = function()
							-- Same path as editing the Type cell: converts each row's value.
							list:ApplyEdit(selected[1], "Kind", typeName)
							status(("set %d rows to %s"):format(n, typeName))
						end })
					end
					return options
				end },
				{ Separator = true },
				{ Text = "Select all", Shortcut = "", Callback = function() list:SelectAll() end },
				{ Text = "Remove", Icon = "trash", Danger = true, Disabled = n == 0, Callback = function()
					local keep = {}
					local drop = {}
					for _, entry in selected do
						drop[entry] = true
					end
					for _, entry in list:GetItems() do
						if not drop[entry] then
							table.insert(keep, entry)
						end
					end
					list:SetItems(keep)
					status(("removed %d rows"):format(n))
				end },
			}
			-- Edit entries for the editable columns, right after the header.
			for offset, entry in list:EditMenuItems(item) do
				table.insert(menu, 1 + offset, entry)
			end
			ContextMenu.open(menu, { Position = point })
		end,
	})
	list:SetItems(items)

	Button.new({ Parent = top, Text = "Select all", Style = "ghost", LayoutOrder = 2, OnClick = function() list:SelectAll() end })
	Button.new({ Parent = top, Text = "Clear", Style = "ghost", LayoutOrder = 3, OnClick = function() list:ClearSelection() end })
	Button.new({ Parent = top, Text = "Reset rows", Style = "ghost", LayoutOrder = 4, OnClick = function()
		list:SetItems(items)
		status("10,000 rows restored")
	end })
end

local function buildMenus(page: Frame, status: (string) -> ())
	local holder = new("Frame", {
		Name = "Holder",
		Size = UDim2.new(1, -24, 1, -20),
		Position = UDim2.fromOffset(12, 10),
		BackgroundTransparency = 1,
		Parent = page,
	})
	Create.list(holder, Enum.FillDirection.Vertical, 8)
	Label.new({
		Parent = holder, LayoutOrder = 1, Style = "dim",
		Text = "Right-click the area below to open a menu at the mouse. Drag the window to a screen edge and right-click near it: the menu flips and stays on screen. Menus close on Escape, an outside click, dragging or minimizing the window, and switching tabs.",
	})
	local buttons = row(holder, 2)
	local openButton
	openButton = Button.new({ Parent = buttons, Text = "Open menu", Icon = "chevron_down", OnClick = function(self)
		if Overlay.justClosed(openButton) then
			return -- this click just closed it
		end
		local button = self.Instance
		ContextMenu.open(sampleMenu(status), { AnchorPos = button.AbsolutePosition, AnchorSize = button.AbsoluteSize, Side = "below", Owner = openButton })
	end })
	Button.new({ Parent = buttons, Text = "Very long menu (80)", OnClick = function()
		local items = {}
		for index = 1, 80 do
			table.insert(items, { Text = "Entry " .. index, Callback = function() status("long menu entry " .. index) end })
		end
		ContextMenu.open(items)
	end })
	Button.new({ Parent = buttons, Text = "Empty menu", Style = "ghost", OnClick = function()
		ContextMenu.open({}, { EmptyText = "No plugin actions for Part" })
	end })

	local area = new("Frame", {
		Name = "RightClickArea",
		Size = UDim2.new(1, 0, 1, -110),
		LayoutOrder = 3,
		Active = true,
		Theme = { BackgroundColor3 = "Chrome" },
		Parent = holder,
	})
	Create.corner(area, Sizes.RadiusSmall)
	Create.stroke(area, "Border", 1, 0)
	new("TextLabel", {
		Name = "Hint",
		Size = UDim2.fromScale(1, 1),
		Text = "Right-click anywhere here",
		TextXAlignment = Enum.TextXAlignment.Center,
		Theme = { TextColor3 = "TextMuted" },
		Parent = area,
	})
	area.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			ContextMenu.open(sampleMenu(status), { Position = Overlay.pointOf(input) })
		end
	end)
end

local function buildEditor(page: Frame, status: (string) -> ())
	local top = new("Frame", {
		Name = "Toolbar",
		Size = UDim2.new(1, -24, 0, Sizes.Control),
		Position = UDim2.fromOffset(12, 10),
		BackgroundTransparency = 1,
		Parent = page,
	})
	Create.list(top, Enum.FillDirection.Horizontal, 8, { VerticalAlignment = Enum.VerticalAlignment.Center })

	local editor = TextEditor.new({
		Parent = page,
		Position = UDim2.fromOffset(12, 10 + Sizes.Control + 8),
		Size = UDim2.new(1, -24, 1, -(10 + Sizes.Control + 8 + 12)),
		Text = SAMPLE,
	})
	Toggle.new({ Parent = top, Text = "Read-only", LayoutOrder = 1, OnChanged = function(on)
		editor:SetReadOnly(on)
		status("editor read-only " .. (if on then "on" else "off"))
	end })
	Button.new({ Parent = top, Text = "Sample", Style = "ghost", LayoutOrder = 2, OnClick = function()
		editor:SetText(SAMPLE)
	end })
	Button.new({ Parent = top, Text = "5,000 lines", Style = "ghost", LayoutOrder = 3, OnClick = function()
		local started = os.clock()
		editor:SetText(bigSample(5000))
		status(("loaded 5,000 lines in %.0f ms"):format((os.clock() - started) * 1000))
	end })
	Button.new({ Parent = top, Text = "Copy all", Icon = "copy", Style = "ghost", LayoutOrder = 4, OnClick = function()
		pcall(setclipboard, editor:GetText())
		status("copied the whole text")
	end })
	local position = Label.new({ Parent = top, Text = "", Style = "muted", Size = UDim2.fromOffset(160, Sizes.Control), Wrap = false, LayoutOrder = 5 })
	local function showPosition()
		position.Text = ("Ln %d, Col %d · %d lines"):format(editor.CursorLine, editor.CursorCol + 1, #editor.Lines)
	end
	T.Bin:Add(T.import("base/services").RunService.Heartbeat:Connect(function()
		if page.Visible then
			showPosition()
		end
	end))
end

local function buildScroll(page: Frame)
	local holder = new("Frame", {
		Name = "Holder",
		Size = UDim2.new(1, -24, 1, -20),
		Position = UDim2.fromOffset(12, 10),
		BackgroundTransparency = 1,
		Parent = page,
	})
	Label.new({
		Parent = holder, Style = "dim", Size = UDim2.new(1, 0, 0, 34),
		Text = "Wheel scrolls down; Shift+wheel scrolls sideways; drag the bars or click their tracks. The strip below only scrolls sideways (plain wheel works there).",
	})

	local strip = Scroll.new({ Parent = holder, Direction = "X", Position = UDim2.fromOffset(0, 40), Size = UDim2.new(1, 0, 0, 40), Background = "Chrome" })
	Create.list(strip.Content, Enum.FillDirection.Horizontal, 6, { VerticalAlignment = Enum.VerticalAlignment.Center })
	Create.padding(strip.Content, 6, 8, 10, 8)
	for index = 1, 40 do
		local chip = new("TextLabel", {
			Name = "Chip" .. index,
			Text = "Chip " .. index,
			Size = UDim2.fromOffset(70, 22),
			TextXAlignment = Enum.TextXAlignment.Center,
			LayoutOrder = index,
			Theme = { BackgroundColor3 = "SurfaceHover" },
			BackgroundTransparency = 0,
			Parent = strip.Content,
		})
		Create.corner(chip, 11)
	end

	local grid = Scroll.new({ Parent = holder, Direction = "XY", Position = UDim2.fromOffset(0, 88), Size = UDim2.new(1, 0, 1, -88), Background = "Chrome" })
	local layout = new("UIGridLayout", {
		CellSize = UDim2.fromOffset(96, 40),
		CellPadding = UDim2.fromOffset(6, 6),
		FillDirectionMaxCells = 16,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = grid.Content,
	})
	Create.padding(grid.Content, 8, 8, 8, 8)
	for index = 1, 16 * 30 do
		local tile = new("TextLabel", {
			Name = "Tile" .. index,
			Text = ("%d, %d"):format((index - 1) % 16 + 1, (index - 1) // 16 + 1),
			TextXAlignment = Enum.TextXAlignment.Center,
			LayoutOrder = index,
			BackgroundTransparency = 0,
			Theme = { BackgroundColor3 = if index % 2 == 0 then "Surface" else "SurfaceHover", TextColor3 = "TextDim" },
			Parent = grid.Content,
		})
		Create.corner(tile, 4)
	end
	local _ = layout
end

----------------------------------------------------------------------
-- Tab
----------------------------------------------------------------------

local SECTIONS = {
	{ Id = "basics", Title = "Basics", Build = buildBasics },
	{ Id = "list", Title = "List", Build = buildList },
	{ Id = "menus", Title = "Menus", Build = buildMenus },
	{ Id = "editor", Title = "Editor", Build = buildEditor },
	{ Id = "scroll", Title = "Scroll", Build = buildScroll },
}

return {
	Id = "componenttest",
	Title = "Component Test",
	Icon = "dummy",
	Order = 50,
	Builtin = true,
	Build = function(page)
		-- Section switcher
		local bar = new("Frame", {
			Name = "Sections",
			Size = UDim2.new(1, 0, 0, 36),
			Theme = { BackgroundColor3 = "Background" },
			Parent = page,
		})
		new("Frame", { -- outside the bar: the bar's list layout would move it
			Name = "SectionLine",
			Position = UDim2.fromOffset(0, 35),
			Size = UDim2.new(1, 0, 0, 1),
			Theme = { BackgroundColor3 = "Border" },
			Parent = page,
		})
		Create.padding(bar, 0, 12, 0, 12)
		Create.list(bar, Enum.FillDirection.Horizontal, 4, { VerticalAlignment = Enum.VerticalAlignment.Center })

		local statusLabel = new("TextLabel", {
			Name = "Status",
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -12, 0.5, 0),
			Size = UDim2.fromOffset(0, 20),
			AutomaticSize = Enum.AutomaticSize.X,
			TextSize = Sizes.TextSmall,
			TextXAlignment = Enum.TextXAlignment.Right,
			Theme = { TextColor3 = "TextMuted" },
			Text = "",
			Parent = page,
		})
		statusLabel.Position = UDim2.new(1, -12, 0, 18)
		local function status(text: string)
			statusLabel.Text = text
			T.Log.debug("componenttest", text)
		end

		local body = new("Frame", {
			Name = "Body",
			Position = UDim2.fromOffset(0, 36),
			Size = UDim2.new(1, 0, 1, -36),
			BackgroundTransparency = 1,
			ClipsDescendants = true,
			Parent = page,
		})

		local pages, tabs = {}, {}
		local current = nil
		local function select(id: string)
			if current == id then
				return
			end
			current = id
			for _, section in SECTIONS do
				local active = section.Id == id
				local tab = tabs[section.Id]
				Theme.bind(tab, "BackgroundColor3", if active then "AccentSoft" else "SurfaceHover", Animate.Fast)
				Animate.tween(tab, { BackgroundTransparency = if active then 0 else 1 }, Animate.Fast)
				Theme.bind(tab, "TextColor3", if active then "Accent" else "TextDim", Animate.Fast)
				if active and not pages[section.Id] then
					local sub = new("Frame", {
						Name = section.Id,
						Size = UDim2.fromScale(1, 1),
						BackgroundTransparency = 1,
						Parent = body,
					})
					pages[section.Id] = sub
					local ok, err = xpcall(section.Build, debug.traceback, sub, status)
					if not ok then
						T.Log.error("componenttest", ("section '%s' failed:\n%s"):format(section.Id, tostring(err)))
						Create.placeholder(sub, section.Title, { "This section failed to build.", "Details are in the newest log file." })
					end
				end
				if pages[section.Id] then
					pages[section.Id].Visible = active
				end
			end
			Overlay.closeAll("section")
		end

		for index, section in SECTIONS do
			local tab = new("TextButton", {
				Name = section.Id,
				Text = section.Title,
				FontFace = Theme.Fonts.Medium,
				Size = UDim2.fromOffset(0, 26),
				AutomaticSize = Enum.AutomaticSize.X,
				LayoutOrder = index,
				BackgroundTransparency = 1,
				Theme = { BackgroundColor3 = "SurfaceHover", TextColor3 = "TextDim" },
				Parent = bar,
			})
			Create.corner(tab, Sizes.RadiusSmall)
			Create.padding(tab, 0, 10, 0, 10)
			tabs[section.Id] = tab
			tab.Activated:Connect(function()
				select(section.Id)
			end)
		end
		select("basics")
	end,
}
