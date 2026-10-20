--[[
	Tungsten · base/ui/components/subtabs
	Tabs inside one tab: a plugin keeps a single tab in the side bar and
	shows its views as sub-tabs across the top of its page (a scanner with
	two modes, say). Each view is built the first time it shows.

		local tabs = SubTabs.new({
			Parent = page,
			TabId = "scanner",              -- the side-bar tab it lives in
			Tabs = {
				{ Id = "values", Title = "Values", Icon = "variable", Build = function(view) end },
				{ Id = "remotes", Title = "Remotes", Build = function(view) end },
			},
			Selected = "values",            -- default: the first
			OnChanged = function(id) end,
		})
		tabs:Select("remotes") ; tabs.Selected ; tabs:View("values") -> Frame
		tabs:Add({ Id, Title, Icon?, Badge?, Build }) ; tabs:Remove(id)
		tabs:Badge("remotes", 12)       -- a number or short text (nil / 0: none)
		tabs.Changed:Connect(function(id) end)

	The strip is in Tungsten's own look, like the side bar and the title
	bar: rounded pills on a Chrome band; the open one has the side bar's
	AccentSoft fill and an Accent icon, hover is SurfaceHover, and a badge
	is an accent dot like the side bar's. Sub-tabs that don't fit scroll
	sideways (mouse wheel). Plugins can't restyle it.
]]

local T = ...
local signal = T.import("base/signal")
local Theme = T.import("base/theme")
local Create = T.import("base/ui/create")
local Animate = T.import("base/ui/animate")
local Icons = T.import("base/data/icons")
local UI = T.import("base/ui/ui")
local Scroll = T.import("base/ui/components/scroll")

local new = Create.new
local Sizes = Theme.Sizes

local STRIP = 38 -- the band's height (like the path bar)
local PILL = 26 -- a sub-tab's height (like the title-bar buttons)
local PAD = 10 -- padding inside a pill
local ICON = 14
local GAP = 4 -- between pills
local BADGE_GAP = 6 -- between the title and a badge

local SubTabs = {}
SubTabs.__index = SubTabs
SubTabs.StripHeight = STRIP

function SubTabs.new(props: { [string]: any })
	local self = setmetatable({}, SubTabs)
	self.Origin = props.Origin or "core"
	self.TabId = props.TabId
	self.OnChanged = props.OnChanged
	self.Changed = signal.new()
	self.Bin = signal.bin()
	self.Entries = {} -- id -> { Def, Button, Line, Label, View, Built }
	self.Order = {}
	self.Selected = nil

	local holder = new("Frame", {
		Name = props.Name or "SubTabs",
		Size = props.Size or UDim2.fromScale(1, 1),
		Position = props.Position or UDim2.new(),
		BackgroundTransparency = 1,
		Parent = props.Parent,
	})
	self.Instance = holder
	local strip = new("Frame", {
		Name = "Strip",
		Size = UDim2.new(1, 0, 0, STRIP),
		Theme = { BackgroundColor3 = "Chrome" },
		Parent = holder,
	})
	self.Strip = strip
	-- the pills scroll sideways when they don't fit
	local scroll = Scroll.new({ Name = "Pills", Direction = "X", BarThickness = 2, Size = UDim2.new(1, 0, 1, -1), Origin = self.Origin, Parent = strip })
	self.Bin:Add(scroll)
	self.Scroll = scroll
	local pills = scroll.Content
	pills.Size = UDim2.new(0, 0, 1, 0)
	local stripLayout = Create.list(pills, Enum.FillDirection.Horizontal, GAP, { VerticalAlignment = Enum.VerticalAlignment.Center })
	stripLayout.SortOrder = Enum.SortOrder.LayoutOrder
	-- the pills centred in the band (above its 1 px rule)
	Create.padding(pills, math.floor((STRIP - 1 - PILL) / 2), 8, math.ceil((STRIP - 1 - PILL) / 2), 8)
	self.Pills = pills
	new("Frame", {
		Name = "Rule",
		Position = UDim2.new(0, 0, 0, STRIP - 1),
		Size = UDim2.new(1, 0, 0, 1),
		Theme = { BackgroundColor3 = "Border" },
		Parent = holder,
	})
	self.Views = new("Frame", {
		Name = "Views",
		Position = UDim2.fromOffset(0, STRIP),
		Size = UDim2.new(1, 0, 1, -STRIP),
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		Parent = holder,
	})

	for _, def in props.Tabs or {} do
		self:Add(def)
	end
	local first = props.Selected or self.Order[1]
	if first then
		self:Select(first)
	end
	self.Bin:Add(Create.cleanupWith(holder, self))
	UI.fire("SubTabs", "Created", self.Origin, self, props)
	return self
end

function SubTabs:_restyle(id: string)
	local entry = self.Entries[id]
	if not entry then
		return
	end
	local active = self.Selected == id
	local hovered = entry.Hovered
	Theme.bind(entry.Button, "BackgroundColor3", if active then "AccentSoft" else "SurfaceHover", Animate.Fast)
	Animate.tween(entry.Button, { BackgroundTransparency = if active or hovered then 0 else 1 }, Animate.Fast)
	Theme.bind(entry.Label, "TextColor3", if active or hovered then "Text" else "TextDim", Animate.Fast)
	if entry.Icon then
		Icons.tint(entry.Icon, if active then "Accent" elseif hovered then "Text" else "TextDim", Animate.Fast)
	end
end

-- A badge's text, or nil for none (like the side bar's).
local function badgeText(value: any): string?
	if value == nil or value == false or value == 0 or value == "" then
		return nil
	end
	local text = tostring(value)
	if #text > 3 then
		text = text:sub(1, 2) .. "+"
	end
	return text
end

-- Sizes a pill to its icon, title and badge.
function SubTabs:_layout(id: string)
	local entry = self.Entries[id]
	if not entry then
		return
	end
	local iconWidth = if entry.Icon then ICON + 6 else 0
	local textWidth = math.ceil(Create.textWidth(entry.Def.Title, Sizes.Text, "Medium"))
	local text = badgeText(entry.BadgeValue)
	local badgeWidth = 0
	if text then
		badgeWidth = math.max(14, math.ceil(Create.textWidth(text, 10)) + 8)
		entry.BadgeText.Text = text
		entry.Badge.Size = UDim2.fromOffset(badgeWidth, 14)
		entry.Badge.Position = UDim2.new(0, PAD + iconWidth + textWidth + BADGE_GAP, 0.5, 0)
	end
	entry.Badge.Visible = text ~= nil
	entry.Label.Size = UDim2.new(0, textWidth, 1, 0)
	entry.Button.Size = UDim2.fromOffset(PAD + iconWidth + textWidth + (if text then BADGE_GAP + badgeWidth else 0) + PAD, PILL)
end

-- Scrolls the strip so a sub-tab's pill is in view.
function SubTabs:_reveal(id: string)
	if not self.Scroll or not self.Entries[id] then
		return
	end
	local left = 8 -- the strip's padding
	for _, other in self.Order do
		if other == id then
			break
		end
		local entry = self.Entries[other]
		if entry then
			left += entry.Button.Size.X.Offset + GAP
		end
	end
	local width = self.Entries[id].Button.Size.X.Offset
	pcall(self.Scroll.Reveal, self.Scroll, "X", left, left + width, 8, true)
end

-- A number or short text on a sub-tab (nil, 0 or "" takes it away).
function SubTabs:Badge(id: string, value: any): boolean
	local entry = self.Entries[id]
	if not entry then
		return false
	end
	entry.BadgeValue = value
	self:_layout(id)
	return true
end

function SubTabs:Add(def: { [string]: any })
	assert(type(def) == "table" and type(def.Id) == "string" and def.Id ~= "", "a sub-tab needs an Id")
	assert(type(def.Title) == "string", "a sub-tab needs a Title")
	assert(def.Build == nil or type(def.Build) == "function", "Build must be a function")
	if self.Entries[def.Id] then
		self:Remove(def.Id)
	end
	table.insert(self.Order, def.Id)
	local iconWidth = if def.Icon then ICON + 6 else 0
	local button = new("TextButton", {
		Name = "Tab_" .. def.Id,
		Size = UDim2.fromOffset(PAD * 2, PILL),
		LayoutOrder = #self.Order,
		BackgroundTransparency = 1,
		Theme = { BackgroundColor3 = "SurfaceHover" },
		Parent = self.Pills,
	})
	Create.corner(button, Sizes.RadiusSmall)
	local icon
	if def.Icon then
		icon = Icons.new(def.Icon, ICON, "TextDim")
		icon.AnchorPoint = Vector2.new(0, 0.5)
		icon.Position = UDim2.new(0, PAD, 0.5, 0)
		icon.Parent = button
	end
	local label = new("TextLabel", {
		Name = "Text",
		Position = UDim2.fromOffset(PAD + iconWidth, 0),
		Size = UDim2.new(0, 0, 1, 0),
		Text = def.Title,
		FontFace = Theme.Fonts.Medium,
		TextXAlignment = Enum.TextXAlignment.Left,
		Theme = { TextColor3 = "TextDim" },
		Parent = button,
	})
	local badge = new("Frame", {
		Name = "Badge",
		AnchorPoint = Vector2.new(0, 0.5),
		Size = UDim2.fromOffset(14, 14),
		Visible = false,
		Theme = { BackgroundColor3 = "Accent" },
		Parent = button,
	})
	Create.corner(badge, 7)
	local badgeLabel = new("TextLabel", {
		Name = "Text",
		Size = UDim2.fromScale(1, 1),
		TextSize = 10,
		FontFace = Theme.Fonts.Bold,
		TextXAlignment = Enum.TextXAlignment.Center,
		Theme = { TextColor3 = "OnAccent" },
		Parent = badge,
	})
	local view = new("Frame", {
		Name = "View_" .. def.Id,
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = self.Views,
	})
	local entry = { Def = def, Button = button, Label = label, Icon = icon, Badge = badge, BadgeText = badgeLabel, BadgeValue = def.Badge, View = view, Built = false, Hovered = false }
	self.Entries[def.Id] = entry
	self:_layout(def.Id)
	Animate.hover(button, self.Bin, function(hovered)
		entry.Hovered = hovered
		self:_restyle(def.Id)
	end)
	Animate.pressable(button, self.Bin)
	self.Bin:Add(button.Activated:Connect(function()
		self:Select(def.Id)
	end))
	self:_restyle(def.Id)
	return view
end

function SubTabs:Remove(id: string): boolean
	local entry = self.Entries[id]
	if not entry then
		return false
	end
	self.Entries[id] = nil
	local index = table.find(self.Order, id)
	if index then
		table.remove(self.Order, index)
	end
	entry.Button:Destroy()
	entry.View:Destroy()
	if self.Selected == id then
		self.Selected = nil
		if self.Order[1] then
			self:Select(self.Order[1])
		end
	end
	return true
end

-- The frame a sub-tab's content goes in (built or not).
function SubTabs:View(id: string): Frame?
	local entry = self.Entries[id]
	return entry and entry.View
end

function SubTabs:Select(id: string): boolean
	local entry = self.Entries[id]
	if not entry then
		return false
	end
	local previous = self.Selected
	self.Selected = id
	for otherId, other in self.Entries do
		other.View.Visible = otherId == id
		self:_restyle(otherId)
	end
	if not entry.Built then
		entry.Built = true
		if entry.Def.Build then
			local ok, err = xpcall(entry.Def.Build, function(message)
				return tostring(message) .. "\n" .. debug.traceback(tostring(message), 2)
			end, entry.View, self)
			if not ok then
				T.import("console/reporter").ownerFault(self.Origin, ("building sub-tab '%s'"):format(id), err)
			end
		end
	end
	self:_reveal(id)
	if previous ~= id then
		self.Changed:Fire(id)
		UI.fire("SubTabs", "Changed", self.Origin, self, id)
		if self.OnChanged then
			local ok, err = pcall(self.OnChanged, id)
			if not ok then
				T.import("console/reporter").ownerFault(self.Origin, "sub-tab OnChanged", err)
			end
		end
	end
	return true
end

function SubTabs:Destroy()
	if self.Destroyed then
		return
	end
	self.Destroyed = true
	self.Bin:Clean()
	self.Changed:DisconnectAll()
	if self.Instance.Parent then
		self.Instance:Destroy()
	end
end

return UI.register("SubTabs", SubTabs, {
	Description = "tabs inside a tab (a plugin's views across the top of its page)",
	Events = {
		Created = "subtabs, props",
		Changed = "subtabs, id · another sub-tab was opened",
	},
})
