--[[
	Tungsten · base/explorer/treeview
	Draws the explorer tree: only the rows on screen exist. Expand arrows,
	class icons and tints, variable badges, multi-select, keyboard.

		local view = TreeView.new({ Parent = frame, Tree = tree })
		view:Refresh()                    -- after the tree or filter changed
		view:SetFilter(filter or nil)     -- search mode (see Tree:Flatten)
		view:Select(nodes, primary)       -- replace the selection
		view.SelectionChanged:Connect(function(nodes, primary) end)

	Mouse: click selects, Ctrl+click adds/removes, Shift+click selects a
	range, double-click opens/closes, the arrow opens/closes, right-click
	asks for a menu (OnContext). Drag rows onto another row to move them
	into it (OnMove; CanMove says whether a drop is allowed): a label
	follows the mouse, the row under it lights up, the list scrolls near
	its edges, a closed row opens after a moment, Escape cancels.
	Keys (after clicking in the tree, while no text box has focus):
	Up/Down move (Shift extends), Left closes or goes to the parent, Right
	opens or goes to the first child, Home/End, Enter opens/closes,
	Ctrl+A selects every row, F2 renames, Delete deletes, Ctrl+Z undoes.
]]

local T = ...
local signal = T.import("base/signal")
local Services = T.import("base/services")
local Theme = T.import("base/theme")
local Create = T.import("base/ui/create")
local Animate = T.import("base/ui/animate")
local Icons = T.import("base/data/icons")
local Classes = T.import("base/data/classes")
local Categories = T.import("base/data/categories")
local Overlay = T.import("base/ui/overlay")
local Scroll = T.import("base/ui/components/scroll")
local CellEditor = T.import("base/ui/components/celleditor")

local UserInputService = Services.UserInputService
local new = Create.new
local Sizes = Theme.Sizes

local ROW = 22
local INDENT = 14
local LEFT = 4 -- space before the first arrow
local ARROW = 16
local ICON = 16
local DOUBLE_CLICK = 0.35
local RIGHT = 12 -- space kept after the end of the widest row
local DRAG_START = 6 -- px the mouse moves before a press becomes a drag
local DRAG_EDGE = 26 -- px from the top/bottom edge where dragging scrolls
local DRAG_SCROLL = 420 -- px per second at the very edge
local DRAG_OPEN = 0.6 -- seconds over a closed row before it opens

local TreeView = {}
TreeView.__index = TreeView
TreeView.RowHeight = ROW
TreeView.Indent = INDENT

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

function TreeView.new(props: { [string]: any })
	local self = setmetatable({}, TreeView)
	self.Bin = signal.bin()
	self.SelectionChanged = signal.new() -- (nodes in row order, primary node)
	self.Tree = props.Tree
	self.Filter = nil
	self.Rows = {}
	self.Index = {} -- node -> row index
	self.Selected = {} -- node -> true
	self.SelectedCount = 0
	self.Primary = nil -- last clicked / focused node
	self.Anchor = nil -- node Shift ranges start from
	self.Hover = 0
	self.Active = false -- keyboard goes to the tree
	self.Entries = {}
	self.Badges = props.Badges -- function(node) -> text?
	self.Dimmed = props.Dimmed -- function(node) -> true to fade the row (e.g. cut objects)
	self.OnContext = props.OnContext -- function(nodes, node, point)
	self.OnActivate = props.OnActivate -- function(node) on double-click (return true if handled)
	self.OnDelete = props.OnDelete -- function(nodes)
	self.OnRename = props.OnRename -- function(node, name) -> ok, reason
	self.OnMove = props.OnMove -- function(nodes, targetNode) after a drop
	self.OnUndo = props.OnUndo -- function() on Ctrl+Z
	self.OnShortcut = props.OnShortcut -- function(key, nodes) on Ctrl+<key>; return true if handled
	self.CanMove = props.CanMove -- function(nodes, targetNode) -> ok, reason
	self.CanDragNode = props.CanDrag -- function(node) -> false to keep a row from being dragged
	self.DropTarget = nil -- the row a drag would drop onto
	self._press = nil -- { Node, Point, Deferred } while the button is down on a row
	self._drag = nil -- the drag in progress
	self.EmptyText = props.EmptyText or "Nothing here"
	self._lastClick = { Node = nil, Time = 0 }
	self._width = 0

	local root = new("Frame", {
		Name = props.Name or "Tree",
		Size = props.Size or UDim2.fromScale(1, 1),
		Position = props.Position or UDim2.new(),
		BackgroundTransparency = 1,
		ClipsDescendants = true,
	})
	self.Instance = root
	self.Bin:Add(root)

	local scroll = Scroll.new({ Mode = "virtual", Direction = "XY", Parent = root })
	self.Scroll = scroll
	self.Bin:Add(scroll)
	self.Bin:Add(scroll.Changed:Connect(function()
		self:_render()
	end))
	self.Bin:Add(scroll.Instance:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		self:_render()
	end))

	self.EmptyLabel = new("TextLabel", {
		Name = "Empty",
		Text = self.EmptyText,
		Size = UDim2.new(1, 0, 0, 40),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextWrapped = true,
		Visible = false,
		Theme = { TextColor3 = "TextMuted" },
		Parent = scroll.Instance,
	})

	-- Empty space below the rows: click clears, right-click asks for a menu.
	local backdrop = new("TextButton", {
		Name = "Backdrop",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 0,
		Parent = scroll.Instance,
	})
	self.Bin:Add(backdrop.InputBegan:Connect(function(input)
		local point = Overlay.pointOf(input)
		local y = Create.toLocal(point, scroll.Instance).Y + scroll.Offset.Y
		if y < #self.Rows * ROW then
			return
		end
		self.Active = true
		local kind = input.UserInputType
		if kind == Enum.UserInputType.MouseButton1 then
			if not ctrlDown() and not shiftDown() then
				self:Select({}, nil)
			end
		elseif kind == Enum.UserInputType.MouseButton2 then
			self:Select({}, nil)
			self:_context(nil, point)
		end
	end))

	-- Keyboard focus follows clicks: inside the tree on, elsewhere off.
	self.Bin:Add(UserInputService.InputBegan:Connect(function(input)
		local kind = input.UserInputType
		if kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.MouseButton2 or kind == Enum.UserInputType.Touch then
			local point = Overlay.pointOf(input)
			if not (Overlay.shown(root) and Overlay.inside(root, point)) and not Overlay.popupAt(point) then
				self.Active = false
			end
		elseif kind == Enum.UserInputType.Keyboard then
			if self._drag and input.KeyCode == Enum.KeyCode.Escape then
				self:_endDrag(false)
				return
			end
			self:_onKey(input.KeyCode)
		end
	end))
	self.Bin:Add(UserInputService.InputChanged:Connect(function(input)
		local kind = input.UserInputType
		if kind ~= Enum.UserInputType.MouseMovement and kind ~= Enum.UserInputType.Touch then
			return
		end
		local press = self._press
		if not press then
			return
		end
		local point = Overlay.mouse()
		if not self._drag then
			if (point - press.Point).Magnitude < DRAG_START then
				return
			end
			self:_beginDrag(press)
			if not self._drag then
				return
			end
		end
		self:_updateDrag(point)
	end))
	self.Bin:Add(UserInputService.InputEnded:Connect(function(input)
		local kind = input.UserInputType
		if kind ~= Enum.UserInputType.MouseButton1 and kind ~= Enum.UserInputType.Touch then
			return
		end
		local press = self._press
		self._press = nil
		if self._drag then
			self:_endDrag(true)
		elseif press and press.Deferred and not press.Node.Removed then
			-- A plain click on a row of a multi-selection: it selects only
			-- that row once we know it wasn't the start of a drag.
			self:_click(press.Node)
		end
	end))

	self.Bin:Add(Create.cleanupWith(root, self))
	if props.Parent then
		root.Parent = props.Parent
	end
	return self
end

----------------------------------------------------------------------
-- Rows
----------------------------------------------------------------------

function TreeView:IsOpen(node): boolean
	local filter = self.Filter
	if filter and filter.Keep[node] then
		return not filter.Closed[node]
	end
	return node.Expanded == true
end

function TreeView:SetOpen(node, open: boolean)
	local filter = self.Filter
	if open then
		self.Tree:Load(node)
	end
	if filter and filter.Keep[node] then
		filter.Closed[node] = if open then nil else true
	else
		node.Expanded = open
	end
	self:Refresh()
end

function TreeView:Toggle(node)
	if node and self.Tree:HasChildren(node) then
		self:SetOpen(node, not self:IsOpen(node))
	end
end

function TreeView:SetFilter(filter)
	self.Filter = filter
	self:Refresh()
end

-- The name drawn for a node (Nil Instances shows its count once loaded).
local function displayName(node): string
	if node.IsNil and node.Loaded then
		return ("%s (%d)"):format(node.Name, #node.Children)
	end
	return node.Name
end

-- Where a row's content ends (arrow, icon, name and badge), in canvas
-- pixels. Measured with the real font so sideways scrolling reaches the
-- very end of long names.
function TreeView:_rowEnd(node, badgeText: string?): number
	local x = LEFT + node.Depth * INDENT + ARROW + ICON + 6
	x += math.ceil(Create.textWidth(displayName(node), Sizes.Text)) + 4 + 6 -- the same steps _render takes
	if badgeText then
		x += math.ceil(Create.textWidth(badgeText, Sizes.TextSmall, "Mono")) + 10
	end
	return x + RIGHT
end

function TreeView:Refresh()
	local rows = self.Tree:Flatten(self.Filter)
	self.Rows = rows
	table.clear(self.Index)
	local width = 0
	for index, node in rows do
		self.Index[node] = index
		local w = self:_rowEnd(node, nil)
		if w > width then
			width = w
		end
	end
	-- Drop selected nodes that left the tree.
	local dropped = false
	for node in table.clone(self.Selected) do
		if node.Removed then
			self.Selected[node] = nil
			dropped = true
		end
	end
	if dropped then
		self:_recount()
	end
	if self.Primary and self.Primary.Removed then
		self.Primary = nil
	end
	if self.Anchor and self.Anchor.Removed then
		self.Anchor = nil
	end
	self._width = math.ceil(width)
	self.Scroll:SetCanvasSize(Vector2.new(self._width, #rows * ROW))
	self:_render()
	if dropped then
		self:_fire()
	end
end

function TreeView:_makeEntry(slot: number)
	local row = new("TextButton", {
		Name = "Row" .. slot,
		Size = UDim2.new(0, 100, 0, ROW),
		BackgroundTransparency = 1,
		Theme = { BackgroundColor3 = "SurfaceHover" },
		ZIndex = 2,
		Parent = self.Scroll.Instance,
	})
	Create.corner(row, 4)
	local mark = new("Frame", {
		Name = "Mark",
		Size = UDim2.new(0, 2, 1, -6),
		Position = UDim2.fromOffset(0, 3),
		Visible = false,
		Theme = { BackgroundColor3 = "Accent" },
		ZIndex = 3,
		Parent = row,
	})
	local arrow = Icons.new("chevron_right", 12, "TextMuted")
	arrow.Name = "Arrow"
	arrow.AnchorPoint = Vector2.new(0.5, 0.5)
	arrow.ZIndex = 3
	arrow.Parent = row
	local icon = Icons.new("class_unknown", ICON - 2, "TextDim")
	icon.Name = "ClassIcon"
	icon.AnchorPoint = Vector2.new(0, 0.5)
	icon.ZIndex = 3
	icon.Parent = row
	local label = new("TextLabel", {
		Name = "Name",
		Size = UDim2.new(0, 100, 1, 0),
		AutomaticSize = Enum.AutomaticSize.None,
		TextTruncate = Enum.TextTruncate.None,
		ZIndex = 3,
		Parent = row,
	})
	local badge = new("Frame", {
		Name = "Badge",
		AnchorPoint = Vector2.new(0, 0.5),
		Size = UDim2.fromOffset(30, 16),
		Visible = false,
		ZIndex = 3,
		Theme = { BackgroundColor3 = "AccentSoft" },
		Parent = row,
	})
	Create.corner(badge, 4)
	local badgeText = new("TextLabel", {
		Name = "Text",
		Size = UDim2.fromScale(1, 1),
		TextSize = Sizes.TextSmall,
		FontFace = Theme.Fonts.Mono,
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 4,
		Theme = { TextColor3 = "Accent" },
		Parent = badge,
	})

	local entry = {
		Row = row,
		Mark = mark,
		Arrow = arrow,
		Icon = icon,
		IconName = nil,
		Label = label,
		Badge = badge,
		BadgeText = badgeText,
		Index = 0,
	}
	self.Entries[slot] = entry

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
		local node = self.Rows[entry.Index]
		if not node then
			return
		end
		local kind = input.UserInputType
		-- Clicking a highlighted row ends the highlight straight away.
		if self.Flashing and self.Flashing.Node == node and (kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.MouseButton2 or kind == Enum.UserInputType.Touch) then
			self:StopFlash()
		end
		if kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch then
			self.Active = true
			local point = Overlay.pointOf(input)
			local x = Create.toLocal(point, row).X
			local arrowLeft = LEFT + node.Depth * INDENT
			if x >= arrowLeft - 2 and x <= arrowLeft + ARROW + 2 and self.Tree:HasChildren(node) then
				self:Toggle(node)
				return
			end
			if self.OnMove and not self.PickHandler and self:CanDrag(node) then
				-- Might become a drag. Pressing a row of a multi-selection
				-- keeps the selection (to drag them all) until release.
				local deferred = self.Selected[node] == true and self.SelectedCount > 1 and not ctrlDown() and not shiftDown()
				self._press = { Node = node, Point = point, Deferred = deferred }
				if deferred then
					return
				end
			end
			self:_click(node)
		elseif kind == Enum.UserInputType.MouseButton2 then
			self.Active = true
			if not self.Selected[node] then
				self:Select({ node }, node)
			end
			self:_context(node, Overlay.pointOf(input))
		end
	end)
	return entry
end

-- Rows of a frozen tree whose object is no longer there (Tree:FrozenState).
local FROZEN_STYLE = {
	deleted = { Text = "Danger", Band = "Danger", Transparency = 0.82 },
	inside_deleted = { Text = "DangerSoft", Band = "Danger", Transparency = 0.9 },
	moved = { Text = "Moved", Band = "Moved", Transparency = 0.84 },
	inside_moved = { Text = "Moved", Band = "Moved", Transparency = 0.92 },
}

function TreeView:_paint(entry)
	local node = self.Rows[entry.Index]
	local selected = node ~= nil and self.Selected[node] == true
	local hovered = entry.Index ~= 0 and self.Hover == entry.Index
	if node ~= nil and self.Flashing and node == self.Flashing.Node and node ~= self.DropTarget then
		self:_paintFlash(entry, os.clock() - self.Flashing.Started)
		return
	end
	entry.FlashBound = nil
	if node ~= nil and node == self.DropTarget then
		-- Where a drag would drop: accent band and mark.
		Theme.bind(entry.Row, "BackgroundColor3", "AccentSoft")
		entry.Row.BackgroundTransparency = 0
		entry.Mark.Visible = true
		return
	end
	if selected then
		Theme.bind(entry.Row, "BackgroundColor3", "Selection")
		entry.Row.BackgroundTransparency = if hovered then 0 else 0.15
	elseif node ~= nil and entry.FrozenState then
		-- frozen, and the object is no longer here: a tinted band
		local style = FROZEN_STYLE[entry.FrozenState]
		Theme.bind(entry.Row, "BackgroundColor3", style.Band)
		entry.Row.BackgroundTransparency = if hovered then style.Transparency - 0.12 else style.Transparency
	else
		Theme.bind(entry.Row, "BackgroundColor3", "SurfaceHover")
		entry.Row.BackgroundTransparency = if hovered then 0.35 else 1
	end
	entry.Mark.Visible = selected and node == self.Primary
end

local NIL_STYLE = nil
local function styleOf(node)
	if node.IsNil then
		NIL_STYLE = NIL_STYLE or Categories.valueType("nil")
		return NIL_STYLE.Icon, NIL_STYLE.Color
	end
	local style = Classes.style(node.Class)
	return style.Icon, style.Color
end

function TreeView:_render()
	local scroll = self.Scroll
	local offset = scroll.Offset
	local view = scroll:ViewSize()
	local rows = self.Rows
	local first = math.max(1, math.floor(offset.Y / ROW) + 1)
	local count = math.ceil(math.max(view.Y, ROW) / ROW) + 1
	local rowWidth = math.max(self._width, view.X)
	local grow = 0
	self.EmptyLabel.Visible = #rows == 0
	self.EmptyLabel.Text = self.EmptyText

	for slot = 1, math.max(count, #self.Entries) do
		local entry = self.Entries[slot]
		local index = first + slot - 1
		local node = rows[index]
		if slot > count or node == nil then
			if entry then
				entry.Row.Visible = false
				entry.Index = 0
			end
		else
			entry = entry or self:_makeEntry(slot)
			entry.Index = index
			local row = entry.Row
			row.Visible = true
			row.Position = UDim2.fromOffset(-offset.X, (index - 1) * ROW - offset.Y)
			row.Size = UDim2.new(0, rowWidth, 0, ROW)

			local x = LEFT + node.Depth * INDENT
			local hasKids = self.Tree:HasChildren(node)
			entry.Arrow.Visible = hasKids
			entry.Arrow.Position = UDim2.new(0, x + ARROW / 2, 0.5, 0)
			entry.Arrow.Rotation = if self:IsOpen(node) then 90 else 0
			x += ARROW

			local iconName, color = styleOf(node)
			if iconName ~= entry.IconName then
				Icons.set(entry.Icon, iconName)
				entry.IconName = iconName
			end
			Icons.tint(entry.Icon, color)
			local dimmed = self.Dimmed ~= nil and not node.IsNil and self.Dimmed(node) == true
			entry.Dimmed = dimmed
			entry.Icon.ImageTransparency = if dimmed then 0.55 else 0
			entry.Icon.Position = UDim2.new(0, x, 0.5, 0)
			x += ICON + 6

			local name = displayName(node)
			local label = entry.Label
			label.Text = name
			-- Gone (frozen tree, the object left this place): red
			-- Frozen: deleted red, inside something deleted light red, moved
			-- (or inside something moved) light blue.
			local state = if self.Tree.FrozenState then self.Tree:FrozenState(node) else nil
			entry.Gone = state ~= nil
			entry.FrozenState = state
			Theme.bind(label, "TextColor3", if state then FROZEN_STYLE[state].Text elseif node.IsNil or dimmed then "TextDim" else "Text")
			label.TextTransparency = if dimmed then 0.35 else 0
			local nameWidth = math.ceil(Create.textWidth(name, Sizes.Text)) + 4
			label.Position = UDim2.fromOffset(x, 0)
			label.Size = UDim2.new(0, nameWidth, 1, 0)
			x += nameWidth + 6

			local badgeText = if self.Badges and not node.IsNil then self.Badges(node) else nil
			if badgeText then
				entry.BadgeText.Text = badgeText
				entry.Badge.Size = UDim2.fromOffset(math.ceil(Create.textWidth(badgeText, Sizes.TextSmall, "Mono")) + 10, 16)
				entry.Badge.Position = UDim2.new(0, x, 0.5, 0)
				entry.Badge.Visible = true
			else
				entry.Badge.Visible = false
			end
			-- a badge (or a count) can make a row longer than Refresh measured
			local rowEnd = x + (if badgeText then entry.Badge.Size.X.Offset else 0) + RIGHT
			if rowEnd > self._width then
				grow = math.max(grow, rowEnd)
			end
			self:_paint(entry)
		end
	end
	if grow > 0 then
		-- widen the canvas so sideways scrolling reaches the end of it
		self._width = math.ceil(grow)
		self.Scroll:SetCanvasSize(Vector2.new(self._width, #rows * ROW))
		local wide = math.max(self._width, view.X)
		for _, item in self.Entries do
			if item.Row.Visible then
				item.Row.Size = UDim2.new(0, wide, 0, ROW)
			end
		end
	end
end

-- Draws the visible rows again (after something Badges / Dimmed read
-- changed) without rebuilding the tree.
function TreeView:Redraw()
	self:_render()
end

-- Screen rectangle of a node's name (scrolled into view first).
function TreeView:NameRect(node): (Vector2?, Vector2?)
	local index = self.Index[node]
	if not index then
		return nil, nil
	end
	self:Reveal(node, false)
	self:_render()
	-- worked out in layout pixels, returned on screen like AbsolutePosition
	local origin = self.Scroll.Instance.AbsolutePosition
	local factor = Create.scaleOf(self.Scroll.Instance)
	local x = LEFT + node.Depth * INDENT + ARROW + ICON + 6 - self.Scroll.Offset.X
	local y = (index - 1) * ROW - self.Scroll.Offset.Y
	local width = math.max(120, self.Scroll:ViewSize().X - x - 6)
	return origin + Vector2.new(x - 4, y) * factor, Vector2.new(width, ROW) * factor
end

----------------------------------------------------------------------
-- Selection
----------------------------------------------------------------------

function TreeView:_recount()
	local count = 0
	for _ in self.Selected do
		count += 1
	end
	self.SelectedCount = count
end

function TreeView:_repaint()
	for _, entry in self.Entries do
		if entry.Index ~= 0 then
			self:_paint(entry)
		end
	end
end

function TreeView:GetSelected(): { any }
	local list = {}
	if self.SelectedCount == 0 then
		return list
	end
	for _, node in self.Rows do
		if self.Selected[node] then
			table.insert(list, node)
		end
	end
	-- Selected nodes not on screen (inside closed parents) go last.
	for node in self.Selected do
		if not self.Index[node] then
			table.insert(list, node)
		end
	end
	return list
end

function TreeView:_fire()
	self.SelectionChanged:Fire(self:GetSelected(), self.Primary)
end

-- Replaces the selection. primary: the node the path bar follows.
function TreeView:Select(nodes: { any }, primary: any?, silent: boolean?)
	table.clear(self.Selected)
	for _, node in nodes do
		if not node.Removed then
			self.Selected[node] = true
		end
	end
	self:_recount()
	self.Primary = primary or nodes[#nodes]
	if self.Primary and not self.Selected[self.Primary] then
		self.Primary = nodes[#nodes]
	end
	self.Anchor = self.Primary
	self:_repaint()
	if not silent then
		self:_fire()
	end
end

function TreeView:SelectAll()
	self:Select(table.clone(self.Rows), self.Primary)
end

function TreeView:_click(node)
	-- Pick mode (a property editor asked for an object): the click picks.
	local pick = self.PickHandler
	if pick then
		self.PickHandler = nil
		local ok, err = pcall(pick, node)
		if not ok then
			T.Log.error("explorer", "pick failed: " .. tostring(err))
		end
		return
	end
	local now = os.clock()
	local last = self._lastClick
	if last.Node == node and now - last.Time < DOUBLE_CLICK and not ctrlDown() and not shiftDown() then
		last.Time = 0
		local handled = false
		if self.OnActivate then
			local ok, result = pcall(self.OnActivate, node)
			handled = ok and result == true
		end
		if not handled then
			self:Toggle(node)
		end
		return
	end
	last.Node, last.Time = node, now

	if shiftDown() and self.Anchor and self.Index[self.Anchor] then
		local from, to = self.Index[self.Anchor], self.Index[node]
		if from > to then
			from, to = to, from
		end
		if not ctrlDown() then
			table.clear(self.Selected)
		end
		for i = from, to do
			self.Selected[self.Rows[i]] = true
		end
		self:_recount()
		self.Primary = node
		self:_repaint()
		self:_fire()
	elseif ctrlDown() then
		if self.Selected[node] then
			self.Selected[node] = nil
			if self.Primary == node then
				self.Primary = nil
			end
		else
			self.Selected[node] = true
			self.Primary = node
		end
		self.Anchor = node
		self:_recount()
		self:_repaint()
		self:_fire()
	else
		self:Select({ node }, node)
	end
end

function TreeView:_context(node, point: Vector2)
	if self.OnContext then
		local ok, err = pcall(self.OnContext, self:GetSelected(), node, point)
		if not ok then
			T.Log.error("explorer", "menu failed: " .. tostring(err))
		end
	end
end

-- Lights a row up for a moment (Highlight from the path bar).
-- Lights a row up (Highlight from the path bar or a property): it pulses
-- in the accent color for a few seconds so it is easy to spot, and stops
-- at once when the row is clicked (or another row is highlighted).
local FLASH_TIME = 3 -- seconds in all
local FLASH_PULSE = 0.75 -- seconds per pulse (FLASH_TIME is a whole number of them)

local function flashTransparency(t: number): number
	-- 0.85 (faint) -> 0.3 (strong) -> 0.85 each pulse; starts and ends faint
	local wave = math.sin(math.pi * t / FLASH_PULSE)
	return 0.85 - 0.55 * wave * wave
end

function TreeView:_paintFlash(entry, t: number)
	local row = entry.Row
	if entry.FlashBound ~= self.Flashing then
		entry.FlashBound = self.Flashing
		Theme.bind(row, "BackgroundColor3", "Accent")
	end
	row.BackgroundTransparency = flashTransparency(t)
	entry.Mark.Visible = true
end

function TreeView:Flash(node)
	self:StopFlash()
	if not node then
		return
	end
	local flash = { Node = node, Started = os.clock() }
	self.Flashing = flash
	self.Flashed = node
	flash.Loop = Services.RunService.RenderStepped:Connect(function()
		if self.Flashing ~= flash then
			return
		end
		local t = os.clock() - flash.Started
		if t >= FLASH_TIME or node.Removed then
			self:StopFlash()
			return
		end
		for _, entry in self.Entries do
			if entry.Index ~= 0 and self.Rows[entry.Index] == node and entry.Row.Visible then
				self:_paintFlash(entry, t)
			end
		end
	end)
end

-- Ends a highlight at once (clicking the row does this).
function TreeView:StopFlash()
	local flash = self.Flashing
	if not flash then
		return
	end
	self.Flashing = nil
	if flash.Loop then
		flash.Loop:Disconnect()
	end
	for _, entry in self.Entries do
		entry.FlashBound = nil
	end
	self:_repaint()
end

function TreeView:IsFlashing(node): boolean
	return self.Flashing ~= nil and (node == nil or self.Flashing.Node == node)
end

-- Scrolls a node into view (opening nothing).
function TreeView:Reveal(node, animated: boolean?)
	local index = self.Index[node]
	if index then
		self.Scroll:Reveal("Y", (index - 1) * ROW, index * ROW, ROW, animated)
		local x = LEFT + node.Depth * INDENT
		self.Scroll:Reveal("X", math.max(0, x - 8), x + ARROW + ICON + 80, 0, animated)
	end
end

----------------------------------------------------------------------
-- Dragging rows onto rows (moving objects)
----------------------------------------------------------------------

-- The row under a screen point (nil outside the rows).
function TreeView:RowAt(point: Vector2)
	if not (Overlay.shown(self.Instance) and Overlay.inside(self.Scroll.Instance, point)) then
		return nil
	end
	local y = Create.toLocal(point, self.Scroll.Instance).Y + self.Scroll.Offset.Y
	if y < 0 then
		return nil
	end
	return self.Rows[math.floor(y / ROW) + 1]
end

-- The dragged nodes: the selection (or just the pressed row), without
-- nodes whose ancestor is dragged too (they move with it).
-- Rows that can be picked up (CanDrag; the explorer keeps services like
-- Workspace where they are).
function TreeView:CanDrag(node): boolean
	if not node or not node.Obj or node.IsNil then
		return false
	end
	if self.CanDragNode then
		local ok, result = pcall(self.CanDragNode, node)
		return ok and result ~= false
	end
	return true
end

local function dragNodes(self, pressed)
	local list = if self.Selected[pressed] then self:GetSelected() else { pressed }
	local set = {}
	for _, node in list do
		if node.Obj and not node.IsNil and not node.Removed and self:CanDrag(node) then
			set[node] = true
		end
	end
	local out = {}
	for _, node in list do
		if set[node] then
			local parent, inner = node.Parent, false
			while parent do
				if set[parent] then
					inner = true
					break
				end
				parent = parent.Parent
			end
			if not inner then
				table.insert(out, node)
			end
		end
	end
	return out
end

function TreeView:_beginDrag(press)
	local nodes = dragNodes(self, press.Node)
	if #nodes == 0 then
		self._press = nil
		return
	end
	local okLayer, layer = pcall(Overlay.layer)
	if not okLayer then
		self._press = nil
		return
	end
	local ghost = new("Frame", {
		Name = "DragLabel",
		Size = UDim2.fromOffset(120, 24),
		Active = false,
		ZIndex = 950,
		Theme = { BackgroundColor3 = "SurfaceActive" },
		Parent = layer,
	})
	Create.corner(ghost, 5)
	local ghostStroke = Create.stroke(ghost, "BorderStrong", 1, 0)
	local iconName, color = styleOf(nodes[1])
	local icon = Icons.new(iconName, ICON - 2, color)
	icon.AnchorPoint = Vector2.new(0, 0.5)
	icon.Position = UDim2.new(0, 7, 0.5, 0)
	icon.ZIndex = 951
	icon.Parent = ghost
	local label = new("TextLabel", {
		Name = "Text",
		Position = UDim2.fromOffset(7 + ICON + 2, 0),
		Size = UDim2.new(1, -(7 + ICON + 8), 1, 0),
		Text = "",
		TextSize = Sizes.TextSmall,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 951,
		Theme = { TextColor3 = "Text" },
		Parent = ghost,
	})
	local drag = {
		Nodes = nodes,
		Title = if #nodes == 1 then nodes[1].Name else ("%d objects"):format(#nodes),
		Ghost = ghost,
		GhostStroke = ghostStroke,
		Label = label,
		Target = nil,
		Valid = false,
		Point = press.Point,
		HoverNode = nil,
		HoverSince = 0,
	}
	self._drag = drag
	-- Scroll near the edges and open closed rows the mouse rests on.
	local last = os.clock()
	drag.Loop = Services.RunService.RenderStepped:Connect(function()
		local now = os.clock()
		local dt = math.min(now - last, 0.1)
		last = now
		if self._drag ~= drag then
			return
		end
		local view = self.Scroll.Instance
		local left, top = view.AbsolutePosition.X, view.AbsolutePosition.Y
		local bottom = top + view.AbsoluteSize.Y
		local point = drag.Point
		local edge = DRAG_EDGE * Create.scaleOf(view) -- on screen
		local speed = 0
		if point.X >= left and point.X <= left + view.AbsoluteSize.X then
			if point.Y < top + edge and point.Y > top - edge then
				speed = -DRAG_SCROLL * (1 - math.clamp((point.Y - top) / edge, 0, 1))
			elseif point.Y > bottom - edge and point.Y < bottom + edge then
				speed = DRAG_SCROLL * (1 - math.clamp((bottom - point.Y) / edge, 0, 1))
			end
		end
		if speed ~= 0 then
			local before = self.Scroll.Offset
			self.Scroll:ScrollTo(before + Vector2.new(0, speed * dt), false)
			if self.Scroll.Offset ~= before then
				self:_updateDrag(point)
			end
		end
		local hover = drag.HoverNode
		if hover and now - drag.HoverSince >= DRAG_OPEN and self.Tree:HasChildren(hover) and not self:IsOpen(hover) then
			drag.HoverSince = math.huge
			self:SetOpen(hover, true)
			self:_updateDrag(drag.Point)
		end
	end)
	self:_updateDrag(press.Point)
end

function TreeView:_updateDrag(point: Vector2)
	local drag = self._drag
	if not drag then
		return
	end
	drag.Point = point
	local target = self:RowAt(point)
	local valid, reason = false, nil
	if target then
		if self.CanMove then
			local ok, result, why = pcall(self.CanMove, drag.Nodes, target)
			valid, reason = ok and result == true, if ok then why else "can't drop here"
		else
			valid = target.Obj ~= nil and not target.IsNil
		end
	end
	if target ~= drag.HoverNode then
		drag.HoverNode = target
		drag.HoverSince = os.clock()
	end
	drag.Target, drag.Valid = target, valid
	-- Over itself (where the drag started) the label just names it.
	local quiet = target == nil or table.find(drag.Nodes, target) ~= nil
	local text = drag.Title
	if valid then
		text = ("%s  →  %s"):format(drag.Title, target.Name)
	elseif not quiet and reason then
		text = ("%s  ·  %s"):format(drag.Title, reason)
	end
	drag.Label.Text = text
	Theme.bind(drag.Label, "TextColor3", if valid or quiet or not reason then "Text" else "TextMuted")
	Theme.bind(drag.GhostStroke, "Color", if valid then "Accent" else "BorderStrong")
	local width = math.min(math.ceil(Create.textWidth(text, Sizes.TextSmall)) + 7 + ICON + 14, 340)
	local at = Overlay.toLayout(point) -- the label is on the (scaled) popup layer
	drag.Ghost.Size = UDim2.fromOffset(width, 24)
	drag.Ghost.Position = UDim2.fromOffset(at.X + 14, at.Y + 10)
	local dropTarget = if valid then target else nil
	if dropTarget ~= self.DropTarget then
		self.DropTarget = dropTarget
		self:_repaint()
	end
end

-- drop: move the objects (false: Escape / cancelled).
function TreeView:_endDrag(drop: boolean)
	local drag = self._drag
	self._drag = nil
	self._press = nil
	if not drag then
		return
	end
	if drag.Loop then
		drag.Loop:Disconnect()
	end
	if drag.Ghost then
		drag.Ghost:Destroy()
	end
	self.DropTarget = nil
	self:_repaint()
	if drop and drag.Valid and drag.Target and self.OnMove then
		local ok, err = pcall(self.OnMove, drag.Nodes, drag.Target)
		if not ok then
			T.Log.error("explorer", "move failed: " .. tostring(err))
		end
	end
end

function TreeView:IsDragging(): boolean
	return self._drag ~= nil
end

----------------------------------------------------------------------
-- Keyboard
----------------------------------------------------------------------

function TreeView:_onKey(key: Enum.KeyCode)
	if not self.Active or not self.Instance.Parent or not Overlay.shown(self.Instance) then
		return
	end
	if UserInputService:GetFocusedTextBox() or Overlay.isOpen() then
		return
	end
	local rows = self.Rows
	local current = self.Primary
	local index = current and self.Index[current]

	local function moveTo(newIndex: number)
		newIndex = math.clamp(newIndex, 1, #rows)
		local node = rows[newIndex]
		if not node then
			return
		end
		if shiftDown() and self.Anchor and self.Index[self.Anchor] then
			local from, to = self.Index[self.Anchor], newIndex
			if from > to then
				from, to = to, from
			end
			table.clear(self.Selected)
			for i = from, to do
				self.Selected[rows[i]] = true
			end
			self:_recount()
			self.Primary = node
			self:_repaint()
			self:_fire()
		else
			self:Select({ node }, node)
		end
		self:Reveal(node, true)
	end

	if key == Enum.KeyCode.Down then
		moveTo(if index then index + 1 else 1)
	elseif key == Enum.KeyCode.Up then
		moveTo(if index then index - 1 else #rows)
	elseif key == Enum.KeyCode.Home then
		moveTo(1)
	elseif key == Enum.KeyCode.End then
		moveTo(#rows)
	elseif key == Enum.KeyCode.Right then
		if not current then
			return
		end
		if self.Tree:HasChildren(current) and not self:IsOpen(current) then
			self:SetOpen(current, true)
		elseif self:IsOpen(current) and index and rows[index + 1] and rows[index + 1].Parent == current then
			moveTo(index + 1)
		end
	elseif key == Enum.KeyCode.Left then
		if not current then
			return
		end
		if self:IsOpen(current) and self.Tree:HasChildren(current) then
			self:SetOpen(current, false)
		elseif current.Parent and self.Index[current.Parent] then
			moveTo(self.Index[current.Parent])
		end
	elseif key == Enum.KeyCode.Return or key == Enum.KeyCode.KeypadEnter then
		if current then
			self:Toggle(current)
		end
	elseif ctrlDown() and self.OnShortcut and key ~= Enum.KeyCode.A and key ~= Enum.KeyCode.Z then
		local ok, result = pcall(self.OnShortcut, key, self:GetSelected())
		if not ok then
			T.Log.error("explorer", "shortcut failed: " .. tostring(result))
		end
	elseif key == Enum.KeyCode.A and ctrlDown() then
		self:SelectAll()
	elseif key == Enum.KeyCode.Z and ctrlDown() then
		if self.OnUndo then
			local ok, err = pcall(self.OnUndo)
			if not ok then
				T.Log.error("explorer", "undo failed: " .. tostring(err))
			end
		end
	elseif key == Enum.KeyCode.F2 then
		if current then
			self:BeginRename(current)
		end
	elseif key == Enum.KeyCode.Delete then
		local nodes = self:GetSelected()
		if #nodes > 0 and self.OnDelete then
			local ok, err = pcall(self.OnDelete, nodes)
			if not ok then
				T.Log.error("explorer", "delete failed: " .. tostring(err))
			end
		end
	end
end

----------------------------------------------------------------------
-- Rename
----------------------------------------------------------------------

function TreeView:BeginRename(node)
	if not node or node.IsNil or node.Removed then
		return nil
	end
	local pos, size = self:NameRect(node)
	if not pos then
		return nil
	end
	local handle = CellEditor.open({
		AnchorPos = pos,
		AnchorSize = size,
		Text = node.Name,
		Hint = "new name · Enter saves",
		Validate = function(text)
			if text == "" then
				return false, "a name can't be empty"
			end
			return true, text
		end,
		OnCommit = function(name)
			if self.OnRename then
				return self.OnRename(node, name)
			end
			local ok, err = pcall(function()
				node.Obj.Name = name
			end)
			if not ok then
				return false, tostring(err)
			end
			return true
		end,
		Owner = self,
	})
	self.Renaming = handle
	return handle
end

function TreeView:Destroy()
	self:_endDrag(false)
	self:StopFlash()
	if self.Renaming and not self.Renaming.Closed then
		self.Renaming:Close("destroyed")
	end
	self.Bin:Clean()
	self.SelectionChanged:DisconnectAll()
end

return TreeView
