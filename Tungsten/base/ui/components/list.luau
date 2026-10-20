--[[
	Tungsten · base/ui/components/list
	Fast list: only the rows on screen exist, so 10,000+ items scroll
	smoothly. Multi-select with click, Ctrl+click and Shift+click,
	right-click for a context menu, double-click to activate. Optional
	column header; typed columns show class / value-type / enum icons.

		local list = List.new({
			Parent = page,
			Columns = {
				{ Key = "Name", Title = "Name", Flex = true, Min = 160 },
				{ Key = "Class", Title = "Class", Width = 150, Type = "class" },
				{ Key = "Kind", Title = "Type", Width = 110, Type = "valueType" },
			},
			MultiSelect = true,
			OnContextMenu = function(selected, item, point) ... end,
			-- or a named menu (base/ui/menus) opened with the context
			-- { List, Selected, Item, Point } (+ whatever MenuContext adds):
			Menu = "myplugin.items", MenuContext = function(ctx) ctx.Extra = 1 end,
			OnActivate = function(item) end,
		})
		list:SetItems(items)   -- array of tables (or strings for one column)
		list.SelectionChanged:Connect(function(selected) end)

	A column's text comes from item[Key] (or column.Get(item)). Type is
	"class", "valueType", "enum:<Name>" (the cell holds a class or type
	name / EnumItem) or "value" (the cell holds a real value: number,
	Vector3, Instance, ... shown with its type's icon). Items are kept by
	identity, so selection survives SetItems for items that are still there.

	Editing entries
		{ Key = "Class", Type = "class", Editable = true }      -- class picker
		{ Key = "Kind", Type = "valueType", Editable = true }   -- type picker
		{ Key = "Value", Type = "value", Editable = true }      -- typed text box
		{ Key = "Value", Type = "value", Editable = true, ValueType = "Vector3" }
		{ Key = "Mat", Type = "enum:Material", Editable = true } -- enum items
		{ Key = "Name", Editable = true }                       -- plain text
	Double-click an editable cell (or press F2 over the list, or use
	list:EditMenuItems(item) in a right-click menu) to edit. Class, type
	and enum columns offer a searchable selection; value columns parse the
	text into the cell's current type (booleans and enums get a choice).
	When the edited row is part of a multi-selection, every selected row
	gets the new value.
		OnEdit = function(item, key, newValue, oldValue)  -- optional
			return false, "reason"   -- reject; anything else accepts
		end
	Accepted values are written to item[key]; list.Edited fires
	(items, key, newValue).
]]

local T = ...
local signal = T.import("base/signal")
local Services = T.import("base/services")
local Theme = T.import("base/theme")
local Create = T.import("base/ui/create")
local Icons = T.import("base/data/icons")
local Overlay = T.import("base/ui/overlay")
local Scroll = T.import("base/ui/components/scroll")
local TypePicker = T.import("base/ui/components/typepicker")
local Dropdown = T.import("base/ui/components/dropdown")
local CellEditor = T.import("base/ui/components/celleditor")
local Types = T.import("base/types")
local UI = T.import("base/ui/ui")

local UserInputService = Services.UserInputService
local new = Create.new
local Sizes = Theme.Sizes

local HEADER = 24
local CELL_PAD = 8
local DOUBLE_CLICK = 0.35

local List = {}
List.__index = List

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

function List.new(props: { [string]: any })
	local self = setmetatable({}, List)
	self.Bin = signal.bin()
	self.SelectionChanged = signal.new() -- (selectedItems)
	self.Activated = signal.new() -- (item)
	self.ContextRequested = signal.new() -- (selectedItems, item, point)
	self.Edited = signal.new() -- (items, key, newValue)
	self._onEdit = props.OnEdit
	self.Origin = props.Origin or "core" -- who made it (base/ui/ui)
	self.Editing = nil -- overlay handle of the open cell editor

	self.Columns = props.Columns or { { Key = nil, Flex = true } }
	self.RowHeight = props.RowHeight or Sizes.Row
	self.MultiSelect = props.MultiSelect ~= false
	self.ShowHeader = props.Header
	if self.ShowHeader == nil then
		self.ShowHeader = #self.Columns > 1 or self.Columns[1].Title ~= nil
	end
	self.EmptyText = props.EmptyText or "Nothing to show"
	self._onContext = props.OnContextMenu
	self.MenuId = props.Menu
	self._menuContext = props.MenuContext
	self._onActivate = props.OnActivate
	self._onSelection = props.OnSelectionChanged

	self.Items = {}
	self.Index = {} -- item -> position
	self.Selected = {} -- item -> true
	self.SelectedCount = 0
	self.Anchor = nil -- index Shift+click ranges start from
	self.Rows = {}
	self.Hover = 0
	self._lastClick = { Index = 0, Time = 0 }
	self._widths = {}
	self._totalWidth = 0

	local root = new("Frame", {
		Name = props.Name or "List",
		Size = props.Size or UDim2.fromScale(1, 1),
		Position = props.Position or UDim2.new(),
		LayoutOrder = props.LayoutOrder or 0,
		Theme = { BackgroundColor3 = props.Background or "Chrome" },
		ClipsDescendants = true,
	})
	self.Instance = root
	self.Bin:Add(root)
	Create.corner(root, Sizes.RadiusSmall)
	Create.stroke(root, "Border", 1, 0)

	local top = 0
	if self.ShowHeader then
		local header = new("Frame", {
			Name = "Header",
			Size = UDim2.new(1, 0, 0, HEADER),
			Theme = { BackgroundColor3 = "Surface" },
			ClipsDescendants = true,
			Parent = root,
		})
		new("Frame", {
			Name = "Line",
			Position = UDim2.new(0, 0, 1, -1),
			Size = UDim2.new(1, 0, 0, 1),
			Theme = { BackgroundColor3 = "Border" },
			ZIndex = 3,
			Parent = header,
		})
		self.Header = header
		self.HeaderCells = {}
		for index, column in self.Columns do
			self.HeaderCells[index] = new("TextLabel", {
				Name = "Column" .. index,
				Text = column.Title or "",
				FontFace = Theme.Fonts.Medium,
				TextSize = Sizes.TextSmall,
				TextTruncate = Enum.TextTruncate.AtEnd,
				Size = UDim2.new(0, 100, 1, 0),
				Theme = { TextColor3 = "TextMuted" },
				Parent = header,
			})
		end
		top = HEADER
	end

	local scroll = Scroll.new({
		Mode = "virtual",
		Direction = "XY",
		Position = UDim2.fromOffset(0, top),
		Size = UDim2.new(1, 0, 1, -top),
		Parent = root,
	})
	self.Scroll = scroll
	self.Bin:Add(scroll)
	self.Bin:Add(scroll.Changed:Connect(function()
		self:_render()
	end))
	self.Bin:Add(scroll.Instance:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		self:_layoutColumns()
		self:_render()
	end))

	self.EmptyLabel = new("TextLabel", {
		Name = "Empty",
		Text = self.EmptyText,
		Size = UDim2.new(1, 0, 0, 40),
		TextXAlignment = Enum.TextXAlignment.Center,
		Theme = { TextColor3 = "TextMuted" },
		Parent = scroll.Instance,
	})

	-- Clicking empty space below the rows clears the selection.
	local backdrop = new("TextButton", {
		Name = "Backdrop",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 0,
		Parent = scroll.Instance,
	})
	self.Bin:Add(backdrop.InputBegan:Connect(function(input)
		local kind = input.UserInputType
		-- Only the empty space: ignore clicks that land on a row.
		local point = Overlay.pointOf(input)
		local y = Create.toLocal(point, scroll.Instance).Y + scroll.Offset.Y
		if y < #self.Items * self.RowHeight then
			return
		end
		if kind == Enum.UserInputType.MouseButton1 then
			if not ctrlDown() and not shiftDown() then
				self:ClearSelection()
			end
		elseif kind == Enum.UserInputType.MouseButton2 then
			self:ClearSelection()
			self:_context(nil, Overlay.pointOf(input))
		end
	end))

	-- F2 edits the first editable column of the last clicked row while
	-- the pointer is over the list.
	self.Bin:Add(UserInputService.InputBegan:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.Keyboard or input.KeyCode ~= Enum.KeyCode.F2 then
			return
		end
		if UserInputService:GetFocusedTextBox() or not root.Parent then
			return
		end
		local point = Overlay.mouse()
		if not (Overlay.shown(root) and Overlay.inside(root, point)) or Overlay.popupAt(point) then
			return
		end
		local item = self.Anchor and self.Items[self.Anchor]
		if item ~= nil then
			for index, column in self.Columns do
				if column.Editable then
					self:BeginEdit(item, index)
					break
				end
			end
		end
	end))

	self.Bin:Add(Create.cleanupWith(root, self))
	if props.Parent then
		root.Parent = props.Parent
	end
	self:_layoutColumns()
	if props.Items then
		self:SetItems(props.Items)
	else
		self:_render()
	end
	UI.fire("List", "Created", self.Origin, self, props)
	return self
end

----------------------------------------------------------------------
-- Columns
----------------------------------------------------------------------

function List:_layoutColumns()
	local available = self.Scroll:ViewSize().X
	if available <= 0 then
		available = 400
	end
	local fixed, flexCount = 0, 0
	for _, column in self.Columns do
		if column.Flex then
			flexCount += 1
			fixed += column.Min or 120
		else
			fixed += column.Width or 120
		end
	end
	local spare = math.max(0, available - fixed)
	local x = 0
	for index, column in self.Columns do
		local width = if column.Flex then (column.Min or 120) + math.floor(spare / flexCount) else (column.Width or 120)
		self._widths[index] = { X = x, Width = width }
		x += width
	end
	self._totalWidth = x
	self.Scroll:SetCanvasSize(Vector2.new(x, #self.Items * self.RowHeight))
	self:_placeHeader()
end

function List:_placeHeader()
	if not self.Header then
		return
	end
	local offsetX = self.Scroll.Offset.X
	for index, cell in self.HeaderCells do
		local span = self._widths[index]
		cell.Position = UDim2.fromOffset(span.X - offsetX + CELL_PAD, 0)
		cell.Size = UDim2.new(0, span.Width - CELL_PAD * 2, 1, 0)
	end
end

----------------------------------------------------------------------
-- Rows
----------------------------------------------------------------------

function List:_cellText(column, item): string
	local text = self:_rawCellText(column, item)
	if UI.has("List", "CellText") then
		text = tostring(UI.apply("List", "CellText", self.Origin, text, column, item, self))
	end
	return text
end

function List:_rawCellText(column, item): string
	if column.Get then
		local ok, value = pcall(column.Get, item)
		return if ok then tostring(value) else "?"
	end
	if type(item) ~= "table" then
		return tostring(item)
	end
	local value = if column.Key then item[column.Key] else item.Text
	if column.Type == "value" then
		return Types.display(value)
	end
	if value == nil then
		return ""
	end
	if typeof(value) == "EnumItem" then
		return value.Name
	end
	return tostring(value)
end

function List:_makeRow(slot: number)
	local row = new("TextButton", {
		Name = "Row" .. slot,
		Size = UDim2.new(0, 100, 0, self.RowHeight),
		BackgroundTransparency = 1,
		Theme = { BackgroundColor3 = "SurfaceHover" },
		ZIndex = 2,
		Parent = self.Scroll.Instance,
	})
	local accent = new("Frame", {
		Name = "Mark",
		Size = UDim2.new(0, 2, 1, -6),
		Position = UDim2.fromOffset(0, 3),
		Visible = false,
		Theme = { BackgroundColor3 = "Accent" },
		ZIndex = 3,
		Parent = row,
	})
	local cells = {}
	for index, column in self.Columns do
		local cell = { Column = column }
		if column.Type then
			cell.Icon = Icons.new("dummy", 14, "TextDim")
			cell.Icon.AnchorPoint = Vector2.new(0, 0.5)
			cell.Icon.ZIndex = 3
			cell.Icon.Parent = row
			cell.IconName = nil
		end
		cell.Label = new("TextLabel", {
			Name = "Cell" .. index,
			TextTruncate = Enum.TextTruncate.AtEnd,
			FontFace = if column.Mono then Theme.Fonts.Mono else Theme.Fonts.Regular,
			Size = UDim2.new(0, 100, 1, 0),
			ZIndex = 3,
			Theme = { TextColor3 = if index == 1 then "Text" else "TextDim" },
			Parent = row,
		})
		cells[index] = cell
	end

	local entry = { Row = row, Mark = accent, Cells = cells, Index = 0 }
	self.Rows[slot] = entry

	row.MouseEnter:Connect(function()
		self.Hover = entry.Index
		self:_paint(entry)
	end)
	row.MouseLeave:Connect(function()
		if self.Hover == entry.Index then
			self.Hover = 0
		end
		self:_paint(entry)
	end)
	row.InputBegan:Connect(function(input)
		local kind = input.UserInputType
		if kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch then
			self:_click(entry.Index)
		elseif kind == Enum.UserInputType.MouseButton2 then
			local item = self.Items[entry.Index]
			if item ~= nil and not self.Selected[item] then
				self:_selectOnly(entry.Index)
			end
			self:_context(item, Overlay.pointOf(input))
		end
	end)
	return entry
end

function List:_paint(entry)
	local item = self.Items[entry.Index]
	local selected = item ~= nil and self.Selected[item] == true
	local hovered = entry.Index ~= 0 and self.Hover == entry.Index
	if selected then
		Theme.bind(entry.Row, "BackgroundColor3", "Selection")
		entry.Row.BackgroundTransparency = if hovered then 0 else 0.15
	else
		Theme.bind(entry.Row, "BackgroundColor3", "SurfaceHover")
		entry.Row.BackgroundTransparency = if hovered then 0.35 else 1
	end
	entry.Mark.Visible = selected
end

function List:_render()
	local scroll = self.Scroll
	local rowHeight = self.RowHeight
	local offset = scroll.Offset
	local view = scroll:ViewSize()
	local first = math.max(1, math.floor(offset.Y / rowHeight) + 1)
	local count = math.ceil(math.max(view.Y, rowHeight) / rowHeight) + 1
	local rowWidth = math.max(self._totalWidth, view.X)
	local items = self.Items

	self.EmptyLabel.Visible = #items == 0
	self:_placeHeader()

	for slot = 1, math.max(count, #self.Rows) do
		local entry = self.Rows[slot]
		local index = first + slot - 1
		local item = items[index]
		if slot > count or item == nil then
			if entry then
				entry.Row.Visible = false
				entry.Index = 0
			end
		else
			entry = entry or self:_makeRow(slot)
			entry.Index = index
			local row = entry.Row
			row.Visible = true
			row.Position = UDim2.fromOffset(-offset.X, (index - 1) * rowHeight - offset.Y)
			row.Size = UDim2.new(0, rowWidth, 0, rowHeight)
			for columnIndex, cell in entry.Cells do
				local span = self._widths[columnIndex]
				local column = cell.Column
				local x = span.X + CELL_PAD
				local textWidth = span.Width - CELL_PAD * 2
				local value = if type(item) == "table" and column.Key then item[column.Key] else nil
				if cell.Icon then
					local iconName, color = TypePicker.iconFor(column.Type, value)
					if iconName then
						if iconName ~= cell.IconName then
							Icons.set(cell.Icon, iconName)
							cell.IconName = iconName
						end
						Icons.tint(cell.Icon, color :: Color3)
						cell.Icon.Visible = true
						cell.Icon.Position = UDim2.new(0, x, 0.5, 0)
						x += 20
						textWidth -= 20
					else
						cell.Icon.Visible = false
					end
				end
				cell.Label.Position = UDim2.fromOffset(x, 0)
				cell.Label.Size = UDim2.new(0, math.max(0, textWidth), 1, 0)
				cell.Label.Text = self:_cellText(column, item)
			end
			self:_paint(entry)
		end
	end
end

----------------------------------------------------------------------
-- Selection
----------------------------------------------------------------------

function List:_fireSelection()
	local selected = self:GetSelected()
	if self._onSelection then
		local ok, err = pcall(self._onSelection, selected)
		if not ok then
			T.Log.error("ui", "list callback failed: " .. tostring(err))
		end
	end
	self.SelectionChanged:Fire(selected)
	UI.fire("List", "SelectionChanged", self.Origin, self, selected)
end

function List:_repaint()
	for _, entry in self.Rows do
		if entry.Index ~= 0 then
			self:_paint(entry)
		end
	end
end

function List:_selectOnly(index: number)
	table.clear(self.Selected)
	local item = self.Items[index]
	self.SelectedCount = 0
	if item ~= nil then
		self.Selected[item] = true
		self.SelectedCount = 1
	end
	self.Anchor = index
	self:_repaint()
	self:_fireSelection()
end

function List:_click(index: number)
	local item = self.Items[index]
	if item == nil then
		return
	end

	-- Double-click activates.
	local now = os.clock()
	local last = self._lastClick
	if last.Index == index and now - last.Time < DOUBLE_CLICK and not ctrlDown() and not shiftDown() then
		last.Time = 0
		local columnIndex = self:ColumnAt(Overlay.mouse())
		if columnIndex and self.Columns[columnIndex].Editable then
			self:BeginEdit(item, columnIndex)
			return
		end
		if self._onActivate then
			local ok, err = pcall(self._onActivate, item)
			if not ok then
				T.Log.error("ui", "list callback failed: " .. tostring(err))
			end
		end
		self.Activated:Fire(item)
		UI.fire("List", "Activated", self.Origin, self, item)
		return
	end
	last.Index, last.Time = index, now

	if self.MultiSelect and shiftDown() and self.Anchor and self.Items[self.Anchor] ~= nil then
		-- Range from the anchor; Ctrl+Shift adds the range to the selection.
		if not ctrlDown() then
			table.clear(self.Selected)
		end
		local from, to = math.min(self.Anchor, index), math.max(self.Anchor, index)
		for i = from, to do
			self.Selected[self.Items[i]] = true
		end
		self:_recount()
		self:_repaint()
		self:_fireSelection()
	elseif self.MultiSelect and ctrlDown() then
		if self.Selected[item] then
			self.Selected[item] = nil
		else
			self.Selected[item] = true
		end
		self.Anchor = index
		self:_recount()
		self:_repaint()
		self:_fireSelection()
	else
		self:_selectOnly(index)
	end
end

function List:_recount()
	local count = 0
	for _ in self.Selected do
		count += 1
	end
	self.SelectedCount = count
end

function List:_context(item, point: Vector2)
	local selected = self:GetSelected()
	if self._onContext then
		local ok, err = pcall(self._onContext, selected, item, point)
		if not ok then
			T.Log.error("ui", "list context callback failed: " .. tostring(err))
		end
	end
	if self.MenuId then
		local ctx = { List = self, Selected = selected, Item = item, Point = point }
		if self._menuContext then
			local ok, err = pcall(self._menuContext, ctx)
			if not ok then
				T.Log.error("ui", "list menu context failed: " .. tostring(err))
			end
		end
		self.Menu = T.import("base/ui/menus").open(self.MenuId, ctx, { Position = point })
	end
	self.ContextRequested:Fire(selected, item, point)
	UI.fire("List", "ContextRequested", self.Origin, self, selected, item, point)
end

----------------------------------------------------------------------
-- Public
----------------------------------------------------------------------

function List:SetItems(items: { any })
	if UI.has("List", "Items") then
		items = UI.apply("List", "Items", self.Origin, table.clone(items), self)
	end
	self.Items = items
	table.clear(self.Index)
	for index, item in items do
		self.Index[item] = index
	end
	-- Keep only selected items that are still listed.
	for item in table.clone(self.Selected) do
		if self.Index[item] == nil then
			self.Selected[item] = nil
		end
	end
	self:_recount()
	if self.Anchor and self.Anchor > #items then
		self.Anchor = nil
	end
	self.Scroll:SetCanvasSize(Vector2.new(self._totalWidth, #items * self.RowHeight))
	self:_render()
end

function List:GetItems(): { any }
	return self.Items
end

-- Selected items in list order.
function List:GetSelected(): { any }
	local result = {}
	if self.SelectedCount == 0 then
		return result
	end
	for _, item in self.Items do
		if self.Selected[item] then
			table.insert(result, item)
		end
	end
	return result
end

function List:SetSelected(items: { any }, silent: boolean?)
	table.clear(self.Selected)
	for _, item in items do
		if self.Index[item] then
			self.Selected[item] = true
		end
	end
	self:_recount()
	self:_repaint()
	if not silent then
		self:_fireSelection()
	end
end

function List:SelectAll()
	if not self.MultiSelect then
		return
	end
	for _, item in self.Items do
		self.Selected[item] = true
	end
	self:_recount()
	self:_repaint()
	self:_fireSelection()
end

function List:ClearSelection()
	if self.SelectedCount == 0 then
		return
	end
	table.clear(self.Selected)
	self.SelectedCount = 0
	self:_repaint()
	self:_fireSelection()
end

function List:ScrollToItem(item: any, animated: boolean?)
	local index = self.Index[item]
	if index then
		self.Scroll:Reveal("Y", (index - 1) * self.RowHeight, index * self.RowHeight, self.RowHeight, animated)
	end
end

----------------------------------------------------------------------
-- Editing
----------------------------------------------------------------------

-- Column index under a point (AbsolutePosition space), if any.
function List:ColumnAt(point: Vector2): number?
	local view = self.Scroll.Instance
	local x = Create.toLocal(point, view).X + self.Scroll.Offset.X
	for index, span in self._widths do
		if x >= span.X and x < span.X + span.Width then
			return index
		end
	end
	return nil
end

local function columnIndexOf(self, key: any): number?
	if type(key) == "number" then
		return if self.Columns[key] then key else nil
	end
	for index, column in self.Columns do
		if column.Key == key then
			return index
		end
	end
	return nil
end

-- Screen rectangle of a cell (scrolls it into view first).
function List:CellRect(item: any, key: any): (Vector2?, Vector2?)
	local index = self.Index[item]
	local columnIndex = columnIndexOf(self, key)
	if not index or not columnIndex then
		return nil, nil
	end
	local rowHeight = self.RowHeight
	local scroll = self.Scroll
	scroll:Reveal("Y", (index - 1) * rowHeight, index * rowHeight, 0, false)
	local span = self._widths[columnIndex]
	scroll:Reveal("X", span.X, span.X + span.Width, 0, false)
	self:_render()
	-- worked out in layout pixels, returned on screen like AbsolutePosition
	local origin = scroll.Instance.AbsolutePosition
	local factor = Create.scaleOf(scroll.Instance)
	local x = span.X - scroll.Offset.X
	local y = (index - 1) * rowHeight - scroll.Offset.Y
	return origin + Vector2.new(x, y) * factor, Vector2.new(span.Width, rowHeight) * factor
end

-- Rows an edit applies to: the whole selection when the row is in it.
function List:_editTargets(item: any, column): { any }
	if self.Selected[item] and self.SelectedCount > 1 and column.MultiEdit ~= false then
		return self:GetSelected()
	end
	return { item }
end

-- Writes a value to the rows (through OnEdit). Returns true, or false + reason.
function List:ApplyEdit(item: any, key: any, value: any): (boolean, string?)
	local columnIndex = columnIndexOf(self, key)
	if not columnIndex then
		return false, "no such column"
	end
	local column = self.Columns[columnIndex]
	local targets = self:_editTargets(item, column)
	local changed = {}
	local firstProblem = nil
	for _, target in targets do
		local old = if type(target) == "table" then target[column.Key] else nil
		local accepted, reason = true, nil
		if self._onEdit then
			local ok, a, b = pcall(self._onEdit, target, column.Key, value, old)
			if not ok then
				accepted, reason = false, tostring(a)
				T.Log.error("ui", "list edit callback failed: " .. tostring(a))
			elseif a == false then
				accepted, reason = false, b
			end
		end
		if accepted then
			if type(target) == "table" and column.Key ~= nil then
				target[column.Key] = value
			end
			table.insert(changed, target)
		else
			firstProblem = firstProblem or reason or "not accepted"
		end
	end
	self:_render()
	if #changed > 0 then
		self.Edited:Fire(changed, column.Key, value)
		UI.fire("List", "Edited", self.Origin, self, changed, column.Key, value)
	end
	if #changed == 0 then
		return false, firstProblem
	end
	return true, if firstProblem then ("%d of %d rows rejected it: %s"):format(#targets - #changed, #targets, firstProblem) else nil
end

local function enumNameOf(item: EnumItem): string
	return (tostring(item.EnumType):gsub("^Enum%.", ""))
end

-- Opens the right editor for a cell: a selection for class / type / enum
-- columns and booleans, a typed text box otherwise.
function List:BeginEdit(item: any, key: any)
	local columnIndex = columnIndexOf(self, key)
	if item == nil or not columnIndex then
		return nil
	end
	local column = self.Columns[columnIndex]
	if not column.Editable then
		return nil
	end
	if self.Editing and not self.Editing.Closed then
		self.Editing:Close("replaced")
	end
	local anchorPos, anchorSize = self:CellRect(item, columnIndex)
	if not anchorPos then
		return nil
	end
	local current = if type(item) == "table" then item[column.Key] else item
	local kind = column.EditKind or column.Type
	local count = #self:_editTargets(item, column)
	local suffix = if count > 1 then (" · %d rows"):format(count) else ""

	local function choose(options, isSelected)
		self.Editing = Dropdown.popup({
			Origin = self.Origin,
			Options = options,
			AnchorPos = anchorPos,
			AnchorSize = anchorSize,
			Width = math.max(anchorSize.X / Overlay.factor(), 160), -- the anchor is on screen
			IsSelected = isSelected,
			OnPick = function(option)
				local ok, reason = self:ApplyEdit(item, columnIndex, option.Value)
				if not ok then
					T.Log.warn("ui", "edit rejected: " .. tostring(reason))
				end
			end,
			Owner = self,
		})
		return self.Editing
	end

	local valueType = column.ValueType
	if kind == "value" then
		valueType = valueType or (if current ~= nil then Types.typeName(current) else "any")
	end

	if TypePicker.isPickerKind(kind) then
		return choose(TypePicker.options(kind, self.Origin), function(option)
			return option.Value == current
		end)
	elseif valueType == "boolean" then
		local style = T.import("base/data/categories").valueType("boolean")
		return choose({
			{ Value = true, Text = "true", Icon = style.Icon, IconColor = style.Color },
			{ Value = false, Text = "false", Icon = style.Icon, IconColor = style.Color },
		}, function(option)
			return option.Value == current
		end)
	elseif valueType == "EnumItem" and typeof(current) == "EnumItem" then
		return choose(TypePicker.options("enum:" .. enumNameOf(current), self.Origin), function(option)
			return option.Value == current
		end)
	end

	-- Text: parse into the cell's type ("string" for plain columns).
	valueType = valueType or "string"
	local hint = Types.hint(valueType)
	self.Editing = CellEditor.open({
		Origin = self.Origin,
		ValueType = valueType,
		AnchorPos = anchorPos,
		AnchorSize = anchorSize,
		Text = if valueType == "string" and type(current) ~= "string" then Types.display(current) else Types.editText(current),
		Mono = valueType ~= "string",
		Hint = hint .. suffix .. " · Enter saves",
		Validate = function(text)
			return Types.parse(text, valueType)
		end,
		OnCommit = function(value)
			return self:ApplyEdit(item, columnIndex, value)
		end,
		Owner = self,
	})
	return self.Editing
end

-- Menu entries for a right-click menu: "Edit <column>" per editable column.
function List:EditMenuItems(item: any): { any }
	local entries = {}
	for index, column in self.Columns do
		if column.Editable then
			table.insert(entries, {
				Text = "Edit " .. tostring(column.Title or column.Key or ("column " .. index)):lower(),
				Icon = "edit",
				Shortcut = if #entries == 0 then "F2" else nil,
				Disabled = item == nil,
				Callback = function()
					task.defer(function()
						self:BeginEdit(item, index)
					end)
				end,
			})
		end
	end
	if UI.has("List", "EditMenuItems") then
		entries = UI.apply("List", "EditMenuItems", self.Origin, entries, item, self)
	end
	return entries
end

function List:Destroy()
	if self.Editing and not self.Editing.Closed then
		self.Editing:Close("destroyed")
	end
	self.Bin:Clean()
	self.Edited:DisconnectAll()
	self.SelectionChanged:DisconnectAll()
	self.Activated:DisconnectAll()
	self.ContextRequested:DisconnectAll()
end

return UI.register("List", List, {
	Description = "virtual multi-select lists with typed, editable columns",
	Events = {
		Created = "list, props",
		SelectionChanged = "list, selectedItems",
		Activated = "list, item · double-click on a cell that isn't editable",
		Edited = "list, items, key, value · cells changed (one or several rows)",
		ContextRequested = "list, selected, item, point · right-click",
	},
	Filters = {
		Items = "items, list · the rows SetItems shows",
		CellText = "text, column, item, list · text drawn in a cell",
		EditMenuItems = "entries, item, list · the Edit … entries for a menu",
	},
})
