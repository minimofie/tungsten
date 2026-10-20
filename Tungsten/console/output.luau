--[[
	Tungsten · console/output
	The console's output area: a virtual view over Console.Lines (only
	the visible rows exist, so long sessions stay fast), sticky scrolling
	to the newest line, multi-select (click, Ctrl+click, Shift+click),
	a right-click menu and Ctrl+C / Ctrl+A while the pointer is over it.

		local view = Output.new({
			Parent = page, Console = Console,
			OnEmptyClick = function() end,       -- click on empty space
			OnRecall = function(inputText) end,  -- double-click an [>] line
		})

	Text is drawn as escaped rich text, so game output like "<b>" shows
	exactly as printed.
]]

local T = ...
local signal = T.import("base/signal")
local Services = T.import("base/services")
local Theme = T.import("base/theme")
local Settings = T.import("base/settings")
local Create = T.import("base/ui/create")
local Icons = T.import("base/data/icons")
local Overlay = T.import("base/ui/overlay")
local Scroll = T.import("base/ui/components/scroll")
local Menus = T.import("base/ui/menus")

local UserInputService = Services.UserInputService
local new = Create.new
local Sizes = Theme.Sizes

local ROW = Sizes.CodeLine
local TEXT_SIZE = Sizes.CodeText
local PAD_X = 10
local PAD_Y = 6
local ICON = 14
local STAMP_CHARS = 9 -- "12:00:00 "
local DOUBLE_CLICK = 0.35

local Output = {}
Output.__index = Output

local function keyDown(...): boolean
	for _, key in { ... } do
		if UserInputService:IsKeyDown(key) then
			return true
		end
	end
	return false
end
local function ctrlDown(): boolean
	return keyDown(Enum.KeyCode.LeftControl, Enum.KeyCode.RightControl)
end
local function shiftDown(): boolean
	return keyDown(Enum.KeyCode.LeftShift, Enum.KeyCode.RightShift)
end

function Output.new(props: { [string]: any })
	local self = setmetatable({}, Output)
	self.Bin = signal.bin()
	self.Console = props.Console
	self.OnEmptyClick = props.OnEmptyClick
	self.OnRecall = props.OnRecall
	self.Selected = setmetatable({}, { __mode = "k" }) :: { [any]: boolean }
	self.Anchor = nil
	self.Rows = {}
	self.MaxLength = 0
	self.Stick = true
	self._themeVersion = 0
	self._renderQueued = false
	self._lastClick = { Line = nil, Time = 0 }
	self.CharWidth = Create.textWidth("0000000000", TEXT_SIZE, "Mono") / 10

	local frame = new("Frame", {
		Name = "Output",
		Size = props.Size or UDim2.fromScale(1, 1),
		Position = props.Position or UDim2.new(),
		Theme = { BackgroundColor3 = "EditorGutter" },
		ClipsDescendants = true,
		Parent = props.Parent,
	})
	Create.corner(frame, Sizes.Radius)
	Create.stroke(frame, "Border", 1, 0)
	self.Instance = frame
	self.Bin:Add(frame)

	-- Clicks on empty space (below the last line).
	local hit = new("TextButton", {
		Name = "Hit",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 1,
		Parent = frame,
	})
	self.Bin:Add(hit.InputBegan:Connect(function(input)
		local kind = input.UserInputType
		if kind == Enum.UserInputType.MouseButton2 then
			self:_menu(nil, Overlay.pointOf(input))
		elseif kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch then
			if next(self.Selected) and not ctrlDown() and not shiftDown() then
				self:ClearSelection()
			end
			if self.OnEmptyClick then
				self.OnEmptyClick()
			end
		end
	end))

	local scroll = Scroll.new({
		Name = "Scroll",
		Mode = "virtual",
		Direction = "XY",
		Parent = frame,
	})
	scroll.Instance.ZIndex = 2
	self.Scroll = scroll
	self.Bin:Add(scroll)
	self.Bin:Add(scroll.Changed:Connect(function()
		local max = scroll:MaxOffset().Y
		-- Scrolling up stops following new lines; back at the end resumes.
		self.Stick = scroll.Target.Y >= max - ROW * 0.5
		self:_render()
	end))
	self.Bin:Add(scroll.Instance:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		self:_updateCanvas()
		if self.Stick then
			self:ScrollToEnd()
		end
		self:_render()
	end))

	-- Console events.
	local Console = self.Console
	self.Bin:Add(Console.LineAdded:Connect(function(line)
		if line.Length > self.MaxLength then
			self.MaxLength = line.Length
		end
		self:_queue()
	end))
	self.Bin:Add(Console.LinesTrimmed:Connect(function(count)
		if not self.Stick then
			scroll:ScrollTo(scroll.Target - Vector2.new(0, count * ROW), false)
		end
		self:_recountWidth()
		self:_queue()
	end))
	self.Bin:Add(Console.Cleared:Connect(function()
		table.clear(self.Selected)
		self.Anchor = nil
		self.MaxLength = 0
		self.Stick = true
		self:_queue()
	end))
	self.Bin:Add(Theme.Changed:Connect(function()
		self._themeVersion += 1
		self:_render()
	end))
	self.Bin:Add(Settings.Changed:Connect(function(key)
		if key == "ConsoleTimestamps" then
			self._themeVersion += 1
			self:_updateCanvas()
			self:_render()
		end
	end))

	-- Ctrl+C / Ctrl+A while the pointer is over the output and no box has focus.
	self.Bin:Add(UserInputService.InputBegan:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.Keyboard or not frame.Parent then
			return
		end
		if UserInputService:GetFocusedTextBox() or not ctrlDown() then
			return
		end
		if not (Overlay.shown(frame) and Overlay.inside(frame, Overlay.mouse())) or Overlay.popupAt(Overlay.mouse()) then
			return
		end
		if input.KeyCode == Enum.KeyCode.C and next(self.Selected) then
			self:CopySelected()
		elseif input.KeyCode == Enum.KeyCode.A then
			self:SelectAll()
		end
	end))

	self.Bin:Add(Create.cleanupWith(frame, self))
	self:_recountWidth()
	self:_updateCanvas()
	self:ScrollToEnd()
	self:_render()
	return self
end

----------------------------------------------------------------------
-- Geometry
----------------------------------------------------------------------

function Output:_stamps(): boolean
	return Settings.get("ConsoleTimestamps") == true
end

function Output:_textX(): number
	return PAD_X + (if self:_stamps() then STAMP_CHARS * self.CharWidth else 0)
end

function Output:_recountWidth()
	local max = 0
	for _, line in self.Console.Lines do
		if line.Length > max then
			max = line.Length
		end
	end
	self.MaxLength = max
end

function Output:_updateCanvas()
	local lines = #self.Console.Lines
	local width = math.ceil(self:_textX() + self.MaxLength * self.CharWidth + PAD_X)
	local height = PAD_Y * 2 + lines * ROW
	self.Scroll:SetCanvasSize(Vector2.new(width, height))
end

function Output:ScrollToEnd()
	local scroll = self.Scroll
	scroll:ScrollTo(Vector2.new(scroll.Target.X, scroll:MaxOffset().Y), false)
	self.Stick = true
end

----------------------------------------------------------------------
-- Drawing
----------------------------------------------------------------------

local function colorHex(color): string
	if typeof(color) == "Color3" then
		return "#" .. color:ToHex()
	end
	return Theme.hex(color or "Text")
end

function Output:_rich(line): string
	local parts = {}
	if self:_stamps() then
		table.insert(parts, ('<font color="%s">%s </font>'):format(Theme.hex("TextMuted"), Create.escape(line.Time or "")))
	end
	for _, segment in line.Segments do
		table.insert(parts, ('<font color="%s">%s</font>'):format(colorHex(segment.Color), Create.escape(segment.Text)))
	end
	return table.concat(parts)
end

function Output:_makeRow(slot: number)
	local row = new("TextButton", {
		Name = "Row" .. slot,
		Size = UDim2.new(1, 0, 0, ROW),
		BackgroundTransparency = 1,
		Theme = { BackgroundColor3 = "Selection" },
		ZIndex = 3,
		Parent = self.Scroll.Instance,
	})
	local label = new("TextLabel", {
		Name = "Text",
		Position = UDim2.fromOffset(PAD_X, 0),
		Size = UDim2.new(1, -PAD_X, 1, 0),
		FontFace = Theme.Fonts.Mono,
		TextSize = TEXT_SIZE,
		RichText = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 4,
		Parent = row,
	})
	local icon = Icons.new("dummy", ICON, "TextDim")
	icon.AnchorPoint = Vector2.new(0, 0.5)
	icon.Position = UDim2.new(0, 0, 0.5, 0)
	icon.Visible = false
	icon.ZIndex = 5
	icon.Parent = row

	local entry = { Row = row, Label = label, Icon = icon, Line = nil, IconName = nil, Version = -1 }
	row.InputBegan:Connect(function(input)
		local line = entry.Line
		if not line then
			return
		end
		local kind = input.UserInputType
		if kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch then
			self:_click(line)
		elseif kind == Enum.UserInputType.MouseButton2 then
			if not self.Selected[line] then
				self:_selectOnly(line)
			end
			self:_menu(line, Overlay.pointOf(input))
		end
	end)
	self.Rows[slot] = entry
	return entry
end

function Output:_queue()
	if self._renderQueued then
		return
	end
	self._renderQueued = true
	task.defer(function()
		self._renderQueued = false
		if not self.Instance.Parent then
			return
		end
		local stick = self.Stick
		self:_updateCanvas()
		if stick then
			self:ScrollToEnd()
		end
		self:_render()
	end)
end

function Output:_render()
	local scroll = self.Scroll
	if not scroll.Instance.Parent then
		return
	end
	local lines = self.Console.Lines
	local offset = scroll.Offset
	local view = scroll:ViewSize()
	local viewHeight = if view.Y > 0 then view.Y else 400
	local first = math.max(1, math.floor((offset.Y - PAD_Y) / ROW) + 1)
	local count = math.ceil(viewHeight / ROW) + 2
	local rowWidth = math.max(view.X, scroll.Canvas.X)
	local textX = self:_textX()

	for slot = 1, math.max(count, #self.Rows) do
		local index = first + slot - 1
		local line = lines[index]
		local entry = self.Rows[slot]
		if slot > count or not line then
			if entry then
				entry.Row.Visible = false
				entry.Line = nil
			end
		else
			entry = entry or self:_makeRow(slot)
			local row = entry.Row
			row.Visible = true
			row.Position = UDim2.fromOffset(-math.floor(offset.X + 0.5), PAD_Y + (index - 1) * ROW - math.floor(offset.Y + 0.5))
			row.Size = UDim2.fromOffset(rowWidth, ROW)
			if entry.Line ~= line or entry.Version ~= self._themeVersion then
				entry.Line = line
				entry.Version = self._themeVersion
				entry.Label.Text = self:_rich(line)
				local icon = entry.Icon
				if line.Icon and line.IconAt then
					if entry.IconName ~= line.Icon then
						Icons.set(icon, line.Icon)
						entry.IconName = line.Icon
					end
					Icons.tint(icon, line.IconColor or "TextDim")
					local cell = self.CharWidth * 2
					icon.Position = UDim2.new(0, math.floor(textX + line.IconAt * self.CharWidth + (cell - ICON) / 2 + 0.5), 0.5, 0)
					icon.Visible = true
				else
					icon.Visible = false
				end
			end
			entry.Label.Position = UDim2.fromOffset(PAD_X, 0)
			-- Selected rows use the selection color; error rows a faint red.
			local tint = if self.Selected[line] then "Selection" elseif line.Error and line.Kind == "error" then "Danger" else nil
			if tint ~= entry.Tint then
				entry.Tint = tint
				Theme.bind(row, "BackgroundColor3", tint or "Selection")
			end
			row.BackgroundTransparency = if tint == "Selection" then 0.25 elseif tint == "Danger" then 0.9 else 1
		end
	end
end

----------------------------------------------------------------------
-- Selection
----------------------------------------------------------------------

function Output:_indexOf(line): number?
	return table.find(self.Console.Lines, line)
end

function Output:_selectOnly(line)
	table.clear(self.Selected)
	self.Selected[line] = true
	self.Anchor = line
	self:_render()
end

function Output:_click(line)
	local now = os.clock()
	local last = self._lastClick
	if last.Line == line and now - last.Time < DOUBLE_CLICK and not ctrlDown() and not shiftDown() then
		last.Time = 0
		if line.Error then
			self.Console.run("/trace " .. line.Error.Id)
		elseif line.Input and self.OnRecall then
			self.OnRecall(line.Input)
		end
		return
	end
	last.Line, last.Time = line, now

	if shiftDown() and self.Anchor then
		local from = self:_indexOf(self.Anchor)
		local to = self:_indexOf(line)
		if from and to then
			if not ctrlDown() then
				table.clear(self.Selected)
			end
			for index = math.min(from, to), math.max(from, to) do
				self.Selected[self.Console.Lines[index]] = true
			end
			self:_render()
			return
		end
	end
	if ctrlDown() then
		self.Selected[line] = if self.Selected[line] then nil else true
		self.Anchor = line
		self:_render()
		return
	end
	self:_selectOnly(line)
end

function Output:SelectAll()
	for _, line in self.Console.Lines do
		self.Selected[line] = true
	end
	self.Anchor = self.Console.Lines[1]
	self:_render()
end

function Output:ClearSelection()
	table.clear(self.Selected)
	self.Anchor = nil
	self:_render()
end

-- Selected lines, top to bottom.
function Output:GetSelected(): { any }
	local list = {}
	for _, line in self.Console.Lines do
		if self.Selected[line] then
			table.insert(list, line)
		end
	end
	return list
end

local function lineText(line, withPrefix: boolean, stamps: boolean): string
	local text = line.Plain
	if not withPrefix then
		-- Drop the first segment when it is the prefix or indent.
		local first = line.Segments[1]
		if first and (first.Text:match("^%[[^%]]+%] $") or first.Text:match("^%s+$")) then
			text = text:sub(#first.Text + 1)
		end
	end
	if stamps then
		text = (line.Time or "") .. " " .. text
	end
	return text
end

function Output:_copy(lines, withPrefix: boolean)
	local parts = {}
	local stamps = self:_stamps()
	for _, line in lines do
		table.insert(parts, lineText(line, withPrefix, stamps))
	end
	local text = table.concat(parts, "\n")
	local ok, err = pcall(setclipboard, text)
	if not ok then
		T.Log.warn("console", "copy failed: " .. tostring(err))
	end
	return text
end

function Output:CopySelected(withPrefix: boolean?): string
	return self:_copy(self:GetSelected(), withPrefix ~= false)
end

function Output:CopyAll(): string
	return self:_copy(self.Console.Lines, true)
end

----------------------------------------------------------------------
-- Right-click menu
----------------------------------------------------------------------

--[[
	"console.output" (open to plugins). Context:
		ctx.Output, ctx.Console, ctx.Line (the clicked line or nil),
		ctx.Selected (selected lines), ctx.Record (error record of a single
		selected [x] line)
]]
Menus.define("console.output", {
	Title = "Console output",
	Sections = {
		{
			Id = "lines",
			Header = function(ctx)
				if ctx.Line and #ctx.Selected > 0 then
					return if #ctx.Selected == 1 then "Line" else ("%d lines"):format(#ctx.Selected)
				end
				return nil
			end,
		},
		{
			Id = "error",
			Header = function(ctx)
				local record = ctx.Record
				return if record then ("Error #%d · %s"):format(record.Id, record.Kind) else nil
			end,
		},
		{ Id = "console", Header = "Console" },
		"switches",
		"danger",
	},
})

local function onLines(ctx)
	return ctx.Line ~= nil and #ctx.Selected > 0
end
local function onError(ctx)
	return ctx.Record ~= nil
end

Menus.addMany("console.output", {
	{
		Id = "copy",
		Section = "lines",
		Order = 10,
		When = onLines,
		Text = "Copy",
		Icon = "copy",
		Shortcut = "Ctrl+C",
		Callback = function(ctx)
			ctx.Output:CopySelected(true)
		end,
	},
	{
		Id = "copy_plain",
		Section = "lines",
		Order = 20,
		When = onLines,
		Text = "Copy without prefixes",
		Callback = function(ctx)
			ctx.Output:CopySelected(false)
		end,
	},
	{
		Id = "recall",
		Section = "lines",
		Order = 30,
		When = function(ctx)
			return onLines(ctx) and #ctx.Selected == 1 and ctx.Line.Input ~= nil
		end,
		Text = "Put back in the input",
		Icon = "edit",
		Callback = function(ctx)
			if ctx.Output.OnRecall then
				ctx.Output.OnRecall(ctx.Line.Input)
			end
		end,
	},
	{
		Id = "explain",
		Section = "error",
		Order = 10,
		When = onError,
		Text = "Explain this error",
		Shortcut = "double-click",
		Callback = function(ctx)
			ctx.Console.run("/trace " .. ctx.Record.Id)
		end,
	},
	{
		Id = "copy_error",
		Section = "error",
		Order = 20,
		When = onError,
		Text = "Copy error with details",
		Icon = "copy",
		Callback = function(ctx)
			pcall(setclipboard, table.concat(ctx.Console.Errors.describe(ctx.Record), "\n"))
		end,
	},
	{
		Id = "retry",
		Section = "error",
		Order = 30,
		When = onError,
		Text = "Run it again",
		Disabled = function(ctx)
			return ctx.Record.Input == nil
		end,
		Callback = function(ctx)
			ctx.Console.run("/retry " .. ctx.Record.Id)
		end,
	},
	{
		Id = "error_input",
		Section = "error",
		Order = 40,
		When = onError,
		Text = "Put the input back",
		Icon = "edit",
		Disabled = function(ctx)
			return ctx.Record.Input == nil
		end,
		Callback = function(ctx)
			if ctx.Output.OnRecall and ctx.Record.Input then
				ctx.Output.OnRecall(ctx.Record.Input)
			end
		end,
	},
	{
		Id = "select_all",
		Section = "console",
		Order = 10,
		Text = "Select all",
		Shortcut = "Ctrl+A",
		Disabled = function(ctx)
			return #ctx.Console.Lines == 0
		end,
		Callback = function(ctx)
			ctx.Output:SelectAll()
		end,
	},
	{
		Id = "copy_all",
		Section = "console",
		Order = 20,
		Text = "Copy all",
		Icon = "copy",
		Disabled = function(ctx)
			return #ctx.Console.Lines == 0
		end,
		Callback = function(ctx)
			ctx.Output:CopyAll()
		end,
	},
	{
		Id = "game_output",
		Section = "switches",
		Order = 10,
		Text = "Show game output",
		Checked = function(ctx)
			return ctx.Console.gameOutput()
		end,
		Callback = function(ctx, item)
			ctx.Console.setGameOutput(item.Checked)
		end,
	},
	{
		Id = "timestamps",
		Section = "switches",
		Order = 20,
		Text = "Show timestamps",
		Checked = function(ctx)
			return ctx.Output:_stamps()
		end,
		Callback = function(_, item)
			Settings.set("ConsoleTimestamps", item.Checked == true)
		end,
	},
	{
		Id = "clear",
		Section = "danger",
		Order = 10,
		Text = "Clear console",
		Icon = "trash",
		Danger = true,
		Disabled = function(ctx)
			return #ctx.Console.Lines == 0
		end,
		Callback = function(ctx)
			ctx.Console.clear()
		end,
	},
})

function Output:_menu(line, point: Vector2)
	local selected = self:GetSelected()
	local ctx = {
		Output = self,
		Console = self.Console,
		Line = line,
		Selected = selected,
		Record = if line and #selected == 1 then line.Error else nil,
	}
	self.Menu = Menus.open("console.output", ctx, { Position = point })
	return self.Menu
end

function Output:Destroy()
	self.Bin:Clean()
end

return Output
