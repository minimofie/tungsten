--[[
	Script Viewer (prime plugin "scriptviewer")
	Looks into what is loaded: a LocalScript, a ModuleScript, a function
	or a table. Ships with Tungsten and starts off, like any plugin; turn
	it on in the Plugins tab.

	Parts (Plugins stage, round 1):
		1.1  the tab and what a loaded item is (lib/inspect), reveal
		1.2  Constants, Upvalues and Functions (Tree / List), read-only
		1.3  Source (decompiled, read-only) and Contents
		1.4  views: Tree, List (search, type filter), Table (as a Luau table);
		     scope with nested functions (revamp)
		1.5  references of constants and upvalues (filtergc)
		1.6  editing: right-click menu + forms, editable Table view, Undo
		1.7  links from the other plugins, menus, docs

	Exports (for plugins that list scriptviewer in Requires or Uses):
		reveal({ Target?, Panel? })  -- load Target (if given) and open Panel
		subject()                    -- what is shown now (lib/inspect)
		view()                       -- the tab's view once built (panels, rows)
]]

local P = ...

local Inspect = P.import("lib/inspect")
local View = P.import("lib/view")
local Actions = P.import("lib/actions")

local state = {
	Api = nil,
	View = nil,
	Items = {}, -- what is loaded (base/loaded items)
	Subject = nil, -- worked out from Items when first needed
}

-- What is loaded, worked out when first needed (scripts are compiled again
-- and modules looked up, so not on every load while the tab is closed).
local function subject()
	if state.Subject == nil then
		state.Subject = Inspect.subject(state.Items[1], #state.Items)
	end
	return state.Subject
end

local function viewAlive(): boolean
	return state.View ~= nil and not state.View.Destroyed
end

-- What is loaded changed: the tab shows it now if open, else when opened.
local function refresh(items: { any }?)
	local api = state.Api
	if not api then
		return
	end
	state.Items = items or api.loaded.list()
	state.Subject = nil
	if viewAlive() then
		if api.tab.isOpen() then
			state.View:Show(subject())
		else
			state.View.Dirty = true
		end
	end
end

return {
	Name = "Script Viewer",
	Id = "scriptviewer",
	Prime = true,
	Version = "0.1",
	Author = "Tungsten",
	Description = "look into scripts, ModuleScripts, functions and tables",
	Icon = "type_function",
	Order = 1,
	Settings = {
		{ Id = "constantsView", Kind = "choice", Text = "Constants view", Hint = "Tree: explore and change in place · List: search and filter, with paths · Table: as a Luau table, bulk changes", Options = { "Tree", "List", "Table" }, Default = "Tree" },
		{ Id = "upvaluesView", Kind = "choice", Text = "Upvalues view", Options = { "Tree", "List", "Table" }, Default = "Tree" },
		{ Id = "functionsView", Kind = "choice", Text = "Functions view", Options = { "Tree", "List", "Table" }, Default = "Tree" },
		{ Id = "contentsView", Kind = "choice", Text = "Contents view", Options = { "Tree", "List", "Table" }, Default = "Tree" },
		{ Id = "constantsScope", Kind = "choice", Text = "Constants scope", Hint = "also every nested function's constants", Options = { "This function", "With nested functions" }, Default = "This function" },
		{ Id = "upvaluesScope", Kind = "choice", Text = "Upvalues scope", Hint = "also the upvalues of nested functions' running copies", Options = { "This function", "With nested functions" }, Default = "This function" },
		{ Id = "showReferences", Kind = "toggle", Text = "Show references", Hint = "under the list: other functions using the selected constant or upvalue", Default = false },
		{ Id = "showEmpty", Kind = "toggle", Text = "Show empty constant slots", Hint = "slots the compiler left empty", Default = false },
		{ Id = "constantAnyType", Kind = "toggle", Text = "Constants may change type", Hint = "off: a string stays a string; the bytecode may expect the type", Default = false },
	},
	Tab = {
		Title = "Script Viewer",
		Icon = "type_function",
		Build = function(page, api)
			state.Api = api
			local view = View.new(page, api, Inspect)
			state.View = view
			if #state.Items == 0 then
				state.Items = api.loaded.list()
				state.Subject = nil
			end
			view:Show(subject())
		end,
		-- every load, whichever tab is open (the view follows
		-- api.loaded.Changed, which also covers unloads)
		OnLoad = function()
			return true
		end,
		-- opening the tab starts a decompile that was waiting for it
		OnSelect = function()
			if viewAlive() then
				if state.View.Dirty or state.View.Subject ~= subject() then
					state.View:Show(subject())
				end
				state.View:Opened()
			end
		end,
	},
	Exports = function(api)
		return {
			reveal = function(focus)
				focus = if type(focus) == "table" then focus else {}
				if focus.Target ~= nil then
					local target = focus.Target
					if typeof(target) ~= "Instance" and not api.loaded.isTarget(target) then
						target = api.loaded.target(target)
					end
					api.loaded.set(target)
				end
				if focus.Panel and state.View then
					state.View:Select(focus.Panel)
				end
			end,
			subject = function()
				return if state.Api then subject() else nil
			end,
			-- the tab's view once built (its panels and rows), or nil
			view = function()
				return state.View
			end,
		}
	end,
	Load = function(api)
		state.Api = api
		-- the right-click menu on rows and its forms (lib/actions)
		Actions.define(api, function()
			return state.View
		end)
		state.Items = api.loaded.list()
		state.Subject = nil
		-- every change to what is loaded: loads, unloads, destroyed objects
		api.connect(api.loaded.Changed, function(items)
			refresh(items)
		end)
		-- empty constant slots shown or hidden: the rows change
		api.connect(api.settings.Changed, function(key)
			if key == "showEmpty" and viewAlive() then
				state.View:Show(subject())
			end
		end)
	end,
	Unload = function()
		if state.View then
			state.View:Destroy()
		end
		state.Api, state.View, state.Subject, state.Items = nil, nil, nil, {}
	end,
}
