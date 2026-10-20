--[[
	Tungsten · base/ui/window
	The main window: hidden ScreenGui, title bar (the only drag handle),
	side bar for the tab bar, path bar strip, content area, and the
	top-center pill that the window minimizes into.

	The explorer panel hangs off the window's right edge (a child of
	Root, so it moves and scales with the window).

	Scale: Root is BaseSize (760 × 460) × the scale, like resizing the
	window; what is inside keeps its size and stretching layouts get the
	room (RootScale stays at Scale.factor(), which is 1). window.Size is
	the size on screen. The pill sits outside Root and keeps its size.

	The window keeps the whole footprint (window + explorer when open) on
	screen as far as it fits:
		window:SetSideOpen(true/false)   -- re-clamps the position
		window:Footprint()               -- size including the explorer
		window:AddVeil(frame)            -- fades with the window's veil

	Signals other parts use to close menus, etc.:
		DragStarted, DragEnded(pos), Moved(pos), Resized(size),
		MinimizedChanged(isMinimized)
]]

local T = ...
local signal = T.import("base/signal")
local Services = T.import("base/services")
local Theme = T.import("base/theme")
local Scale = T.import("base/scale")
local Create = T.import("base/ui/create")
local Animate = T.import("base/ui/animate")
local Icons = T.import("base/data/icons")

local UserInputService = Services.UserInputService

local new = Create.new
local Sizes = Theme.Sizes

local PILL_SHOWN_Y = 22 -- gap from the top of the screen
local PILL_ICON = 22 -- the W mark inside the pill
local PILL_SIZE = 35 -- rounded square around it
local PILL_RADIUS = 9
local FADE = 0.22 -- minimize / restore fade
local DISPLAY_NAME = "tungsten (unified)"

local Window = {}
Window.__index = Window
Window.DisplayName = DISPLAY_NAME
Window.OutlineTransparency = 0.6 -- the faint accent outline around the window and the explorer

local rng = Random.new()

local function randomName(): string
	local chars = {}
	for index = 1, rng:NextInteger(14, 22) do
		local roll = rng:NextInteger(1, 3)
		local code = if roll == 1
			then rng:NextInteger(48, 57)
			elseif roll == 2 then rng:NextInteger(65, 90)
			else rng:NextInteger(97, 122)
		chars[index] = string.char(code)
	end
	return table.concat(chars)
end

Window.randomName = randomName

local function isPointer(input: InputObject): boolean
	local kind = input.UserInputType
	return kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch
end

function Window.new(opts: { [string]: any }?)
	opts = opts or {}
	local self = setmetatable({}, Window)
	self.SideOpen = opts.SideOpen ~= false -- explorer open (counts toward the footprint)
	self.Veils = {}
	self.Bin = signal.bin()
	self.DragStarted = signal.new()
	self.DragEnded = signal.new()
	self.Moved = signal.new()
	self.Resized = signal.new()
	self.MinimizedChanged = signal.new()
	self.Minimized = false
	self.Dragging = false
	self._token = 0
	self._contentToken = 0

	local bin = self.Bin

	------------------------------------------------------------------
	-- Screen container (hidden UI, random name)
	------------------------------------------------------------------
	local gui = new("ScreenGui", {
		Name = randomName(),
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 1000,
	})
	self.Gui = gui
	bin:Add(gui)

	------------------------------------------------------------------
	-- Window frame
	------------------------------------------------------------------
	-- Root is a clear container; Backing (ZIndex 0) draws the window itself.
	-- Things placed under the window (the explorer panel, ZIndex below 0)
	-- can then slide out from underneath it.
	local root = new("Frame", {
		Name = "Window",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Active = true,
		Visible = false,
		BackgroundTransparency = 1,
		Parent = gui,
	})
	local backing = new("Frame", {
		Name = "Backing",
		Size = UDim2.fromScale(1, 1),
		ZIndex = 0,
		Theme = { BackgroundColor3 = "Background" },
		Parent = root,
	})
	Create.corner(backing, Sizes.Radius)
	self.Backing = backing
	-- Squares the window's right corners while the explorer is attached
	-- there, so window and explorer read as one surface.
	self.BackingSquare = new("Frame", {
		Name = "BackingSquare",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(0, Sizes.Radius, 1, 0),
		ZIndex = 0,
		Visible = false,
		Theme = { BackgroundColor3 = "Background" },
		Parent = root,
	})
	-- A faint outline in the accent color (follows the color scheme)
	-- around the window and the explorer together: a clear frame on top
	-- that grows over the explorer while it is open.
	local outline = new("Frame", {
		Name = "Outline",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Active = false,
		ZIndex = 80,
		Parent = root,
	})
	Create.corner(outline, Sizes.Radius)
	self.OutlineFrame = outline
	self.Outline = Create.stroke(outline, "Accent", 1, Window.OutlineTransparency)
	self.Root = root
	self.RootScale = new("UIScale", { Parent = root })

	------------------------------------------------------------------
	-- Title bar
	------------------------------------------------------------------
	local titleBar = new("Frame", {
		Name = "TitleBar",
		Size = UDim2.new(1, 0, 0, Sizes.TitleBar),
		Active = true,
		Theme = { BackgroundColor3 = "Chrome" },
		Parent = root,
	})
	Create.corner(titleBar, Sizes.Radius)
	new("Frame", { -- squares off the bottom corners
		Name = "Square",
		Position = UDim2.new(0, 0, 1, -Sizes.Radius),
		Size = UDim2.new(1, 0, 0, Sizes.Radius),
		Theme = { BackgroundColor3 = "Chrome" },
		Parent = titleBar,
	})
	new("Frame", {
		Name = "Line",
		Position = UDim2.new(0, 0, 1, 0),
		Size = UDim2.new(1, 0, 0, 1),
		Theme = { BackgroundColor3 = "Border" },
		Parent = titleBar,
	})
	self.TitleBar = titleBar

	local heading = new("Frame", {
		Name = "Heading",
		Position = UDim2.fromOffset(12, 0),
		Size = UDim2.new(0, 0, 1, 0),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		ZIndex = 2,
		Parent = titleBar,
	})
	Create.list(heading, Enum.FillDirection.Horizontal, 7, { VerticalAlignment = Enum.VerticalAlignment.Center })

	local logo = Icons.new(Icons.Brand, 18, "Accent") -- the brand icon, same as the pill
	logo.LayoutOrder = 1
	logo.Parent = heading

	-- "tungsten" large in the accent color, "(unified)" small and white.
	new("TextLabel", {
		Name = "Title",
		Text = "tungsten",
		FontFace = Theme.Fonts.Bold,
		TextSize = Sizes.Title + 4,
		Size = UDim2.fromScale(0, 1),
		AutomaticSize = Enum.AutomaticSize.X,
		LayoutOrder = 2,
		Theme = { TextColor3 = "Accent" },
		Parent = heading,
	})
	new("TextLabel", {
		Name = "Unified",
		Text = "(unified)",
		FontFace = Theme.Fonts.Medium,
		TextSize = Sizes.TextSmall,
		Size = UDim2.fromScale(0, 1),
		AutomaticSize = Enum.AutomaticSize.X,
		LayoutOrder = 3,
		Theme = { TextColor3 = "Text" },
		Parent = heading,
	})
	new("TextLabel", {
		Name = "Version",
		Text = "v" .. T.Version,
		TextSize = Sizes.TextSmall,
		Size = UDim2.fromScale(0, 1),
		AutomaticSize = Enum.AutomaticSize.X,
		Theme = { TextColor3 = "TextMuted" },
		LayoutOrder = 4,
		Parent = heading,
	})
	self.Subtitle = new("TextLabel", {
		Name = "Subtitle",
		Text = "",
		Size = UDim2.fromScale(0, 1),
		AutomaticSize = Enum.AutomaticSize.X,
		Theme = { TextColor3 = "TextDim" },
		LayoutOrder = 5,
		Parent = heading,
	})

	-- Buttons at the right end of the title bar (minimize, and the
	-- explorer's open / close button to its right).
	self.TitleBar = titleBar
	self.TitleButtons = {}
	local minimize = self:AddTitleButton({
		Name = "Minimize",
		Icon = "minimize",
		Order = 10,
		OnClick = function()
			self:Minimize()
		end,
	})
	self.MinimizeButton = minimize.Button

	------------------------------------------------------------------
	-- Body: side bar + content
	------------------------------------------------------------------
	local body = new("Frame", {
		Name = "Body",
		Position = UDim2.fromOffset(0, Sizes.TitleBar + 1),
		Size = UDim2.new(1, 0, 1, -(Sizes.TitleBar + 1)),
		BackgroundTransparency = 1,
		Parent = root,
	})

	local sidebar = new("Frame", {
		Name = "Sidebar",
		Size = UDim2.new(0, Sizes.Sidebar, 1, 0),
		Theme = { BackgroundColor3 = "Chrome" },
		Parent = body,
	})
	Create.corner(sidebar, Sizes.Radius)
	new("Frame", { -- square top edge
		Name = "SquareTop",
		Size = UDim2.new(1, 0, 0, Sizes.Radius),
		Theme = { BackgroundColor3 = "Chrome" },
		Parent = sidebar,
	})
	new("Frame", { -- square right edge
		Name = "SquareRight",
		Position = UDim2.new(1, -Sizes.Radius, 0, 0),
		Size = UDim2.new(0, Sizes.Radius, 1, 0),
		Theme = { BackgroundColor3 = "Chrome" },
		Parent = sidebar,
	})
	new("Frame", {
		Name = "Line",
		Position = UDim2.fromOffset(Sizes.Sidebar, 0),
		Size = UDim2.new(0, 1, 1, 0),
		Theme = { BackgroundColor3 = "Border" },
		Parent = body,
	})
	self.Sidebar = sidebar

	-- Path bar strip across the top of the content area (filled by base/ui/pathbar).
	local pathStrip = new("Frame", {
		Name = "PathBar",
		Position = UDim2.fromOffset(Sizes.Sidebar + 1, 0),
		Size = UDim2.new(1, -(Sizes.Sidebar + 1), 0, Sizes.PathBar),
		BackgroundTransparency = 1,
		Parent = body,
	})
	self.PathStrip = pathStrip

	local content = new("Frame", {
		Name = "Content",
		Position = UDim2.fromOffset(Sizes.Sidebar + 1, Sizes.PathBar),
		Size = UDim2.new(1, -(Sizes.Sidebar + 1), 1, -Sizes.PathBar),
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		Parent = body,
	})
	self.Content = content

	-- Fades content in on tab switches.
	self.ContentVeil = new("Frame", {
		Name = "Veil",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 50,
		Theme = { BackgroundColor3 = "Background" },
		Parent = content,
	})

	-- Fades the whole window in/out.
	self.Veil = new("Frame", {
		Name = "Veil",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 100,
		Theme = { BackgroundColor3 = "Background" },
		Parent = root,
	})
	Create.corner(self.Veil, Sizes.Radius)
	table.insert(self.Veils, self.Veil)

	------------------------------------------------------------------
	-- Minimized pill (top center of the screen)
	------------------------------------------------------------------
	-- A rounded square with the colored W mark; fades in and out.
	local pill = new("TextButton", {
		Name = "Pill",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, PILL_SHOWN_Y),
		Size = UDim2.fromOffset(PILL_SIZE, PILL_SIZE),
		Visible = false,
		Theme = { BackgroundColor3 = "Chrome" },
		Parent = gui,
	})
	Create.corner(pill, PILL_RADIUS)
	local pillStroke = Create.stroke(pill, "Accent", 1, 0.45)
	self.PillStroke = pillStroke
	local pillLogo = Icons.new(Icons.Brand, PILL_ICON, "Accent") -- a plain W in the accent color
	pillLogo.Name = "Mark"
	pillLogo.AnchorPoint = Vector2.new(0.5, 0.5)
	pillLogo.Position = UDim2.fromScale(0.5, 0.5)
	pillLogo.Parent = pill
	self.PillScale = Animate.pressable(pill, bin)
	Animate.hover(pill, bin, function(hovered)
		Theme.bind(pill, "BackgroundColor3", if hovered then "Surface" else "Chrome", Animate.Fast)
		if self.Minimized then
			Animate.tween(pillStroke, { Transparency = if hovered then 0 else 0.45 }, Animate.Fast)
		end
	end)
	bin:Add(pill.Activated:Connect(function()
		self:Restore()
	end))
	self.Pill = pill

	------------------------------------------------------------------
	-- Dragging (title bar only, clamped to the screen)
	------------------------------------------------------------------
	local dragInput: InputObject? = nil
	local dragStart = Vector2.zero
	local dragOrigin = Vector2.zero

	bin:Add(titleBar.InputBegan:Connect(function(input)
		if not isPointer(input) or self._overControl or self.Minimized or self.Dragging then
			return
		end
		self.Dragging = true
		dragInput = input
		dragStart = Vector2.new(input.Position.X, input.Position.Y)
		dragOrigin = self.Pos
		self.DragStarted:Fire()
	end))

	bin:Add(UserInputService.InputChanged:Connect(function(input)
		if not self.Dragging then
			return
		end
		local kind = input.UserInputType
		if kind == Enum.UserInputType.MouseMovement or (kind == Enum.UserInputType.Touch and input == dragInput) then
			local point = Vector2.new(input.Position.X, input.Position.Y)
			self:MoveTo(dragOrigin + (point - dragStart))
		end
	end))

	bin:Add(UserInputService.InputEnded:Connect(function(input)
		if self.Dragging and (input == dragInput or input.UserInputType == Enum.UserInputType.MouseButton1) then
			self:_endDrag()
		end
	end))

	------------------------------------------------------------------
	-- Mount + layout
	------------------------------------------------------------------
	gui.Parent = gethui()

	Scale.setViewport(self:_viewport())
	self.RootScale.Scale = Scale.factor()
	self.Size = Scale.windowSize()
	self.Pos = self:_clamp((self:_viewport() - self:Footprint()) / 2, self.Size)
	self:_apply(false)

	-- Screen size changes: the ScreenGui's size is the main signal; the
	-- camera's viewport is a backup in case the container reports late.
	-- A new screen size only moves the limit for the next scale change
	-- and keeps the window's corner on screen; the scale stays.
	local function onViewport()
		Scale.setViewport(self:_viewport())
		self:Fit(false)
	end
	bin:Add(gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(onViewport))
	local cameraConnection: RBXScriptConnection? = nil
	local function watchCamera()
		if cameraConnection then
			cameraConnection:Disconnect()
			cameraConnection = nil
		end
		local camera = workspace.CurrentCamera
		if camera then
			cameraConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(onViewport)
		end
	end
	watchCamera()
	bin:Add(workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		watchCamera()
		onViewport()
	end))
	bin:Add(function()
		if cameraConnection then
			cameraConnection:Disconnect()
		end
	end)
	bin:Add(Scale.Changed:Connect(function()
		self:Fit(true)
	end))

	return self
end

----------------------------------------------------------------------
-- Geometry
----------------------------------------------------------------------

function Window:_viewport(): Vector2
	local size = self.Gui.AbsoluteSize
	if size.X < 1 or size.Y < 1 then
		local camera = workspace.CurrentCamera
		size = if camera then camera.ViewportSize else Vector2.new(1280, 720)
	end
	return size
end

-- Size of everything the window keeps on screen (window + open explorer).
function Window:Footprint(size: Vector2?): Vector2
	size = size or self.Size
	if self.SideOpen then
		return Scale.footprint(size :: Vector2)
	end
	return size :: Vector2
end

function Window:_clamp(pos: Vector2, size: Vector2): Vector2
	local viewport = self:_viewport()
	local footprint = self:Footprint(size)
	local x = math.clamp(pos.X, 0, math.max(0, viewport.X - footprint.X))
	local y = math.clamp(pos.Y, 0, math.max(0, viewport.Y - size.Y))
	return Vector2.new(math.floor(x + 0.5), math.floor(y + 0.5))
end

function Window:_apply(duration: number?)
	local center = self.Pos + self.Size / 2
	-- the window is as big as the scale makes it; its contents are 1:1
	Animate.set(self.Root, {
		Position = UDim2.fromOffset(center.X, center.Y),
		Size = UDim2.fromOffset(self.Size.X, self.Size.Y),
	}, duration or nil)
	Animate.set(self.RootScale, { Scale = Scale.factor() }, duration or nil)
end

function Window:MoveTo(pos: Vector2)
	local clamped = self:_clamp(pos, self.Size)
	if clamped == self.Pos then
		return
	end
	self.Pos = clamped
	self:_apply(nil)
	self.Moved:Fire(clamped)
end

-- Re-fit to the current scale and screen; keeps the window's center.
function Window:Fit(animated: boolean?)
	local newSize = Scale.windowSize()
	local center = self.Pos + self.Size / 2
	self.Size = newSize
	self.Pos = self:_clamp(center - newSize / 2, newSize)
	self:_apply(if animated then Animate.Normal else nil)
	self.Resized:Fire(newSize)
end

-- The explorer opened or closed: keep the new footprint on screen.
--[[
	window:SetAttached(fraction)
	How much of the explorer's width sticks out on the right (0..1). The
	outline goes around the window and that part. The window's right
	corners are square only while the explorer covers them (it sticks out
	by at least a corner radius); otherwise they are round. The explorer
	calls this every frame while it slides, so both follow it exactly.
]]
function Window:SetAttached(fraction: number)
	fraction = math.clamp(fraction, 0, 1)
	self.Attached = fraction
	self.OutlineFrame.Size = UDim2.new(1 + Scale.SideShare * fraction, 0, 1, 0)
	-- how far the explorer sticks out, in the window's own (layout) units
	local out = Scale.SideShare * fraction * self.Size.X
	self.BackingSquare.Visible = fraction > 0 and out >= Sizes.Radius - 0.5
end

local TITLE_BUTTON = 24
local TITLE_GAP = 4
local TITLE_RIGHT = 7

-- Lays the title bar buttons out from the right: the highest Order is
-- the rightmost.
function Window:_layoutTitleButtons()
	table.sort(self.TitleButtons, function(a, b)
		return a.Order > b.Order
	end)
	for index, entry in self.TitleButtons do
		entry.Button.Position = UDim2.new(1, -TITLE_RIGHT - (index - 1) * (TITLE_BUTTON + TITLE_GAP), 0.5, 0)
	end
end

--[[
	window:AddTitleButton({ Name, Icon, Order, OnClick }) -> { Button, Icon, SetActive(on) }
	A button in the title bar, the same size and look as minimize.
	SetActive(true) tints its icon in the accent color (a switch that is on).
]]
function Window:AddTitleButton(spec: { [string]: any })
	local bin = self.Bin
	local button = new("TextButton", {
		Name = spec.Name or "TitleButton",
		AnchorPoint = Vector2.new(1, 0.5),
		Size = UDim2.fromOffset(TITLE_BUTTON, TITLE_BUTTON),
		BackgroundTransparency = 1,
		Theme = { BackgroundColor3 = "SurfaceHover" },
		ZIndex = 2,
		Parent = self.TitleBar,
	})
	Create.corner(button, Sizes.RadiusSmall)
	local icon = Icons.new(spec.Icon or "dummy", 14, "TextDim")
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.5)
	icon.Parent = button
	local entry = { Button = button, Icon = icon, Order = spec.Order or 0, Active = false, Hovered = false }
	local function restyle()
		Icons.tint(icon, if entry.Active then "Accent" elseif entry.Hovered then "Text" else "TextDim", Animate.Fast)
	end
	function entry.SetActive(on: boolean)
		entry.Active = on == true
		restyle()
	end
	Animate.pressable(button, bin)
	Animate.hover(button, bin, function(hovered)
		self._overControl = hovered
		entry.Hovered = hovered
		Animate.tween(button, { BackgroundTransparency = if hovered then 0 else 1 }, Animate.Fast)
		restyle()
	end)
	if spec.OnClick then
		bin:Add(button.Activated:Connect(spec.OnClick))
	end
	table.insert(self.TitleButtons, entry)
	self:_layoutTitleButtons()
	return entry
end

function Window:SetSideOpen(open: boolean, animated: boolean?)
	open = open == true
	if open == self.SideOpen then
		return
	end
	self.SideOpen = open
	local clamped = self:_clamp(self.Pos, self.Size)
	if clamped ~= self.Pos then
		self.Pos = clamped
		self:_apply(if animated then Animate.Normal else nil)
		self.Moved:Fire(clamped)
	end
end

-- Extra veils (e.g. the explorer panel) fade together with the window's.
function Window:AddVeil(frame: Frame)
	table.insert(self.Veils, frame)
	frame.Visible = self.Veil.Visible
	frame.BackgroundTransparency = self.Veil.BackgroundTransparency
end

function Window:_veils(props: { [string]: any }, duration: number?)
	for _, veil in self.Veils do
		if veil.Parent then
			for key, value in props do
				if key ~= "BackgroundTransparency" or not duration then
					(veil :: any)[key] = value
				end
			end
			if duration and props.BackgroundTransparency ~= nil then
				Animate.tween(veil, { BackgroundTransparency = props.BackgroundTransparency }, duration)
			end
		end
	end
end

function Window:_endDrag()
	if not self.Dragging then
		return
	end
	self.Dragging = false
	self.DragEnded:Fire(self.Pos)
end

----------------------------------------------------------------------
-- Title
----------------------------------------------------------------------

function Window:SetSubtitle(text: string?)
	self.Subtitle.Text = if text and text ~= "" then "/  " .. text else ""
end

----------------------------------------------------------------------
-- Animations
----------------------------------------------------------------------

function Window:_nextToken(): number
	self._token += 1
	return self._token
end

-- Brief fade of the content area (used when switching tabs).
function Window:FadeContent()
	self._contentToken += 1
	local token = self._contentToken
	local veil = self.ContentVeil
	veil.BackgroundTransparency = 0
	veil.Visible = true
	Animate.tween(veil, { BackgroundTransparency = 1 }, Animate.Normal)
	task.delay(Animate.Normal, function()
		if self._contentToken == token and veil.Parent then
			veil.Visible = false
		end
	end)
end

function Window:Open()
	self:_nextToken()
	self.RootScale.Scale = Scale.factor()
	self:_veils({ Visible = false })
	Animate.fade(self.Root, "in", Animate.Slow)
end

-- Minimize: the window fades out and the pill fades in at the top of
-- the screen. Restore does the reverse.
function Window:Minimize()
	if self.Minimized then
		return
	end
	self.Minimized = true
	self:_endDrag()
	-- A text box in the window keeps no focus while it is hidden.
	pcall(function()
		local focused = UserInputService:GetFocusedTextBox()
		if focused and focused:IsDescendantOf(self.Root) then
			focused:ReleaseFocus()
		end
	end)
	self:_nextToken()
	self.MinimizedChanged:Fire(true)
	-- A tooltip shown over the window must not stay behind on screen.
	pcall(function()
		T.import("base/ui/components/tooltip").hide()
	end)
	Animate.fade(self.Root, "out", FADE)
	self.Pill.Position = UDim2.new(0.5, 0, 0, PILL_SHOWN_Y)
	self.PillScale.Scale = 1
	Animate.fade(self.Pill, "in", FADE)
	T.Log.debug("window", "minimized")
end

function Window:Restore()
	if not self.Minimized then
		return
	end
	self.Minimized = false
	self:_nextToken()
	self.MinimizedChanged:Fire(false)
	self.RootScale.Scale = Scale.factor()
	Animate.fade(self.Pill, "out", FADE)
	Animate.fade(self.Root, "in", FADE)
	T.Log.debug("window", "restored")
end

function Window:Toggle()
	if self.Minimized then
		self:Restore()
	else
		self:Minimize()
	end
end

function Window:Destroy()
	self._token += 1
	self.Bin:Clean()
	for _, sig in { self.DragStarted, self.DragEnded, self.Moved, self.Resized, self.MinimizedChanged } do
		sig:DisconnectAll()
	end
end

return Window
