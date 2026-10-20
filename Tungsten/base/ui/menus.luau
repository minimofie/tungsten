--[[
	Tungsten · base/ui/menus
	The menu framework. Every right-click menu and button menu in Tungsten
	is a *named menu*: a list of sections that entries are added to. A menu
	is built fresh each time it opens, from a *context* (whatever the
	opener knows: the selection, the line under the mouse, ...), so entries
	can decide their own text, state and visibility. ContextMenu draws the
	result; the look never changes.

	Defining a menu (Tungsten parts and plugins alike)
		Menus.define("console.output", {
			Title = "Console output",               -- for /menus
			Header = function(ctx) return "3 lines" end,   -- optional top header
			Sections = {                            -- in order; separators between
				{ Id = "lines", Header = function(ctx) ... end },
				{ Id = "console", Header = "Console" },
			},
			Empty = "Nothing here",                 -- text or function(ctx)
			Locked = false,                         -- true: only core may add entries
			Owner = "core",                         -- plugins pass their id
			Source = "explorer",                    -- optional: whose console name
			                                        -- Tungsten's own faults print under
		})

	Adding entries (any number of owners may add to one menu)
		local handle = Menus.add("console.output", {
			Id = "copy", Section = "lines", Order = 10,     -- no Section: the first one
			Text = "Copy", Icon = "copy", Shortcut = "Ctrl+C",
			IconColor = "Accent",                           -- optional icon tint
			When = function(ctx) return ctx.Line ~= nil end,    -- shown at all?
			Disabled = function(ctx) return #ctx.Selected == 0 end,
			Callback = function(ctx, item) ... end,
		}, "myplugin")
		handle:Remove()

		Every field except Id, Section, Order, Callback, When and Provide may
		be a value or a function(ctx). Other entry shapes:
			{ Checked = function(ctx) ... end, Callback = function(ctx, item) end }
			                                -- check item; item.Checked is the new state
			{ Menu = "explorer.function" }  -- a submenu that is another named menu
			{ Items = function(ctx) return { entries } end }  -- an inline submenu
			{ Provide = function(ctx) return { entries } end } -- several entries at once
			{ Include = "editor" }          -- all of another menu's entries, here
			{ Kind = "slider", ... }        -- a custom row kind (ContextMenu.addKind)

	Opening
		Menus.open("console.output", ctx, { Position = point })
		Menus.build("console.output", ctx)  -> the items ContextMenu draws

	Cleanup
		Menus.removeOwner("myplugin")  -- its entries and the menus it defined
]]

local T = ...
local signal = T.import("base/signal")
local ContextMenu = T.import("base/ui/components/contextmenu")

local Menus = {}
Menus.Opened = signal.new() -- (menuId, ctx, menuObject)
Menus.Changed = signal.new() -- (menuId)

local definitions: { [string]: any } = {}
local seq = 0
local currentSource: string? = nil -- the Source of the menu being built

-- A fault in an entry: printed for plugins (and menus with a Source),
-- logged for the rest. Identical repeats are folded by the reporter.
local function warnOwner(owner: string?, text: string)
	T.Log.warn("menus", (if owner then "[" .. owner .. "] " else "") .. text)
	if owner and owner ~= "core" then
		local ok, Reporter = pcall(T.import, "console/reporter")
		if ok then
			Reporter.ownerFault(owner, "a menu entry", text)
		end
	end
end

local function reportAs(owner: string?): string?
	if owner and owner ~= "core" then
		return owner
	end
	return currentSource
end

-- A value, or a function(ctx) that gives it (errors give `fallback`).
local function resolve(value: any, ctx: any, fallback: any, owner: string?)
	if type(value) ~= "function" then
		return value
	end
	local ok, result = pcall(value, ctx)
	if not ok then
		warnOwner(owner, "menu field failed: " .. tostring(result))
		return fallback
	end
	return result
end
Menus.resolve = resolve

----------------------------------------------------------------------
-- Definitions
----------------------------------------------------------------------

local function normalizeSections(list): { any }
	local out = {}
	for index, section in list or {} do
		if type(section) == "string" then
			section = { Id = section }
		end
		assert(type(section) == "table" and type(section.Id) == "string", "a section needs an Id")
		table.insert(out, { Id = section.Id, Header = section.Header, Index = index })
	end
	if #out == 0 then
		table.insert(out, { Id = "main", Index = 1 })
	end
	return out
end

function Menus.define(id: string, definition: { [string]: any }?)
	assert(type(id) == "string" and id ~= "", "a menu needs an id")
	definition = definition or {}
	local owner = (definition :: any).Owner or "core"
	local existing = definitions[id]
	if existing then
		if existing.Owner ~= owner then
			error(("menu '%s' already belongs to %s"):format(id, existing.Owner), 2)
		end
		-- Redefining keeps the entries (a module reloading its menu).
		existing.Title = definition.Title or existing.Title
		existing.Header = definition.Header
		existing.Sections = normalizeSections(definition.Sections)
		existing.Empty = definition.Empty
		existing.Locked = definition.Locked == true
		existing.Source = definition.Source
		Menus.Changed:Fire(id)
		return existing
	end
	local menu = {
		Id = id,
		Title = definition.Title or id,
		Header = definition.Header,
		Sections = normalizeSections(definition.Sections),
		Empty = definition.Empty,
		Locked = definition.Locked == true,
		Source = definition.Source,
		Owner = owner,
		Entries = {},
	}
	definitions[id] = menu
	Menus.Changed:Fire(id)
	return menu
end

function Menus.exists(id: string): boolean
	return definitions[id] ~= nil
end

function Menus.get(id: string)
	return definitions[id]
end

-- Every menu id, sorted.
function Menus.list(): { string }
	local ids = {}
	for id in definitions do
		table.insert(ids, id)
	end
	table.sort(ids)
	return ids
end

----------------------------------------------------------------------
-- Entries
----------------------------------------------------------------------

local Handle = {}
Handle.__index = Handle

function Handle:Remove()
	return Menus.remove(self.Menu, self.Id, self.Owner)
end

--[[
	Menus.add(menuId, entry, owner?) -> handle
	owner defaults to entry.Owner or "core". Entries with the same Id and
	owner replace each other.
]]
function Menus.add(menuId: string, entry: { [string]: any }, owner: string?)
	local menu = definitions[menuId]
	if not menu then
		error(("no menu '%s' · Menus.define it first"):format(tostring(menuId)), 2)
	end
	assert(type(entry) == "table", "a menu entry must be a table")
	owner = owner or entry.Owner or "core"
	if menu.Locked and owner ~= "core" and owner ~= menu.Owner then
		error(("the menu '%s' is fixed and can't be changed by %s"):format(menuId, tostring(owner)), 2)
	end
	seq += 1
	local stored = table.clone(entry)
	stored.Owner = owner
	stored.Id = entry.Id or ("entry" .. seq)
	stored.Order = tonumber(entry.Order) or 100
	stored.Seq = seq
	-- Same id + owner: replace.
	for index, other in menu.Entries do
		if other.Id == stored.Id and other.Owner == owner then
			table.remove(menu.Entries, index)
			break
		end
	end
	table.insert(menu.Entries, stored)
	Menus.Changed:Fire(menuId)
	return setmetatable({ Menu = menuId, Id = stored.Id, Owner = owner }, Handle)
end

-- Several entries at once (the same owner).
function Menus.addMany(menuId: string, entries: { any }, owner: string?): { any }
	local handles = {}
	for _, entry in entries do
		table.insert(handles, Menus.add(menuId, entry, owner))
	end
	return handles
end

function Menus.remove(menuId: string, entryId: string, owner: string?): boolean
	local menu = definitions[menuId]
	if not menu then
		return false
	end
	for index, entry in menu.Entries do
		if entry.Id == entryId and (owner == nil or entry.Owner == owner) then
			table.remove(menu.Entries, index)
			Menus.Changed:Fire(menuId)
			return true
		end
	end
	return false
end

-- Removes an owner's entries everywhere and the menus it defined.
function Menus.removeOwner(owner: string): number
	local removed = 0
	for id, menu in table.clone(definitions) do
		if menu.Owner == owner then
			definitions[id] = nil
			removed += 1
			Menus.Changed:Fire(id)
		else
			for index = #menu.Entries, 1, -1 do
				if menu.Entries[index].Owner == owner then
					table.remove(menu.Entries, index)
					removed += 1
				end
			end
		end
	end
	return removed
end

-- Entries of a menu (copies), for /menus and the documentation.
function Menus.entries(menuId: string): { any }
	local menu = definitions[menuId]
	if not menu then
		return {}
	end
	local list = {}
	for _, entry in menu.Entries do
		table.insert(list, table.clone(entry))
	end
	table.sort(list, function(a, b)
		if a.Section ~= b.Section then
			return tostring(a.Section) < tostring(b.Section)
		end
		if a.Order ~= b.Order then
			return a.Order < b.Order
		end
		return a.Seq < b.Seq
	end)
	return list
end

----------------------------------------------------------------------
-- Building
----------------------------------------------------------------------

local convertList

-- One framework entry -> one item for ContextMenu (nil when hidden).
local function convert(entry, ctx, owner: string?)
	owner = reportAs(entry.Owner or owner)
	if entry.When ~= nil and resolve(entry.When, ctx, false, owner) ~= true then
		return nil
	end
	if entry.Visible ~= nil and resolve(entry.Visible, ctx, false, owner) == false then
		return nil
	end
	if entry.Separator then
		return { Separator = true }
	end
	if entry.Header ~= nil then
		local text = resolve(entry.Header, ctx, nil, owner)
		return if text then { Header = tostring(text) } else nil
	end
	local item = {
		Text = tostring(resolve(entry.Text, ctx, "?", owner) or ""),
		Icon = resolve(entry.Icon, ctx, nil, owner),
		IconColor = resolve(entry.IconColor, ctx, nil, owner),
		Shortcut = resolve(entry.Shortcut, ctx, nil, owner),
		Danger = resolve(entry.Danger, ctx, false, owner) == true,
		Emphasis = resolve(entry.Emphasis, ctx, false, owner) == true,
		Kind = entry.Kind,
		Data = entry.Data,
		Id = entry.Id,
		Owner = owner,
	}
	local disabled = resolve(entry.Disabled, ctx, true, owner) == true
	if entry.Enabled ~= nil and resolve(entry.Enabled, ctx, false, owner) ~= true then
		disabled = true
	end
	item.Disabled = disabled
	if entry.Checked ~= nil then
		item.Checked = resolve(entry.Checked, ctx, false, owner) == true
	end
	-- Custom kinds get every other field too.
	if entry.Kind then
		for key, value in entry do
			if item[key] == nil and key ~= "When" and key ~= "Callback" then
				item[key] = resolve(value, ctx, nil, owner)
			end
		end
	end
	if entry.Menu then
		local subId = entry.Menu
		item.Items = function()
			return Menus.build(subId, ctx)
		end
	elseif entry.Items ~= nil then
		local source = entry.Items
		item.Items = function()
			local list = if type(source) == "function" then resolve(source, ctx, {}, owner) else source
			return convertList(list or {}, ctx, owner)
		end
	end
	if entry.Callback then
		local callback = entry.Callback
		item.Callback = function(rendered)
			local ok, err = xpcall(callback, debug.traceback, ctx, rendered)
			if not ok then
				T.Log.error("menus", ("[%s] '%s' failed:\n%s"):format(tostring(owner), item.Text, tostring(err)))
				local okImport, Reporter = pcall(T.import, "console/reporter")
				if okImport then
					Reporter.ownerFault(owner, ("'%s'"):format(item.Text), err)
				end
			end
		end
	end
	return item
end

-- A list of entries (Provide results, inline submenus).
convertList = function(list, ctx, owner: string?): { any }
	local out = {}
	for _, entry in list do
		if type(entry) == "table" then
			if entry.Include then
				local included = definitions[entry.Include]
				local shown = entry.When == nil or resolve(entry.When, ctx, false, entry.Owner or owner) == true
				if included and shown and not (ctx._including or {})[entry.Include] then
					-- Guard against menus including each other.
					ctx._including = ctx._including or {}
					ctx._including[entry.Include] = true
					local built = Menus.build(entry.Include, ctx, true)
					ctx._including[entry.Include] = nil
					for _, item in built do
						table.insert(out, item)
					end
				end
			elseif entry.Provide then
				local provided = resolve(entry.Provide, ctx, {}, entry.Owner or owner)
				for _, item in convertList(provided or {}, ctx, entry.Owner or owner) do
					table.insert(out, item)
				end
			else
				local item = convert(entry, ctx, owner)
				if item then
					table.insert(out, item)
				end
			end
		end
	end
	return out
end
Menus.convert = convertList

-- Drops leading, trailing and doubled separators.
local function tidy(items: { any }): { any }
	local out = {}
	for _, item in items do
		if item.Separator then
			local last = out[#out]
			if last and not last.Separator and not last.Header then
				table.insert(out, item)
			end
		else
			table.insert(out, item)
		end
	end
	while out[#out] and out[#out].Separator do
		table.remove(out)
	end
	return out
end

--[[
	Menus.build(menuId, ctx) -> items for ContextMenu.open
	Sections in their order; entries by Order (then by when they were
	added). A separator goes between sections that have items, and a
	section's Header (if any) above its items.
]]
function Menus.build(menuId: string, ctx: any?, included: boolean?): { any }
	local menu = definitions[menuId]
	if not menu then
		return { { Text = ("no menu '%s'"):format(tostring(menuId)), Disabled = true } }
	end
	ctx = ctx or {}
	local previousSource = currentSource
	currentSource = menu.Source or (if menu.Owner ~= "core" then menu.Owner else nil)
	local ok, result = pcall(Menus._build, menu, ctx, included)
	currentSource = previousSource
	if not ok then
		error(result, 0)
	end
	return result
end

function Menus._build(menu, ctx, included: boolean?): { any }
	local bySection = {}
	local known = {}
	for _, section in menu.Sections do
		known[section.Id] = true
		bySection[section.Id] = {}
	end
	-- No Section: the first section. A section the menu doesn't have: the last.
	local firstId = menu.Sections[1].Id
	local lastId = menu.Sections[#menu.Sections].Id
	for _, entry in menu.Entries do
		local sectionId = if entry.Section == nil then firstId elseif known[entry.Section] then entry.Section else lastId
		table.insert(bySection[sectionId], entry)
	end

	local out = {}
	local header = if included then nil else resolve(menu.Header, ctx, nil, menu.Owner)
	if header then
		table.insert(out, { Header = tostring(header) })
	end
	local hasItems = false
	for _, section in menu.Sections do
		local entries = bySection[section.Id]
		table.sort(entries, function(a, b)
			if a.Order ~= b.Order then
				return a.Order < b.Order
			end
			return a.Seq < b.Seq
		end)
		local items = tidy(convertList(entries, ctx, nil))
		if #items > 0 then
			if hasItems then
				table.insert(out, { Separator = true })
			end
			local sectionHeader = resolve(section.Header, ctx, nil, menu.Owner)
			if sectionHeader then
				table.insert(out, { Header = tostring(sectionHeader) })
			end
			for _, item in items do
				table.insert(out, item)
			end
			hasItems = true
		end
	end
	if not hasItems and not included then
		local empty = resolve(menu.Empty, ctx, nil, menu.Owner) or "Nothing here"
		table.insert(out, { Text = tostring(empty), Disabled = true })
	end
	return out
end

--[[
	Menus.open(menuId, ctx, opts) -> the open ContextMenu
	opts as ContextMenu.open: Position (default: mouse), or AnchorPos +
	AnchorSize + Side, Owner, MinWidth, OnClose.
]]
function Menus.open(menuId: string, ctx: any?, opts: { [string]: any }?)
	ctx = ctx or {}
	opts = table.clone(opts or {})
	local definition = definitions[menuId]
	opts.Origin = opts.Origin or (if definition then definition.Owner else "core")
	local menu = ContextMenu.open(Menus.build(menuId, ctx), opts)
	menu.MenuId = menuId
	menu.Context = ctx
	Menus.Opened:Fire(menuId, ctx, menu)
	return menu
end

T.Bin:Add(function()
	table.clear(definitions)
	Menus.Opened:DisconnectAll()
	Menus.Changed:DisconnectAll()
end)

return Menus
