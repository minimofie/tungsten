--[[
	Tungsten · base/ui/components/dropdown
	Single- or multi-choice dropdown, searchable when the list is long.

		local dropdown = Dropdown.new({
			Parent = row, Width = 200,
			Options = { "Low", "High" }   -- or { Value = x, Text = "X", Icon = "...", IconColor = Color3|key, Hint = "..." }
			Value = "Low",                -- single choice
			Multi = true, Values = {...}, -- multi choice
			Placeholder = "Choose…",
			Searchable = nil,             -- nil: automatic (more than 8 options)
			OnChanged = function(value or values) end,
		})

	Dropdown.popup(opts) opens just the option list (used by pickers and
	other parts that bring their own button).
]]

local T = ...
local signal = T.import("base/signal")
local Services = T.import("base/services")
local Theme = T.import("base/theme")
local Create = T.import("base/ui/create")
local Animate = T.import("base/ui/animate")
local Icons = T.import("base/data/icons")
local Overlay = T.import("base/ui/overlay")
local Scroll = T.import("base/ui/components/scroll")
local UI = T.import("base/ui/ui")
local TextFilter = T.import("base/textfilter")

local UserInputService = Services.UserInputService
local new = Create.new
local Sizes = Theme.Sizes

local ROW = 24
local PAD = 4
local SEARCH = 30
local AUTO_SEARCH = 8
local MAX_ROWS = 12

local Dropdown = {}
Dropdown.__index = Dropdown

local function normalizeOptions(options): { any }
	local list = {}
	for index, option in options or {} do
		if type(option) ~= "table" then
			list[index] = { Value = option, Text = tostring(option) }
		else
			local copy = table.clone(option)
			if copy.Text == nil then
				copy.Text = tostring(copy.Value)
			end
			list[index] = copy
		end
	end
	return list
end
Dropdown.normalize = normalizeOptions

----------------------------------------------------------------------
-- Option popup
----------------------------------------------------------------------

--[[
	opts:
		Options     normalized options
		AnchorPos, AnchorSize   the button it drops from (screen pixels)
		Width       minimum width
		Multi       keep open and toggle
		IsSelected  function(option) -> boolean
		OnPick      function(option)
		Searchable  boolean (typed words follow base/textfilter: several
		            words, !not, "exact", hint:…)
		Match       function(option, text) -> boolean: the opener's own search
		Owner       overlay owner (the button object)
		OnClose     function()
]]
function Dropdown.popup(opts)
	local origin = opts.Origin or "core"
	if opts.IsSelected == nil then
		opts.IsSelected = function()
			return false
		end
	end
	local options = opts.Options
	if UI.has("Dropdown", "Options") then
		options = Dropdown.normalize(UI.apply("Dropdown", "Options", origin, table.clone(options), opts))
	end
	local searchable = opts.Searchable
	if searchable == nil then
		searchable = #options > AUTO_SEARCH
	end

	local hasIcons, hasHints = false, false
	local textWidth, hintWidth = 0, 0
	for index, option in options do
		if option.Icon then
			hasIcons = true
		end
		if index <= 400 then -- measuring every option of huge lists is wasted work
			textWidth = math.max(textWidth, Create.textWidth(option.Text, Sizes.Text))
			if option.Hint then
				hasHints = true
				hintWidth = math.max(hintWidth, Create.textWidth(option.Hint, Sizes.TextSmall))
			end
		end
	end
	local leftSpace = 10 + (if opts.Multi then 20 else 0) + (if hasIcons then 22 else 0)
	local width = leftSpace + textWidth + (if hasHints then hintWidth + 18 else 0) + 18 + PAD * 2
	width = math.clamp(math.ceil(width), math.max(opts.Width or 0, 140), 380)

	local visibleRows = math.clamp(#options, 1, MAX_ROWS)
	local listHeight = visibleRows * ROW
	local height = PAD * 2 + listHeight + (if searchable then SEARCH + PAD else 0)
	height = math.min(height, Overlay.maxHeight())
	local size = Vector2.new(width, height)
	local position = Overlay.place(size, opts.AnchorPos, opts.AnchorSize, { Side = "below", Gap = 4 })

	local panel = Overlay.panel(size, position)
	panel.Name = "Options"
	local bin = signal.bin()

	local state = {
		Filtered = options,
		Highlight = 1,
		Rows = {},
	}

	-- Search box
	local searchBox = nil
	local top = PAD
	if searchable then
		local holder = new("Frame", {
			Name = "Search",
			Position = UDim2.fromOffset(PAD, PAD),
			Size = UDim2.new(1, -PAD * 2, 0, SEARCH),
			Theme = { BackgroundColor3 = "Chrome" },
			Parent = panel,
		})
		Create.corner(holder, 5)
		Create.stroke(holder, "Border", 1, 0)
		local icon = Icons.new("search", 13, "TextMuted")
		icon.AnchorPoint = Vector2.new(0, 0.5)
		icon.Position = UDim2.new(0, 8, 0.5, 0)
		icon.Parent = holder
		searchBox = new("TextBox", {
			Name = "Box",
			Position = UDim2.fromOffset(27, 0),
			Size = UDim2.new(1, -33, 1, 0),
			BackgroundTransparency = 1,
			PlaceholderText = "Search…",
			TextXAlignment = Enum.TextXAlignment.Left,
			ClipsDescendants = true,
			Parent = holder,
		})
		Theme.bind(searchBox, "PlaceholderColor3", "TextMuted")
		top += SEARCH + PAD
	end

	local scroll = Scroll.new({
		Mode = "virtual",
		Direction = "Y",
		BarThickness = 3,
		Position = UDim2.fromOffset(PAD, top),
		Size = UDim2.new(1, -PAD * 2, 1, -top - PAD),
		Parent = panel,
	})
	bin:Add(scroll)

	local emptyLabel = new("TextLabel", {
		Name = "Empty",
		Text = "No matches",
		Size = UDim2.new(1, 0, 0, ROW),
		TextXAlignment = Enum.TextXAlignment.Center,
		Visible = false,
		Theme = { TextColor3 = "TextMuted" },
		Parent = scroll.Instance,
	})

	local handle

	local function pick(option)
		if not option or option.Disabled then
			return
		end
		UI.fire("Dropdown", "Picked", origin, option, opts)
		local ok, err = pcall(opts.OnPick, option)
		if not ok then
			T.Log.error("ui", "dropdown callback failed: " .. tostring(err))
		end
		if opts.Multi then
			state.Render()
		else
			handle:Close("chosen")
		end
	end

	local function makeRow(slot: number)
		local row = new("TextButton", {
			Name = "Row" .. slot,
			Size = UDim2.new(1, 0, 0, ROW),
			BackgroundTransparency = 1,
			Theme = { BackgroundColor3 = "SurfaceHover" },
			Parent = scroll.Instance,
		})
		Create.corner(row, 5)
		local check = nil
		local x = 8
		if opts.Multi then
			check = Icons.new("check", 13, "Accent")
			check.AnchorPoint = Vector2.new(0, 0.5)
			check.Position = UDim2.new(0, x, 0.5, 0)
			check.Parent = row
			x += 20
		end
		local icon = nil
		if hasIcons then
			icon = Icons.new("dummy", 14, "TextDim")
			icon.AnchorPoint = Vector2.new(0, 0.5)
			icon.Position = UDim2.new(0, x, 0.5, 0)
			icon.Parent = row
			x += 22
		end
		local label = new("TextLabel", {
			Name = "Text",
			Position = UDim2.fromOffset(x, 0),
			Size = UDim2.new(1, -x - 8, 1, 0),
			TextTruncate = Enum.TextTruncate.AtEnd,
			Parent = row,
		})
		local hint = new("TextLabel", {
			Name = "Hint",
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -8, 0, 0),
			Size = UDim2.fromScale(0, 1),
			AutomaticSize = Enum.AutomaticSize.X,
			TextSize = Sizes.TextSmall,
			TextXAlignment = Enum.TextXAlignment.Right,
			Theme = { TextColor3 = "TextMuted" },
			Parent = row,
		})
		local entry = { Row = row, Check = check, Icon = icon, Label = label, Hint = hint, Index = 0, IconName = nil }
		row.MouseEnter:Connect(function()
			-- Ignore rows covered by another popup (MouseEnter reaches them too).
			if entry.Index > 0 and Overlay.popupAt(Overlay.mouse()) == handle then
				state.Highlight = entry.Index
				state.Paint()
			end
		end)
		row.Activated:Connect(function()
			if Overlay.popupAt(Overlay.mouse()) ~= handle then
				return
			end
			pick(state.Filtered[entry.Index])
		end)
		state.Rows[slot] = entry
		return entry
	end

	function state.Paint()
		for _, entry in state.Rows do
			local lit = entry.Index == state.Highlight and entry.Index > 0
			entry.Row.BackgroundTransparency = if lit then 0 else 1
		end
	end

	function state.Render()
		local filtered = state.Filtered
		local offset = scroll.Offset.Y
		local viewHeight = scroll:ViewSize().Y
		if viewHeight <= 0 then
			viewHeight = listHeight
		end
		local first = math.floor(offset / ROW) + 1
		local count = math.ceil(viewHeight / ROW) + 1
		emptyLabel.Visible = #filtered == 0
		for slot = 1, math.max(count, #state.Rows) do
			local entry = state.Rows[slot]
			local index = first + slot - 1
			local option = filtered[index]
			if slot > count or not option then
				if entry then
					entry.Row.Visible = false
					entry.Index = 0
				end
			else
				entry = entry or makeRow(slot)
				entry.Index = index
				entry.Row.Visible = true
				entry.Row.Position = UDim2.fromOffset(0, (index - 1) * ROW - offset)
				entry.Label.Text = option.Text
				entry.Hint.Text = option.Hint or ""
				local disabled = option.Disabled == true
				Theme.bind(entry.Label, "TextColor3", if disabled then "TextMuted" else "Text")
				if entry.Check then
					entry.Check.Visible = opts.IsSelected(option)
				elseif opts.IsSelected(option) then
					Theme.bind(entry.Label, "TextColor3", "Accent")
				end
				if entry.Icon then
					entry.Icon.Visible = option.Icon ~= nil
					if option.Icon and option.Icon ~= entry.IconName then
						Icons.set(entry.Icon, option.Icon)
						entry.IconName = option.Icon
					end
					if option.Icon then
						Icons.tint(entry.Icon, option.IconColor or "TextDim")
					end
				end
			end
		end
		state.Paint()
	end

	local function applyFilter(text: string)
		local query = string.lower(text)
		if query == "" then
			state.Filtered = options
		elseif opts.Match or not TextFilter.isPlain(text) then
			-- Several words, !not, "exact", hint:… (base/textfilter), or the
			-- opener's own Match(option, text).
			local test = TextFilter.compile(text)
			local result = {}
			for _, option in options do
				local keep
				if opts.Match then
					local ok, value = pcall(opts.Match, option, text)
					keep = ok and value == true
				else
					keep = test({ option.Text, option.Hint or "" }, { hint = option.Hint or "", text = option.Text })
				end
				if keep then
					table.insert(result, option)
				end
			end
			state.Filtered = UI.apply("Dropdown", "Search", origin, result, text, options)
		else
			-- Exact matches first, then names starting with the text, then the rest.
			local exact, starts, rest = {}, {}, {}
			for _, option in options do
				local haystack = string.lower(option.Text)
				if haystack == query then
					table.insert(exact, option)
				elseif haystack:sub(1, #query) == query then
					table.insert(starts, option)
				elseif haystack:find(query, 1, true) or (option.Hint and string.lower(option.Hint):find(query, 1, true)) then
					table.insert(rest, option)
				end
			end
			local result = exact
			table.move(starts, 1, #starts, #result + 1, result)
			table.move(rest, 1, #rest, #result + 1, result)
			state.Filtered = UI.apply("Dropdown", "Search", origin, result, text, options)
		end
		state.Highlight = 1
		scroll:SetCanvasSize(Vector2.new(0, #state.Filtered * ROW))
		scroll:ScrollTo(Vector2.zero)
		state.Render()
	end

	local function revealHighlight()
		local index = state.Highlight
		scroll:Reveal("Y", (index - 1) * ROW, index * ROW, 0, false)
		state.Render()
	end

	bin:Add(scroll.Changed:Connect(state.Render))
	scroll:SetCanvasSize(Vector2.new(0, #options * ROW))

	-- Start scrolled to the (first) selected option.
	for index, option in options do
		if opts.IsSelected and opts.IsSelected(option) then
			state.Highlight = index
			scroll:ScrollTo(Vector2.new(0, (index - 1) * ROW - (listHeight - ROW) / 2))
			break
		end
	end
	state.Render()

	if searchBox then
		bin:Add(searchBox:GetPropertyChangedSignal("Text"):Connect(function()
			applyFilter(searchBox.Text)
		end))
		bin:Add(searchBox.FocusLost:Connect(function(enterPressed)
			if enterPressed and handle and not handle.Closed then
				pick(state.Filtered[state.Highlight])
			end
		end))
	end

	-- Up/Down/Enter while the popup is open.
	bin:Add(UserInputService.InputBegan:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.Keyboard or handle.Closed then
			return
		end
		local key = input.KeyCode
		if key == Enum.KeyCode.Down or key == Enum.KeyCode.Up then
			local count = #state.Filtered
			if count == 0 then
				return
			end
			local step = if key == Enum.KeyCode.Down then 1 else -1
			state.Highlight = math.clamp(state.Highlight + step, 1, count)
			revealHighlight()
		elseif (key == Enum.KeyCode.Return or key == Enum.KeyCode.KeypadEnter) and not searchBox then
			pick(state.Filtered[state.Highlight])
		end
	end))

	handle = Overlay.open(panel, {
		Owner = opts.Owner,
		OnClose = function(reason)
			bin:Clean()
			if opts.OnClose then
				opts.OnClose(reason)
			end
		end,
	})
	handle.State = state -- .Filtered: the options the search leaves

	if searchBox then
		task.defer(function()
			if not handle.Closed then
				searchBox:CaptureFocus()
			end
		end)
	end

	UI.fire("Dropdown", "PopupOpened", origin, handle, opts)
	return handle
end

----------------------------------------------------------------------
-- The button
----------------------------------------------------------------------

function Dropdown.new(props: { [string]: any })
	local self = setmetatable({}, Dropdown)
	self.Bin = signal.bin()
	self.Changed = signal.new() -- (value) or (values)
	self.Multi = props.Multi == true
	self.Options = normalizeOptions(props.Options)
	self.Searchable = props.Searchable
	self.Match = props.Match -- function(option, text) -> boolean: own search rule
	self.Placeholder = props.Placeholder or "Choose…"
	self.PopupWidth = props.PopupWidth
	self._onChanged = props.OnChanged
	self.Hovered = false
	self.Popup = nil

	if self.Multi then
		self.Values = {}
		for _, value in props.Values or {} do
			self.Values[value] = true
		end
	else
		self.Value = props.Value
	end

	local button = new("TextButton", {
		Name = props.Name or "Dropdown",
		Size = props.Size or UDim2.fromOffset(props.Width or 180, Sizes.Control),
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		LayoutOrder = props.LayoutOrder or 0,
		Theme = { BackgroundColor3 = "Surface" },
	})
	self.Instance = button
	self.Bin:Add(button)
	Create.corner(button, Sizes.RadiusSmall)
	self.Stroke = Create.stroke(button, "Border", 1, 0)

	self.Icon = Icons.new("dummy", 14, "TextDim")
	self.Icon.AnchorPoint = Vector2.new(0, 0.5)
	self.Icon.Position = UDim2.new(0, 8, 0.5, 0)
	self.Icon.Visible = false
	self.Icon.Parent = button
	self._iconName = nil

	self.Label = new("TextLabel", {
		Name = "Text",
		Position = UDim2.fromOffset(9, 0),
		Size = UDim2.new(1, -32, 1, 0),
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = button,
	})
	self.Arrow = Icons.new("chevron_down", 13, "TextDim")
	self.Arrow.AnchorPoint = Vector2.new(1, 0.5)
	self.Arrow.Position = UDim2.new(1, -8, 0.5, 0)
	self.Arrow.Parent = button

	Animate.pressable(button, self.Bin)
	Animate.hover(button, self.Bin, function(hovered)
		self.Hovered = hovered
		self:_restyle(Animate.Fast)
	end)
	self.Bin:Add(button.Activated:Connect(function()
		if self.Popup and not self.Popup.Closed then
			self.Popup:Close("toggle")
		elseif not Overlay.justClosed(self) then
			self:Open()
		end
	end))

	self.Bin:Add(Create.cleanupWith(button, self))
	self.Origin = props.Origin or "core"
	self:_refresh()
	if props.Parent then
		button.Parent = props.Parent
	end
	UI.fire("Dropdown", "Created", self.Origin, self, props)
	return self
end

function Dropdown:_restyle(duration: number?)
	local open = self.Popup ~= nil and not self.Popup.Closed
	Theme.bind(self.Instance, "BackgroundColor3", if self.Hovered or open then "SurfaceHover" else "Surface", duration)
	Theme.bind(self.Stroke, "Color", if open then "Accent" elseif self.Hovered then "BorderStrong" else "Border", duration)
	Icons.tint(self.Arrow, if open then "Accent" else "TextDim", duration)
	Animate.set(self.Arrow, { Rotation = if open then 180 else 0 }, duration)
end

function Dropdown:_find(value)
	for _, option in self.Options do
		if option.Value == value then
			return option
		end
	end
	return nil
end

function Dropdown:_refresh()
	local text, muted, icon, iconColor = self.Placeholder, true, nil, nil
	if self.Multi then
		local chosen = {}
		for _, option in self.Options do
			if self.Values[option.Value] then
				table.insert(chosen, option.Text)
			end
		end
		if #chosen == 1 then
			text, muted = chosen[1], false
		elseif #chosen > 1 then
			text, muted = ("%d selected"):format(#chosen), false
		end
	else
		local option = self:_find(self.Value)
		if option then
			text, muted, icon, iconColor = option.Text, false, option.Icon, option.IconColor
		elseif self.Value ~= nil then
			text, muted = tostring(self.Value), false
		end
	end
	self.Label.Text = text
	Theme.bind(self.Label, "TextColor3", if muted then "TextMuted" else "Text")
	if icon then
		if icon ~= self._iconName then
			Icons.set(self.Icon, icon)
			self._iconName = icon
		end
		Icons.tint(self.Icon, iconColor or "TextDim")
		self.Icon.Visible = true
		self.Label.Position = UDim2.fromOffset(29, 0)
		self.Label.Size = UDim2.new(1, -52, 1, 0)
	else
		self.Icon.Visible = false
		self.Label.Position = UDim2.fromOffset(9, 0)
		self.Label.Size = UDim2.new(1, -32, 1, 0)
	end
end

function Dropdown:_fire()
	local payload = if self.Multi then self:GetValues() else self.Value
	if self._onChanged then
		local ok, err = pcall(self._onChanged, payload)
		if not ok then
			T.Log.error("ui", "dropdown callback failed: " .. tostring(err))
		end
	end
	self.Changed:Fire(payload)
	UI.fire("Dropdown", "Changed", self.Origin, self, payload)
end

function Dropdown:Open()
	if self.Popup and not self.Popup.Closed then
		return
	end
	local button = self.Instance
	self.Popup = Dropdown.popup({
		Origin = self.Origin,
		Options = self.Options,
		AnchorPos = button.AbsolutePosition,
		AnchorSize = button.AbsoluteSize,
		Width = math.max(Create.layoutSize(button).X, self.PopupWidth or 0),
		Multi = self.Multi,
		Searchable = self.Searchable,
		Match = self.Match,
		Owner = self,
		IsSelected = function(option)
			if self.Multi then
				return self.Values[option.Value] == true
			end
			return option.Value == self.Value
		end,
		OnPick = function(option)
			if self.Multi then
				self.Values[option.Value] = not self.Values[option.Value] or nil
			else
				if option.Value == self.Value then
					return
				end
				self.Value = option.Value
			end
			self:_refresh()
			self:_fire()
		end,
		OnClose = function()
			self:_restyle(Animate.Fast)
		end,
	})
	self:_restyle(Animate.Fast)
end

function Dropdown:Close()
	if self.Popup and not self.Popup.Closed then
		self.Popup:Close("closed")
	end
end

function Dropdown:SetOptions(options)
	self.Options = normalizeOptions(options)
	self:_refresh()
end

function Dropdown:SetValue(value, silent: boolean?)
	self.Value = value
	self:_refresh()
	if not silent then
		self:_fire()
	end
end

function Dropdown:GetValue()
	return self.Value
end

function Dropdown:SetValues(values: { any }, silent: boolean?)
	self.Values = {}
	for _, value in values do
		self.Values[value] = true
	end
	self:_refresh()
	if not silent then
		self:_fire()
	end
end

function Dropdown:GetValues(): { any }
	local list = {}
	for _, option in self.Options do
		if self.Values[option.Value] then
			table.insert(list, option.Value)
		end
	end
	return list
end

function Dropdown:Destroy()
	self:Close()
	self.Bin:Clean()
	self.Changed:DisconnectAll()
end

return UI.register("Dropdown", Dropdown, {
	Description = "single or multi choice dropdowns and option lists (Dropdown.popup)",
	Events = {
		Created = "dropdown, props · a dropdown button was made",
		Changed = "dropdown, value (or values) · the choice changed",
		PopupOpened = "handle, opts · an option list opened (also pickers, list cells)",
		Picked = "option, opts · an option was clicked or chosen with Enter",
	},
	Filters = {
		Options = "options, opts · the options an option list shows",
		Search = "matches, query, options · the matches for typed search text",
	},
})
