-- Stage 4 round A: explorer panel, tree, search, selection + $sel, path
-- bar, right-click menu skeleton, explorer commands.
local passed, failed = 0, 0
local function check(name, cond, detail)
	if cond then
		passed += 1
	else
		failed += 1
		print("FAIL: " .. name .. (if detail ~= nil then "  [" .. tostring(detail) .. "]" else ""))
	end
end
local V2 = H.env.Vector2.new
H.ABS_SHIFT = SHIFT or 0
local new = H.env.Instance.new
local game = H.game
local workspace = H.env.workspace

----------------------------------------------------------------------
-- A small game
----------------------------------------------------------------------
local function make(class, name, parent)
	local o = new(class)
	o.Name = name
	o.Parent = parent
	return o
end
local baseplate = make("Part", "Baseplate", workspace)
local map = make("Model", "Map", workspace)
local door = make("Part", "Door", map)
local click = make("ClickDetector", "ClickDetector", door)
local lamp = make("Part", "Lamp", map)
local spawns = make("Folder", "Spawns", map)
local spawn1 = make("SpawnLocation", "Spawn 1", spawns)
local rs = H.services.ReplicatedStorage
local remotes = make("Folder", "Remotes", rs)
local fire = make("RemoteEvent", "Fire", remotes)
local ask = make("RemoteFunction", "Ask", remotes)
local fast = make("UnreliableRemoteEvent", "Fast", remotes)
local bind = make("BindableEvent", "Bind", remotes)
local module = make("ModuleScript", "Loader", rs)
H.LOADED = { module }
local orphan = make("Folder", "Orphan", nil)
local inner = make("LocalScript", "Inner", orphan)
H.NIL = { orphan }
-- The hidden UI container is inside the game here, so hiding is tested.
H.HUI.Name = "HiddenUI"
H.HUI.Parent = game

local ok, err = H.run("Tungsten/Tungsten.luau")
check("loader runs", ok, err)
H.advance(1)
local T = H.genv.Tungsten.Context
local W, Overlay, Scale = T.Window, T.Overlay, T.Scale
local E, P, C = T.Explorer, T.PathBar, T.Console
local Variables = T.Variables
local view = E.View
local tree = E.Tree
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
	H.advance(0.2)
	return at
end
local function has(at, text)
	return lines(at):find(text, 1, true) ~= nil
end
local function rowNames()
	local out = {}
	for _, node in view.Rows do
		table.insert(out, node.Name)
	end
	return table.concat(out, ",")
end
local function entryFor(name)
	for _, entry in view.Entries do
		if entry.Index ~= 0 and entry.Row.Visible and view.Rows[entry.Index] and view.Rows[entry.Index].Name == name then
			return entry
		end
	end
	return nil
end
local function clickRow(name, button)
	local entry = entryFor(name)
	assert(entry, "no row " .. name)
	return H.clickObject(entry.Row, button)
end
local function clickArrow(name)
	local entry = entryFor(name)
	assert(entry, "no row " .. name)
	local p, s = entry.Arrow.AbsolutePosition, entry.Arrow.AbsoluteSize
	return H.click(H.toScreen(p + s / 2))
end
local function withKey(key, fn)
	H.keys[key] = true
	fn()
	H.keys[key] = nil
end
local function selectedNames()
	local out = {}
	for _, obj in E.getSelection() do
		table.insert(out, obj.Name)
	end
	return table.concat(out, ",")
end

----------------------------------------------------------------------
-- 1. Panel geometry
----------------------------------------------------------------------
local holder = W.Root:FindFirstChild("Explorer")
check("explorer is part of the window", holder ~= nil)
local rootPos, rootSize = W.Root.AbsolutePosition, W.Root.AbsoluteSize
local hp, hs = holder.AbsolutePosition, holder.AbsoluteSize
check("explorer on the right edge", math.abs(hp.X - (rootPos.X + rootSize.X)) <= 1, tostring(hp) .. " vs " .. tostring(rootPos + rootSize))
local panelSize = E.Panel.AbsoluteSize
check("explorer panel is 200/760 of the window (200 px at scale 1)", math.abs(panelSize.X - rootSize.X * 200 / 760) <= 1, panelSize.X)
check("at scale 1 the explorer is 200 px wide", math.floor(Scale.BaseSize.X * Scale.SideShare + 0.5) == 200)
check("explorer panel as tall as the window", panelSize.Y == rootSize.Y, panelSize.Y)
check("explorer panel starts a gap after the window", math.abs(E.Panel.AbsolutePosition.X - (rootPos.X + rootSize.X + Scale.SideGap)) <= 1 and E.Panel.AbsolutePosition.Y == rootPos.Y)
check("no gap: the explorer joins the window", Scale.SideGap == 0 and hs.Y == rootSize.Y and math.abs(E.Panel.AbsolutePosition.X - (rootPos.X + rootSize.X)) <= 1)
check("one outline around both", math.abs(W.OutlineFrame.AbsoluteSize.X - (rootSize.X + panelSize.X)) <= 1 and W.BackingSquare.Visible)
check("footprint fits the screen", W.Pos.X >= 0 and W.Pos.X + W:Footprint().X <= H.SCREEN.X, tostring(W.Pos) .. " " .. tostring(W:Footprint()))
-- dragging moves the explorer too
local title = W.TitleBar
local tp = title.AbsolutePosition + V2(60, 10)
H.press(H.toScreen(tp))
H.moveTo(H.toScreen(tp + V2(-50, 30)))
H.release()
H.advance(0.3)
check("window dragged", W.Pos.Y > 100, tostring(W.Pos))
check("explorer moved with it", math.abs(holder.AbsolutePosition.X - (W.Root.AbsolutePosition.X + W.Root.AbsoluteSize.X)) <= 1)
W:MoveTo(V2(5000, 100))
H.advance(0.3)
check("dragging right keeps the explorer on screen", W.Pos.X + W:Footprint().X <= H.SCREEN.X, W.Pos.X)
-- scale changes keep the share
Scale.set(0.8)
H.advance(0.5)
check("explorer follows the scale", math.abs(E.Panel.AbsoluteSize.X - W.Root.AbsoluteSize.X * 200 / 760) <= 1, E.Panel.AbsoluteSize.X)
Scale.set(1)
H.advance(0.5)
check("path bar strip above the content", W.PathStrip.AbsolutePosition.Y < W.Content.AbsolutePosition.Y)
check("pages sit below the path bar", W.Content.AbsolutePosition.Y >= W.PathStrip.AbsolutePosition.Y + W.PathStrip.AbsoluteSize.Y)

----------------------------------------------------------------------
-- 2. Tree basics
----------------------------------------------------------------------
check("services first, in order", rowNames() == "Workspace,Lighting,ReplicatedStorage,StarterGui,HiddenUI,Nil Instances", rowNames())
check("Tungsten's own UI is hidden", tree:IsHidden(W.Gui) and tree:IsHidden(T.Overlay.gui()))
local huiNode = tree:NodeFor(H.HUI)
tree:Load(huiNode)
check("hidden UI container lists no Tungsten guis", #huiNode.Children == 0, #huiNode.Children)
check("children load lazily", tree:Get(map) == nil)
local wsEntry = entryFor("Workspace")
check("Workspace row has an arrow", wsEntry and wsEntry.Arrow.Visible)
check("service icon", wsEntry and wsEntry.IconName == "class_model" or wsEntry.IconName == "class_service", wsEntry and wsEntry.IconName)
clickArrow("Workspace")
H.advance(0.2)
check("arrow opens Workspace", rowNames():find("Workspace,Baseplate,Map,Lighting", 1, true) ~= nil, rowNames())
check("arrow turns", entryFor("Workspace").Arrow.Rotation == 90)
check("Baseplate has no arrow", not entryFor("Baseplate").Arrow.Visible)
check("part icon", entryFor("Baseplate").IconName == "class_part", entryFor("Baseplate").IconName)
check("arrow click doesn't select", #E.getSelection() == 0)
-- double-click opens
clickRow("Map")
clickRow("Map")
H.advance(0.2)
check("double-click opens Map", rowNames():find("Map,Door,Lamp,Spawns", 1, true) ~= nil, rowNames())
check("Map loaded now", tree:Get(map) ~= nil and tree:Get(map).Loaded)

-- live updates
local zed = make("Part", "Alpha", workspace)
H.advance(0.2)
check("new child appears sorted", rowNames():find("Workspace,Alpha,Baseplate", 1, true) ~= nil, rowNames())
zed.Name = "Zed"
H.advance(0.2)
check("rename re-sorts", rowNames():find("Spawns,Zed,Lighting", 1, true) ~= nil, rowNames())
lamp.Parent = workspace
H.advance(0.2)
check("moved object follows", rowNames():find("Workspace,Baseplate,Lamp,Map,Door,Spawns,Zed", 1, true) ~= nil, rowNames())
-- a selected object keeps its selection, and an open one stays open, when moved
E.select({ lamp })
local lampNode = T.Explorer.Tree:Get(lamp)
lamp.Parent = map
H.advance(0.2)
check("a moved object keeps its node and selection", T.Explorer.Tree:Get(lamp) == lampNode and selectedNames() == "Lamp" and Variables.get("sel") == lamp, selectedNames())
check("its depth follows the new parent", lampNode.Depth == 2, lampNode.Depth)
E.clearSelection()
zed:Destroy()
H.advance(0.2)
check("destroyed object disappears", rowNames():find("Zed", 1, true) == nil, rowNames())
-- order setting
run("/explorer sort off")
H.advance(0.2)
check("sort off: game order", rowNames():find("Workspace,Baseplate,Map,Door,Spawns,Lamp", 1, true) ~= nil, rowNames())
run("/explorer sort on")
H.advance(0.2)
check("sort on again", rowNames():find("Map,Door,Lamp,Spawns", 1, true) ~= nil, rowNames())
check("sort setting saved", T.Settings.get("ExplorerSort") == true)

----------------------------------------------------------------------
-- 3. Selection, $sel, keys
----------------------------------------------------------------------
clickRow("Door")
H.advance(0.1)
check("click selects", selectedNames() == "Door", selectedNames())
check("$sel is the instance", Variables.get("sel") == door)
check("selected row painted", entryFor("Door").Mark.Visible)
withKey("LeftControl", function()
	clickRow("Baseplate")
end)
H.advance(0.1)
check("ctrl+click adds", selectedNames() == "Baseplate,Door", selectedNames())
local sel = Variables.get("sel")
check("$sel is a table for several", type(sel) == "table" and #sel == 2, typeof(sel))
clickRow("Map")
H.advance(0.4)
withKey("LeftShift", function()
	clickRow("Spawns")
end)
H.advance(0.1)
check("shift+click range", selectedNames() == "Map,Door,Lamp,Spawns", selectedNames())
-- keyboard (the tree is active after the click)
clickRow("Door")
H.advance(0.4)
H.key("Down")
check("Down moves", selectedNames() == "Lamp", selectedNames())
H.key("Up")
H.key("Up")
check("Up moves", selectedNames() == "Map", selectedNames())
H.key("Left")
check("Left closes", rowNames():find("Map,Lamp", 1, true) == nil and rowNames():find("Map,Zed", 1, true) == nil and rowNames():find("Map,Lighting", 1, true) ~= nil, rowNames())
H.key("Right")
check("Right opens", rowNames():find("Map,Door", 1, true) ~= nil, rowNames())
H.key("Right")
check("Right again goes to first child", selectedNames() == "Door", selectedNames())
H.key("Left")
check("Left on a leaf goes to the parent", selectedNames() == "Map", selectedNames())
H.key("Home")
check("Home", selectedNames() == "Workspace", selectedNames())
H.key("End")
check("End selects the nil node (no instances)", #E.getSelection() == 0 and view.Primary == tree.NilNode)
withKey("LeftShift", function()
	H.key("Up")
end)
check("Shift+Up extends", view.SelectedCount == 2, view.SelectedCount)
withKey("LeftControl", function()
	H.key("A")
end)
check("Ctrl+A selects every row", view.SelectedCount == #view.Rows, view.SelectedCount)
-- clicking elsewhere stops keys
clickRow("Door")
H.advance(0.4)
H.click(H.toScreen(W.Content.AbsolutePosition + V2(50, 50)))
H.key("Down")
check("keys stop after clicking outside", selectedNames() == "Door", selectedNames())

-- rename (F2)
clickRow("Lamp")
H.advance(0.4)
H.key("F2")
H.advance(0.1)
local editor = view.Renaming
check("F2 opens a rename box", editor ~= nil and not editor.Closed)
if editor and not editor.Closed then
	editor.Box.Text = "Lantern"
	H.focused = nil
	editor.Box.FocusLost:Fire(true)
	H.advance(0.2)
end
check("renamed", lamp.Name == "Lantern", lamp.Name)
check("rename re-sorted", rowNames():find("Door,Lantern,Spawns", 1, true) ~= nil, rowNames())
lamp.Name = "Lamp"
H.advance(0.2)

-- delete key
local junk = make("Part", "Junk", map)
H.advance(0.2)
clickRow("Junk")
H.advance(0.4)
local at = #C.Lines + 1
H.key("Delete")
H.advance(0.2)
check("Delete takes it out of the game (kept for /undo)", junk.Parent == nil and junk._destroyed ~= true)
check("delete reported", has(at, "deleted Junk"), lines(at))
check("selection emptied", #E.getSelection() == 0 and Variables.get("sel") == nil)

-- variable badges
run("/set door = workspace.Map.Door")
H.advance(0.2)
local doorEntry = entryFor("Door")
check("badge shows the variable", doorEntry.Badge.Visible and doorEntry.BadgeText.Text == "$door", doorEntry.BadgeText.Text)
clickRow("Door")
H.advance(0.2)
check("badge shows $sel too", entryFor("Door").BadgeText.Text == "$door $sel" or entryFor("Door").BadgeText.Text == "$sel $door", entryFor("Door").BadgeText.Text)
run("/unset door")
H.advance(0.2)
check("badge follows unset", entryFor("Door").BadgeText.Text == "$sel", entryFor("Door").BadgeText.Text)

-- nil instances
clickArrow("Nil Instances")
H.advance(0.2)
check("nil node lists objects without a parent", rowNames():find("Nil Instances,Orphan", 1, true) ~= nil, rowNames())
check("nil node icon and count", entryFor("Nil Instances").IconName == "type_nil" and entryFor("Nil Instances").Label.Text == "Nil Instances (1)", entryFor("Nil Instances").Label.Text)
local late = make("Folder", "Late", nil)
table.insert(H.NIL, late)
E.refreshNil()
H.advance(0.2)
check("refresh picks up new nil objects", rowNames():find("Late", 1, true) ~= nil, rowNames())
late.Parent = workspace
H.advance(0.2)
check("nil object given a parent leaves the nil list", entryFor("Nil Instances").Label.Text == "Nil Instances (1)" and rowNames():find("Baseplate,Late,Map", 1, true) ~= nil and rowNames():find("Orphan,Late", 1, true) == nil, rowNames())
late:Destroy()
E.hideNil()
H.advance(0.2)
check("hide empties the nil list", rowNames():find("Orphan", 1, true) == nil and rowNames():find("Nil Instances", 1, true) ~= nil, rowNames())

----------------------------------------------------------------------
-- 4. Search
----------------------------------------------------------------------
local function search(text)
	E.setSearch(text)
	H.advance(0.3)
end
search("door")
check("search shows matches with their parents", rowNames() == "Workspace,Map,Door", rowNames())
check("search footer counts", E.Status.Text:find("1 result", 1, true) ~= nil, E.Status.Text)
search('"door"')
check("quoted is exact and case-sensitive", #view.Rows == 0, rowNames())
search('"Door"')
check("quoted exact match", rowNames() == "Workspace,Map,Door", rowNames())
search("isa:BasePart")
check("isa:", rowNames() == "Workspace,Baseplate,Map,Door,Lamp,Spawns,Spawn 1", rowNames())
search("class:part")
check("class: is exact (any case)", rowNames() == "Workspace,Baseplate,Map,Door,Lamp", rowNames())
search("remotes")
check("remotes include UnreliableRemoteEvent", rowNames() == "ReplicatedStorage,Remotes,Ask,Fast,Fire", rowNames())
search("/bindables")
check("bindables (with /)", rowNames() == "ReplicatedStorage,Remotes,Bind", rowNames())
search("scripts")
check("scripts include nil ones", rowNames():find("Loader", 1, true) ~= nil and rowNames():find("Inner", 1, true) ~= nil, rowNames())
search("loadedmodules")
check("loadedmodules", rowNames() == "ReplicatedStorage,Loader", rowNames())
search("nil")
check("nil filter", rowNames():find("Nil Instances", 1, true) ~= nil and rowNames():find("Orphan", 1, true) ~= nil and rowNames():find("Workspace", 1, true) == nil, rowNames())
search("isa:BasePart !door")
check("! excludes", rowNames():find("Door", 1, true) == nil and rowNames():find("Lamp", 1, true) ~= nil, rowNames())
search("isa:BasePart amp")
check("words combine (AND)", rowNames() == "Workspace,Map,Lamp", rowNames())
search("rad:20")
check("rad: without a character says why", E.Status.Text:find("character", 1, true) ~= nil and #view.Rows == 0, E.Status.Text)
search("rad:x")
check("rad: needs a number", E.Status.Text:find("number", 1, true) ~= nil, E.Status.Text)
search("door")
local door2 = make("Part", "Door2", baseplate)
H.advance(0.3)
check("live: new matching objects appear", rowNames():find("Baseplate,Door2", 1, true) ~= nil, rowNames())
door2:Destroy()
H.advance(0.2)
-- open a match to see all its children
clickArrow("Door")
H.advance(0.2)
check("opening a match shows its children", rowNames():find("Door,ClickDetector", 1, true) ~= nil, rowNames())
-- typing in the box searches after a pause
local box = E.SearchInput.Box
H.focusBox(box)
box.Text = "spawn"
H.advance(0.15)
check("no search before the pause", rowNames():find("Spawn 1", 1, true) == nil)
H.advance(0.4)
check("typing searches", rowNames():find("Spawns,Spawn 1", 1, true) ~= nil, rowNames())
H.focusBox(nil)
check("clear button visible", E.SearchInput.Instance.Clear.Visible)
clickRow("Spawn 1")
H.advance(0.2)
H.clickObject(E.SearchInput.Instance.Clear)
H.advance(0.3)
check("clear restores the tree", rowNames():find("Lighting", 1, true) ~= nil and box.Text == "", rowNames())
check("selection kept and visible after clearing", selectedNames() == "Spawn 1" and view.Index[tree:Get(spawn1)] ~= nil)
-- search capped
local oldMax = E.Search.MaxResults
E.Search.MaxResults = 2
search("isa:BasePart")
check("broad searches stop at the limit", E.Status.Text:find("2+ results", 1, true) ~= nil, E.Status.Text)
E.Search.MaxResults = oldMax
search("")

----------------------------------------------------------------------
-- 5. Path bar
----------------------------------------------------------------------
local function crumbs()
	local out = {}
	local list = P.Crumbs:GetChildren()
	table.sort(list, function(a, b) return (a.LayoutOrder or 0) < (b.LayoutOrder or 0) end)
	for _, c in list do
		if c.Name:sub(1, 5) == "Crumb" then
			local t = c:FindFirstChild("Text")
			table.insert(out, t and t.Text or "?")
		end
	end
	return table.concat(out, " > ")
end
local function shownName()
	local obj = P.current()
	return obj and obj.Name
end
E.select({ door })
H.advance(0.2)
check("selecting doesn't load the path", crumbs() == "", crumbs())
E.load({ door })
H.advance(0.2)
check("Load shows the path", crumbs() == "game > Workspace > Map > Door", crumbs())
local mapCrumb
for _, c in P.Crumbs:GetChildren() do
	local t = c:FindFirstChild("Text")
	if t and t.Text == "Map" then mapCrumb = c end
end
H.clickObject(mapCrumb)
H.advance(0.2)
check("clicking a crumb loads it", shownName() == "Map", shownName())
check("path bar follows", crumbs() == "game > Workspace > Map", crumbs())
-- chevron after Map lists its children
local chevrons = {}
for _, c in P.Crumbs:GetChildren() do
	if c.Name == "Chevron" then table.insert(chevrons, c) end
end
table.sort(chevrons, function(a, b) return a.LayoutOrder < b.LayoutOrder end)
local mapChevron = chevrons[#chevrons]
H.clickObject(mapChevron)
H.advance(0.2)
local list = P.ChildList
check("chevron opens the children list", list ~= nil and not list.Closed)
local lampRow
if list then
	for _, d in list.Frame:GetDescendants() do
		if d.Name == "Text" and d.Text == "Lamp" then lampRow = d.Parent end
	end
end
check("children list has Lamp", lampRow ~= nil)
if lampRow then
	H.clickObject(lampRow)
	H.advance(0.2)
end
check("picking a child loads it", shownName() == "Lamp", shownName())
-- game crumb lists services
local gameCrumb = P.Crumbs:FindFirstChild("Crumb_game")
H.clickObject(gameCrumb)
H.advance(0.2)
check("game crumb lists services", P.ChildList and not P.ChildList.Closed)
Overlay.closeAll()
-- typing a path
local fp, fs = P.Field.AbsolutePosition, P.Field.AbsoluteSize
H.click(H.toScreen(fp + V2(fs.X - 12, fs.Y / 2))) -- the empty end of the bar
H.advance(0.2)
check("clicking the bar starts editing", P.EditClip.Visible and P.EditBox.Text == "game.Workspace.Map.Lamp", P.EditBox.Text)
P.EditBox.Text = "game.Workspace.Missing"
H.focused = nil
P.EditBox.FocusLost:Fire(true)
H.advance(0.3)
check("Enter on a wrong path keeps editing", P.EditClip.Visible and P.LastError:find("Missing", 1, true) ~= nil, P.LastError)
P.EditBox.Text = 'workspace["Map"].Spawns["Spawn 1"]'
H.focused = nil
P.EditBox.FocusLost:Fire(true)
H.advance(0.2)
check("Enter loads a typed path", shownName() == "Spawn 1" and not P.EditClip.Visible, shownName())
E.select({ lamp })
H.advance(0.2)
H.clickObject(P.GoButton)
H.advance(0.2)
check("arrow outside editing loads the selection", shownName() == "Lamp" and not P.EditClip.Visible, shownName())
P.edit()
H.advance(0.1)
check("editing again", P.EditClip.Visible)
P.EditBox.Text = "game.Workspace.Nope"
H.clickObject(P.GoButton)
H.advance(0.3)
check("wrong path says why", P.LastError and P.LastError:find("Nope", 1, true) ~= nil, P.LastError)
check("still editing after a wrong path", P.EditClip.Visible)
-- focus leaving while the pointer is on the arrow keeps the typed path
P.EditBox.Text = "game.Workspace.Map"
H.mouse = H.toScreen(P.GoButton.AbsolutePosition + P.GoButton.AbsoluteSize / 2)
H.focused = nil
P.EditBox.FocusLost:Fire(false)
H.advance(0.5)
check("a slow click on the arrow doesn't lose the typed path", P.EditClip.Visible and P.EditBox.Text == "game.Workspace.Map")
H.mouse = H.toScreen(V2(5, 5))
P.EditBox.FocusLost:Fire(false)
H.advance(0.3)
check("clicking elsewhere ends editing", not P.EditClip.Visible)
P.edit()
H.advance(0.1)
P.EditBox.Text = "game.Workspace.Nope"
P.EditBox.Text = 'print("hi")'
P.go()
H.advance(0.2)
check("code is never run", P.LastError ~= nil and shownName() == "Lamp", P.LastError)
P.EditBox.Text = "game.ReplicatedStorage.Remotes.Fire"
P.go()
H.advance(0.2)
check("arrow/Enter resolve paths", shownName() == "Fire", shownName())
-- left menu
H.clickObject(P.MenuButton)
H.advance(0.2)
local menu = P.Menu
local function menuTexts(m)
	local out = {}
	for _, d in m.Frame:GetDescendants() do
		if d.Name == "Text" and d.Parent.Name:sub(1, 4) == "Item" then table.insert(out, d.Text) end
	end
	return table.concat(out, ",")
end
check("path menu has exactly Copy and Highlight", menu and menuTexts(menu) == "Copy,Highlight", menu and menuTexts(menu))
if menu then
	H.clickObject(H.find(menu.Frame, "Item2"))
	H.advance(0.2)
end
check("Copy copies the path as code", H.CLIPBOARD == "game.ReplicatedStorage.Remotes.Fire", H.CLIPBOARD)
-- Highlight opens a collapsed explorer
E.setOpen(false)
H.advance(0.4)
E.View:Select({}, nil)
P.show(door, "console")
H.advance(0.1)
check("a tab can show its own instance", crumbs() == "game > Workspace > Map > Door", crumbs())
H.clickObject(P.MenuButton)
H.advance(0.2)
H.clickObject(H.find(P.Menu.Frame, "Item3"))
H.advance(0.4)
check("Highlight opens the explorer", E.isOpen())
check("Highlight selects", selectedNames() == "Door", selectedNames())
T.Tabs:Select("documentation")
H.advance(0.3)
check("every tab shows the one loaded object", crumbs() == "game > Workspace > Map > Door", crumbs())
P.show(lamp, "documentation")
check("override only on its own tab", crumbs() == "game > Workspace > Map > Lamp", crumbs())
P.clear("documentation")
P.clear("console")
T.Tabs:Select("console")
H.advance(0.3)
-- nil-rooted path
E.load({ inner })
H.advance(0.2)
check("nil objects show a nil crumb", crumbs() == "nil > Orphan > Inner", crumbs())
-- rename along the path updates it
E.load({ door })
H.advance(0.2)
map.Name = "Level"
H.advance(0.2)
check("path follows renames", crumbs() == "game > Workspace > Level > Door", crumbs())
map.Name = "Map"
H.advance(0.2)
Variables.unset("loaded") -- Load into the console set it

----------------------------------------------------------------------
-- 6. Collapse and reopen
----------------------------------------------------------------------
local toggle = E.ToggleButton
local minimizeButton = W.MinimizeButton
check("the explorer button is in the title bar", toggle.Parent == W.TitleBar)
check("…rightmost, with minimize to its left", toggle.AbsolutePosition.X > minimizeButton.AbsolutePosition.X and toggle.AbsolutePosition.X + toggle.AbsoluteSize.X >= W.TitleBar.AbsolutePosition.X + W.TitleBar.AbsoluteSize.X - 10, tostring(toggle.AbsolutePosition))
check("…the same size as minimize", toggle.Size == minimizeButton.Size and toggle.AbsoluteSize == minimizeButton.AbsoluteSize)
local tpos = toggle.AbsolutePosition
local ContextMenu = T.import("base/ui/components/contextmenu")
ContextMenu.open({ { Text = "x" } })
H.clickObject(toggle)
H.advance(0.5)
check("collapsed", not E.isOpen() and T.Settings.get("ExplorerOpen") == false)
check("collapsing closes popups", not Overlay.isOpen())
check("panel hidden", not holder.Visible)
check("the button didn't move", toggle.AbsolutePosition == tpos and toggle.Parent == W.TitleBar)
check("console input keeps its full width", C.View.Bar.Size.X.Offset == 0)
W:MoveTo(V2(5000, 100))
H.advance(0.2)
local rightX = W.Pos.X
check("collapsed window may go further right", rightX + W.Size.X == H.SCREEN.X, rightX)
H.clickObject(toggle)
H.advance(0.5)
check("button reopens", E.isOpen() and holder.Visible)
check("reopening keeps everything on screen", W.Pos.X + W:Footprint().X <= H.SCREEN.X and W.Pos.X < rightX, W.Pos.X)
check("still in the title bar after reopening", toggle.Parent == W.TitleBar)
run("/explorer close")
check("/explorer close", not E.isOpen())
run("/explorer")
check("/explorer toggles", E.isOpen())

----------------------------------------------------------------------
-- 7. Right-click menu
----------------------------------------------------------------------
E.select({ door })
H.advance(0.2)
clickRow("Door", "MouseButton2")
H.advance(0.2)
local top = Overlay.top()
check("right-click opens a menu", top ~= nil)
local function itemTexts(frame)
	local out = {}
	for _, d in frame:GetDescendants() do
		if d.Name == "Text" and d.Parent.Name:sub(1, 4) == "Item" then table.insert(out, d.Text) end
	end
	return table.concat(out, ",")
end
local headerText
for _, d in top.Frame:GetDescendants() do
	if d.Name:sub(1, 6) == "Header" then headerText = d.Text end
end
check("menu header counts the selection", headerText == "1 SELECTED", headerText)
check("Load and four categories", itemTexts(top.Frame) == "Load,Object,Function,Variable,Save", itemTexts(top.Frame))
check("Load is emphasized", H.find(top.Frame, "Item2") and H.find(H.find(top.Frame, "Item2"), "Emphasis") ~= nil)
local function openSub(index)
	local item = H.find(Overlay.top().Frame, "Item" .. index)
	H.clickObject(item)
	H.advance(0.2)
	return Overlay.top()
end
local object = openSub(4)
check("Object submenu", itemTexts(object.Frame):find("Rename,Duplicate,Delete,Delete Children,Cut,Copy,Paste Into,Show Clipboard,Clear Clipboard,Group,Group in Folder,Ungroup,Select Children,Jump to Parent,Expand All,Collapse All,Copy Path", 1, true) ~= nil, itemTexts(object.Frame))
Overlay.closeAll()
clickRow("Door", "MouseButton2")
H.advance(0.2)
local fn = openSub(5)
check("Function submenu: Documentation and View in console (no plugin actions)", itemTexts(fn.Frame) == "Documentation,View in console" and (function()
	for _, d in fn.Frame:GetDescendants() do
		if d:IsA("TextLabel") and d.Text:upper():find("NO PLUGIN ACTIONS FOR PART", 1, true) then
			return true
		end
	end
	return false
end)(), itemTexts(fn.Frame))
Overlay.closeAll()
-- Variable > Set variable…
clickRow("Door", "MouseButton2")
H.advance(0.2)
local var = openSub(6)
check("Variable submenu", itemTexts(var.Frame):find("Set variable…,Add to list…,Copy variable,Watch,Unset variables", 1, true) ~= nil, itemTexts(var.Frame))
H.clickObject(H.find(var.Frame, "Item1"))
H.advance(0.2)
local prompt = Overlay.top()
check("Set variable asks for a name", prompt and prompt.Box ~= nil and prompt.Box.Text == "door", prompt and prompt.Box and prompt.Box.Text)
if prompt and prompt.Box then
	prompt.Box.Text = "frontdoor"
	H.focused = nil
	prompt.Box.FocusLost:Fire(true)
	H.advance(0.2)
end
check("variable set from the menu", Variables.get("frontdoor") == door)
-- several selected -> a table; Copy Path gives a table of paths
E.select({ door, lamp })
H.advance(0.2)
clickRow("Lamp", "MouseButton2")
H.advance(0.2)
openSub(4)
local copyItem
for _, d in Overlay.top().Frame:GetDescendants() do
	if d.Name == "Text" and d.Text == "Copy Path" then copyItem = d.Parent end
end
H.clickObject(copyItem)
H.advance(0.2)
check("Copy Path for several is a table", H.CLIPBOARD == "{\n\tgame.Workspace.Map.Door,\n\tgame.Workspace.Map.Lamp,\n}", H.CLIPBOARD)
clickRow("Lamp", "MouseButton2")
H.advance(0.2)
openSub(4)
local renameItem
for _, d in Overlay.top().Frame:GetDescendants() do
	if d.Name == "Text" and d.Text == "Rename" then renameItem = d end
end
check("Rename greyed for several", renameItem and renameItem.TextColor3 == T.Theme.Colors.TextMuted)
Overlay.closeAll()
-- Unset from the menu
clickRow("Lamp", "MouseButton2")
H.advance(0.2)
openSub(6)
for _, d in Overlay.top().Frame:GetDescendants() do
	if d.Name == "Text" and d:IsA("TextLabel") and d.Text:sub(1, 5) == "Unset" then
		H.clickObject(d.Parent)
		break
	end
end
H.advance(0.2)
check("Unset removes variables holding the objects", Variables.get("frontdoor") == nil)
-- Jump to Parent / Select Children
E.select({ door })
H.advance(0.2)
clickRow("Door", "MouseButton2")
H.advance(0.2)
openSub(4)
for _, d in Overlay.top().Frame:GetDescendants() do
	if d.Name == "Text" and d.Text == "Jump to Parent" then H.clickObject(d.Parent) break end
end
H.advance(0.2)
check("Jump to Parent", selectedNames() == "Map", selectedNames())
clickRow("Map", "MouseButton2")
H.advance(0.2)
openSub(4)
for _, d in Overlay.top().Frame:GetDescendants() do
	if d.Name == "Text" and d.Text == "Select Children" then H.clickObject(d.Parent) break end
end
H.advance(0.2)
check("Select Children", selectedNames() == "Door,Lamp,Spawns", selectedNames())
-- Clear Search and Jump to
search("spawn 1")
clickRow("Spawn 1", "MouseButton2")
H.advance(0.2)
openSub(4)
for _, d in Overlay.top().Frame:GetDescendants() do
	if d.Name == "Text" and d.Text == "Clear Search and Jump to" then H.clickObject(d.Parent) break end
end
H.advance(0.3)
check("Clear Search and Jump to", E.getSearch() == "" and selectedNames() == "Spawn 1" and rowNames():find("Lighting", 1, true) ~= nil, rowNames())

----------------------------------------------------------------------
-- 8. Console commands
----------------------------------------------------------------------
at = run("/select game.Workspace.Map.Door")
check("/select path", selectedNames() == "Door" and has(at, "selected 1"), lines(at))
at = run("/select remotes")
check("/select search selects every match", selectedNames() == "Ask,Fast,Fire", selectedNames())
check("$sel holds them", type(Variables.get("sel")) == "table" and #Variables.get("sel") == 3)
run("/set pair = {workspace.Baseplate, workspace.Map}")
at = run("/select $pair")
check("/select $table", selectedNames() == "Baseplate,Map", selectedNames())
at = run("/select game.Workspace.Nope")
check("/select bad path fails with the reason", has(at, "[x]") and has(at, "Nope"), lines(at))
at = run("/select game")
check("/select game is refused (it has no row)", has(at, "[x]") and selectedNames() == "", lines(at))
at = run("/select none")
check("/select none", #E.getSelection() == 0 and Variables.get("sel") == nil)
at = run("/select")
check("/select alone reports", has(at, "nothing is selected"), lines(at))
at = run("> $sel")
check("$sel empty explains", has(at, "select something in the explorer"), lines(at))
at = run("/find isa:BasePart")
check("/find lists matches", has(at, "4 matches") and has(at, "game.Workspace.Map.Door"), lines(at))
check("/find shows them in the explorer", E.getSearch() == "isa:BasePart" and rowNames():find("Spawn 1", 1, true) ~= nil, rowNames())
check("$last holds the matches", type(Variables.get("last")) == "table" and #Variables.get("last") == 4)
E.clearSearch()
at = run("/find nothingmatches")
check("/find nothing", has(at, "nothing matches"), lines(at))
E.clearSearch()
run("/select workspace.Map.Lamp")
at = run("/path")
check("/path of the selection", has(at, "game.Workspace.Map.Lamp") and Variables.get("last") == "game.Workspace.Map.Lamp", lines(at))
at = run("/path game.ReplicatedStorage.Remotes")
check("/path of a path", has(at, "game.ReplicatedStorage.Remotes"), lines(at))
at = run("> $sel.Name")
check("$sel in code", has(at, '"Lamp"'), lines(at))
run("/collapse workspace all")
H.advance(0.1)
check("/collapse all", rowNames():find("Workspace,Lighting", 1, true) ~= nil, rowNames())
run("/expand workspace all")
H.advance(0.1)
check("/expand all opens every level", rowNames():find("Spawns,Spawn 1", 1, true) ~= nil and rowNames():find("Door,ClickDetector", 1, true) ~= nil, rowNames())
at = run("/expand $nope")
check("/expand unknown variable fails", has(at, "unknown variable"), lines(at))
at = run("/help explorer")
check("/help explorer", has(at, "/explorer"), lines(at))
at = run("/help")
check("/help has an Explorer group", has(at, "EXPLORER"), lines(at))

----------------------------------------------------------------------
-- 9. Re-run
----------------------------------------------------------------------
local before = { H.UIS.InputBegan:Count(), H.UIS.InputChanged:Count(), H.UIS.InputEnded:Count() }
local ok2 = H.run("Tungsten/Tungsten.luau")
H.advance(1)
check("re-run ok", ok2)
local mid = { H.UIS.InputBegan:Count(), H.UIS.InputChanged:Count(), H.UIS.InputEnded:Count() }
H.run("Tungsten/Tungsten.luau")
H.advance(1)
local after = { H.UIS.InputBegan:Count(), H.UIS.InputChanged:Count(), H.UIS.InputEnded:Count() }
check("re-running doesn't add listeners", table.concat(mid, ",") == table.concat(after, ","), table.concat(mid, ",") .. " -> " .. table.concat(after, ","))
local childAdded = workspace._events.ChildAdded and workspace._events.ChildAdded:Count() or 0
check("old explorer stopped watching the game", childAdded <= 1, childAdded)
local T2 = H.genv.Tungsten.Context
check("a re-run starts with the explorer open (not remembered)", T2.Explorer.isOpen() == true)

for _, e in H.ERRORS do print("ERR: " .. e) end
print(("stage4a: %d passed, %d failed, %d runtime errors"):format(passed, failed, #H.ERRORS))
