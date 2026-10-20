--[[
	Tungsten · base/ui/components/scroll
	The shared scroll area: mouse wheel, Shift+wheel for sideways,
	draggable themed bars that only appear when content overflows,
	smooth motion, and no camera zoom while the wheel is over Tungsten.

	Two modes:
	  "content" (default) — children go in scroll.Content, which sizes
	      itself (AutomaticSize) and is moved by the scroll offset.
	  "virtual" — the owner draws only what is visible. It tells the
	      scroll its full size with SetCanvasSize and redraws on Changed.

		local scroll = Scroll.new({ Parent = page, Direction = "Y" })
		Create.list(scroll.Content, Enum.FillDirection.Vertical, 4)

	Direction: "Y" (default), "X" or "XY".
]]

local T = ...
local signal = T.import("base/signal")
local Services = T.import("base/services")
local Theme = T.import("base/theme")
local Create = T.import("base/ui/create")
local Animate = T.import("base/ui/animate")
local Overlay = T.import("base/ui/overlay")
local UI = T.import("base/ui/ui")

local UserInputService = Services.UserInputService
local RunService = Services.RunService
local ContextActionService = Services.ContextActionService

local new = Create.new
local WHEEL_STEP = 64
local MIN_THUMB = 22
local BAR_INSET = 2
local SINK_ACTION = "TungstenWheelSink"

local Scroll = {}
Scroll.__index = Scroll

----------------------------------------------------------------------
-- Wheel routing (one listener for all scroll areas)
----------------------------------------------------------------------

local live = {} -- scroll objects
local routerStarted = false
local sinkBound = false

local function depth(object: Instance): number
	local count = 0
	local current = object.Parent
	while current do
		count += 1
		current = current.Parent
	end
	return count
end

local function inOverlay(object: Instance): boolean
	local ok, layer = pcall(Overlay.layer)
	return ok and object:IsDescendantOf(layer)
end

-- Innermost visible scroll area under the point that can move in `axis`.
local function target(point: Vector2, axis: string)
	local overPopup = Overlay.popupAt(point) ~= nil
	local best, bestDepth = nil, -1
	for _, scroll in live do
		local view = scroll.Instance
		if view.Parent and scroll:CanScroll(axis) and Overlay.inside(view, point) and Overlay.shown(view) then
			if (not overPopup) or inOverlay(view) then
				local d = depth(view)
				if d > bestDepth then
					best, bestDepth = scroll, d
				end
			end
		end
	end
	return best
end

local function setSink(on: boolean)
	if on == sinkBound then
		return
	end
	sinkBound = on
	if on then
		ContextActionService:BindActionAtPriority(SINK_ACTION, function()
			return Enum.ContextActionResult.Sink
		end, false, Enum.ContextActionPriority.High.Value + 100, Enum.UserInputType.MouseWheel)
	else
		ContextActionService:UnbindAction(SINK_ACTION)
	end
end

-- Shift tracking. Three sources, because Roblox doesn't always report
-- Shift the same way while the wheel turns (another script may sink the
-- key, and IsKeyDown can miss it): the wheel input's own modifier flags,
-- Shift presses we saw ourselves, and IsKeyDown.
local shiftHeld = { [Enum.KeyCode.LeftShift] = false, [Enum.KeyCode.RightShift] = false }

local function shiftDown(input: InputObject?): boolean
	if input then
		local ok, down = pcall(function()
			return input:IsModifierKeyDown(Enum.ModifierKey.Shift)
		end)
		if ok and down then
			return true
		end
	end
	return shiftHeld[Enum.KeyCode.LeftShift]
		or shiftHeld[Enum.KeyCode.RightShift]
		or UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
		or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
end

-- Scroll whatever is under the pointer. `axis` is the requested direction.
local function route(axis: string, delta: number)
	local point = Overlay.mouse()
	local scroll = target(point, axis)
	if not scroll then
		if axis == "Y" then
			-- Areas that only scroll sideways take the plain wheel too.
			local sideways = target(point, "X")
			if sideways and sideways.Direction == "X" then
				scroll, axis = sideways, "X"
			end
		else
			-- Shift+wheel over something that can't scroll sideways scrolls it down instead.
			scroll = target(point, "Y")
			axis = "Y"
		end
	end
	if scroll then
		if axis == "X" then
			-- Every sideways scroll (Shift+wheel, tilt/touchpad input, and the
			-- plain wheel on sideways-only areas): wheel down moves left, up moves right.
			delta = -delta
		end
		scroll:ScrollBy(if axis == "X" then Vector2.new(delta, 0) else Vector2.new(0, delta), true)
	end
end

local function startRouter()
	if routerStarted then
		return
	end
	routerStarted = true

	T.Bin:Add(UserInputService.InputBegan:Connect(function(input)
		if shiftHeld[input.KeyCode] ~= nil then
			shiftHeld[input.KeyCode] = true
		end
	end))
	T.Bin:Add(UserInputService.InputEnded:Connect(function(input)
		if shiftHeld[input.KeyCode] ~= nil then
			shiftHeld[input.KeyCode] = false
		end
	end))
	-- The window losing focus can swallow the key-up.
	T.Bin:Add(UserInputService.WindowFocusReleased:Connect(function()
		shiftHeld[Enum.KeyCode.LeftShift] = false
		shiftHeld[Enum.KeyCode.RightShift] = false
	end))

	T.Bin:Add(UserInputService.InputChanged:Connect(function(input)
		local kind = input.UserInputType
		if kind == Enum.UserInputType.MouseMovement then
			-- Stop the camera zooming while the pointer is over our UI.
			setSink(Overlay.pointerOverUI())
		elseif kind == Enum.UserInputType.MouseWheel then
			local z = input.Position.Z
			if z ~= 0 then
				route(if shiftDown(input) then "X" else "Y", -z * WHEEL_STEP)
			end
		end
	end))

	-- Sideways wheel movement. On Windows, Shift+wheel (and tilt wheels and
	-- touchpads) can arrive as a sideways "pan" instead of a wheel turn;
	-- Roblox reports that only through PointerAction.
	T.Bin:Add(UserInputService.PointerAction:Connect(function(_wheel: number, pan: Vector2)
		if pan and pan.X ~= 0 then
			local amount = if math.abs(pan.X) <= 4 then pan.X * WHEEL_STEP else pan.X
			route("X", amount)
		end
	end))

	T.Bin:Add(function()
		setSink(false)
		table.clear(live)
		routerStarted = false
	end)
end

----------------------------------------------------------------------
-- Construction
----------------------------------------------------------------------

local function makeBar(self, axis: string)
	local vertical = axis == "Y"
	local track = new("Frame", {
		Name = "Bar" .. axis,
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 40,
		Active = true,
		Parent = self.Instance,
	})
	-- holder: position/length along the bar (set instantly);
	-- thumb: the visible pill inside it (thickness animates on hover).
	local holder = new("TextButton", { -- its own click target, so grabbing never depends on coordinates
		Name = "Holder",
		Text = "",
		AutoButtonColor = false,
		Selectable = false,
		BackgroundTransparency = 1,
		Size = if vertical then UDim2.new(1, 0, 0, MIN_THUMB) else UDim2.new(0, MIN_THUMB, 1, 0),
		ZIndex = 41,
		Parent = track,
	})
	local thumb = new("Frame", {
		Name = "Thumb",
		AnchorPoint = if vertical then Vector2.new(1, 0) else Vector2.new(0, 1),
		Position = if vertical then UDim2.fromScale(1, 0) else UDim2.fromScale(0, 1),
		BackgroundTransparency = 0.15,
		Theme = { BackgroundColor3 = "BorderStrong" },
		ZIndex = 42,
		Parent = holder,
	})
	Create.corner(thumb, UDim.new(1, 0))

	local bar = { Axis = axis, Track = track, Holder = holder, Thumb = thumb, Hovered = false, Dragging = false }
	local thickness = self.BarThickness
	thumb.Size = if vertical then UDim2.new(0, thickness, 1, 0) else UDim2.new(1, 0, 0, thickness)

	local function layout(animated: boolean?)
		local wide = if bar.Hovered or bar.Dragging then thickness + 2 else thickness
		local otherVisible = false
		if vertical then
			otherVisible = self.Bars.X ~= nil and self.Bars.X.Track.Visible
			track.AnchorPoint = Vector2.new(1, 0)
			track.Position = UDim2.new(1, -BAR_INSET, 0, BAR_INSET)
			track.Size = UDim2.new(0, thickness + 4, 1, -BAR_INSET * 2 - (if otherVisible then thickness + 4 else 0))
			Animate.set(thumb, { Size = UDim2.new(0, wide, 1, 0) }, if animated then Animate.Fast else nil)
		else
			otherVisible = self.Bars.Y ~= nil and self.Bars.Y.Track.Visible
			track.AnchorPoint = Vector2.new(0, 1)
			track.Position = UDim2.new(0, BAR_INSET, 1, -BAR_INSET)
			track.Size = UDim2.new(1, -BAR_INSET * 2 - (if otherVisible then thickness + 4 else 0), 0, thickness + 4)
			Animate.set(thumb, { Size = UDim2.new(1, 0, 0, wide) }, if animated then Animate.Fast else nil)
		end
	end
	bar.Layout = layout

	local function restyle()
		local active = bar.Hovered or bar.Dragging
		Theme.bind(thumb, "BackgroundColor3", if active then "TextMuted" else "BorderStrong", Animate.Fast)
		layout(true)
	end
	Animate.hover(track, self.Bin, function(hovered)
		bar.Hovered = hovered
		restyle()
	end)

	local function isPress(input: InputObject): boolean
		return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
	end

	-- Grab the thumb and drag it. Movement is measured from where the
	-- press started, so the thumb follows the mouse 1:1.
	self.Bin:Add(holder.InputBegan:Connect(function(input)
		if not isPress(input) or bar.Dragging then
			return
		end
		local key = if vertical then "Y" else "X"
		bar.Dragging = true
		restyle()
		local startPoint = Overlay.pointOf(input)[key]
		local startOffset = self.Target[key]

		local moveConn, endConn
		moveConn = UserInputService.InputChanged:Connect(function(move)
			if move.UserInputType ~= Enum.UserInputType.MouseMovement and move.UserInputType ~= Enum.UserInputType.Touch then
				return
			end
			local view = self:ViewSize()
			local trackLength = track.AbsoluteSize[key]
			local thumbLength = holder.AbsoluteSize[key]
			local range = math.max(1, self.Canvas[key] - view[key])
			local travel = math.max(1, trackLength - thumbLength)
			local now = Overlay.pointOf(move)[key]
			local offset = startOffset + (now - startPoint) / travel * range
			self:ScrollTo(if vertical then Vector2.new(self.Target.X, offset) else Vector2.new(offset, self.Target.Y), false)
		end)
		endConn = UserInputService.InputEnded:Connect(function(ended)
			if isPress(ended) then
				moveConn:Disconnect()
				endConn:Disconnect()
				bar.Dragging = false
				restyle()
			end
		end)
		self.Bin:Add(moveConn)
		self.Bin:Add(endConn)
	end))

	-- A click on the empty track (not the thumb) jumps a page toward it.
	-- Deferred so a press that started a drag on the thumb is never also
	-- treated as a track click, whichever event Roblox delivers first.
	self.Bin:Add(track.InputBegan:Connect(function(input)
		if not isPress(input) then
			return
		end
		local point = Overlay.pointOf(input)
		task.defer(function()
			if bar.Dragging or not track.Parent then
				return
			end
			local key = if vertical then "Y" else "X"
			local view = self:ViewSize()
			local thumbStart = holder.AbsolutePosition[key]
			local thumbEnd = thumbStart + holder.AbsoluteSize[key]
			if point[key] >= thumbStart and point[key] <= thumbEnd then
				return
			end
			local direction = if point[key] < thumbStart then -1 else 1
			local page = view[key] * 0.9 * direction
			self:ScrollBy(if vertical then Vector2.new(0, page) else Vector2.new(page, 0), true)
		end)
	end))

	return bar
end

function Scroll.new(props: { [string]: any })
	local self = setmetatable({}, Scroll)
	self.Bin = signal.bin()
	self.Changed = signal.new() -- (offset: Vector2)
	self.Direction = props.Direction or "Y"
	self.Mode = props.Mode or "content"
	self.Origin = props.Origin or "core"
	self.BarThickness = props.BarThickness or Theme.Sizes.ScrollBar
	self.Canvas = Vector2.zero
	self.Offset = Vector2.zero -- what is shown
	self.Target = Vector2.zero -- where it is heading (smooth scrolling)
	self.Bars = {}
	self._stepping = nil

	local view = new("Frame", {
		Name = props.Name or "Scroll",
		Size = props.Size or UDim2.fromScale(1, 1),
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		BackgroundTransparency = props.BackgroundTransparency or 1,
		ClipsDescendants = true,
		LayoutOrder = props.LayoutOrder or 0,
		Active = false,
	})
	if props.Background then
		Theme.bind(view, "BackgroundColor3", props.Background)
	end
	self.Instance = view
	self.Bin:Add(view)

	if self.Mode == "content" then
		local horizontal = self.Direction ~= "Y"
		local vertical = self.Direction ~= "X"
		local content = new("Frame", {
			Name = "Content",
			BackgroundTransparency = 1,
			Size = UDim2.new(if horizontal then 0 else 1, 0, if vertical then 0 else 1, 0),
			AutomaticSize = if horizontal and vertical
				then Enum.AutomaticSize.XY
				elseif horizontal then Enum.AutomaticSize.X
				else Enum.AutomaticSize.Y,
			Parent = view,
		})
		self.Content = content
		self.Bin:Add(content:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
			self:_measure()
		end))
	end

	if self.Direction ~= "X" then
		self.Bars.Y = makeBar(self, "Y")
	end
	if self.Direction ~= "Y" then
		self.Bars.X = makeBar(self, "X")
	end

	self.Bin:Add(view:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		self:_clampAndApply()
	end))

	self.Bin:Add(Create.cleanupWith(view, self))
	table.insert(live, self)
	startRouter()

	if props.Parent then
		view.Parent = props.Parent
	end
	self:_measure()
	UI.fire("Scroll", "Created", self.Origin, self, props)
	return self
end

----------------------------------------------------------------------
-- Geometry
----------------------------------------------------------------------

-- The visible area in layout pixels (Offset and Canvas are layout pixels
-- too; only pointer maths works on screen).
function Scroll:ViewSize(): Vector2
	return Create.layoutSize(self.Instance)
end

function Scroll:MaxOffset(): Vector2
	local view = self:ViewSize()
	return Vector2.new(math.max(0, self.Canvas.X - view.X), math.max(0, self.Canvas.Y - view.Y))
end

function Scroll:CanScroll(axis: string): boolean
	if axis == "X" and self.Direction == "Y" then
		return false
	end
	if axis == "Y" and self.Direction == "X" then
		return false
	end
	return self:MaxOffset()[axis] > 0.5
end

function Scroll:_measure()
	if self.Mode ~= "content" then
		return
	end
	local size = Create.layoutSize(self.Content)
	self.Canvas = Vector2.new(size.X, size.Y)
	self:_clampAndApply()
end

function Scroll:SetCanvasSize(size: Vector2)
	if size == self.Canvas then
		return
	end
	self.Canvas = size
	self:_clampAndApply()
end

function Scroll:_clamp(offset: Vector2): Vector2
	local max = self:MaxOffset()
	return Vector2.new(math.clamp(offset.X, 0, max.X), math.clamp(offset.Y, 0, max.Y))
end

function Scroll:_clampAndApply()
	self.Target = self:_clamp(self.Target)
	local clamped = self:_clamp(self.Offset)
	if clamped ~= self.Offset then
		self.Offset = clamped
		self:_apply()
		self.Changed:Fire(self.Offset)
	else
		self:_updateBars()
	end
end

function Scroll:_apply()
	local offset = self.Offset
	if UI.has("Scroll", "Scrolled") then
		UI.fire("Scroll", "Scrolled", self.Origin, self, offset)
	end
	if self.Content then
		self.Content.Position = UDim2.fromOffset(-math.floor(offset.X + 0.5), -math.floor(offset.Y + 0.5))
	end
	self:_updateBars()
end

function Scroll:_updateBars()
	local view = self:ViewSize()
	-- Visibility first (each bar's length depends on the other's).
	for axis, bar in self.Bars do
		bar.Track.Visible = self.Canvas[axis] > view[axis] + 0.5
	end
	for axis, bar in self.Bars do
		bar.Layout()
		if bar.Track.Visible then
			local trackLength = Create.layoutSize(bar.Track)[axis]
			if trackLength <= 0 then
				trackLength = view[axis]
			end
			local ratio = math.clamp(view[axis] / math.max(1, self.Canvas[axis]), 0, 1)
			local thumbLength = math.max(MIN_THUMB, math.floor(trackLength * ratio))
			local range = math.max(1, self.Canvas[axis] - view[axis])
			local position = math.floor((trackLength - thumbLength) * math.clamp(self.Offset[axis] / range, 0, 1) + 0.5)
			local holder = bar.Holder
			if axis == "Y" then
				holder.Size = UDim2.new(1, 0, 0, thumbLength)
				holder.Position = UDim2.fromOffset(0, position)
			else
				holder.Size = UDim2.new(0, thumbLength, 1, 0)
				holder.Position = UDim2.fromOffset(position, 0)
			end
		end
	end
end

----------------------------------------------------------------------
-- Moving
----------------------------------------------------------------------

function Scroll:_step(dt: number)
	local difference = self.Target - self.Offset
	if difference.Magnitude < 0.5 then
		self.Offset = self.Target
		if self._stepping then
			self._stepping:Disconnect()
			self._stepping = nil
		end
	else
		local alpha = 1 - math.exp(-dt * 18)
		self.Offset = self.Offset + difference * alpha
	end
	self:_apply()
	self.Changed:Fire(self.Offset)
end

function Scroll:ScrollTo(offset: Vector2, animated: boolean?)
	self.Target = self:_clamp(offset)
	if animated then
		if not self._stepping then
			self._stepping = RunService.RenderStepped:Connect(function(dt)
				self:_step(dt)
			end)
		end
		return
	end
	if self._stepping then
		self._stepping:Disconnect()
		self._stepping = nil
	end
	if self.Target ~= self.Offset then
		self.Offset = self.Target
		self:_apply()
		self.Changed:Fire(self.Offset)
	end
end

function Scroll:ScrollBy(delta: Vector2, animated: boolean?)
	self:ScrollTo(self.Target + delta, animated)
end

-- Bring the span [from, to] (pixels along `axis`) into view.
function Scroll:Reveal(axis: string, from: number, to: number, padding: number?, animated: boolean?)
	padding = padding or 0
	local view = self:ViewSize()[axis]
	local current = self.Target[axis]
	local wanted = current
	if from - padding < current then
		wanted = from - padding
	elseif to + padding > current + view then
		wanted = to + padding - view
	end
	if wanted ~= current then
		local offset = if axis == "X" then Vector2.new(wanted, self.Target.Y) else Vector2.new(self.Target.X, wanted)
		self:ScrollTo(offset, animated)
	end
end

function Scroll:Destroy()
	local index = table.find(live, self)
	if index then
		table.remove(live, index)
	end
	if self._stepping then
		self._stepping:Disconnect()
		self._stepping = nil
	end
	self.Bin:Clean()
	self.Changed:DisconnectAll()
end

return UI.register("Scroll", Scroll, {
	Description = "the shared scroll area (wheel, Shift+wheel, draggable bars)",
	Events = {
		Created = "scroll, props",
		Scrolled = "scroll, offset · the visible part moved",
	},
})
