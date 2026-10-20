-- Stage 4 Round C: the explorer's right-click actions (edit, clipboard,
-- group, files, gameplay, remote blocking, players), Function ›
-- Documentation / View in console, the Variable entries, var(), /undo for
-- deletes, /decompile and /save, the plugin api, the loading screen and
-- the tab divider.
local passed, failed = 0, 0
local function check(name, cond, detail)
	if cond then
		passed += 1
	else
		failed += 1
		print("FAIL: " .. name .. (if detail ~= nil then "  [" .. tostring(detail) .. "]" else ""))
	end
end
local E_ = H.env
local V2 = E_.Vector2.new
H.ABS_SHIFT = SHIFT or 0
local new = E_.Instance.new
local workspace = E_.workspace

local function make(class, name, parent)
	local o = new(class)
	o.Name = name
	o.Parent = parent
	return o
end
local map = make("Model", "Map", workspace)
local crate = H.part("Crate", map)
local barrel = H.part("Barrel", map)
local stuff = make("Folder", "Stuff", workspace)
local rs = H.services.ReplicatedStorage
local remote = make("RemoteEvent", "Shoot", rs)
local bindable = make("BindableEvent", "Signal", rs)
local script = make("LocalScript", "Controller", stuff)
script._props.Source = "local x = 1\nprint(x)"
local button = H.part("Button", workspace)
local click = make("ClickDetector", "ClickDetector", button)
local prompt = make("ProximityPrompt", "Prompt", button)
local touch = make("TouchTransmitter", "TouchInterest", button)
local tween = make("Tween", "Spin", stuff)
local animation = make("Animation", "Wave", stuff)

local ok, err = H.run("Tungsten/Tungsten.luau")
check("loader runs", ok, err)
H.advance(1)
local T = H.genv.Tungsten.Context
local E, C = T.Explorer, T.Console
local Actions = E.Actions
local Variables = T.Variables
local Undo = T.Undo
local Menus = T.Menus
check("no errors at start", #H.ERRORS == 0, H.ERRORS[1])

local function lines(from)
	local out = {}
	for index = from or 1, #C.Lines do
		table.insert(out, C.Lines[index].Plain)
	end
	return table.concat(out, "\n")
end
local function run(text)
	local at = #C.Lines + 1
	C.run(text)
	H.advance(0.3)
	return at
end
local function has(at, text)
	return lines(at):find(text, 1, true) ~= nil
end
local ExplorerMenu = T.import("base/explorer/menu")
local function ctxFor(list)
	E.select(list)
	H.advance(0.2)
	local nodes = {}
	for _, obj in list do
		table.insert(nodes, E.Tree:NodeFor(obj))
	end
	return ExplorerMenu.context(E, nodes, nodes[1], V2(300, 300))
end
local function items(menuId, list)
	local out = {}
	for _, item in Menus.build(menuId, ctxFor(list)) do
		if item.Text then
			out[item.Text] = item
		end
	end
	return out
end
local function choose(menuId, list, text)
	local item = items(menuId, list)[text]
	assert(item, ("no entry %s in %s"):format(text, menuId))
	assert(not item.Disabled, text .. " is greyed out")
	local at = #C.Lines + 1
	item.Callback(item)
	H.advance(0.3)
	return at
end

----------------------------------------------------------------------
-- 1. Loading screen, divider, no "looks like Luau"
----------------------------------------------------------------------
check("the splash is gone once Tungsten is up", T.Loading and T.Loading.Gui.Parent == nil)
check("the splash lasts 3 seconds", T.import("base/ui/loading").Duration == 3 and T.Loading.Duration == 3)
local probe = T.import("base/ui/loading").show({ Yield = false })
check("it shows the brand icon, name and a progress bar", probe.Card:FindFirstChild("Brand") ~= nil and probe.Card:FindFirstChild("Name") ~= nil and probe.Card:FindFirstChild("Track") ~= nil)
local nameRow = probe.Card:FindFirstChild("Name")
check("…the name reads tungsten (unified)", nameRow:FindFirstChild("Title").Text == "tungsten" and nameRow:FindFirstChild("Unified").Text == "(unified)")
probe:Step(0.5)
check("…the bar follows the progress", probe.Fill.Size.X.Scale == 0.5)
probe:Finish()
H.advance(0.5)
check("…and goes away", probe.Gui.Parent == nil)
check("the divider sits under the main tabs", T.Tabs.Divider.Visible)
local order = {}
for _, id in { "console", "plugins", "documentation" } do
	table.insert(order, T.Tabs.Entries[id].Button.LayoutOrder < T.Tabs.Divider.LayoutOrder)
end
check("…below all three", order[1] and order[2] and order[3])
for i = 1, 25 do
	T.Registry.addTab({ Id = "p" .. i, Title = "Plugin " .. i, Owner = "demo" })
end
H.advance(0.3)
check("plugin tabs go below the divider", T.Tabs.Entries.p1.Button.LayoutOrder > T.Tabs.Divider.LayoutOrder)
check("the side bar scrolls with many tabs", T.Tabs.Scroll:CanScroll("Y"))
T.Tabs.Scroll:ScrollBy(V2(0, 200), false)
H.advance(0.2)
check("…and actually moves", T.Tabs.Scroll.Offset.Y > 0)
T.UI.removeOwner("demo")
H.advance(0.2)
local at = run("x = 1")
check("bare Luau gets no 'looks like Luau' line", not has(at, "looks like Luau"), lines(at))

-- The splash comes first and holds everything back for its 3 seconds.
do
	local f = assert(H.env.loadfile("Tungsten/Tungsten.luau"))
	local co = coroutine.create(function()
		f()
	end)
	local startTime = H.TIME
	coroutine.resume(co)
	H.advance(0.5)
	local T2 = H.genv.Tungsten.Context
	local splash = T2.Loading
	check("splash: up first, with the brand icon", splash and splash.Gui.Parent ~= nil and splash.Card:FindFirstChild("Brand") ~= nil)
	check("splash: the window isn't shown yet", not T2.Window.Root.Visible)
	check("splash: the command bar key doesn't work yet", (function()
		H.key("Quote")
		H.advance(0.1)
		return not T2.CommandBar.IsOpen
	end)())
	H.advance(1.5)
	check("splash: still up after 2 seconds", splash.Gui.Parent ~= nil and not T2.Window.Root.Visible)
	check("splash: it faded in", splash.Card.BackgroundTransparency == 0)
	H.advance(1.7)
	check("splash: the bar is full after its 3 seconds, still showing", splash.Gui.Parent ~= nil and not T2.Window.Root.Visible, H.TIME - startTime)
	H.advance(0.35)
	check("splash: it fades out before the window appears", splash.Gui.Parent ~= nil and splash.Card.BackgroundTransparency > 0 and not T2.Window.Root.Visible, splash.Card.BackgroundTransparency)
	H.advance(1)
	check("splash: then it's gone and the window opens", splash.Gui.Parent == nil and T2.Window.Root.Visible and coroutine.status(co) == "dead", H.TIME - startTime)
	T = T2
	E, C = T.Explorer, T.Console
	Actions = E.Actions
	Variables = T.Variables
	Undo = T.Undo
	Menus = T.Menus
	ExplorerMenu = T.import("base/explorer/menu")
end
-- the command bar opens with ' now (an old saved \ is replaced)
check("the welcome line names the ' key", (function()
	for _, line in C.Lines do
		if line.Plain:find("' opens the command bar", 1, true) then
			return true
		end
	end
	return false
end)())
H.key("Quote")
H.advance(0.3)
check("' opens the command bar", T.CommandBar.IsOpen)
H.focused = T.CommandBar.box()
H.key("Quote")
H.advance(0.3)
check("' on the empty bar closes it", not T.CommandBar.IsOpen)
H.focused = nil
H.FILES["Tungsten/base/settings.json"] = '{"CommandBarKey":"BackSlash","Scale":1}'
T.Settings.load()
check("an old saved \\ key becomes '", T.Settings.get("CommandBarKey") == "Quote")
T.Settings.set("CommandBarKey", "F8")
T.Settings.flush()
T.Settings.load()
check("…but a key you chose yourself stays", T.Settings.get("CommandBarKey") == "F8")
T.Settings.set("CommandBarKey", "Quote")

-- closing the bar gives input back to the game at once
H.key("Quote")
H.advance(0.3)
local barBox = T.CommandBar.box()
check("the bar's box takes text while open", barBox.TextEditable == true)
H.focused = barBox
H.click(V2(5, H.SCREEN.Y - 5))
H.advance(0.3)
check("one click closes it and frees the keyboard", not T.CommandBar.IsOpen and H.focused ~= barBox)
check("…its box no longer takes text", barBox.TextEditable == false and barBox.Selectable == false)
H.services.GuiService.SelectedObject = barBox
H.key("Quote")
H.advance(0.3)
H.key("Escape")
H.advance(0.4)
check("closing clears a selected bar object", H.services.GuiService.SelectedObject == nil and not T.CommandBar.IsOpen)

----------------------------------------------------------------------
-- 2. Duplicate, delete (undoable), delete children
----------------------------------------------------------------------
Undo.clear()
at = choose("explorer.object", { crate }, "Duplicate")
local copies = {}
for _, c in map:GetChildren() do
	if c.Name == "Crate" then
		table.insert(copies, c)
	end
end
check("Duplicate makes a copy next to it", #copies == 2 and has(at, "duplicated Crate"), lines(at))
check("the copy is selected", E.getSelection()[1] ~= crate and E.getSelection()[1].Name == "Crate")
local copy = E.getSelection()[1]
run("/undo")
check("/undo removes the copy", copy.Parent == nil)
at = choose("explorer.object", { barrel }, "Delete")
check("Delete takes it out", barrel.Parent == nil and has(at, "deleted Barrel"), lines(at))
at = run("/undo")
check("/undo brings it back", barrel.Parent == map and has(at, "undid delete Barrel"), lines(at))
local kid1 = make("Part", "K1", stuff)
local kid2 = make("Part", "K2", stuff)
H.advance(0.2)
local before = #stuff:GetChildren()
choose("explorer.object", { stuff }, "Delete Children")
check("Delete Children empties it", #stuff:GetChildren() == 0)
run("/undo")
check("…undo puts them back", #stuff:GetChildren() == before and kid1.Parent == stuff and kid2.Parent == stuff)

----------------------------------------------------------------------
-- 3. Cut / Copy / Paste Into
----------------------------------------------------------------------
local pasteItem = items("explorer.object", { map })["Paste Into"]
check("Paste Into greyed with an empty clipboard", pasteItem and pasteItem.Disabled)
choose("explorer.object", { crate }, "Copy")
check("Copy fills the explorer's clipboard (not the computer's)", Actions.Clipboard.Mode == "copy" and Actions.Clipboard.Items[1] == crate)
local itemsNow = items("explorer.object", { stuff })
local pasteText
for text in itemsNow do
	if text:sub(1, 10) == "Paste Into" then
		pasteText = text
	end
end
check("Paste Into says what it pastes", pasteText == "Paste Into (copy Crate)", pasteText)
at = choose("explorer.object", { stuff }, pasteText)
local pasted = stuff:FindFirstChild("Crate")
check("Paste Into puts a copy inside", pasted ~= nil and pasted ~= crate and crate.Parent == map and has(at, "pasted Crate into"), lines(at))
run("/undo")
check("…undo removes the pasted copy", pasted.Parent == nil)
choose("explorer.object", { crate }, "Cut")
at = choose("explorer.object", { stuff }, "Paste Into (move Crate)")
check("Cut then Paste Into moves it", crate.Parent == stuff, lines(at))
check("…and empties the clipboard", not Actions.hasClipboard())
run("/undo")
check("…undo moves it back", crate.Parent == map)

----------------------------------------------------------------------
-- 3b. /clipboard, Clear Clipboard, and the tree showing cut objects
----------------------------------------------------------------------
local function rowOf(obj)
	E.select({ obj })
	H.advance(0.2)
	for _, entry in E.View.Entries do
		if entry.Row.Visible and E.View.Rows[entry.Index] and E.View.Rows[entry.Index].Obj == obj then
			return entry
		end
	end
	return nil
end
Actions.clearClipboard(true)
at = run("/clipboard")
check("/clipboard on an empty clipboard says so", has(at, "the clipboard is empty"), lines(at))
local showItem = items("explorer.object", { crate })["Show Clipboard"]
local clearItem = items("explorer.object", { crate })["Clear Clipboard"]
check("Object › Show Clipboard and Clear Clipboard are there", showItem ~= nil and clearItem ~= nil)
check("…Clear Clipboard is greyed while it is empty", clearItem and clearItem.Disabled)
at = run("/clearclipboard")
check("/clearclipboard with nothing on it", has(at, "already empty"), lines(at))

choose("explorer.object", { crate, barrel }, "Cut")
at = run("/clipboard")
check("/clipboard shows a cut", has(at, "clipboard · cut · 2 objects") and has(at, "Workspace.Map.Crate  (Part)") and has(at, "Workspace.Map.Barrel  (Part)"), lines(at))
check("…and the objects become $last", type(T.Variables.get("last")) == "table" and #T.Variables.get("last") == 2)
local crateRow = rowOf(crate)
check("cut objects are faded in the tree", crateRow and crateRow.Dimmed == true and crateRow.Label.TextTransparency > 0 and crateRow.Icon.ImageTransparency > 0)
local stuffRow = rowOf(stuff)
check("…other rows are not", stuffRow and stuffRow.Dimmed == false and stuffRow.Label.TextTransparency == 0)
local menuItems = items("explorer.object", { crate })
local showText
for text in menuItems do
	if text:sub(1, 14) == "Show Clipboard" then
		showText = text
	end
end
check("Show Clipboard says how many", showText == "Show Clipboard (2)", showText)
check("Clear Clipboard is enabled now", menuItems["Clear Clipboard"] and not menuItems["Clear Clipboard"].Disabled)
at = choose("explorer.object", { crate }, showText)
check("Object › Show Clipboard prints it too", has(at, "clipboard · cut · 2 objects") and has(at, "Workspace.Map.Crate"), lines(at))
at = choose("explorer.object", { crate }, "Clear Clipboard")
check("Object › Clear Clipboard empties it", not Actions.hasClipboard() and Actions.Clipboard.Mode == nil and has(at, "clipboard cleared"), lines(at))
check("…cut objects stay where they are", crate.Parent == map and barrel.Parent == map)
crateRow = rowOf(crate)
check("…and are no longer faded", crateRow and crateRow.Dimmed == false and crateRow.Label.TextTransparency == 0 and crateRow.Icon.ImageTransparency == 0)
local pasteAfter = items("explorer.object", { stuff })["Paste Into"]
check("Paste Into is greyed after clearing", pasteAfter and pasteAfter.Disabled)
E.select({ stuff })
H.advance(0.2)
E.View.Active = true
H.keys.LeftControl = true
H.key("V")
H.keys.LeftControl = nil
H.advance(0.3)
check("Ctrl+V after clearing pastes nothing", crate.Parent == map and stuff:FindFirstChild("Crate") == nil)

-- Ctrl+X / /clearclipboard / Ctrl+C
E.select({ crate })
H.advance(0.2)
E.View.Active = true
H.keys.LeftControl = true
H.key("X")
H.keys.LeftControl = nil
H.advance(0.3)
check("Ctrl+X cuts and fades the row", Actions.clipboardMode() == "cut" and rowOf(crate).Dimmed == true)
at = run("/clearclipboard")
check("/clearclipboard empties it and says what it held", not Actions.hasClipboard() and has(at, "clipboard cleared · Crate no longer cut"), lines(at))
check("…the row comes back", rowOf(crate).Dimmed == false)
E.select({ crate })
H.advance(0.2)
E.View.Active = true
H.keys.LeftControl = true
H.key("C")
H.keys.LeftControl = nil
H.advance(0.3)
at = run("/clipboard")
check("/clipboard shows a copy", has(at, "clipboard · copied · 1 object") and T.Variables.get("last") == crate, lines(at))
check("copied rows aren't faded", rowOf(crate).Dimmed == false)
at = run("/clip clear")
check("/clip clear (alias, subcommand) empties it", not Actions.hasClipboard() and has(at, "Crate no longer copied"), lines(at))

-- the console side: cut / copy / paste through /clipboard
T.Variables.set("box", barrel)
at = run("/clipboard copy $box")
check("/clipboard copy $var", Actions.clipboardMode() == "copy" and Actions.clipboardItems()[1] == barrel and has(at, "clipboard · copied"), lines(at))
at = run("/clipboard paste game.Workspace.Stuff")
local pastedBarrel = stuff:FindFirstChild("Barrel")
check("/clipboard paste <path> pastes a copy and returns it", pastedBarrel ~= nil and pastedBarrel ~= barrel and T.Variables.get("last") == pastedBarrel, lines(at))
check("…the copy stays on the clipboard", Actions.clipboardMode() == "copy")
run("/undo")
check("…/undo removes it", pastedBarrel.Parent == nil)
at = run("/clipboard cut game.Workspace.Map.Crate")
check("/clipboard cut <path>", Actions.clipboardMode() == "cut" and rowOf(crate).Dimmed == true, lines(at))
crate.Parent = nil
H.advance(0.2)
at = run("/clipboard")
check("a deleted object is noted and left out", has(at, "the clipboard is empty · what was on it has been deleted") and has(at, "deleted since, left out"), lines(at))
at = run("/clipboard paste game.Workspace.Stuff")
check("…pasting it says why nothing happened", has(at, "has been deleted"), lines(at))
crate.Parent = map
H.advance(0.2)
at = run("/clipboard paste game.Workspace.Stuff")
check("undeleted, it pastes (moves) again", crate.Parent == stuff and not Actions.hasClipboard(), lines(at))
check("…and is no longer faded", rowOf(crate).Dimmed == false)
run("/undo")
check("…undo moves it back", crate.Parent == map)
Actions.copy({ crate })
run("/clearclipboard")
at = run("/clipboard paste game.Workspace.Stuff")
check("/clipboard paste with nothing on it fails cleanly", has(at, "the clipboard is empty") and stuff:FindFirstChild("Crate") == nil, lines(at))
at = run("/clipboard fly")
check("an unknown /clipboard word shows the usage", has(at, "/clipboard [clear"), lines(at))
local Commands = T.import("console/commands")
check("both commands are listed", Commands.get("core", "clipboard") ~= nil and Commands.get("core", "clearclipboard") ~= nil)
check("/copy is still the computer's clipboard", (function()
	run("/copy hello")
	return H.CLIPBOARD == "hello" and not Actions.hasClipboard()
end)())

----------------------------------------------------------------------
-- 4. Group / Ungroup and the tree's Ctrl keys
----------------------------------------------------------------------
at = choose("explorer.object", { crate, barrel }, "Group")
local group = crate.Parent
check("Group puts them in a new Model where they were", group ~= map and group.ClassName == "Model" and group.Parent == map and barrel.Parent == group, lines(at))
check("the group is selected", E.getSelection()[1] == group)
at = choose("explorer.object", { group }, "Ungroup")
check("Ungroup moves them up and removes the group", crate.Parent == map and barrel.Parent == map and group.Parent == nil, lines(at))
run("/undo")
check("undo Ungroup restores the group", crate.Parent == group and group.Parent == map)
run("/undo")
check("undo Group puts them back", crate.Parent == map and group.Parent == nil)
choose("explorer.object", { crate, barrel }, "Group in Folder")
check("Group in Folder makes a Folder", crate.Parent.ClassName == "Folder")
run("/undo")
local ungroupItem = items("explorer.object", { crate })["Ungroup"]
check("Ungroup greyed for a part", ungroupItem and ungroupItem.Disabled)
-- Ctrl keys in the tree
E.select({ barrel })
H.advance(0.2)
E.View.Active = true
H.keys.LeftControl = true
H.key("D")
H.keys.LeftControl = nil
H.advance(0.3)
local barrels = 0
for _, c in map:GetChildren() do
	if c.Name == "Barrel" then
		barrels += 1
	end
end
check("Ctrl+D duplicates", barrels == 2)
local dup = E.getSelection()[1]
H.keys.LeftControl = true
H.key("Z")
H.keys.LeftControl = nil
H.advance(0.2)
check("Ctrl+Z undoes it", dup.Parent == nil)

----------------------------------------------------------------------
-- 5. Copy API page URL, files
----------------------------------------------------------------------
check("no Copy API Page URL", items("explorer.object", { crate })["Copy API Page URL"] == nil)
check("Save is its own category", items("explorer", { crate })["Save"] ~= nil)
check("…and Object has no save entries", items("explorer.object", { script })["Save Script"] == nil and items("explorer.object", { map })["Save to File"] == nil)
at = choose("explorer.save", { map }, "Save to File")
H.advance(0.2)
check("Save to File uses saveinstance with a path", H.SAVED and H.SAVED["Tungsten/saved/Map.rbxm"] == map, lines(at))
check("…and says where", has(at, "saved Map to Tungsten/saved/Map.rbxm"), lines(at))
local saveMenu = items("explorer.save", { script })
check("Save › has the script entries for scripts", saveMenu["Save to File"] and saveMenu["Save Script"] and saveMenu["Save Bytecode"])
check("Dump Functions stays in Object (it prints, doesn't save)", items("explorer.object", { script })["Dump Functions"] ~= nil)
check("…and not View Script (comes later as a plugin)", items("explorer.object", { script })["View Script"] == nil)
check("…but not for parts", items("explorer.save", { crate })["Save Script"] == nil)
at = choose("explorer.save", { script }, "Save Script")
H.advance(0.2)
local saved = H.FILES["Tungsten/saved/Controller.lua"]
check("Save Script writes the decompiled source", saved and saved:find("print(x)", 1, true), lines(at))
choose("explorer.save", { script }, "Save Bytecode")
check("Save Bytecode writes the bytecode", H.FILES["Tungsten/saved/Controller.luac"] ~= nil)
at = choose("explorer.object", { script }, "Dump Functions")
check("Dump Functions lists nested functions", has(at, "3 functions") and has(at, "function onTouched(a1)") and has(at, "function setup(a1, a2)") and has(at, "(anonymous)(...)"), lines(at))
script._props.Source = nil
at = choose("explorer.save", { script }, "Save Script")
H.advance(0.2)
check("a failed decompile says so", has(at, "couldn't decompile Controller"), lines(at))
script._props.Source = "return 1"
E.select({ script })
H.advance(0.2)
at = run("/decompile")
check("/decompile saves the selected script", has(at, "Tungsten/saved/Controller (2).lua") or has(at, "saved the source"), lines(at))
at = run("/decompile $sel ctl")
check("/decompile with a file name", H.FILES["Tungsten/saved/ctl.lua"] ~= nil, lines(at))
at = run("/save game.Workspace.Map mapcopy")
check("/save", H.SAVED["Tungsten/saved/mapcopy.rbxm"] == map, lines(at))

----------------------------------------------------------------------
-- 6. Gameplay
----------------------------------------------------------------------
H.spawnCharacter()
H.advance(0.2)
local cam = workspace.CurrentCamera
check("no View Object entry", items("explorer.object", { crate })["View Object"] == nil)
choose("explorer.object", { tween }, "Play Tween")
check("Play Tween", tween._props.PlayCount == 1)
choose("explorer.object", { animation }, "Load Animation")
check("Load Animation plays it on your character", H.TRACKS and H.TRACKS[1].Playing and H.TRACKS[1].Animation == animation)
choose("explorer.object", { crate }, "Stop Animations")
check("Stop Animations", not H.TRACKS[1].Playing)
H.FIRED = {}
choose("explorer.object", { click }, "Fire ClickDetector")
choose("explorer.object", { prompt }, "Fire ProximityPrompt")
choose("explorer.object", { touch }, "Fire TouchInterest")
H.advance(0.1)
check("fires ClickDetector, ProximityPrompt and TouchInterest", #H.FIRED == 4 and H.FIRED[1][1] == "click" and H.FIRED[2][1] == "prompt" and H.FIRED[3][1] == "touch" and H.FIRED[3][4] == 0 and H.FIRED[4][4] == 1)

----------------------------------------------------------------------
-- 7. Block / Unblock remotes and bindables
----------------------------------------------------------------------
local RemoteBlock = T.import("base/explorer/remoteblock")
check("remotes get Block", items("explorer.object", { remote })["Block"] ~= nil)
check("bindables too", items("explorer.object", { bindable })["Block"] ~= nil)
check("parts don't", items("explorer.object", { crate })["Block"] == nil)
choose("explorer.object", { remote }, "Block")
check("blocked", RemoteBlock.isBlocked(remote) and H.HOOKS == 1)
local function gameCall(obj, method)
	H.NAMECALL_METHOD = method
	H.CHECKCALLER = false
	local result = H.NAMECALL_HOOK(obj, "arg")
	H.CHECKCALLER = nil
	return result
end
check("a game call to it goes nowhere", gameCall(remote, "FireServer") == nil)
check("other remotes still work", gameCall(bindable, "Fire") == "passed")
H.CHECKCALLER = true
H.NAMECALL_METHOD = "FireServer"
check("your own calls still work", H.NAMECALL_HOOK(remote) == "passed")
H.CHECKCALLER = nil
check("the menu shows how many were stopped", items("explorer.object", { remote })["Unblock"].Shortcut == "1 stopped")
choose("explorer.object", { bindable }, "Block")
check("one shared hook for all of them", H.HOOKS == 1 and gameCall(bindable, "Fire") == nil)
choose("explorer.object", { remote }, "Unblock")
check("Unblock lets calls through again", gameCall(remote, "FireServer") == "passed")

----------------------------------------------------------------------
-- 8. Players
----------------------------------------------------------------------
local Players = H.services.Players
local playerCtx = ExplorerMenu.context(E, { { Obj = H.player, Class = "Player", Name = H.player.Name } }, nil, V2(300, 300))
local playerItems = {}
for _, item in Menus.build("explorer.object", playerCtx) do
	if item.Text then
		playerItems[item.Text] = true
	end
end
check("players get Select Character only", playerItems["Select Character"] and not playerItems["View Player"] and not playerItems["Select Local Player"] and not playerItems["Select All Characters"])
-- the Players service isn't in the mock tree; call the actions directly
Actions.selectCharacter({ H.player })
H.advance(0.2)
check("Select Character", E.getSelection()[1] == H.character)


----------------------------------------------------------------------
-- 9. Function › Documentation and View in console
----------------------------------------------------------------------
local fnItems = items("explorer.function", { crate })
check("Function starts with Documentation and View in console", fnItems["Documentation"] and fnItems["View in console"])
check("…Documentation names the class", fnItems["Documentation"].Shortcut == "Part")
choose("explorer.function", { crate }, "Documentation")
H.advance(0.3)
check("Documentation opens the docs tab", T.Tabs.Selected == "documentation")
local docsView = T.Docs.View
check("…on the class page", docsView and docsView.Current and tostring(docsView.Current.Title or docsView.Current.Id):find("Part", 1, true), docsView and docsView.Current and docsView.Current.Id)
Variables.set("box", crate)
at = choose("explorer.function", { crate }, "View in console")
check("View in console opens the console", T.Tabs.Selected == "console")
check("…prints class and base classes", has(at, "class") and has(at, "Part  ‹ ") and has(at, "‹ BasePart ‹ PVInstance ‹ Instance"), lines(at))
check("…path, parent and children", has(at, "game.Workspace.Map.Crate") and has(at, "children") and not has(at, "kids"), lines(at))
check("…and the variables that hold it", has(at, "$box") and has(at, "$sel"), lines(at))
at = choose("explorer.function", { crate, barrel }, "View in console")
check("several: a count, then each", has(at, "2 objects") and has(at, "Crate") and has(at, "Barrel"), lines(at))
check("View in console left the Variable menu", items("explorer.variable", { crate })["View in console"] == nil)

----------------------------------------------------------------------
-- 10. Variable entries
----------------------------------------------------------------------
Menus = T.Menus
ExplorerMenu.addToList("list1", { crate })
ExplorerMenu.addToList("list1", { barrel, crate })
local list1 = Variables.get("list1")
check("Add to list makes and grows a list (no repeats)", type(list1) == "table" and #list1 == 2 and list1[2] == barrel)
local okBad, reason = ExplorerMenu.addToList("box", { crate })
check("…but not into a variable that isn't a list", okBad == false and tostring(reason):find("isn't a list", 1, true))
local varItems = items("explorer.variable", { crate })
check("Copy variable names the variable that holds it", varItems["Copy variable"] ~= nil and varItems["Copy variable"].Shortcut == "$box")
choose("explorer.variable", { crate }, "Copy variable")
check("…and copies it", H.CLIPBOARD == "$box")
check("Copy variable greyed when no variable holds it", items("explorer.variable", { map })["Copy variable"].Disabled)
choose("explorer.variable", { crate }, "Watch")
at = #C.Lines + 1
crate.Transparency = 0.5
H.advance(0.1)
check("Watch prints property changes", has(at, "Crate.Transparency = 0.5"), lines(at))
check("…the entry turns into Stop watching", items("explorer.variable", { crate })["Stop watching"] ~= nil)
choose("explorer.variable", { crate }, "Stop watching")
at = #C.Lines + 1
crate.Transparency = 0.2
H.advance(0.1)
check("…which stops it", not has(at, "Crate.Transparency"), lines(at))

----------------------------------------------------------------------
-- 11. var("name")
----------------------------------------------------------------------
local p1 = H.part("V1", workspace)
local p2 = H.part("V2", workspace)
Variables.set("list2", { p1, p2 })
at = run('> var("list2").Transparency = 0.7')
check('var("list").Prop = v sets every object', p1.Transparency == 0.7 and p2.Transparency == 0.7, lines(at))
at = run('= var("list2").Name')
check("reading gives a table of values", has(at, "V1") and has(at, "V2"), lines(at))
at = run('= #var("list2")')
check("#group", has(at, "2"), lines(at))
at = run('> var("list2"):Destroy()')
check('var("list"):Destroy() destroys every object', p1._destroyed and p2._destroyed, lines(at))
at = run('= var("box").Name')
check("var on a single object gives the object", has(at, "Crate"), lines(at))
at = run('= var("$box") == box')
check("the $ is optional", has(at, "true"), lines(at))
E.select({ crate })
H.advance(0.2)
at = run('= var("sel").Name')
check('var("sel") is the selection', has(at, "Crate"), lines(at))
at = run('= var("nope")')
check("an unknown name is an error", has(at, "unknown variable $nope"), lines(at))
at = run("> var = 1")
check("var belongs to the console", has(at, "belongs to the console"), lines(at))

----------------------------------------------------------------------
-- 12. Plugins: commands, variables, functions, cleanup
----------------------------------------------------------------------
local api = T.api("spawner", { Name = "Spawner" })
api.console.register({
	Name = "spawnit",
	Usage = "/spawnit",
	Description = "make a part",
	Run = function(ctx)
		local part = new("Part")
		part.Name = "Spawned"
		part.Parent = workspace
		ctx.success("made it")
		return part
	end,
})
at = run(":spawner.spawnit")
check("a plugin command runs as :plugin.name", workspace:FindFirstChild("Spawned") ~= nil and has(at, "made it"), lines(at))
at = run("/spawnit")
check("…and as /name when unique", has(at, "made it"), lines(at))
check("its result is $last", Variables.get("last") ~= nil and Variables.get("last").Name == "Spawned")
at = #C.Lines + 1
api.console.print("hello")
check("api.console.print writes [plugin] Spawner:", has(at, "[plugin] Spawner: hello"), lines(at))
E.select({ crate })
H.advance(0.2)
check("plugins read $sel", api.variables.get("sel") == crate and api.variables.selection()[1] == crate)
check("…and any variable by name, lists as groups", #api.variables.ref("list1") == 2 and Variables.isGroup(api.variables.ref("list1")))
local seen = nil
local conn = api.variables.watch("sel", function(value)
	seen = value
end)
E.select({ barrel })
H.advance(0.2)
check("plugins can watch $sel", seen == barrel)
conn:Disconnect()
api.variables.set("hits", 3)
check("plugin variables carry its name", Variables.source("hits") == "spawner")
check("…and reserved names stay read-only", api.variables.set("sel", 1) == false)
api.explorer.addFunction({ Id = "lift", Text = "Lift", AppliesTo = function(list) return true end, Run = function(list) list[1].Name = "Lifted" end })
check("plugin functions appear under Function", items("explorer.function", { crate })["Lift"] ~= nil)
check("api.console.onLine sees new lines", (function()
	local got = nil
	local c = api.console.onLine(function(line) got = line end)
	C.info("ping")
	c:Disconnect()
	return got ~= nil and got.Plain:find("ping", 1, true) ~= nil
end)())
api:remove()
H.advance(0.2)
at = run(":spawner.spawnit")
check("removing the plugin removes its commands", not has(at, "made it"), lines(at))
check("…its variables", Variables.get("hits") == nil)
check("…and its functions", items("explorer.function", { crate })["Lift"] == nil)

----------------------------------------------------------------------
-- 13. Docs
----------------------------------------------------------------------
local Docs = T.Docs
check("a Plugins topic", Docs.find("plugins") ~= nil or Docs.get("plugins") ~= nil)
check("undo is documented", #Docs.search("undo") > 0)
check('var() is documented', #Docs.search('var("list1")') > 0 or #Docs.search("var") > 0)
for _, name in { "decompile", "save", "insert", "move", "undo" } do
	at = run("/help " .. name)
	check("/help " .. name, has(at, "/" .. name), lines(at))
end

----------------------------------------------------------------------
-- 13b. Services can't be dragged, cut or moved
----------------------------------------------------------------------
E.clearSearch()
E.select({})
E.View:SetOpen(E.Tree:NodeFor(workspace), false)
H.advance(0.2)
E.View.Scroll:ScrollTo(V2(0, 0), false)
H.advance(0.2)
local view = E.View
local function rowPoint(name)
	for _, entry in view.Entries do
		if entry.Index ~= 0 and entry.Row.Visible and view.Rows[entry.Index] and view.Rows[entry.Index].Name == name then
			return entry.Row.AbsolutePosition + V2(60, 11)
		end
	end
	local shown = {}
	for _, entry in view.Entries do
		if entry.Index ~= 0 and entry.Row.Visible then
			table.insert(shown, view.Rows[entry.Index].Name)
		end
	end
	error("no row " .. name .. " · shown: " .. table.concat(shown, ","))
end
H.press(H.toScreen(rowPoint("Workspace")))
H.moveTo(H.toScreen(rowPoint("ReplicatedStorage")))
check("Workspace can't be dragged", not view:IsDragging())
H.release()
H.advance(0.2)
check("…and stays put", workspace.Parent == H.game)
E.View:SetOpen(E.Tree:NodeFor(workspace), true)
H.advance(0.2)
H.press(H.toScreen(rowPoint("Map")))
H.moveTo(H.toScreen(rowPoint("Button")))
check("ordinary objects still drag", view:IsDragging())
H.key("Escape")
H.release()
H.advance(0.2)
check("Cut is greyed out for a service", items("explorer.object", { workspace })["Cut"].Disabled)
check("Jump to Parent is greyed out for a top-level datamodel", items("explorer.object", { workspace })["Jump to Parent"].Disabled)
check("…but not for objects inside one", not items("explorer.object", { map })["Jump to Parent"].Disabled)
at = run("/move game.ReplicatedStorage game.Workspace")
check("/move refuses a service: datamodels cannot be moved", workspace.Parent == H.game and has(at, "datamodels cannot be moved"), lines(at))
E.moveInto({ workspace }, rs)
check("Explorer.moveInto refuses too", workspace.Parent == H.game)

----------------------------------------------------------------------
-- 13c. Plugins tab: the "tungsten" settings entry
----------------------------------------------------------------------
T.Tabs:Select("plugins")
H.advance(0.3)
local page = T.Tabs.Pages.plugins
local card = H.find(page, "Entry_tungsten")
check("the Plugins tab lists a tungsten entry", card ~= nil)
local cardStroke = card and card:FindFirstChildOfClass("UIStroke")
check("…outlined in the accent color", cardStroke and cardStroke.Color == T.Theme.Colors.Accent)
check("…and it adds no tab", T.Registry.getTab("tungsten") == nil and T.Tabs.Entries.tungsten == nil)
check("…it is selected and shows the settings", T.Manager.Selected == "tungsten" and H.find(page, "Settings") ~= nil)
local P = T.Preferences
local missing = {}
for _, group in P.groups() do
	for _, entry in group.Items do
		if not H.find(page, "Pref_" .. entry.Id) then
			table.insert(missing, entry.Id)
		end
	end
end
check("every preference has a row", #missing == 0, table.concat(missing, ","))
local covered = {}
for _, group in P.groups() do
	for _, entry in group.Items do
		if entry.Setting then
			covered[entry.Setting] = true
		end
	end
end
local saved = {}
-- kept off the page on purpose (changed where they are used)
local elsewhere = { TabOrder = true, HiddenTabs = true, ExplorerSplit = true, Accent = true, ConsoleGameOutput = true,
	ConsoleTimestamps = true, ConsoleTraceback = true, PropertyDecimals = true, PropertiesDeprecated = true, PropertiesHidden = true }
for key in T.Settings.defaults() do
	if not T.Settings.isSession(key) and not covered[key] and not elsewhere[key] then
		table.insert(saved, key)
	end
end
check("every saved setting is on the page (except the ones with their own place)", #saved == 0, table.concat(saved, ","))
check("no redundant rows: explorer split, tab order, hidden tabs", not H.find(page, "Pref_split") and not H.find(page, "Pref_resetTabOrder") and not H.find(page, "Pref_showHiddenTabs"))
local rowIds = {}
for _, group in P.groups() do
	for _, entry in group.Items do
		table.insert(rowIds, entry.Id)
	end
end
check("the page keeps only window size, tooltips, the bar key, services first and Reset all", table.concat(rowIds, ",") == "scale,tooltips,barKey,sort,resetAll", table.concat(rowIds, ","))
check("no accent, console or other explorer rows", not H.find(page, "Pref_accent") and not H.find(page, "Pref_timestamps") and not H.find(page, "Pref_traceback") and not H.find(page, "Pref_gameOutput") and not H.find(page, "Pref_decimals") and not H.find(page, "Pref_deprecated") and not H.find(page, "Pref_hidden"))
-- the controls change the real settings
local sortToggle = T.Manager.Controls.sort.Widget
sortToggle:Set(false)
H.advance(0.1)
check("a switch changes its setting", T.Settings.get("ExplorerSort") == false)
sortToggle:Set(true)
H.advance(0.1)
run("/scale 1")
local stepper = T.Manager.Controls.scale.Widget
check("window size is a − / + stepper showing 100%", stepper.Label.Text == "100%", stepper.Label.Text)
H.clickObject(stepper.Up.Instance)
H.advance(0.2)
check("+ makes the window bigger", math.abs(T.Scale.effective() - 1.1) < 0.001 and stepper.Label.Text == "110%", stepper.Label.Text)
H.clickObject(stepper.Down.Instance)
H.clickObject(stepper.Down.Instance)
H.advance(0.2)
check("− makes it smaller", math.abs(T.Scale.effective() - 0.9) < 0.001 and stepper.Label.Text == "90%", stepper.Label.Text)
for _ = 1, 5 do
	H.clickObject(stepper.Down.Instance)
end
H.advance(0.2)
check("− greys out at the smallest size", math.abs(T.Scale.effective() - T.Scale.Min) < 0.001 and stepper.Down.Enabled == false)
for _ = 1, 20 do
	H.clickObject(stepper.Up.Instance)
end
H.advance(0.2)
check("+ greys out at the biggest size that fits", stepper.Up.Enabled == false and T.Scale.effective() <= T.Scale.limit() + 0.001)
run("/scale 1")
check("a command's change shows on the page", stepper.Label.Text == "100%", stepper.Label.Text)
H.clickObject(stepper.Up.Instance)
P.reset("scale")
H.advance(0.2)
check("Reset puts it back to 100%", T.Scale.effective() == 1 and stepper.Label.Text == "100%")
P.set("barKey", "F8")
check("the command bar key choice", T.Settings.get("CommandBarKey") == "F8")
P.set("barKey", "Quote")
T.Settings.set("PropertiesDeprecated", true)
T.Settings.set("ConsoleTraceback", true)
T.Settings.set("Accent", { 60, 160, 240 })
P.set("barKey", "F8")
P.resetAll()
H.advance(0.2)
check("Reset all settings puts back the ones off the page too", T.Settings.get("PropertiesDeprecated") == false and T.Settings.get("ConsoleTraceback") == false and T.Settings.get("Accent")[1] == T.Settings.defaults().Accent[1] and T.Settings.get("CommandBarKey") == "Quote")
check("…and the theme follows", T.Theme.Colors.Accent ~= E_.Color3.fromRGB(60, 160, 240))

----------------------------------------------------------------------
-- 13d. Groundwork for the plugin manager (no loader yet)
----------------------------------------------------------------------
local ApiModule = T.import("base/api")
local good = { Name = "Spawner", Version = "1.0", Settings = { { Id = "speed", Kind = "number", Text = "Speed", Default = 16, Min = 0, Max = 100 } }, Load = function() end }
check("a plugin definition checks out", ApiModule.checkDefinition(good, "Spawner") == nil, ApiModule.checkDefinition(good, "Spawner"))
check("…Name is required", ApiModule.checkDefinition({}, "x") == "Name is missing")
check("…it must be a table", ApiModule.checkDefinition(5) ~= nil)
check("…a bad Id is refused", ApiModule.checkDefinition({ Name = "a", Id = "has space" }) ~= nil)
check("…tungsten and core are taken", ApiModule.checkDefinition({ Name = "a", Id = "tungsten" }) ~= nil and ApiModule.checkDefinition({ Name = "a", Id = "core" }) ~= nil)
check("…a setting needs a known Kind", ApiModule.checkDefinition({ Name = "a", Settings = { { Id = "s", Kind = "slider", Default = 1 } } }) ~= nil)
check("…a setting's Default has the right type", ApiModule.checkDefinition({ Name = "a", Settings = { { Id = "s", Kind = "toggle", Default = 1 } } }) ~= nil)
check("…an action needs Run", ApiModule.checkDefinition({ Name = "a", Settings = { { Id = "go", Kind = "action" } } }) ~= nil)
check("…a Tab needs Build", ApiModule.checkDefinition({ Name = "a", Tab = { Title = "A" } }) ~= nil)
check("…Commands need Run", ApiModule.checkDefinition({ Name = "a", Commands = { { Name = "x" } } }) ~= nil)
check("the id defaults to the folder name, made safe", ApiModule.idFor({ Name = "a" }, "My Plugin") == "my_plugin")

-- a plugin's own settings
local path = "Tungsten/plugins/Spawner/settings.json"
local ranWith
local pApi = T.api("spawner", {
	Name = "Spawner",
	SettingsPath = path,
	Settings = {
		{ Id = "speed", Kind = "number", Text = "Speed", Default = 16, Min = 0, Max = 100 },
		{ Id = "loud", Kind = "toggle", Text = "Loud", Default = false },
		{ Id = "mode", Kind = "choice", Text = "Mode", Default = "a", Options = { "a", "b" } },
		{ Id = "tint", Kind = "color", Text = "Tint", Default = { 255, 0, 0 } },
		{ Id = "go", Kind = "action", Text = "Go", Run = function(api) ranWith = api end },
	},
})
local st = pApi.settings
check("settings start at their defaults", st.get("speed") == 16 and st.get("loud") == false and st.get("mode") == "a")
local heard
local conn = st.Changed:Connect(function(key, value) heard = { key, value } end)
check("a number is kept in range", st.set("speed", 500) and st.get("speed") == 100)
check("…Changed fires", heard and heard[1] == "speed" and heard[2] == 100)
check("the wrong type is refused", st.set("loud", "yes") == false and st.get("loud") == false)
check("a choice must be one of its options", st.set("mode", "z") == false and st.set("mode", "b") and st.get("mode") == "b")
check("a Color3 is stored as r, g, b", st.set("tint", E_.Color3.fromRGB(0, 128, 255)) and st.get("tint")[2] == 128)
check("an action has no value", st.set("go", 1) == false)
check("reset puts the default back", st.reset("speed") and st.get("speed") == 16)
st.set("speed", 42)
H.advance(0.6)
check("settings are saved next to the plugin", H.FILES[path] ~= nil and H.FILES[path]:find("42") ~= nil)
conn:Disconnect()
pApi.icons.register("spawner_icon", "Tungsten/base/data/icons/save.png")
check("a plugin can register an icon", T.Icons.list and table.find(T.Icons.list(), "spawner_icon") ~= nil)

-- the Plugins tab can show it (the manager will do this)
local M = T.Manager
check("the empty note shows with no plugins", H.find(page, "Empty").Visible == true)
M.addEntry({ Id = "spawner", Name = "Spawner", Version = "1.0", Author = "me", Description = "makes parts", Settings = st, Context = pApi })
check("an entry gets a card", H.find(page, "Entry_spawner") ~= nil)
check("…and the empty note hides", H.find(page, "Empty").Visible == false)
check("…the tungsten entry stays first and outlined", H.find(page, "Entry_tungsten") ~= nil)
check("selecting it shows its page", M.select("spawner") and M.Selected == "spawner" and H.find(page, "Pref_speed") ~= nil and H.find(page, "Pref_tint") ~= nil)
check("…the tungsten rows are gone from the page", H.find(page, "Pref_scale") == nil)
check("…with version and author", H.find(page, "Footer") and H.find(page, "Footer").Text:find("v1.0") and H.find(page, "Footer").Text:find("by me"))
M.Controls.loud.Widget:Set(true)
H.advance(0.1)
check("a row's switch changes the plugin's setting", st.get("loud") == true)
st.set("speed", 7)
check("a change from the plugin shows on the page", M.Controls.speed.Widget.Value == 7, M.Controls.speed.Widget.Value)
H.clickObject(M.Controls.go.Widget.Instance)
H.advance(0.1)
check("an action gets the plugin's api", ranWith == pApi)
check("selecting tungsten brings its settings back", M.select("tungsten") and H.find(page, "Pref_scale") ~= nil and H.find(page, "Pref_speed") == nil)
st.set("speed", 9) -- no page for it now; nothing should break
M.select("spawner")
check("removeEntry takes the card away", M.removeEntry("spawner") and H.find(page, "Entry_spawner") == nil)
check("…goes back to tungsten", M.Selected == "tungsten" and H.find(page, "Pref_scale") ~= nil)
check("…and the empty note is back", H.find(page, "Empty").Visible == true)
check("the tungsten entry can't be removed", M.removeEntry("tungsten") == false and H.find(page, "Entry_tungsten") ~= nil)

-- remove() and replacing
pApi:remove()
check("api:remove takes the plugin's icon away", table.find(T.Icons.list(), "spawner_icon") == nil)
check("…and saves its settings", H.FILES[path]:find('"speed":9') ~= nil, H.FILES[path])
check("a second remove does nothing", pApi:remove() == 0)
local again = T.api("spawner", { Name = "Spawner", SettingsPath = path, Settings = { { Id = "speed", Kind = "number", Text = "Speed", Default = 16 } } })
check("saved settings come back next time", again.settings.get("speed") == 9)
local replaced = T.api("spawner", { Name = "Spawner" })
check("a new api for the same id replaces the old one", ApiModule.get("spawner") == replaced and again:remove() == 0)
check("a console-made api keeps settings in memory", replaced.settings.set("x", 1) and replaced.settings.get("x") == 1 and replaced.settings.Path == nil)
replaced:remove()
check("nothing loads plugins yet (no manager)", T.PluginHost == nil and not H.FILES["Tungsten/plugins/Spawner/plugin.luau"])

----------------------------------------------------------------------
-- 13e. A 200 px explorer: sideways scrolling, long values, no hints
----------------------------------------------------------------------
do
T.Tabs:Select("console")
T.Scale.set(1)
H.advance(0.5)
local exHolder = T.Window.Root:FindFirstChild("Explorer")
check("the explorer is 200 px wide at the default size", math.abs(exHolder.AbsoluteSize.X - 200) < 1 and math.abs(T.Window.Root.AbsoluteSize.X - 760) < 1, exHolder.AbsoluteSize.X)
T.Scale.set(1.2)
H.advance(0.5)
check("…and grows with the window (the same share of it)", math.abs(exHolder.AbsoluteSize.X / T.Window.Root.AbsoluteSize.X - 200 / 760) < 0.01, exHolder.AbsoluteSize.X)
T.Scale.set(1)
H.advance(0.5)
local searchBox
for _, d in E.Panel:GetDescendants() do
	if d.ClassName == "TextBox" and d.PlaceholderText ~= "" and d.Parent and d.Parent.Name == "Search" then
		searchBox = d
	end
end
if not searchBox then
	for _, d in E.Panel:GetDescendants() do
		if d.ClassName == "TextBox" and tostring(d.PlaceholderText):find("Search", 1, true) then
			searchBox = d
		end
	end
end
check("the search box hint is just Search…", searchBox and searchBox.PlaceholderText == "Search…", searchBox and searchBox.PlaceholderText)

-- a long name deep in the tree
local deep = workspace
for i = 1, 6 do
	deep = make("Folder", "Level" .. i, deep)
end
local longName = "AVeryLongObjectNameThatIsMuchWiderThanTheExplorerPanel_" .. string.rep("x", 30)
local far = H.part(longName, deep)
H.advance(0.3)
E.select({ far })
H.advance(0.5)
local tv = E.View
local scroll = tv.Scroll
local farEntry
for _, entry in tv.Entries do
	if entry.Row.Visible and tv.Rows[entry.Index] and tv.Rows[entry.Index].Obj == far then
		farEntry = entry
	end
end
check("the long row is drawn", farEntry ~= nil)
local view = scroll:ViewSize()
check("the tree can scroll sideways", scroll:CanScroll("X") and scroll.Canvas.X > view.X, scroll.Canvas.X)
local labelEnd = farEntry and (farEntry.Label.Position.X.Offset + farEntry.Label.Size.X.Offset) or 0
check("…far enough to reach the end of the longest name", scroll.Canvas.X >= labelEnd, ("%d canvas vs name ending at %d"):format(scroll.Canvas.X, labelEnd))
check("the measured width matches what is drawn", math.abs(scroll.Canvas.X - tv:_rowEnd(tv.Rows[farEntry.Index], nil)) <= 1 or scroll.Canvas.X >= labelEnd)
scroll:ScrollTo(E_.Vector2.zero, false)
H.advance(0.1)
local treePoint = tv.Instance.AbsolutePosition + V2(60, 40)
H.keys.LeftShift = true
H.wheel(H.toScreen(treePoint), 3) -- wheel up moves right
H.keys.LeftShift = nil
H.advance(0.4)
check("Shift+wheel scrolls the tree sideways", scroll.Offset.X > 0, scroll.Offset.X)
scroll:ScrollTo(E_.Vector2.zero, false)
H.advance(0.1)
H.pan(H.toScreen(treePoint), -40) -- sideways input is reversed: negative moves right
H.advance(0.4)
check("a sideways wheel / touchpad scrolls it too", scroll.Offset.X > 0, scroll.Offset.X)
tv:Reveal(tv.Tree:NodeFor(far), false) -- its row in view (top to bottom)
scroll:ScrollTo(E_.Vector2.new(1e6, scroll.Offset.Y), false)
H.advance(0.2)
farEntry = nil
for _, entry in tv.Entries do
	if entry.Row.Visible and tv.Rows[entry.Index] and tv.Rows[entry.Index].Obj == far then
		farEntry = entry
	end
end
local viewRight = scroll.Instance.AbsolutePosition.X + scroll.Instance.AbsoluteSize.X
local nameRight = farEntry and farEntry.Label.AbsolutePosition.X + farEntry.Label.AbsoluteSize.X or math.huge
check("scrolled all the way, the whole name is in view", nameRight <= viewRight + 0.5, ("%d vs %d"):format(nameRight, viewRight))
check("…and the selected row's band still spans the canvas", farEntry and farEntry.Row.AbsoluteSize.X >= scroll.Canvas.X - 0.5)
local bar = scroll.Bars.X
check("a sideways scrollbar shows", bar and bar.Track.Visible ~= false)
-- a badge (e.g. a count) makes a row longer than its name: the canvas grows
local oldBadges = tv.Badges
tv.Badges = function(node)
	return if node.Obj == far then "12345 events" else nil
end
tv:Redraw()
H.advance(0.1)
local withBadge = scroll.Canvas.X
tv.Badges = oldBadges
check("a badge widens the canvas to fit", withBadge > labelEnd + 40, withBadge)
tv:Refresh()
H.advance(0.1)
scroll:ScrollTo(E_.Vector2.zero, false)
H.advance(0.1)

-- long values in properties: the editor still floats wider than the cell
local note = make("StringValue", "Note", workspace)
local longText = string.rep("long value text ", 12)
note.Name = "Note"
far.Name = longText:gsub(" ", "_")
E.select({ far })
H.advance(0.4)
local pv2 = E.PropView
local nameRow = pv2:Find("Name")
local valuePos, valueSize = pv2:ValueRect(nameRow)
local editor = pv2:EditText(nameRow)
H.advance(0.1)
check("a long value opens in the editor in full", editor and editor.Box.Text == far.Name, editor and editor.Box.Text)
local frame = editor and editor.Box.Parent.Parent
check("…the editor is at least as wide as before (170 px), wider than the cell", frame and frame.AbsoluteSize.X >= 170 and frame.AbsoluteSize.X >= valueSize.X, frame and frame.AbsoluteSize.X)
check("…it stays on the screen", frame and frame.AbsolutePosition.X + frame.AbsoluteSize.X <= H.SCREEN.X and frame.AbsolutePosition.X >= 0)
check("…and the text box clips and scrolls with the cursor", editor and editor.Box.ClipsDescendants == true and editor.Box.TextWrapped ~= true)
check("no hint under the box while editing a property", frame and frame:FindFirstChild("Hint") and frame.Hint.Visible == false and frame.AbsoluteSize.Y == editor.Box.Parent.AbsoluteSize.Y)
editor.Box.Text = longText .. "edited"
check("a long value saves", editor.Commit() and far.Name == longText .. "edited", far.Name)
H.advance(0.1)
-- an error still shows under the box
local sizeRow = pv2:Find("Size")
local sizeEditor = pv2:EditText(sizeRow)
H.advance(0.1)
local sframe = sizeEditor.Box.Parent.Parent
check("…no hint for other kinds either", sframe.Hint.Visible == false)
sizeEditor.Box.Text = "not a vector"
check("a bad value is refused", sizeEditor.Commit() == false)
check("…and the reason shows under the box", sframe.Hint.Visible == true and sframe.Hint.Text ~= "" and sframe.AbsoluteSize.Y > sizeEditor.Box.Parent.AbsoluteSize.Y, sframe.Hint.Text)
sizeEditor.Box.Text = "4, 4, 4"
check("…typing hides it again", sframe.Hint.Visible == false)
sizeEditor:Close("test")
H.advance(0.1)
-- other editors keep their hint (e.g. renaming in the tree)
local CellEditor = T.import("base/ui/components/celleditor")
local plain = CellEditor.open({ AnchorPos = V2(100, 100), AnchorSize = V2(120, 22), Text = "x" })
H.advance(0.1)
check("editors outside properties keep their hint", plain.Box.Parent.Parent.Hint.Visible == true and plain.Box.Parent.Parent.Hint.Text ~= "")
plain:Close("test")
far.Name = "Far"
note:Destroy()
deep = workspace:FindFirstChild("Level1")
if deep then
	deep:Destroy()
end
H.advance(0.3)

end
----------------------------------------------------------------------
-- 13f. Freeze
----------------------------------------------------------------------
do
local tree = E.Tree
local tv2 = E.View
local fb = E.FreezeButton
local filterB = E.FilterButton
local searchFrame
for _, d in E.Panel:GetChildren() do
	if d.Name == "Search" then
		searchFrame = d
	end
end
check("a freeze button is there", fb ~= nil and fb:FindFirstChild("Icon") ~= nil or fb ~= nil)
check("…right of the filter button, both right of the search bar", searchFrame
	and searchFrame.AbsolutePosition.X + searchFrame.AbsoluteSize.X <= filterB.AbsolutePosition.X
	and filterB.AbsolutePosition.X + filterB.AbsoluteSize.X <= fb.AbsolutePosition.X
	and math.abs(fb.AbsolutePosition.X + fb.AbsoluteSize.X - (E.Panel.AbsolutePosition.X + E.Panel.AbsoluteSize.X - 8)) <= 1
	and fb.AbsolutePosition.Y == filterB.AbsolutePosition.Y and fb.AbsoluteSize == filterB.AbsoluteSize)
check("…and the same height as the search bar", searchFrame and searchFrame.AbsoluteSize.Y == fb.AbsoluteSize.Y)
check("not frozen at start", not E.isFrozen())

local box = make("Folder", "FreezeBox", workspace)
local a1 = H.part("Alpha", box)
local b1 = H.part("Bravo", box)
local c1 = H.part("Charlie", box)
local other = make("Folder", "Elsewhere", workspace)
H.advance(0.3)
E.select({ b1 })
H.advance(0.3)
tv2:SetOpen(tree:NodeFor(other), true)
H.advance(0.3)
local function rowIndex(obj)
	for index, node in tv2.Rows do
		if node.Obj == obj then
			return index, node
		end
	end
	return nil
end
local function entryOf(obj)
	local node = tree:Get(obj)
	tv2:Reveal(node, false)
	tv2:Redraw()
	for _, entry in tv2.Entries do
		if entry.Row.Visible and tv2.Rows[entry.Index] == node then
			return entry
		end
	end
	return nil
end
local bravoBefore = rowIndex(b1)
check("rows are there before freezing", rowIndex(a1) and bravoBefore and rowIndex(c1))

H.clickObject(fb)
H.advance(0.3)
check("clicking the button freezes the explorer", E.isFrozen() and tree.Frozen)
check("…the button lights up", fb.BackgroundColor3 == T.Theme.Colors.AccentSoft)
check("…and the status line says so", E.Status.Text:find("frozen", 1, true) ~= nil, E.Status.Text)

-- new objects wait
local newPart = H.part("Aardvark", box)
H.advance(0.3)
check("frozen: a new object is not added", rowIndex(newPart) == nil and tree:Get(newPart) == nil)
check("…and nothing moved", rowIndex(b1) == bravoBefore)
-- removed objects stay, red
c1.Parent = nil
H.advance(0.3)
local _, cNode = rowIndex(c1)
check("frozen: a removed object keeps its row", cNode ~= nil and cNode.Gone == true)
local cEntry = entryOf(c1)
check("…shown red", cEntry and cEntry.Label.TextColor3 == T.Theme.Colors.Danger and cEntry.Row.BackgroundColor3 == T.Theme.Colors.Danger and cEntry.Row.BackgroundTransparency < 1)
check("…the status counts it", E.Status.Text:find("1 deleted", 1, true) ~= nil, E.Status.Text)
-- moved objects stay where they were, red
a1.Parent = other
H.advance(0.3)
local _, aNode = rowIndex(a1)
check("frozen: a moved object stays at its old place, light blue", aNode and aNode.Parent == tree:Get(box) and aNode.Gone == true and tree:FrozenState(aNode) == "moved")
local aEntry = entryOf(a1)
check("…drawn light blue", aEntry and aEntry.Label.TextColor3 == T.Theme.Colors.Moved and aEntry.Row.BackgroundColor3 == T.Theme.Colors.Moved)
check("…and doesn't appear at the new place yet", #tree:Get(other).Children == 0)
-- renames keep the order
local before = rowIndex(b1)
b1.Name = "Zulu"
H.advance(0.3)
local after, bNode = rowIndex(b1)
check("frozen: a rename changes the text, not the order", after == before and bNode.Name == "Zulu")
-- coming back
c1.Parent = box
H.advance(0.3)
check("an object that comes back to its place is no longer red", not tree:Get(c1).Gone)
check("…the count follows", E.Status.Text:find("frozen · 1 moved", 1, true) ~= nil and E.Status.Text:find("deleted", 1, true) == nil, E.Status.Text)
-- the selection and editing still work while frozen
E.select({ b1 })
H.advance(0.2)
check("selecting still works while frozen", E.getSelection()[1] == b1)

-- unfreeze
local selectedNode = tree:Get(a1)
E.select({ a1 })
H.advance(0.2)
c1.Parent = nil
H.advance(0.2)
H.clickObject(fb)
H.advance(0.4)
check("clicking again unfreezes", not E.isFrozen() and fb.BackgroundColor3 ~= T.Theme.Colors.AccentSoft)
check("…new objects appear", rowIndex(newPart) ~= nil)
check("…removed ones are gone", rowIndex(c1) == nil and tree:Get(c1) == nil)
local _, movedNode = rowIndex(a1)
check("…moved ones are at their new place", movedNode and movedNode.Parent == tree:Get(other))
check("…keeping their row (and selection)", movedNode == selectedNode and E.getSelection()[1] == a1)
check("…and the order catches up with renames", (function()
	local names = {}
	for _, child in tree:Get(box).Children do
		table.insert(names, child.Name)
	end
	return table.concat(names, ",") == "Aardvark,Zulu"
end)())
local anyGone = false
for _, node in tree.Nodes do
	if node.Gone then
		anyGone = true
	end
end
check("…nothing is red any more", not anyGone and (tree.GoneCount or 0) == 0)
check("…and the status line no longer says frozen", E.Status.Text:find("frozen", 1, true) == nil, E.Status.Text)
-- live again
local live = H.part("Live", box)
H.advance(0.3)
check("unfrozen, new objects show up again", rowIndex(live) ~= nil)

-- console
at = run("/explorer freeze")
check("/explorer freeze", E.isFrozen() and has(at, "explorer frozen"), lines(at))
check("…just says explorer frozen", lines(at):match("explorer frozen%s*$") ~= nil and not has(at, "stops changing"), lines(at))
at = run("/explorer freeze on")
check("…again says it already is", has(at, "already frozen"), lines(at))
at = run("/explorer unfreeze")
check("/explorer unfreeze", not E.isFrozen() and has(at, "explorer unfrozen"), lines(at))
check("…just says explorer unfrozen", lines(at):match("explorer unfrozen%s*$") ~= nil and not has(at, "caught up"), lines(at))
run("/explorer freeze on")
check("/explorer freeze on", E.isFrozen())
run("/explorer freeze off")
check("/explorer freeze off", not E.isFrozen())
E.setFrozen(true)
check("freezing isn't saved as a setting", T.Settings.get("ExplorerFrozen") == nil)
E.setFrozen(false)
box:Destroy()
other:Destroy()
H.advance(0.3)

end
----------------------------------------------------------------------
-- 13g. Freeze: the tree keeps up underneath, deleted rows red then gone
----------------------------------------------------------------------
do
local ftree = E.Tree
local fview = E.View
local function shown(obj)
	for _, node in fview.Rows do
		if node.Obj == obj then
			return node
		end
	end
	return nil
end
local function redRow(obj)
	local node = ftree:Get(obj)
	if not node then
		return false
	end
	fview:Reveal(node, false)
	fview:Redraw()
	for _, entry in fview.Entries do
		if entry.Row.Visible and fview.Rows[entry.Index] == node then
			return entry.Label.TextColor3 == T.Theme.Colors.Danger and entry.Row.BackgroundColor3 == T.Theme.Colors.Danger
		end
	end
	return false
end
local holder = make("Folder", "Holder", workspace)
local shut = make("Folder", "Shut", holder) -- never opened before freezing
local keep = H.part("Keep", shut)
local crateBox = make("Model", "CrateBox", holder)
local inner1 = H.part("Inner1", crateBox)
local inner2 = H.part("Inner2", crateBox)
H.advance(0.3)
E.select({ inner1 })
H.advance(0.3)
check("set up: the model's children are on show", shown(inner1) and shown(inner2))
E.setFrozen(true)
H.advance(0.1)

-- new objects: tracked, not shown, even in a folder opened for the first time
local late = H.part("Late", shut)
H.advance(0.2)
fview:SetOpen(ftree:NodeFor(shut), true)
H.advance(0.3)
check("frozen: opening a folder for the first time shows what was there", shown(keep) ~= nil)
check("…but not what was added after freezing", shown(late) == nil)
check("…and selecting a new object doesn't put it in the tree", (function()
	E.select({ late })
	H.advance(0.2)
	return shown(late) == nil
end)())
local lateDeep = make("Folder", "LateFolder", holder)
local lateKid = H.part("LateKid", lateDeep)
H.advance(0.2)
check("…new folders (and what is in them) stay out too", shown(lateDeep) == nil and shown(lateKid) == nil)

-- deleted: the object and everything shown inside it turn red
crateBox.Parent = nil
H.advance(0.2)
check("frozen: a deleted model keeps its row, red", shown(crateBox) and redRow(crateBox))
local function softRedRow(obj)
	local node = ftree:Get(obj)
	fview:Reveal(node, false)
	fview:Redraw()
	for _, entry in fview.Entries do
		if entry.Row.Visible and fview.Rows[entry.Index] == node then
			return entry.Label.TextColor3 == T.Theme.Colors.DangerSoft and entry.Row.BackgroundColor3 == T.Theme.Colors.Danger and entry.Row.BackgroundTransparency > 0.85
		end
	end
	return false
end
check("…the rows inside it stay, light red (they went with it)", shown(inner1) and softRedRow(inner1) and softRedRow(inner2) and ftree:FrozenState(ftree:Get(inner1)) == "inside_deleted")
check("…the status counts the deleted object once", E.Status.Text:find("frozen · 1 deleted", 1, true) ~= nil, E.Status.Text)
local destroyed = H.part("Destroyed", holder)
E.setFrozen(false)
H.advance(0.2)
E.setFrozen(true)
H.advance(0.1)
check("set up: shown", shown(destroyed) ~= nil)
destroyed:Destroy()
H.advance(0.2)
check("frozen: a destroyed object keeps its row, red", shown(destroyed) and redRow(destroyed))

-- unfreeze: the tree is what the game is now
E.setFrozen(false)
H.advance(0.3)
check("unfrozen: deleted objects disappear", shown(crateBox) == nil and shown(destroyed) == nil and ftree:Get(crateBox) == nil and ftree:Get(destroyed) == nil)
check("…with what was inside them", shown(inner1) == nil and shown(inner2) == nil and ftree:Get(inner1) == nil)
check("…the deleted selection is dropped", #E.getSelection() == 0 or E.getSelection()[1] ~= inner1)
check("…new objects appear", shown(late) ~= nil and shown(lateDeep) ~= nil)
fview:SetOpen(ftree:NodeFor(lateDeep), true)
H.advance(0.3)
check("…and what is inside new folders", shown(lateKid) ~= nil)
check("…nothing is red", not redRow(keep) and not redRow(late))
-- after unfreezing, a later freeze starts clean
E.setFrozen(true)
local again = H.part("Again", shut)
H.advance(0.2)
check("a second freeze hides only what is new since then", shown(again) == nil and shown(late) ~= nil)
E.setFrozen(false)
H.advance(0.2)
check("…and shows it after", shown(again) ~= nil)
holder:Destroy()
H.advance(0.3)

end
----------------------------------------------------------------------
-- 13h. Freeze colours: deleted / inside deleted / moved, and variables
----------------------------------------------------------------------
do
local ht = E.Tree
local hv = E.View
local function stateOf(obj)
	return E.frozenState(obj)
end
local function colours(obj)
	local node = ht:Get(obj)
	hv:Reveal(node, false)
	hv:Redraw()
	for _, entry in hv.Entries do
		if entry.Row.Visible and hv.Rows[entry.Index] == node then
			return entry.Label.TextColor3, entry.Row.BackgroundColor3
		end
	end
	return nil
end
local C3 = T.Theme.Colors
local base = make("Folder", "ColourBase", workspace)
local model = make("Model", "Doomed", base)
local kidA = H.part("KidA", model)
local kidB = H.part("KidB", model)
local saved = H.part("Saved", model) -- moved out before the model goes
local target = make("Folder", "Target", base)
local mover = make("Model", "Mover", base)
local riding = H.part("Riding", mover)
H.advance(0.3)
E.select({ kidA, riding })
H.advance(0.3)
E.select({ riding })
H.advance(0.2)
T.Variables.set("doomed", model)
T.Variables.set("kid", kidA)
T.Variables.set("mv", mover)
T.Variables.set("crew", T.Variables.group({ kidA, kidB, saved, riding }))
E.setFrozen(true)
H.advance(0.1)

saved.Parent = target -- reparented out of the model first
model.Parent = nil -- then the model is deleted
mover.Parent = target -- a whole model moved
H.advance(0.3)
check("deleted object: red", stateOf(model) == "deleted" and colours(model) == C3.Danger)
local kt, kb = colours(kidA)
check("its children: still shown, light red", stateOf(kidA) == "inside_deleted" and kt == C3.DangerSoft and kb == C3.Danger)
local st, sb = colours(saved)
check("a child moved out before the delete: light blue (it still exists)", stateOf(saved) == "moved" and st == C3.Moved and sb == C3.Moved)
local mt = colours(mover)
check("moved object: light blue", stateOf(mover) == "moved" and mt == C3.Moved)
local rt = colours(riding)
check("…and what moved with it: light blue", stateOf(riding) == "inside_moved" and rt == C3.Moved)
check("the status line counts both kinds", E.Status.Text:find("frozen · 1 deleted · 2 moved", 1, true) ~= nil, E.Status.Text)
-- the marks follow the objects
mover.Parent = nil
H.advance(0.2)
check("moved, then deleted: turns red", stateOf(mover) == "deleted" and colours(mover) == C3.Danger)
mover.Parent = target
H.advance(0.2)
check("deleted, then put somewhere: light blue again", stateOf(mover) == "moved")

-- variables
local at = run("/vars")
check("/vars tags a deleted object", has(at, "doomed") and has(at, "deleted (frozen)"), lines(at))
check("…one deleted with its parent", has(at, "deleted with its parent (frozen)"), lines(at))
check("…a moved one", has(at, "moved (frozen)"), lines(at))
check("…and counts inside a group", has(at, "2 deleted with its parent (frozen)") and has(at, "1 moved (frozen)") and has(at, "1 moved with its parent (frozen)"), lines(at))
local info = T.Variables.info("kid")
check("Variables.info says what happened (for plugins)", info.Frozen == "inside_deleted")
local groupInfo = T.Variables.info("crew")
check("…counts for a group", type(groupInfo.Frozen) == "table" and groupInfo.Frozen.inside_deleted == 2 and groupInfo.Frozen.moved == 1 and groupInfo.Frozen.inside_moved == 1)
local papi = T.api("freezeprobe", { Name = "Probe" })
check("plugins see it too", papi.explorer.isFrozen() and papi.explorer.frozenState(model) == "deleted" and papi.variables.frozenState(kidA) == "inside_deleted")
papi:remove()
at = #C.Lines + 1
C.inspect(mover)
H.advance(0.2)
check("View in console says it moved, and where to", has(at, "moved while the explorer is frozen") and has(at, "now in game.Workspace.ColourBase.Target"), lines(at))
at = #C.Lines + 1
C.inspect(kidA)
H.advance(0.2)
check("…or that it was deleted with its parent", has(at, "deleted with its parent while the explorer is frozen"), lines(at))
-- selecting through variables lands on the frozen rows
run("/select $mv")
H.advance(0.2)
check("/select $var on a moved object selects its (light blue) row", E.getSelection()[1] == mover and hv.Primary == ht:Get(mover) and ht:Get(mover).Parent == ht:Get(base))
run("/select $kid")
H.advance(0.2)
check("…and on an object deleted with its parent", E.getSelection()[1] == kidA and hv.Primary == ht:Get(kidA))
check("$sel holds it", T.Variables.get("sel") == kidA)

-- unfreeze: deleted ones leave (children too), moved ones go to their place
E.setFrozen(false)
H.advance(0.3)
check("unfrozen: the deleted model and its children are gone", ht:Get(model) == nil and ht:Get(kidA) == nil and ht:Get(kidB) == nil)
check("…moved ones are at their new place (inside the folder they went to)", ht:NodeFor(saved) and ht:NodeFor(saved).Parent == ht:Get(target) and ht:NodeFor(mover).Parent == ht:Get(target) and ht:Get(base) and ht:NodeFor(target).Parent == ht:Get(base))
check("…nothing has a frozen state", stateOf(mover) == nil and stateOf(saved) == nil and T.Variables.info("crew").Frozen == nil)
at = run("/vars")
check("/vars no longer tags anything", not has(at, "(frozen)"), lines(at))
check("…variables still hold their objects", T.Variables.get("doomed") == model and T.Variables.get("mv") == mover)
for _, name in { "doomed", "kid", "mv", "crew" } do
	T.Variables.unset(name)
end
base:Destroy()
H.advance(0.3)

end
----------------------------------------------------------------------
-- 13i. Freeze: a moved object stays under its original parent, even
-- when the folder it went to is opened
----------------------------------------------------------------------
do
	local it = E.Tree
	local iv = E.View
	local home = make("Folder", "Home", workspace)
	local away = make("Folder", "Away", workspace) -- not opened before freezing
	local traveller = make("Model", "Traveller", home)
	local passenger = H.part("Passenger", traveller)
	local stayer = H.part("Stayer", away)
	H.advance(0.3)
	E.select({ passenger })
	H.advance(0.3)
	local node = it:Get(traveller)
	check("set up: under Home, Away not loaded", node and node.Parent == it:Get(home) and it:Get(away) and not it:Get(away).Loaded)
	E.setFrozen(true)
	traveller.Parent = away
	H.advance(0.2)
	-- open the folder it went to, every way there is
	iv:SetOpen(it:Get(away), true)
	H.advance(0.3)
	local function rowsUnder(folder)
		local names = {}
		for _, child in it:Get(folder).Children or {} do
			table.insert(names, child.Name)
		end
		table.sort(names)
		return table.concat(names, ",")
	end
	check("opening the new parent doesn't move it there", it:Get(traveller) == node and node.Parent == it:Get(home), node.Parent and node.Parent.Name)
	check("…the new parent shows only what it had", rowsUnder(away) == "Stayer", rowsUnder(away))
	check("…it is still under Home, light blue", rowsUnder(home) == "Traveller" and E.frozenState(traveller) == "moved")
	check("…and only once in the rows", (function()
		local count = 0
		for _, row in iv.Rows do
			if row.Obj == traveller then
				count += 1
			end
		end
		return count == 1
	end)())
	-- other ways of loading it
	E.select({ stayer })
	H.advance(0.2)
	run("/expand game.Workspace.Away all")
	H.advance(0.2)
	E.select({ traveller })
	H.advance(0.2)
	check("selecting or expanding doesn't move it either", it:Get(traveller).Parent == it:Get(home) and iv.Primary == node)
	check("…its children stay with it", it:Get(passenger) and it:Get(passenger).Parent == node and E.frozenState(passenger) == "inside_moved")
	-- moved again, into a folder that IS loaded
	traveller.Parent = workspace
	H.advance(0.2)
	check("moved again: still under Home, still light blue", it:Get(traveller).Parent == it:Get(home) and E.frozenState(traveller) == "moved")
	traveller.Parent = away
	H.advance(0.2)
	-- unfreeze: now it goes
	E.setFrozen(false)
	H.advance(0.3)
	check("unfrozen: it moves to where it is now, same row", it:Get(traveller) == node and node.Parent == it:Get(away) and rowsUnder(away) == "Stayer,Traveller" and rowsUnder(home) == "")
	check("…not light blue any more", E.frozenState(traveller) == nil)
	home:Destroy()
	away:Destroy()
	H.advance(0.3)
end

----------------------------------------------------------------------
-- 14. Re-run keeps one hook, closing unblocks
----------------------------------------------------------------------
RemoteBlock.block(remote)
local okRun = H.run("Tungsten/Tungsten.luau")
H.advance(1)
check("re-run ok", okRun)
check("re-running doesn't stack a second hook", H.HOOKS == 1, H.HOOKS)
check("closing the old copy unblocked everything", gameCall(remote, "FireServer") == "passed")
check("a new run starts unfrozen", not H.genv.Tungsten.Context.Explorer.isFrozen())

check("no runtime errors", #H.ERRORS == 0, H.ERRORS[1])
print(("stage4d: %d passed, %d failed, %d runtime errors"):format(passed, failed, #H.ERRORS))
