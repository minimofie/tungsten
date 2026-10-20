--[[
	Tungsten · base/ui/overlay
	The top layer that menus, dropdowns and pickers open on. It is its own
	hidden ScreenGui above the window, so popups can extend past the
	window's edges.

		local handle = Overlay.open(frame, {
			Owner = self,              -- who opened it (see justClosed)
			Parent = parentHandle,     -- submenus: closes with its parent
			Modal = true,              -- dialogs: a click elsewhere doesn't close it
			OnClose = function(reason) end,
		})
		handle:Close()

	Every open popup closes on: Escape, a click outside all popups, window
	drag, minimize, window resize, tab switch and explorer collapse.

	Scale: popups open on a layer with a UIScale of Scale.factor(), so
	they grow and shrink with the window. Popups that belong to the
	command bar (its suggestions) pass Fixed = true and open on a second
	layer that is never scaled. A popup's Size and Position are layout
	pixels of its layer; place() takes on-screen anchors and returns a
	layout position for that layer:
		Overlay.open(frame, { Fixed = true }) ; Overlay.place(size, …, { Fixed = true })
		Overlay.factor(fixed?) ; Overlay.toLayout(point, fixed?) -> layer position
		Overlay.layoutViewport(fixed?) ; Overlay.maxHeight(fixed?)

	Coordinates: everything here works in AbsolutePosition space (what
	GuiObject.AbsolutePosition reports). Roblox measures the mouse
	(GetMouseLocation) from the very top of the screen, but AbsolutePosition
	may be measured from below the top bar even in a ScreenGui that ignores
	the inset. Overlay.origin() measures that difference at run time, and
	mouse(), pointOf() and place() convert with it, so hit tests and popup
	positions line up whichever way Roblox reports them.
]]

local T = ...
local signal = T.import("base/signal")
local Services = T.import("base/services")
local Animate = T.import("base/ui/animate")
local Create = T.import("base/ui/create")

local UserInputService = Services.UserInputService
local Scale = T.import("base/scale")

local MARGIN = 6 -- popups keep this gap from screen edges
local frameCount = 0 -- render frame counter (both halves of one click arrive in the same frame)

local Overlay = {}
Overlay.Margin = MARGIN
Overlay.Opened = signal.new() -- (handle)
Overlay.Closed = signal.new() -- (handle, reason)

local gui: ScreenGui? = nil
local layer: Frame? = nil -- scaled popups
local fixedLayer: Frame? = nil -- command bar popups (never scaled)
local layerScale: UIScale? = nil
local stack = {} -- open handles, oldest first
local uiRoots = {} -- GuiObjects counted as "our UI" for pointer checks
local lastClosed = setmetatable({}, { __mode = "k" }) -- owner -> os.clock()

----------------------------------------------------------------------
-- Geometry helpers
----------------------------------------------------------------------

-- Where the screen's top-left corner is in AbsolutePosition space.
function Overlay.origin(): Vector2
	if fixedLayer then
		return fixedLayer.AbsolutePosition
	end
	return Vector2.zero
end

-- How big a layer draws its popups (1 for the fixed layer).
function Overlay.factor(fixed: boolean?): number
	if fixed then
		return 1
	end
	return Scale.factor()
end

-- A point in AbsolutePosition space as a position on a layer.
function Overlay.toLayout(point: Vector2, fixed: boolean?): Vector2
	return (point - Overlay.origin()) / Overlay.factor(fixed)
end

-- Mouse position in AbsolutePosition space.
function Overlay.mouse(): Vector2
	return UserInputService:GetMouseLocation() + Overlay.origin()
end

-- Point (AbsolutePosition space) for a mouse or touch input.
function Overlay.pointOf(input: InputObject): Vector2
	if input.UserInputType == Enum.UserInputType.Touch then
		-- Touch positions exclude the top-bar inset; make them screen
		-- positions, then convert like the mouse.
		local inset = Services.GuiService:GetGuiInset()
		return Vector2.new(input.Position.X, input.Position.Y) + inset + Overlay.origin()
	end
	return Overlay.mouse()
end

-- The screen in on-screen pixels.
function Overlay.viewport(): Vector2
	local size = if fixedLayer then fixedLayer.AbsoluteSize else Vector2.zero
	if size.X < 1 or size.Y < 1 then
		local camera = workspace.CurrentCamera
		size = if camera then camera.ViewportSize else Vector2.new(1280, 720)
	end
	return size
end

-- The screen in a layer's layout pixels.
function Overlay.layoutViewport(fixed: boolean?): Vector2
	return Overlay.viewport() / Overlay.factor(fixed)
end

function Overlay.inside(gui: GuiObject, point: Vector2): boolean
	local pos, size = gui.AbsolutePosition, gui.AbsoluteSize
	return point.X >= pos.X and point.Y >= pos.Y and point.X < pos.X + size.X and point.Y < pos.Y + size.Y
end

-- Whether a GuiObject and all its GuiObject ancestors are visible.
function Overlay.shown(object: Instance): boolean
	local current: Instance? = object
	while current do
		if current:IsA("GuiObject") then
			if not (current :: GuiObject).Visible then
				return false
			end
		elseif current:IsA("LayerCollector") then
			return (current :: any).Enabled ~= false
		end
		current = current.Parent
	end
	return false
end

--[[
	Position for a popup of `size` next to an anchor rectangle.

	opts.Side = "below" (dropdowns: under the anchor, flips above)
	          | "right" (submenus: right of the anchor, flips left)
	          | "point" (context menus: at a point, flips left/up)
	opts.Gap  = layout pixels between anchor and popup
	opts.Fixed = true for the command bar's (unscaled) layer
	size is the popup's layout size. The anchor is in AbsolutePosition
	space (on-screen pixels, e.g. a button's AbsolutePosition /
	AbsoluteSize); the result is a layout position on the popup's layer
	(UDim2.fromOffset), always fully on screen as far as the size allows.
]]
function Overlay.place(size: Vector2, anchorPos: Vector2, anchorSize: Vector2?, opts: { [string]: any }?): Vector2
	opts = opts or {}
	local fixed = opts.Fixed == true
	local factor = Overlay.factor(fixed)
	anchorPos = Overlay.toLayout(anchorPos, fixed)
	local side = opts.Side or "point"
	local gap = opts.Gap or 0
	local view = Overlay.layoutViewport(fixed)
	local aSize = (anchorSize or Vector2.zero) / factor
	local left, top = anchorPos.X, anchorPos.Y
	local right, bottom = left + aSize.X, top + aSize.Y
	local x, y

	if side == "below" then
		x = left
		y = bottom + gap
		if y + size.Y > view.Y - MARGIN and top - gap - size.Y >= MARGIN then
			y = top - gap - size.Y -- flip above
		end
	elseif side == "right" then
		x = right + gap
		if x + size.X > view.X - MARGIN and left - gap - size.X >= MARGIN then
			x = left - gap - size.X -- flip left
		end
		y = top
		if y + size.Y > view.Y - MARGIN then
			y = view.Y - MARGIN - size.Y -- slide up
		end
	else
		x = left + gap
		y = top + gap
		if x + size.X > view.X - MARGIN then
			x = left - gap - size.X -- flip left
		end
		if y + size.Y > view.Y - MARGIN then
			y = top - gap - size.Y -- flip up
		end
	end

	x = math.clamp(x, MARGIN, math.max(MARGIN, view.X - MARGIN - size.X))
	y = math.clamp(y, MARGIN, math.max(MARGIN, view.Y - MARGIN - size.Y))
	return Vector2.new(math.floor(x + 0.5), math.floor(y + 0.5))
end

-- Tallest a popup may be (layout pixels of its layer).
function Overlay.maxHeight(fixed: boolean?): number
	return Overlay.layoutViewport(fixed).Y - MARGIN * 2
end

----------------------------------------------------------------------
-- Popups
----------------------------------------------------------------------

local Handle = {}
Handle.__index = Handle

function Handle:Close(reason: string?)
	if self.Closed then
		return
	end
	self.Closed = true
	-- Children (submenus) first.
	for index = #stack, 1, -1 do
		local other = stack[index]
		if other ~= self and other.Parent == self then
			other:Close(reason)
		end
	end
	local index = table.find(stack, self)
	if index then
		table.remove(stack, index)
	end
	-- Remember only clicks that closed it from outside: that same click
	-- may be on the owner's button, which must not reopen it.
	if self.Owner ~= nil and reason == "outside" then
		lastClosed[self.Owner] = os.clock()
	end
	if self.OnClose then
		local ok, err = pcall(self.OnClose, reason)
		if not ok then
			T.Log.warn("overlay", "close callback failed: " .. tostring(err))
		end
	end
	local frame = self.Frame
	if frame and frame.Parent then
		frame:Destroy()
	end
	Overlay.Closed:Fire(self, reason)
end

function Handle:IsOpen(): boolean
	return not self.Closed
end

function Overlay.layer(fixed: boolean?): Frame
	assert(layer, "overlay not started")
	return (if fixed then fixedLayer else layer) :: Frame
end

-- The overlay's ScreenGui (the explorer leaves it out of the tree).
function Overlay.gui(): ScreenGui?
	return gui
end

function Overlay.open(frame: GuiObject, opts: { [string]: any }?): any
	assert(layer, "overlay not started")
	opts = opts or {}
	local handle = setmetatable({
		Frame = frame,
		Owner = opts.Owner,
		Parent = opts.Parent,
		OnClose = opts.OnClose,
		Closed = false,
		OpenedFrame = frameCount,
		-- Modal popups (dialogs) stay open when you click elsewhere.
		Modal = opts.Modal == true,
		Fixed = opts.Fixed == true,
	}, Handle)
	table.insert(stack, handle)
	frame.ZIndex = 10 + #stack * 10
	frame.Parent = if handle.Fixed then fixedLayer else layer
	Overlay.Opened:Fire(handle)
	return handle
end

-- Close every popup (optionally keeping one handle and its parents).
function Overlay.closeAll(reason: string?)
	for index = #stack, 1, -1 do
		local handle = stack[index]
		if handle then
			handle:Close(reason)
		end
	end
end

-- Close popups opened after `handle` that are not its ancestors/itself.
function Overlay.closeAbove(handle)
	for index = #stack, 1, -1 do
		local other = stack[index]
		if other == handle then
			break
		end
		other:Close("replaced")
	end
end

function Overlay.isOpen(): boolean
	return #stack > 0
end

function Overlay.top()
	return stack[#stack]
end

-- True for a short moment after a popup owned by `owner` closed. Buttons
-- that toggle a popup use it so the click that closed it doesn't reopen it.
function Overlay.justClosed(owner: any): boolean
	local at = lastClosed[owner]
	return at ~= nil and os.clock() - at < 0.25
end

-- Popup under a screen point, if any.
function Overlay.popupAt(point: Vector2)
	for index = #stack, 1, -1 do
		local handle = stack[index]
		if handle.Frame.Parent and Overlay.inside(handle.Frame, point) then
			return handle
		end
	end
	return nil
end

----------------------------------------------------------------------
-- "Is the pointer over Tungsten?" (used to stop the camera zooming
-- while the mouse wheel scrolls our lists)
----------------------------------------------------------------------

function Overlay.addRoot(object: GuiObject)
	table.insert(uiRoots, object)
end

function Overlay.pointerOverUI(point: Vector2?): boolean
	point = point or Overlay.mouse()
	if Overlay.popupAt(point :: Vector2) then
		return true
	end
	for _, root in uiRoots do
		if root.Parent and Overlay.shown(root) and Overlay.inside(root, point :: Vector2) then
			return true
		end
	end
	return false
end

----------------------------------------------------------------------
-- Start / stop
----------------------------------------------------------------------

-- window: base/ui/window object; tabs: base/ui/tabbar object (optional).
function Overlay.start(window, randomName: string)
	assert(gui == nil, "overlay already started")
	local bin = signal.bin()

	gui = Create.new("ScreenGui", {
		Name = randomName,
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = (window.Gui.DisplayOrder or 1000) + 1,
	})
	-- The fixed layer covers the screen; the scaled one is 1/factor of
	-- the screen in layout pixels, so drawn at the factor it covers it too.
	fixedLayer = Create.new("Frame", {
		Name = "Fixed",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = gui,
	})
	layer = Create.new("Frame", {
		Name = "Layer",
		BackgroundTransparency = 1,
		Parent = gui,
	})
	layerScale = Create.new("UIScale", { Parent = layer })
	local function applyScale()
		local factor = Scale.factor()
		;(layerScale :: UIScale).Scale = factor
		;(layer :: Frame).Size = UDim2.fromScale(1 / factor, 1 / factor)
	end
	applyScale()
	bin:Add(Scale.Changed:Connect(applyScale))
	bin:Add(gui)
	gui.Parent = gethui()

	Overlay.addRoot(window.Root)
	Overlay.addRoot(window.Pill)

	bin:Add(Services.RunService.RenderStepped:Connect(function()
		frameCount += 1
	end))

	-- Outside clicks and Escape.
	bin:Add(UserInputService.InputBegan:Connect(function(input)
		if #stack == 0 then
			return
		end
		local kind = input.UserInputType
		if
			kind == Enum.UserInputType.MouseButton1
			or kind == Enum.UserInputType.MouseButton2
			or kind == Enum.UserInputType.MouseButton3
			or kind == Enum.UserInputType.Touch
		then
			if not Overlay.popupAt(Overlay.pointOf(input)) then
				-- Roblox runs a GUI object's InputBegan before this listener,
				-- so a right-click that just opened a menu reaches here too.
				-- Popups opened by this same click stay open.
				for index = #stack, 1, -1 do
					local handle = stack[index]
					if handle and not handle.Closed and handle.OpenedFrame ~= frameCount and not handle.Modal then
						handle:Close("outside")
					end
				end
			end
		elseif kind == Enum.UserInputType.Keyboard and input.KeyCode == Enum.KeyCode.Escape then
			Overlay.closeAll("escape")
		end
	end))

	-- Window events.
	bin:Add(window.DragStarted:Connect(function()
		Overlay.closeAll("drag")
	end))
	bin:Add(window.MinimizedChanged:Connect(function()
		Overlay.closeAll("minimize")
	end))
	bin:Add(window.Resized:Connect(function()
		Overlay.closeAll("resize")
	end))

	bin:Add(function()
		Overlay.closeAll("shutdown")
		table.clear(uiRoots)
		gui = nil
		layer = nil
		fixedLayer = nil
		layerScale = nil
	end)
	T.Bin:Add(bin)
end

-- Tab switches close popups too (tab bar is created after the overlay).
function Overlay.watchTabs(tabs)
	T.Bin:Add(tabs.Changed:Connect(function()
		Overlay.closeAll("tab")
	end))
end

----------------------------------------------------------------------
-- Shared popup look: panel with border, shadow-free, rounded, and a
-- short open animation (grow + fade from the surface color).
----------------------------------------------------------------------

function Overlay.panel(size: Vector2, position: Vector2): (Frame, Frame)
	local frame = Create.new("Frame", {
		Name = "Popup",
		Position = UDim2.fromOffset(position.X, position.Y),
		Size = UDim2.fromOffset(size.X, size.Y),
		Active = true,
		Theme = { BackgroundColor3 = "Surface" },
	})
	Create.corner(frame, 7)
	Create.stroke(frame, "BorderStrong", 1, 0)

	local scale = Create.new("UIScale", { Scale = 0.96, Parent = frame })
	local veil = Create.new("Frame", {
		Name = "Veil",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 0,
		ZIndex = 200,
		Active = false,
		Theme = { BackgroundColor3 = "Surface" },
		Parent = frame,
	})
	Create.corner(veil, 7)
	Animate.tween(scale, { Scale = 1 }, Animate.Fast)
	Animate.tween(veil, { BackgroundTransparency = 1 }, Animate.Fast)
	task.delay(Animate.Fast + 0.02, function()
		if veil.Parent then
			veil:Destroy()
		end
	end)
	return frame, veil
end

return Overlay
