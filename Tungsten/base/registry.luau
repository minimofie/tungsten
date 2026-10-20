--[[
	Tungsten · base/registry
	The tabs in the side bar. Built-in tabs and plugin tabs register the
	same way; the tab bar follows every change.

		Registry.addTab({
			Id = "mytab", Title = "My Tab",
			Icon = "myplugin.gear",           -- an icon name (base/data/icons), or a
			                                  -- source: a file, rbxassetid://…, sprite
			Order = 10,                       -- position among its group
			Owner = "myplugin",               -- removed with the plugin
			Tooltip = "What it does",         -- shown on hover (default: Title)
			Badge = 3,                        -- a number or short text on the icon
			Build = function(page, T, tab) end,     -- the first time it opens
			OnSelect = function(tab) end,     -- each time it opens
			OnDeselect = function(tab) end,   -- each time another tab opens
			OnLoad = function(instances, tab) end,  -- explorer › Load sent objects here
			MenuItems = function(ctx) return { entries } end,  -- its right-click entries
			Closable = true,                  -- the user may hide it (plugin tabs)
		})
		Registry.updateTab("mytab", { Title = "…", Icon = "…", Badge = 5 })
		Registry.removeTab("mytab") ; Registry.removeOwner("myplugin")

	Built-in tabs (Builtin = true) come first; a line separates them from
	the others. The user's order (Move up / Move down) and hidden tabs are
	kept in the settings.
]]

local T = ...
local signal = T.import("base/signal")

local Registry = {}
Registry.TabAdded = signal.new() -- (tab)
Registry.TabRemoved = signal.new() -- (tab)
Registry.TabChanged = signal.new() -- (tab, changedFields)

local tabs: { [string]: any } = {}
local seq = 0

local UPDATABLE = { Title = true, Icon = true, Order = true, Tooltip = true, Badge = true, MenuItems = true, OnSelect = true, OnDeselect = true, OnLoad = true, Closable = true }

local function settings()
	local ok, Settings = pcall(T.import, "base/settings")
	return if ok then Settings else nil
end

function Registry.addTab(definition)
	assert(type(definition) == "table", "tab definition must be a table")
	local id = definition.Id
	assert(type(id) == "string" and #id > 0, "tab needs a string Id")
	assert(type(definition.Title) == "string", ("tab '%s' needs a string Title"):format(id))
	assert(definition.Build == nil or type(definition.Build) == "function", ("tab '%s' Build must be a function"):format(id))
	assert(definition.Icon == nil or type(definition.Icon) == "string" or type(definition.Icon) == "table", ("tab '%s' Icon must be a name or a source"):format(id))
	if tabs[id] then
		error(("a tab with id '%s' already exists"):format(id), 2)
	end
	seq += 1
	local tab = {
		Id = id,
		Title = definition.Title,
		Icon = definition.Icon or "dummy",
		Order = tonumber(definition.Order) or 100,
		Builtin = definition.Builtin == true,
		Build = definition.Build,
		Owner = definition.Owner or (if definition.Builtin then "core" else nil),
		Tooltip = definition.Tooltip,
		Badge = definition.Badge,
		OnSelect = definition.OnSelect,
		OnDeselect = definition.OnDeselect,
		OnLoad = definition.OnLoad,
		MenuItems = definition.MenuItems,
		Closable = if definition.Closable ~= nil then definition.Closable == true else definition.Builtin ~= true,
		Seq = seq,
	}
	-- An icon given as a source (a table or a file) gets a name.
	if type(tab.Icon) == "table" or (type(tab.Icon) == "string" and (tab.Icon:find("://", 1, true) or tab.Icon:match("%.png$"))) then
		local Icons = T.import("base/data/icons")
		tab.Icon = Icons.register("tab." .. id, tab.Icon, { Owner = tab.Owner or "core" })
	end
	tabs[id] = tab
	T.Log.debug("registry", "tab added: " .. id)
	Registry.TabAdded:Fire(tab)
	return tab
end

function Registry.updateTab(id: string, fields: { [string]: any }): boolean
	local tab = tabs[id]
	if not tab then
		return false
	end
	local changed = {}
	for key, value in fields do
		if UPDATABLE[key] then
			if key == "Icon" and (type(value) == "table" or (type(value) == "string" and (value:find("://", 1, true) or value:match("%.png$")))) then
				local Icons = T.import("base/data/icons")
				value = Icons.register("tab." .. id, value, { Owner = tab.Owner or "core" })
			end
			if key == "Order" then
				value = tonumber(value) or tab.Order
			end
			tab[key] = value
			changed[key] = true
		end
	end
	if next(changed) then
		Registry.TabChanged:Fire(tab, changed)
	end
	return true
end

function Registry.removeTab(id: string): boolean
	local tab = tabs[id]
	if not tab then
		return false
	end
	tabs[id] = nil
	T.Log.debug("registry", "tab removed: " .. id)
	Registry.TabRemoved:Fire(tab)
	return true
end

function Registry.removeOwner(owner: string): number
	local count = 0
	for id, tab in table.clone(tabs) do
		if tab.Owner == owner and not tab.Builtin then
			Registry.removeTab(id)
			count += 1
		end
	end
	return count
end

function Registry.getTab(id: string)
	return tabs[id]
end

-- The user's own order (from Move up / down): id -> position.
local function userOrder(): { [string]: number }
	local Settings = settings()
	local saved = if Settings then Settings.get("TabOrder") else nil
	local order = {}
	if type(saved) == "table" then
		for index, id in saved do
			if type(id) == "string" then
				order[id] = index
			end
		end
	end
	return order
end

function Registry.isHidden(id: string): boolean
	local Settings = settings()
	local hidden = if Settings then Settings.get("HiddenTabs") else nil
	return type(hidden) == "table" and table.find(hidden, id) ~= nil
end

local function sorted(includeHidden: boolean?): { any }
	local list = {}
	for _, tab in tabs do
		if includeHidden or not Registry.isHidden(tab.Id) then
			table.insert(list, tab)
		end
	end
	local custom = userOrder()
	table.sort(list, function(a, b)
		if a.Builtin ~= b.Builtin then
			return a.Builtin
		end
		local ca, cb = custom[a.Id], custom[b.Id]
		if ca and cb and ca ~= cb then
			return ca < cb
		elseif ca ~= nil and cb == nil then
			return true
		elseif cb ~= nil and ca == nil then
			return false
		end
		if a.Order ~= b.Order then
			return a.Order < b.Order
		end
		if a.Title ~= b.Title then
			return a.Title < b.Title
		end
		return a.Seq < b.Seq
	end)
	return list
end

-- Built-in tabs first, then everything else; each group in the user's
-- order, then by Order and Title. Hidden tabs are left out.
function Registry.listTabs(): { any }
	return sorted(false)
end

function Registry.allTabs(): { any }
	return sorted(true)
end

-- Moves a tab one place up (-1) or down (1) within its group.
function Registry.move(id: string, delta: number): boolean
	local tab = tabs[id]
	local Settings = settings()
	if not tab or not Settings then
		return false
	end
	local group = {}
	for _, other in sorted(true) do
		if other.Builtin == tab.Builtin then
			table.insert(group, other.Id)
		end
	end
	local index = table.find(group, id)
	local target = index and index + delta
	if not index or target < 1 or target > #group then
		return false
	end
	group[index], group[target] = group[target], group[index]
	-- Keep the other group's saved order.
	local saved = {}
	for _, other in sorted(true) do
		if other.Builtin ~= tab.Builtin then
			table.insert(saved, other.Id)
		end
	end
	for _, other in group do
		table.insert(saved, other)
	end
	Settings.set("TabOrder", saved)
	Registry.TabChanged:Fire(tab, { Order = true })
	return true
end

function Registry.setHidden(id: string, hidden: boolean): boolean
	local tab = tabs[id]
	local Settings = settings()
	if not tab or not Settings then
		return false
	end
	if hidden and not tab.Closable then
		return false
	end
	local list = Settings.get("HiddenTabs") or {}
	local at = table.find(list, id)
	if hidden and not at then
		table.insert(list, id)
	elseif not hidden and at then
		table.remove(list, at)
	else
		return true
	end
	Settings.set("HiddenTabs", list)
	Registry.TabChanged:Fire(tab, { Hidden = true })
	return true
end

T.Bin:Add(function()
	table.clear(tabs)
	for _, sig in { Registry.TabAdded, Registry.TabRemoved, Registry.TabChanged } do
		sig:DisconnectAll()
	end
end)

return Registry
