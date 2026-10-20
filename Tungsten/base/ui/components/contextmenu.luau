--[[
	Tungsten · base/ui/components/contextmenu
	Right-click menus: category headers, icons, shortcuts, disabled
	items, check marks, separators and submenus (open on hover or click).

		ContextMenu.open({
			{ Header = "Edit" },
			{ Text = "Copy", Icon = "copy", Shortcut = "Ctrl+C", Callback = function() end },
			{ Text = "Delete", Icon = "trash", Danger = true, Disabled = true },
			{ Text = "Load", Icon = "arrow_right", Emphasis = true },   -- accent, bold
			{ Text = "Part", Icon = "class_part", IconColor = Color3.new(1, 0.6, 0) }, -- tinted icon (Color3 or theme key)
			{ Separator = true },
			{ Text = "More", Items = { ... } },      -- or Items = function() return {...} end
			{ Text = "Wrap", Checked = true, Callback = ... },  -- toggles in place; Callback(item) sees item.Checked
		}, { Position = screenPoint })  -- defaults to the mouse

	Menus live on the overlay: they may extend past the window, flip near
	screen edges, never go off-screen and scroll when taller than it.

	This is the drawing layer. Named, extendable menus are built with
	base/ui/menus (the menu framework) and drawn here.

	Custom row kinds (for plugins that need more than a clickable row):
		ContextMenu.addKind("swatch", {
			Height = 30,                                  -- or function(item)
			Width = function(item) return 180 end,        -- optional minimum
			Build = function(row, item, menu) ... end,    -- fill `row` (a Frame)
		})
		{ Kind = "swatch", Color = ... }                  -- an item of that kind
	Build gets the row frame, the item and the menu; menu:Close() closes it.
]]

local T = ...
local Services = T.import("base/services")
local UserInputService = Services.UserInputService
local Theme = T.import("base/theme")
local Create = T.import("base/ui/create")
local Animate = T.import("base/ui/animate")
local Icons = T.import("base/data/icons")
local Overlay = T.import("base/ui/overlay")
local Scroll = T.import("base/ui/components/scroll")
local UI = T.import("base/ui/ui")

local new = Create.new
local Sizes = Theme.Sizes

local PAD = 4 -- inside the panel
local ITEM_PAD = 10 -- inside each item
local ICON = 14
local SEPARATOR = 9
local HOVER_DELAY = 0.12
local MIN_WIDTH = 168
local MAX_WIDTH = 380

local ContextMenu = {}
ContextMenu.__index = ContextMenu

local kinds: { [string]: any } = {}

function ContextMenu.addKind(name: string, definition: { [string]: any })
	assert(type(name) == "string" and name ~= "", "a row kind needs a name")
	assert(type(definition) == "table" and type(definition.Build) == "function", "a row kind needs a Build function")
	kinds[name] = definition
end

-- Row kinds an owner added (definition.Owner).
function ContextMenu.removeOwner(owner: string): number
	local count = 0
	for name, definition in table.clone(kinds) do
		if definition.Owner == owner then
			kinds[name] = nil
			count += 1
		end
	end
	return count
end

function ContextMenu.removeKind(name: string)
	kinds[name] = nil
end

function ContextMenu.hasKind(name: string): boolean
	return kinds[name] ~= nil
end

T.Bin:Add(function()
	table.clear(kinds)
end)

local function resolve(items)
	if type(items) == "function" then
		local ok, result = pcall(items)
		if not ok then
			T.Log.error("menu", "menu items failed to build: " .. tostring(result))
			return { { Text = "Could not build this menu", Disabled = true } }
		end
		items = result
	end
	return if type(items) == "table" then items else {}
end

local function itemHeight(item): number
	local kind = item.Kind and kinds[item.Kind]
	if kind then
		local height = kind.Height
		if type(height) == "function" then
			local ok, value = pcall(height, item)
			height = if ok then value else nil
		end
		return tonumber(height) or Sizes.MenuItem
	end
	if item.Separator then
		return SEPARATOR
	elseif item.Header then
		return Sizes.MenuHeader
	end
	return Sizes.MenuItem
end

local function measure(items, minWidth: number?): (number, number)
	local hasIcons = false
	local textWidth, shortcutWidth, hasArrow = 0, 0, false
	local height = PAD * 2
	for _, item in items do
		height += itemHeight(item)
		if item.Icon or item.Checked ~= nil then
			hasIcons = true
		end
		if item.Text then
			textWidth = math.max(textWidth, Create.textWidth(item.Text, Sizes.Text))
		elseif item.Header then
			textWidth = math.max(textWidth, Create.textWidth(string.upper(item.Header), Sizes.TextSmall, "Bold"))
		end
		if item.Shortcut then
			shortcutWidth = math.max(shortcutWidth, Create.textWidth(item.Shortcut, Sizes.TextSmall))
		end
		if item.Items then
			hasArrow = true
		end
		local kind = item.Kind and kinds[item.Kind]
		if kind and kind.Width then
			local ok, value = pcall(kind.Width, item)
			if ok and tonumber(value) then
				textWidth = math.max(textWidth, tonumber(value) - ITEM_PAD * 2)
			end
		end
	end
	local width = PAD * 2 + ITEM_PAD * 2 + textWidth
	if hasIcons then
		width += ICON + 8
	end
	if shortcutWidth > 0 then
		width += shortcutWidth + 24
	end
	if hasArrow then
		width += 20
	end
	width = math.clamp(math.ceil(width), math.max(MIN_WIDTH, minWidth or 0), MAX_WIDTH)
	return width, height
end

--[[
	opts:
		Position   screen point (context menus; default: mouse)
		AnchorPos, AnchorSize, Side  ("below" | "right") instead of Position
		Owner      passed to the overlay (for toggle buttons)
		Parent     parent menu's overlay handle (submenus)
		MinWidth
		EmptyText  shown when there are no items
		OnClose    function(reason)
		Origin     who opened it ("core" or a plugin id; see base/ui/ui)
]]
function ContextMenu.open(items, opts: { [string]: any }?)
	opts = opts or {}
	local origin = opts.Origin or "core"
	items = resolve(items)
	items = UI.apply("ContextMenu", "Items", origin, items, opts)
	if #items == 0 then
		items = { { Text = opts.EmptyText or "Nothing here", Disabled = true } }
	end

	local self = setmetatable({}, ContextMenu)
	self.Origin = origin
	self.Items = items
	self.Rows = {}
	self.Child = nil
	self.Hovered = nil
	self._hoverToken = 0

	local width, height = measure(items, opts.MinWidth)
	height = math.min(height, Overlay.maxHeight())
	local size = Vector2.new(width, height)
	local position
	if opts.AnchorPos then
		position = Overlay.place(size, opts.AnchorPos, opts.AnchorSize, { Side = opts.Side or "right", Gap = opts.Gap or 2 })
	else
		position = Overlay.place(size, opts.Position or Overlay.mouse(), nil, { Side = "point", Gap = 2 })
	end

	local panel = Overlay.panel(size, position)
	panel.Name = "Menu"
	self.Frame = panel

	local scroll = Scroll.new({ Parent = panel, Direction = "Y", BarThickness = 3 })
	Create.padding(scroll.Content, PAD, PAD, PAD, PAD)
	Create.list(scroll.Content, Enum.FillDirection.Vertical, 0)
	self.Scroll = scroll

	local hasIcons = false
	for _, item in items do
		if item.Icon or item.Checked ~= nil then
			hasIcons = true
			break
		end
	end
	self._iconSpace = if hasIcons then ICON + 8 else 0

	for index, item in items do
		self:_buildRow(index, item)
	end

	local moveConn = UserInputService.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseMovement then
			self:_track()
		end
	end)
	-- Scrolling a long menu moves rows under a still mouse.
	local scrollConn = scroll.Changed:Connect(function()
		self:_track()
	end)

	self.Handle = Overlay.open(panel, {
		Owner = opts.Owner,
		Parent = opts.Parent,
		OnClose = function(reason)
			moveConn:Disconnect()
			scrollConn:Disconnect()
			scroll:Destroy()
			if opts.OnClose then
				opts.OnClose(reason)
			end
			UI.fire("ContextMenu", "Closed", origin, self, reason)
		end,
	})
	UI.fire("ContextMenu", "Created", origin, self, opts)
	UI.fire("ContextMenu", "Opened", origin, self, opts)
	return self
end

function ContextMenu:_buildRow(index: number, item)
	local content = self.Scroll.Content
	local kind = item.Kind and kinds[item.Kind]
	if kind then
		local row = new("Frame", {
			Name = "Custom" .. index,
			Size = UDim2.new(1, 0, 0, itemHeight(item)),
			BackgroundTransparency = 1,
			LayoutOrder = index,
			Parent = content,
		})
		local ok, err = xpcall(kind.Build, debug.traceback, row, item, self)
		if not ok then
			T.Log.error("menu", ("row kind '%s' failed:\n%s"):format(item.Kind, tostring(err)))
			local okImport, Reporter = pcall(T.import, "console/reporter")
			if okImport then
				Reporter.ownerFault(kind.Owner, ("menu row kind '%s'"):format(item.Kind), err)
			end
			row:ClearAllChildren()
			new("TextLabel", {
				Name = "Text",
				Text = (item.Text or item.Kind) .. " (failed)",
				Position = UDim2.fromOffset(ITEM_PAD, 0),
				Size = UDim2.new(1, -ITEM_PAD * 2, 1, 0),
				Theme = { TextColor3 = "TextMuted" },
				Parent = row,
			})
		end
		return
	end
	if item.Separator then
		local holder = new("Frame", {
			Name = "Separator",
			Size = UDim2.new(1, 0, 0, SEPARATOR),
			BackgroundTransparency = 1,
			LayoutOrder = index,
			Parent = content,
		})
		new("Frame", {
			Name = "Line",
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 6, 0.5, 0),
			Size = UDim2.new(1, -12, 0, 1),
			Theme = { BackgroundColor3 = "Border" },
			Parent = holder,
		})
		return
	end

	if item.Header then
		local header = new("TextLabel", {
			Name = "Header" .. index,
			Text = string.upper(item.Header),
			FontFace = Theme.Fonts.Bold,
			TextSize = Sizes.TextSmall,
			Size = UDim2.new(1, 0, 0, Sizes.MenuHeader),
			TextYAlignment = Enum.TextYAlignment.Bottom,
			LayoutOrder = index,
			Theme = { TextColor3 = "TextMuted" },
			Parent = content,
		})
		Create.padding(header, 0, ITEM_PAD, 4, ITEM_PAD)
		return
	end

	local disabled = item.Disabled == true
	local row = new("TextButton", {
		Name = "Item" .. index,
		Size = UDim2.new(1, 0, 0, Sizes.MenuItem),
		BackgroundTransparency = 1,
		LayoutOrder = index,
		Theme = { BackgroundColor3 = "SurfaceHover" },
		Parent = content,
	})
	Create.corner(row, 5)

	local textKey = if disabled then "TextMuted" elseif item.Danger then "Danger" elseif item.Emphasis then "Accent" else "Text"
	local x = ITEM_PAD
	local icon = nil
	if self._iconSpace > 0 then
		local iconName = item.Icon
		if item.Checked ~= nil then
			iconName = "check"
		end
		if iconName then
			icon = Icons.new(iconName, ICON, if item.Checked ~= nil or (item.Emphasis and not disabled) then "Accent" elseif disabled then "TextMuted" else (item.IconColor or "TextDim"))
			icon.AnchorPoint = Vector2.new(0, 0.5)
			icon.Position = UDim2.new(0, x, 0.5, 0)
			icon.Visible = item.Checked ~= false
			icon.Parent = row
		end
		x += self._iconSpace
	end

	local rightSpace = ITEM_PAD + (if item.Items then 16 else 0)
	new("TextLabel", {
		Name = "Text",
		Text = item.Text or "",
		Position = UDim2.fromOffset(x, 0),
		Size = UDim2.new(1, -x - rightSpace, 1, 0),
		TextTruncate = Enum.TextTruncate.AtEnd,
		FontFace = if item.Emphasis then Theme.Fonts.Bold else Theme.Fonts.Regular,
		Theme = { TextColor3 = textKey },
		Parent = row,
	})
	if item.Emphasis and not disabled then
		-- An emphasized entry: a soft accent band behind it.
		local band = new("Frame", {
			Name = "Emphasis",
			Size = UDim2.fromScale(1, 1),
			ZIndex = 0,
			BackgroundTransparency = 0.35,
			Theme = { BackgroundColor3 = "AccentSoft" },
			Parent = row,
		})
		Create.corner(band, 5)
	end
	if item.Shortcut then
		new("TextLabel", {
			Name = "Shortcut",
			Text = item.Shortcut,
			TextSize = Sizes.TextSmall,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -rightSpace, 0, 0),
			Size = UDim2.new(0, 0, 1, 0),
			AutomaticSize = Enum.AutomaticSize.X,
			TextXAlignment = Enum.TextXAlignment.Right,
			Theme = { TextColor3 = "TextMuted" },
			Parent = row,
		})
	end
	local arrow = nil
	if item.Items then
		arrow = Icons.new("chevron_right", 12, if disabled then "TextMuted" else "TextDim")
		arrow.AnchorPoint = Vector2.new(1, 0.5)
		arrow.Position = UDim2.new(1, -8, 0.5, 0)
		arrow.Parent = row
	end

	local entry = { Item = item, Row = row, Icon = icon, Arrow = arrow, Hovered = false, Disabled = disabled }
	self.Rows[index] = entry

	if disabled then
		return
	end

	-- Hover comes from _track (mouse position), not MouseEnter: Roblox
	-- sends MouseEnter to rows hidden under an overlapping submenu too.
	row.Activated:Connect(function()
		if Overlay.popupAt(Overlay.mouse()) ~= self.Handle then
			return -- the click was meant for a menu on top of this one
		end
		if item.Items then
			self:_openChild(entry)
			return
		end
		if item.Checked ~= nil then
			-- Check items flip in place and keep the menu open.
			item.Checked = not item.Checked
			if entry.Icon then
				entry.Icon.Visible = item.Checked
			end
			UI.fire("ContextMenu", "Chosen", self.Origin, self, item)
			if item.Callback then
				task.spawn(function()
					local ok, err = xpcall(item.Callback, debug.traceback, item)
					if not ok then
						T.Log.error("menu", ("'%s' failed:\n%s"):format(tostring(item.Text), tostring(err)))
					end
				end)
			end
			return
		end
		Overlay.closeAll("chosen")
		UI.fire("ContextMenu", "Chosen", self.Origin, self, item)
		if item.Callback then
			task.spawn(function()
				local ok, err = xpcall(item.Callback, debug.traceback, item)
				if not ok then
					T.Log.error("menu", ("'%s' failed:\n%s"):format(tostring(item.Text), tostring(err)))
				end
			end)
		end
	end)
end

-- Which row is under the mouse, counting only this menu when it is the
-- topmost popup there.
function ContextMenu:_track()
	if self.Handle == nil or self.Handle.Closed then
		return
	end
	local point = Overlay.mouse()
	local over = nil
	if Overlay.popupAt(point) == self.Handle and Overlay.inside(self.Scroll.Instance, point) then
		for _, entry in self.Rows do
			if entry.Row.Parent and Overlay.inside(entry.Row, point) then
				over = entry
				break
			end
		end
	end
	if over == self.Hovered then
		return
	end
	local previous = self.Hovered
	self.Hovered = over
	if previous then
		previous.Hovered = false
		self:_style(previous, Animate.Fast)
	end
	if over then
		over.Hovered = not over.Disabled
		self:_style(over, Animate.Fast)
		self:_onHover(over)
	end
end

function ContextMenu:_style(entry, duration: number?)
	local open = self.Child ~= nil and self.Child.Entry == entry
	local lit = (entry.Hovered and not entry.Disabled) or open
	Animate.set(entry.Row, { BackgroundTransparency = if lit then 0 else 1 }, duration)
	Theme.bind(entry.Row, "BackgroundColor3", if open and not entry.Hovered then "SurfaceActive" else "SurfaceHover", duration)
	if entry.Arrow then
		Icons.tint(entry.Arrow, if lit then "Text" else "TextDim", duration)
	end
end

function ContextMenu:_onHover(entry)
	self._hoverToken += 1
	local token = self._hoverToken
	local child = self.Child
	if child and child.Entry == entry then
		return
	end
	task.delay(HOVER_DELAY, function()
		if self._hoverToken ~= token or self.Hovered ~= entry or self.Handle.Closed then
			return
		end
		if entry.Item.Items and not entry.Disabled then
			self:_openChild(entry)
		elseif self.Child then
			self:_closeChild()
		end
	end)
end

function ContextMenu:_closeChild()
	local child = self.Child
	if child then
		self.Child = nil
		child.Menu:Close()
		self:_style(child.Entry, Animate.Fast)
	end
end

function ContextMenu:_openChild(entry)
	if self.Child and self.Child.Entry == entry and not self.Child.Menu.Handle.Closed then
		return
	end
	self:_closeChild()
	local row = entry.Row
	local menu = ContextMenu.open(entry.Item.Items, {
		-- on screen: PAD (layout pixels) drawn at the popup layer's scale
		AnchorPos = row.AbsolutePosition - Vector2.new(0, PAD * Overlay.factor()),
		AnchorSize = row.AbsoluteSize + Vector2.new(PAD * Overlay.factor(), 0),
		Side = "right",
		Gap = 2,
		Parent = self.Handle,
		Origin = self.Origin,
		OnClose = function()
			if self.Child and self.Child.Entry == entry then
				self.Child = nil
				self:_style(entry, Animate.Fast)
			end
		end,
	})
	self.Child = { Entry = entry, Menu = menu }
	self:_style(entry, Animate.Fast)
end

function ContextMenu:Close()
	if self.Handle and not self.Handle.Closed then
		self.Handle:Close("closed")
	end
end

function ContextMenu:IsOpen(): boolean
	return self.Handle ~= nil and not self.Handle.Closed
end

return UI.register("ContextMenu", ContextMenu, {
	Description = "right-click and button menus (named menus are built with base/ui/menus)",
	Constructor = function(props)
		return ContextMenu.open(props.Items or {}, props)
	end,
	Events = {
		Created = "menu, opts · (same as Opened)",
		Opened = "menu, opts · a menu (or submenu) opened",
		Chosen = "menu, item · an item was clicked (check items too)",
		Closed = "menu, reason · it closed",
	},
	Filters = {
		Items = "items, opts · the items about to be drawn (add, remove, reorder)",
	},
})
