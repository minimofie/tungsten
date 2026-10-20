--[[
	Tungsten · base/ui/components/sequenceeditor
	Keypoint editor for NumberSequence and ColorSequence values, on the
	overlay.

		SequenceEditor.open({
			AnchorPos = pos, AnchorSize = size,
			Value = NumberSequence.new(0, 1),     -- or a ColorSequence
			OnChange = function(sequence) end,    -- each valid change (a live preview)
			OnAccept = function(sequence) end,    -- Accept (or a click outside)
			OnCancel = function(original) end,    -- Cancel or Escape
			Live = true,                          -- false: OnChange only on Accept
			OnClose = function(reason) end,
			Owner = button, Origin = "core",
		})

	A preview on top (a graph for numbers, the gradient for colors) and a
	row per keypoint: time, value (or color) and envelope. The first
	keypoint stays at time 0 and the last at time 1; the ones between can
	move, be removed, and "Add keypoint" adds one in the widest gap.
	Every valid edit is reported straight away; a problem shows under the
	rows and nothing is reported until it is fixed. Cancel / Accept sit beside
	"Add keypoint": Cancel (or Escape) reports the original sequence again
	if anything changed, Accept (or a click outside) keeps the edit.
]]

local T = ...
local signal = T.import("base/signal")
local Theme = T.import("base/theme")
local Create = T.import("base/ui/create")
local Icons = T.import("base/data/icons")
local Animate = T.import("base/ui/animate")
local Overlay = T.import("base/ui/overlay")
local Input = T.import("base/ui/components/input")
local Button = T.import("base/ui/components/button")
local Scroll = T.import("base/ui/components/scroll")
local ColorPicker = T.import("base/ui/components/colorpicker")
local ConfirmBar = T.import("base/ui/components/confirmbar")
local UI = T.import("base/ui/ui")

local new = Create.new
local Sizes = Theme.Sizes

local PAD = 10
local WIDTH = 330
local PREVIEW = 56
local ROW = 30
local MAX_ROWS = 6

local SequenceEditor = {}

local function call(fn, ...)
	if fn then
		local ok, err = pcall(fn, ...)
		if not ok then
			T.Log.error("ui", "sequence editor callback failed: " .. tostring(err))
		end
	end
end

-- Keypoints as plain tables: { Time, Value, Envelope }.
local function pointsOf(sequence): { any }
	local points = {}
	for _, key in sequence.Keypoints do
		table.insert(points, { Time = key.Time, Value = key.Value, Envelope = if typeof(sequence) == "NumberSequence" then key.Envelope else 0 })
	end
	return points
end

local function build(isColor: boolean, points: { any }): (boolean, any)
	local sorted = table.clone(points)
	table.sort(sorted, function(a, b)
		return a.Time < b.Time
	end)
	return pcall(function()
		local keys = {}
		for _, point in sorted do
			if isColor then
				table.insert(keys, ColorSequenceKeypoint.new(point.Time, point.Value))
			else
				table.insert(keys, NumberSequenceKeypoint.new(point.Time, point.Value, point.Envelope))
			end
		end
		return if isColor then ColorSequence.new(keys) else NumberSequence.new(keys)
	end)
end
SequenceEditor.build = build

local function lerpColor(a: Color3, b: Color3, t: number): Color3
	return Color3.new(a.R + (b.R - a.R) * t, a.G + (b.G - a.G) * t, a.B + (b.B - a.B) * t)
end

function SequenceEditor.open(opts: { [string]: any })
	local origin = opts.Origin or "core"
	local value = opts.Value
	local isColor = typeof(value) == "ColorSequence"
	if typeof(value) ~= "NumberSequence" and not isColor then
		value = if opts.Kind == "color" then ColorSequence.new(Color3.new(1, 1, 1)) else NumberSequence.new(0)
		isColor = opts.Kind == "color"
	end
	local points = pointsOf(value)

	local height = PAD + PREVIEW + 8 + 18 + MAX_ROWS * ROW + 4 + 18 + 6 + Sizes.Control + PAD
	local size = Vector2.new(WIDTH, height)
	local position = Overlay.place(size, opts.AnchorPos, opts.AnchorSize, { Side = "below", Gap = 4 })
	local frame = Overlay.panel(size, position)
	frame.Name = "SequenceEditor"
	local bin = signal.bin()
	local rowBin = signal.bin()
	bin:Add(rowBin)
	local handle

	-- Preview.
	local preview = new("Frame", {
		Name = "Preview",
		Position = UDim2.fromOffset(PAD, PAD),
		Size = UDim2.new(1, -PAD * 2, 0, PREVIEW),
		Theme = { BackgroundColor3 = "Chrome" },
		ClipsDescendants = true,
		Parent = frame,
	})
	Create.corner(preview, 4)
	Create.stroke(preview, "Border", 1, 0)
	local gradient = nil
	if isColor then
		preview.BackgroundColor3 = Color3.new(1, 1, 1)
		gradient = new("UIGradient", { Parent = preview })
	end

	local y = PAD + PREVIEW + 8
	local columns = if isColor then { "Time", "Color", "" } else { "Time", "Value", "Envelope" }
	local header = new("Frame", {
		Name = "Header",
		Position = UDim2.fromOffset(PAD, y),
		Size = UDim2.new(1, -PAD * 2, 0, 18),
		BackgroundTransparency = 1,
		Parent = frame,
	})
	local columnWidth = math.floor((WIDTH - PAD * 2 - 30) / 3)
	for index, title in columns do
		new("TextLabel", {
			Name = "Column" .. index,
			Position = UDim2.fromOffset((index - 1) * columnWidth + 4, 0),
			Size = UDim2.fromOffset(columnWidth - 8, 18),
			Text = title,
			TextSize = Sizes.TextSmall,
			Theme = { TextColor3 = "TextMuted" },
			Parent = header,
		})
	end
	y += 18
	local scroll = Scroll.new({
		Name = "Keypoints",
		Origin = origin,
		Position = UDim2.fromOffset(PAD, y),
		Size = UDim2.new(1, -PAD * 2, 0, MAX_ROWS * ROW),
		Parent = frame,
	})
	bin:Add(scroll)
	Create.list(scroll.Content, Enum.FillDirection.Vertical, 0)
	y += MAX_ROWS * ROW + 4
	local problem = new("TextLabel", {
		Name = "Problem",
		Position = UDim2.fromOffset(PAD, y),
		Size = UDim2.new(1, -PAD * 2, 0, 18),
		Text = "",
		TextSize = Sizes.TextSmall,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Theme = { TextColor3 = "Danger" },
		Parent = frame,
	})
	y += 18 + 6

	local renderRows -- forward

	local function drawPreview()
		local okSeq, sequence = build(isColor, points)
		if isColor then
			if okSeq then
				gradient.Color = sequence
			end
			return
		end
		for _, child in preview:GetChildren() do
			if child.Name == "Dot" or child.Name == "Band" then
				child:Destroy()
			end
		end
		local low, high = math.huge, -math.huge
		for _, point in points do
			low = math.min(low, point.Value - point.Envelope)
			high = math.max(high, point.Value + point.Envelope)
		end
		if high - low < 1e-6 then
			low, high = low - 1, high + 1
		end
		local span = high - low
		local function yOf(number: number): number
			return 1 - (number - low) / span
		end
		for _, point in points do
			if point.Envelope > 0 then
				new("Frame", {
					Name = "Band",
					AnchorPoint = Vector2.new(0.5, 0),
					Position = UDim2.new(point.Time, 0, yOf(point.Value + point.Envelope) * 0.8 + 0.1, 0),
					Size = UDim2.new(0, 3, (point.Envelope * 2 / span) * 0.8, 0),
					BackgroundTransparency = 0.5,
					Theme = { BackgroundColor3 = "Accent" },
					Parent = preview,
				})
			end
			local dot = new("Frame", {
				Name = "Dot",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(point.Time, 0, yOf(point.Value) * 0.8 + 0.1, 0),
				Size = UDim2.fromOffset(7, 7),
				ZIndex = 2,
				Theme = { BackgroundColor3 = "Accent" },
				Parent = preview,
			})
			Create.corner(dot, 4)
		end
	end

	local original = value
	local live = opts.Live ~= false
	local dirty = false -- OnChange has had something other than the original
	local pending = false -- an edit OnChange hasn't had yet (Live = false)
	local finished = false
	local function report(sequence)
		call(opts.OnChange, sequence)
		UI.fire("SequenceEditor", "Changed", origin, sequence, opts)
	end
	local function changed()
		local okSeq, sequence = build(isColor, points)
		if not okSeq then
			problem.Text = (tostring(sequence):gsub("^.-:%d+: ", ""))
			return
		end
		problem.Text = ""
		value = sequence
		drawPreview()
		if live then
			dirty = true
			report(sequence)
		else
			pending = true
		end
	end
	local function finish(accepted: boolean)
		if finished then
			return
		end
		finished = true
		if accepted then
			if pending then
				report(value)
			end
			call(opts.OnAccept, value)
			UI.fire("SequenceEditor", "Accepted", origin, value, opts)
		else
			if dirty then
				report(original)
			end
			value = original
			call(opts.OnCancel, original)
			UI.fire("SequenceEditor", "Cancelled", origin, original, opts)
		end
	end

	local function sortPoints()
		table.sort(points, function(a, b)
			return a.Time < b.Time
		end)
	end

	renderRows = function()
		rowBin:Clean()
		for _, child in scroll.Content:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		for index, point in points do
			local row = new("Frame", {
				Name = "Key" .. index,
				Size = UDim2.new(1, 0, 0, ROW),
				LayoutOrder = index,
				BackgroundTransparency = 1,
				Parent = scroll.Content,
			})
			local fixed = index == 1 or index == #points
			local timeBox = Input.new({
				Name = "Time",
				Parent = row,
				Origin = origin,
				Numeric = true,
				Min = 0,
				Max = 1,
				Decimals = 3,
				Value = point.Time,
				Position = UDim2.fromOffset(0, 2),
				Size = UDim2.fromOffset(columnWidth - 6, Sizes.Control),
			})
			rowBin:Add(timeBox)
			if fixed then
				timeBox.Box.TextEditable = false
				Theme.bind(timeBox.Box, "TextColor3", "TextMuted")
			else
				rowBin:Add(timeBox.Committed:Connect(function(number)
					point.Time = math.clamp(number, 0.001, 0.999)
					sortPoints()
					changed()
					renderRows()
				end))
			end
			if isColor then
				local swatch = new("TextButton", {
					Name = "Swatch",
					Position = UDim2.fromOffset(columnWidth, 4),
					Size = UDim2.fromOffset(22, Sizes.Control - 4),
					BackgroundColor3 = point.Value,
					AutoButtonColor = false,
					Text = "",
					Parent = row,
				})
				Create.corner(swatch, 4)
				Create.stroke(swatch, "Border", 1, 0)
				local hex = Input.new({
					Name = "Hex",
					Parent = row,
					Origin = origin,
					Mono = true,
					Text = "#" .. point.Value:ToHex():upper(),
					Position = UDim2.fromOffset(columnWidth + 26, 2),
					Size = UDim2.fromOffset(columnWidth * 2 - 32, Sizes.Control),
				})
				rowBin:Add(hex)
				rowBin:Add(hex.Committed:Connect(function(text)
					local digits = tostring(text):match("^%s*#?(%x%x%x%x%x%x)%s*$")
					if not digits then
						problem.Text = "type a color as #rrggbb"
						return
					end
					point.Value = Color3.fromRGB(tonumber(digits:sub(1, 2), 16), tonumber(digits:sub(3, 4), 16), tonumber(digits:sub(5, 6), 16))
					swatch.BackgroundColor3 = point.Value
					changed()
				end))
				rowBin:Add(swatch.Activated:Connect(function()
					ColorPicker.open({
						Origin = origin,
						AnchorPos = swatch.AbsolutePosition,
						AnchorSize = swatch.AbsoluteSize,
						Value = point.Value,
						Parent = handle,
						Owner = swatch,
						OnChange = function(color)
							point.Value = color
							if swatch.Parent then
								swatch.BackgroundColor3 = color
								hex:SetText("#" .. color:ToHex():upper())
							end
							changed()
						end,
					})
				end))
			else
				for column, key in { "Value", "Envelope" } do
					local box = Input.new({
						Name = key,
						Parent = row,
						Origin = origin,
						Numeric = true,
						Min = if key == "Envelope" then 0 else nil,
						Decimals = 4,
						Value = point[key],
						Position = UDim2.fromOffset(column * columnWidth, 2),
						Size = UDim2.fromOffset(columnWidth - 6, Sizes.Control),
					})
					rowBin:Add(box)
					rowBin:Add(box.Committed:Connect(function(number)
						point[key] = number
						changed()
					end))
				end
			end
			local remove = new("TextButton", {
				Name = "Remove",
				Position = UDim2.new(1, -26, 0, 4),
				Size = UDim2.fromOffset(22, 22),
				BackgroundTransparency = 1,
				Visible = not fixed,
				Theme = { BackgroundColor3 = "SurfaceHover" },
				Parent = row,
			})
			Create.corner(remove, 5)
			local icon = Icons.new("close", 12, "TextMuted")
			icon.AnchorPoint = Vector2.new(0.5, 0.5)
			icon.Position = UDim2.fromScale(0.5, 0.5)
			icon.Parent = remove
			Animate.hover(remove, rowBin, function(hovered)
				remove.BackgroundTransparency = if hovered then 0 else 1
				Icons.tint(icon, if hovered then "Danger" else "TextMuted", Animate.Fast)
			end)
			rowBin:Add(remove.Activated:Connect(function()
				local at = table.find(points, point)
				if at and #points > 2 and not fixed then
					table.remove(points, at)
					changed()
					renderRows()
				end
			end))
		end
		drawPreview()
	end

	-- Adds a keypoint in the middle of the widest gap.
	local function addKeypoint()
		if #points >= 20 then
			problem.Text = "a sequence has at most 20 keypoints"
			return
		end
		local best, bestGap = 1, -1
		for index = 1, #points - 1 do
			local gap = points[index + 1].Time - points[index].Time
			if gap > bestGap then
				best, bestGap = index, gap
			end
		end
		local a, b = points[best], points[best + 1]
		local time = (a.Time + b.Time) / 2
		local point = {
			Time = math.floor(time * 1000 + 0.5) / 1000,
			Value = if isColor then lerpColor(a.Value, b.Value, 0.5) else (a.Value + b.Value) / 2,
			Envelope = if isColor then 0 else (a.Envelope + b.Envelope) / 2,
		}
		table.insert(points, best + 1, point)
		changed()
		renderRows()
	end

	local addButton = Button.new({
		Name = "Add",
		Parent = frame,
		Origin = origin,
		Text = "Add keypoint",
		Icon = "add",
		Position = UDim2.fromOffset(PAD, y),
		OnClick = addKeypoint,
	})
	bin:Add(addButton)
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

	renderRows()
	handle = Overlay.open(frame, {
		Owner = opts.Owner,
		Parent = opts.Parent,
		OnClose = function(reason)
			finish(ConfirmBar.closeMeans(reason) == "accept")
			bin:Clean()
			call(opts.OnClose, reason)
			UI.fire("SequenceEditor", "Closed", origin, handle, value)
		end,
	})
	handle.Kind = if isColor then "color" else "number"
	handle.Confirm = confirm
	handle.Accept = function()
		finish(true)
		handle:Close("accepted")
	end
	handle.Cancel = function()
		finish(false)
		handle:Close("cancelled")
	end
	handle.Points = points
	handle.Add = addKeypoint
	handle.Get = function()
		return value
	end
	handle.Problem = problem
	handle.Rows = scroll.Content
	-- Replaces the keypoints (tests, plugins): { { Time, Value, Envelope } }
	handle.SetPoints = function(list)
		table.clear(points)
		for _, point in list do
			table.insert(points, { Time = point.Time, Value = point.Value, Envelope = point.Envelope or 0 })
		end
		sortPoints()
		changed()
		renderRows()
	end
	UI.fire("SequenceEditor", "Created", origin, handle, opts)
	UI.fire("SequenceEditor", "Opened", origin, handle, opts)
	return handle
end

return UI.register("SequenceEditor", SequenceEditor, {
	Description = "keypoint editor for NumberSequence and ColorSequence values",
	Constructor = "open",
	Events = {
		Created = "handle, opts · (same as Opened)",
		Opened = "handle, opts",
		Changed = "sequence, opts · each valid change",
		Accepted = "sequence, opts · Accept (or a click outside)",
		Cancelled = "original, opts · Cancel or Escape",
		Closed = "handle, sequence",
	},
})
