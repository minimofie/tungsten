--[[
	Script Viewer · lib/view
	The plugin's tab: a toolbar naming what is shown, then sub-tabs:
	Source first (the decompiled script, read-only), then Constants,
	Upvalues, Functions and Contents (a loaded table, or what a required
	ModuleScript returns). The toolbar names what is shown and what kind
	of thing it is (hover it for notes). Each data sub-tab has views,
	kept in the plugin's settings (1.4):
		Tree      rows that open in place (tables, functions)
		List      every row with its path
		Table     the rows written as a Luau table
		Function  rows grouped under the function that owns them
		          (not for Functions, which is already by function)
	Constants, Upvalues and Contents have a References area (1.5): select a
	constant or an upvalue and it lists the other functions that use the
	same constant or hold the same upvalue; double-click one to load it.
	Editing (1.6): right-click a row for the "scriptviewer.row" menu
	(Change value…, Set to nil / Remove entry, Add entry…, Rename key…,
	Look into it, Keep in a variable…, Copy); double-click a row that
	doesn't open to change it; the Table view can be edited and applied.

		local view = View.new(page, api, inspect)
		view:Show(subject)        -- what to show (from Inspect.subject)
		view:Select("source")     -- open a sub-tab
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

local REFS = 150 -- height of the References area under a list

local View = {}
View.__index = View
-- the editing modules, for other plugins and the tests: view.Edit, view.Actions
View.Edit = Edit
View.Actions = Actions

-- Sub-tabs in order. Later parts add theirs here.
View.Panels = {
	{ Id = "source", Title = "Source", Icon = "console" },
	{ Id = "constants", Title = "Constants", Icon = "type_number", Data = true, Setting = "constantsView", Modes = { "Tree", "List", "Table", "Function" }, Refs = true },
	{ Id = "upvalues", Title = "Upvalues", Icon = "variable", Data = true, Setting = "upvaluesView", Modes = { "Tree", "List", "Table", "Function" }, Refs = true },
	{ Id = "functions", Title = "Functions", Icon = "type_function", Data = true, Setting = "functionsView", Modes = { "Tree", "List", "Table" } },
	{ Id = "contents", Title = "Contents", Icon = "type_table", Data = true, Setting = "contentsView", Modes = { "Tree", "List", "Table", "Function" }, Refs = true },
}
View.Modes = { "Tree", "List", "Table", "Function" }
local PANEL = {}
for _, def in View.Panels do
	PANEL[def.Id] = def
end

-- Name column: indented by depth, with ▸ / ▾ on things that open.
local function treeName(node): string
	local arrow = if node.Expandable then (if node.Expanded then "▾ " else "▸ ") else "   "
	return string.rep("    ", node.Depth) .. arrow .. node.Key
end

local VALUE_COLUMNS = {
	Tree = {
		{ Key = "Name", Title = "Name", Width = 190, Get = treeName },
		{ Key = "Type", Title = "Type", Width = 110, Type = "valueType" },
		{ Key = "ValueText", Title = "Value", Flex = true, Min = 160, Mono = true },
	},
	List = {
		{ Key = "Path", Title = "Path", Width = 230, Mono = true },
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
	value = "not something to look into",
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
	local api = self.Api
	if PANEL[id].Data then
		self:_buildDataPanel(id, holder)
		return
	end
	self:_buildSource(holder)
end

-- The view a data panel uses, from the plugin's settings (Tree when the
-- setting holds a view this panel doesn't have).
function View:_mode(id: string): string
	local ok, value = pcall(self.Api.settings.get, PANEL[id].Setting)
	if ok and table.find(PANEL[id].Modes, value) then
		return value
	end
	return "Tree"
end

-- A data panel: a toolbar (view, what is shown) over a list.
function View:_buildDataPanel(id: string, holder: Frame)
	local api = self.Api
	local layout = api.ui.page({ Parent = holder, Toolbar = true, Name = "Panel_" .. id })
	local panel = { Holder = holder, Page = layout, Body = layout.Body, Data = true, Expanded = {}, Closed = {}, Mode = self:_mode(id) }
	self.Panels[id] = panel
	panel.Switch = api.ui.new("Dropdown", {
		Parent = layout.Toolbar,
		Name = "View",
		Width = 110,
		Options = PANEL[id].Modes,
		Value = panel.Mode,
		OnChanged = function(value)
			api.settings.set(PANEL[id].Setting, value)
		end,
	})
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
	panel.Apply.Instance.LayoutOrder = 2
	panel.Revert.Instance.LayoutOrder = 3
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
		panel.Add.Instance.LayoutOrder = 4
	end
	panel.Info = api.ui.new("Label", { Parent = layout.Toolbar, Name = "Info", Text = "", Style = "muted", Size = UDim2.new(1, -130, 1, 0) })
	panel.Info.LayoutOrder = 5
	panel.Info.TextTruncate = Enum.TextTruncate.AtEnd
	-- hovering the bar shows all of it
	pcall(api.tooltip.attach, panel.Info, function()
		return panel.InfoFull or panel.Info.Text
	end)
	local holderFrame = Instance.new("Frame")
	holderFrame.Name = "ListHolder"
	holderFrame.BackgroundTransparency = 1
	holderFrame.Position = UDim2.fromOffset(12, 8)
	holderFrame.Size = UDim2.new(1, -24, 1, if PANEL[id].Refs then -16 - REFS - 8 else -16)
	holderFrame.Parent = layout.Body
	panel.ListHolder = holderFrame
	if PANEL[id].Refs then
		self:_buildRefs(id, layout.Body)
	end
	-- the Table view: the rows written as a Luau table (read-only for now)
	panel.Text = api.ui.new("TextEditor", {
		Parent = layout.Body,
		Name = "TableText",
		Position = UDim2.fromOffset(12, 8),
		Size = UDim2.new(1, -24, 1, -16),
		ReadOnly = true,
		Text = "",
	})
	self:_makeList(id)
	-- the view setting changed (here, or on the plugin's page)
	api.connect(api.settings.Changed, function(key)
		if key == PANEL[id].Setting and not self.Destroyed then
			local mode = self:_mode(id)
			if mode ~= panel.Mode then
				panel.Mode = mode
				panel.Switch:SetValue(mode, true)
				self:_makeList(id)
				self:_fill(id)
			end
		end
	end)
	self:_fill(id)
end

function View:_makeList(id: string)
	local api = self.Api
	local panel = self.Panels[id]
	if panel.List then
		panel.List:Destroy()
	end
	local listMode = if panel.Mode == "List" then "List" else "Tree" -- Function view uses the Tree columns
	local columns = if id == "functions" then FUNCTION_COLUMNS[listMode] else VALUE_COLUMNS[listMode]
	if id == "contents" and listMode == "Tree" and panel.Mode ~= "Function" then
		columns = table.clone(columns)
		columns[1] = table.clone(columns[1])
		columns[1].Title = "Key"
	end
	-- the list shows in Tree / List / Function, the text in Table
	panel.ListHolder.Visible = panel.Mode ~= "Table"
	panel.Text.Instance.Visible = panel.Mode == "Table"
	panel.Apply.Instance.Visible = panel.Mode == "Table" and id ~= "functions"
	panel.Revert.Instance.Visible = panel.Mode == "Table" and id ~= "functions"
	if panel.Add then
		panel.Add.Instance.Visible = panel.Mode ~= "Table"
	end
	panel.Info.Size = UDim2.new(1, if panel.Mode == "Table" and id ~= "functions" then -300 elseif panel.Add then -240 else -130, 1, 0)
	if panel.RefsFrame then
		panel.RefsFrame.Visible = panel.Mode ~= "Table"
	end

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
			if (panel.Mode == "Tree" or panel.Mode == "Function") and node.Expandable then
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

----------------------------------------------------------------------
-- References
----------------------------------------------------------------------

function View:_buildRefs(id: string, parent: Instance)
	local api = self.Api
	local panel = self.Panels[id]
	local frame = Instance.new("Frame")
	frame.Name = "References"
	frame.BackgroundTransparency = 1
	frame.Position = UDim2.new(0, 12, 1, -REFS - 8)
	frame.Size = UDim2.new(1, -24, 0, REFS)
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

-- Loads a function found as a reference, so the viewer looks into it.
function View:OpenReference(result)
	local api = self.Api
	api.loaded.set(api.loaded.target(result.Fn, { Label = ("function %s"):format(result.Name) }))
end

-- Searches the references of a row (in a thread; a newer selection wins).
function View:FindReferences(id: string, node: any)
	local panel = self.Panels[id]
	if not panel or not panel.RefsFrame then
		return
	end
	panel.RefsToken += 1
	local token = panel.RefsToken
	panel.RefsList:SetItems({})
	panel.RefsNode = node
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
		-- Function view headings start open; this closes or opens one
		panel.Closed[nodeId] = not panel.Closed[nodeId] or nil
	else
		panel.Expanded[nodeId] = not panel.Expanded[nodeId] or nil
	end
	self:_render(id)
end

-- The root rows of a data panel for the subject (and why there are none).
function View:_roots(id: string): ({ any }, string?)
	local subject = self.Subject
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
		-- upvalues: its running functions hold them (even with no copy)
		local live, why = Rows.liveFunctions(subject)
		if not live then
			return {}, why
		end
		return Rows.upvaluesOfFunctions(live)
	end
	local fn = subject.Fn
	if fn == nil then
		return {}, if subject.Kind == "table" then "a table has no " .. id .. " (its entries are in the Contents sub-tab)" else "this has no function to look into"
	end
	local showEmpty = false
	pcall(function()
		showEmpty = self.Api.settings.get("showEmpty") == true
	end)
	if id == "constants" then
		return Rows.constants(fn, { ShowEmpty = showEmpty })
	elseif id == "upvalues" then
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

-- The Function view's headings for a panel.
function View:_byFunction(id: string): ({ any }, string?)
	local subject = self.Subject
	if id == "contents" then
		return Rows.contentsByFunction(subject.Table)
	end
	local showEmpty = false
	pcall(function()
		showEmpty = self.Api.settings.get("showEmpty") == true
	end)
	if id == "constants" then
		return Rows.constantsByFunction(subject.Fn, { ShowEmpty = showEmpty })
	end
	if subject.Kind == "script" or subject.Kind == "module" then
		local live, why = Rows.liveFunctions(subject)
		if not live then
			return {}, why
		end
		return Rows.upvaluesOfFunctions(live)
	end
	return Rows.upvaluesByFunction(subject.Fn)
end

-- The Table view: the panel's data written as a Luau table.
function View:_renderText(id: string)
	local panel = self.Panels[id]
	local subject = self.Subject
	local text
	if panel.Why then
		text = "-- " .. panel.Why
	else
		local value, why
		if id == "upvalues" and panel.Roots[1] and panel.Roots[1].Kind == "heading" then
			-- a script's running functions: their upvalues, by function
			value = {}
			for _, heading in panel.Roots do
				local upvalues = {}
				for _, node in Rows.childrenOf(heading) do
					upvalues[node.Index] = node.Value
				end
				value[heading.Key:gsub("%s+", " ")] = upvalues
			end
		else
			value, why = Rows.plain(id, if id == "contents" then subject.Table else subject.Fn)
		end
		if value == nil then
			text = "-- " .. tostring(why or "nothing to write")
		else
			local ok, written = pcall(Serialize.write, value)
			text = if ok then written else "-- couldn't write it: " .. tostring(written)
		end
	end
	panel.Text:SetText(text, true)
	-- editable where it can be written back: not Functions, not a script's
	-- upvalues by function, not when there is nothing to write
	local editable = id ~= "functions" and not panel.Why and text:sub(1, 3) ~= "-- " and not (id == "upvalues" and panel.Roots[1] and panel.Roots[1].Kind == "heading")
	panel.Text:SetReadOnly(not editable)
	panel.Apply:SetEnabled(editable)
	panel.Revert:SetEnabled(editable)
	panel.List:SetItems({})
	return text
end

-- Rows for a data panel (Tree, List, Function or Table view).
function View:_render(id: string)
	local panel = self.Panels[id]
	local roots = panel.Roots or {}
	local rows, capped
	panel.Headings = nil
	local functionsShown = nil
	if panel.Mode == "Table" then
		self:_renderText(id)
		rows, capped = {}, false
	elseif panel.Mode == "List" then
		rows, capped = Rows.flat(roots)
	elseif panel.Mode == "Function" and not panel.Why then
		-- built once per subject (a script's needs a memory search), then
		-- opening and closing rows only redraws
		if not panel.FunctionRoots then
			panel.FunctionRoots, panel.FunctionRootsWhy = self:_byFunction(id)
		end
		local headings, why = panel.FunctionRoots, panel.FunctionRootsWhy
		panel.Headings = {}
		for _, node in headings do
			panel.Headings[node.Id] = true
		end
		functionsShown = #headings
		rows = Rows.tree(headings, function(node)
			if panel.Headings[node.Id] then
				return not panel.Closed[node.Id]
			end
			return panel.Expanded[node.Id] == true
		end)
		capped = #rows >= Rows.MaxRows
		if why and #headings == 0 then
			panel.FunctionWhy = why
		else
			panel.FunctionWhy = nil
		end
	else
		local headings = {}
		for _, node in roots do
			if node.Kind == "heading" then
				headings[node.Id] = true
			end
		end
		if next(headings) then
			-- function headings (a script's running functions) start open
			panel.Headings = headings
			rows = Rows.tree(roots, function(node)
				if headings[node.Id] then
					return not panel.Closed[node.Id]
				end
				return panel.Expanded[node.Id] == true
			end)
		else
			rows = Rows.tree(roots, panel.Expanded)
		end
		capped = #rows >= Rows.MaxRows
	end
	local items = table.create(#rows)
	local display = self.Api.types.display
	for index, node in rows do
		local item = node
		if node.Kind == "heading" then
			node.ValueText = ("%d %s"):format(node.Count or 0, if id == "constants" then "constants" else "upvalues")
		elseif id ~= "functions" then
			local ok, text = pcall(display, node.Value)
			node.ValueText = if node.Note then ("(%s)"):format(node.Note) .. (if node.Value ~= nil then " " .. (if ok then text else "?") else "") else (if ok then text else "?")
		end
		items[index] = item
	end
	panel.Rows = rows
	if panel.Mode ~= "Table" then
		panel.List:SetItems(items)
	end
	local count = View.count(roots)
	if roots[1] and roots[1].Kind == "heading" and panel.Mode ~= "Function" then
		functionsShown = #roots -- roots are functions (a script's running ones)
	end
	local noun = ({ functions = "function", constants = "constant", upvalues = "upvalue", contents = "entry" })[id] or "row"
	local plural = if count == 1 then noun elseif noun == "entry" then "entries" else noun .. "s"
	local text = if panel.Why then panel.Why else ("%d %s"):format(count, plural)
	if functionsShown and not panel.Why then
		text = if panel.FunctionWhy then panel.FunctionWhy else text .. (" · %d %s"):format(functionsShown, if functionsShown == 1 then "function" else "functions")
	end
	if capped then
		text ..= (" · showing the first %d rows"):format(Rows.MaxRows)
	end
	panel.Info.Text = text
	panel.InfoFull = text
	-- an empty list says why in its middle, in full (the bar may cut it)
	if panel.List and panel.List.EmptyLabel then
		panel.List.EmptyLabel.Text = if panel.Why then panel.Why else "Nothing here"
		panel.List.EmptyLabel.TextWrapped = true
		panel.List.EmptyLabel.Size = UDim2.new(1, -24, 0, 60)
	end
	-- the count on the sub-tab's pill
	self.Tabs:Badge(id, if panel.Why then nil else count)
end

-- How many rows a panel's roots stand for: the rows themselves, or, when
-- they are function headings (a script's running functions), the rows
-- under them. The pill and the bar both use this.
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
	local subject = self.Subject
	if panel.Source then
		self:_fillSource()
		return
	end
	if panel.Data then
		local roots, why = self:_roots(id)
		panel.Roots, panel.Why = roots, why
		panel.FunctionRoots, panel.FunctionRootsWhy = nil, nil
		self:_render(id)
		return
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
			local roots, why = self:_roots(def.Id)
			self.Tabs:Badge(def.Id, if why then nil else View.count(roots))
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
