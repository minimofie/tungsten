--[[
	Tungsten · console/completion
	The suggestion list shown above the console input. It lives on the
	overlay (so it can extend past the window) and never takes keyboard
	focus: the input keeps typing while it is open, Up/Down move the
	highlight and Tab accepts.

		local list = Completion.new({ Anchor = inputFrame, OnPick = function(item) end })
		  Transparency = 0.1   -- optional: a see-through background (the command bar)
		  Fixed = true         -- optional: never scaled (the command bar's list)
		list:Show(items)    -- { { Label, Hint, Text } }
		list:Move(1)        -- highlight down
		list:Current()
		list:Close()
]]

local T = ...
local signal = T.import("base/signal")
local Theme = T.import("base/theme")
local Create = T.import("base/ui/create")
local Overlay = T.import("base/ui/overlay")
local Scroll = T.import("base/ui/components/scroll")

local new = Create.new
local Sizes = Theme.Sizes

local ROW = 22
local PAD = 4
local MAX_ROWS = 8
local MIN_WIDTH = 200
local MAX_WIDTH = 440
local GAP = 6

local Completion = {}
Completion.__index = Completion

function Completion.new(props: { [string]: any })
	local self = setmetatable({}, Completion)
	self.Anchor = props.Anchor
	self.OnPick = props.OnPick
	self.Transparency = props.Transparency
	self.Fixed = props.Fixed == true
	self.Items = {}
	self.Highlight = 1
	self.Handle = nil
	self.Rows = {}
	self.Closed = signal.new()
	return self
end

function Completion:IsOpen(): boolean
	return self.Handle ~= nil and not self.Handle.Closed
end

function Completion:Current()
	return self.Items[self.Highlight]
end

function Completion:_size(): Vector2
	local labelWidth, hintWidth = 0, 0
	for index, item in self.Items do
		if index > 200 then
			break
		end
		labelWidth = math.max(labelWidth, Create.textWidth(item.Label, Sizes.CodeText, "Mono"))
		if item.Hint and item.Hint ~= "" then
			hintWidth = math.max(hintWidth, Create.textWidth(item.Hint, Sizes.TextSmall))
		end
	end
	local width = 10 + labelWidth + (if hintWidth > 0 then 24 + hintWidth else 0) + 10 + PAD * 2
	width = math.clamp(math.ceil(width), MIN_WIDTH, MAX_WIDTH)
	local rows = math.clamp(#self.Items, 1, MAX_ROWS)
	return Vector2.new(width, rows * ROW + PAD * 2)
end

-- Above the input when there is room, otherwise below it.
function Completion:_position(size: Vector2): Vector2
	local anchor = self.Anchor
	-- on-screen anchor -> layout pixels of the list's layer
	local fixed = self.Fixed
	local at = Overlay.toLayout(anchor.AbsolutePosition, fixed)
	local anchorSize = anchor.AbsoluteSize / Overlay.factor(fixed)
	local top = at.Y
	local view = Overlay.layoutViewport(fixed)
	local x = at.X
	local y = top - GAP - size.Y
	if y < Overlay.Margin then
		y = top + anchorSize.Y + GAP
	end
	x = math.clamp(x, Overlay.Margin, math.max(Overlay.Margin, view.X - Overlay.Margin - size.X))
	y = math.clamp(y, Overlay.Margin, math.max(Overlay.Margin, view.Y - Overlay.Margin - size.Y))
	return Vector2.new(math.floor(x + 0.5), math.floor(y + 0.5))
end

function Completion:_build(size: Vector2, position: Vector2)
	local panel = Overlay.panel(size, position)
	panel.Name = "Completion"
	if self.Transparency then
		panel.BackgroundTransparency = self.Transparency
	end
	self.Panel = panel
	self.Rows = {}

	local scroll = Scroll.new({
		Mode = "virtual",
		Direction = "Y",
		BarThickness = 3,
		Position = UDim2.fromOffset(PAD, PAD),
		Size = UDim2.new(1, -PAD * 2, 1, -PAD * 2),
		Parent = panel,
	})
	self.Scroll = scroll
	local bin = signal.bin()
	self.PanelBin = bin
	bin:Add(scroll)
	bin:Add(scroll.Changed:Connect(function()
		self:_render()
	end))

	self.Handle = Overlay.open(panel, {
		Owner = self,
		Fixed = self.Fixed,
		OnClose = function()
			bin:Clean()
			self.Handle = nil
			self.Panel = nil
			self.Scroll = nil
			self.Rows = {}
			self.Closed:Fire()
		end,
	})
end

function Completion:_makeRow(slot: number)
	local row = new("TextButton", {
		Name = "Row" .. slot,
		Size = UDim2.new(1, 0, 0, ROW),
		BackgroundTransparency = 1,
		Theme = { BackgroundColor3 = "SurfaceHover" },
		Parent = self.Scroll.Instance,
	})
	Create.corner(row, 5)
	local label = new("TextLabel", {
		Name = "Label",
		Position = UDim2.fromOffset(8, 0),
		Size = UDim2.new(1, -16, 1, 0),
		FontFace = Theme.Fonts.Mono,
		TextSize = Sizes.CodeText,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = row,
	})
	local hint = new("TextLabel", {
		Name = "Hint",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -8, 0, 0),
		Size = UDim2.fromScale(0, 1),
		AutomaticSize = Enum.AutomaticSize.X,
		TextSize = Sizes.TextSmall,
		TextXAlignment = Enum.TextXAlignment.Right,
		Theme = { TextColor3 = "TextMuted" },
		Parent = row,
	})
	local entry = { Row = row, Label = label, Hint = hint, Index = 0 }
	row.MouseEnter:Connect(function()
		if entry.Index > 0 and self.Handle and Overlay.popupAt(Overlay.mouse()) == self.Handle then
			self.Highlight = entry.Index
			self:_paint()
		end
	end)
	row.Activated:Connect(function()
		if entry.Index > 0 and self.Handle and Overlay.popupAt(Overlay.mouse()) == self.Handle then
			self.Highlight = entry.Index
			self:Pick()
		end
	end)
	self.Rows[slot] = entry
	return entry
end

function Completion:_paint()
	for _, entry in self.Rows do
		local lit = entry.Index == self.Highlight and entry.Index > 0
		entry.Row.BackgroundTransparency = if lit then 0 else 1
		Theme.bind(entry.Label, "TextColor3", if lit then "Accent" else "Text")
	end
end

function Completion:_render()
	local scroll = self.Scroll
	if not scroll then
		return
	end
	local offset = scroll.Offset.Y
	local first = math.floor(offset / ROW) + 1
	local count = MAX_ROWS + 1
	for slot = 1, math.max(count, #self.Rows) do
		local index = first + slot - 1
		local item = self.Items[index]
		local entry = self.Rows[slot]
		if slot > count or not item then
			if entry then
				entry.Row.Visible = false
				entry.Index = 0
			end
		else
			entry = entry or self:_makeRow(slot)
			entry.Index = index
			entry.Row.Visible = true
			entry.Row.Position = UDim2.fromOffset(0, (index - 1) * ROW - offset)
			entry.Label.Text = item.Label
			entry.Hint.Text = item.Hint or ""
			-- Long hints give way to the label.
			local room = (if self.Panel then self.Panel.AbsoluteSize.X / Overlay.factor(self.Fixed) else MIN_WIDTH) - 24 - Create.textWidth(item.Label, Sizes.CodeText, "Mono")
			entry.Hint.Visible = item.Hint ~= nil and Create.textWidth(item.Hint, Sizes.TextSmall) + 16 < room
		end
	end
	self:_paint()
end

function Completion:Show(items: { any }, highlight: number?)
	if #items == 0 then
		self:Close()
		return
	end
	self.Items = items
	self.Highlight = math.clamp(highlight or 1, 1, #items)
	local size = self:_size()
	local position = self:_position(size)
	if self:IsOpen() then
		self.Panel.Size = UDim2.fromOffset(size.X, size.Y)
		self.Panel.Position = UDim2.fromOffset(position.X, position.Y)
	else
		self:_build(size, position)
	end
	self.Scroll:SetCanvasSize(Vector2.new(0, #items * ROW))
	self.Scroll:ScrollTo(Vector2.zero)
	self:_reveal()
end

function Completion:_reveal()
	if not self.Scroll then
		return
	end
	local index = self.Highlight
	self.Scroll:Reveal("Y", (index - 1) * ROW, index * ROW, 0, false)
	self:_render()
end

function Completion:Move(step: number)
	if not self:IsOpen() or #self.Items == 0 then
		return
	end
	local count = #self.Items
	self.Highlight = ((self.Highlight - 1 + step) % count) + 1
	self:_reveal()
end

function Completion:Pick()
	local item = self:Current()
	self:Close()
	if item and self.OnPick then
		local ok, err = pcall(self.OnPick, item)
		if not ok then
			T.Log.error("console", "completion pick failed: " .. tostring(err))
		end
	end
end

function Completion:Close()
	if self.Handle and not self.Handle.Closed then
		self.Handle:Close("closed")
	end
	self.Handle = nil
end

function Completion:Destroy()
	self:Close()
	self.Closed:DisconnectAll()
end

return Completion
