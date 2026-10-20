--[[
	Tungsten · plugins/manager
	The Plugins tab: the plugin list on the left, the selected entry's
	settings on the right.

	The first entry is always "tungsten": not a plugin, but where the
	program's own settings and preferences live (base/preferences). It has
	an accent outline like the window and the pill, and it adds no tab.

	Every plugin the host (base/plugins) knows gets a card: icon, name,
	version, a line about it and a state chip (on / off / failed /
	problem). The list follows the host as it changes. Cards can be
	multi-selected (Ctrl / Shift + click); right-click opens the
	"plugins.entry" menu (Turn on, Turn off, Reload, Open its tab,
	Documentation, Copy id, Reset its settings). A search box shows once
	there are more than a few plugins. The Plugins tab's badge counts the
	plugins that didn't start.

		Manager.attachHost(T.Plugins)   -- the loader, once plugins started
		Manager.addEntry({ Id, Name, Note?, Icon?, Version?, Author?,
			Description?, Settings = api.settings, Context = api })
		                                -- a card of your own (tests, tools)
		Manager.removeEntry(id) ; Manager.select(id) ; Manager.selected() -> ids
	A settings store is anything with get / set / reset / items / Changed
	(base/api's settingsStore; the tungsten entry wraps base/preferences).
]]

local T = ...
local signal = T.import("base/signal")
local Theme = T.import("base/theme")
local Create = T.import("base/ui/create")
local Animate = T.import("base/ui/animate")
local Icons = T.import("base/data/icons")
local Scroll = T.import("base/ui/components/scroll")
local Toggle = T.import("base/ui/components/toggle")
local Input = T.import("base/ui/components/input")
local Dropdown = T.import("base/ui/components/dropdown")
local Button = T.import("base/ui/components/button")
local ColorPicker = T.import("base/ui/components/colorpicker")
local Preferences = T.import("base/preferences")
local Services = T.import("base/services")
local Overlay = T.import("base/ui/overlay")

local new = Create.new
local Sizes = Theme.Sizes

local LIST_WIDTH = 220
local PAD = 12
local ROW = 40
local ENTRY = 56
local SEARCH_FROM = 5 -- the search box shows from this many plugins
local STATE_COLOR = { on = "Success", off = "TextMuted", failed = "Danger", problem = "Danger" }

local Manager = {}
Manager.Entries = {} -- id -> { Frame, Select }
Manager.Controls = {} -- setting id on the shown page -> { Kind, Update(value) }
Manager.Selected = nil
Manager.Pending = {} -- id -> entry spec (shown whenever the tab is built)
Manager.Multi = {} -- id -> true: the cards selected together (multi-select)
Manager.Query = "" -- the search box text
local host = nil -- base/plugins, once attached
local anchorId = nil -- where a Shift+click range starts

local function keyDown(...): boolean
	for _, key in { ... } do
		if Services.UserInputService:IsKeyDown(key) then
			return true
		end
	end
	return false
end

-- The tungsten entry's store: the program's own preferences.
local preferenceStore = {
	get = Preferences.get,
	set = Preferences.set,
	reset = Preferences.reset,
	Changed = Preferences.Changed,
}
local pageConnection = nil -- the shown store's Changed

local function colorOf(value): Color3
	if type(value) == "table" and #value == 3 then
		return Color3.fromRGB(value[1], value[2], value[3])
	end
	return Theme.Colors.Accent
end

-- One entry in the plugin list. `emphasis` gives it the accent outline.
local function entryCard(list: Frame, spec)
	local card = new("TextButton", {
		Name = "Entry_" .. spec.Id,
		Size = UDim2.new(1, 0, 0, ENTRY),
		LayoutOrder = spec.Order or 10,
		Theme = { BackgroundColor3 = "Surface" },
		Parent = list,
	})
	Create.corner(card, Sizes.Radius)
	local stroke = Create.stroke(card, if spec.Emphasis then "Accent" else "Border", if spec.Emphasis then 1.5 else 1, if spec.Emphasis then 0.15 else 0)
	local icon = Icons.new(spec.Icon, 24, if spec.Emphasis then "Accent" else "TextDim")
	icon.AnchorPoint = Vector2.new(0, 0.5)
	icon.Position = UDim2.new(0, 12, 0.5, 0)
	icon.Parent = card
	-- state chip (plugins only): on / off / failed / problem
	local chip
	if spec.State then
		local chipText = spec.State
		chip = new("TextLabel", {
			Name = "State",
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -8, 0, 10),
			Size = UDim2.fromOffset(math.ceil(Create.textWidth(chipText, Sizes.TextSmall)) + 12, 16),
			Text = chipText,
			TextSize = Sizes.TextSmall,
			TextXAlignment = Enum.TextXAlignment.Center,
			BackgroundTransparency = 0.82,
			Theme = { TextColor3 = STATE_COLOR[chipText] or "TextMuted", BackgroundColor3 = STATE_COLOR[chipText] or "TextMuted" },
			Parent = card,
		})
		Create.corner(chip, 8)
	end
	new("TextLabel", {
		Name = "Name",
		Position = UDim2.fromOffset(46, 9),
		Size = UDim2.new(1, -56 - (if chip then chip.Size.X.Offset + 6 else 0), 0, 20),
		Text = spec.Name,
		TextTruncate = Enum.TextTruncate.AtEnd,
		FontFace = Theme.Fonts.Bold,
		TextSize = Sizes.Text + 2,
		Theme = { TextColor3 = if spec.Emphasis then "Accent" else "Text" },
		Parent = card,
	})
	new("TextLabel", {
		Name = "Note",
		Position = UDim2.fromOffset(46, 29),
		Size = UDim2.new(1, -56, 0, 16),
		Text = spec.Note or "",
		TextSize = Sizes.TextSmall,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Theme = { TextColor3 = "TextMuted" },
		Parent = card,
	})
	local entry = { Frame = card, Stroke = stroke, Spec = spec, Hovered = false, Chip = chip }
	local function restyle()
		local selected = Manager.Selected == spec.Id or Manager.Multi[spec.Id] == true
		Theme.bind(card, "BackgroundColor3", if selected then "AccentSoft" elseif entry.Hovered then "SurfaceHover" else "Surface", Animate.Fast)
	end
	entry.Restyle = restyle
	Animate.hover(card, T.Bin, function(hovered)
		entry.Hovered = hovered
		restyle()
	end)
	card.Activated:Connect(function()
		Manager.click(spec.Id, keyDown(Enum.KeyCode.LeftControl, Enum.KeyCode.RightControl), keyDown(Enum.KeyCode.LeftShift, Enum.KeyCode.RightShift))
	end)
	card.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			Manager.openMenu(spec.Id, Overlay.pointOf(input))
		end
	end)
	Manager.Entries[spec.Id] = entry
	return entry
end

-- A settings row: label + hint on the left, the control on the right.
local function settingRow(parent: Frame, order: number, entry, store)
	store = store or preferenceStore
	local row = new("Frame", {
		Name = "Pref_" .. entry.Id,
		Size = UDim2.new(1, 0, 0, ROW),
		LayoutOrder = order,
		BackgroundTransparency = 1,
		Parent = parent,
	})
	new("TextLabel", {
		Name = "Label",
		Position = UDim2.fromOffset(0, if entry.Hint then 3 else 0),
		Size = UDim2.new(1, -220, 0, if entry.Hint then 20 else ROW),
		Text = entry.Text,
		Theme = { TextColor3 = if entry.Danger then "Danger" else "Text" },
		Parent = row,
	})
	if entry.Hint then
		new("TextLabel", {
			Name = "Hint",
			Position = UDim2.fromOffset(0, 21),
			Size = UDim2.new(1, -220, 0, 16),
			Text = entry.Hint,
			TextSize = Sizes.TextSmall,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Theme = { TextColor3 = "TextMuted" },
			Parent = row,
		})
	end
	local control = { Kind = entry.Kind }
	local value = store.get(entry.Id)
	if entry.Kind == "toggle" then
		local toggle = Toggle.new({
			Name = "Control",
			Parent = row,
			Position = UDim2.new(1, -34, 0.5, -Sizes.Control / 2),
			Value = value ~= false,
			OnChanged = function(on)
				store.set(entry.Id, on)
			end,
		})
		control.Widget = toggle
		control.Update = function(v)
			toggle:Set(v ~= false, true)
		end
	elseif entry.Kind == "number" then
		local box = Input.new({
			Name = "Control",
			Parent = row,
			Numeric = true,
			Value = tonumber(value) or 0,
			Min = entry.Min,
			Max = entry.Max,
			Step = entry.Step,
			Decimals = entry.Decimals,
			Width = 90,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, 0, 0.5, 0),
			OnCommit = function(number)
				store.set(entry.Id, number)
				control.Update(store.get(entry.Id))
			end,
		})
		control.Widget = box
		control.Update = function(v)
			if tonumber(v) then
				box:SetValue(tonumber(v) :: number)
			end
		end
	elseif entry.Kind == "stepper" then
		-- [ − ]  100%  [ + ]  Reset
		local holder = new("Frame", {
			Name = "Control",
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, 0, 0.5, 0),
			Size = UDim2.fromOffset(0, Sizes.Control),
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundTransparency = 1,
			Parent = row,
		})
		local layout = Create.list(holder, Enum.FillDirection.Horizontal, 6, { VerticalAlignment = Enum.VerticalAlignment.Center })
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		local valueLabel
		local down, up
		local function refresh()
			local current = store.get(entry.Id)
			valueLabel.Text = if entry.Format then entry.Format(current) else tostring(current)
			down:SetEnabled(entry.CanStep == nil or entry.CanStep(-1))
			up:SetEnabled(entry.CanStep == nil or entry.CanStep(1))
		end
		down = Button.new({
			Name = "Smaller",
			Parent = holder,
			Text = "−",
			Size = UDim2.fromOffset(Sizes.Control + 4, Sizes.Control),
			LayoutOrder = 1,
			OnClick = function()
				entry.Step(-1)
				refresh()
			end,
		})
		valueLabel = new("TextLabel", {
			Name = "Value",
			Size = UDim2.fromOffset(52, Sizes.Control),
			LayoutOrder = 2,
			TextXAlignment = Enum.TextXAlignment.Center,
			FontFace = Theme.Fonts.Mono,
			Theme = { TextColor3 = "Text" },
			Parent = holder,
		})
		up = Button.new({
			Name = "Bigger",
			Parent = holder,
			Text = "+",
			Size = UDim2.fromOffset(Sizes.Control + 4, Sizes.Control),
			LayoutOrder = 3,
			OnClick = function()
				entry.Step(1)
				refresh()
			end,
		})
		Button.new({
			Name = "Reset",
			Parent = holder,
			Text = "Reset",
			Style = "ghost",
			LayoutOrder = 4,
			OnClick = function()
				store.reset(entry.Id)
				refresh()
			end,
		})
		refresh()
		control.Widget = { Down = down, Up = up, Label = valueLabel }
		control.Update = function()
			refresh()
		end
		-- the screen size can change what fits
		if entry.Id == "scale" then
			T.Bin:Add(T.import("base/scale").Changed:Connect(function()
				if valueLabel.Parent then
					refresh()
				end
			end))
		end
	elseif entry.Kind == "choice" then
		local dropdown = Dropdown.new({
			Name = "Control",
			Parent = row,
			Options = entry.Options,
			Value = value,
			Width = 170,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, 0, 0.5, 0),
			OnChanged = function(choice)
				store.set(entry.Id, choice)
			end,
		})
		control.Widget = dropdown
		control.Update = function(v)
			dropdown:SetValue(v, true)
		end
	elseif entry.Kind == "color" then
		local holder = new("Frame", {
			Name = "Control",
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, 0, 0.5, 0),
			Size = UDim2.fromOffset(0, Sizes.Control),
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundTransparency = 1,
			Parent = row,
		})
		local layout = Create.list(holder, Enum.FillDirection.Horizontal, 6, { VerticalAlignment = Enum.VerticalAlignment.Center })
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		local swatch = new("TextButton", {
			Name = "Swatch",
			Size = UDim2.fromOffset(48, Sizes.Control),
			LayoutOrder = 1,
			BackgroundColor3 = colorOf(value),
			Parent = holder,
		})
		Create.corner(swatch, Sizes.RadiusSmall)
		Create.stroke(swatch, "BorderStrong", 1, 0)
		local function toSetting(color: Color3)
			return { math.floor(color.R * 255 + 0.5), math.floor(color.G * 255 + 0.5), math.floor(color.B * 255 + 0.5) }
		end
		swatch.Activated:Connect(function()
			ColorPicker.open({
				AnchorPos = swatch.AbsolutePosition,
				AnchorSize = swatch.AbsoluteSize,
				Value = swatch.BackgroundColor3,
				Owner = swatch,
				OnChange = function(color)
					store.set(entry.Id, toSetting(color))
				end,
			})
		end)
		Button.new({
			Name = "Reset",
			Parent = holder,
			Text = "Reset",
			Style = "ghost",
			LayoutOrder = 2,
			OnClick = function()
				store.reset(entry.Id)
			end,
		})
		control.Widget = swatch
		control.Update = function(v)
			swatch.BackgroundColor3 = colorOf(v)
		end
	elseif entry.Kind == "action" then
		local button = Button.new({
			Name = "Control",
			Parent = row,
			Text = entry.Button or entry.Text,
			Style = if entry.Danger then "danger" else "default",
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, 0, 0.5, 0),
			OnClick = function()
				local ok, err = pcall(entry.Run, store.Context)
				if not ok then
					-- a plugin's action fails under its name; Tungsten's own go to the log
					local owner = if type(store.Context) == "table" then store.Context.Id else nil
					T.import("console/reporter").ownerFault(owner, ("'%s'"):format(tostring(entry.Text)), err)
				end
			end,
		})
		control.Widget = button
	end
	Manager.Controls[entry.Id] = control
	return row
end

-- The settings row for other pages (Page.field): the row and its control,
-- without taking the place of a row on the Plugins tab's own page.
function Manager.settingRow(parent: Instance, order: number, item, store)
	local prior = Manager.Controls[item.Id]
	local row = settingRow(parent :: Frame, order, item, store)
	local control = Manager.Controls[item.Id]
	Manager.Controls[item.Id] = prior
	return row, control
end

-- A page: the header, a line, then the rows in a scroll. `groups` is
-- { { Title?, Items = { item } } }; `store` reads and writes the values.
local function buildPage(panel: Frame, spec, groups, store, footer: string?)
	for _, child in panel:GetChildren() do
		child:Destroy()
	end
	table.clear(Manager.Controls)
	if pageConnection then
		pageConnection:Disconnect()
		pageConnection = nil
	end
	local header = new("Frame", {
		Name = "Header",
		Size = UDim2.new(1, 0, 0, 44),
		BackgroundTransparency = 1,
		Parent = panel,
	})
	local icon = Icons.new(spec.Icon or "plugins", 22, "Accent")
	icon.AnchorPoint = Vector2.new(0, 0.5)
	icon.Position = UDim2.new(0, PAD, 0.5, 0)
	icon.Parent = header
	new("TextLabel", {
		Name = "Title",
		Position = UDim2.fromOffset(PAD + 30, 0),
		Size = UDim2.new(1, -(PAD * 2 + 30), 1, 0),
		Text = spec.Title,
		FontFace = Theme.Fonts.Bold,
		TextSize = Sizes.Title,
		Theme = { TextColor3 = "Text" },
		Parent = header,
	})
	new("Frame", {
		Name = "Line",
		Position = UDim2.fromOffset(0, 44),
		Size = UDim2.new(1, 0, 0, 1),
		Theme = { BackgroundColor3 = "Border" },
		Parent = panel,
	})
	local scroll = Scroll.new({
		Name = "Settings",
		Direction = "Y",
		Position = UDim2.fromOffset(0, 45),
		Size = UDim2.new(1, 0, 1, -45),
		Parent = panel,
	})
	Manager.Scroll = scroll
	local content = scroll.Content
	Create.padding(content, 8, PAD + 4, 16, PAD)
	local layout = Create.list(content, Enum.FillDirection.Vertical, 2)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	local order = 0
	local function note(name: string, text: string, height: number)
		order += 1
		new("TextLabel", {
			Name = name,
			Size = UDim2.new(1, 0, 0, height),
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = order,
			Text = text,
			TextWrapped = true,
			TextSize = Sizes.TextSmall,
			TextYAlignment = Enum.TextYAlignment.Bottom,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Theme = { TextColor3 = "TextMuted" },
			Parent = content,
		})
	end
	if spec.Description then
		note("Description", spec.Description, 20)
	end
	for _, group in groups do
		if group.Title then
			order += 1
			new("TextLabel", {
				Name = "Group_" .. group.Title,
				Size = UDim2.new(1, 0, 0, 28),
				LayoutOrder = order,
				Text = string.upper(group.Title),
				FontFace = Theme.Fonts.Bold,
				TextSize = Sizes.TextSmall,
				TextYAlignment = Enum.TextYAlignment.Bottom,
				Theme = { TextColor3 = "Accent" },
				Parent = content,
			})
		end
		for _, entry in group.Items do
			order += 1
			settingRow(content, order, entry, store)
		end
	end
	if footer then
		note("Footer", footer, 34)
	end
	-- Values changed elsewhere (commands, menus, the plugin itself) show here too.
	if store.Changed then
		pageConnection = store.Changed:Connect(function(id, value)
			local control = Manager.Controls[id]
			if control and control.Update then
				local current = store.get(id)
				control.Update(if current ~= nil then current else value)
			end
		end)
	end
end

-- The tungsten entry's page: every preference, grouped.
local function buildSettings(panel: Frame)
	buildPage(
		panel,
		{ Title = "tungsten · settings", Icon = Icons.Brand },
		Preferences.groups(),
		preferenceStore,
		("tungsten (unified) v%s · settings are saved in %s"):format(T.Version or "?", T.Settings.Path)
	)
end

local NO_STORE = {
	get = function() end,
	set = function()
		return false
	end,
	reset = function()
		return false
	end,
}

----------------------------------------------------------------------
-- A plugin's page (plugins the host knows)
----------------------------------------------------------------------

-- What a running plugin has registered, counted from the registries by
-- owner (so it is always true).
local function addsOf(id: string): { { Key: string, Text: string } }
	local out = {}
	local function add(key: string, count: number, one: string, many: string)
		if count > 0 then
			table.insert(out, { Key = key, Text = ("%d %s"):format(count, if count == 1 then one else many) })
		end
	end
	local tabs = 0
	for _, tab in T.Registry.allTabs() do
		if tab.Owner == id then
			tabs += 1
		end
	end
	add("tabs", tabs, "tab", "tabs")
	local commands = 0
	local okCommands, Commands = pcall(T.import, "console/commands")
	if okCommands then
		for _, command in Commands.list() do
			if command.Owner == id then
				commands += 1
			end
		end
	end
	add("commands", commands, "command", "commands")
	local functions, entries = 0, 0
	for _, menuId in T.Menus.list() do
		for _, entry in T.Menus.entries(menuId) do
			if entry.Owner == id then
				if menuId == "explorer.function" then
					functions += 1
				else
					entries += 1
				end
			end
		end
	end
	add("functions", functions, "explorer function", "explorer functions")
	add("menus", entries, "menu entry", "menu entries")
	local topics = 0
	for _, topic in T.Docs.topics(true) do
		if topic.Owner == id then
			topics += 1
		end
	end
	add("docs", topics, "docs topic", "docs topics")
	local variables = 0
	for _, entry in T.Variables.list() do
		if entry.Source == id then
			variables += 1
		end
	end
	add("variables", variables, "variable", "variables")
	return out
end

local function chip(parent: Instance, name: string, text: string, color: string, order: number)
	local label = new("TextLabel", {
		Name = name,
		Size = UDim2.fromOffset(math.ceil(Create.textWidth(text, Sizes.TextSmall)) + 16, 20),
		LayoutOrder = order,
		Text = text,
		TextSize = Sizes.TextSmall,
		TextXAlignment = Enum.TextXAlignment.Center,
		BackgroundTransparency = 0.85,
		Theme = { TextColor3 = color, BackgroundColor3 = color },
		Parent = parent,
	})
	Create.corner(label, 10)
	return label
end

-- Shows a plugin's error with its trace in the console.
local function showError(record)
	local Console = T.Console
	if not Console then
		return
	end
	pcall(Console.write, "error", ("%s: %s"):format(record.Name or record.Folder, tostring(record.Problem)))
	if record.Trace then
		for line in tostring(record.Trace):gmatch("[^\n]+") do
			pcall(Console.detail, line)
		end
	end
	if T.Tabs then
		T.Tabs:Select("console")
	end
end

local buildPluginPage

-- A plugin entry's page: its details and its settings.
local function buildEntryPage(panel: Frame, spec)
	if spec.Host and spec.Record then
		return buildPluginPage(panel, spec)
	end
	local store = spec.Settings or NO_STORE
	local items = if store.items then store.items() else {}
	local details = {}
	if spec.Version then
		table.insert(details, "v" .. spec.Version)
	end
	if spec.Author then
		table.insert(details, "by " .. spec.Author)
	end
	if #items == 0 then
		table.insert(details, "no settings")
	end
	local groups = if #items > 0 then { { Title = "Settings", Items = items } } else {}
	-- an action's Run gets the plugin's api
	local pageStore = setmetatable({ Context = spec.Context }, { __index = store })
	buildPage(panel, { Title = spec.Name, Icon = spec.Icon, Description = spec.Description }, groups, pageStore, table.concat(details, " · "))
end

-- The cards in list order (what Shift+click ranges and search go by).
local function orderedIds(): { string }
	local list = {}
	for id, entry in Manager.Entries do
		table.insert(list, { Id = id, Order = entry.Frame.LayoutOrder, Name = tostring(entry.Spec.Name):lower() })
	end
	table.sort(list, function(a, b)
		if a.Order ~= b.Order then
			return a.Order < b.Order
		end
		return a.Name < b.Name
	end)
	local ids = {}
	for _, item in list do
		table.insert(ids, item.Id)
	end
	return ids
end

local function pluginCount(): number
	local count = 0
	for id in Manager.Entries do
		if id ~= "tungsten" then
			count += 1
		end
	end
	return count
end

-- Search: a card shows when its name, id or line has the text.
local function applySearch()
	local query = Manager.Query:lower()
	for id, entry in Manager.Entries do
		local spec = entry.Spec
		local shown = id == "tungsten" or query == ""
		if not shown then
			for _, field in { spec.Name, spec.Id, spec.Note, spec.Description } do
				if type(field) == "string" and field:lower():find(query, 1, true) then
					shown = true
					break
				end
			end
		end
		entry.Frame.Visible = shown
	end
end

--[[
	The page of one plugin:
		header   icon, name, version and author, the Enabled switch (on or
		         off from the next start)
		state    on / off / failed / problem, and what changes at the next start
		         description
		actions  Open tab · Reload · Docs · Copy id
		ADDS     what it has registered (counted from the registries)
		SETTINGS a row per setting, then Reset
		PROBLEMS its problem or Load error (Details shows the trace), faults,
		         warnings
		footer   id and folder
]]
buildPluginPage = function(panel: Frame, spec)
	local record = spec.Record
	for _, child in panel:GetChildren() do
		child:Destroy()
	end
	table.clear(Manager.Controls)
	if pageConnection then
		pageConnection:Disconnect()
		pageConnection = nil
	end
	local id = record.Id

	-- header
	local header = new("Frame", {
		Name = "Header",
		Size = UDim2.new(1, 0, 0, 44),
		BackgroundTransparency = 1,
		Parent = panel,
	})
	local icon = Icons.new(spec.Icon or "plugins", 22, "Accent")
	icon.AnchorPoint = Vector2.new(0, 0.5)
	icon.Position = UDim2.new(0, PAD, 0.5, 0)
	icon.Parent = header
	local titleWidth = math.ceil(Create.textWidth(spec.Name, Sizes.Title, "Bold")) + 2
	new("TextLabel", {
		Name = "Title",
		Position = UDim2.fromOffset(PAD + 30, 0),
		Size = UDim2.new(0, titleWidth, 1, 0),
		Text = spec.Name,
		FontFace = Theme.Fonts.Bold,
		TextSize = Sizes.Title,
		Theme = { TextColor3 = "Text" },
		Parent = header,
	})
	local byline = {}
	if record.Version then
		table.insert(byline, "v" .. record.Version)
	end
	if record.Author then
		table.insert(byline, "by " .. record.Author)
	end
	new("TextLabel", {
		Name = "Byline",
		Position = UDim2.fromOffset(PAD + 30 + titleWidth + 8, 2),
		Size = UDim2.new(1, -(PAD + 30 + titleWidth + 8 + 110), 1, 0),
		Text = table.concat(byline, " · "),
		TextSize = Sizes.TextSmall,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Theme = { TextColor3 = "TextMuted" },
		Parent = header,
	})
	if id then
		new("TextLabel", {
			Name = "EnabledLabel",
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -PAD - 44, 0.5, 0),
			Size = UDim2.fromOffset(60, 20),
			Text = "Enabled",
			TextSize = Sizes.TextSmall,
			TextXAlignment = Enum.TextXAlignment.Right,
			Theme = { TextColor3 = "TextDim" },
			Parent = header,
		})
		local toggle = Toggle.new({
			Name = "Enabled",
			Parent = header,
			Position = UDim2.new(1, -PAD - 34, 0.5, -Sizes.Control / 2),
			Value = host ~= nil and host.wanted(id),
			OnChanged = function(on)
				if host then
					host.setWanted(id, on)
				end
			end,
		})
		Manager.Controls.__enabled = { Kind = "toggle", Widget = toggle }
	end
	new("Frame", {
		Name = "Line",
		Position = UDim2.fromOffset(0, 44),
		Size = UDim2.new(1, 0, 0, 1),
		Theme = { BackgroundColor3 = "Border" },
		Parent = panel,
	})

	local scroll = Scroll.new({
		Name = "Settings",
		Direction = "Y",
		Position = UDim2.fromOffset(0, 45),
		Size = UDim2.new(1, 0, 1, -45),
		Parent = panel,
	})
	Manager.Scroll = scroll
	local content = scroll.Content
	Create.padding(content, 8, PAD + 4, 16, PAD)
	local layout = Create.list(content, Enum.FillDirection.Vertical, 4)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	local order = 0
	local function nextOrder(): number
		order += 1
		return order
	end
	local function text(name: string, value: string, color: string?)
		return new("TextLabel", {
			Name = name,
			Size = UDim2.new(1, 0, 0, 18),
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = nextOrder(),
			Text = value,
			TextWrapped = true,
			TextSize = Sizes.TextSmall,
			Theme = { TextColor3 = color or "TextMuted" },
			Parent = content,
		})
	end
	local function heading(title: string)
		new("TextLabel", {
			Name = "Group_" .. title,
			Size = UDim2.new(1, 0, 0, 26),
			LayoutOrder = nextOrder(),
			Text = string.upper(title),
			FontFace = Theme.Fonts.Bold,
			TextSize = Sizes.TextSmall,
			TextYAlignment = Enum.TextYAlignment.Bottom,
			Theme = { TextColor3 = "Accent" },
			Parent = content,
		})
	end
	local function row(name: string, height: number): Frame
		local frame = new("Frame", {
			Name = name,
			Size = UDim2.new(1, 0, 0, height),
			LayoutOrder = nextOrder(),
			BackgroundTransparency = 1,
			Parent = content,
		})
		local rowLayout = Create.list(frame, Enum.FillDirection.Horizontal, 6, { VerticalAlignment = Enum.VerticalAlignment.Center })
		rowLayout.SortOrder = Enum.SortOrder.LayoutOrder
		return frame
	end

	-- state
	local stateRow = row("StateLine", 22)
	chip(stateRow, "State", record.State, STATE_COLOR[record.State] or "TextMuted", 1)
	local pending = id and host and host.pending(id)
	if pending then
		chip(stateRow, "Pending", ("%s at next start"):format(pending), "Warning", 2)
	end
	if record.State == "on" and record.LoadTime then
		new("TextLabel", {
			Name = "LoadTime",
			Size = UDim2.fromOffset(120, 20),
			LayoutOrder = 3,
			Text = ("loaded in %d ms"):format(math.floor(record.LoadTime * 1000 + 0.5)),
			TextSize = Sizes.TextSmall,
			Theme = { TextColor3 = "TextMuted" },
			Parent = stateRow,
		})
	end
	if record.Description then
		text("Description", record.Description, "TextDim")
	end

	-- actions
	local actions = row("Actions", Sizes.Control + 4)
	local tabExists = id ~= nil and T.Registry.getTab(id) ~= nil
	local docsExist = id ~= nil and T.Docs.get(id) ~= nil
	local function action(name: string, label: string, enabled: boolean, onClick)
		local button = Button.new({ Name = name, Parent = actions, Text = label, Style = "default", OnClick = onClick })
		button:SetEnabled(enabled)
		return button
	end
	action("OpenTab", "Open tab", tabExists, function()
		if T.Tabs then
			T.Tabs:Select(id)
		end
	end)
	action("Reload", "Reload", host ~= nil, function()
		local key = id or record.Folder
		task.spawn(function()
			local ok, why = host.reload(key)
			if not ok then
				local Console = T.Console
				if Console then
					pcall(Console.write, "warn", ("%s: %s"):format(key, tostring(why)))
				end
			end
		end)
	end)
	action("Docs", "Docs", docsExist, function()
		if T.Tabs then
			T.Tabs:Select("documentation")
		end
		T.Docs.open(id)
	end)
	action("CopyId", "Copy id", id ~= nil, function()
		pcall(setclipboard, id)
	end)

	-- what it adds
	heading("Adds")
	local adds = if record.State == "on" and id then addsOf(id) else {}
	if #adds == 0 then
		text("AddsNone", if record.State == "on" then "nothing so far" else "nothing while it isn't running")
	else
		local addsRow = row("AddsList", 22)
		for index, item in adds do
			chip(addsRow, "Add_" .. item.Key, item.Text, "TextDim", index)
		end
	end

	-- settings
	local store = spec.Settings
	local items = if store and store.items then store.items() else {}
	if #items > 0 then
		heading("Settings")
		local pageStore = setmetatable({ Context = spec.Context }, { __index = store })
		for _, item in items do
			settingRow(content, nextOrder(), item, pageStore)
		end
		settingRow(content, nextOrder(), {
			Id = "__reset",
			Kind = "action",
			Text = "Reset settings",
			Hint = "every setting back to the plugin's default",
			Button = "Reset",
			Run = function()
				for _, item in items do
					pcall(store.reset, item.Id)
				end
				pcall(store.flush)
			end,
		}, { get = function() end, Context = spec.Context })
		if store.Changed then
			pageConnection = store.Changed:Connect(function(key, value)
				local control = Manager.Controls[key]
				if control and control.Update then
					local current = store.get(key)
					control.Update(if current ~= nil then current else value)
				end
			end)
		end
	end

	-- problems
	heading("Problems")
	local any = false
	if record.Problem then
		any = true
		local problemRow = new("Frame", {
			Name = "ProblemRow",
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = nextOrder(),
			BackgroundTransparency = 1,
			Parent = content,
		})
		new("TextLabel", {
			Name = "Problem",
			Size = UDim2.new(1, -90, 0, 18),
			AutomaticSize = Enum.AutomaticSize.Y,
			Text = tostring(record.Problem),
			TextWrapped = true,
			TextSize = Sizes.TextSmall,
			Theme = { TextColor3 = "Danger" },
			Parent = problemRow,
		})
		if record.Trace then
			Button.new({
				Name = "Details",
				Parent = problemRow,
				Text = "Details",
				Style = "ghost",
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, 0, 0, 0),
				OnClick = function()
					showError(record)
				end,
			})
		end
	end
	if (record.Faults or 0) > 0 then
		any = true
		local last = record.LastFault
		text("Faults", ("%d fault%s%s"):format(record.Faults, if record.Faults == 1 then "" else "s",
			if last then (" · last: %s failed: %s"):format(last.What, last.Message) else ""), "Warning")
	end
	for index, warning in record.Warnings or {} do
		any = true
		text("Warning" .. index, warning, "Warning")
	end
	if record.Hooks and #record.Hooks > 0 then
		text("Hooks", ("its code mentions %s (it runs with the executor's rights)"):format(table.concat(record.Hooks, ", ")))
	end
	if not any then
		text("NoProblems", "None · faults inside this plugin show here and in the console")
	end

	text("Footer", ("id %s · folder plugins/%s"):format(tostring(id or "—"), record.Folder))
end

local function updateEmpty()
	local count = pluginCount()
	local list = Manager.List
	local empty = list and list:FindFirstChild("Empty", true)
	if empty then
		empty.Visible = count == 0
	end
	local search = Manager.Search
	if search then
		local show = count >= SEARCH_FROM
		search.Instance.Visible = show
		if not show and Manager.Query ~= "" then
			Manager.Query = ""
			search:SetText("")
		end
	end
	applySearch()
end

local function makeCard(spec)
	local entry = entryCard(Manager.ListContent or Manager.List, {
		Id = spec.Id,
		Name = spec.Name,
		Note = spec.Note or (if spec.Version then "v" .. spec.Version else ""),
		Icon = spec.Icon or "plugins",
		Order = spec.Order or 10,
		State = spec.State,
		Description = spec.Description,
	})
	entry.Page = spec
	return entry
end

-- For the plugin manager: a card in the list for one plugin.
function Manager.addEntry(spec)
	assert(type(spec) == "table" and type(spec.Id) == "string" and type(spec.Name) == "string", "an entry needs Id and Name")
	assert(spec.Id ~= "tungsten", "'tungsten' is the settings entry")
	Manager.Pending[spec.Id] = spec -- kept, so it shows when the tab is (re)built
	if not Manager.List then
		return nil
	end
	local wasSelected = Manager.Selected == spec.Id
	local old = Manager.Entries[spec.Id]
	if old then
		Manager.Entries[spec.Id] = nil
		old.Frame:Destroy()
	end
	local entry = makeCard(spec)
	updateEmpty()
	if wasSelected then
		-- show the new state on its page (the multi-selection stays)
		Manager.Selected = spec.Id
		for _, item in Manager.Entries do
			item.Restyle()
		end
		if Manager.Panel then
			buildEntryPage(Manager.Panel, spec)
		end
	end
	return entry
end

function Manager.removeEntry(id: string): boolean
	Manager.Pending[id] = nil
	local entry = Manager.Entries[id]
	if not entry or id == "tungsten" then
		return false
	end
	Manager.Entries[id] = nil
	Manager.Multi[id] = nil
	entry.Frame:Destroy()
	if Manager.Selected == id then
		Manager.select("tungsten")
	end
	updateEmpty()
	return true
end

function Manager.select(id: string): boolean
	local entry = Manager.Entries[id]
	if not entry then
		return false
	end
	Manager.Selected = id
	table.clear(Manager.Multi)
	if id ~= "tungsten" then
		Manager.Multi[id] = true
	end
	anchorId = id
	for _, item in Manager.Entries do
		item.Restyle()
	end
	if Manager.Panel then
		if id == "tungsten" then
			buildSettings(Manager.Panel)
		else
			buildEntryPage(Manager.Panel, entry.Page)
		end
	end
	return true
end

-- A click on a card: plain selects it; Ctrl adds / removes it; Shift
-- selects the range from the last plain click. The page shows the
-- clicked card. The tungsten entry is never part of a multi-selection.
function Manager.click(id: string, ctrl: boolean?, shift: boolean?)
	if id == "tungsten" or not (ctrl or shift) then
		return Manager.select(id)
	end
	local previous = Manager.Selected
	if shift and anchorId and Manager.Entries[anchorId] then
		local ids = orderedIds()
		local from, to = table.find(ids, anchorId), table.find(ids, id)
		if from and to then
			if not ctrl then
				table.clear(Manager.Multi)
			end
			for index = math.min(from, to), math.max(from, to) do
				if ids[index] ~= "tungsten" and Manager.Entries[ids[index]].Frame.Visible then
					Manager.Multi[ids[index]] = true
				end
			end
		end
	elseif ctrl then
		if Manager.Multi[id] then
			Manager.Multi[id] = nil
		else
			Manager.Multi[id] = true
		end
		anchorId = id
	end
	Manager.Selected = id
	for _, item in Manager.Entries do
		item.Restyle()
	end
	if Manager.Panel and previous ~= id then
		buildEntryPage(Manager.Panel, Manager.Entries[id].Page)
	end
	return true
end

-- The selected plugin cards (ids, list order).
function Manager.selected(): { string }
	local out = {}
	for _, id in orderedIds() do
		if Manager.Multi[id] then
			table.insert(out, id)
		end
	end
	return out
end

----------------------------------------------------------------------
-- The plugin host's plugins
----------------------------------------------------------------------

local syncQueued = false

-- The list's key for a plugin: its id, or "@Folder" for one without.
local function keyOf(record): string
	return record.Id or ("@" .. record.Folder)
end

local function iconOf(record): string
	local definition = record.Definition
	local icon = definition and definition.Icon
	local candidates = {}
	if type(icon) == "string" then
		table.insert(candidates, record.Path .. "/" .. icon)
	end
	table.insert(candidates, record.Path .. "/icon.png")
	for _, path in candidates do
		local ok, has = pcall(isfile, path)
		if ok and has and path:match("%.png$") then
			local okIcon, name = pcall(Icons.register, "plugin." .. keyOf(record), path, { Owner = "core" })
			if okIcon and type(name) == "string" then
				return name
			end
		end
	end
	if type(icon) == "string" and not icon:find("/", 1, true) and not icon:find("%.") then
		return icon -- a built-in icon name
	end
	return "plugins"
end

-- The one line under a plugin's name.
local function lineOf(record): string
	local pending = record.Id and host and host.pending(record.Id)
	local parts = {}
	if record.Version then
		table.insert(parts, "v" .. record.Version)
	end
	if pending then
		table.insert(parts, ("%s at next start"):format(pending))
	elseif record.State == "failed" or record.State == "problem" then
		table.insert(parts, tostring(record.Problem or record.State))
	elseif record.Description then
		table.insert(parts, record.Description)
	end
	return table.concat(parts, " · ")
end

local function specOf(record, index: number)
	local key = keyOf(record)
	local api = record.Api
	local settings = if api then api.settings else nil
	if not settings and record.Definition and record.Definition.Settings and #record.Definition.Settings > 0 then
		-- an off plugin: its saved settings, read (and changed) without running it
		local okStore, store = pcall(T.import("base/api").settingsStore, key, record.Definition.Settings, record.Path .. "/settings.json")
		settings = if okStore then store else nil
	end
	return {
		Id = key,
		Name = tostring(record.Name or record.Folder),
		Version = record.Version,
		Author = record.Author,
		Description = record.Description,
		Note = lineOf(record),
		Icon = iconOf(record),
		Order = 10 + index,
		State = record.State,
		Settings = settings,
		Context = api,
		Record = record,
		Host = true,
	}
end

-- How many plugins didn't start (failed, or on and with a problem).
local function troubled(): number
	if not host then
		return 0
	end
	local count = 0
	for _, record in host.list() do
		if record.State == "failed" or (record.State == "problem" and record.Id and host.wanted(record.Id)) then
			count += 1
		end
	end
	return count
end

local function updateBadge()
	pcall(T.Registry.updateTab, "plugins", { Badge = troubled() })
end

-- Brings the cards in line with the host (added, changed, gone).
function Manager.sync()
	syncQueued = false
	updateBadge()
	if not host then
		return
	end
	local seen = {}
	for index, record in host.list() do
		local spec = specOf(record, index)
		seen[spec.Id] = true
		Manager.addEntry(spec)
	end
	for id, spec in table.clone(Manager.Pending) do
		if spec.Host and not seen[id] then
			Manager.removeEntry(id)
		end
	end
end

local function queueSync()
	if syncQueued then
		return
	end
	syncQueued = true
	task.defer(Manager.sync)
end

local hostConnection = nil
function Manager.attachHost(plugins)
	host = plugins
	if hostConnection then
		hostConnection:Disconnect()
	end
	hostConnection = plugins.Changed:Connect(queueSync)
	Manager.sync()
end

function Manager.host()
	return host
end

----------------------------------------------------------------------
-- Right-click: the plugins.entry menu
----------------------------------------------------------------------

local function records(ctx): { any }
	local out = {}
	for _, id in ctx.Ids do
		local entry = Manager.Entries[id]
		local record = entry and entry.Page and entry.Page.Record
		if record then
			table.insert(out, record)
		end
	end
	return out
end

-- Shows a documentation topic (the tab first, like Function › Documentation).
local function openDocs(id: string)
	if T.Tabs then
		T.Tabs:Select("documentation")
	end
	T.Docs.open(id)
end

local function say(kind: string, text: string)
	local Console = T.Console
	if Console then
		pcall(Console.write, kind, { { Text = "Plugins: ", Color = "Accent" }, { Text = text, Color = if kind == "warn" then "Warning" else "Text" } })
	end
end

local function idsText(list: { any }): string
	local names = {}
	for _, record in list do
		table.insert(names, record.Id or record.Folder)
	end
	return table.concat(names, ", ")
end

T.Menus.define("plugins.entry", {
	Title = "Plugin list",
	Sections = { { Id = "state" }, { Id = "open" }, { Id = "copy" }, { Id = "settings" } },
	Empty = "Nothing to do for the tungsten entry",
})

local function setWanted(ctx, on: boolean)
	local changed = {}
	for _, record in records(ctx) do
		if record.Id and host.setWanted(record.Id, on) then
			table.insert(changed, record)
		end
	end
	if #changed > 0 then
		say("info", ("%s will be %s at the next start"):format(idsText(changed), if on then "on" else "off"))
	end
end

T.Menus.addMany("plugins.entry", {
	{
		Id = "on", Section = "state", Order = 10, Text = "Turn on", Icon = "check",
		When = function(ctx) return #records(ctx) > 0 end,
		Disabled = function(ctx)
			for _, record in records(ctx) do
				if record.Id and record.State ~= "problem" and not host.wanted(record.Id) then
					return false
				end
			end
			return true
		end,
		Callback = function(ctx) setWanted(ctx, true) end,
	},
	{
		Id = "off", Section = "state", Order = 20, Text = "Turn off", Icon = "close",
		When = function(ctx) return #records(ctx) > 0 end,
		Disabled = function(ctx)
			for _, record in records(ctx) do
				if record.Id and host.wanted(record.Id) then
					return false
				end
			end
			return true
		end,
		Callback = function(ctx) setWanted(ctx, false) end,
	},
	{
		Id = "reload", Section = "state", Order = 30, Text = "Reload", Icon = "refresh",
		When = function(ctx) return #records(ctx) > 0 end,
		Callback = function(ctx)
			for _, record in records(ctx) do
				local key = record.Id or record.Folder
				-- Load may wait: run where Tungsten can wait for it
				task.spawn(function()
					local ok, why = host.reload(key)
					local now = host.get(key) or host.byFolder(record.Folder)
					if ok then
						say("success", ("%s reloaded · %s"):format(key, if now then now.State else "?"))
					else
						say("warn", ("%s: %s"):format(key, tostring(why)))
					end
				end)
			end
		end,
	},
	{
		Id = "tab", Section = "open", Order = 10, Text = "Open its tab", Icon = "arrow_right",
		When = function(ctx) return #records(ctx) > 0 end,
		Disabled = function(ctx)
			local list = records(ctx)
			return #list ~= 1 or not list[1].Id or T.Registry.getTab(list[1].Id) == nil
		end,
		Callback = function(ctx)
			local record = records(ctx)[1]
			if record and T.Tabs then
				T.Tabs:Select(record.Id)
			end
		end,
	},
	{
		Id = "docs", Section = "open", Order = 20, Text = "Documentation", Icon = "documentation",
		When = function(ctx) return #records(ctx) > 0 end,
		Disabled = function(ctx)
			local list = records(ctx)
			return #list ~= 1 or not list[1].Id or T.Docs.get(list[1].Id) == nil
		end,
		Callback = function(ctx)
			local record = records(ctx)[1]
			if record then
				openDocs(record.Id)
			end
		end,
	},
	{
		Id = "copyid", Section = "copy", Order = 10, Text = "Copy id", Icon = "copy",
		When = function(ctx) return #records(ctx) > 0 end,
		Callback = function(ctx)
			local text = idsText(records(ctx))
			if pcall(setclipboard, text) then
				say("success", "copied " .. text)
			end
		end,
	},
	{
		Id = "reset", Section = "settings", Order = 10, Text = "Reset its settings…", Icon = "trash",
		Danger = true,
		When = function(ctx) return #records(ctx) > 0 end,
		Disabled = function(ctx)
			for _, id in ctx.Ids do
				local entry = Manager.Entries[id]
				local store = entry and entry.Page and entry.Page.Settings
				if store and store.items and #store.items() > 0 then
					return false
				end
			end
			return true
		end,
		Callback = function(ctx)
			local list = records(ctx)
			local Prompt = T.import("base/ui/components/prompt")
			Prompt.confirm({
				Title = ("Reset the settings of %s?"):format(idsText(list)),
				Text = "Each setting goes back to the plugin's default.",
				ConfirmText = "Reset",
				Danger = true,
				OnConfirm = function()
					for _, id in ctx.Ids do
						local entry = Manager.Entries[id]
						local store = entry and entry.Page and entry.Page.Settings
						if store and store.items then
							for _, item in store.items() do
								pcall(store.reset, item.Id)
							end
							pcall(store.flush)
						end
					end
					say("success", ("settings reset: %s"):format(idsText(list)))
				end,
			})
		end,
	},
}, "core")

-- Right-click on a card: acts on the selection when the card is in it,
-- otherwise on that card alone (which becomes the selection).
function Manager.openMenu(id: string, point: Vector2?)
	if id ~= "tungsten" and not Manager.Multi[id] then
		Manager.select(id)
	end
	local ids = if id == "tungsten" then {} else Manager.selected()
	return T.Menus.open("plugins.entry", { Ids = ids, Manager = Manager }, { Position = point })
end

function Manager.build(page: Frame)
	local left = new("Frame", {
		Name = "List",
		Size = UDim2.new(0, LIST_WIDTH, 1, 0),
		BackgroundTransparency = 1,
		Parent = page,
	})
	Manager.List = left
	new("TextLabel", {
		Name = "Heading",
		Position = UDim2.fromOffset(PAD, PAD),
		Size = UDim2.new(1, -PAD * 2, 0, 18),
		Text = "PLUGINS",
		FontFace = Theme.Fonts.Bold,
		TextSize = Sizes.TextSmall,
		Theme = { TextColor3 = "TextMuted" },
		Parent = left,
	})
	local search = Input.new({
		Name = "Search",
		Parent = left,
		Placeholder = "Search…",
		Position = UDim2.fromOffset(PAD, PAD + 24),
		Size = UDim2.new(1, -PAD * 2, 0, Sizes.Control),
		OnTyping = function(text)
			Manager.Query = text or ""
			applySearch()
		end,
	})
	search.Instance.Visible = false
	Manager.Search = search
	local listTop = PAD + 24
	local scroll = Scroll.new({
		Name = "Cards",
		Direction = "Y",
		Position = UDim2.fromOffset(0, listTop),
		Size = UDim2.new(1, 0, 1, -listTop),
		Parent = left,
	})
	Manager.ListScroll = scroll
	local content = scroll.Content
	Manager.ListContent = content
	-- room above the first card for its border (the tungsten card's accent
	-- outline is drawn outside the card and would touch the heading)
	Create.padding(content, 4, PAD, PAD, PAD)
	local leftLayout = Create.list(content, Enum.FillDirection.Vertical, 8)
	leftLayout.SortOrder = Enum.SortOrder.LayoutOrder
	-- the search box takes room above the cards only when it shows
	search.Instance:GetPropertyChangedSignal("Visible"):Connect(function()
		local top = listTop + (if search.Instance.Visible then Sizes.Control + 8 else 0)
		scroll.Instance.Position = UDim2.fromOffset(0, top)
		scroll.Instance.Size = UDim2.new(1, 0, 1, -top)
	end)
	entryCard(content, {
		Id = "tungsten",
		Name = "tungsten",
		Note = "settings and preferences",
		Icon = Icons.Brand,
		Emphasis = true,
		Order = 2,
	})
	-- No plugins: where they go, the guide, and Rescan.
	local empty = new("Frame", {
		Name = "Empty",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 10000,
		BackgroundTransparency = 1,
		Parent = content,
	})
	local emptyLayout = Create.list(empty, Enum.FillDirection.Vertical, 6)
	emptyLayout.SortOrder = Enum.SortOrder.LayoutOrder
	new("TextLabel", {
		Name = "Text",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 1,
		Text = "No plugins yet. Put a plugin's folder in Tungsten/plugins/, then Rescan.",
		TextWrapped = true,
		TextSize = Sizes.TextSmall,
		Theme = { TextColor3 = "TextMuted" },
		Parent = empty,
	})
	local emptyButtons = new("Frame", {
		Name = "Buttons",
		Size = UDim2.new(1, 0, 0, Sizes.Control),
		LayoutOrder = 2,
		BackgroundTransparency = 1,
		Parent = empty,
	})
	Create.list(emptyButtons, Enum.FillDirection.Horizontal, 6)
	Button.new({
		Name = "Rescan",
		Parent = emptyButtons,
		Text = "Rescan",
		Icon = "refresh",
		OnClick = function()
			if host then
				host.rescan()
				Manager.sync()
			end
		end,
	})
	Button.new({
		Name = "Guide",
		Parent = emptyButtons,
		Text = "How plugins work",
		Style = "ghost",
		OnClick = function()
			openDocs("plugins")
		end,
	})
	new("Frame", {
		Name = "Divider",
		Position = UDim2.fromOffset(LIST_WIDTH, PAD),
		Size = UDim2.new(0, 1, 1, -PAD * 2),
		Theme = { BackgroundColor3 = "Border" },
		Parent = page,
	})
	local panel = new("Frame", {
		Name = "Panel",
		Position = UDim2.fromOffset(LIST_WIDTH + 1, 0),
		Size = UDim2.new(1, -(LIST_WIDTH + 1), 1, 0),
		BackgroundTransparency = 1,
		Parent = page,
	})
	Manager.Panel = panel
	for _, spec in table.clone(Manager.Pending) do
		Manager.addEntry(spec)
	end
	updateEmpty()
	Manager.select("tungsten")
	if host then
		Manager.sync()
	end
	T.Bin:Add(function()
		table.clear(Manager.Pending)
		if pageConnection then
			pageConnection:Disconnect()
			pageConnection = nil
		end
		Manager.Panel = nil
		Manager.List = nil
		Manager.ListContent = nil
		Manager.ListScroll = nil
		Manager.Search = nil
		Manager.Selected = nil
		Manager.Query = ""
		table.clear(Manager.Multi)
		table.clear(Manager.Entries)
		table.clear(Manager.Controls)
	end)
end

T.Bin:Add(function()
	if hostConnection then
		hostConnection:Disconnect()
		hostConnection = nil
	end
	host = nil
end)

T.Manager = Manager

return {
	Id = "plugins",
	Title = "Plugins",
	Icon = "plugins",
	Order = 2,
	Builtin = true,
	Tooltip = "Plugins · tungsten settings",
	Build = function(page)
		Manager.build(page)
	end,
}
