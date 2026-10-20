--[[
	Tungsten · base/explorer/propview
	The properties panel under the explorer tree: the selection's
	properties by category, then its attributes and tags. Only the rows on
	screen exist.

		local view = PropView.new({ Parent = frame, Explorer = Explorer })
		view:SetInstances({ part })      -- what to show
		view:SetFilter("anch")           -- only matching names / categories
		view:Apply(row, value)           -- write a value (all selected objects)

	Rows: categories (click to fold), properties, sub-rows of composite
	values (X / Y / Z, Position / Orientation …, opened with the arrow),
	attributes, "Add attribute…" and tags. Clicking a value edits it the
	way its editor says (base/explorer/editors): a switch, a list, a color
	popup or a text box. Read-only properties are greyed out. Right-click
	opens the "explorer.property" menu.

	Values update live: the panel listens to Changed / AttributeChanged on
	the (first 50) selected objects and redraws once per frame.
]]

local T = ...
local signal = T.import("base/signal")
local Settings = T.import("base/settings")
local Theme = T.import("base/theme")
local Types = T.import("base/types")
local Create = T.import("base/ui/create")
local Animate = T.import("base/ui/animate")
local Icons = T.import("base/data/icons")
local Overlay = T.import("base/ui/overlay")
local Menus = T.import("base/ui/menus")
local Scroll = T.import("base/ui/components/scroll")
local Dropdown = T.import("base/ui/components/dropdown")
local CellEditor = T.import("base/ui/components/celleditor")
local Properties = T.import("base/explorer/properties")
local Editors = T.import("base/explorer/editors")

local new = Create.new
local Sizes = Theme.Sizes

local ROW = 22
local INDENT = 12
local LEFT = 6
local ARROW = 14
local SWATCH = 14
local VALUE_PAD = 8
local MAX_DISTINCT = 50
local GUTTER = 12 -- right edge kept clear for the scroll bar

local PropView = {}
PropView.__index = PropView
PropView.RowHeight = ROW

function PropView.new(props: { [string]: any })
	local self = setmetatable({}, PropView)
	self.Bin = signal.bin()
	self.Explorer = props.Explorer
	self.Origin = props.Origin or "core"
	self.Instances = {}
	self.Rows = {}
	self.Entries = {} -- row slots
	self.Expanded = {} -- property / attribute key -> true
	self.Filter = ""
	self.Hover = 0
	self.Selected = nil -- key of the last clicked row
	self.Changed = signal.new() -- () after every rebuild
	self._watch = signal.bin()
	self.Bin:Add(self._watch)
	self._queued = false

	local root = new("Frame", {
		Name = props.Name or "Properties",
		Size = props.Size or UDim2.fromScale(1, 1),
		Position = props.Position or UDim2.new(),
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		Parent = props.Parent,
	})
	self.Instance = root
	self.Bin:Add(root)

	local scroll = Scroll.new({ Mode = "virtual", Direction = "Y", Parent = root, Origin = self.Origin })
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
		Text = "Select an object to see its properties",
		Size = UDim2.new(1, -16, 0, 40),
		Position = UDim2.fromOffset(8, 0),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextWrapped = true,
		Visible = false,
		Theme = { TextColor3 = "TextMuted" },
		Parent = scroll.Instance,
	})

	self.Bin:Add(Settings.Changed:Connect(function(key)
		if key == "PropertyDecimals" or key == "PropertiesDeprecated" or key == "PropertiesHidden" then
			self:Rebuild()
		end
	end))
	self.Bin:Add(Editors.Changed:Connect(function()
		self:Rebuild()
	end))
	self.Bin:Add(Create.cleanupWith(root, self))
	return self
end

----------------------------------------------------------------------
-- Options
----------------------------------------------------------------------

function PropView:Options()
	return {
		ShowDeprecated = Settings.get("PropertiesDeprecated") == true,
		ShowHidden = Settings.get("PropertiesHidden") == true,
		Filter = self.Filter,
	}
end

local function collapsedSet(): { [string]: boolean }
	local set = {}
	for _, name in Settings.get("PropertiesCollapsed") or {} do
		set[name] = true
	end
	return set
end

function PropView:IsCollapsed(category: string): boolean
	return collapsedSet()[category] == true
end

function PropView:SetCollapsed(category: string, collapsed: boolean)
	local list = {}
	for name in collapsedSet() do
		if name ~= category then
			table.insert(list, name)
		end
	end
	if collapsed then
		table.insert(list, category)
	end
	table.sort(list)
	Settings.set("PropertiesCollapsed", list)
	self:Rebuild()
end

function PropView:SetAllCollapsed(collapsed: boolean)
	local list = {}
	if collapsed then
		local seen = {}
		for _, row in self.Rows do
			if row.Kind == "category" and not seen[row.Name] then
				seen[row.Name] = true
				table.insert(list, row.Name)
			end
		end
		for name in collapsedSet() do
			if not seen[name] then
				table.insert(list, name)
			end
		end
		table.sort(list)
	end
	Settings.set("PropertiesCollapsed", list)
	self:Rebuild()
end

function PropView:SetFilter(text: string)
	self.Filter = tostring(text or "")
	self:Rebuild()
end

----------------------------------------------------------------------
-- Building rows
----------------------------------------------------------------------

local function distinctCount(instances: { Instance }, prop): number
	local uniques = {}
	for _, instance in Properties.compared(instances) do
		local ok, value = Properties.read(instance, prop)
		if ok then
			local found = false
			for _, other in uniques do
				if Properties.equal(other, value) then
					found = true
					break
				end
			end
			if not found then
				table.insert(uniques, value)
				if #uniques >= MAX_DISTINCT then
					break
				end
			end
		end
	end
	return #uniques
end

-- A property-like description of an attribute (editors work on both).
local function attributeProp(entry)
	local prop = {
		Name = entry.Name,
		Class = "?",
		Category = "Attributes",
		Type = entry.Type,
		DataType = entry.Type,
		Attribute = true,
		Security = "None",
	}
	if entry.Type == "EnumItem" and typeof(entry.Value) == "EnumItem" then
		prop.Enum = (tostring(entry.Value.EnumType):gsub("^Enum%.", ""))
	end
	prop.Editable = T.import("base/explorer/api").EditableTypes[entry.Type] == true
	return prop
end
PropView.attributeProp = attributeProp

function PropView:SetInstances(instances: { Instance })
	self.Instances = table.clone(instances or {})
	self:_watchInstances()
	self:Rebuild()
end

function PropView:_watchInstances()
	self._watch:Clean()
	self._dirty = {}
	self._dirtyAll = false
	for _, instance in Properties.compared(self.Instances) do
		pcall(function()
			local okValue, isValue = pcall(function()
				return instance:IsA("ValueBase")
			end)
			if okValue and isValue then
				-- ValueBase.Changed passes the new value, not a name.
				self._watch:Add(instance.Changed:Connect(function()
					self:Queue("Value")
				end))
				self._watch:Add(instance:GetPropertyChangedSignal("Name"):Connect(function()
					self:Queue("Name")
				end))
			else
				self._watch:Add(instance.Changed:Connect(function(name)
					self:Queue(if type(name) == "string" then name else nil)
				end))
			end
			self._watch:Add(instance.AttributeChanged:Connect(function()
				self:Queue(nil)
			end))
		end)
	end
end

--[[
	Redraws on the next frame, so many changes at once redraw once. A
	property name re-reads just that property; nil rebuilds everything
	(attributes changed, or something unknown).
]]
function PropView:Queue(name: string?)
	self._dirty = self._dirty or {}
	if name == nil then
		self._dirtyAll = true
	else
		self._dirty[name] = true
	end
	if self._queued then
		return
	end
	self._queued = true
	task.defer(function()
		self._queued = false
		local all, names = self._dirtyAll, self._dirty
		self._dirtyAll = false
		self._dirty = {}
		if not self.Instance.Parent then
			return
		end
		if all then
			self:Rebuild()
		else
			self:RefreshValues(names)
		end
	end)
end

-- Re-reads some properties' values (and their parts) in place.
function PropView:RefreshValues(names: { [string]: boolean })
	local instances = self.Instances
	local touched = false
	for index, row in self.Rows do
		if row.Kind == "property" and names[row.Name] then
			local entry = Properties.entry(instances, row.Prop)
			row.Value, row.Same, row.Readable, row.Reason = entry.Value, entry.Same, entry.Readable, entry.Reason
			row.Distinct = if entry.Same then 1 else distinctCount(instances, row.Prop)
			touched = true
		elseif row.Kind == "field" and row.Parent.Kind == "property" and names[row.Parent.Name] then
			row.Value, row.Same = Properties.fieldValue(instances, row.Parent.Prop, row.Field)
		end
	end
	if touched then
		self:_render()
		self.Changed:Fire()
	end
end

function PropView:Rebuild()
	local instances = self.Instances
	local rows = {}
	local collapsed = collapsedSet()
	local opts = self:Options()
	local entries = if #instances > 0 then Properties.collect(instances, opts) else {}
	self.Data = entries
	local lastCategory = nil

	local function addValueRows(row)
		table.insert(rows, row)
		local fields = if row.Prop.Type ~= nil then Properties.fields(row.Prop) else nil
		row.Expandable = fields ~= nil and row.Readable ~= false
		if row.Expandable and self.Expanded[row.Key] then
			for _, field in fields :: { any } do
				local value, same
				if row.Kind == "attribute" then
					value, same = self:_attributeFieldValue(row, field)
				else
					value, same = Properties.fieldValue(instances, row.Prop, field)
				end
				local fieldProp = {
					Name = field.Name,
					Type = field.Type,
					Enum = field.Enum,
					Integer = field.Integer,
					Class = "?",
					Category = row.Prop.Category,
					Editable = row.Prop.Editable ~= false and not row.Prop.ReadOnly,
					ReadOnly = row.Prop.ReadOnly,
					Security = "None",
				}
				table.insert(rows, {
					Kind = "field",
					Key = row.Key .. "." .. field.Name,
					Parent = row,
					Field = field,
					Prop = fieldProp,
					Name = field.Name,
					Value = value,
					Same = same,
					Readable = true,
					Depth = 1,
				})
			end
		end
	end

	for _, entry in entries do
		if entry.Category ~= lastCategory then
			lastCategory = entry.Category
			table.insert(rows, { Kind = "category", Name = entry.Category, Key = "#" .. entry.Category, Collapsed = collapsed[entry.Category] == true })
		end
		if not collapsed[entry.Category] then
			addValueRows({
				Kind = "property",
				Key = entry.Name,
				Name = entry.Name,
				Prop = entry.Prop,
				Value = entry.Value,
				Same = entry.Same,
				Readable = entry.Readable,
				Reason = entry.Reason,
				Distinct = if entry.Same then 1 else distinctCount(instances, entry.Prop),
				Depth = 0,
			})
		end
	end

	-- Attributes and tags.
	if #instances > 0 then
		local filter = self.Filter:lower()
		local attributes = Properties.attributes(instances)
		local category = "Attributes"
		table.insert(rows, { Kind = "category", Name = category, Key = "#" .. category, Collapsed = collapsed[category] == true })
		if not collapsed[category] then
			for _, attribute in attributes do
				if filter == "" or attribute.Name:lower():find(filter, 1, true) or ("attributes"):find(filter, 1, true) then
					addValueRows({
						Kind = "attribute",
						Key = "@" .. attribute.Name,
						Name = attribute.Name,
						Prop = attributeProp(attribute),
						Value = attribute.Value,
						Same = attribute.Same,
						Readable = true,
						Distinct = if attribute.Same then 1 else self:_attributeDistinct(attribute.Name),
						Depth = 0,
					})
				end
			end
			table.insert(rows, { Kind = "add_attribute", Key = "+attribute", Name = "Add attribute…", Depth = 0 })
		end
		local tags = Properties.tags(instances)
		if #tags > 0 then
			category = "Tags"
			table.insert(rows, { Kind = "category", Name = category, Key = "#" .. category, Collapsed = collapsed[category] == true })
			if not collapsed[category] then
				for _, tag in tags do
					if filter == "" or tag:lower():find(filter, 1, true) or ("tags"):find(filter, 1, true) then
						table.insert(rows, { Kind = "tag", Key = "%" .. tag, Name = tag, Depth = 0 })
					end
				end
			end
		end
	end

	self.Rows = rows
	self.EmptyLabel.Text = if #instances == 0
		then "Select an object to see its properties"
		elseif self.Filter ~= "" then ("No properties match \"%s\""):format(self.Filter)
		else "No properties to show"
	self.Scroll:SetCanvasSize(Vector2.new(0, #rows * ROW))
	self:_render()
	self.Changed:Fire()
end

function PropView:_attributeDistinct(name: string): number
	local uniques = {}
	for _, instance in Properties.compared(self.Instances) do
		local ok, value = pcall(function()
			return instance:GetAttribute(name)
		end)
		if ok then
			local found = false
			for _, other in uniques do
				if Properties.equal(other, value) then
					found = true
					break
				end
			end
			if not found then
				table.insert(uniques, value)
			end
		end
	end
	return #uniques
end

function PropView:_attributeFieldValue(row, field): (any, boolean)
	local value, have, same = nil, false, true
	for _, instance in Properties.compared(self.Instances) do
		local ok, current = pcall(function()
			return instance:GetAttribute(row.Name)
		end)
		if ok and current ~= nil then
			local okGet, part = pcall(field.Get, current)
			if okGet then
				if not have then
					value, have = part, true
				elseif not Properties.equal(value, part) then
					same = false
				end
			end
		end
	end
	return value, same
end

-- The row with a key ("Anchored", "@Health", "Size.X", "#Data").
function PropView:Find(key: string)
	for index, row in self.Rows do
		if row.Key == key then
			return row, index
		end
	end
	return nil, nil
end

----------------------------------------------------------------------
-- Drawing
----------------------------------------------------------------------

function PropView:NameWidth(): number
	local width = self.Scroll:ViewSize().X
	if width <= 0 then
		width = 260
	end
	return math.clamp(math.floor(width * 0.45), 80, 220)
end

function PropView:_makeEntry(slot: number)
	local row = new("TextButton", {
		Name = "Row" .. slot,
		Size = UDim2.new(1, 0, 0, ROW),
		BackgroundTransparency = 1,
		Theme = { BackgroundColor3 = "SurfaceHover" },
		ZIndex = 2,
		Parent = self.Scroll.Instance,
	})
	local arrow = Icons.new("chevron_right", 11, "TextMuted")
	arrow.Name = "Arrow"
	arrow.AnchorPoint = Vector2.new(0.5, 0.5)
	arrow.ZIndex = 3
	arrow.Parent = row
	local name = new("TextLabel", {
		Name = "Name",
		Size = UDim2.new(0, 100, 1, 0),
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 3,
		Parent = row,
	})
	local divider = new("Frame", {
		Name = "Divider",
		Size = UDim2.new(0, 1, 1, 0),
		ZIndex = 3,
		Theme = { BackgroundColor3 = "Border" },
		Parent = row,
	})
	local swatch = new("Frame", {
		Name = "Swatch",
		AnchorPoint = Vector2.new(0, 0.5),
		Size = UDim2.fromOffset(SWATCH, SWATCH),
		ZIndex = 3,
		Visible = false,
		Parent = row,
	})
	Create.corner(swatch, 3)
	Create.stroke(swatch, "BorderStrong", 1, 0)
	local check = new("Frame", {
		Name = "Check",
		AnchorPoint = Vector2.new(0, 0.5),
		Size = UDim2.fromOffset(SWATCH, SWATCH),
		ZIndex = 3,
		Visible = false,
		Theme = { BackgroundColor3 = "Chrome" },
		Parent = row,
	})
	Create.corner(check, 3)
	local checkStroke = Create.stroke(check, "BorderStrong", 1, 0)
	local checkIcon = Icons.new("check", 11, "OnAccent")
	checkIcon.AnchorPoint = Vector2.new(0.5, 0.5)
	checkIcon.Position = UDim2.fromScale(0.5, 0.5)
	checkIcon.ZIndex = 4
	checkIcon.Parent = check
	local value = new("TextLabel", {
		Name = "Value",
		Size = UDim2.new(0, 100, 1, 0),
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 3,
		Parent = row,
	})
	local tail = Icons.new("chevron_down", 12, "TextMuted")
	tail.Name = "Tail"
	tail.AnchorPoint = Vector2.new(1, 0.5)
	tail.ZIndex = 3
	tail.Visible = false
	tail.Parent = row

	local entry = {
		Row = row,
		Arrow = arrow,
		Name = name,
		Divider = divider,
		Swatch = swatch,
		Check = check,
		CheckStroke = checkStroke,
		CheckIcon = checkIcon,
		Value = value,
		Tail = tail,
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
		local data = self.Rows[entry.Index]
		if not data then
			return
		end
		local kind = input.UserInputType
		local point = Overlay.pointOf(input)
		if kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch then
			self:_click(data, Create.toLocal(point, row).X)
		elseif kind == Enum.UserInputType.MouseButton2 then
			self.Selected = data.Key
			self:_repaint()
			self:OpenMenu(data, point)
		end
	end)
	return entry
end

function PropView:_paint(entry)
	local data = self.Rows[entry.Index]
	local hovered = entry.Index ~= 0 and self.Hover == entry.Index
	local selected = data ~= nil and data.Key == self.Selected
	if data and data.Kind == "category" then
		Theme.bind(entry.Row, "BackgroundColor3", if hovered then "SurfaceHover" else "Surface")
		entry.Row.BackgroundTransparency = 0
	elseif selected then
		Theme.bind(entry.Row, "BackgroundColor3", "Selection")
		entry.Row.BackgroundTransparency = if hovered then 0 else 0.25
	else
		Theme.bind(entry.Row, "BackgroundColor3", "SurfaceHover")
		entry.Row.BackgroundTransparency = if hovered then 0.4 else 1
	end
end

function PropView:_repaint()
	for _, entry in self.Entries do
		if entry.Index ~= 0 then
			self:_paint(entry)
		end
	end
end

-- Text a value row shows.
function PropView:ValueText(row): string
	if row.Readable == false then
		return "can't read"
	end
	if row.Same == false then
		if row.Distinct and row.Distinct > 1 then
			return ("— (%d%s values)"):format(row.Distinct, if row.Distinct >= MAX_DISTINCT then "+" else "")
		end
		return "—"
	end
	local editor = Editors.get(row.Prop)
	if editor.Display then
		local ok, text = pcall(editor.Display, row.Value, row.Prop)
		if ok and text ~= nil then
			return tostring(text)
		end
	end
	if row.Prop.Type == "boolean" and editor.Inline == "toggle" then
		return ""
	end
	return Properties.display(row.Value, row.Prop)
end

local function canEdit(row): boolean
	if row.Kind == "attribute" then
		return row.Prop.Editable == true
	end
	local prop = row.Prop
	return prop ~= nil and prop.Editable ~= false and not prop.ReadOnly and row.Readable ~= false
end
PropView.canEdit = canEdit

function PropView:_render()
	local scroll = self.Scroll
	local offset = scroll.Offset
	local view = scroll:ViewSize()
	local rows = self.Rows
	local first = math.max(1, math.floor(offset.Y / ROW) + 1)
	local count = math.ceil(math.max(view.Y, ROW) / ROW) + 1
	local width = math.max(view.X, 100)
	local nameWidth = self:NameWidth()
	self.EmptyLabel.Visible = #rows == 0 or (#self.Instances == 0)

	for slot = 1, math.max(count, #self.Entries) do
		local entry = self.Entries[slot]
		local index = first + slot - 1
		local data = rows[index]
		if slot > count or data == nil then
			if entry then
				entry.Row.Visible = false
				entry.Index = 0
			end
		else
			entry = entry or self:_makeEntry(slot)
			entry.Index = index
			local row = entry.Row
			row.Visible = true
			row.Position = UDim2.fromOffset(0, (index - 1) * ROW - offset.Y)
			row.Size = UDim2.new(0, width, 0, ROW)
			self:_draw(entry, data, width, nameWidth)
			self:_paint(entry)
		end
	end
end

function PropView:_draw(entry, data, width: number, nameWidth: number)
	local kind = data.Kind
	entry.Swatch.Visible = false
	entry.Check.Visible = false
	entry.Tail.Visible = false
	entry.Arrow.Visible = false
	entry.Divider.Visible = false
	entry.Value.Visible = false
	entry.Name.FontFace = Theme.Fonts.Regular

	if kind == "category" then
		entry.Arrow.Visible = true
		entry.Arrow.Position = UDim2.new(0, LEFT + ARROW / 2, 0.5, 0)
		entry.Arrow.Rotation = if data.Collapsed then 0 else 90
		entry.Name.Text = data.Name
		entry.Name.FontFace = Theme.Fonts.Medium
		entry.Name.Position = UDim2.fromOffset(LEFT + ARROW + 2, 0)
		entry.Name.Size = UDim2.new(0, width - LEFT - ARROW - 8, 1, 0)
		Theme.bind(entry.Name, "TextColor3", "TextDim")
		return
	end
	if kind == "add_attribute" or kind == "tag" then
		local x = LEFT + ARROW
		entry.Name.Text = if kind == "tag" then data.Name else "+  Add attribute…"
		entry.Name.Position = UDim2.fromOffset(x, 0)
		entry.Name.Size = UDim2.new(0, width - x - 8, 1, 0)
		Theme.bind(entry.Name, "TextColor3", if kind == "tag" then "Text" else "Accent")
		return
	end

	-- property / attribute / field
	local x = LEFT + (data.Depth or 0) * INDENT
	if data.Expandable then
		entry.Arrow.Visible = true
		entry.Arrow.Position = UDim2.new(0, x + ARROW / 2, 0.5, 0)
		entry.Arrow.Rotation = if self.Expanded[data.Key] then 90 else 0
	end
	x += ARROW
	local editable = canEdit(data)
	local prop = data.Prop
	entry.Name.Text = data.Name
	entry.Name.Position = UDim2.fromOffset(x, 0)
	entry.Name.Size = UDim2.new(0, math.max(10, nameWidth - x - 4), 1, 0)
	local nameColor = "Text"
	if prop and prop.Deprecated then
		nameColor = "TextDim"
	end
	if not editable then
		nameColor = "TextMuted"
	end
	Theme.bind(entry.Name, "TextColor3", nameColor)
	entry.Divider.Visible = true
	entry.Divider.Position = UDim2.fromOffset(nameWidth, 0)

	local valueX = nameWidth + VALUE_PAD
	local valueWidth = width - valueX - GUTTER
	local editor = Editors.get(prop)
	local inline = editor.Inline or "text"
	local same = data.Same ~= false and data.Readable ~= false

	if inline == "toggle" and same then
		entry.Check.Visible = true
		entry.Check.Position = UDim2.new(0, valueX, 0.5, 0)
		local on = data.Value == true
		Theme.bind(entry.Check, "BackgroundColor3", if on then "Accent" else "Chrome")
		Theme.bind(entry.CheckStroke, "Color", if on then "Accent" else "BorderStrong")
		entry.CheckIcon.Visible = on
		entry.Check.BackgroundTransparency = if editable then 0 else 0.5
		valueX += SWATCH + 6
		valueWidth -= SWATCH + 6
	elseif (inline == "swatch" or editor.Swatch) and same and data.Value ~= nil then
		local okColor, color = pcall(editor.Swatch or function(v)
			return v
		end, data.Value)
		if okColor and typeof(color) == "Color3" then
			entry.Swatch.Visible = true
			entry.Swatch.BackgroundColor3 = color
			entry.Swatch.Position = UDim2.new(0, valueX, 0.5, 0)
			valueX += SWATCH + 6
			valueWidth -= SWATCH + 6
		end
	end
	if (inline == "dropdown" or inline == "popup") and editable then
		entry.Tail.Visible = true
		entry.Tail.Position = UDim2.new(0, width - GUTTER - 2, 0.5, 0)
		Icons.set(entry.Tail, if inline == "dropdown" then "chevron_down" else "more")
		valueWidth -= 16
	end
	entry.Value.Visible = true
	entry.Value.Text = self:ValueText(data)
	entry.Value.Position = UDim2.fromOffset(valueX, 0)
	entry.Value.Size = UDim2.new(0, math.max(10, valueWidth), 1, 0)
	entry.Value.FontFace = if prop and (prop.Type == "string" or prop.Type == "boolean" or prop.Type == "EnumItem" or prop.Type == "Instance")
		then Theme.Fonts.Regular
		else Theme.Fonts.Mono
	Theme.bind(entry.Value, "TextColor3", if not same then "TextMuted" elseif editable then "Text" else "TextDim")
end

----------------------------------------------------------------------
-- Clicking and editing
----------------------------------------------------------------------

function PropView:_click(row, x: number)
	self.Selected = row.Key
	self:_repaint()
	if row.Kind == "category" then
		self:SetCollapsed(row.Name, not row.Collapsed)
		return
	end
	if row.Kind == "add_attribute" then
		self:AddAttribute()
		return
	end
	if row.Kind == "tag" then
		return
	end
	local nameWidth = self:NameWidth()
	local arrowLeft = LEFT + (row.Depth or 0) * INDENT
	if row.Expandable and x >= arrowLeft - 2 and x <= arrowLeft + ARROW + 2 then
		self:ToggleExpanded(row)
		return
	end
	if x < nameWidth then
		if row.Expandable and x < nameWidth then
			-- A click on the name of a composite value opens it too.
			self:ToggleExpanded(row)
		end
		return
	end
	self:Edit(row, x)
end

function PropView:ToggleExpanded(row)
	if not row.Expandable then
		return
	end
	self.Expanded[row.Key] = if self.Expanded[row.Key] then nil else true
	self:Rebuild()
end

-- Screen rectangle of a row's value cell.
function PropView:ValueRect(row): (Vector2?, Vector2?)
	local _, index = self:Find(row.Key)
	if not index then
		return nil, nil
	end
	self.Scroll:Reveal("Y", (index - 1) * ROW, index * ROW, 0, false)
	self:_render()
	-- worked out in layout pixels, returned on screen like AbsolutePosition
	local origin = self.Scroll.Instance.AbsolutePosition
	local factor = Create.scaleOf(self.Scroll.Instance)
	local nameWidth = self:NameWidth()
	local width = self.Scroll:ViewSize().X
	local y = (index - 1) * ROW - self.Scroll.Offset.Y
	return origin + Vector2.new(nameWidth + 2, y) * factor, Vector2.new(math.max(120, width - nameWidth - 4), ROW) * factor
end

local function failureText(failures: { any }): string
	local first = failures[1]
	local reason = tostring(first.Reason or "failed")
	if #failures > 1 then
		return ("%d objects: %s"):format(#failures, reason)
	end
	return reason
end

-- Writes a value for a row (all selected objects). true, or false + reason.
function PropView:Apply(row, value): (boolean, string?)
	local instances = self.Instances
	if #instances == 0 then
		return false, "nothing is selected"
	end
	local changed, failures
	if row.Kind == "attribute" then
		changed, failures = Properties.setAttribute(instances, row.Name, value)
	elseif row.Kind == "field" then
		local parent = row.Parent
		if parent.Kind == "attribute" then
			changed, failures = self:_setAttributeField(parent, row.Field, value)
		else
			changed, failures = Properties.setField(instances, parent.Prop, row.Field, value)
		end
	else
		changed, failures = Properties.set(instances, row.Prop, value)
	end
	if #failures > 0 then
		local text = failureText(failures)
		if self.Explorer then
			self.Explorer.report("error", ("couldn't set %s: %s"):format(row.Name, text))
		end
		self:Rebuild()
		if changed == 0 then
			return false, text
		end
	end
	self:Rebuild()
	return true, nil
end

function PropView:_setAttributeField(row, field, part): (number, { any })
	local changed, failures = 0, {}
	for _, instance in self.Instances do
		local ok, err = pcall(function()
			local current = instance:GetAttribute(row.Name)
			instance:SetAttribute(row.Name, field.Set(current, part))
		end)
		if ok then
			changed += 1
		else
			table.insert(failures, { Instance = instance, Reason = (tostring(err):gsub("^.-:%d+: ", "")) })
		end
	end
	return changed, failures
end

function PropView:_context(row, anchorPos: Vector2, anchorSize: Vector2)
	local explorer = self.Explorer
	return {
		View = self,
		Row = row,
		Prop = row.Prop,
		Value = row.Value,
		Same = row.Same ~= false,
		Instances = self.Instances,
		AnchorPos = anchorPos,
		AnchorSize = anchorSize,
		Origin = self.Origin,
		Owner = self,
		Apply = function(value)
			return self:Apply(row, value)
		end,
		Pick = function()
			if explorer and explorer.pick then
				explorer.pick(("set %s"):format(row.Name), function(instance)
					local className = row.Prop.ClassRef
					if className and className ~= "Instance" then
						local okIs, is = pcall(function()
							return instance:IsA(className)
						end)
						if not (okIs and is) then
							explorer.report("warn", ("%s needs a %s, not a %s"):format(row.Name, className, Types.classOf(instance) or "?"))
							return
						end
					end
					local applied, reason = self:Apply(row, instance)
					if applied then
						explorer.report("success", ("%s = %s"):format(row.Name, Types.path(instance)))
					elseif reason then
						explorer.report("warn", reason)
					end
				end)
			end
		end,
		Highlight = function(instance)
			if explorer then
				explorer.highlight(instance, { Flash = true })
			end
		end,
	}
end

--[[
	Edits a row's value with its editor. x: where the click landed in the
	row (nil: keyboard / menu, which opens the main editor).
]]
function PropView:Edit(row, x: number?)
	if not canEdit(row) then
		return nil
	end
	if self.Editing and not self.Editing.Closed then
		self.Editing:Close("replaced")
	end
	local anchorPos, anchorSize = self:ValueRect(row)
	if not anchorPos then
		return nil
	end
	local editor = Editors.get(row.Prop)
	local inline = editor.Inline or "text"
	local same = row.Same ~= false
	local ctx = self:_context(row, anchorPos, anchorSize)
	local valueX = self:NameWidth() + VALUE_PAD
	local width = self.Scroll:ViewSize().X

	local function open()
		-- Everything one popup changes (a color picker drag after drag,
		-- Cancel putting it back) is a single /undo step.
		local Undo = T.import("base/undo")
		local key = if row.Kind == "attribute" then Properties.undoKey("attr", row.Name, self.Instances) else Properties.undoKey("prop", row.Name, self.Instances)
		Undo.beginGroup(key)
		local ok, handle = pcall(editor.Open, ctx)
		if not ok then
			Undo.endGroup(key)
			T.import("console/reporter").ownerFault(editor.Owner, ("editor for %s"):format(row.Prop.Type), handle)
			return nil
		end
		if type(handle) == "table" and handle.Closed ~= true then
			local connection
			connection = Overlay.Closed:Connect(function(closed)
				if closed == handle then
					connection:Disconnect()
					Undo.endGroup(key)
				end
			end)
		else
			Undo.endGroup(key)
		end
		self.Editing = handle
		return handle
	end

	if inline == "toggle" then
		return self:Apply(row, if same then not (row.Value == true) else true)
	elseif inline == "dropdown" then
		local options = {}
		if editor.Options then
			local ok, list = pcall(editor.Options, ctx)
			if ok and type(list) == "table" then
				options = Dropdown.normalize(list)
			end
		end
		self.Editing = Dropdown.popup({
			Origin = self.Origin,
			Options = options,
			AnchorPos = anchorPos,
			AnchorSize = anchorSize,
			Width = anchorSize.X / Overlay.factor(), -- the anchor is on screen
			IsSelected = function(option)
				return same and Properties.equal(option.Value, row.Value)
			end,
			OnPick = function(option)
				self:Apply(row, option.Value)
			end,
			Owner = self,
		})
		return self.Editing
	elseif editor.Open then
		local onSwatch = x ~= nil and inline == "swatch" and x >= valueX - 2 and x <= valueX + SWATCH + 4
		local onTail = x ~= nil and inline == "popup" and x >= width - GUTTER - 22
		if x == nil or onSwatch or onTail or row.Prop.Type == "Instance" then
			return open()
		end
	end
	return self:EditText(row)
end

-- The text box editor for any row.
function PropView:EditText(row)
	if not canEdit(row) then
		return nil
	end
	local anchorPos, anchorSize = self:ValueRect(row)
	if not anchorPos then
		return nil
	end
	local text = if row.Same ~= false then Editors.editText(row.Prop, row.Value) else ""
	self.Editing = CellEditor.open({
		Origin = self.Origin,
		AnchorPos = anchorPos,
		AnchorSize = anchorSize,
		Text = text,
		Mono = row.Prop.Type ~= "string",
		Hint = false, -- nothing under the box (an error still shows there)
		Validate = function(input)
			return Editors.parse(row.Prop, input)
		end,
		OnCommit = function(value)
			return self:Apply(row, value)
		end,
		Owner = self,
	})
	return self.Editing
end

----------------------------------------------------------------------
-- Attributes
----------------------------------------------------------------------

function PropView:AddAttribute(point: Vector2?)
	if #self.Instances == 0 then
		return nil
	end
	local row, index = self:Find("+attribute")
	local anchorPos, anchorSize
	if row and index then
		self.Scroll:Reveal("Y", (index - 1) * ROW, index * ROW, 0, false)
		self:_render()
		local origin = self.Scroll.Instance.AbsolutePosition
		local factor = Create.scaleOf(self.Scroll.Instance)
		anchorPos = origin + Vector2.new(0, (index - 1) * ROW - self.Scroll.Offset.Y) * factor
		anchorSize = Vector2.new(self.Scroll:ViewSize().X, ROW) * factor
	else
		anchorPos, anchorSize = point or Overlay.mouse(), Vector2.new(0, 0)
	end
	self.Editing = T.import("base/explorer/attributeform").open({
		View = self,
		Origin = self.Origin,
		AnchorPos = anchorPos,
		AnchorSize = anchorSize,
		Owner = self,
	})
	return self.Editing
end

function PropView:RenameAttribute(row)
	local anchorPos, anchorSize = self:ValueRect(row)
	if not anchorPos then
		return nil
	end
	anchorPos = Vector2.new(self.Scroll.Instance.AbsolutePosition.X, anchorPos.Y)
	self.Editing = CellEditor.open({
		Origin = self.Origin,
		AnchorPos = anchorPos,
		AnchorSize = Vector2.new(self.Scroll:ViewSize().X, ROW),
		Text = row.Name,
		Mono = true,
		Hint = false,
		Validate = function(text)
			local ok, reason = Properties.validAttributeName(text)
			if not ok then
				return false, reason
			end
			return true, text
		end,
		OnCommit = function(name)
			local changed, failures = Properties.renameAttribute(self.Instances, row.Name, name)
			if #failures > 0 and changed == 0 then
				return false, failureText(failures)
			end
			if self.Expanded[row.Key] then
				self.Expanded[row.Key] = nil
				self.Expanded["@" .. name] = true
			end
			self:Rebuild()
			return true
		end,
		Owner = self,
	})
	return self.Editing
end

function PropView:RemoveAttribute(row)
	local changed, failures = Properties.removeAttribute(self.Instances, row.Name)
	if #failures > 0 and self.Explorer then
		self.Explorer.report("error", ("couldn't remove attribute %s: %s"):format(row.Name, failureText(failures)))
	end
	self:Rebuild()
	return changed
end

----------------------------------------------------------------------
-- Menu
----------------------------------------------------------------------

function PropView:MenuContext(row, point: Vector2?)
	return {
		View = self,
		Explorer = self.Explorer,
		Row = row,
		Kind = row.Kind,
		Name = row.Name,
		Prop = row.Prop,
		Value = row.Value,
		Same = row.Same ~= false,
		Instances = self.Instances,
		Count = #self.Instances,
		Attribute = row.Kind == "attribute",
		Field = if row.Kind == "field" then row.Field else nil,
		Tag = if row.Kind == "tag" then row.Name else nil,
		Point = point,
	}
end

function PropView:OpenMenu(row, point: Vector2?)
	if row.Kind == "category" then
		return nil
	end
	local ctx = self:MenuContext(row, point)
	self.Menu = Menus.open("explorer.property", ctx, { Position = point or Overlay.mouse() })
	return self.Menu
end

function PropView:Destroy()
	if self.Editing and not self.Editing.Closed then
		self.Editing:Close("destroyed")
	end
	self.Bin:Clean()
	self.Changed:DisconnectAll()
end

return PropView
