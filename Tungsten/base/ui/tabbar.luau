--[[
	Tungsten · base/ui/tabbar
	The vertical tab bar in the window's side bar. It follows the tab
	registry (base/registry): tabs added, changed (title, icon, badge,
	order) or removed there show up here straight away. Pages are built
	the first time a tab opens.

	- Scrolls with the mouse wheel (and its thin bar) when the tabs don't fit.
	- Hovering a tab shows its title (or Tooltip).
	- A Badge shows a number or short text on the icon.
	- Right-click a tab for the "tabbar" menu: Open, Move up / down, Hide
	  (plugin tabs), the tab's own MenuItems, and Show hidden tabs.
	- Ctrl+Up / Ctrl+Down (while no text box is focused) switch tabs.

	Signal: Changed(newId, previousId)
]]

local T = ...
local signal = T.import("base/signal")
local Services = T.import("base/services")
local Theme = T.import("base/theme")
local Settings = T.import("base/settings")
local Registry = T.import("base/registry")
local Create = T.import("base/ui/create")
local Animate = T.import("base/ui/animate")
local Icons = T.import("base/data/icons")
local Overlay = T.import("base/ui/overlay")
local Menus = T.import("base/ui/menus")
local Scroll = T.import("base/ui/components/scroll")
local Tooltip = T.import("base/ui/components/tooltip")

local UserInputService = Services.UserInputService
local new = Create.new
local Sizes = Theme.Sizes

local BUILTIN_ORDER_OFFSET = 0
local OTHER_ORDER_OFFSET = 1000
local DIVIDER_ORDER = 999
local BAR_HEIGHT = 18
local ICON_SIZE = 18

local TabBar = {}
TabBar.__index = TabBar

----------------------------------------------------------------------
-- The "tabbar" menu
----------------------------------------------------------------------

Menus.define("tabbar", {
	Title = "Tab bar (right-click a tab)",
	Header = function(ctx)
		return if ctx.Tab then ctx.Tab.Title else "Tabs"
	end,
	Sections = { "open", "own", "arrange", "hidden" },
})
Menus.addMany("tabbar", {
	{
		Id = "open",
		Section = "open",
		Order = 10,
		Text = "Open",
		Icon = "arrow_right",
		When = function(ctx)
			return ctx.Tab ~= nil
		end,
		Disabled = function(ctx)
			return ctx.TabBar.Selected == ctx.Tab.Id
		end,
		Callback = function(ctx)
			ctx.TabBar:Select(ctx.Tab.Id)
		end,
	},
	{
		Id = "own",
		Section = "own",
		Order = 10,
		Provide = function(ctx)
			local tab = ctx.Tab
			if not tab or type(tab.MenuItems) ~= "function" then
				return {}
			end
			local ok, list = pcall(tab.MenuItems, ctx)
			if not ok then
				T.import("console/reporter").ownerFault(tab.Owner, ("menu of tab '%s'"):format(tab.Id), list)
				return {}
			end
			return if type(list) == "table" then list else {}
		end,
	},
	{
		Id = "move_up",
		Section = "arrange",
		Order = 10,
		Text = "Move up",
		Icon = "chevron_left",
		When = function(ctx)
			return ctx.Tab ~= nil
		end,
		Callback = function(ctx)
			Registry.move(ctx.Tab.Id, -1)
		end,
	},
	{
		Id = "move_down",
		Section = "arrange",
		Order = 20,
		Text = "Move down",
		Icon = "chevron_down",
		When = function(ctx)
			return ctx.Tab ~= nil
		end,
		Callback = function(ctx)
			Registry.move(ctx.Tab.Id, 1)
		end,
	},
	{
		Id = "hide",
		Section = "arrange",
		Order = 30,
		Text = "Hide tab",
		Icon = "hide",
		When = function(ctx)
			return ctx.Tab ~= nil
		end,
		Disabled = function(ctx)
			return not ctx.Tab.Closable
		end,
		Callback = function(ctx)
			Registry.setHidden(ctx.Tab.Id, true)
		end,
	},
	{
		Id = "reset_order",
		Section = "arrange",
		Order = 40,
		Text = "Reset order",
		Icon = "refresh",
		Disabled = function()
			return #(Settings.get("TabOrder") or {}) == 0
		end,
		Callback = function(ctx)
			Settings.set("TabOrder", {})
			ctx.TabBar:Rebuild()
		end,
	},
	{
		Id = "show_hidden",
		Section = "hidden",
		Order = 10,
		Text = "Show hidden tabs",
		Icon = "explorer",
		Disabled = function()
			return #(Settings.get("HiddenTabs") or {}) == 0
		end,
		Items = function()
			local items = {}
			for _, id in Settings.get("HiddenTabs") or {} do
				local tab = Registry.getTab(id)
				if tab then
					table.insert(items, {
						Text = tab.Title,
						Icon = tab.Icon,
						Callback = function()
							Registry.setHidden(id, false)
						end,
					})
				end
			end
			if #items == 0 then
				table.insert(items, { Text = "No hidden tabs", Disabled = true })
			end
			return items
		end,
	},
})

----------------------------------------------------------------------
-- Building
----------------------------------------------------------------------

function TabBar.new(window)
	local self = setmetatable({}, TabBar)
	self.Window = window
	self.Bin = signal.bin()
	self.Changed = signal.new()
	self.Entries = {} -- id -> entry
	self.Pages = {} -- id -> Frame
	self.Selected = nil :: string?

	local scroll = Scroll.new({ Name = "Tabs", Direction = "Y", BarThickness = 3, Parent = window.Sidebar })
	Create.list(scroll.Content, Enum.FillDirection.Vertical, 4, { HorizontalAlignment = Enum.HorizontalAlignment.Center })
	Create.padding(scroll.Content, 6, 0, 6, 0)
	self.Scroll = scroll
	self.List = scroll.Content
	self.Bin:Add(scroll)

	-- Separates the main tabs (Console, Plugins, Documentation) from plugin tabs.
	self.Divider = new("Frame", {
		Name = "Divider",
		Size = UDim2.fromOffset(22, 1),
		LayoutOrder = DIVIDER_ORDER,
		Visible = false,
		Theme = { BackgroundColor3 = "Border" },
		Parent = scroll.Content,
	})

	-- Right-click on the empty part of the side bar.
	self.Bin:Add(scroll.Instance.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			local point = Overlay.pointOf(input)
			for _, entry in self.Entries do
				if Overlay.inside(entry.Button, point) then
					return
				end
			end
			self:OpenMenu(nil, point)
		end
	end))

	self:Rebuild()
	self.Bin:Add(Registry.TabAdded:Connect(function()
		self:Rebuild()
	end))
	self.Bin:Add(Registry.TabRemoved:Connect(function(tab)
		self:_remove(tab.Id)
		self:Rebuild()
	end))
	self.Bin:Add(Registry.TabChanged:Connect(function(tab, changed)
		self:_update(tab, changed)
	end))

	-- Ctrl+Up / Ctrl+Down switch tabs.
	self.Bin:Add(UserInputService.InputBegan:Connect(function(input, processed)
		if processed or input.UserInputType ~= Enum.UserInputType.Keyboard or UserInputService:GetFocusedTextBox() then
			return
		end
		if window.Minimized then
			return
		end
		local ctrl = UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)
		if not ctrl then
			return
		end
		if input.KeyCode == Enum.KeyCode.Down then
			self:Step(1)
		elseif input.KeyCode == Enum.KeyCode.Up then
			self:Step(-1)
		end
	end))
	return self
end

----------------------------------------------------------------------
-- Buttons
----------------------------------------------------------------------

function TabBar:_style(entry, duration: number?)
	local active = self.Selected == entry.Tab.Id
	local hovered = entry.Hovered

	Theme.bind(entry.Button, "BackgroundColor3", if active then "AccentSoft" else "SurfaceHover", duration)
	Animate.set(entry.Button, {
		BackgroundTransparency = if active then 0 elseif hovered then 0.3 else 1,
	}, duration)
	Icons.tint(entry.Icon, if active then "Accent" elseif hovered then "Text" else "TextMuted", duration)
	Animate.set(entry.Bar, {
		Size = UDim2.fromOffset(3, if active then BAR_HEIGHT else 0),
	}, duration)
end

function TabBar:_updateDivider()
	local builtin, other = false, false
	for _, entry in self.Entries do
		if entry.Tab.Builtin then
			builtin = true
		else
			other = true
		end
	end
	-- Always under the main tabs, so plugin tabs have their own place.
	self.Divider.Visible = builtin
end

function TabBar:_badge(entry)
	local value = entry.Tab.Badge
	local text = if value == nil or value == false or value == 0 or value == "" then nil else tostring(value)
	if text and #text > 3 then
		text = text:sub(1, 2) .. "+"
	end
	if not text then
		entry.Badge.Visible = false
		return
	end
	entry.BadgeText.Text = text
	entry.Badge.Size = UDim2.fromOffset(math.max(14, math.ceil(Create.textWidth(text, 10)) + 8), 14)
	entry.Badge.Visible = true
end

function TabBar:_add(tab)
	if self.Entries[tab.Id] then
		return self.Entries[tab.Id]
	end
	local bin = signal.bin()
	local button = new("TextButton", {
		Name = tab.Id,
		Size = UDim2.fromOffset(Sizes.TabButton, Sizes.TabButton),
		BackgroundTransparency = 1,
		Theme = { BackgroundColor3 = "SurfaceHover" },
		Parent = self.List,
	})
	bin:Add(button)
	Create.corner(button, Sizes.RadiusSmall)

	-- Accent bar on the side bar's left edge.
	local bar = new("Frame", {
		Name = "Bar",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, -(Sizes.Sidebar - Sizes.TabButton) / 2, 0.5, 0),
		Size = UDim2.fromOffset(3, 0),
		Theme = { BackgroundColor3 = "Accent" },
		Parent = button,
	})
	Create.corner(bar, 2)

	local icon = Icons.new(tab.Icon, ICON_SIZE, "TextMuted")
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.5)
	icon.Parent = button

	local badge = new("Frame", {
		Name = "Badge",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 2, 0, -2),
		Size = UDim2.fromOffset(14, 14),
		Visible = false,
		ZIndex = 3,
		Theme = { BackgroundColor3 = "Accent" },
		Parent = button,
	})
	Create.corner(badge, 7)
	local badgeText = new("TextLabel", {
		Name = "Text",
		Size = UDim2.fromScale(1, 1),
		TextSize = 10,
		FontFace = Theme.Fonts.Bold,
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 4,
		Theme = { TextColor3 = "OnAccent" },
		Parent = badge,
	})

	local entry = { Tab = tab, Button = button, Bar = bar, Icon = icon, Badge = badge, BadgeText = badgeText, Hovered = false, Bin = bin }
	self.Entries[tab.Id] = entry

	Animate.pressable(button, bin)
	Animate.hover(button, bin, function(hovered)
		entry.Hovered = hovered
		self:_style(entry, Animate.Fast)
	end)
	entry.Tooltip = Tooltip.attach(button, function()
		return entry.Tab.Tooltip or entry.Tab.Title
	end, { Side = "right" })
	bin:Add(function()
		entry.Tooltip:Remove()
	end)
	bin:Add(button.Activated:Connect(function()
		self:Select(tab.Id)
	end))
	bin:Add(button.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			self:OpenMenu(entry.Tab, Overlay.pointOf(input))
		end
	end))

	self:_badge(entry)
	self:_style(entry, nil)
	return entry
end

-- Puts the buttons in registry order (hidden tabs removed).
function TabBar:Rebuild()
	local shown = {}
	for index, tab in Registry.listTabs() do
		shown[tab.Id] = true
		local entry = self:_add(tab)
		entry.Button.LayoutOrder = (if tab.Builtin then BUILTIN_ORDER_OFFSET else OTHER_ORDER_OFFSET) + math.min(index, 998)
	end
	for id in table.clone(self.Entries) do
		if not shown[id] then
			self:_remove(id)
		end
	end
	self:_updateDivider()
	if self.Selected and not self.Entries[self.Selected] then
		self.Selected = nil
	end
	if not self.Selected then
		local first = Registry.listTabs()[1]
		if first and self._started then
			self:Select(first.Id)
		end
	end
end

function TabBar:_update(tab, changed)
	if changed.Hidden or changed.Order then
		self:Rebuild()
	end
	local entry = self.Entries[tab.Id]
	if not entry then
		return
	end
	if changed.Icon then
		Icons.set(entry.Icon, tab.Icon)
		self:_style(entry, nil)
	end
	if changed.Badge then
		self:_badge(entry)
	end
	if changed.Title and self.Selected == tab.Id then
		self.Window:SetSubtitle(tab.Title)
	end
end

function TabBar:_remove(id: string)
	local entry = self.Entries[id]
	if not entry then
		return
	end
	self.Entries[id] = nil
	entry.Bin:Clean()

	local page = self.Pages[id]
	if page then
		self.Pages[id] = nil
		page:Destroy()
	end
	self:_updateDivider()

	if self.Selected == id then
		self.Selected = nil
		local first = Registry.listTabs()[1]
		if first and first.Id ~= id then
			self:Select(first.Id)
		else
			self.Window:SetSubtitle(nil)
		end
	end
end

function TabBar:OpenMenu(tab, point: Vector2?)
	self.Menu = Menus.open("tabbar", { TabBar = self, Tab = tab, Point = point }, { Position = point or Overlay.mouse() })
	return self.Menu
end

----------------------------------------------------------------------
-- Pages
----------------------------------------------------------------------

function TabBar:_page(tab): Frame
	local page = self.Pages[tab.Id]
	if page then
		return page
	end

	page = new("Frame", {
		Name = tab.Id,
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = self.Window.Content,
	})
	self.Pages[tab.Id] = page

	if tab.Build then
		local ok, err = xpcall(tab.Build, debug.traceback, page, T, tab)
		if not ok then
			T.Log.error("tabs", ("tab '%s' failed to build:\n%s"):format(tab.Id, tostring(err)))
			if tab.Owner and tab.Owner ~= "core" then
				T.import("console/reporter").ownerFault(tab.Owner, ("building tab '%s'"):format(tab.Id), err)
			end
			page:ClearAllChildren()
			Create.placeholder(page, tab.Title, {
				"This tab failed to load.",
				"Details are in the newest file in Tungsten/logs/.",
			})
		end
	end
	return page
end

function TabBar:_scrollIntoView(button: GuiObject)
	local scroll = self.Scroll
	if scroll:ViewSize().Y <= 0 then
		return
	end
	local top = Create.toLocal(button.AbsolutePosition, self.List).Y
	scroll:Reveal("Y", top, top + Create.layoutSize(button).Y, 6, true)
end

----------------------------------------------------------------------
-- Public
----------------------------------------------------------------------

local function call(tab, key: string)
	local fn = tab[key]
	if type(fn) == "function" then
		local ok, err = pcall(fn, tab)
		if not ok then
			T.Log.error("tabs", ("%s of tab '%s' failed: %s"):format(key, tab.Id, tostring(err)))
			if tab.Owner and tab.Owner ~= "core" then
				T.import("console/reporter").ownerFault(tab.Owner, ("%s of tab '%s'"):format(key, tab.Id), err)
			end
		end
	end
end

function TabBar:Select(id: string): boolean
	local entry = self.Entries[id]
	if not entry then
		return false
	end
	self._started = true
	if self.Selected == id then
		return true
	end

	local previous = self.Selected
	self.Selected = id

	local previousEntry = previous and self.Entries[previous]
	if previousEntry then
		self:_style(previousEntry, Animate.Normal)
		call(previousEntry.Tab, "OnDeselect")
	end
	self:_style(entry, Animate.Normal)

	local page = self:_page(entry.Tab)
	for otherId, otherPage in self.Pages do
		if otherId ~= id then
			otherPage.Visible = false
		end
	end
	page.Position = UDim2.fromOffset(0, 10)
	page.Visible = true
	Animate.tween(page, { Position = UDim2.fromOffset(0, 0) }, Animate.Slow)
	self.Window:FadeContent()

	self.Window:SetSubtitle(entry.Tab.Title)
	self:_scrollIntoView(entry.Button)
	Settings.set("LastTab", id)
	call(entry.Tab, "OnSelect")

	T.Log.debug("tabs", ("selected '%s'"):format(id))
	self.Changed:Fire(id, previous)
	return true
end

-- Opens the next (1) or previous (-1) tab.
function TabBar:Step(delta: number): boolean
	local list = Registry.listTabs()
	local index = 1
	for position, tab in list do
		if tab.Id == self.Selected then
			index = position
		end
	end
	local target = list[((index - 1 + delta) % #list) + 1]
	return if target then self:Select(target.Id) else false
end

-- Ids of the shown tabs in their order.
function TabBar:Order(): { string }
	local list = {}
	for _, tab in Registry.listTabs() do
		if self.Entries[tab.Id] then
			table.insert(list, tab.Id)
		end
	end
	return list
end

function TabBar:Destroy()
	for id in table.clone(self.Entries) do
		local entry = self.Entries[id]
		self.Entries[id] = nil
		entry.Bin:Clean()
	end
	for _, page in self.Pages do
		page:Destroy()
	end
	table.clear(self.Pages)
	self.Bin:Clean()
	self.Changed:DisconnectAll()
end

return TabBar
