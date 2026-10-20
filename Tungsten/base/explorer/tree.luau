--[[
	Tungsten · base/explorer/tree
	The explorer's model of the game: one node per instance it has seen.
	Children load the first time a node is opened (or a search or a
	selection needs them) and stay live from then on through the
	instance's ChildAdded / ChildRemoved.

		local tree = Tree.new({ Hidden = { gui1, gui2 } })
		tree:Load(node)                  -- children of a node
		tree:NodeFor(instance)           -- builds the path down to it
		tree:Flatten()                   -- rows to draw, in order
		tree.Changed:Connect(fn)         -- something to redraw (batched)
		tree.Removed:Connect(fn(node))   -- a node left the tree
		tree:SetFrozen(true)             -- stop following the game (see Freezing)

	Node fields
		Obj        the Instance (nil for the "Nil Instances" node)
		Parent     parent node
		Children   array of nodes once loaded
		Loaded, Expanded, Depth, Name, Class
		IsNil      true for the "Nil Instances" node only
		Gone       true while frozen: the object left this place;
		GoneKind   "deleted" or "moved" (tree:FrozenState(node) says how
		           the row looks, rows inside it included)

	Freezing
		While frozen the tree stops following the game, so no row moves:
		new objects are tracked (tree.NewSinceFreeze) but not added, not
		even when a folder is opened for the first time; deleted objects
		keep their row in red (what was inside them light red), moved
		ones keep theirs in light blue (marked Gone), and renames change
		the text but not the order. Unfreezing brings the tree back in line with the game:
		new objects appear, gone ones leave (moved ones go to their new
		place, keeping their selection), and everything is sorted again.
]]

local T = ...
local signal = T.import("base/signal")
local Settings = T.import("base/settings")

-- Services shown first, in this order; other services follow by name.
local SERVICE_ORDER = {
	"Workspace", "Players", "Lighting", "MaterialService", "NetworkClient", "ReplicatedFirst",
	"ReplicatedStorage", "ServerScriptService", "ServerStorage", "StarterGui", "StarterPack",
	"StarterPlayer", "Teams", "SoundService", "Chat", "TextChatService", "LocalizationService", "TestService",
}
local SERVICE_RANK = {}
for index, name in SERVICE_ORDER do
	SERVICE_RANK[name] = index
end

local Tree = {}
Tree.__index = Tree
Tree.ServiceOrder = SERVICE_ORDER

local function getName(obj: Instance): string
	local ok, name = pcall(function()
		return obj.Name
	end)
	return if ok then tostring(name) else "<locked>"
end

local function getClass(obj: Instance): string
	local ok, class = pcall(function()
		return obj.ClassName
	end)
	return if ok then tostring(class) else "Instance"
end

local function parentOf(obj: Instance): Instance?
	local ok, parent = pcall(function()
		return obj.Parent
	end)
	return if ok then parent else nil
end
Tree.parentOf = parentOf

-- Two references to the same instance (cloneref copies are not ==).
local function same(a: any, b: any): boolean
	if a == b then
		return true
	end
	if typeof(a) ~= "Instance" or typeof(b) ~= "Instance" or compareinstances == nil then
		return false
	end
	local ok, result = pcall(compareinstances, a, b)
	return ok and result == true
end
Tree.same = same

function Tree.new(opts: { [string]: any }?)
	opts = opts or {}
	local self = setmetatable({}, Tree)
	self.Bin = signal.bin()
	self.Changed = signal.new()
	self.Removed = signal.new() -- (node)
	self.Renamed = signal.new() -- (node)
	self.Added = signal.new() -- (instance) a child appeared under a loaded node
	self.Nodes = {} :: { [Instance]: any }
	self.Hidden = {} :: { [Instance]: boolean }
	for _, object in opts.Hidden or {} do
		self.Hidden[object] = true
	end
	-- function(obj, className) -> true to leave a child (and what is inside) out
	self.HideTest = opts.HideTest
	self.Sorting = Settings.get("ExplorerSort") ~= false
	self._seq = 0
	self._queued = false
	self.Frozen = false
	self.FrozenChanged = signal.new() -- (frozen)
	-- While frozen: every object added to the game since freezing (it
	-- keeps being tracked, and stays out of the tree until Unfreeze).
	self.NewSinceFreeze = setmetatable({}, { __mode = "k" })
	self._marked = {} -- node -> true: marked Gone while frozen
	self._freezeWatch = nil

	self.Root = { Obj = game, Depth = -1, Name = "game", Class = "DataModel", Conns = {}, Expanded = true }
	self.Nodes[game] = self.Root
	self.NilNode = {
		Obj = nil,
		IsNil = true,
		Depth = 0,
		Name = "Nil Instances",
		Class = "Nil",
		Conns = {},
		Seq = math.huge,
	}
	self.ShowNil = getnilinstances ~= nil

	self.Bin:Add(Settings.Changed:Connect(function(key, value)
		if key == "ExplorerSort" then
			self:SetSorting(value ~= false)
		end
	end))
	return self
end

----------------------------------------------------------------------
-- Change notification (batched to one redraw per frame)
----------------------------------------------------------------------

function Tree:_changed()
	if self._queued or self._dead then
		return
	end
	self._queued = true
	task.defer(function()
		self._queued = false
		if not self._dead then
			self.Changed:Fire()
		end
	end)
end

-- Tungsten's own ScreenGuis. The engine hands out the same reference for
-- an instance every time (only cloneref copies differ, and these are the
-- originals), so a lookup is enough; this runs for every loaded child.
function Tree:IsHidden(obj: Instance): boolean
	return self.Hidden[obj] == true
end

function Tree:Hide(obj: Instance)
	self.Hidden[obj] = true
	local node = self:Get(obj)
	if node then
		self:_detach(node)
		self:_changed()
	end
end

----------------------------------------------------------------------
-- Nodes
----------------------------------------------------------------------

function Tree:Get(obj: Instance?)
	if obj == nil then
		return nil
	end
	local node = self.Nodes[obj]
	if node then
		return node
	end
	if typeof(obj) ~= "Instance" or compareinstances == nil then
		return nil
	end
	-- A cloneref copy: look among the parent's loaded children.
	local parent = parentOf(obj)
	local parentNode = if parent then self.Nodes[parent] else self.NilNode
	if parentNode and parentNode.Children then
		for _, child in parentNode.Children do
			if same(child.Obj, obj) then
				return child
			end
		end
	end
	return nil
end

local function setDepth(node, depth: number)
	node.Depth = depth
	if node.Children then
		for _, child in node.Children do
			setDepth(child, depth + 1)
		end
	end
end

-- Takes a node out of its parent's child list (the node itself lives on).
local function unlink(node)
	local parent = node.Parent
	if parent and parent.Children then
		local index = table.find(parent.Children, node)
		if index then
			table.remove(parent.Children, index)
		end
	end
	node.Parent = nil
end

function Tree:_newNode(parentNode, obj: Instance)
	self._seq += 1
	local node = {
		Obj = obj,
		Parent = parentNode,
		Depth = parentNode.Depth + 1,
		Name = getName(obj),
		Class = getClass(obj),
		Conns = {},
		Seq = self._seq,
	}
	self.Nodes[obj] = node
	-- Renames re-sort the parent's children and redraw.
	local ok, connection = pcall(function()
		return obj:GetPropertyChangedSignal("Name"):Connect(function()
			node.Name = getName(obj)
			if node.Parent and not self.Frozen then
				node.Parent.Sorted = false -- (frozen: the order waits for Unfreeze)
			end
			self.Renamed:Fire(node)
			self:_changed()
		end)
	end)
	if ok then
		table.insert(node.Conns, connection)
	end
	self:_watchNil(node)
	return node
end

-- Nil-parented objects: notice when they get a parent again (the new
-- parent's ChildAdded re-links the node when that parent is loaded).
function Tree:_watchNil(node)
	if node.NilWatch then
		pcall(function()
			node.NilWatch:Disconnect()
		end)
		node.NilWatch = nil
	end
	if not (node.Parent and node.Parent.IsNil) then
		return
	end
	local obj = node.Obj
	local ok, connection = pcall(function()
		return obj.AncestryChanged:Connect(function(child)
			if child == obj and parentOf(obj) ~= nil and node.Parent == self.NilNode then
				if self.Frozen then
					self:_markGone(node, true)
				else
					self:_release(node)
				end
			end
		end)
	end)
	if ok then
		node.NilWatch = connection
		table.insert(node.Conns, connection)
	end
end

-- A child left its parent: hide it now, and drop it a frame later unless
-- it reappeared under another loaded parent (a move).
function Tree:_release(node)
	unlink(node)
	node.Pending = true
	self:_changed()
	task.defer(function()
		if node.Pending and not node.Removed then
			node.Pending = nil
			self:_detach(node)
			self:_changed()
		end
	end)
end

function Tree:_addChild(parentNode, obj: Instance)
	if self:IsHidden(obj) then
		return nil
	end
	local existing = self.Nodes[obj]
	if self.Frozen and not existing and self.NewSinceFreeze[obj] then
		return nil -- added after freezing: shown once the tree is unfrozen
	end
	if existing and not existing.Removed then
		if existing.Parent == parentNode then
			return existing
		end
		if self.Frozen then
			-- Frozen: a moved object keeps its row under the parent it had
			-- when the tree was frozen (light blue), even when the folder it
			-- went to is opened. Unfreezing moves it.
			return nil
		end
		-- Moved: keep the same node (selection, open state and search
		-- marks stay with it) under its new parent.
		unlink(existing)
		existing.Pending = nil
		self._seq += 1
		existing.Seq = self._seq -- the engine appends it to the new parent
		existing.Parent = parentNode
		setDepth(existing, parentNode.Depth + 1)
		table.insert(parentNode.Children, existing)
		parentNode.Sorted = false
		self:_watchNil(existing)
		return existing
	end
	local node = self:_newNode(parentNode, obj)
	table.insert(parentNode.Children, node)
	parentNode.Sorted = false
	return node
end

local function disconnect(list: { any }?)
	if not list then
		return
	end
	for _, connection in list do
		pcall(function()
			connection:Disconnect()
		end)
	end
	table.clear(list)
end

-- Removes a node and everything below it from the model.
function Tree:_detach(node)
	local parent = node.Parent
	if parent and parent.Children then
		local index = table.find(parent.Children, node)
		if index then
			table.remove(parent.Children, index)
		end
	end
	local function drop(n)
		disconnect(n.Conns)
		disconnect(n.ChildConns)
		self:_unwatchGone(n)
		self._marked[n] = nil
		if n.Children then
			for _, child in n.Children do
				drop(child)
			end
		end
		if n.Obj and self.Nodes[n.Obj] == n then
			self.Nodes[n.Obj] = nil
		end
		n.Removed = true
		self.Removed:Fire(n)
	end
	drop(node)
	node.Parent = nil
end

-- Loads a node's children (once) and starts watching them.
function Tree:Load(node)
	if node.Loaded or node.Removed then
		return
	end
	node.Loaded = true
	node.Children = {}
	node.ChildConns = node.ChildConns or {}
	if node.IsNil then
		local ok, list = pcall(getnilinstances)
		if ok and type(list) == "table" then
			for _, obj in list do
				if typeof(obj) == "Instance" and obj ~= game and parentOf(obj) == nil then
					self:_addChild(node, obj)
				end
			end
		end
		node.Sorted = false
		return
	end
	local obj = node.Obj
	local ok, children = pcall(function()
		return obj:GetChildren()
	end)
	if ok then
		for _, child in children do
			self:_addChild(node, child)
		end
	end
	local okAdded, added = pcall(function()
		return obj.ChildAdded:Connect(function(child)
			if node.Removed then
				return
			end
			if self.Frozen then
				-- Nothing new appears; an object that came back to where its
				-- row still is stops being gone.
				local existing = self.Nodes[child]
				if existing and existing.Parent == node and existing.Gone then
					self:_markGone(existing, false)
				end
				return
			end
			if self:_addChild(node, child) then
				self.Added:Fire(child)
				self:_changed()
			end
		end)
	end)
	if okAdded then
		table.insert(node.ChildConns, added)
	end
	local okRemoved, removed = pcall(function()
		return obj.ChildRemoved:Connect(function(child)
			local childNode = self.Nodes[child]
			if childNode and childNode.Parent == node then
				if self.Frozen then
					self:_markGone(childNode, true) -- stays in place, shown red
				else
					self:_release(childNode)
				end
			end
		end)
	end)
	if okRemoved then
		table.insert(node.ChildConns, removed)
	end
end

-- Forgets a node's children (they load again when needed).
function Tree:Unload(node)
	if not node.Loaded then
		return
	end
	for _, child in table.clone(node.Children or {}) do
		self:_detach(child)
	end
	disconnect(node.ChildConns)
	node.Loaded = false
	node.Children = nil
	self:_changed()
end

-- The nil node: reload (Refresh) or empty and close (Hide).
function Tree:RefreshNil()
	self:Unload(self.NilNode)
	self:Load(self.NilNode)
	self.NilNode.Expanded = true
	self:_changed()
end

function Tree:HideNil()
	self:Unload(self.NilNode)
	self.NilNode.Expanded = false
	self:_changed()
end

-- Whether a node has children (without loading them).
function Tree:HasChildren(node): boolean
	if node.Loaded then
		return #node.Children > 0
	end
	if node.IsNil then
		return true
	end
	local ok, child = pcall(function()
		return node.Obj:FindFirstChildWhichIsA("Instance")
	end)
	if ok then
		return child ~= nil
	end
	local okList, list = pcall(function()
		return node.Obj:GetChildren()
	end)
	return okList and #list > 0
end

-- The node for an instance, loading the path down to it. nil when the
-- instance is hidden, destroyed or outside the game and nil roots.
function Tree:NodeFor(obj: Instance?)
	if typeof(obj) ~= "Instance" or same(obj, game) then
		return nil -- game itself has no row; its children are the top level
	end
	local found = self:Get(obj)
	if found then
		return found
	end
	local chain = {}
	local current: Instance? = obj
	local guard = 0
	while current ~= nil and not same(current, game) and guard < 400 do
		guard += 1
		table.insert(chain, 1, current)
		current = parentOf(current :: Instance)
	end
	local node = if current ~= nil then self.Root else self.NilNode
	if node.IsNil and not self.ShowNil then
		return nil
	end
	for index, link in chain do
		if self:IsHidden(link) then
			return nil
		end
		self:Load(node)
		local nextNode = self:Get(link)
		if not nextNode and node.IsNil and index == 1 then
			-- Not in the loaded nil list: add it only if the executor lists it
			-- now (a destroyed object is not something to show).
			local okList, list = pcall(getnilinstances)
			if okList and type(list) == "table" then
				for _, item in list do
					if same(item, link) then
						nextNode = self:_addChild(node, link)
						break
					end
				end
			end
		end
		if not nextNode then
			return nil
		end
		node = nextNode
	end
	return node
end

-- Ancestor nodes from the top down (not including the node).
function Tree:Ancestors(node): { any }
	local list = {}
	local current = node.Parent
	while current and current ~= self.Root do
		table.insert(list, 1, current)
		current = current.Parent
	end
	return list
end

----------------------------------------------------------------------
-- Freezing
----------------------------------------------------------------------

-- What happened to a marked node's object since freezing: "deleted" (it
-- has no parent now) or "moved" (it is somewhere else).
local function goneKind(node): string
	return if node.Obj ~= nil and parentOf(node.Obj) ~= nil then "moved" else "deleted"
end

function Tree:_unwatchGone(node)
	if node.GoneWatch then
		pcall(function()
			node.GoneWatch:Disconnect()
		end)
		node.GoneWatch = nil
	end
end

-- Marks (or unmarks) a node whose object left its place while frozen.
-- The object is watched, so the mark follows it: moved and then
-- destroyed becomes "deleted", deleted and then put elsewhere "moved".
function Tree:_markGone(node, gone: boolean)
	gone = gone == true
	if not gone then
		if node.Gone then
			node.Gone = nil
			node.GoneKind = nil
			self._marked[node] = nil
			self:_unwatchGone(node)
			self:_changed()
		end
		return
	end
	node.Gone = true
	node.GoneKind = goneKind(node)
	self._marked[node] = true
	if not node.GoneWatch and node.Obj then
		local ok, connection = pcall(function()
			return node.Obj.AncestryChanged:Connect(function()
				if node.Gone and self.Frozen then
					local kind = goneKind(node)
					if kind ~= node.GoneKind then
						node.GoneKind = kind
						self:_changed()
					end
				end
			end)
		end)
		if ok then
			node.GoneWatch = connection
		end
	end
	self:_changed()
end

--[[
	How a row looks while frozen (nil when nothing happened to it):
		"deleted"         the object was deleted                      red
		"inside_deleted"  it was in something that was deleted         light red
		"moved"           the object was put somewhere else            light blue
		"inside_moved"    it was in something that was moved           light blue
	A child moved out of something deleted is "moved": it still exists.
]]
function Tree:FrozenState(node): string?
	if not self.Frozen or not node then
		return nil
	end
	local own = if node.Gone then node.GoneKind else nil
	if own == "moved" then
		return "moved"
	end
	local current = node.Parent
	while current and current ~= self.Root do
		if current.Gone then
			return if current.GoneKind == "moved" and own ~= "deleted" then "inside_moved"
				elseif current.GoneKind == "moved" then "deleted"
				else "inside_deleted"
		end
		current = current.Parent
	end
	return own
end

-- Whether a row shows as gone (any of the states above).
function Tree:IsGone(node): boolean
	return self:FrozenState(node) ~= nil
end

-- How many marked objects there are, by what happened to them (the
-- outermost ones only: what is inside them isn't counted again).
function Tree:FrozenCounts(): { Deleted: number, Moved: number }
	local counts = { Deleted = 0, Moved = 0 }
	for node in self._marked do
		if node.Removed or not node.Gone then
			continue
		end
		local state = self:FrozenState(node)
		if state == "deleted" then
			counts.Deleted += 1
		elseif state == "moved" then
			counts.Moved += 1
		end
	end
	return counts
end

-- Every loaded node, parents before children.
function Tree:_loadedNodes(): { any }
	local list = {}
	local function walk(node)
		if node.Loaded and not node.Removed then
			table.insert(list, node)
			for _, child in node.Children do
				walk(child)
			end
		end
	end
	walk(self.Root)
	walk(self.NilNode)
	return list
end

-- Brings every loaded node's children in line with the game.
function Tree:_resync()
	local loaded = self:_loadedNodes()
	-- Adds and moves first, so a moved object keeps its node (and with it
	-- its selection and open state) at its new place.
	for _, node in loaded do
		if not node.IsNil and not node.Removed then
			local ok, children = pcall(function()
				return node.Obj:GetChildren()
			end)
			if ok then
				for _, child in children do
					local existed = self.Nodes[child] ~= nil and not self.Nodes[child].Removed
					local added = self:_addChild(node, child)
					if added and not existed then
						self.Added:Fire(child)
					end
				end
			end
		end
	end
	-- Then whatever is no longer where its row is.
	for _, node in loaded do
		if node.Removed or not node.Children then
			continue
		end
		for _, child in table.clone(node.Children) do
			if child.Removed or not child.Obj then
				continue
			end
			local parent = parentOf(child.Obj)
			local stays = if node.IsNil then parent == nil else (parent ~= nil and same(parent, node.Obj))
			if not stays then
				self:_detach(child)
			end
		end
		node.Sorted = false
	end
	self.Root.Sorted = false
	self.NilNode.Sorted = false
end

-- Freeze or unfreeze. Returns whether anything changed.
function Tree:SetFrozen(on: boolean): boolean
	on = on == true
	if on == self.Frozen then
		return false
	end
	self.Frozen = on
	if on then
		-- Keep track of everything added from now on (the game keeps
		-- changing; the tree just doesn't show it yet).
		table.clear(self.NewSinceFreeze)
		local ok, connection = pcall(function()
			return game.DescendantAdded:Connect(function(obj)
				self.NewSinceFreeze[obj] = true
			end)
		end)
		self._freezeWatch = if ok then connection else nil
	else
		if self._freezeWatch then
			pcall(function()
				self._freezeWatch:Disconnect()
			end)
			self._freezeWatch = nil
		end
		table.clear(self.NewSinceFreeze)
		self:_resync()
		for node in self._marked do
			node.Gone = nil
			node.GoneKind = nil
			self:_unwatchGone(node)
		end
		table.clear(self._marked)
	end
	self.FrozenChanged:Fire(on)
	self:_changed()
	return true
end

----------------------------------------------------------------------
-- Order
----------------------------------------------------------------------

function Tree:SetSorting(on: boolean)
	if on == self.Sorting then
		return
	end
	self.Sorting = on
	local function mark(node)
		node.Sorted = false
		if node.Children then
			for _, child in node.Children do
				mark(child)
			end
		end
	end
	mark(self.Root)
	mark(self.NilNode)
	self:_changed()
end

local function compareSorted(a, b): boolean
	local ra, rb = SERVICE_RANK[a.Class] or 1000, SERVICE_RANK[b.Class] or 1000
	if a.Depth == 0 and ra ~= rb then
		return ra < rb
	end
	local na, nb = a.Name:lower(), b.Name:lower()
	if na ~= nb then
		return na < nb
	end
	if a.Class ~= b.Class then
		return a.Class < b.Class
	end
	return a.Seq < b.Seq
end

local function compareSeq(a, b): boolean
	return a.Seq < b.Seq
end

function Tree:_sort(node)
	if node.Sorted or not node.Children then
		return
	end
	table.sort(node.Children, if self.Sorting then compareSorted else compareSeq)
	node.Sorted = true
end

----------------------------------------------------------------------
-- Rows
----------------------------------------------------------------------

--[[
	Flatten(filter) -> rows (nodes in drawing order)
	filter (search mode): { Match = {[node]=true}, Keep = {[node]=true},
	Closed = {[node]=true} }. Kept nodes (ancestors of matches) are shown
	open unless closed; a match the user opens shows all its children.
]]
function Tree:Flatten(filter)
	local rows = {}
	local count = 0
	local function walk(node, filtered: boolean)
		self:_sort(node)
		local hide = self.HideTest
		for _, child in node.Children do
			if hide and child.Obj and not child.IsNil and hide(child.Obj, child.Class) then
				continue
			end
			local keep = filter and filter.Keep[child]
			local match = filter and filter.Match[child]
			if filtered and not keep and not match then
				continue
			end
			count += 1
			rows[count] = child
			if filtered and keep and not (filter :: any).Closed[child] then
				if child.Loaded then
					walk(child, true)
				end
			elseif child.Expanded and child.Loaded then
				walk(child, false)
			end
		end
	end
	self:Load(self.Root)
	walk(self.Root, filter ~= nil)
	if self.ShowNil then
		local nilNode = self.NilNode
		local visible = filter == nil or filter.Keep[nilNode] or filter.Match[nilNode]
		if visible then
			count += 1
			rows[count] = nilNode
			local open = if filter and filter.Keep[nilNode] then not filter.Closed[nilNode] else nilNode.Expanded
			if open and nilNode.Loaded then
				walk(nilNode, filter ~= nil and filter.Keep[nilNode] == true)
			end
		end
	end
	return rows
end

function Tree:Destroy()
	self._dead = true
	self:_detach(self.NilNode)
	if self.Root.Children then
		for _, child in table.clone(self.Root.Children) do
			self:_detach(child)
		end
	end
	disconnect(self.Root.ChildConns)
	table.clear(self.Nodes)
	self.Bin:Clean()
	self.Changed:DisconnectAll()
	self.Removed:DisconnectAll()
	self.Renamed:DisconnectAll()
	self.Added:DisconnectAll()
	self.FrozenChanged:DisconnectAll()
	if self._freezeWatch then
		pcall(function()
			self._freezeWatch:Disconnect()
		end)
		self._freezeWatch = nil
	end
end

return Tree
