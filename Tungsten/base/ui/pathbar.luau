--[[
	Tungsten · base/ui/pathbar
	The strip under the title bar, on every tab, like a file explorer's
	address bar:

		[⌄]  game › Workspace › Map › Door ›                         [→]

	- Shows the path of what is LOADED (base/loaded): one target shared by
	  every tab (explorer › Load, the arrow, a crumb, a typed path, /load,
	  or a plugin). Selecting in the explorer does not change it. Several
	  loaded objects: the first, then "+N". A loaded value that isn't an
	  Instance (a function, a table…) shows as one crumb after the crumbs
	  of the script it came from, when known.
	- Clicking a crumb loads that ancestor; a crumb's chevron opens a
	  searchable list of that object's children (picking one loads it).
	- Clicking the empty part turns it into a text box with the full path;
	  Enter or the arrow loads it (Types.resolvePath, so no code runs).
	  A wrong path shows the reason under the bar; Escape cancels. Long
	  paths scroll inside the box to keep the cursor in view.
	- The arrow outside editing loads the explorer selection, like
	  explorer › Load; with nothing selected it starts editing.
	- The left button has two entries: Copy (the path as code) and
	  Highlight (select it in the explorer, opening the explorer).
	- Long paths scroll sideways (wheel down = left).

		PathBar.show(instance)   -- loads it (Loaded.load), for every tab
		PathBar.clear()          -- nothing loaded (Loaded.clear)
		PathBar.current() -> the first loaded item (Instance or target) or nil
		PathBar.Changed:Connect(function(item) end)
]]

local T = ...
local signal = T.import("base/signal")
local Theme = T.import("base/theme")
local Services = T.import("base/services")
local Types = T.import("base/types")
local Create = T.import("base/ui/create")
local Animate = T.import("base/ui/animate")
local Icons = T.import("base/data/icons")
local Overlay = T.import("base/ui/overlay")
local Scroll = T.import("base/ui/components/scroll")
local Menus = T.import("base/ui/menus")
local Dropdown = T.import("base/ui/components/dropdown")
local Loaded = T.import("base/loaded")
local Access = T.import("base/access")

local new = Create.new
local Sizes = Theme.Sizes

local BUTTON = 26
local GAP = 6
local MAX_CHILDREN = 2000

local PathBar = {}
PathBar.Changed = signal.new() -- (item or nil)

local bar, crumbsScroll, crumbsList, editBox, hint = nil, nil, nil, nil, nil
local menuButton, goButton, backButton, backIcon = nil, nil, nil, nil
local bin = signal.bin()
local crumbBin = signal.bin() -- hover listeners of the current crumbs
local watchers = {} -- connections on the shown instance and its ancestors
local shown: any = nil -- the first loaded item (Instance or target)
local shownAccess: any = nil -- how the shown target is reached in a script (base/access)
local shownCount = 0 -- how many items are loaded
local editing = false
local editClip = nil -- clips the edit box; the box slides inside it
local editScroll = 0 -- how far the edit box is slid left
local pinEnd = false -- keep the end of a long path in view
local errorHandle = nil
local rebuildQueued = false
local Explorer = nil
local Tabs = nil
local stopEditing -- defined under Editing

local function nameOf(obj: Instance): string
	local ok, name = pcall(function()
		return obj.Name
	end)
	return if ok then tostring(name) else "?"
end

local function parentOf(obj: Instance): Instance?
	local ok, parent = pcall(function()
		return obj.Parent
	end)
	return if ok then parent else nil
end

-- Ancestors from the top down, ending with the object itself.
local function chainOf(obj: Instance): ({ Instance }, boolean)
	local chain = {}
	local current: Instance? = obj
	local guard = 0
	while current and guard < 200 do
		guard += 1
		if current == game then
			return chain, true
		end
		table.insert(chain, 1, current)
		current = parentOf(current :: Instance)
	end
	return chain, false
end

local function setClipboard(text: string): boolean
	return (pcall(setclipboard, text))
end

----------------------------------------------------------------------
-- Errors under the bar
----------------------------------------------------------------------

local function closeError()
	if errorHandle and not errorHandle.Closed then
		errorHandle:Close("replaced")
	end
	errorHandle = nil
end

local function showError(text: string)
	closeError()
	local width = math.min(math.ceil(Create.textWidth(text, Sizes.Text)) + 34, 520)
	local size = Vector2.new(width, 28)
	local position = Overlay.place(size, bar.AbsolutePosition, bar.AbsoluteSize, { Side = "below", Gap = 4 })
	local frame = Overlay.panel(size, position)
	frame.Name = "PathError"
	local icon = Icons.new("close", 12, "Danger")
	icon.AnchorPoint = Vector2.new(0, 0.5)
	icon.Position = UDim2.new(0, 10, 0.5, 0)
	icon.Parent = frame
	new("TextLabel", {
		Name = "Text",
		Text = text,
		Position = UDim2.fromOffset(28, 0),
		Size = UDim2.new(1, -36, 1, 0),
		TextTruncate = Enum.TextTruncate.AtEnd,
		Theme = { TextColor3 = "Danger" },
		Parent = frame,
	})
	local handle = Overlay.open(frame, {})
	errorHandle = handle
	PathBar.LastError = text
	task.delay(5, function()
		if errorHandle == handle then
			closeError()
		end
	end)
end

----------------------------------------------------------------------
-- Crumbs
----------------------------------------------------------------------

local function clearCrumbs()
	crumbBin:Clean()
	for _, child in crumbsList:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

-- Highlight: select in the explorer (opening it), scroll to it and flash
-- the row so it is easy to spot.
local function select(obj: Instance)
	if not Explorer then
		return false
	end
	local ok, reason = Explorer.highlight(obj, { Flash = true })
	if not ok then
		showError(("can't show %s: %s"):format(nameOf(obj), tostring(reason)))
	end
	return ok
end
PathBar.highlight = select

-- Loads objects for every tab: explorer › Load when the explorer runs
-- (it reports it), else straight into base/loaded.
local function load(list: { Instance })
	if Explorer and Explorer.load then
		return Explorer.load(list)
	end
	return Loaded.load(list)
end
PathBar.load = function(obj: Instance)
	return load({ obj })
end


local function childOptions(obj: Instance): { any }
	local ok, children = pcall(function()
		return obj:GetChildren()
	end)
	local options = {}
	if not ok then
		return options
	end
	local hidden = Explorer and Explorer.Tree
	for _, child in children do
		local filtered = Explorer and Explorer.Filter and Explorer.Filter.hiddenClass(child)
		if not (hidden and hidden:IsHidden(child)) and not filtered then
			local option = Types.option(child, nameOf(child))
			option.Hint = Types.classOf(child) or ""
			table.insert(options, option)
		end
		if #options >= MAX_CHILDREN then
			break
		end
	end
	table.sort(options, function(a, b)
		return a.Text:lower() < b.Text:lower()
	end)
	return options
end

local function crumbButton(text: string, iconName: string?, iconColor: any, order: number, last: boolean)
	local button = new("TextButton", {
		Name = "Crumb",
		Size = UDim2.fromOffset(0, BUTTON - 4),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		LayoutOrder = order,
		Theme = { BackgroundColor3 = if last then "AccentSoft" else "SurfaceHover" },
		Parent = crumbsList,
	})
	if last then
		button.BackgroundTransparency = 0
	end
	Create.corner(button, 5)
	Create.padding(button, 0, 7, 0, 6)
	Create.list(button, Enum.FillDirection.Horizontal, 5, { VerticalAlignment = Enum.VerticalAlignment.Center })
	if iconName then
		local icon = Icons.new(iconName, 14, iconColor or "TextDim")
		icon.LayoutOrder = 1
		icon.Parent = button
	end
	local label = new("TextLabel", {
		Name = "Text",
		Text = text,
		Size = UDim2.fromScale(0, 1),
		AutomaticSize = Enum.AutomaticSize.X,
		LayoutOrder = 2,
		Theme = { TextColor3 = if last then "Text" else "TextDim" },
		Parent = button,
	})
	Animate.hover(button, crumbBin, function(hovered)
		if not last then
			button.BackgroundTransparency = if hovered then 0 else 1
		end
		Theme.bind(label, "TextColor3", if hovered or last then "Text" else "TextDim", Animate.Fast)
	end)
	return button
end

local function chevron(obj: Instance, order: number)
	local button = new("TextButton", {
		Name = "Chevron",
		Size = UDim2.fromOffset(16, BUTTON - 4),
		BackgroundTransparency = 1,
		LayoutOrder = order,
		Theme = { BackgroundColor3 = "SurfaceHover" },
		Parent = crumbsList,
	})
	Create.corner(button, 4)
	local icon = Icons.new("chevron_right", 11, "TextMuted")
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.5)
	icon.Parent = button
	local popup = nil
	Animate.hover(button, crumbBin, function(hovered)
		button.BackgroundTransparency = if hovered then 0 else 1
		Icons.tint(icon, if hovered then "Text" else "TextMuted", Animate.Fast)
	end)
	local function openList()
		if popup and not popup.Closed then
			popup:Close("toggle")
			return
		end
		if Overlay.justClosed(button) then
			return
		end
		local options = childOptions(obj)
		if #options == 0 then
			options = { { Value = false, Text = "No children", Disabled = true } }
		end
		icon.Rotation = 90
		popup = Dropdown.popup({
			Options = options,
			AnchorPos = button.AbsolutePosition,
			AnchorSize = button.AbsoluteSize,
			Width = 200,
			Searchable = #options > 8,
			Owner = button,
			IsSelected = function()
				return false
			end,
			OnPick = function(option)
				if typeof(option.Value) == "Instance" then
					load({ option.Value })
				end
			end,
			OnClose = function()
				if icon.Parent then
					icon.Rotation = 0
				end
			end,
		})
		PathBar.ChildList = popup
	end
	crumbBin:Add(button.Activated:Connect(openList))
	return button, openList
end

local function unwatch()
	for _, connection in watchers do
		pcall(function()
			connection:Disconnect()
		end)
	end
	table.clear(watchers)
end

local function queueRebuild()
	if rebuildQueued then
		return
	end
	rebuildQueued = true
	task.defer(function()
		rebuildQueued = false
		if bar then
			PathBar._rebuild()
		end
	end)
end

-- The crumb of a loaded value that isn't an Instance.
local function valueCrumb(target, order: number, text: string?)
	local typeName = if target.Kind == "connection" then "RBXScriptConnection"
		elseif target.Kind == "call" or target.Kind == "value" then typeof(target.Value)
		else target.Kind
	local style = T.import("base/data/categories").valueType(typeName)
	local button = crumbButton(text or target.Label, style.Icon, style.Color, order, true)
	button.Name = "Crumb_value"
	return button
end

local function separator(order: number)
	new("TextLabel", {
		Name = "Separator",
		Text = "›",
		Size = UDim2.fromOffset(12, BUTTON - 4),
		TextXAlignment = Enum.TextXAlignment.Center,
		LayoutOrder = order,
		Theme = { TextColor3 = "TextMuted" },
		Parent = crumbsList,
	})
end

-- Loads the value an access reaches (a crumb inside a script).
local function loadAccess(access, label: string?)
	local ok, value = Access.resolve(access)
	if not ok then
		showError(tostring(value))
		return false, value
	end
	if value == nil then
		showError(Access.code(access) .. " is nil")
		return false, "nil"
	end
	if typeof(value) == "Instance" then
		load({ value })
		return true, nil
	end
	Loaded.load({ Loaded.target(value, { Access = access, Label = label or Access.code(access) }) })
	return true, nil
end
PathBar.loadAccess = loadAccess

-- The crumbs inside a script: require() / getsenv(), then keys and upvalues.
local function accessCrumbs(target, access, nextOrder: () -> number)
	local crumbs = Access.crumbs(access)
	for index, crumb in crumbs do
		local last = index == #crumbs
		local prefix = Access.prefix(access, crumb.Depth)
		local button
		if last then
			button = valueCrumb(target, nextOrder(), crumb.Text)
		else
			local style = T.import("base/data/categories").valueType(if crumb.Depth == 0 and access.Root == "getsenv" then "table" else "table")
			button = crumbButton(crumb.Text, style.Icon, style.Color, nextOrder(), false)
			button.Name = "Crumb_step" .. crumb.Depth
			crumbBin:Add(button.Activated:Connect(function()
				loadAccess(prefix, crumb.Text)
			end))
			separator(nextOrder())
		end
		-- right-click: Copy (the code to that point) and Highlight (the script)
		crumbBin:Add(button.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton2 then
				PathBar.Menu = Menus.open("pathbar", { Access = prefix }, { Position = Overlay.pointOf(input) })
			end
		end))
	end
end

-- "+N" after the last crumb when several are loaded.
local function moreLabel(order: number)
	if shownCount <= 1 then
		return
	end
	new("TextLabel", {
		Name = "More",
		Text = ("+%d"):format(shownCount - 1),
		Size = UDim2.fromOffset(0, BUTTON - 4),
		AutomaticSize = Enum.AutomaticSize.X,
		LayoutOrder = order,
		Theme = { TextColor3 = "TextMuted" },
		Parent = crumbsList,
	})
end

function PathBar._rebuild()
	unwatch()
	clearCrumbs()
	local item = shown
	local target = if Loaded.isTarget(item) then item else nil
	-- a value inside a script: where it is reached from (given, or found)
	local access = nil
	if target then
		access = target.Access
		if access == nil and (target.Kind == "function" or target.Kind == "table") then
			local ok, found = pcall(Access.find, target.Value)
			access = if ok then found else nil
		end
	end
	shownAccess = access
	local obj: Instance? = if access then access.Script elseif target then target.Origin else item
	if item == nil then
		new("TextLabel", {
			Name = "Empty",
			Text = "Load something (explorer › Load, or the arrow)",
			Size = UDim2.fromOffset(0, BUTTON - 4),
			AutomaticSize = Enum.AutomaticSize.X,
			LayoutOrder = 1,
			Theme = { TextColor3 = "TextMuted" },
			Parent = crumbsList,
		})
		return
	end
	local order = 0
	local function nextOrder(): number
		order += 1
		return order
	end
	if obj == nil then
		-- a value with no script it came from: one crumb
		valueCrumb(target, nextOrder())
		moreLabel(nextOrder())
		return
	end
	local chain, inGame = chainOf(obj)
	if inGame then
		local root = crumbButton("game", "class_service", nil, nextOrder(), false)
		root.Name = "Crumb_game"
		local _, openServices = chevron(game, nextOrder())
		crumbBin:Add(root.Activated:Connect(openServices))
	else
		local style = T.import("base/data/categories").valueType("nil")
		crumbButton("nil", style.Icon, style.Color, nextOrder(), false).Name = "Crumb_nil"
		local separator = new("TextLabel", {
			Name = "Separator",
			Text = "›",
			Size = UDim2.fromOffset(12, BUTTON - 4),
			TextXAlignment = Enum.TextXAlignment.Center,
			LayoutOrder = nextOrder(),
			Theme = { TextColor3 = "TextMuted" },
			Parent = crumbsList,
		})
		separator.Name = "Separator"
	end
	for index, link in chain do
		local icon, color = Types.icon(link)
		local last = index == #chain and target == nil
		local button = crumbButton(nameOf(link), icon, color, nextOrder(), last)
		crumbBin:Add(button.Activated:Connect(function()
			load({ link })
		end))
		-- Right-click a part of the path: the same Copy / Highlight, for it.
		crumbBin:Add(button.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton2 then
				PathBar.Menu = Menus.open("pathbar", { Instance = link }, { Position = Overlay.pointOf(input) })
			end
		end))
		local okKids, kid = pcall(function()
			return link:FindFirstChildWhichIsA("Instance")
		end)
		if not last or (okKids and kid) then
			chevron(link, nextOrder())
		end
		-- Renames and moves anywhere along the path redraw it (a destroyed
		-- object drops out of base/loaded, which redraws it too).
		pcall(function()
			table.insert(watchers, link:GetPropertyChangedSignal("Name"):Connect(queueRebuild))
			table.insert(watchers, link.AncestryChanged:Connect(queueRebuild))
		end)
	end
	if access then
		accessCrumbs(target, access, nextOrder)
	elseif target then
		valueCrumb(target, nextOrder())
	end
	moreLabel(nextOrder())
	-- Show the end of long paths (again once the crumbs have their size).
	pinEnd = true
	task.defer(function()
		if crumbsScroll then
			crumbsScroll:ScrollTo(Vector2.new(crumbsScroll:MaxOffset().X, 0), false)
		end
	end)
end

----------------------------------------------------------------------
-- What is shown
----------------------------------------------------------------------

-- The Instance a menu or Highlight works on: a loaded Instance (a value
-- has none: Copy and Highlight are greyed for it).
local function shownInstance(): Instance?
	return if typeof(shown) == "Instance" then shown else nil
end

-- What the back button would go to, for its tooltip.
local function describeList(list: { any }): string
	local first = list[1]
	local text
	if typeof(first) == "Instance" then
		local ok, path = pcall(function()
			return first:GetFullName()
		end)
		text = if ok then path else nameOf(first)
	else
		text = tostring(first)
	end
	if #list > 1 then
		text ..= (" +%d"):format(#list - 1)
	end
	return text
end

-- The back button: greyed when there is nothing to go back to.
local function updateBack()
	if not backButton then
		return
	end
	local can = Loaded.canGoBack()
	backButton.AutoButtonColor = false
	backButton:SetAttribute("Enabled", can)
	if backIcon then
		Icons.tint(backIcon, if can then "TextDim" else "TextMuted", Animate.Fast)
		backIcon.ImageTransparency = if can then 0 else 0.55
	end
end
PathBar.updateBack = updateBack

-- Goes back to what was loaded before (the back button).
function PathBar.back(): boolean
	if editing then
		stopEditing()
	end
	local went = Loaded.back("you")
	updateBack()
	return went
end

local function refresh()
	updateBack()
	local item = Loaded.get()
	local count = #Loaded.list()
	if item == shown and count == shownCount and bar then
		return
	end
	shown = item
	shownCount = count
	if not editing and bar then
		PathBar._rebuild()
	end
	PathBar.Changed:Fire(item)
end
PathBar.refresh = refresh

function PathBar.current(): any
	return shown
end

-- Loads obj for every tab (nil: nothing loaded). Extra arguments (the old
-- tab / sub-tab ids) are ignored: there is one loaded target.
function PathBar.show(obj: any, ...: any)
	if obj == nil then
		Loaded.clear()
	else
		Loaded.load({ obj })
	end
end

function PathBar.clear(...: any)
	Loaded.clear()
end

----------------------------------------------------------------------
-- Editing
----------------------------------------------------------------------

-- Slides the edit box so the cursor stays visible in long paths.
local function followCursor()
	if not editBox or not editClip then
		return
	end
	local text = editBox.Text
	local width = Create.textWidth(text, Sizes.CodeText, "Mono")
	local visible = math.max(20, Create.layoutSize(editClip).X)
	local okCursor, cursor = pcall(function()
		return editBox.CursorPosition
	end)
	if not okCursor or type(cursor) ~= "number" or cursor < 1 then
		cursor = #text + 1
	end
	local cursorX = Create.textWidth(text:sub(1, cursor - 1), Sizes.CodeText, "Mono")
	if cursorX - editScroll > visible - 12 then
		editScroll = cursorX - visible + 12
	elseif cursorX - editScroll < 0 then
		editScroll = cursorX
	end
	editScroll = math.clamp(editScroll, 0, math.max(0, width + 12 - visible))
	editBox.Size = UDim2.new(0, math.max(visible, math.ceil(width) + 16), 1, 0)
	editBox.Position = UDim2.fromOffset(-math.floor(editScroll), 0)
end
PathBar._followCursor = followCursor

function stopEditing()
	if not editing then
		return
	end
	editing = false
	editClip.Visible = false
	if editBox:IsFocused() then
		editBox:ReleaseFocus()
	end
	crumbsScroll.Instance.Visible = true
	PathBar._rebuild()
end
PathBar.cancelEdit = stopEditing

function PathBar.edit()
	if editing then
		editBox:CaptureFocus()
		return
	end
	editing = true
	closeError()
	local obj = if Loaded.isTarget(shown) then shown.Origin else shown
	-- a value in a script starts as the code reaching it
	editBox.Text = if Loaded.isTarget(shown) and shownAccess then Access.code(shownAccess) elseif obj then Types.path(obj) else "game."
	editClip.Visible = true
	crumbsScroll.Instance.Visible = false
	editScroll = 0
	followCursor()
	task.defer(function()
		if editing then
			editBox:CaptureFocus()
			pcall(function()
				editBox.CursorPosition = #editBox.Text + 1
			end)
			followCursor()
		end
	end)
end

-- Resolves typed text (never runs it) and loads the result.
function PathBar.go(text: string?): (boolean, string?)
	text = text or editBox.Text
	-- require(path).a.b / getsenv(path).x / debug.getupvalues(...)[n]
	local head = (text :: string):match("^%s*([%a_][%w_%.]*)%s*%(")
	if head == "require" or head == "getsenv" or head == "debug.getupvalues" then
		local access, why = Access.parse(text :: string)
		if not access then
			showError(why or "not a path")
			return false, why
		end
		local ok, value = Access.resolve(access)
		if not ok then
			showError(tostring(value))
			return false, value
		end
		if value == nil then
			showError(Access.code(access) .. " is nil")
			return false, "nil"
		end
		stopEditing()
		local crumbs = Access.crumbs(access)
		if typeof(value) == "Instance" then
			load({ value })
		else
			Loaded.load({ Loaded.target(value, { Access = access, Label = crumbs[#crumbs].Text }) })
		end
		return true, nil
	end
	local obj, reason = Types.resolvePath(text :: string)
	if not obj then
		showError(reason or "not a path")
		return false, reason
	end
	if obj == game then
		showError("game itself isn't in the explorer · add a service, e.g. game.Workspace")
		return false, "game"
	end
	stopEditing()
	load({ obj })
	return true, nil
end

----------------------------------------------------------------------
-- Left menu
----------------------------------------------------------------------

-- The left button's menu ("pathbar", fixed: exactly Copy and Highlight).
-- ctx.Instance is the shown instance (or nil); ctx.Access how a shown value
-- is reached inside a script (Copy gives the code, Highlight the script).
Menus.define("pathbar", {
	Title = "Path bar",
	Locked = true,
	Source = "explorer",
	Header = "Path",
	Sections = { "main" },
})
Menus.addMany("pathbar", {
	{
		Id = "copy",
		Order = 10,
		Text = "Copy",
		Icon = "copy",
		Disabled = function(ctx)
			return ctx.Instance == nil and ctx.Access == nil
		end,
		Callback = function(ctx)
			local obj = ctx.Instance
			if (not obj and not ctx.Access) or not T.Console then
				return
			end
			-- an Instance's path, or the code reaching a value in a script
			local text = if obj then Types.path(obj) else Access.code(ctx.Access)
			local reporter = T.Console.reporter("explorer", { Label = "Explorer", Plugin = false, Kind = "explorer" })
			if setClipboard(text) then
				reporter:success("copied " .. text)
			else
				reporter:error("couldn't copy: the clipboard isn't available")
			end
		end,
	},
	{
		Id = "highlight",
		Order = 20,
		Text = "Highlight",
		Icon = "target",
		Disabled = function(ctx)
			return ctx.Instance == nil and ctx.Access == nil
		end,
		Callback = function(ctx)
			-- a value in a script: its script
			local obj = ctx.Instance or (ctx.Access and ctx.Access.Script)
			if obj then
				select(obj)
			end
		end,
	},
})

function PathBar.menuItems(): { any }
	return Menus.build("pathbar", { Instance = shownInstance(), Access = if shownInstance() then nil else shownAccess })
end

----------------------------------------------------------------------
-- Building
----------------------------------------------------------------------

local function iconButton(name: string, iconName: string, anchorX: number, position: UDim2, enabled: (() -> boolean)?)
	local button = new("TextButton", {
		Name = name,
		AnchorPoint = Vector2.new(anchorX, 0.5),
		Position = position,
		Size = UDim2.fromOffset(BUTTON, BUTTON),
		Theme = { BackgroundColor3 = "Surface" },
		Parent = bar,
	})
	Create.corner(button, Sizes.RadiusSmall)
	local stroke = Create.stroke(button, "Border", 1, 0)
	local icon = Icons.new(iconName, 14, "TextDim")
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.5)
	icon.Parent = button
	Animate.pressable(button, bin)
	Animate.hover(button, bin, function(hovered)
		if enabled and not enabled() then
			hovered = false -- greyed: no hover look
		end
		Theme.bind(button, "BackgroundColor3", if hovered then "SurfaceHover" else "Surface", Animate.Fast)
		Theme.bind(stroke, "Color", if hovered then "BorderStrong" else "Border", Animate.Fast)
		Icons.tint(icon, if hovered then "Accent" else "TextDim", Animate.Fast)
	end)
	return button, icon
end

function PathBar.start(window, explorer, tabs)
	Explorer = explorer
	Tabs = tabs
	local strip = window.PathStrip
	bar = new("Frame", {
		Name = "Bar",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 8, 0.5, 0),
		Size = UDim2.new(1, -16, 0, BUTTON),
		BackgroundTransparency = 1,
		Parent = strip,
	})
	new("Frame", {
		Name = "Line",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 1),
		Theme = { BackgroundColor3 = "Border" },
		Parent = strip,
	})
	PathBar.Instance = bar

	menuButton = iconButton("Menu", "chevron_down", 0, UDim2.new(0, 0, 0.5, 0))
	-- back: right of the menu button; loads what was loaded before
	backButton, backIcon = iconButton("Back", "arrow_left", 0, UDim2.new(0, BUTTON + GAP, 0.5, 0), Loaded.canGoBack)
	goButton = iconButton("Go", "arrow_right", 1, UDim2.new(1, 0, 0.5, 0))
	PathBar.MenuButton, PathBar.GoButton, PathBar.BackButton = menuButton, goButton, backButton
	pcall(T.import("base/ui/components/tooltip").attach, backButton, function()
		local list = Loaded.previous()
		return if list then "Back to " .. describeList(list) else "Nothing to go back to"
	end)
	bin:Add(backButton.Activated:Connect(function()
		PathBar.back()
	end))

	-- The path field between the buttons.
	local field = new("TextButton", {
		Name = "Field",
		Position = UDim2.fromOffset((BUTTON + GAP) * 2, 0),
		Size = UDim2.new(1, -(BUTTON + GAP) * 3, 1, 0),
		Theme = { BackgroundColor3 = "Chrome" },
		Parent = bar,
	})
	Create.corner(field, Sizes.RadiusSmall)
	local fieldStroke = Create.stroke(field, "Border", 1, 0)
	PathBar.Field = field

	crumbsScroll = Scroll.new({ Name = "Crumbs", Direction = "X", BarThickness = 2, Position = UDim2.fromOffset(2, 0), Size = UDim2.new(1, -4, 1, 0), Parent = field })
	bin:Add(crumbsScroll)
	crumbsList = crumbsScroll.Content
	crumbsList.Size = UDim2.new(0, 0, 1, 0)
	Create.list(crumbsList, Enum.FillDirection.Horizontal, 1, { VerticalAlignment = Enum.VerticalAlignment.Center })
	Create.padding(crumbsList, 0, 4, 0, 2)
	PathBar.Crumbs = crumbsList

	editClip = new("Frame", {
		Name = "EditClip",
		Position = UDim2.fromOffset(9, 0),
		Size = UDim2.new(1, -18, 1, 0),
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		Visible = false,
		Parent = field,
	})
	editBox = new("TextBox", {
		Name = "Edit",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		FontFace = Theme.Fonts.Mono,
		TextSize = Sizes.CodeText,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = editClip,
	})
	PathBar.EditClip = editClip
	PathBar.EditBox = editBox

	bin:Add(field.Activated:Connect(function()
		if not editing then
			PathBar.edit()
		end
	end))
	bin:Add(editBox.Focused:Connect(function()
		Theme.bind(fieldStroke, "Color", "Accent", Animate.Fast)
	end))
	bin:Add(editBox.FocusLost:Connect(function(enterPressed)
		Theme.bind(fieldStroke, "Color", "Border", Animate.Fast)
		if enterPressed then
			if not PathBar.go(editBox.Text) then
				-- Keep the box open and focused so the path can be fixed.
				task.defer(function()
					if editing and editBox then
						editBox:CaptureFocus()
					end
				end)
			end
			return
		end
		-- Pressing the arrow also ends focus: keep editing; its click goes
		-- there. Anything else ends editing.
		if goButton and Overlay.shown(goButton) and Overlay.inside(goButton, Overlay.mouse()) then
			return
		end
		task.delay(0.05, function()
			if editing and editBox and not editBox:IsFocused() then
				stopEditing()
			end
		end)
	end))
	bin:Add(editBox:GetPropertyChangedSignal("Text"):Connect(function()
		closeError()
		followCursor()
	end))
	bin:Add(editBox:GetPropertyChangedSignal("CursorPosition"):Connect(followCursor))
	bin:Add(crumbsList:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		if pinEnd and crumbsScroll then
			crumbsScroll:ScrollTo(Vector2.new(crumbsScroll:MaxOffset().X, 0), false)
		end
	end))
	-- Escape cancels editing (the box may not report it as lost focus).
	bin:Add(Services.UserInputService.InputBegan:Connect(function(input)
		if editing and input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode == Enum.KeyCode.Escape then
			stopEditing()
		end
	end))

	bin:Add(goButton.Activated:Connect(function()
		if editing then
			PathBar.go(editBox.Text)
			return
		end
		-- Like explorer › Load: the selection is loaded for every tab.
		local selection = if Explorer then Explorer.getSelection() else {}
		if #selection > 0 then
			load(selection)
		else
			PathBar.edit()
		end
	end))
	local menuOpen = nil
	bin:Add(menuButton.Activated:Connect(function()
		if menuOpen and menuOpen:IsOpen() then
			menuOpen:Close()
			return
		end
		if Overlay.justClosed(PathBar) then
			return
		end
		menuOpen = Menus.open("pathbar", { Instance = shownInstance(), Access = if shownInstance() then nil else shownAccess }, {
			AnchorPos = menuButton.AbsolutePosition,
			AnchorSize = menuButton.AbsoluteSize,
			Side = "below",
			Gap = 4,
			MinWidth = 150,
			Owner = PathBar,
		})
		PathBar.Menu = menuOpen
	end))

	bin:Add(Loaded.Changed:Connect(function()
		refresh()
	end))

	shown = nil
	shownCount = 0
	PathBar._rebuild()
	refresh()

	bin:Add(function()
		closeError()
		unwatch()
		crumbBin:Clean()
		PathBar.Changed:DisconnectAll()
		bar, crumbsScroll, crumbsList, editBox = nil, nil, nil, nil
		backButton, backIcon = nil, nil
		shown = nil
		shownCount = 0
		editing = false
		Explorer, Tabs = nil, nil
	end)
	T.Bin:Add(bin)
end

return PathBar
