--[[
	Script Viewer · lib/view
	The plugin's tab: a toolbar naming what is shown, then sub-tabs:
	Source first (the decompiled script, read-only), then Constants,
	Upvalues, Functions and Contents (a loaded table, or what a required
	ModuleScript returns). The toolbar names what is shown and what kind
	of thing it is (hover it for notes). Each data sub-tab has views,
	kept in the plugin's settings:
		Tree    explore and change in place: rows open into tables,
		        functions and upvalues
		List    find things: every row flat with its full path, a search
		        box (key, path or value text) and a type filter
		Table   bulk changes and copying: the rows as a Luau table,
		        editable, Apply / Revert
	Constants and Upvalues also have a scope: "This function", or "With
	nested functions" (every nested function's constants; the upvalues of
	the running copies of nested functions), each under a heading.
	A sub-tab's work area scrolls when the window is small, so the list
	keeps a useful height. References (a toggle on the toolbar) shows,
	under the list, the other functions that use the selected constant or
	hold the selected upvalue; double-click one to load it.
	Editing: right-click a row for the "scriptviewer.row" menu; double-
	click a row that doesn't open to change it; the Table view can be
	edited and applied.

	Switching views never runs inside the dropdown: the work is deferred
	and guarded, a newer switch wins, and a failure says why in the bar.

		local view = View.new(page, api, inspect)
		view:Show(subject)        -- what to show (from Inspect.subject)
		view:Select("source")     -- open a sub-tab
		view:SetMode(id, mode)    -- Tree / List / Table (saved)
		view:SetScope(id, scope)  -- "This function" / "With nested functions" (saved)
		view:Opened()             -- the plugin's tab was opened (decompiles if waiting)
		view.Subject ; view.Tabs ; view.Destroyed
]]

local P = ...

local Rows = P.import("lib/rows")
local Source = P.import("lib/source")
local Serialize = P.import("lib/serialize")
local Refs = P.import("lib/refs")
local Actions = P.import("lib/actions")
local Edit = P.import("lib/edit")

local View = {}
View.__index = View
-- the editing modules, for other plugins and the tests: view.Edit, view.Actions
View.Edit = Edit
View.Actions = Actions

-- Sub-tabs in order.
View.Panels = {
	{ Id = "source", Title = "Source", Icon = "console" },
	{ Id = "constants", Title = "Constants", Icon = "type_number", Data = true, Setting = "constantsView", Modes = { "Tree", "List", "Table" }, Refs = true, Scope = "constantsScope" },
	{ Id = "upvalues", Title = "Upvalues", Icon = "variable", Data = true, Setting = "upvaluesView", Modes = { "Tree", "List", "Table" }, Refs = true, Scope = "upvaluesScope" },
	{ Id = "functions", Title = "Functions", Icon = "type_function", Data = true, Setting = "functionsView", Modes = { "Tree", "List", "Table" } },
	{ Id = "contents", Title = "Contents", Icon = "type_table", Data = true, Setting = "contentsView", Modes = { "Tree", "List", "Table" }, Refs = true },
}
View.Modes = { "Tree", "List", "Table" }
View.Scopes = { "This function", "With nested functions" }
-- the List view's type filter
View.TypeFilters = { "Any type", "string", "number", "boolean", "table", "function", "Instance", "other" }
local KNOWN_TYPES = { string = true, number = true, boolean = true, table = true, ["function"] = true, Instance = true }
local PANEL = {}
for _, def in View.Panels do
	PANEL[def.Id] = def
end

-- The work area is at least this tall; in a smaller window it scrolls.
View.ListMin = 420 -- the list's least height
View.RefsHeight = 210 -- the References area, when shown
local FILTER_ROW = 28
local PAD = 8

-- Name column: indented by depth, with ▸ / ▾ on things that open.
local function treeName(node): string
	local arrow = if node.Expandable then (if node.Expanded then "▾ " else "▸ ") else "   "
	return string.rep("    ", node.Depth) .. arrow .. node.Key
end

local VALUE_COLUMNS = {
	Tree = {
		{ Key = "Name", Title = "Name", Width = 220, Get = treeName },
		{ Key = "Type", Title = "Type", Width = 110, Type = "valueType" },
		{ Key = "ValueText", Title = "Value", Flex = true, Min = 160, Mono = true },
	},
	List = {
		{ Key = "Path", Title = "Path", Width = 300, Mono = true },
		{ Key = "Type", Title = "Type", Width = 110, Type = "valueType" },
		{ Key = "ValueText", Title = "Value", Flex = true, Min = 160, Mono = true },
	},
}
local FUNCTION_COLUMNS = {
	Tree = {
		{ Key = "Name", Title = "Function", Flex = true, Min = 200, Get = treeName },
		{ Key = "Params", Title = "Params", Width = 70 },
		{ Key = "Upvalues", Title = "Upvalues", Width = 80 },
		{ Key = "Constants", Title = "Constants", Width = 85 },
		{ Key = "Nested", Title = "Nested", Width = 70 },
	},
	List = {
		{ Key = "Path", Title = "Path", Width = 90, Mono = true },
		{ Key = "Key", Title = "Function", Flex = true, Min = 180 },
		{ Key = "Params", Title = "Params", Width = 70 },
		{ Key = "Upvalues", Title = "Upvalues", Width = 80 },
		{ Key = "Constants", Title = "Constants", Width = 85 },
		{ Key = "Nested", Title = "Nested", Width = 70 },
	},
}

local KIND_TEXT = {
	script = "script",
	module = "ModuleScript",
	["function"] = "function",
	table = "table",
	value = "nothing to inspect",
	none = "",
}

function View.new(page: Frame, api, inspect)
	local self = setmetatable({}, View)
	self.Api = api
	self.Inspect = inspect
	self.Subject = nil
	self.Panels = {} -- id -> { Holder, Body }

	local layout = api.ui.page({ Parent = page, Toolbar = true })
	self.Page = layout
	self.TitleLabel = api.ui.new("Label", { Parent = layout.Toolbar, Name = "Title", Text = "Nothing loaded", Style = "title", Size = UDim2.new(0, 0, 1, 0) })
	self.TitleLabel.AutomaticSize = Enum.AutomaticSize.X
	self.TitleLabel.LayoutOrder = 1
	self.Kind = api.ui.new("Label", { Parent = layout.Toolbar, Name = "Kind", Text = "", Style = "dim", Size = UDim2.new(0, 0, 1, 0) })
	self.Kind.AutomaticSize = Enum.AutomaticSize.X
	self.Kind.LayoutOrder = 2
	-- hovering the kind shows the notes about what is shown
	pcall(api.tooltip.attach, self.Kind, function()
		return self.NotesText or "no notes"
	end)

	-- the strip first, then its sub-tabs: a sub-tab is built when it first
	-- opens, and building needs self.Tabs (Source, the first, opens at once)
	self.Tabs = api.ui.subtabs({ Parent = layout.Body, Tabs = {} })
	for _, def in View.Panels do
		self.Tabs:Add({
			Id = def.Id,
			Title = def.Title,
			Icon = def.Icon,
			Build = function(holder)
				self:_buildPanel(def.Id, holder)
			end,
		})
	end
	self.Tabs:Select(View.Panels[1].Id)
	return self
end

function View:_buildPanel(id: string, holder: Frame)
	if PANEL[id].Data then
		self:_buildDataPanel(id, holder)
		return
	end
	self:_buildSource(holder)
end

local function setting(api, key: string): any
	local ok, value = pcall(api.settings.get, key)
	return if ok then value else nil
end

-- The view a data panel uses, from the plugin's settings (Tree when the
-- setting holds a view this panel doesn't have, e.g. an old "Function").
function View:_mode(id: string): string
	local value = setting(self.Api, PANEL[id].Setting)
	return if table.find(PANEL[id].Modes, value) then value else "Tree"
end

-- The scope of Constants / Upvalues, from the plugin's settings.
function View:_scope(id: string): string
	local key = PANEL[id].Scope
	local value = if key then setting(self.Api, key) else nil
	return if table.find(View.Scopes, value) then value else View.Scopes[1]
end

local function nested(panel): boolean
	return panel.Scope == View.Scopes[2]
end

-- A data panel: a toolbar over a work area that scrolls when the window is
-- small. The work area holds the List view's filter row, the list (or the
-- Table view's text) and the References area when it is on.
function View:_buildDataPanel(id: string, holder: Frame)
	local api = self.Api
	local def = PANEL[id]
	local layout = api.ui.page({ Parent = holder, Toolbar = true, Name = "Panel_" .. id })
	local panel = {
		Holder = holder, Page = layout, Body = layout.Body, Data = true, Expanded = {}, Closed = {},
		Mode = self:_mode(id), Scope = self:_scope(id), Token = 0, Search = "", TypeFilter = View.TypeFilters[1],
	}
	self.Panels[id] = panel
	local order = 0
	local function nextOrder(): number
		order += 1
		return order
	end
	panel.Switch = api.ui.new("Dropdown", {
		Parent = layout.Toolbar,
		Name = "View",
		Width = 90,
		Options = def.Modes,
		Value = panel.Mode,
		OnChanged = function(value)
			self:SetMode(id, value)
		end,
	})
	panel.Switch.Instance.LayoutOrder = nextOrder()
	if def.Scope then
		panel.ScopeSwitch = api.ui.new("Dropdown", {
			Parent = layout.Toolbar,
			Name = "Scope",
			Width = 170,
			Options = View.Scopes,
			Value = panel.Scope,
			OnChanged = function(value)
				self:SetScope(id, value)
			end,
		})
		panel.ScopeSwitch.Instance.LayoutOrder = nextOrder()
	end
	-- Table view: write the edited text back, or put it back as it is
	panel.Apply = api.ui.new("Button", {
		Parent = layout.Toolbar,
		Name = "Apply",
		Text = "Apply",
		Icon = "check",
		Style = "accent",
		OnClick = function()
			Actions.applyText(self, id)
		end,
	})
	panel.Apply.Instance.LayoutOrder = nextOrder()
	panel.Revert = api.ui.new("Button", {
		Parent = layout.Toolbar,
		Name = "Revert",
		Text = "Revert",
		Icon = "refresh",
		Style = "ghost",
		OnClick = function()
			self:_render(id)
		end,
	})
	panel.Revert.Instance.LayoutOrder = nextOrder()
	if id == "contents" then
		panel.Add = api.ui.new("Button", {
			Parent = layout.Toolbar,
			Name = "Add",
			Text = "Add entry",
			Icon = "add",
			Style = "ghost",
			OnClick = function()
				local subject = self.Subject
				if subject and type(subject.Table) == "table" then
					Actions.addEntry(self, id, subject.Table, "the table")
				end
			end,
		})
		panel.Add.Instance.LayoutOrder = nextOrder()
	end
	if def.Refs then
		panel.RefsToggle = api.ui.new("Toggle", {
			Parent = layout.Toolbar,
			Name = "References",
			Text = "References",
			Value = setting(api, "showReferences") == true,
			OnChanged = function(on)
				pcall(api.settings.set, "showReferences", on == true)
			end,
		})
		panel.RefsToggle.Instance.LayoutOrder = nextOrder()
	end
	panel.Info = api.ui.new("Label", { Parent = layout.Toolbar, Name = "Info", Text = "", Style = "muted", Size = UDim2.new(1, -130, 1, 0) })
	panel.Info.LayoutOrder = nextOrder()
	panel.Info.TextTruncate = Enum.TextTruncate.AtEnd
	-- hovering the bar shows all of it
	pcall(api.tooltip.attach, panel.Info, function()
		return panel.InfoFull or panel.Info.Text
	end)

	-- the work area
	panel.Scroll = api.ui.new("Scroll", { Parent = layout.Body, Name = "Work", Direction = "Y" })
	local canvas = Instance.new("Frame")
	canvas.Name = "Canvas"
	canvas.BackgroundTransparency = 1
	canvas.Size = UDim2.new(1, 0, 0, View.ListMin)
	canvas.Parent = panel.Scroll.Content
	panel.Canvas = canvas
	-- the List view's filter row: search, type, count
	local filterRow = Instance.new("Frame")
	filterRow.Name = "Filter"
	filterRow.BackgroundTransparency = 1
	filterRow.Position = UDim2.fromOffset(12, PAD)
	filterRow.Size = UDim2.new(1, -24, 0, FILTER_ROW)
	filterRow.Parent = canvas
	panel.FilterRow = filterRow
	local filterLayout = Instance.new("UIListLayout")
	filterLayout.FillDirection = Enum.FillDirection.Horizontal
	filterLayout.SortOrder = Enum.SortOrder.LayoutOrder
	filterLayout.Padding = UDim.new(0, 6)
	filterLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	filterLayout.Parent = filterRow
	panel.SearchBox = api.ui.new("Input", {
		Parent = filterRow,
		Name = "Search",
		Width = 240,
		Placeholder = "Search keys, paths and values",
		Text = "",
		OnTyping = function(text)
			panel.Search = tostring(text or "")
			if panel.Mode == "List" then
				self:_render(id)
			end
		end,
	})
	panel.SearchBox.Instance.LayoutOrder = 1
	panel.TypeSwitch = api.ui.new("Dropdown", {
		Parent = filterRow,
		Name = "Type",
		Width = 120,
		Options = View.TypeFilters,
		Value = panel.TypeFilter,
		OnChanged = function(value)
			panel.TypeFilter = value
			if panel.Mode == "List" then
				self:_render(id)
			end
		end,
	})
	panel.TypeSwitch.Instance.LayoutOrder = 2
	panel.Count = api.ui.new("Label", { Parent = filterRow, Name = "Count", Text = "", Style = "muted", Size = UDim2.new(0, 200, 1, 0) })
	panel.Count.LayoutOrder = 3

	local holderFrame = Instance.new("Frame")
	holderFrame.Name = "ListHolder"
	holderFrame.BackgroundTransparency = 1
	holderFrame.Parent = canvas
	panel.ListHolder = holderFrame
	if def.Refs then
		self:_buildRefs(id, canvas)
	end
	-- the Table view: the rows written as a Luau table
	panel.Text = api.ui.new("TextEditor", {
		Parent = canvas,
		Name = "TableText",
		ReadOnly = true,
		Text = "",
	})
	api.connect(layout.Body:GetPropertyChangedSignal("AbsoluteSize"), function()
		if not self.Destroyed then
			self:_layout(id)
		end
	end)
	self:_makeList(id)
	-- a setting changed (here, or on the plugin's page)
	api.connect(api.settings.Changed, function(key)
		if self.Destroyed then
			return
		end
		if key == def.Setting then
			local mode = self:_mode(id)
			if mode ~= panel.Mode then
				self:SetMode(id, mode)
			end
		elseif key == def.Scope then
			local scope = self:_scope(id)
			if scope ~= panel.Scope then
				self:SetScope(id, scope)
			end
		elseif key == "showReferences" and def.Refs then
			local on = setting(api, "showReferences") == true
			if panel.RefsToggle.Value ~= on then
				panel.RefsToggle:Set(on)
			end
			self:_layout(id)
			if on then
				self:FindReferences(id, panel.List and panel.List:GetSelected()[1] or nil)
			end
		end
	end)
	self:_fill(id)
end

-- Is the References area shown for a panel?
function View:_refsOn(id: string): boolean
	local panel = self.Panels[id]
	return panel ~= nil and panel.RefsFrame ~= nil and panel.Mode ~= "Table" and setting(self.Api, "showReferences") == true
end

-- Places the work area's parts: the filter row (List view), the list or
-- the text, and References. The work area is the body's height, or more
-- (then it scrolls) so the list keeps View.ListMin.
function View:_layout(id: string)
	local panel = self.Panels[id]
	if not panel or not panel.Canvas then
		return
	end
	local listMode = panel.Mode == "List"
	local refs = self:_refsOn(id)
	local top = PAD + (if listMode then FILTER_ROW + 6 else 0)
	local bottom = PAD + (if refs then View.RefsHeight + PAD else 0)
	local bodyHeight = panel.Body.AbsoluteSize.Y
	local height = math.max(bodyHeight, top + View.ListMin + bottom)
	panel.Canvas.Size = UDim2.new(1, 0, 0, height)
	panel.FilterRow.Visible = listMode
	local listHeight = height - top - bottom
	panel.ListHolder.Position = UDim2.fromOffset(12, top)
	panel.ListHolder.Size = UDim2.new(1, -24, 0, listHeight)
	panel.Text.Instance.Position = UDim2.fromOffset(12, PAD)
	panel.Text.Instance.Size = UDim2.new(1, -24, 0, height - PAD * 2)
	if panel.RefsFrame then
		panel.RefsFrame.Visible = refs
		panel.RefsFrame.Position = UDim2.new(0, 12, 0, height - View.RefsHeight - PAD)
		panel.RefsFrame.Size = UDim2.new(1, -24, 0, View.RefsHeight)
	end
end

function View:_makeList(id: string)
	local api = self.Api
	local panel = self.Panels[id]
	if panel.List then
		panel.List:Destroy()
	end
	local listMode = if panel.Mode == "List" then "List" else "Tree"
	local columns = if id == "functions" then FUNCTION_COLUMNS[listMode] else VALUE_COLUMNS[listMode]
	if id == "contents" and listMode == "Tree" then
		columns = table.clone(columns)
		columns[1] = table.clone(columns[1])
		columns[1].Title = "Key"
	end
	-- the list shows in Tree / List, the text in Table
	panel.ListHolder.Visible = panel.Mode ~= "Table"
	panel.Text.Instance.Visible = panel.Mode == "Table"
	panel.Apply.Instance.Visible = panel.Mode == "Table" and id ~= "functions"
	panel.Revert.Instance.Visible = panel.Mode == "Table" and id ~= "functions"
	if panel.Add then
		panel.Add.Instance.Visible = panel.Mode ~= "Table"
	end
	if panel.RefsToggle then
		panel.RefsToggle.Instance.Visible = panel.Mode ~= "Table"
	end
	local used = 100 + (if panel.ScopeSwitch then 180 else 0) + (if panel.Mode == "Table" and id ~= "functions" then 180 elseif panel.Add then 110 else 0) + (if panel.RefsToggle and panel.Mode ~= "Table" then 120 else 0)
	panel.Info.Size = UDim2.new(1, -used, 1, 0)
	self:_layout(id)

	panel.List = api.ui.new("List", {
		Parent = panel.ListHolder,
		Name = "Rows",
		Columns = columns,
		EmptyText = "Nothing here",
		-- right-click: change, remove, add, rename, use (lib/actions)
		Menu = "scriptviewer.row",
		MenuContext = function(ctx)
			ctx.Panel = id
			ctx.View = self
		end,
		OnActivate = function(node)
			if type(node) ~= "table" then
				return
			end
			if panel.Mode == "Tree" and node.Expandable then
				self:Toggle(id, node.Id)
			elseif Edit.kindOf(node) and not node.Expandable then
				-- a row that doesn't open: double-click changes it
				Actions.editValue(self, id, node)
			end
		end,
	})
	if panel.RefsFrame then
		self.Api.connect(panel.List.SelectionChanged, function(selected)
			self:FindReferences(id, selected[1])
		end)
		self:FindReferences(id, nil)
	end
end

-- Runs a panel's rebuild after the current event (never inside a dropdown
-- callback), guarded: a newer request wins, a failure says why in the bar.
function View:_schedule(id: string, rebuildList: boolean)
	local panel = self.Panels[id]
	if not panel then
		return
	end
	panel.Token += 1
	local token = panel.Token
	panel.Info.Text = "…"
	task.defer(function()
		if self.Destroyed or panel.Token ~= token then
			return
		end
		local ok, err = pcall(function()
			if rebuildList then
				self:_makeList(id)
			end
			self:_fill(id)
		end)
		if not ok then
			local text = ("couldn't show the %s view: %s"):format(panel.Mode, tostring(err))
			panel.Info.Text = text
			panel.InfoFull = text
			pcall(self.Api.console.error, text)
		end
	end)
end

-- Switches a data panel's view (Tree / List / Table) and saves it.
function View:SetMode(id: string, mode: string)
	local panel = self.Panels[id]
	if not panel then
		return
	end
	if not table.find(PANEL[id].Modes, mode) then
		mode = "Tree"
	end
	panel.Mode = mode
	if panel.Switch:GetValue() ~= mode then
		panel.Switch:SetValue(mode, true)
	end
	if setting(self.Api, PANEL[id].Setting) ~= mode then
		pcall(self.Api.settings.set, PANEL[id].Setting, mode)
	end
	self:_schedule(id, true)
end

-- Switches Constants / Upvalues between this function and with its nested
-- functions, and saves it.
function View:SetScope(id: string, scope: string)
	local panel = self.Panels[id]
	if not panel or not PANEL[id].Scope then
		return
	end
	if not table.find(View.Scopes, scope) then
		scope = View.Scopes[1]
	end
	panel.Scope = scope
	if panel.ScopeSwitch:GetValue() ~= scope then
		panel.ScopeSwitch:SetValue(scope, true)
	end
	if setting(self.Api, PANEL[id].Scope) ~= scope then
		pcall(self.Api.settings.set, PANEL[id].Scope, scope)
	end
	table.clear(panel.Expanded)
	table.clear(panel.Closed)
	self:_schedule(id, false)
end

----------------------------------------------------------------------
-- References
----------------------------------------------------------------------

function View:_buildRefs(id: string, parent: Instance)
	local api = self.Api
	local panel = self.Panels[id]
	local frame = Instance.new("Frame")
	frame.Name = "References"
	frame.BackgroundTransparency = 1
	frame.Size = UDim2.new(1, -24, 0, View.RefsHeight)
	frame.Parent = parent
	panel.RefsFrame = frame
	panel.RefsToken = 0
	panel.RefsInfo = api.ui.new("Label", { Parent = frame, Name = "Info", Text = "", Style = "muted", Size = UDim2.new(1, 0, 0, 20) })
	panel.RefsInfo.TextTruncate = Enum.TextTruncate.AtEnd
	local listFrame = Instance.new("Frame")
	listFrame.Name = "ListHolder"
	listFrame.BackgroundTransparency = 1
	listFrame.Position = UDim2.fromOffset(0, 22)
	listFrame.Size = UDim2.new(1, 0, 1, -22)
	listFrame.Parent = frame
	panel.RefsList = api.ui.new("List", {
		Parent = listFrame,
		Name = "RefsList",
		Columns = {
			{ Key = "Name", Title = "Function", Width = 180 },
			{ Key = "Match", Title = "Where", Width = 100 },
			{ Key = "Place", Title = "Source", Flex = true, Min = 160, Mono = true },
		},
		EmptyText = "No other functions",
		OnActivate = function(result)
			if type(result) == "table" and result.Fn then
				self:OpenReference(result)
			end
		end,
	})
end

-- Loads a function found as a reference, so the viewer inspects it.
function View:OpenReference(result)
	local api = self.Api
	api.loaded.set(api.loaded.target(result.Fn, { Label = ("function %s"):format(result.Name) }))
end

-- Searches the references of a row (in a thread; a newer selection wins).
-- Nothing is searched while References is off.
function View:FindReferences(id: string, node: any)
	local panel = self.Panels[id]
	if not panel or not panel.RefsFrame then
		return
	end
	panel.RefsToken += 1
	local token = panel.RefsToken
	panel.RefsList:SetItems({})
	panel.RefsNode = node
	if setting(self.Api, "showReferences") ~= true then
		panel.RefsInfo.Text = "References: off"
		panel.RefsResults = nil
		return
	end
	local ok, why = Refs.canSearch(node)
	if not ok then
		panel.RefsInfo.Text = "References: " .. tostring(why)
		panel.RefsResults = nil
		return
	end
	panel.RefsInfo.Text = ("References of %s: searching…"):format(node.Path)
	self.Api.spawn(function()
		local found, results, capped = Refs.find(node, { Self = node.Owner })
		if self.Destroyed or panel.RefsToken ~= token then
			return -- another row was selected meanwhile
		end
		if not found then
			panel.RefsInfo.Text = "References: " .. tostring(results)
			panel.RefsResults = nil
			return
		end
		for _, result in results do
			result.Place = result.Source .. (if result.Line then ":" .. result.Line else "")
			if result.Self then
				result.Name ..= " (this one)"
			end
		end
		panel.RefsResults = results
		panel.RefsList:SetItems(results)
		local others = 0
		for _, result in results do
			if not result.Self then
				others += 1
			end
		end
		panel.RefsInfo.Text = ("References of %s: %d other %s%s"):format(node.Path, others, if others == 1 then "function" else "functions", if capped then (" (first %d)"):format(Refs.Limit) else "")
	end)
end

-- Opens or closes a row in a Tree view (by its node Id).
function View:Toggle(id: string, nodeId: string)
	local panel = self.Panels[id]
	if not panel or not panel.Data then
		return
	end
	if panel.Headings and panel.Headings[nodeId] then
		-- function headings start open; this closes or opens one
		panel.Closed[nodeId] = not panel.Closed[nodeId] or nil
	else
		panel.Expanded[nodeId] = not panel.Expanded[nodeId] or nil
	end
	self:_render(id)
end

local function showEmptySlots(api): boolean
	return setting(api, "showEmpty") == true
end

-- The root rows of a data panel for the subject (and why there are none).
function View:_roots(id: string): ({ any }, string?)
	local subject = self.Subject
	local panel = self.Panels[id]
	local wide = panel ~= nil and nested(panel) or (panel == nil and PANEL[id].Scope ~= nil and self:_scope(id) == View.Scopes[2])
	if subject == nil or subject.Kind == "none" then
		return {}, "nothing loaded"
	end
	if id == "contents" then
		if subject.Table ~= nil then
			return Rows.entries(subject.Table)
		end
		if subject.Kind == "module" then
			return {}, if subject.Returned ~= nil then ("it returns a %s, not a table"):format(typeof(subject.Returned)) else "the game hasn't required it yet, so its table isn't shown"
		end
		return {}, "load a table, or a ModuleScript the game has required"
	end
	if id == "upvalues" and (subject.Kind == "script" or subject.Kind == "module") then
		-- a script's main function here is a fresh copy with no running
		-- upvalues: its running functions hold them (nested ones included)
		local live, why = Rows.liveFunctions(subject)
		if not live then
			return {}, why
		end
		return Rows.upvaluesOfFunctions(live)
	end
	local fn = subject.Fn
	if fn == nil then
		return {}, if subject.Kind == "table" then "a table has no " .. id .. " (its entries are in the Contents sub-tab)" else "this has no function to inspect"
	end
	if id == "constants" then
		if wide then
			return Rows.constantsByFunction(fn, { ShowEmpty = showEmptySlots(self.Api) })
		end
		return Rows.constants(fn, { ShowEmpty = showEmptySlots(self.Api) })
	elseif id == "upvalues" then
		if wide then
			return Rows.upvaluesWithNested(fn)
		end
		return Rows.upvalues(fn)
	end
	return Rows.functions(fn)
end

----------------------------------------------------------------------
-- Source
----------------------------------------------------------------------

function View:_buildSource(holder: Frame)
	local api = self.Api
	local layout = api.ui.page({ Parent = holder, Toolbar = true, Name = "Panel_source" })
	local panel = { Holder = holder, Page = layout, Body = layout.Body, Source = true, Token = 0 }
	self.Panels.source = panel
	panel.Copy = api.ui.new("Button", {
		Parent = layout.Toolbar,
		Name = "Copy",
		Text = "Copy",
		Icon = "copy",
		OnClick = function()
			self:CopySource()
		end,
	})
	panel.Again = api.ui.new("Button", {
		Parent = layout.Toolbar,
		Name = "Again",
		Text = "Decompile again",
		Icon = "refresh",
		Style = "ghost",
		OnClick = function()
			Source.forget()
			self:_fill("source")
		end,
	})
	panel.Copy.Instance.LayoutOrder = 1
	panel.Again.Instance.LayoutOrder = 2
	panel.Info = api.ui.new("Label", { Parent = layout.Toolbar, Name = "Info", Text = "", Style = "muted", Size = UDim2.new(1, -260, 1, 0) })
	panel.Info.LayoutOrder = 3
	panel.Info.TextTruncate = Enum.TextTruncate.AtEnd
	panel.Editor = api.ui.new("TextEditor", {
		Parent = layout.Body,
		Name = "Code",
		Position = UDim2.fromOffset(12, 8),
		Size = UDim2.new(1, -24, 1, -16),
		ReadOnly = true,
		Text = "",
	})
	panel.Status = api.ui.new("Label", {
		Parent = layout.Body,
		Name = "Status",
		Text = "",
		Style = "dim",
		Position = UDim2.fromOffset(20, 16),
		Size = UDim2.new(1, -40, 0, 40),
	})
	-- decompiling waits until the sub-tab is looked at
	api.connect(self.Tabs.Changed, function(tabId)
		if tabId == "source" and panel.Pending and not self.Destroyed then
			self:_fill("source")
		end
	end)
	self:_fill("source")
end

local function setStatus(panel, text: string?)
	panel.Status.Text = text or ""
	panel.Status.Visible = text ~= nil
	panel.Editor.Instance.Visible = text == nil
	panel.Copy:SetEnabled(text == nil)
end

function View:_fillSource()
	local panel = self.Panels.source
	panel.Token += 1
	local token = panel.Token
	local script, note = Source.scriptFor(self.Subject)
	panel.Script = script
	if not script then
		panel.Pending = false
		panel.Editor:SetText("", true)
		panel.Info.Text = ""
		setStatus(panel, note or "no source")
		return
	end
	panel.Info.Text = note or ""
	local known = Source.cached(script)
	if known then
		panel.Pending = false
		panel.Editor:SetText(known, true)
		setStatus(panel, nil)
		return
	end
	if self.Tabs.Selected ~= "source" or not self.Api.tab.isOpen() then
		panel.Pending = true -- decompiled when the sub-tab (and the tab) open
		setStatus(panel, "decompiles when you open this sub-tab")
		return
	end
	panel.Pending = false
	setStatus(panel, "Decompiling…")
	self.Api.spawn(function()
		local ok, text = Source.get(script)
		if self.Destroyed or panel.Token ~= token then
			return -- something else was loaded meanwhile
		end
		if ok then
			panel.Editor:SetText(text, true)
			setStatus(panel, nil)
		else
			panel.Editor:SetText("", true)
			setStatus(panel, text)
		end
	end)
end

-- Copies the whole decompiled source.
function View:CopySource(): boolean
	local panel = self.Panels.source
	if not panel or panel.Status.Visible then
		return false
	end
	local text = panel.Editor:GetText()
	local ok = pcall(setclipboard, text)
	if ok then
		self.Api.console.success(("copied the source of %s (%d lines)"):format(if panel.Script then panel.Script.Name else "?", select(2, text:gsub("\n", "")) + 1))
	else
		self.Api.console.error("couldn't copy: the clipboard isn't available")
	end
	return ok
end

-- The Table view: the panel's data written as a Luau table. Rows under
-- function headings (a scope with nested functions, a script's running
-- functions) are written by function and can't be applied back.
function View:_renderText(id: string)
	local panel = self.Panels[id]
	local subject = self.Subject
	local headings = panel.Roots and panel.Roots[1] and panel.Roots[1].Kind == "heading"
	local text, capped
	if panel.Why then
		text = "-- " .. panel.Why
	else
		local value, why
		if headings then
			value = {}
			for _, heading in panel.Roots do
				local rows = {}
				for _, node in Rows.childrenOf(heading) do
					if node.Index ~= nil then
						rows[node.Index] = node.Value
					end
				end
				value[(heading.Key:gsub("%s+", " "))] = rows
			end
		else
			value, why = Rows.plain(id, if id == "contents" then subject.Table else subject.Fn)
		end
		if value == nil then
			text = "-- " .. tostring(why or "nothing to write")
		else
			local ok, written, wasCapped = pcall(Serialize.write, value)
			text = if ok then written else "-- couldn't write it: " .. tostring(written)
			capped = ok and wasCapped
		end
	end
	if capped then
		text = ("-- long: tables past the first %d entries are KEEP (kept as they are)\n"):format(Serialize.MaxTotal) .. text
	end
	panel.Text:SetText(text, true)
	-- editable where it can be written back: not Functions, not rows by
	-- function, not when there is nothing to write
	local editable = id ~= "functions" and not panel.Why and not headings and (capped or text:sub(1, 3) ~= "-- ")
	panel.Text:SetReadOnly(not editable)
	panel.Apply:SetEnabled(editable)
	panel.Revert:SetEnabled(editable)
	panel.List:SetItems({})
	return text
end

-- Does a row pass the List view's search and type filter?
local function passes(node, needle: string, typeFilter: string): boolean
	if typeFilter ~= View.TypeFilters[1] then
		local kind = node.Type
		if typeFilter == "other" then
			if KNOWN_TYPES[kind] then
				return false
			end
		elseif kind ~= typeFilter then
			return false
		end
	end
	if needle == "" then
		return true
	end
	for _, field in { node.Key, node.Path, node.ValueText } do
		if type(field) == "string" and field:lower():find(needle, 1, true) then
			return true
		end
	end
	return false
end

-- Rows for a data panel (Tree, List or Table view).
function View:_render(id: string)
	local panel = self.Panels[id]
	local roots = panel.Roots or {}
	local rows, capped
	panel.Headings = nil
	local headings = {}
	for _, node in roots do
		if node.Kind == "heading" then
			headings[node.Id] = true
		end
	end
	local hasHeadings = next(headings) ~= nil
	if panel.Mode == "Table" then
		self:_renderText(id)
		rows, capped = {}, false
	elseif panel.Mode == "List" then
		rows, capped = Rows.flat(roots)
	elseif hasHeadings then
		-- function headings start open
		panel.Headings = headings
		rows = Rows.tree(roots, function(node)
			if headings[node.Id] then
				return not panel.Closed[node.Id]
			end
			return panel.Expanded[node.Id] == true
		end)
		capped = #rows >= Rows.MaxRows
	else
		rows = Rows.tree(roots, panel.Expanded)
		capped = #rows >= Rows.MaxRows
	end
	local display = self.Api.types.display
	local noun = ({ functions = "function", constants = "constant", upvalues = "upvalue", contents = "entry" })[id] or "row"
	for _, node in rows do
		if node.Kind == "heading" then
			node.ValueText = ("%d %s"):format(node.Count or 0, if (node.Count or 0) == 1 then noun elseif noun == "entry" then "entries" else noun .. "s")
		elseif id ~= "functions" then
			local ok, text = pcall(display, node.Value)
			node.ValueText = if node.Note then ("(%s)"):format(node.Note) .. (if node.Value ~= nil then " " .. (if ok then text else "?") else "") else (if ok then text else "?")
		end
	end
	local filtered = nil
	if panel.Mode == "List" then
		-- flat rows with their paths: headings are in the paths
		local needle = panel.Search:lower():match("^%s*(.-)%s*$")
		local kept, total = {}, 0
		for _, node in rows do
			if node.Kind ~= "heading" then
				total += 1
				if passes(node, needle, panel.TypeFilter) then
					table.insert(kept, node)
				end
			end
		end
		filtered = needle ~= "" or panel.TypeFilter ~= View.TypeFilters[1]
		panel.Count.Text = if filtered then ("%d of %d"):format(#kept, total) else ("%d %s"):format(total, if total == 1 then "row" else "rows")
		rows = kept
	end
	panel.Rows = rows
	if panel.Mode ~= "Table" then
		panel.List:SetItems(rows)
	end
	local count = View.count(roots)
	local plural = if count == 1 then noun elseif noun == "entry" then "entries" else noun .. "s"
	local text = if panel.Why then panel.Why else ("%d %s"):format(count, plural)
	if hasHeadings and not panel.Why then
		text ..= (" · %d %s"):format(#roots, if #roots == 1 then "function" else "functions")
	end
	if capped then
		text ..= (" · showing the first %d rows"):format(Rows.MaxRows)
	end
	panel.Info.Text = text
	panel.InfoFull = text
	-- an empty list says why in its middle, in full (the bar may cut it)
	if panel.List and panel.List.EmptyLabel then
		panel.List.EmptyLabel.Text = if panel.Why then panel.Why elseif filtered then "Nothing matches" else "Nothing here"
		panel.List.EmptyLabel.TextWrapped = true
		panel.List.EmptyLabel.Size = UDim2.new(1, -24, 0, 60)
	end
	-- the count on the sub-tab's pill
	self.Tabs:Badge(id, if panel.Why then nil else count)
end

-- How many rows a panel's roots stand for: the rows themselves, or, when
-- they are function headings, the rows under them. The pill and the bar
-- both use this.
function View.count(roots: { any }): number
	if roots[1] and roots[1].Kind == "heading" then
		local count = 0
		for _, node in roots do
			count += node.Count or 0
		end
		return count
	end
	return #roots
end

-- Fills one built panel from the subject.
function View:_fill(id: string)
	local panel = self.Panels[id]
	if not panel then
		return -- not built yet: filled when it first shows
	end
	if panel.Source then
		self:_fillSource()
		return
	end
	if panel.Data then
		local ok, roots, why = pcall(self._roots, self, id)
		if not ok then
			roots, why = {}, "couldn't read it: " .. tostring(roots)
		end
		panel.Roots, panel.Why = roots, why
		self:_render(id)
	end
end

-- What to show. Fills every built panel now and the others when they open.
function View:Show(subject)
	if subject ~= self.Subject then
		-- a new subject: rows open in Tree views start closed again
		for panelId, panel in self.Panels do
			if panel.Data then
				table.clear(panel.Expanded)
				table.clear(panel.Closed)
				if panel.RefsFrame then
					self:FindReferences(panelId, nil) -- nothing selected in the new rows
				end
			end
		end
	end
	self.Subject = subject
	if self.Destroyed then
		return
	end
	local title = if subject then subject.Title else "Nothing loaded"
	self.TitleLabel.Text = title
	self.Kind.Text = View.summary(subject)
	self.NotesText = if subject and #subject.Notes > 0 then table.concat(subject.Notes, "\n") else nil
	-- the rows (and the searches some need) wait until the tab is open,
	-- so loading things elsewhere stays quick
	if not self.Api.tab.isOpen() then
		self.Dirty = true
		return
	end
	self.Dirty = false
	for id in self.Panels do
		self:_fill(id)
	end
	-- counts on the pills of data sub-tabs that haven't been opened yet
	for _, def in View.Panels do
		if def.Data and not self.Panels[def.Id] then
			local ok, roots, why = pcall(self._roots, self, def.Id)
			self.Tabs:Badge(def.Id, if ok and not why then View.count(roots) else nil)
		end
	end
end

function View:Select(id: string): boolean
	return self.Tabs:Select(id)
end

-- After a change: the rows read again (rows open stay open).
function View:Refresh()
	if self.Destroyed then
		return
	end
	self:Show(self.Subject)
end

-- The plugin's tab was opened: a decompile waiting for it starts now.
function View:Opened()
	if self.Destroyed then
		return
	end
	if self.Dirty then
		self:Show(self.Subject) -- what was loaded while the tab was closed
		return
	end
	local source = self.Panels.source
	if source and source.Pending then
		self:_fill("source")
	end
end

-- What kind of thing is shown, in a few words ("LocalScript · running").
function View.summary(subject): string
	if subject == nil or subject.Kind == "none" then
		return "load a script, a ModuleScript, a function or a table"
	end
	local parts = { KIND_TEXT[subject.Kind] or subject.Kind }
	local facts = {}
	for _, fact in subject.Facts do
		facts[fact.Id] = fact.Value
	end
	if subject.Kind == "script" or subject.Kind == "module" then
		parts[1] = tostring(facts.class or parts[1])
		if facts.running then
			table.insert(parts, if facts.running == "yes" then "running" else "not running")
		end
		if facts.required then
			table.insert(parts, if facts.required == "yes" then "required" else "not required yet")
		end
	elseif subject.Kind == "function" then
		parts[1] = tostring(facts.kind or parts[1])
		if facts.made == "the executor" then
			table.insert(parts, "made by the executor")
		end
	elseif subject.Kind == "table" and facts.entries then
		table.insert(parts, (tostring(facts.entries):match("^%d+") or "?") .. " entries")
	end
	if subject.Count > 1 then
		table.insert(parts, ("%d loaded, showing the first"):format(subject.Count))
	end
	return table.concat(parts, " · ")
end

function View:Destroy()
	self.Destroyed = true
end

return View
