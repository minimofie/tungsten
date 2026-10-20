--[[
	Tungsten · base/explorer/menu
	The explorer's right-click menu, built on the menu framework
	(base/ui/menus). Menus defined here:

		explorer           header, Load, Object › Function › Variable › Save ›  (fixed)
		explorer.object    actions on the objects (base/explorer/actions)  (fixed)
		explorer.function  Documentation, View in console, then
		                   the actions plugins add                (open to plugins)
		explorer.variable  keep the selection in variables, Watch (fixed)
		explorer.save      write the objects to files              (fixed)
		explorer.search    the search bar's right-click menu      (open to plugins)

	The context every entry receives:
		ctx.Explorer   the explorer module
		ctx.Nodes      selected tree nodes (row order)
		ctx.Node       the row that was right-clicked (or nil)
		ctx.Instances  the selected Instances
		ctx.Count      #ctx.Instances
		ctx.Classes    { ClassName } of the selection, no repeats
		ctx.NilNode    true when the Nil Instances row is selected
		ctx.Point      where the menu opened

	Plugins add to the Function category with Explorer.addFunction (see
	base/explorer/explorer) or directly with Menus.add("explorer.function", …).
	Every entry looks at the whole selection; entries that don't apply are
	greyed out.
]]

local T = ...
local Variables = T.import("base/variables")
local Types = T.import("base/types")
local Overlay = T.import("base/ui/overlay")
local Menus = T.import("base/ui/menus")
local CellEditor = T.import("base/ui/components/celleditor")
local Dropdown = T.import("base/ui/components/dropdown")
local TypePicker = T.import("base/ui/components/typepicker")
local Insert = T.import("base/explorer/insert")
local Classes = T.import("base/data/classes")

local Menu = {}

local function setClipboard(text: string): boolean
	return (pcall(setclipboard, text))
end

-- Messages go through the explorer's reporter ([+] Explorer: …).
local function say(kind: string, text: string, details: { [string]: any }?)
	local reporter = if T.Console then T.Console.reporter("explorer", { Label = "Explorer", Plugin = false, Kind = "explorer" }) else nil
	if reporter then
		(reporter :: any)[kind](reporter, text, details)
	end
end

local function plural(count: number, word: string): string
	return ("%d %s%s"):format(count, word, if count == 1 then "" else "s")
end

-- Copy Path: one path, or a table of paths for several objects.
function Menu.pathText(instances: { Instance }): string
	if #instances == 1 then
		return Types.path(instances[1])
	end
	local lines = { "{" }
	for _, obj in instances do
		table.insert(lines, "\t" .. Types.path(obj) .. ",")
	end
	table.insert(lines, "}")
	return table.concat(lines, "\n")
end

-- The context for a right-click on the tree.
function Menu.context(Explorer, nodes, node, point: Vector2?)
	local instances, classes, nilNode = {}, {}, false
	for _, n in nodes do
		if n.IsNil then
			nilNode = true
		elseif n.Obj then
			table.insert(instances, n.Obj)
			if not table.find(classes, n.Class) then
				table.insert(classes, n.Class)
			end
		end
	end
	return {
		Explorer = Explorer,
		Nodes = nodes,
		Node = node,
		Instances = instances,
		Count = #instances,
		Classes = classes,
		NilNode = nilNode,
		Point = point,
	}
end

-- Asks for a variable name at a point, then stores the objects.
function Menu.promptVariable(instances: { Instance }, point: Vector2?)
	if #instances == 0 then
		return nil
	end
	local value = if #instances == 1 then instances[1] else table.clone(instances)
	local suggestion = if #instances == 1 then (instances[1].Name:gsub("[^%w_]", ""):gsub("^%d+", "")):lower() else "list"
	if suggestion == "" then
		suggestion = "obj"
	end
	return CellEditor.open({
		AnchorPos = point or Overlay.mouse(),
		AnchorSize = Vector2.new(220, 24),
		Text = suggestion,
		Mono = true,
		Hint = if #instances == 1 then "variable name · holds the object" else ("variable name · holds a table of %d"):format(#instances),
		Validate = function(text)
			local name = text:gsub("^%$", "")
			local ok, reason = Variables.validName(name)
			if not ok then
				return false, reason
			end
			if Variables.isReserved(name) then
				return false, ("$%s is reserved"):format(name)
			end
			return true, name
		end,
		OnCommit = function(name)
			local ok, reason = Variables.set(name, value, { Source = "explorer" })
			if not ok then
				return false, reason
			end
			if T.Console then
				T.Console.value("success", name .. " = ", value)
			end
			return true
		end,
	})
end

----------------------------------------------------------------------
-- Insert ›
----------------------------------------------------------------------

-- Where new objects go: the selection (the right-clicked row is in it).
local function insertParents(ctx): { Instance }
	return ctx.Instances
end

local function classEntry(ctx, className: string)
	local style = Classes.style(className)
	return {
		Id = "insert:" .. className,
		Text = className,
		Icon = style.Icon,
		IconColor = style.Color,
		Callback = function(c)
			ctx.Explorer.insert(className, insertParents(c))
		end,
	}
end

-- A group's entries; long groups become letter-range submenus.
local function groupEntries(ctx, classes: { string })
	local chunks = Insert.split(classes)
	local out = {}
	if #chunks == 1 then
		for _, name in chunks[1].Classes do
			table.insert(out, classEntry(ctx, name))
		end
		return out
	end
	for _, chunk in chunks do
		table.insert(out, {
			Id = "range:" .. chunk.Title,
			Text = chunk.Title,
			Shortcut = tostring(#chunk.Classes),
			Items = function()
				local list = {}
				for _, name in chunk.Classes do
					table.insert(list, classEntry(ctx, name))
				end
				return list
			end,
		})
	end
	return out
end

-- The searchable list of every class (Search all classes…).
function Menu.insertSearch(ctx, point: Vector2?)
	local parents = insertParents(ctx)
	local at = point or ctx.Point or Overlay.mouse()
	return Dropdown.popup({
		Options = TypePicker.options("creatable"),
		AnchorPos = at,
		AnchorSize = Vector2.new(0, 0),
		Width = 260,
		Searchable = true,
		Placeholder = "Class to insert…",
		IsSelected = function()
			return false
		end,
		OnPick = function(option)
			ctx.Explorer.insert(option.Value, parents)
		end,
	})
end

function Menu.insertItems(ctx): { any }
	local items = {
		{
			Id = "search",
			Text = "Search all classes…",
			Icon = "search",
			Emphasis = true,
			Callback = function(c)
				task.defer(Menu.insertSearch, c, c.Point)
			end,
		},
		{ Separator = true },
		{ Header = "Common" },
	}
	for _, name in Insert.common() do
		table.insert(items, classEntry(ctx, name))
	end
	table.insert(items, { Separator = true })
	table.insert(items, { Header = "All classes" })
	for _, group in Insert.groups() do
		table.insert(items, {
			Id = "group:" .. group.Id,
			Text = group.Title,
			Icon = group.Icon,
			IconColor = group.Color,
			Shortcut = tostring(#group.Classes),
			Items = function()
				return groupEntries(ctx, group.Classes)
			end,
		})
	end
	return items
end

----------------------------------------------------------------------
-- Definitions
----------------------------------------------------------------------

local function none(ctx)
	return ctx.Count == 0
end

Menus.define("explorer", {
	Source = "explorer", -- faults in entries print as [x] Explorer: …
	Title = "Explorer (right-click a row)",
	Locked = true,
	Header = function(ctx)
		local count = #ctx.Nodes
		if count == 0 then
			return "Nothing selected"
		elseif count == 1 then
			return if ctx.NilNode then "Nil Instances" else "1 selected"
		end
		return ("%d selected"):format(count)
	end,
	Sections = { "load", "categories" },
})
Menus.addMany("explorer", {
	{
		Id = "load",
		Section = "load",
		Order = 1,
		Text = "Load",
		Icon = "arrow_right",
		Emphasis = true,
		Shortcut = "every tab", -- one loaded target, shared by every tab
		Disabled = none,
		Callback = function(ctx)
			ctx.Explorer.load(ctx.Instances)
		end,
	},
	{ Id = "object", Section = "categories", Order = 1, Text = "Object", Icon = "object", Menu = "explorer.object" },
	{ Id = "function", Section = "categories", Order = 2, Text = "Function", Icon = "type_function", Disabled = none, Menu = "explorer.function" },
	{ Id = "variable", Section = "categories", Order = 3, Text = "Variable", Icon = "variable", Disabled = none, Menu = "explorer.variable" },
	{ Id = "save", Section = "categories", Order = 4, Text = "Save", Icon = "save", Disabled = none, Menu = "explorer.save" },
})

local Actions = T.import("base/explorer/actions")
local RemoteBlock = T.import("base/explorer/remoteblock")

-- Whether any selected object is (or inherits from) one of the classes.
local function anyIs(ctx, ...): boolean
	local classes = { ... }
	for _, obj in ctx.Instances do
		for _, className in classes do
			local ok, yes = pcall(function()
				return obj:IsA(className)
			end)
			if ok and yes then
				return true
			end
		end
	end
	return false
end

local function allMatching(ctx, test): { Instance }
	local out = {}
	for _, obj in ctx.Instances do
		local ok, yes = pcall(test, obj)
		if ok and yes then
			table.insert(out, obj)
		end
	end
	return out
end

local function firstOf(ctx, className: string): Instance?
	for _, obj in ctx.Instances do
		local ok, yes = pcall(function()
			return obj:IsA(className)
		end)
		if ok and yes then
			return obj
		end
	end
	return nil
end

Menus.define("explorer.object", {
	Source = "explorer", -- faults in entries print as [x] Explorer: …
	Title = "Explorer › Object",
	Locked = true,
	Sections = { "insert", "edit", "clipboard", "group", "tree", "copy", "script", "game", "remote", "player", "nil" },
})
Menus.addMany("explorer.object", {
	{
		Id = "insert",
		Section = "insert",
		Order = 10,
		Text = "Insert",
		Icon = "add",
		Shortcut = function(ctx)
			return if ctx.Count == 1 then "into " .. ctx.Instances[1].Name elseif ctx.Count > 1 then ("into %d"):format(ctx.Count) else nil
		end,
		Disabled = none,
		Items = function(ctx)
			return Menu.insertItems(ctx)
		end,
	},
	-- edit
	{
		Id = "rename",
		Section = "edit",
		Order = 10,
		Text = "Rename",
		Icon = "edit",
		Shortcut = "F2",
		Disabled = function(ctx)
			return ctx.Count ~= 1
		end,
		Callback = function(ctx)
			task.defer(ctx.Explorer.rename, ctx.Instances[1])
		end,
	},
	{
		Id = "duplicate",
		Section = "edit",
		Order = 20,
		Text = "Duplicate",
		Icon = "copy",
		Shortcut = "Ctrl+D",
		Disabled = none,
		Callback = function(ctx)
			Actions.duplicate(ctx.Instances)
		end,
	},
	{
		Id = "delete",
		Section = "edit",
		Order = 30,
		Text = "Delete",
		Icon = "trash",
		Shortcut = "Del",
		Danger = true,
		Disabled = none,
		Callback = function(ctx)
			ctx.Explorer.deleteNodes(ctx.Nodes)
		end,
	},
	{
		Id = "delete_children",
		Section = "edit",
		Order = 40,
		Text = "Delete Children",
		Icon = "trash",
		Danger = true,
		Disabled = function(ctx)
			for _, obj in ctx.Instances do
				local ok, kids = pcall(function()
					return #obj:GetChildren()
				end)
				if ok and kids > 0 then
					return false
				end
			end
			return true
		end,
		Callback = function(ctx)
			Actions.deleteChildren(ctx.Instances)
			ctx.Explorer.View:Refresh()
		end,
	},
	-- the explorer's own clipboard
	{
		Id = "cut",
		Section = "clipboard",
		Order = 10,
		Text = "Cut",
		Icon = "cut",
		Shortcut = "Ctrl+X",
		Disabled = function(ctx)
			for _, obj in ctx.Instances do
				if not ctx.Explorer.isFixed(obj) then
					return false
				end
			end
			return true
		end,
		Callback = function(ctx)
			Actions.cut(ctx.Instances)
		end,
	},
	{
		Id = "copy",
		Section = "clipboard",
		Order = 20,
		Text = "Copy",
		Icon = "copy",
		Shortcut = "Ctrl+C",
		Disabled = none,
		Callback = function(ctx)
			Actions.copy(ctx.Instances)
		end,
	},
	{
		Id = "paste_into",
		Section = "clipboard",
		Order = 30,
		Text = function()
			if not Actions.hasClipboard() then
				return "Paste Into"
			end
			-- only what is still there (deleted objects are left out)
			local items = Actions.clipboardItems()
			return ("Paste Into (%s %s)"):format(if Actions.Clipboard.Mode == "cut" then "move" else "copy", if #items == 1 then items[1].Name else #items .. " objects")
		end,
		Icon = "children",
		Shortcut = "Ctrl+V",
		Disabled = function(ctx)
			return ctx.Count == 0 or not Actions.hasClipboard()
		end,
		Callback = function(ctx)
			Actions.pasteInto(ctx.Instances)
		end,
	},
	{
		Id = "show_clipboard",
		Section = "clipboard",
		Order = 40,
		Text = function()
			local count = #Actions.clipboardItems()
			return if Actions.hasClipboard() then ("Show Clipboard (%d)"):format(count) else "Show Clipboard"
		end,
		Icon = "console",
		Shortcut = "/clipboard",
		Callback = function()
			Actions.showClipboard()
		end,
	},
	{
		Id = "clear_clipboard",
		Section = "clipboard",
		Order = 50,
		Text = "Clear Clipboard",
		Icon = "close",
		Disabled = function()
			return Actions.Clipboard.Mode == nil
		end,
		Callback = function()
			Actions.clearClipboard()
		end,
	},
	-- group
	{
		Id = "group",
		Section = "group",
		Order = 10,
		Text = "Group",
		Icon = "class_model",
		Shortcut = "Ctrl+G",
		Disabled = none,
		Callback = function(ctx)
			Actions.group(ctx.Instances, "Model")
		end,
	},
	{
		Id = "group_folder",
		Section = "group",
		Order = 20,
		Text = "Group in Folder",
		Icon = "class_folder",
		Disabled = none,
		Callback = function(ctx)
			Actions.group(ctx.Instances, "Folder")
		end,
	},
	{
		Id = "ungroup",
		Section = "group",
		Order = 30,
		Text = "Ungroup",
		Icon = "parent",
		Disabled = function(ctx)
			return not anyIs(ctx, "Model", "Folder")
		end,
		Callback = function(ctx)
			Actions.ungroup(allMatching(ctx, Actions.canUngroup))
		end,
	},
	-- tree
	{
		Id = "select_children",
		Section = "tree",
		Order = 10,
		Text = "Select Children",
		Icon = "children",
		Disabled = none,
		Callback = function(ctx)
			local children = {}
			for _, obj in ctx.Instances do
				local ok, list = pcall(function()
					return obj:GetChildren()
				end)
				if ok then
					for _, child in list do
						table.insert(children, child)
					end
				end
			end
			ctx.Explorer.select(children)
		end,
	},
	{
		Id = "jump_to_parent",
		Section = "tree",
		Order = 20,
		Text = "Jump to Parent",
		Icon = "parent",
		-- greyed out when everything selected is a top-level datamodel
		-- (its parent is the game itself)
		Disabled = function(ctx)
			for _, obj in ctx.Instances do
				if not ctx.Explorer.isFixed(obj) then
					return false
				end
			end
			return true
		end,
		Callback = function(ctx)
			local tree = ctx.Explorer.Tree
			local parents, seen = {}, {}
			for _, obj in ctx.Instances do
				local parent = tree.parentOf(obj)
				if parent and parent ~= game and not seen[parent] then
					seen[parent] = true
					table.insert(parents, parent)
				end
			end
			ctx.Explorer.select(parents)
		end,
	},
	{
		Id = "expand_all",
		Section = "tree",
		Order = 30,
		Text = "Expand All",
		Icon = "expand_all",
		Disabled = function(ctx)
			return #ctx.Nodes == 0
		end,
		Callback = function(ctx)
			local tree = ctx.Explorer.Tree
			for _, node in ctx.Nodes do
				if node.IsNil then
					tree:Load(node)
					node.Expanded = true
				end
			end
			ctx.Explorer.expand(nil, true)
		end,
	},
	{
		Id = "collapse_all",
		Section = "tree",
		Order = 40,
		Text = "Collapse All",
		Icon = "collapse_all",
		Disabled = function(ctx)
			return #ctx.Nodes == 0
		end,
		Callback = function(ctx)
			ctx.Explorer.collapse(nil, true)
		end,
	},
	{
		Id = "clear_search_jump",
		Section = "tree",
		Order = 50,
		Text = "Clear Search and Jump to",
		Icon = "target",
		When = function(ctx)
			return ctx.Explorer.getSearch() ~= ""
		end,
		Disabled = function(ctx)
			-- top-level datamodels (services) have no parent to jump to
			for _, obj in ctx.Instances do
				if not ctx.Explorer.isFixed(obj) then
					return false
				end
			end
			return true
		end,
		Callback = function(ctx)
			local keep = table.clone(ctx.Instances)
			ctx.Explorer.clearSearch()
			ctx.Explorer.select(keep)
		end,
	},
	-- copy
	{
		Id = "copy_path",
		Section = "copy",
		Order = 10,
		Text = "Copy Path",
		Icon = "copy",
		Disabled = none,
		Callback = function(ctx)
			if setClipboard(Menu.pathText(ctx.Instances)) then
				say("success", ("copied the path%s of %s"):format(if ctx.Count == 1 then "" else "s", plural(ctx.Count, "object")))
			else
				say("error", "couldn't copy: the clipboard isn't available")
			end
		end,
	},
		{
		Id = "dump_functions",
		Section = "script",
		Order = 40,
		Text = "Dump Functions",
		Icon = "type_function",
		When = function(ctx)
			return anyIs(ctx, "LuaSourceContainer")
		end,
		Callback = function(ctx)
			for _, script in allMatching(ctx, Actions.isScript) do
				Actions.dumpFunctions(script)
			end
		end,
	},
	-- gameplay
	{
		Id = "play_tween",
		Section = "game",
		Order = 30,
		Text = "Play Tween",
		Icon = "class_animation",
		When = function(ctx)
			return anyIs(ctx, "Tween")
		end,
		Callback = function(ctx)
			Actions.playTween(ctx.Instances)
		end,
	},
	{
		Id = "load_animation",
		Section = "game",
		Order = 40,
		Text = "Load Animation",
		Icon = "class_animation",
		When = function(ctx)
			return anyIs(ctx, "Animation")
		end,
		Callback = function(ctx)
			Actions.loadAnimation(ctx.Instances)
		end,
	},
	{
		Id = "stop_animations",
		Section = "game",
		Order = 50,
		Text = "Stop Animations",
		Icon = "close",
		When = function()
			return Actions.playingAnimations() > 0
		end,
		Callback = function()
			Actions.stopAnimations()
		end,
	},
	{
		Id = "fire",
		Section = "game",
		Order = 60,
		Text = function(ctx)
			if firstOf(ctx, "ClickDetector") then
				return "Fire ClickDetector"
			elseif firstOf(ctx, "ProximityPrompt") then
				return "Fire ProximityPrompt"
			end
			return "Fire TouchInterest"
		end,
		Icon = "target",
		When = function(ctx)
			return #allMatching(ctx, Actions.canFire) > 0
		end,
		Callback = function(ctx)
			Actions.fire(ctx.Instances)
		end,
	},
	-- remotes and bindables
	{
		Id = "block_remote",
		Section = "remote",
		Order = 10,
		Text = function(ctx)
			local list = allMatching(ctx, RemoteBlock.canBlock)
			local allBlocked = #list > 0
			for _, obj in list do
				if not RemoteBlock.isBlocked(obj) then
					allBlocked = false
				end
			end
			return if allBlocked then "Unblock" else "Block"
		end,
		Icon = "hide",
		Shortcut = function(ctx)
			local stopped = 0
			for _, obj in allMatching(ctx, RemoteBlock.canBlock) do
				stopped += RemoteBlock.stopped(obj)
			end
			return if stopped > 0 then ("%d stopped"):format(stopped) else nil
		end,
		When = function(ctx)
			return #allMatching(ctx, RemoteBlock.canBlock) > 0
		end,
		Callback = function(ctx)
			local list = allMatching(ctx, RemoteBlock.canBlock)
			local allBlocked = true
			for _, obj in list do
				if not RemoteBlock.isBlocked(obj) then
					allBlocked = false
				end
			end
			if allBlocked then
				for _, obj in list do
					RemoteBlock.unblock(obj)
				end
				say("success", ("unblocked %s"):format(if #list == 1 then list[1].Name else plural(#list, "object")))
				return
			end
			local blocked, problem = 0, nil
			for _, obj in list do
				local ok, reason = RemoteBlock.block(obj)
				if ok then
					blocked += 1
				else
					problem = reason
				end
			end
			if blocked > 0 then
				say("success", ("blocked %s · the game's calls to it go nowhere until you unblock it"):format(if #list == 1 then list[1].Name else plural(blocked, "object")))
			end
			if problem then
				say("error", "couldn't block: " .. tostring(problem))
			end
		end,
	},
	-- players
	{
		Id = "select_character",
		Section = "player",
		Order = 10,
		Text = "Select Character",
		Icon = "class_humanoid",
		When = function(ctx)
			return anyIs(ctx, "Player")
		end,
		Callback = function(ctx)
			Actions.selectCharacter(ctx.Instances)
		end,
	},
	-- Nil Instances
	{
		Id = "refresh_nil",
		Section = "nil",
		Order = 10,
		Text = "Refresh Nil Instances",
		Icon = "refresh",
		When = function(ctx)
			return ctx.NilNode
		end,
		Callback = function(ctx)
			ctx.Explorer.refreshNil()
		end,
	},
	{
		Id = "hide_nil",
		Section = "nil",
		Order = 20,
		Text = "Hide Nil Instances",
		Icon = "hide",
		When = function(ctx)
			return ctx.NilNode
		end,
		Callback = function(ctx)
			ctx.Explorer.hideNil()
		end,
	},
})

-- Save: everything that writes a file (Tungsten/saved/ unless a path is given).
Menus.define("explorer.save", {
	Source = "explorer", -- faults in entries print as [x] Explorer: …
	Title = "Explorer › Save",
	Locked = true,
	Sections = { "save" },
})
Menus.addMany("explorer.save", {
	{
		Id = "save_to_file",
		Section = "save",
		Order = 10,
		Text = "Save to File",
		Icon = "save",
		Shortcut = ".rbxm",
		Disabled = none,
		Callback = function(ctx)
			local list = table.clone(ctx.Instances)
			task.spawn(Actions.saveToFile, list)
		end,
	},
	{
		Id = "save_script",
		Section = "save",
		Order = 20,
		Text = "Save Script",
		Icon = "class_script",
		Shortcut = ".lua",
		When = function(ctx)
			return anyIs(ctx, "LuaSourceContainer")
		end,
		Callback = function(ctx)
			local scripts = allMatching(ctx, Actions.isScript)
			task.spawn(function()
				for _, script in scripts do
					Actions.saveScript(script)
				end
			end)
		end,
	},
	{
		Id = "save_bytecode",
		Section = "save",
		Order = 30,
		Text = "Save Bytecode",
		Icon = "class_script",
		Shortcut = ".luac",
		When = function(ctx)
			return anyIs(ctx, "LuaSourceContainer")
		end,
		Callback = function(ctx)
			for _, script in allMatching(ctx, Actions.isScript) do
				Actions.saveBytecode(script)
			end
		end,
	},
})

-- Function: Tungsten's own entries first, then what plugins add.
Menus.define("explorer.function", {
	Source = "explorer", -- faults in entries print as [x] Explorer: …
	Title = "Explorer › Function (Documentation, View in console, plugin actions)",
	Sections = { "core", "main" },
})
Menus.addMany("explorer.function", {
	{
		Id = "documentation",
		Section = "core",
		Order = 10,
		Text = "Documentation",
		Icon = "documentation",
		Shortcut = function(ctx)
			return if ctx.Count >= 1 then ctx.Instances[1].ClassName else nil
		end,
		Disabled = none,
		Callback = function(ctx)
			Menu.openDocumentation(ctx.Instances[1])
		end,
	},
	{
		Id = "view_in_console",
		Section = "core",
		Order = 20,
		Text = "View in console",
		Icon = "console",
		Disabled = none,
		Callback = function(ctx)
			Menu.viewInConsole(ctx.Instances)
		end,
	},
	{
		-- Shown when no plugin action applies to the selection.
		Id = "no_plugin_actions",
		Section = "main",
		Order = 0,
		Header = function(ctx)
			local classes = ctx.Classes or {}
			local label = if #classes == 1 then classes[1] elseif #classes == 0 then "this" else "these objects"
			return ("No plugin actions for %s"):format(label)
		end,
		When = function(ctx)
			for _, entry in Menus.entries("explorer.function") do
				if entry.Section ~= "core" and entry.Id ~= "no_plugin_actions" and entry.Header == nil then
					local shown = true
					if type(entry.When) == "function" then
						local ok, result = pcall(entry.When, ctx)
						shown = ok and result == true
					end
					if shown then
						return false
					end
				end
			end
			return true
		end,
	},
}, "core")

-- Opens the Documentation tab on the object's class page.
function Menu.openDocumentation(obj: Instance): boolean
	local Api = T.import("base/explorer/api")
	local Docs = T.import("documentation/docs")
	local className = Api.knownClass(obj)
	local topic = Docs.classTopic(className)
	if not topic then
		say("warn", ("no documentation for %s"):format(className))
		return false
	end
	if T.Tabs then
		T.Tabs:Select("documentation")
	end
	Docs.open(topic)
	return true
end

-- Prints the objects in the console: class and its base classes, path,
-- parent, children, the variables that hold them, and $sel.
function Menu.viewInConsole(instances: { Instance })
	if T.Tabs then
		T.Tabs:Select("console")
	end
	local Console = T.Console
	if not Console then
		return
	end
	Console.inspect(instances)
end

-- Variable names (not reserved) that hold any of the objects.
local function holding(ctx): { string }
	if ctx._holding then
		return ctx._holding
	end
	local names = {}
	for _, obj in ctx.Instances do
		for _, name in ctx.Explorer.variablesHolding(obj) do
			if not table.find(names, name) and not Variables.isReserved(name) then
				table.insert(names, name)
			end
		end
	end
	table.sort(names)
	ctx._holding = names
	return names
end

-- Asks for a list variable and adds the objects to it (a new list when it
-- doesn't exist yet).
function Menu.promptAddToList(instances: { Instance }, point: Vector2?)
	if #instances == 0 then
		return nil
	end
	local suggestion = "list"
	for _, entry in Variables.list() do
		if not entry.Reserved and type(entry.Value) == "table" and typeof(entry.Value) ~= "Instance" then
			suggestion = entry.Name
			break
		end
	end
	return CellEditor.open({
		AnchorPos = point or Overlay.mouse(),
		AnchorSize = Vector2.new(220, 24),
		Text = suggestion,
		Mono = true,
		Hint = "list variable · new or existing",
		Validate = function(text)
			local name = text:gsub("^%$", "")
			local ok, reason = Variables.validName(name)
			if not ok then
				return false, reason
			end
			if Variables.isReserved(name) then
				return false, ("$%s is reserved"):format(name)
			end
			local value, exists = Variables.get(name)
			if exists and (type(value) ~= "table" or typeof(value) == "Instance") then
				return false, ("$%s holds %s, not a list"):format(name, Types.tag(value))
			end
			return true, name
		end,
		OnCommit = function(name)
			return Menu.addToList(name, instances)
		end,
	})
end

function Menu.addToList(name: string, instances: { Instance }): (boolean, string?)
	local value, exists = Variables.get(name)
	if exists and (type(value) ~= "table" or typeof(value) == "Instance") then
		return false, ("$%s isn't a list"):format(name)
	end
	local list = if exists then table.clone(value) else {}
	local added = 0
	for _, obj in instances do
		if not table.find(list, obj) then
			table.insert(list, obj)
			added += 1
		end
	end
	local ok, reason = Variables.set(name, list, { Source = "explorer" })
	if not ok then
		return false, reason
	end
	say("success", ("added %s to $%s · it holds %d now"):format(plural(added, "object"), name, #list))
	return true
end

Menus.define("explorer.variable", {
	Source = "explorer", -- faults in entries print as [x] Explorer: …
	Title = "Explorer › Variable",
	Locked = true,
	Sections = { "keep", "watch", "remove" },
})
Menus.addMany("explorer.variable", {
	{
		Id = "set",
		Section = "keep",
		Order = 10,
		Text = "Set variable…",
		Icon = "variable",
		Disabled = none,
		Callback = function(ctx)
			task.defer(Menu.promptVariable, ctx.Instances, ctx.Point)
		end,
	},
	{
		Id = "add_to_list",
		Section = "keep",
		Order = 20,
		Text = "Add to list…",
		Icon = "add",
		Disabled = none,
		Callback = function(ctx)
			task.defer(Menu.promptAddToList, ctx.Instances, ctx.Point)
		end,
	},
	{
		Id = "copy_variable",
		Section = "keep",
		Order = 30,
		Text = "Copy variable",
		Icon = "copy",
		-- the variable that holds the object, ready to paste into the console
		Shortcut = function(ctx)
			local names = holding(ctx)
			return if #names > 0 then "$" .. names[1] else nil
		end,
		Disabled = function(ctx)
			return #holding(ctx) == 0
		end,
		Callback = function(ctx)
			local text = "$" .. holding(ctx)[1]
			if setClipboard(text) then
				say("success", "copied " .. text)
			end
		end,
	},
	{
		Id = "watch",
		Section = "watch",
		Order = 10,
		Text = function(ctx)
			for _, obj in ctx.Instances do
				if not Actions.isWatched(obj) then
					return "Watch"
				end
			end
			return if ctx.Count > 0 then "Stop watching" else "Watch"
		end,
		Icon = "target",
		Disabled = none,
		Callback = function(ctx)
			local all = true
			for _, obj in ctx.Instances do
				if not Actions.isWatched(obj) then
					all = false
				end
			end
			if all then
				Actions.unwatch(ctx.Instances)
			else
				Actions.watch(ctx.Instances)
			end
		end,
	},
	{
		Id = "unset",
		Section = "remove",
		Order = 10,
		Text = function(ctx)
			local names = holding(ctx)
			if #names == 0 then
				return "Unset variables"
			end
			local shown = {}
			for _, name in names do
				-- a plugin's variable says whose it is (you may still unset it)
				local owner = Variables.owner(name)
				table.insert(shown, if owner and owner ~= "you" then ("$%s (%s)"):format(name, owner) else "$" .. name)
			end
			return "Unset " .. table.concat(shown, ", ")
		end,
		Icon = "trash",
		Danger = function(ctx)
			return #holding(ctx) > 0
		end,
		Disabled = function(ctx)
			return #holding(ctx) == 0
		end,
		Callback = function(ctx)
			local names = holding(ctx)
			for _, name in names do
				Variables.unset(name)
			end
			say("success", ("removed $%s"):format(table.concat(names, ", $")))
		end,
	},
})

function Menu.open(Explorer, nodes, node, point: Vector2?)
	return Menus.open("explorer", Menu.context(Explorer, nodes, node, point), { Position = point })
end

return Menu
