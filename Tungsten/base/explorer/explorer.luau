--[[
	Tungsten · base/explorer/explorer
	The explorer panel on the window's right edge: search bar, instance
	tree and, under a splitter, the selection's properties. It owns $sel.

		Explorer.select({ part1, part2 })     -- replace the selection
		Explorer.getSelection() -> { Instance }
		Explorer.getPrimary()   -> Instance?  (what the path bar shows)
		Explorer.highlight(instance)          -- select, open, scroll to it
		Explorer.find("isa:BasePart door")    -- matches, without the UI
		Explorer.setOpen(true / false) ; Explorer.isOpen()
		Explorer.SelectionChanged:Connect(function(instances, primary) end)
		Explorer.OpenChanged:Connect(function(isOpen) end)
		Explorer.getProperties(instance) -> { { Name, Value, Type, Category, ReadOnly, … } }
		Explorer.pick("set Part0", function(instance) end)   -- the next tree click picks
		Explorer.setSplit(0.5)                -- tree share of the panel's height

	Plugin actions in the right-click menu's Function category:
		Explorer.addFunction({
			Id = "kill", Text = "Kill humanoid", Icon = "trash",
			AppliesTo = function(instances) return true end,   -- shown when true
			Run = function(instances) ... end,
			Owner = "myplugin", Order = 100,
		})
		Explorer.removeFunction("kill", "myplugin")
	(the menu itself is "explorer.function" in base/ui/menus).

	The panel is Scale.SideShare of the window's width (200 px at scale 1) and as tall as the window. Its
	button (bottom right) slides it into the window; the button then stays
	in the window's bottom-right corner and brings it back.
]]

local T = ...
local signal = T.import("base/signal")
local Services = T.import("base/services")
local Settings = T.import("base/settings")
local Theme = T.import("base/theme")
local Scale = T.import("base/scale")
local Variables = T.import("base/variables")
local Types = T.import("base/types")
local Create = T.import("base/ui/create")
local Animate = T.import("base/ui/animate")
local Icons = T.import("base/data/icons")
local Overlay = T.import("base/ui/overlay")
local Tooltip = T.import("base/ui/components/tooltip")
local Input = T.import("base/ui/components/input")
local Menus = T.import("base/ui/menus")
local Tree = T.import("base/explorer/tree")
local TreeView = T.import("base/explorer/treeview")
local Search = T.import("base/explorer/search")
local ExplorerMenu = T.import("base/explorer/menu") -- defines the explorer menus
local Properties = T.import("base/explorer/properties")
local PropView = T.import("base/explorer/propview")
local Filter = T.import("base/explorer/filter")
local Insert = T.import("base/explorer/insert")
local Actions = T.import("base/explorer/actions")
local Undo = T.import("base/undo")
local FilterPanel = T.import("base/explorer/filterpanel")
T.import("base/explorer/propmenu") -- defines the properties panel's menus

local new = Create.new
local Sizes = Theme.Sizes

local PAD = 8
local FOOTER = 28
local SEARCH_DELAY = 0.3
local SPLIT = 6 -- splitter height
local MIN_TREE = 60
local MIN_PROPS = 90
local UserInputService = Services.UserInputService

local Explorer = {}

--[[
	Explorer.report: the explorer's console printer (console/reporter):
	[*] / [+] / [!] Explorer: …, and [x] Explorer: … error records
	(kind "explorer"). Available once the console has started.
]]
function Explorer.reporter()
	if T.Console then
		return T.Console.reporter("explorer", { Label = "Explorer", Plugin = false, Kind = "explorer" })
	end
	return nil
end

local function report(level: string, ...)
	local reporter = Explorer.reporter()
	if reporter then
		return (reporter :: any)[level](reporter, ...)
	end
	return nil
end
Explorer.report = report

Explorer.SelectionChanged = signal.new() -- (instances, primary)
Explorer.OpenChanged = signal.new() -- (isOpen)
Explorer.SearchChanged = signal.new() -- (text)
Explorer.Loaded = signal.new() -- (instances, tabId) after Load
Explorer.Moved = signal.new() -- (instances, newParent) after a drag or moveInto
Explorer.FrozenChanged = signal.new() -- (frozen) the freeze button / Explorer.setFrozen
Explorer.Insert = Insert
Explorer.Actions = Actions -- every right-click action (base/explorer/actions)
Explorer.Search = Search
Explorer.Filter = Filter

local window = nil
local tree = nil
local view = nil
local holder, panel, toggle, searchInput, clearButton, statusLabel = nil, nil, nil, nil, nil, nil
local filterButton, filterIcon, filterStroke = nil, nil, nil
local freezeButton, freezeIcon, freezeStroke = nil, nil, nil
local open = true
local filter = nil -- search filter for the tree (nil: no search)
local searchText = ""
local searchHandle = nil
local searchState = "" -- status text while searching
local liveConnection = nil
local propView = nil
local splitter, treeArea, propsArea = nil, nil, nil
local split = 0.5
local picking = nil -- { Label, Callback } while a property editor waits for a tree click
local badgeIndex = {} -- Instance -> { names }
local bin = signal.bin()

----------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------

local function instancesOf(nodes): { Instance }
	local list = {}
	for _, node in nodes do
		if node.Obj and not node.IsNil then
			table.insert(list, node.Obj)
		end
	end
	return list
end

local function plural(count: number, word: string): string
	return ("%d %s%s"):format(count, word, if count == 1 then "" else "s")
end

local function setStatus()
	if not statusLabel then
		return
	end
	local text, key = "", "TextMuted"
	if picking then
		statusLabel.Text = ("Click an object to %s · Esc cancels"):format(picking.Label)
		Theme.bind(statusLabel, "TextColor3", "Accent")
		return
	end
	if filter then
		text = searchState
		if filter.Problem then
			key = "Danger"
		end
	elseif Filter.hides() then
		text = "filter: " .. Filter.describe()
	end
	if tree and tree.Frozen then
		local counts = tree:FrozenCounts()
		local frozenText = "frozen"
		if counts.Deleted > 0 then
			frozenText ..= (" · %d deleted"):format(counts.Deleted)
		end
		if counts.Moved > 0 then
			frozenText ..= (" · %d moved"):format(counts.Moved)
		end
		text = if text ~= "" then frozenText .. "  ·  " .. text else frozenText
		key = if key == "Danger" then key else "Accent"
	end
	local selected = view and view:GetSelected() or {}
	if #selected > 0 then
		local primary = view.Primary or selected[#selected]
		local part = if #selected == 1 and primary
			then ("%s · %s"):format(primary.Name, primary.Class)
			else plural(#selected, "object") .. " selected"
		text = if text ~= "" then text .. "  ·  " .. part else part
	end
	statusLabel.Text = text
	Theme.bind(statusLabel, "TextColor3", key)
end

----------------------------------------------------------------------
-- Variable badges
----------------------------------------------------------------------

local SKIP_BADGES = { last = true, err = true }
local badgesQueued = false

local function rebuildBadges()
	badgesQueued = false
	local index = {}
	local function add(obj, name)
		if typeof(obj) ~= "Instance" then
			return
		end
		local names = index[obj]
		if not names then
			names = {}
			index[obj] = names
		end
		if not table.find(names, name) then
			table.insert(names, name)
		end
	end
	for _, entry in Variables.list() do
		if not SKIP_BADGES[entry.Name] then
			local value = entry.Value
			if typeof(value) == "Instance" then
				add(value, entry.Name)
			elseif type(value) == "table" and getmetatable(value) == nil then
				for position = 1, math.min(#value, 200) do
					add(value[position], entry.Name)
				end
			end
		end
	end
	badgeIndex = index
	if view then
		view:_render()
	end
end

local function queueBadges()
	if badgesQueued then
		return
	end
	badgesQueued = true
	task.defer(rebuildBadges)
end

-- Variable names holding an instance (for badges and the Variable menu).
function Explorer.variablesHolding(obj: Instance): { string }
	return table.clone(badgeIndex[obj] or {})
end

local function badgeText(node): string?
	local names = badgeIndex[node.Obj]
	if not names or #names == 0 then
		return nil
	end
	local shown = {}
	for position = 1, math.min(#names, 2) do
		shown[position] = "$" .. names[position]
	end
	local text = table.concat(shown, " ")
	if #names > 2 then
		text ..= (" +%d"):format(#names - 2)
	end
	return text
end

----------------------------------------------------------------------
-- Selection
----------------------------------------------------------------------

local function onSelection(nodes, primaryNode)
	local instances = instancesOf(nodes)
	local value = if #instances == 0 then nil elseif #instances == 1 then instances[1] else instances
	Variables.setReserved("sel", value, "explorer")
	if propView then
		propView:SetInstances(instances)
	end
	setStatus()
	local primary = if primaryNode and primaryNode.Obj and not primaryNode.IsNil then primaryNode.Obj else instances[#instances]
	Explorer.SelectionChanged:Fire(instances, primary)
end

function Explorer.getSelection(): { Instance }
	if not view then
		return {}
	end
	return instancesOf(view:GetSelected())
end

function Explorer.getPrimary(): Instance?
	if not view then
		return nil
	end
	local primary = view.Primary
	if primary and primary.Obj and not primary.IsNil then
		return primary.Obj
	end
	local list = Explorer.getSelection()
	return list[#list]
end

function Explorer.getSelectedNodes(): { any }
	return if view then view:GetSelected() else {}
end

-- Opens every ancestor of a node so it has a row.
local function openTo(node)
	for _, ancestor in tree:Ancestors(node) do
		tree:Load(ancestor)
		if filter and filter.Keep[ancestor] then
			filter.Closed[ancestor] = nil
		else
			ancestor.Expanded = true
		end
	end
end

-- Nodes for instances (building paths), skipping ones not in the tree.
local function nodesFor(instances: { Instance }): ({ any }, number)
	local nodes, missing = {}, 0
	for _, obj in instances do
		local node = tree:NodeFor(obj)
		if node then
			table.insert(nodes, node)
		else
			missing += 1
		end
	end
	return nodes, missing
end

--[[
	Explorer.select(instances, opts) -> count selected, count not found
	opts.Reveal (default true): open ancestors and scroll to the first
	opts.Primary: the instance the path bar should show
]]
function Explorer.select(instances: { Instance } | Instance, opts: { [string]: any }?): (number, number)
	opts = opts or {}
	if typeof(instances) == "Instance" then
		instances = { instances :: Instance }
	end
	local nodes, missing = nodesFor(instances :: { Instance })
	if opts.Reveal ~= false then
		local needsClear = false
		for _, node in nodes do
			openTo(node)
			if filter and not filter.FilterOnly and not (filter.Match[node] or filter.Keep[node]) then
				needsClear = true
			end
		end
		if needsClear then
			Explorer.clearSearch()
		end
		-- The filter leaves them out: show them anyway (until the filter changes).
		if filter and filter.FilterOnly then
			for _, node in nodes do
				if node.Obj and not node.IsNil and not (filter.Match[node] or filter.Keep[node]) then
					Explorer._addMatch(filter, node.Obj)
				end
			end
		end
	end
	view:Refresh()
	local primary = if opts.Primary then tree:Get(opts.Primary) else nodes[1]
	view:Select(nodes, primary)
	if nodes[1] and opts.Reveal ~= false then
		view:Reveal(primary or nodes[1], true)
	end
	return #nodes, missing
end

-- Select, open the explorer if it is collapsed, and scroll to it.
-- opts.Flash: briefly light up the row.
function Explorer.highlight(obj: Instance, opts: { [string]: any }?): (boolean, string?)
	if typeof(obj) ~= "Instance" then
		return false, "not an Instance"
	end
	local node = tree:NodeFor(obj)
	if not node then
		return false, "it isn't in the explorer (hidden, destroyed or not reachable)"
	end
	if Filter.hidden(obj) then
		return false, "the explorer filter hides it (its class or a parent's) · /filter clear shows it"
	end
	if not open then
		Explorer.setOpen(true)
	end
	Explorer.select({ obj })
	if opts and opts.Flash then
		view:Flash(node)
	end
	return true, nil
end

function Explorer.clearSelection()
	if view then
		view:Select({}, nil)
	end
end

----------------------------------------------------------------------
-- Opening and closing nodes
----------------------------------------------------------------------

function Explorer.expand(obj: Instance?, all: boolean?)
	local targets = if obj then nodesFor({ obj }) else view:GetSelected()
	local function expand(node, depth: number)
		tree:Load(node)
		node.Expanded = true
		if filter and filter.Keep[node] then
			filter.Closed[node] = nil
		end
		if all and depth < 40 then
			for _, child in node.Children do
				if tree:HasChildren(child) then
					expand(child, depth + 1)
				end
			end
		end
	end
	for _, node in targets do
		openTo(node)
		expand(node, 0)
	end
	view:Refresh()
	return #targets
end

function Explorer.collapse(obj: Instance?, all: boolean?)
	local targets = if obj then nodesFor({ obj }) else view:GetSelected()
	local function collapse(node)
		node.Expanded = false
		if filter and filter.Keep[node] then
			filter.Closed[node] = true
		end
		if all and node.Children then
			for _, child in node.Children do
				collapse(child)
			end
		end
	end
	for _, node in targets do
		collapse(node)
	end
	view:Refresh()
	return #targets
end

function Explorer.refreshNil()
	if getnilinstances == nil then
		report("warn", "objects without a parent can't be listed here (getnilinstances is missing)")
		return
	end
	tree:RefreshNil()
	view:Refresh()
	local count = if tree.NilNode.Children then #tree.NilNode.Children else 0
	report("info", ("%s without a parent"):format(plural(count, "object")))
end

function Explorer.hideNil()
	tree:HideNil()
	view:Refresh()
end

----------------------------------------------------------------------
-- Search
----------------------------------------------------------------------

local refreshQueued = false
local function queueRefresh()
	if refreshQueued then
		return
	end
	refreshQueued = true
	task.defer(function()
		refreshQueued = false
		if view then
			view:Refresh()
			setStatus()
		end
	end)
end

local function stopSearch()
	if searchHandle then
		searchHandle:Cancel()
		searchHandle = nil
	end
	if liveConnection then
		liveConnection:Disconnect()
		liveConnection = nil
	end
end

-- Whether an object is (inside) Tungsten's own UI, which the explorer
-- leaves out. Searches skip these; the check is cheap per object.
local function isHiddenObject(obj: Instance): boolean
	if not tree then
		return false
	end
	if tree:IsHidden(obj) then
		return true
	end
	for hidden in tree.Hidden do
		local ok, inside = pcall(function()
			return obj:IsDescendantOf(hidden)
		end)
		if ok and inside then
			return true
		end
	end
	return false
end
Explorer.isHidden = isHiddenObject

local function addMatch(activeFilter, obj: Instance)
	if filter ~= activeFilter then
		return
	end
	local node = tree:NodeFor(obj)
	if not node then
		return
	end
	if not activeFilter.Match[node] then
		activeFilter.Match[node] = true
		activeFilter.Count += 1
	end
	local current = node.Parent
	while current and current ~= tree.Root and not activeFilter.Keep[current] do
		activeFilter.Keep[current] = true
		current = current.Parent
	end
	queueRefresh()
end

Explorer._addMatch = addMatch

-- Skips Tungsten's own UI and what the filter hides.
local function skipObject(obj: Instance): boolean
	return isHiddenObject(obj) or Filter.hidden(obj)
end

local function runSearch(text: string)
	stopSearch()
	searchText = text
	Explorer.SearchChanged:Fire(text)
	local only = Filter.onlyTest()
	local searching = not text:match("^%s*$")
	if not searching and not only then
		filter = nil
		searchState = ""
		view.EmptyText = "Nothing here"
		view:SetFilter(nil)
		-- Keep the selection in sight.
		local primary = view.Primary
		if primary and not primary.Removed then
			openTo(primary)
			view:Refresh()
			view:Reveal(primary, false)
		end
		setStatus()
		return
	end
	local query, problem
	if searching then
		query, problem = Search.parse(text)
	else
		query = Search.everything()
	end
	if query then
		query = Search.combine(query, only)
	end
	local active = { Match = {}, Keep = {}, Closed = {}, Count = 0, Query = query, Problem = problem, FilterOnly = not searching }
	filter = active
	if not query then
		searchState = problem or "can't search for that"
		view.EmptyText = searchState
		view:SetFilter(active)
		setStatus()
		return
	end
	searchState = if searching then "searching…" else "filtering…"
	view.EmptyText = if searching then "Searching…" else "Filtering…"
	view:SetFilter(active)
	setStatus()
	searchHandle = Search.run(query, {
		Skip = skipObject,
		OnMatch = function(obj)
			addMatch(active, obj)
			if filter == active then
				searchState = ("%s… %d"):format(if searching then "searching" else "filtering", active.Count)
			end
		end,
		OnDone = function(count, capped)
			if filter ~= active then
				return
			end
			-- Count what is shown (objects the tree can't show don't count).
			if searching then
				searchState = if capped
					then ("%d+ results · narrow the search"):format(active.Count)
					else plural(active.Count, "result")
				view.EmptyText = "No results"
			else
				searchState = if capped
					then ("filter: %d+ objects · narrow it"):format(active.Count)
					else ("filter: %s"):format(plural(active.Count, "object"))
				view.EmptyText = "Nothing matches the filter"
			end
			queueRefresh()
		end,
	})
	-- New objects that match while the search is open.
	liveConnection = game.DescendantAdded:Connect(function(obj)
		if filter == active and active.Count < Search.MaxResults and not skipObject(obj) and query.Test(obj) then
			task.defer(addMatch, active, obj)
		end
	end)
end

function Explorer.setSearch(text: string)
	text = tostring(text or "")
	if searchInput and searchInput:GetText() ~= text then
		searchInput:SetText(text)
	end
	runSearch(text)
end

function Explorer.getSearch(): string
	return searchText
end

function Explorer.clearSearch()
	Explorer.setSearch("")
end

--[[
	Matches for a query without touching the UI (console, plugins).
	The explorer filter applies too, unless opts.NoFilter. An empty text
	with a filter on lists what the filter shows.
]]
function Explorer.find(text: string, limit: number?, opts: { [string]: any }?): ({ Instance }?, string?, boolean?)
	local useFilter = not (opts and opts.NoFilter)
	local query, problem = Search.parse(text)
	if not query then
		if problem == nil and useFilter and Filter.showsOnly() then
			query = Search.everything()
		else
			return nil, problem or "type something to search for", nil
		end
	end
	local skip = isHiddenObject
	if useFilter then
		query = Search.combine(query, Filter.onlyTest())
		skip = function(obj)
			return isHiddenObject(obj) or Filter.hidden(obj)
		end
	end
	local results, capped = Search.collect(query, limit, skip)
	return results, nil, capped
end

--[[
	Explorer.load(instances, opts?) -> handled
	"Load" from the right-click menu: the objects become THE loaded target
	(base/loaded) that every tab works on. The path bar shows the first;
	every tab's OnLoad(values, tab, items) runs (the open tab first; plugins
	decide what loading means for their tab). handled: the open tab used it.
	opts.By: who loaded ("you" by default). A second argument that is a
	string (the old tab id) is ignored: loads go to every tab.
]]
function Explorer.load(instances: { Instance } | Instance, opts: any?): boolean
	if typeof(instances) == "Instance" then
		instances = { instances :: Instance }
	end
	local list = instances :: { Instance }
	if #list == 0 then
		return false
	end
	local by = if type(opts) == "table" and type(opts.By) == "string" then opts.By else "you"
	local Loaded = T.Loaded or T.import("base/loaded")
	local handled = Loaded.load(list, { By = by })
	local what = if #list == 1 then list[1].Name else plural(#list, "object")
	report("success", ("loaded %s"):format(what))
	Explorer.Loaded:Fire(list, T.Tabs and T.Tabs.Selected)
	return handled
end

-- The filter panel under the funnel button.
function Explorer.openFilter()
	if not filterButton then
		return nil
	end
	Explorer.FilterPanel = FilterPanel.open({
		AnchorPos = filterButton.AbsolutePosition,
		AnchorSize = filterButton.AbsoluteSize,
		Owner = filterButton,
	})
	return Explorer.FilterPanel
end

local function styleFreezeButton()
	if not freezeButton or not tree then
		return
	end
	local on = tree.Frozen
	Theme.bind(freezeButton, "BackgroundColor3", if on then "AccentSoft" else "Surface")
	Theme.bind(freezeStroke, "Color", if on then "Accent" else "Border")
	Icons.tint(freezeIcon, if on then "Accent" else "TextDim")
end

local function styleFilterButton()
	if not filterButton then
		return
	end
	local on = Filter.active()
	Theme.bind(filterButton, "BackgroundColor3", if on then "AccentSoft" else "Surface")
	Theme.bind(filterStroke, "Color", if on then "Accent" else "Border")
	Icons.tint(filterIcon, if on then "Accent" else "TextDim")
end

----------------------------------------------------------------------
-- Actions used by keys and menus
----------------------------------------------------------------------

-- Delete (and the Delete key): the objects leave the game but /undo can
-- bring them back (base/explorer/actions).
function Explorer.deleteNodes(nodes): number
	local count = Actions.delete(instancesOf(nodes))
	if view then
		view:Refresh()
	end
	return count
end

-- Renames an object (the tree's F2 / Rename), recorded for /undo.
-- Ctrl+Z in the tree: the same as /undo.
function Explorer.undo(): (boolean, string?)
	local ok, text = Undo.undo()
	if ok then
		report("success", "undid " .. tostring(text))
		if view then
			view:Refresh()
		end
	else
		report("warn", tostring(text))
	end
	return ok, text
end

function Explorer.renameTo(obj: Instance, name: string): (boolean, string?)
	local okOld, oldName = pcall(function()
		return obj.Name
	end)
	local ok, err = pcall(function()
		obj.Name = name
	end)
	if not ok then
		return false, (tostring(err):gsub("^.-:%d+: ", ""))
	end
	if okOld and oldName ~= name then
		Undo.record({
			Text = ("rename %s to %s"):format(tostring(oldName), name),
			Undo = function()
				obj.Name = oldName
			end,
		})
	end
	return true
end

function Explorer.rename(obj: Instance)
	local node = tree:NodeFor(obj)
	if node then
		openTo(node)
		view:Refresh()
		return view:BeginRename(node)
	end
	return nil
end

----------------------------------------------------------------------
-- Moving (drag and drop) and inserting
----------------------------------------------------------------------

local function nameOf(obj: Instance): string
	local ok, name = pcall(function()
		return obj.Name
	end)
	return if ok then tostring(name) else "?"
end

-- Why `obj` can't go into `target` (nil when it can).
-- Services (Workspace, Lighting, …) and the game itself stay where they
-- are: they can't be dragged, cut or moved.
function Explorer.isFixed(obj: Instance): boolean
	if obj == game then
		return true
	end
	local ok, parent = pcall(function()
		return obj.Parent
	end)
	return ok and parent == game
end

function Explorer.cannotMove(obj: Instance, target: Instance): string?
	if Explorer.isFixed(obj) then
		return "datamodels cannot be moved"
	end
	if obj == target then
		return "can't go inside itself"
	end
	local ok, inside = pcall(function()
		return target:IsDescendantOf(obj)
	end)
	if ok and inside then
		return "can't go inside its own descendant"
	end
	local okParent, parent = pcall(function()
		return obj.Parent
	end)
	if okParent and parent == target then
		return "already there"
	end
	return nil
end

--[[
	Explorer.moveInto(objects, target) -> moved
	Sets each object's Parent to target (what dragging rows onto a row
	does). Objects already inside one of the others move with it and are
	left alone. Reports the result and selects the moved objects.
]]
function Explorer.moveInto(objects: { Instance }, target: Instance): { Instance }
	local moved, failures = {}, {}
	local oldParents = {}
	-- objects whose ancestor is moving too go along with it
	for _, obj in Actions.topLevel(objects) do
		local reason = Explorer.cannotMove(obj, target)
		if reason == "already there" then
			continue
		elseif reason then
			table.insert(failures, { Name = nameOf(obj), Error = reason })
		else
			local okParent, oldParent = pcall(function()
				return obj.Parent
			end)
			local ok, err = pcall(function()
				obj.Parent = target
			end)
			if ok then
				table.insert(moved, obj)
				table.insert(oldParents, { obj, if okParent then oldParent else nil })
			else
				table.insert(failures, { Name = nameOf(obj), Error = tostring(err):gsub("^.-:%d+: ", "") })
			end
		end
	end
	if #moved > 0 then
		Undo.record({
			Text = ("move %s into %s"):format(Undo.describe(moved), nameOf(target)),
			Undo = function()
				local problem = nil
				for _, item in oldParents do
					local ok, err = pcall(function()
						item[1].Parent = item[2]
					end)
					if not ok then
						problem = err
					end
				end
				if problem then
					error(problem, 0)
				end
			end,
		})
		report("success", ("moved %s into %s"):format(if #moved == 1 then nameOf(moved[1]) else plural(#moved, "object"), Types.path(target)))
		Explorer.Moved:Fire(moved, target)
		if view then
			view:Refresh()
		end
		-- The tree hears about the new parents a moment later; select
		-- them once their rows are in place.
		Explorer.select(moved)
		task.defer(function()
			Explorer.select(moved)
		end)
	end
	if #failures > 0 then
		local first = failures[1]
		report("error", ("couldn't move %s: %s"):format(if #failures == 1 then first.Name else plural(#failures, "object"), first.Error), {
			Hints = { "locked or protected objects can't be moved from here" },
		})
	end
	return moved
end

--[[
	Explorer.insert(className, parents) -> created
	Makes a new `className` inside each parent (Object › Insert), reports
	it and selects the new objects.
]]
function Explorer.insert(className: string, parents: { Instance }): { Instance }
	if #parents == 0 then
		report("warn", "select where the new object goes first")
		return {}
	end
	local created, failures = Insert.into(className, parents)
	if #created > 0 then
		Undo.record({
			Text = ("insert %s"):format(if #created == 1 then className else ("%d × %s"):format(#created, className)),
			Undo = function()
				for _, object in created do
					pcall(function()
						object:Destroy()
					end)
				end
			end,
		})
		report("success", ("inserted %s into %s"):format(
			if #created == 1 then className else ("%d × %s"):format(#created, className),
			if #parents == 1 then Types.path(parents[1]) else plural(#parents, "object")
		))
		if view then
			view:Refresh()
		end
		Explorer.select(created)
	end
	if #failures > 0 then
		local first = failures[1]
		report("error", ("couldn't insert %s into %s: %s"):format(className, nameOf(first.Parent), first.Error), {
			Hints = { "some classes can only go in certain places, and some can't be made from here" },
		})
	end
	return created
end

----------------------------------------------------------------------
-- Open / collapse
----------------------------------------------------------------------

-- Collapsing: the panel slides to the left underneath the window until
-- it is hidden behind it, and slides back out to the right to open. Only
-- its horizontal position changes; its height and top edge stay exactly
-- the window's. The panel draws below the window (it isn't clipped), so
-- its corners stay round the whole way. Hidden, its right edge is one
-- corner radius inside the window's, so nothing of it shows past the
-- window's rounded corners. Open, it joins the window with no gap.
-- While it slides, the window's outline and its right corners follow
-- the panel every frame (window:SetAttached): the corners are square
-- only while the panel covers them, so no sharp corner ever shows.
-- Reversing mid-way carries on from where it is. The open / close button
-- stays in the window's title bar (rightmost, beside minimize).
local OPEN_TIME = 0.28

local function panelPose(isOpen: boolean): (UDim2, UDim2)
	local size = UDim2.new(1, -Scale.SideGap, 1, 0) -- the same open or hidden
	if isOpen then
		return UDim2.fromOffset(Scale.SideGap, 0), size
	end
	-- right edge one corner radius inside the window's right edge
	return UDim2.new(-1, Scale.SideGap - Sizes.Radius, 0, 0), size
end

-- How much of the panel's width sticks out past the window (0..1).
local function attachedFraction(): number
	local width = holder.AbsoluteSize.X
	if width <= 0 then
		return if open then 1 else 0
	end
	local right = panel.AbsolutePosition.X + panel.AbsoluteSize.X
	return math.clamp((right - holder.AbsolutePosition.X) / width, 0, 1)
end

local openToken = 0
local follow: RBXScriptConnection? = nil
local function stopFollow()
	if follow then
		follow:Disconnect()
		follow = nil
	end
end

local function applyOpen(animated: boolean)
	openToken += 1
	local token = openToken
	toggle.Button.Name = if open then "ExplorerCollapse" else "ExplorerOpen"
	toggle.SetActive(open) -- accent icon while the explorer is open
	local position, size = panelPose(open)
	stopFollow()
	if not animated then
		holder.Visible = open
		panel.Visible = open
		panel.Position, panel.Size = position, size
		window:SetAttached(if open then 1 else 0)
		return
	end
	if open and not holder.Visible then
		-- start hidden behind the window
		local hiddenPosition = panelPose(false)
		panel.Position = hiddenPosition
		window:SetAttached(0)
	end
	panel.Size = size -- the height never animates
	holder.Visible = true
	panel.Visible = true
	Animate.tween(panel, { Position = position }, OPEN_TIME, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
	-- The outline and the window's corners track the panel each frame.
	local elapsed = 0
	follow = Services.RunService.RenderStepped:Connect(function(dt)
		if token ~= openToken or not panel or not panel.Parent then
			stopFollow()
			return
		end
		elapsed += dt
		window:SetAttached(attachedFraction())
		if elapsed >= OPEN_TIME then
			stopFollow()
			window:SetAttached(if open then 1 else 0)
			if not open then
				holder.Visible = false
				panel.Visible = false
			end
		end
	end)
end

function Explorer.isOpen(): boolean
	return open
end

function Explorer.setOpen(value: boolean, animated: boolean?)
	value = value == true
	if value == open then
		return
	end
	open = value
	Settings.set("ExplorerOpen", value)
	Overlay.closeAll("explorer")
	window:SetSideOpen(value, animated ~= false)
	applyOpen(animated ~= false)
	Explorer.OpenChanged:Fire(value)
end

function Explorer.toggle()
	Explorer.setOpen(not open)
end

--[[
	Freeze: the tree stops following the game so nothing moves while you
	work on it. New objects are not added; objects that are removed (or
	moved elsewhere) keep their row, shown red. Unfreezing brings the tree
	back in line with the game. Not saved: Tungsten starts unfrozen.
]]
function Explorer.isFrozen(): boolean
	return tree ~= nil and tree.Frozen == true
end

--[[
	Explorer.frozenState(instance) -> what the frozen tree shows for it:
		"deleted" (red), "inside_deleted" (light red: it was in something
		deleted), "moved" (light blue), "inside_moved" (light blue: it was
		in something moved), or nil (not frozen, or nothing happened to it).
	Used by /vars and View in console; plugins get it as
	api.explorer.frozenState.
]]
function Explorer.frozenState(obj: Instance?): string?
	if not tree or not tree.Frozen or typeof(obj) ~= "Instance" then
		return nil
	end
	local node = tree:Get(obj)
	return if node then tree:FrozenState(node) else nil
end

-- Plain words for a frozen state.
Explorer.FrozenWords = {
	deleted = "deleted",
	inside_deleted = "deleted with its parent",
	moved = "moved",
	inside_moved = "moved with its parent",
}
Explorer.FrozenColors = {
	deleted = "Danger",
	inside_deleted = "DangerSoft",
	moved = "Moved",
	inside_moved = "Moved",
}

function Explorer.setFrozen(value: boolean): boolean
	if not tree then
		return false
	end
	local changed = tree:SetFrozen(value)
	if changed then
		report("info", if value then "explorer frozen" else "explorer unfrozen")
		if not value and view then
			-- Rows may have come and gone: draw now, and refresh a search.
			if searchText ~= "" then
				runSearch(searchText)
			end
		end
	end
	return changed
end

----------------------------------------------------------------------
-- Search box menu
----------------------------------------------------------------------

local FILTER_HELP = {
	{ "isa:", "class or a subclass (isa:BasePart)" },
	{ "class:", "exact class (class:Part)" },
	{ "remotes", "RemoteEvent / RemoteFunction / Unreliable" },
	{ "bindables", "BindableEvent / BindableFunction" },
	{ "scripts", "LocalScript / ModuleScript / Script" },
	{ "players", "Player objects" },
	{ "loadedmodules", "required ModuleScripts" },
	{ "nil", "objects outside the game" },
	{ "rad:", "parts within N studs of you (rad:50)" },
}

-- The search bar's right-click menu ("explorer.search"); ctx.Input is the box.
Menus.define("explorer.search", {
	Source = "explorer",
	Title = "Explorer search bar",
	Sections = { { Id = "filters", Header = "Insert a filter" }, "actions" },
})
for index, entry in FILTER_HELP do
	local word = entry[1]
	Menus.add("explorer.search", {
		Id = "filter_" .. word:gsub(":", ""),
		Section = "filters",
		Order = index * 10,
		Text = word .. "  " .. entry[2],
		Callback = function(ctx)
			local current = ctx.Input:GetText()
			local spacer = if current == "" or current:sub(-1) == " " then "" else " "
			local text = current .. spacer .. word
			ctx.Input:SetText(text)
			if word:sub(-1) ~= ":" then
				Explorer.setSearch(text)
			end
			ctx.Input:Focus()
		end,
	})
end
Menus.add("explorer.search", {
	Id = "filter",
	Section = "actions",
	Order = 5,
	Text = function()
		return if Filter.active() then "Filter… (on)" else "Filter…"
	end,
	Icon = "filter",
	Callback = function()
		task.defer(Explorer.openFilter)
	end,
})
Menus.add("explorer.search", {
	Id = "clear_filter",
	Section = "actions",
	Order = 6,
	Text = "Clear filter",
	Icon = "close",
	When = function()
		return Filter.active()
	end,
	Callback = function()
		Filter.clear()
	end,
})
Menus.add("explorer.search", {
	Id = "clear",
	Section = "actions",
	Order = 10,
	Text = "Clear search",
	Icon = "close",
	Disabled = function()
		return searchText == ""
	end,
	Callback = function()
		Explorer.clearSearch()
	end,
})

local function searchMenu()
	return Menus.open("explorer.search", { Explorer = Explorer, Input = searchInput, Text = searchText }, { Position = Overlay.mouse() })
end

----------------------------------------------------------------------
-- Plugin actions (Function category)
----------------------------------------------------------------------

--[[
	Explorer.addFunction(definition) -> handle (handle:Remove())
	definition: Id, Text, Icon?, Order?, Owner?, Shortcut?,
	AppliesTo(instances) -> boolean (default: always), Run(instances),
	or any other menu entry field (Disabled, Items, Checked, ...), which
	get the menu context (ctx.Instances, ctx.Classes, ...).
]]
function Explorer.addFunction(definition: { [string]: any })
	assert(type(definition) == "table", "addFunction expects a table")
	assert(type(definition.Text) == "string" or type(definition.Text) == "function", "a function needs Text")
	assert(definition.Run == nil or type(definition.Run) == "function", "Run must be a function")
	local entry = table.clone(definition)
	local appliesTo, run = definition.AppliesTo, definition.Run
	entry.AppliesTo, entry.Run = nil, nil
	entry.Id = definition.Id or definition.Text
	entry.Section = definition.Section or "main" -- below Documentation / View in console
	local owner = definition.Owner or "core"
	entry.When = function(ctx)
		if ctx.Count == 0 then
			return false
		end
		if appliesTo then
			local ok, result = pcall(appliesTo, ctx.Instances)
			if not ok then
				T.import("console/reporter").ownerFault(owner, ("AppliesTo of '%s'"):format(tostring(entry.Id)), result)
				return false
			end
			return result == true
		end
		return true
	end
	if run then
		entry.Callback = function(ctx)
			run(ctx.Instances)
		end
	end
	return Menus.add("explorer.function", entry, definition.Owner or "core")
end

function Explorer.removeFunction(id: string, owner: string?): boolean
	return Menus.remove("explorer.function", id, owner)
end

----------------------------------------------------------------------
-- Properties
----------------------------------------------------------------------

--[[
	Explorer.getProperties(instance, opts) -> list of
	{ Name, Value, Type, DataType, Category, ReadOnly, Deprecated, Hidden, Readable }
	opts.ShowHidden / opts.ShowDeprecated (default: true), opts.Filter.
]]
function Explorer.getProperties(instance: Instance, opts: { [string]: any }?): { any }
	assert(typeof(instance) == "Instance", "getProperties expects an Instance")
	opts = opts or {}
	local entries = Properties.collect({ instance }, {
		ShowHidden = (opts :: any).ShowHidden ~= false,
		ShowDeprecated = (opts :: any).ShowDeprecated ~= false,
		Filter = (opts :: any).Filter,
	})
	local list = {}
	for _, entry in entries do
		local prop = entry.Prop
		table.insert(list, {
			Name = entry.Name,
			Value = entry.Value,
			Readable = entry.Readable,
			Type = prop.Type,
			DataType = prop.DataType,
			Enum = prop.Enum,
			Category = prop.Category,
			Class = prop.Class,
			ReadOnly = prop.ReadOnly == true,
			Deprecated = prop.Deprecated == true,
			Hidden = prop.Hidden == true or prop.NotScriptable == true,
		})
	end
	return list
end

Explorer.PropertyData = Properties

-- Pick mode: the next click in the tree calls back with that object
-- instead of selecting it (Esc or Explorer.cancelPick() stops it).
function Explorer.pick(label: string, callback: (Instance) -> ())
	if not view then
		return false
	end
	if not open then
		Explorer.setOpen(true)
	end
	picking = { Label = label, Callback = callback }
	view.PickHandler = function(node)
		local current = picking
		picking = nil
		setStatus()
		if current and node.Obj and not node.IsNil then
			local ok, err = pcall(current.Callback, node.Obj)
			if not ok then
				report("error", ("picking failed: %s"):format(tostring(err)))
			end
		end
	end
	setStatus()
	return true
end

function Explorer.cancelPick()
	if picking then
		picking = nil
		if view then
			view.PickHandler = nil
		end
		setStatus()
	end
end

function Explorer.isPicking(): boolean
	return picking ~= nil
end

-- Tree / properties layout for a split ratio (the tree's share).
local function layoutSplit()
	if not treeArea then
		return
	end
	local top = PAD * 2 + Sizes.Control
	local fixed = top + FOOTER + SPLIT
	local r = split
	treeArea.Position = UDim2.fromOffset(4, top)
	treeArea.Size = UDim2.new(1, -8, r, -r * fixed)
	splitter.Position = UDim2.new(0, 4, r, top - r * fixed)
	propsArea.Position = UDim2.new(0, 4, r, top - r * fixed + SPLIT)
	propsArea.Size = UDim2.new(1, -8, 1 - r, -(1 - r) * fixed)
end

-- Clamps a ratio so both parts keep a usable height.
local function clampSplit(ratio: number): number
	local height = if panel then Create.layoutSize(panel).Y else 0
	local available = height - (PAD * 2 + Sizes.Control + FOOTER + SPLIT)
	if available <= MIN_TREE + MIN_PROPS then
		return math.clamp(ratio, 0.2, 0.8)
	end
	return math.clamp(ratio, MIN_TREE / available, 1 - MIN_PROPS / available)
end

function Explorer.setSplit(ratio: number, save: boolean?)
	split = clampSplit(tonumber(ratio) or 0.5)
	layoutSplit()
	if save ~= false then
		Settings.set("ExplorerSplit", split)
	end
end

function Explorer.getSplit(): number
	return split
end

----------------------------------------------------------------------
-- Building
----------------------------------------------------------------------

function Explorer.start(win, hidden: { Instance })
	window = win
	open = Settings.get("ExplorerOpen") ~= false
	Explorer.reporter() -- registers the "Explorer" name for its messages
	Filter.load()
	tree = Tree.new({
		Hidden = hidden,
		HideTest = function(obj, className)
			return Filter.hiddenClass(obj, className)
		end,
	})
	Explorer.Tree = tree
	bin:Add(tree)

	-- Frame on the window's right edge holding the panel. It sits under
	-- the window and doesn't clip, so the panel's rounded corners and
	-- border are never cut off while it slides.
	holder = new("Frame", {
		Name = "Explorer",
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(Scale.SideShare, Scale.SideGap, 1, 0),
		BackgroundTransparency = 1,
		ClipsDescendants = false,
		ZIndex = -1, -- under the window's Backing: the panel slides out from beneath it
		Parent = window.Root,
	})
	Overlay.addRoot(holder)
	panel = new("Frame", {
		Name = "Panel",
		Position = UDim2.fromOffset(Scale.SideGap, 0),
		Size = UDim2.new(1, -Scale.SideGap, 1, 0),
		Active = true,
		Theme = { BackgroundColor3 = "Background" },
		Parent = holder,
	})
	-- Joined to the window: rounded on the right only (a square patch on
	-- the left), a thin line where they meet, and the window's outline
	-- goes around both.
	Create.corner(panel, Sizes.Radius)
	new("Frame", {
		Name = "Square",
		Size = UDim2.new(0, Sizes.Radius, 1, 0),
		ZIndex = 0,
		Theme = { BackgroundColor3 = "Background" },
		Parent = panel,
	})
	new("Frame", {
		Name = "Seam",
		Size = UDim2.new(0, 1, 1, 0),
		ZIndex = 5,
		Theme = { BackgroundColor3 = "Border" },
		Parent = panel,
	})
	Explorer.Panel = panel

	-- Search
	searchInput = Input.new({
		Name = "Search",
		Icon = "search",
		Placeholder = "Search…",
		Position = UDim2.fromOffset(PAD, PAD),
		Size = UDim2.new(1, -PAD * 2, 0, Sizes.Control),
		OnTyping = function(text)
			clearButton.Visible = text ~= ""
			local token = {}
			Explorer._typingToken = token
			task.delay(SEARCH_DELAY, function()
				if Explorer._typingToken == token and text ~= searchText then
					runSearch(text)
				end
			end)
		end,
		OnCommit = function(text)
			Explorer._typingToken = nil
			if text ~= searchText then
				runSearch(text)
			end
		end,
		Parent = panel,
	})
	-- [ search ………… ] [filter] [freeze]
	searchInput.Instance.Size = UDim2.new(1, -PAD * 2 - (Sizes.Control + 4) * 2, 0, Sizes.Control)
	searchInput.Box.Size = UDim2.new(1, -26 - 26, 1, 0)
	-- Filter button (funnel) right of the search box.
	filterButton = new("TextButton", {
		Name = "FilterButton",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -PAD - Sizes.Control - 4, 0, PAD),
		Size = UDim2.fromOffset(Sizes.Control, Sizes.Control),
		Theme = { BackgroundColor3 = "Surface" },
		Parent = panel,
	})
	Create.corner(filterButton, Sizes.RadiusSmall)
	filterStroke = Create.stroke(filterButton, "Border", 1, 0)
	filterIcon = Icons.new("filter", 14, "TextDim")
	filterIcon.AnchorPoint = Vector2.new(0.5, 0.5)
	filterIcon.Position = UDim2.fromScale(0.5, 0.5)
	filterIcon.Parent = filterButton
	Animate.pressable(filterButton, bin)
	Animate.hover(filterButton, bin, function(hovered)
		if not Filter.active() then
			Theme.bind(filterButton, "BackgroundColor3", if hovered then "SurfaceHover" else "Surface", Animate.Fast)
		end
	end)
	bin:Add(filterButton.Activated:Connect(function()
		local current = Explorer.FilterPanel
		if current and not current.Closed then
			current:Close("toggle")
		elseif not Overlay.justClosed(filterButton) then
			Explorer.openFilter()
		end
	end))
	Explorer.FilterButton = filterButton
	styleFilterButton()
	-- Freeze button (snowflake) right of the filter button: the tree stops
	-- following the game while it is on.
	freezeButton = new("TextButton", {
		Name = "FreezeButton",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -PAD, 0, PAD),
		Size = UDim2.fromOffset(Sizes.Control, Sizes.Control),
		Theme = { BackgroundColor3 = "Surface" },
		Parent = panel,
	})
	Create.corner(freezeButton, Sizes.RadiusSmall)
	freezeStroke = Create.stroke(freezeButton, "Border", 1, 0)
	freezeIcon = Icons.new("freeze", 14, "TextDim")
	freezeIcon.AnchorPoint = Vector2.new(0.5, 0.5)
	freezeIcon.Position = UDim2.fromScale(0.5, 0.5)
	freezeIcon.Parent = freezeButton
	Animate.pressable(freezeButton, bin)
	Animate.hover(freezeButton, bin, function(hovered)
		if not tree.Frozen then
			Theme.bind(freezeButton, "BackgroundColor3", if hovered then "SurfaceHover" else "Surface", Animate.Fast)
		end
	end)
	bin:Add(freezeButton.Activated:Connect(function()
		Explorer.setFrozen(not tree.Frozen)
	end))
	bin:Add((Tooltip.attach(freezeButton, function()
		return if tree.Frozen
			then "Unfreeze: the tree catches up with the game"
			else "Freeze: the tree stops changing (new objects wait, removed ones turn red)"
	end)).Bin)
	Explorer.FreezeButton = freezeButton
	bin:Add(tree.FrozenChanged:Connect(function(frozen)
		styleFreezeButton()
		setStatus()
		Explorer.FrozenChanged:Fire(frozen)
	end))
	styleFreezeButton()
	bin:Add(Filter.Changed:Connect(function()
		styleFilterButton()
		tree:_changed()
		runSearch(searchText)
	end))
	Explorer.SearchInput = searchInput
	clearButton = new("TextButton", {
		Name = "Clear",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -4, 0.5, 0),
		Size = UDim2.fromOffset(20, 20),
		BackgroundTransparency = 1,
		Visible = false,
		Theme = { BackgroundColor3 = "SurfaceHover" },
		Parent = searchInput.Instance,
	})
	Create.corner(clearButton, 5)
	local clearIcon = Icons.new("close", 12, "TextMuted")
	clearIcon.AnchorPoint = Vector2.new(0.5, 0.5)
	clearIcon.Position = UDim2.fromScale(0.5, 0.5)
	clearIcon.Parent = clearButton
	Animate.hover(clearButton, bin, function(hovered)
		clearButton.BackgroundTransparency = if hovered then 0 else 1
		Icons.tint(clearIcon, if hovered then "Text" else "TextMuted", Animate.Fast)
	end)
	bin:Add(clearButton.Activated:Connect(function()
		Explorer.clearSearch()
	end))
	-- Right-click may reach the frame, the text box or both: open once.
	local lastMenuInput = nil
	local function onSearchInput(input)
		if input.UserInputType == Enum.UserInputType.MouseButton2 and input ~= lastMenuInput then
			lastMenuInput = input
			searchMenu()
		end
	end
	bin:Add(searchInput.Instance.InputBegan:Connect(onSearchInput))
	bin:Add(searchInput.Box.InputBegan:Connect(onSearchInput))

	-- Tree
	local treeFrame = new("Frame", {
		Name = "TreeArea",
		BackgroundTransparency = 1,
		Parent = panel,
	})
	treeArea = treeFrame
	Explorer.TreeArea = treeFrame
	view = TreeView.new({
		Parent = treeFrame,
		Tree = tree,
		Badges = badgeText,
		-- cut objects fade until they are pasted or the clipboard is cleared
		Dimmed = function(node)
			return node.Obj ~= nil and Actions.isOnClipboard(node.Obj) == "cut"
		end,
		OnContext = function(nodes, node, point)
			ExplorerMenu.open(Explorer, nodes, node, point)
		end,
		OnDelete = function(nodes)
			Explorer.deleteNodes(nodes)
		end,
		OnRename = function(node, name)
			return Explorer.renameTo(node.Obj, name)
		end,
		OnShortcut = function(key, nodes)
			local list = instancesOf(nodes)
			if key == Enum.KeyCode.D and #list > 0 then
				Actions.duplicate(list)
			elseif key == Enum.KeyCode.X and #list > 0 then
				Actions.cut(list)
			elseif key == Enum.KeyCode.C and #list > 0 then
				Actions.copy(list)
			elseif key == Enum.KeyCode.V then
				Actions.pasteInto(list)
			elseif key == Enum.KeyCode.G and #list > 0 then
				Actions.group(list, "Model")
			else
				return false
			end
			return true
		end,
		OnUndo = function()
			Explorer.undo()
		end,
		CanDrag = function(node)
			return not Explorer.isFixed(node.Obj)
		end,
		CanMove = function(nodes, target)
			if not target or target.IsNil or not target.Obj then
				return false, "can't drop here"
			end
			local already = 0
			for _, node in nodes do
				local reason = Explorer.cannotMove(node.Obj, target.Obj)
				if reason == "already there" then
					already += 1
				elseif reason then
					return false, reason
				end
			end
			if already == #nodes then
				return false, "already there"
			end
			return true
		end,
		OnMove = function(nodes, target)
			Explorer.moveInto(instancesOf(nodes), target.Obj)
		end,
	})
	Explorer.View = view
	bin:Add(view)
	bin:Add(stopFollow)
	bin:Add(view.SelectionChanged:Connect(onSelection))
	-- Cut / Copy / Paste / Clear Clipboard: cut rows fade or come back
	bin:Add(Actions.ClipboardChanged:Connect(function()
		if view then
			view:Redraw()
		end
	end))
	bin:Add(tree.Changed:Connect(function()
		view:Refresh()
		setStatus()
	end))
	bin:Add(tree.Renamed:Connect(function(node)
		-- A rename can make an object match (or stop matching) the search.
		local active = filter
		if active and active.Query and node.Obj then
			local matches = active.Query.Test(node.Obj)
			if matches and not active.Match[node] then
				addMatch(active, node.Obj)
			elseif not matches and active.Match[node] then
				active.Match[node] = nil
				active.Count -= 1
				queueRefresh()
			end
		end
	end))

	-- Splitter between the tree and the properties (drag to resize).
	splitter = new("TextButton", {
		Name = "Splitter",
		Size = UDim2.new(1, -8, 0, SPLIT),
		BackgroundTransparency = 1,
		ZIndex = 5,
		Parent = panel,
	})
	Explorer.Splitter = splitter
	local grip = new("Frame", {
		Name = "Grip",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -8, 0, 1),
		ZIndex = 5,
		Theme = { BackgroundColor3 = "Border" },
		Parent = splitter,
	})
	local dragging = false
	Animate.hover(splitter, bin, function(hovered)
		Theme.bind(grip, "BackgroundColor3", if hovered or dragging then "Accent" else "Border", Animate.Fast)
		grip.Size = UDim2.new(1, -8, 0, if hovered or dragging then 2 else 1)
	end)
	bin:Add(splitter.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			Theme.bind(grip, "BackgroundColor3", "Accent")
		end
	end))
	bin:Add(UserInputService.InputChanged:Connect(function(input)
		if not dragging then
			return
		end
		if input.UserInputType ~= Enum.UserInputType.MouseMovement and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		local top = PAD * 2 + Sizes.Control
		local available = Create.layoutSize(panel).Y - (top + FOOTER + SPLIT)
		if available <= 0 then
			return
		end
		local y = Create.toLocal(Overlay.pointOf(input), panel).Y - top - SPLIT / 2
		Explorer.setSplit(y / available, false)
	end))
	bin:Add(UserInputService.InputEnded:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then
			dragging = false
			Theme.bind(grip, "BackgroundColor3", "Border", Animate.Fast)
			grip.Size = UDim2.new(1, -8, 0, 1)
			Settings.set("ExplorerSplit", split)
		end
	end))

	-- Properties: filter box, options button, the rows.
	propsArea = new("Frame", {
		Name = "PropertiesArea",
		BackgroundTransparency = 1,
		Parent = panel,
	})
	Explorer.PropertiesArea = propsArea
	local propFilter = Input.new({
		Name = "PropertyFilter",
		Icon = "search",
		Placeholder = "Filter properties",
		Position = UDim2.fromOffset(4, 2),
		Size = UDim2.new(1, -8 - Sizes.Control - 4, 0, Sizes.Control),
		OnTyping = function(text)
			if propView then
				propView:SetFilter(text)
			end
		end,
		Parent = propsArea,
	})
	Explorer.PropertyFilter = propFilter
	local optionsButton = new("TextButton", {
		Name = "PropertyOptions",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -4, 0, 2),
		Size = UDim2.fromOffset(Sizes.Control, Sizes.Control),
		Theme = { BackgroundColor3 = "Surface" },
		Parent = propsArea,
	})
	Create.corner(optionsButton, Sizes.RadiusSmall)
	local optionsStroke = Create.stroke(optionsButton, "Border", 1, 0)
	local optionsIcon = Icons.new("more", 14, "TextDim")
	optionsIcon.AnchorPoint = Vector2.new(0.5, 0.5)
	optionsIcon.Position = UDim2.fromScale(0.5, 0.5)
	optionsIcon.Parent = optionsButton
	Animate.pressable(optionsButton, bin)
	Animate.hover(optionsButton, bin, function(hovered)
		Theme.bind(optionsButton, "BackgroundColor3", if hovered then "SurfaceHover" else "Surface", Animate.Fast)
		Theme.bind(optionsStroke, "Color", if hovered then "BorderStrong" else "Border", Animate.Fast)
		Icons.tint(optionsIcon, if hovered then "Text" else "TextDim", Animate.Fast)
	end)
	Explorer.PropertyOptions = optionsButton
	bin:Add(optionsButton.Activated:Connect(function()
		if Overlay.justClosed(optionsButton) then
			return
		end
		local pos, size = optionsButton.AbsolutePosition, optionsButton.AbsoluteSize
		Explorer.PropertiesMenu = Menus.open("explorer.properties", { Explorer = Explorer, View = propView }, {
			Position = Vector2.new(pos.X, pos.Y + size.Y + 4),
			Owner = optionsButton,
		})
	end))
	local propBody = new("Frame", {
		Name = "PropertiesBody",
		Position = UDim2.fromOffset(0, Sizes.Control + 6),
		Size = UDim2.new(1, 0, 1, -(Sizes.Control + 6)),
		BackgroundTransparency = 1,
		Parent = propsArea,
	})
	propView = PropView.new({ Parent = propBody, Explorer = Explorer })
	Explorer.PropView = propView
	bin:Add(propView)
	split = tonumber(Settings.get("ExplorerSplit")) or 0.5
	layoutSplit()
	bin:Add(panel:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		local clamped = clampSplit(split)
		if clamped ~= split then
			split = clamped
			layoutSplit()
		end
	end))

	-- Esc leaves pick mode.
	bin:Add(UserInputService.InputBegan:Connect(function(input)
		if picking and input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode == Enum.KeyCode.Escape then
			Explorer.cancelPick()
		end
	end))

	-- Footer: status text.
	local footer = new("Frame", {
		Name = "Footer",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, FOOTER),
		BackgroundTransparency = 1,
		Parent = panel,
	})
	new("Frame", {
		Name = "Line",
		Size = UDim2.new(1, 0, 0, 1),
		Theme = { BackgroundColor3 = "Border" },
		Parent = footer,
	})
	statusLabel = new("TextLabel", {
		Name = "Status",
		Position = UDim2.fromOffset(10, 1),
		Size = UDim2.new(1, -20, 1, -1),
		TextSize = Sizes.TextSmall,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Theme = { TextColor3 = "TextMuted" },
		Parent = footer,
	})
	Explorer.Status = statusLabel

	-- Veil (fades with the window's open/minimize animations).
	local veil = new("Frame", {
		Name = "Veil",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 100,
		Theme = { BackgroundColor3 = "Background" },
		Parent = panel,
	})
	Create.corner(veil, Sizes.Radius)
	window:AddVeil(veil)

	-- Open / close button: in the window's title bar, rightmost (minimize
	-- sits to its left), the same size as minimize. It never moves.
	toggle = window:AddTitleButton({
		Name = "ExplorerCollapse",
		Icon = "explorer",
		Order = 20,
		OnClick = function()
			Explorer.toggle()
		end,
	})
	Explorer.ToggleButton = toggle.Button

	window:SetSideOpen(open, false)
	applyOpen(false)

	bin:Add(Variables.Changed:Connect(function(name)
		if name ~= "last" then
			queueBadges()
		end
	end))
	rebuildBadges()

	view:Refresh()
	if Filter.showsOnly() then
		runSearch("") -- a saved "show only" filter
	end
	setStatus()

	bin:Add(function()
		stopSearch()
		for _, sig in { Explorer.SelectionChanged, Explorer.OpenChanged, Explorer.SearchChanged } do
			sig:DisconnectAll()
		end
		Variables.setReserved("sel", nil)
		picking = nil
		window, tree, view, propView = nil, nil, nil, nil
		treeArea, splitter, propsArea = nil, nil, nil
		filter = nil
		searchText = ""
	end)
	T.Bin:Add(bin)
	T.Log.info("explorer", "started")
end

return Explorer
