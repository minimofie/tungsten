--[[
	Tungsten · base/ui/components/colorpicker
	Color popups on the overlay.

		ColorPicker.open({
			AnchorPos = pos, AnchorSize = size,   -- what it drops from
			Value = Color3.fromRGB(255, 128, 0),
			OnChange = function(color) end,       -- each finished change (a live preview)
			OnAccept = function(color) end,       -- Accept (or a click outside)
			OnCancel = function(original) end,    -- Cancel or Escape
			Live = true,                          -- false: OnChange only on Accept
			OnClose = function(reason) end,
			Owner = button, Origin = "core", Parent = parentHandle,
		})
		  hue / saturation square, a value bar, a before/after swatch, hex and
		  R, G, B boxes, and Cancel / Accept. A change is reported when a drag
		  ends or a box is committed (not on every mouse move). Cancel (or
		  Escape) reports the original color again if anything changed; Accept
		  or a click outside keeps the edit (base/ui/components/confirmbar).

		ColorPicker.palette({
			AnchorPos = pos, AnchorSize = size,
			Value = BrickColor.new("Bright red"),
			OnChange = function(brickColor) end,  -- each pick (a live preview)
			OnAccept = ..., OnCancel = ..., Live = true,   -- as above
			PickCloses = false,                   -- true: a click picks and closes
		})
		  the BrickColor palette with Cancel / Accept: a click picks a color
		  (shown at once), Accept keeps it, Cancel puts the original back.
]]

local T = ...
local signal = T.import("base/signal")
local Services = T.import("base/services")
local Theme = T.import("base/theme")
local Create = T.import("base/ui/create")
local Overlay = T.import("base/ui/overlay")
local Input = T.import("base/ui/components/input")
local ConfirmBar = T.import("base/ui/components/confirmbar")
local UI = T.import("base/ui/ui")

local UserInputService = Services.UserInputService
local new = Create.new
local Sizes = Theme.Sizes

local PAD = 10
local SQUARE = 180
local BAR = 16
local GAP = 8
local WIDTH = PAD * 2 + SQUARE + GAP + BAR

local ColorPicker = {}

local function toRGB(color: Color3): (number, number, number)
	return math.floor(color.R * 255 + 0.5), math.floor(color.G * 255 + 0.5), math.floor(color.B * 255 + 0.5)
end

local function hueSequence()
	local keys = {}
	for index = 0, 6 do
		table.insert(keys, ColorSequenceKeypoint.new(index / 6, Color3.fromHSV((index % 6) / 6, 1, 1)))
	end
	return ColorSequence.new(keys)
end

local function call(fn, ...)
	if fn then
		local ok, err = pcall(fn, ...)
		if not ok then
			T.Log.error("ui", "color picker callback failed: " .. tostring(err))
		end
	end
end

function ColorPicker.open(opts: { [string]: any })
	local origin = opts.Origin or "core"
	local start: Color3 = if typeof(opts.Value) == "Color3" then opts.Value else Color3.new(1, 1, 1)
	local h, s, v = start:ToHSV()
	local current = start

	local height = PAD + SQUARE + GAP + 28 + GAP + Sizes.Control + GAP + Sizes.Control + GAP + ConfirmBar.Height + PAD
	local size = Vector2.new(WIDTH, height)
	local position = Overlay.place(size, opts.AnchorPos, opts.AnchorSize, { Side = "below", Gap = 4 })
	local frame = Overlay.panel(size, position)
	frame.Name = "ColorPicker"
	local bin = signal.bin()

	-- Saturation (left to right) and value (top to bottom) square.
	local square = new("Frame", {
		Name = "Square",
		Position = UDim2.fromOffset(PAD, PAD),
		Size = UDim2.fromOffset(SQUARE, SQUARE),
		BackgroundColor3 = Color3.fromHSV(h, 1, 1),
		Parent = frame,
	})
	Create.corner(square, 4)
	local white = new("Frame", {
		Name = "White",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		Parent = square,
	})
	Create.corner(white, 4)
	new("UIGradient", { Transparency = NumberSequence.new(0, 1), Parent = white })
	local black = new("Frame", {
		Name = "Black",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		Parent = square,
	})
	Create.corner(black, 4)
	new("UIGradient", { Transparency = NumberSequence.new(1, 0), Rotation = 90, Parent = black })
	local cursor = new("Frame", {
		Name = "Cursor",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(10, 10),
		BackgroundTransparency = 1,
		ZIndex = 3,
		Parent = square,
	})
	Create.corner(cursor, 5)
	local cursorStroke = Create.stroke(cursor, "Text", 2, 0)
	cursorStroke.Color = Color3.new(1, 1, 1)
	-- One clear button over the square takes the clicks (the gradient
	-- layers under it are plain frames).
	local squareHit = new("TextButton", {
		Name = "Hit",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Text = "",
		ZIndex = 5,
		Parent = square,
	})

	-- Hue bar.
	local bar = new("TextButton", {
		Name = "Hue",
		Position = UDim2.fromOffset(PAD + SQUARE + GAP, PAD),
		Size = UDim2.fromOffset(BAR, SQUARE),
		BackgroundColor3 = Color3.new(1, 1, 1),
		AutoButtonColor = false,
		Text = "",
		Parent = frame,
	})
	Create.corner(bar, 4)
	new("UIGradient", { Color = hueSequence(), Rotation = 90, Parent = bar })
	local hueMark = new("Frame", {
		Name = "Mark",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.new(1, 4, 0, 4),
		Position = UDim2.fromScale(0.5, 0),
		BackgroundColor3 = Color3.new(1, 1, 1),
		ZIndex = 3,
		Parent = bar,
	})
	Create.corner(hueMark, 2)
	Create.stroke(hueMark, "Background", 1, 0)

	-- Before / after.
	local y = PAD + SQUARE + GAP
	local before = new("TextButton", {
		Name = "Before",
		Position = UDim2.fromOffset(PAD, y),
		Size = UDim2.fromOffset(40, 28),
		BackgroundColor3 = start,
		AutoButtonColor = false,
		Text = "",
		Parent = frame,
	})
	Create.corner(before, 4)
	Create.stroke(before, "Border", 1, 0)
	local after = new("Frame", {
		Name = "After",
		Position = UDim2.fromOffset(PAD + 40, y),
		Size = UDim2.fromOffset(40, 28),
		BackgroundColor3 = start,
		Parent = frame,
	})
	Create.corner(after, 4)
	Create.stroke(after, "Border", 1, 0)
	new("TextLabel", {
		Name = "Note",
		Position = UDim2.fromOffset(PAD + 88, y),
		Size = UDim2.new(1, -(PAD * 2 + 88), 0, 28),
		Text = "before · after",
		TextSize = Sizes.TextSmall,
		Theme = { TextColor3 = "TextMuted" },
		Parent = frame,
	})

	y += 28 + GAP
	local hexBox = Input.new({
		Name = "Hex",
		Parent = frame,
		Origin = origin,
		Mono = true,
		Placeholder = "#rrggbb",
		Position = UDim2.fromOffset(PAD, y),
		Size = UDim2.new(1, -PAD * 2, 0, Sizes.Control),
	})
	y += Sizes.Control + GAP
	local channelWidth = math.floor((WIDTH - PAD * 2 - GAP * 2) / 3)
	local channels = {}
	for index, name in { "R", "G", "B" } do
		channels[index] = Input.new({
			Name = name,
			Parent = frame,
			Origin = origin,
			Numeric = true,
			Min = 0,
			Max = 255,
			Decimals = 0,
			Position = UDim2.fromOffset(PAD + (index - 1) * (channelWidth + GAP), y),
			Size = UDim2.fromOffset(channelWidth, Sizes.Control),
		})
	end

	local handle

	local function show()
		square.BackgroundColor3 = Color3.fromHSV(h, 1, 1)
		cursor.Position = UDim2.fromScale(s, 1 - v)
		hueMark.Position = UDim2.fromScale(0.5, h)
		after.BackgroundColor3 = current
		local r, g, b = toRGB(current)
		hexBox:SetText("#" .. current:ToHex():upper())
		channels[1]:SetValue(r)
		channels[2]:SetValue(g)
		channels[3]:SetValue(b)
	end

	-- Live preview: each finished change is reported straight away; Cancel
	-- reports the original again.
	local live = opts.Live ~= false
	local reported = start -- the last color OnChange got (or the original)
	local finished = false
	local function report(color: Color3)
		reported = color
		call(opts.OnChange, color)
		UI.fire("ColorPicker", "Changed", origin, color, opts)
	end
	local function commit()
		if live then
			report(current)
		end
	end
	-- Accept / Cancel (also used when it closes some other way).
	local function finish(accepted: boolean)
		if finished then
			return
		end
		finished = true
		if accepted then
			if reported ~= current then
				report(current)
			end
			call(opts.OnAccept, current)
			UI.fire("ColorPicker", "Accepted", origin, current, opts)
		else
			if reported ~= start then
				report(start)
			end
			current = start
			call(opts.OnCancel, start)
			UI.fire("ColorPicker", "Cancelled", origin, start, opts)
		end
	end

	local function setColor(color: Color3, keepHue: boolean?)
		current = color
		local nh, ns, nv = color:ToHSV()
		if not keepHue or ns > 0 then
			h = nh
		end
		s, v = ns, nv
		show()
	end

	local function fromHSV()
		current = Color3.fromHSV(h, s, v)
		show()
	end

	-- Dragging on the square or the bar.
	local dragging: string? = nil
	local function update()
		local point = Overlay.mouse()
		if dragging == "square" then
			local pos, sz = square.AbsolutePosition, square.AbsoluteSize
			s = math.clamp((point.X - pos.X) / math.max(1, sz.X), 0, 1)
			v = 1 - math.clamp((point.Y - pos.Y) / math.max(1, sz.Y), 0, 1)
		elseif dragging == "hue" then
			local pos, sz = bar.AbsolutePosition, bar.AbsoluteSize
			h = math.clamp((point.Y - pos.Y) / math.max(1, sz.Y), 0, 0.9999)
		end
		fromHSV()
	end
	local function startDrag(kind: string)
		return function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				dragging = kind
				update()
			end
		end
	end
	bin:Add(squareHit.InputBegan:Connect(startDrag("square")))
	bin:Add(bar.InputBegan:Connect(startDrag("hue")))
	bin:Add(UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			update()
		end
	end))
	bin:Add(UserInputService.InputEnded:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then
			dragging = nil
			commit()
		end
	end))
	bin:Add(before.Activated:Connect(function()
		setColor(start)
		commit()
	end))
	bin:Add(hexBox.Committed:Connect(function(text)
		local hex = tostring(text):match("^%s*#?(%x%x%x%x%x%x)%s*$")
		if not hex then
			show() -- revert
			return
		end
		setColor(Color3.fromRGB(tonumber(hex:sub(1, 2), 16), tonumber(hex:sub(3, 4), 16), tonumber(hex:sub(5, 6), 16)))
		commit()
	end))
	for _, box in channels do
		bin:Add(box.Committed:Connect(function()
			setColor(Color3.fromRGB(channels[1].Value, channels[2].Value, channels[3].Value), true)
			commit()
		end))
	end

	y += Sizes.Control + GAP
	local confirm = ConfirmBar.new({
		Parent = frame,
		Origin = origin,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -PAD, 0, y),
		OnAccept = function()
			finish(true)
			handle:Close("accepted")
		end,
		OnCancel = function()
			finish(false)
			handle:Close("cancelled")
		end,
	})

	show()
	handle = Overlay.open(frame, {
		Owner = opts.Owner,
		Parent = opts.Parent,
		OnClose = function(reason)
			finish(ConfirmBar.closeMeans(reason) == "accept")
			bin:Clean()
			call(opts.OnClose, reason)
			UI.fire("ColorPicker", "Closed", origin, handle, current)
		end,
	})
	handle.Kind = "color"
	handle.Confirm = confirm
	handle.Accept = function()
		finish(true)
		handle:Close("accepted")
	end
	handle.Cancel = function()
		finish(false)
		handle:Close("cancelled")
	end
	handle.Get = function()
		return current
	end
	-- Sets the color as if picked (tests, plugins).
	handle.Set = function(color: Color3)
		setColor(color)
		commit()
	end
	handle.Square, handle.Bar, handle.HexBox, handle.Channels, handle.Before = square, bar, hexBox, channels, before
	UI.fire("ColorPicker", "Created", origin, handle, opts)
	UI.fire("ColorPicker", "Opened", origin, handle, opts)
	return handle
end

-- BrickColor palette.
local CELL = 16
local COLUMNS = 16
local PALETTE_SIZE = 128

function ColorPicker.palette(opts: { [string]: any })
	local origin = opts.Origin or "core"
	local colors = {}
	for index = 0, PALETTE_SIZE - 1 do
		local ok, brick = pcall(BrickColor.palette, index)
		if ok and brick then
			table.insert(colors, brick)
		end
	end
	local rows = math.ceil(#colors / COLUMNS)
	local size = Vector2.new(PAD * 2 + COLUMNS * (CELL + 2), PAD * 2 + rows * (CELL + 2) + 24 + 4 + ConfirmBar.Height)
	local position = Overlay.place(size, opts.AnchorPos, opts.AnchorSize, { Side = "below", Gap = 4 })
	local frame = Overlay.panel(size, position)
	frame.Name = "BrickPalette"
	local bin = signal.bin()
	local label = new("TextLabel", {
		Name = "Name",
		Position = UDim2.fromOffset(PAD, PAD + rows * (CELL + 2) + 4),
		Size = UDim2.new(1, -PAD * 2, 0, 20),
		Text = if typeof(opts.Value) == "BrickColor" then opts.Value.Name else "",
		TextSize = Sizes.TextSmall,
		Theme = { TextColor3 = "TextDim" },
		Parent = frame,
	})
	local handle
	local cells = {}
	local start = if typeof(opts.Value) == "BrickColor" then opts.Value else nil
	local current = start
	local reported = start
	local finished = false
	local live = opts.Live ~= false
	local marks = {} -- the stroke on the picked cell
	local function report(brick)
		reported = brick
		call(opts.OnChange, brick)
		UI.fire("ColorPicker", "Changed", origin, brick, opts)
	end
	local function markCell(brick)
		for _, stroke in marks do
			stroke:Destroy()
		end
		table.clear(marks)
		local cell = brick and cells[brick.Name]
		if cell then
			table.insert(marks, Create.stroke(cell, "Accent", 2, 0))
		end
		label.Text = if brick then ("%s · %d"):format(brick.Name, brick.Number) else ""
	end
	local function finish(accepted: boolean)
		if finished then
			return
		end
		finished = true
		if accepted then
			if current and reported ~= current then
				report(current)
			end
			call(opts.OnAccept, current)
			UI.fire("ColorPicker", "Accepted", origin, current, opts)
		else
			if start and reported ~= start then
				report(start)
			end
			call(opts.OnCancel, start)
			UI.fire("ColorPicker", "Cancelled", origin, start, opts)
		end
	end
	for index, brick in colors do
		local column = (index - 1) % COLUMNS
		local row = (index - 1) // COLUMNS
		local cell = new("TextButton", {
			Name = brick.Name,
			Position = UDim2.fromOffset(PAD + column * (CELL + 2), PAD + row * (CELL + 2)),
			Size = UDim2.fromOffset(CELL, CELL),
			BackgroundColor3 = brick.Color,
			AutoButtonColor = false,
			Text = "",
			Parent = frame,
		})
		Create.corner(cell, 3)
		bin:Add(cell.MouseEnter:Connect(function()
			label.Text = ("%s · %d"):format(brick.Name, brick.Number)
		end))
		bin:Add(cell.MouseLeave:Connect(function()
			label.Text = if current then ("%s · %d"):format(current.Name, current.Number) else ""
		end))
		bin:Add(cell.Activated:Connect(function()
			current = brick
			markCell(brick)
			if opts.PickCloses then
				finish(true)
				if handle then
					handle:Close("picked")
				end
				return
			end
			if live then
				report(brick)
			end
		end))
		cells[brick.Name] = cell
	end
	markCell(current)
	local confirm = ConfirmBar.new({
		Parent = frame,
		Origin = origin,
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -PAD, 1, -PAD),
		OnAccept = function()
			finish(true)
			handle:Close("accepted")
		end,
		OnCancel = function()
			finish(false)
			handle:Close("cancelled")
		end,
	})
	label.Size = UDim2.new(1, -PAD * 2, 0, 20)
	handle = Overlay.open(frame, {
		Owner = opts.Owner,
		Parent = opts.Parent,
		OnClose = function(reason)
			finish(ConfirmBar.closeMeans(reason) == "accept")
			bin:Clean()
			call(opts.OnClose, reason)
			UI.fire("ColorPicker", "Closed", origin, handle, current)
		end,
	})
	handle.Kind = "palette"
	handle.Cells = cells
	handle.Confirm = confirm
	handle.Get = function()
		return current
	end
	handle.Accept = function()
		finish(true)
		handle:Close("accepted")
	end
	handle.Cancel = function()
		finish(false)
		handle:Close("cancelled")
	end
	UI.fire("ColorPicker", "Created", origin, handle, opts)
	UI.fire("ColorPicker", "Opened", origin, handle, opts)
	return handle
end

return UI.register("ColorPicker", ColorPicker, {
	Description = "Color3 picker (square, hue bar, hex, RGB) and the BrickColor palette",
	Constructor = "open",
	Events = {
		Created = "handle, opts · (same as Opened)",
		Opened = "handle, opts",
		Changed = "color, opts · a finished change (Color3 or BrickColor)",
		Closed = "handle, color",
	},
})
