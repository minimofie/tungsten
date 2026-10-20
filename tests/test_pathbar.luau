-- The path bar: its dropdown (Copy / Highlight), Highlight, the arrow,
-- crumbs and their child lists, typing paths, long paths, overrides.
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
local function make(class, name, parent)
	local o = new(class)
	o.Name = name
	o.Parent = parent
	return o
end
local workspace = H.env.workspace
local map = make("Model", "Map", workspace)
local spawn = make("Part", "Spawn Point", map) -- a name with a space
local deep = map
for index = 1, 14 do
	deep = make("Folder", "VeryLongFolderName" .. index, deep)
end
local leaf = make("Part", "Leaf", deep)
local crowd = make("Folder", "Crowd", workspace)
for index = 1, 12 do
	make("Part", ("Member%02d"):format(index), crowd)
end

local ok, err = H.run("Tungsten/Tungsten.luau")
check("loader runs", ok, err)
H.advance(1)
local T = H.genv.Tungsten.Context
local E, P, Overlay, C = T.Explorer, T.PathBar, T.Overlay, T.Console

local function crumbs()
	local list = {}
	for _, c in P.Crumbs:GetChildren() do
		if c.Name:sub(1, 5) == "Crumb" then table.insert(list, c) end
	end
	table.sort(list, function(a, b) return a.LayoutOrder < b.LayoutOrder end)
	local out = {}
	for _, c in list do table.insert(out, c:FindFirstChild("Text").Text) end
	return table.concat(out, " > "), list
end
local function crumbNamed(name)
	local _, list = crumbs()
	for _, c in list do if c:FindFirstChild("Text").Text == name then return c end end
	return nil
end
local function chevronAfter(crumb)
	local best
	for _, c in P.Crumbs:GetChildren() do
		if c.Name == "Chevron" and c.LayoutOrder == crumb.LayoutOrder + 1 then best = c end
	end
	return best
end
local function rowsOf(frame)
	local out = {}
	for _, d in frame:GetDescendants() do
		if d.Name == "Text" and d.Parent and (d.Parent.Name:sub(1, 4) == "Item" or d.Parent.Name:sub(1, 3) == "Row") and d.Parent.Visible then
			table.insert(out, d.Text)
		end
	end
	return out
end
local function selectedNames()
	local out = {}
	for _, o in E.getSelection() do table.insert(out, o.Name) end
	return table.concat(out, ",")
end
local function center(o) return H.toScreen(o.AbsolutePosition + o.AbsoluteSize / 2) end

----------------------------------------------------------------------
-- 1. Empty state and the dropdown
----------------------------------------------------------------------
check("nothing selected: a hint instead of crumbs", P.Crumbs:FindFirstChild("Empty") ~= nil)
H.clickObject(P.MenuButton)
H.advance(0.2)
local menu = P.Menu
check("dropdown opens", menu and menu:IsOpen())
check("dropdown is below its button", menu.Frame.AbsolutePosition.Y >= P.MenuButton.AbsolutePosition.Y + P.MenuButton.AbsoluteSize.Y, tostring(menu.Frame.AbsolutePosition))
check("dropdown has exactly Copy and Highlight", table.concat(rowsOf(menu.Frame), ",") == "Copy,Highlight", table.concat(rowsOf(menu.Frame), ","))
local headerText
for _, d in menu.Frame:GetDescendants() do if d.Name:sub(1, 6) == "Header" then headerText = d.Text end end
check("dropdown header", headerText == "PATH")
local function itemColor(m, text)
	for _, d in m.Frame:GetDescendants() do if d.Name == "Text" and d.Text == text then return d.TextColor3 end end
	return nil
end
check("both greyed with nothing shown", itemColor(menu, "Copy") == T.Theme.Colors.TextMuted and itemColor(menu, "Highlight") == T.Theme.Colors.TextMuted)
H.clickObject(P.MenuButton)
H.advance(0.2)
check("clicking the button again closes it", not menu:IsOpen())
H.advance(0.4)
H.clickObject(P.MenuButton)
H.advance(0.2)
check("and opens it again", P.Menu:IsOpen())
H.click(H.toScreen(V2(5, 5)))
H.advance(0.2)
check("clicking elsewhere closes it", not P.Menu:IsOpen())

----------------------------------------------------------------------
-- 2. Copy and Highlight
----------------------------------------------------------------------
local function shownName()
	local obj = P.current()
	return obj and obj.Name
end
E.select({ spawn })
H.advance(0.2)
check("selecting does not change the bar", (crumbs()) == "", (crumbs()))
E.load({ spawn })
H.advance(0.2)
check("bar shows what was loaded", (crumbs()) == "game > Workspace > Map > Spawn Point", (crumbs()))
E.select({ map })
H.advance(0.2)
check("selecting something else keeps it", (crumbs()) == "game > Workspace > Map > Spawn Point", (crumbs()))
H.clickObject(P.MenuButton)
H.advance(0.2)
check("enabled once something is shown", itemColor(P.Menu, "Copy") == T.Theme.Colors.Text)
H.clickObject(H.find(P.Menu.Frame, "Item2"))
H.advance(0.2)
check("Copy copies the path as code (names with spaces quoted)", H.CLIPBOARD == 'game.Workspace.Map["Spawn Point"]', H.CLIPBOARD)
check("Copy closes the dropdown", not P.Menu:IsOpen())
-- the copied path resolves back to the object
local resolved = T.Types.resolvePath(H.CLIPBOARD)
check("copied path resolves to the same object", resolved == spawn)

-- Highlight with the explorer collapsed, the object in a closed branch
E.select({})
E.collapse(workspace, true)
P.show(spawn, "console")
H.advance(0.2)
E.setOpen(false)
H.advance(0.5)
check("explorer collapsed", not E.isOpen())
H.clickObject(P.MenuButton)
H.advance(0.2)
H.clickObject(H.find(P.Menu.Frame, "Item3"))
H.advance(0.5)
check("Highlight opens the explorer", E.isOpen())
check("Highlight selects", selectedNames() == "Spawn Point", selectedNames())
check("Highlight opens the parents", E.View.Index[E.Tree:Get(spawn)] ~= nil)
check("Highlight flashes the row", E.View.Flashed == E.Tree:Get(spawn) and E.View:IsFlashing(E.Tree:Get(spawn)))
local function flashEntry()
	for _, entry in E.View.Entries do
		if entry.Index ~= 0 and E.View.Rows[entry.Index] == E.Tree:Get(spawn) then
			return entry
		end
	end
	return nil
end
H.advance(1.5)
check("still flashing after 2 seconds (longer, easier to see)", E.View:IsFlashing(E.Tree:Get(spawn)))
local fe = flashEntry()
check("the row is lit in the accent color", fe and fe.Row.BackgroundColor3 == T.Theme.Colors.Accent and fe.Row.BackgroundTransparency < 1)
H.advance(1.5)
check("the flash ends by itself after about 3 seconds", not E.View:IsFlashing())
fe = flashEntry()
check("…and the row goes back to its selected look", fe and fe.Row.BackgroundColor3 ~= T.Theme.Colors.Accent)
-- clicking the row stops it at once
E.View:Flash(E.Tree:Get(spawn))
H.advance(0.3)
check("flashing again", E.View:IsFlashing())
fe = flashEntry()
H.clickObject(fe.Row)
check("clicking the highlighted row stops the flash immediately", not E.View:IsFlashing())
check("…and repaints it straight away", fe.Row.BackgroundColor3 ~= T.Theme.Colors.Accent)
H.advance(0.3)
local idx = E.View.Index[E.Tree:Get(spawn)]
local scroll = E.View.Scroll
check("the row is scrolled into view", (idx - 1) * 22 >= scroll.Offset.Y - 1 and idx * 22 <= scroll.Offset.Y + scroll:ViewSize().Y + 1)
P.clear("console")
-- Highlight clears a search that hides the object
E.setSearch("Crowd")
H.advance(0.3)
check("search active", E.getSearch() == "Crowd")
P.highlight(spawn)
H.advance(0.3)
check("Highlight clears a search that hides it", E.getSearch() == "" and selectedNames() == "Spawn Point")
-- Highlight of something the explorer can't show
local orphan = new("Folder")
orphan.Name = "Gone"
orphan:Destroy()
P.show(orphan, "console")
H.advance(0.1)
P.highlight(orphan)
H.advance(0.2)
check("Highlight explains when it can't show it", P.LastError and P.LastError:find("Gone", 1, true) ~= nil, P.LastError)
P.clear("console")
Overlay.closeAll()

----------------------------------------------------------------------
-- 3. The arrow
----------------------------------------------------------------------
P.clear("console")
E.select({ spawn })
H.advance(0.2)
check("nothing loaded yet", P.current() == nil)
H.clickObject(P.GoButton)
H.advance(0.3)
check("arrow loads the selection into the bar", P.current() == spawn and not P.EditBox.Parent.Visible)
check("…and into the open tab (like Load)", T.Variables.get("loaded") == spawn)
E.select({})
H.advance(0.2)
H.clickObject(P.GoButton)
H.advance(0.2)
check("arrow with nothing selected starts editing", P.EditClip.Visible and P.EditBox.Text == 'game.Workspace.Map["Spawn Point"]', P.EditBox.Text)
P.cancelEdit()

----------------------------------------------------------------------
-- 4. Crumbs and their lists
----------------------------------------------------------------------
E.load({ spawn })
H.advance(0.2)
H.clickObject(crumbNamed("Map"))
H.advance(0.2)
check("clicking a crumb loads it", P.current() == map and T.Variables.get("loaded") == map)
check("bar shortens", (crumbs()) == "game > Workspace > Map")
local mapChevron = chevronAfter(crumbNamed("Map"))
check("last crumb has a chevron when it has children", mapChevron ~= nil)
H.clickObject(mapChevron)
H.advance(0.2)
local list = P.ChildList
check("chevron opens the children", list and not list.Closed)
check("chevron turns while open", mapChevron:FindFirstChild("Icon").Rotation == 90)
check("children sorted", table.concat(rowsOf(list.Frame), ",") == "Spawn Point,VeryLongFolderName1", table.concat(rowsOf(list.Frame), ","))
H.clickObject(mapChevron)
H.advance(0.2)
check("chevron again closes the list", list.Closed)
check("chevron turns back", mapChevron:FindFirstChild("Icon").Rotation == 0)
-- a long list is searchable
E.load({ crowd })
H.advance(0.2)
H.clickObject(chevronAfter(crumbNamed("Crowd")))
H.advance(0.2)
list = P.ChildList
local box = H.find(list.Frame, "Box")
check("long child lists are searchable", box ~= nil)
box.Text = "member07"
H.step()
check("search narrows the list", table.concat(rowsOf(list.Frame), ",") == "Member07", table.concat(rowsOf(list.Frame), ","))
H.focused = nil
box.FocusLost:Fire(true)
H.advance(0.2)
check("Enter loads the match", shownName() == "Member07", shownName())
-- the game crumb lists services
H.clickObject(crumbNamed("game"))
H.advance(0.2)
check("game crumb lists services", table.find(rowsOf(P.ChildList.Frame), "Workspace") ~= nil and table.find(rowsOf(P.ChildList.Frame), "ReplicatedStorage") ~= nil)
Overlay.closeAll()
-- a leaf without children has no chevron after it
E.load({ leaf })
H.advance(0.2)
check("no chevron after a leaf", chevronAfter(crumbNamed("Leaf")) == nil)

----------------------------------------------------------------------
-- 5. Long paths
----------------------------------------------------------------------
H.advance(0.3)
local cs = P.Crumbs.Parent
local scrollObj
for _, entry in { E.View.Scroll } do scrollObj = entry end
check("long path is wider than the bar", P.Crumbs.AbsoluteSize.X > P.Field.AbsoluteSize.X, P.Crumbs.AbsoluteSize.X)
check("long path shows its end", P.Crumbs.Position.X.Offset < 0 and crumbNamed("Leaf").AbsolutePosition.X + crumbNamed("Leaf").AbsoluteSize.X <= P.Field.AbsolutePosition.X + P.Field.AbsoluteSize.X + 1, P.Crumbs.Position.X.Offset)
-- wheel scrolls it sideways (wheel down = left)
local before = P.Crumbs.Position.X.Offset
H.wheel(center(P.Field), -3)
H.advance(0.5)
check("plain wheel scrolls the path sideways (down = left)", P.Crumbs.Position.X.Offset > before, P.Crumbs.Position.X.Offset)

----------------------------------------------------------------------
-- 6. Typing a path
----------------------------------------------------------------------
local fp, fs = P.Field.AbsolutePosition, P.Field.AbsoluteSize
E.load({ spawn })
H.advance(0.3)
H.click(H.toScreen(fp + V2(fs.X - 8, fs.Y / 2)))
H.advance(0.2)
check("clicking the empty end edits", P.EditClip.Visible and P.EditBox.Text == 'game.Workspace.Map["Spawn Point"]', P.EditBox.Text)
check("the crumbs hide while editing", not P.Crumbs.Parent.Visible)
H.key("Escape")
H.advance(0.2)
check("Escape cancels", not P.EditClip.Visible and P.Crumbs.Parent.Visible and (crumbs()) == "game > Workspace > Map > Spawn Point")
P.edit()
H.advance(0.1)
P.EditBox.Text = "Workspace.Crowd.Member03"
H.focused = nil
P.EditBox.FocusLost:Fire(true)
H.advance(0.3)
check("a service name works as the start (and loads it)", shownName() == "Member03", shownName())
P.edit()
H.advance(0.1)
P.EditBox.Text = 'game:GetService("Workspace"):FindFirstChild("Map")'
H.focused = nil
P.EditBox.FocusLost:Fire(true)
H.advance(0.3)
check("GetService / FindFirstChild paths work", shownName() == "Map")
P.edit()
H.advance(0.1)
P.EditBox.Text = "game.Workspace.Map.Nope"
H.focused = nil
P.EditBox.FocusLost:Fire(true)
H.advance(0.3)
local errorPopup = Overlay.top()
check("a wrong path explains under the bar", P.LastError and P.LastError:find("Nope", 1, true) and errorPopup and errorPopup.Frame.AbsolutePosition.Y >= P.Instance.AbsolutePosition.Y + P.Instance.AbsoluteSize.Y)
check("and keeps the box focused", P.EditClip.Visible and H.focused == P.EditBox)
P.EditBox.Text = "game.Workspace.Map"
H.step()
check("typing clears the explanation", errorPopup.Closed)
P.EditBox.Text = "game"
H.focused = nil
P.EditBox.FocusLost:Fire(true)
H.advance(0.2)
check("game itself is refused", P.LastError:find("game itself", 1, true) ~= nil and P.EditClip.Visible)
P.EditBox.Text = 'workspace.Map.Destroy(workspace.Map)'
P.go()
H.advance(0.2)
check("code is not run", map.Parent == workspace and P.EditClip.Visible)
P.cancelEdit()
-- long text keeps the cursor in view
P.edit()
H.advance(0.1)
local long = "game.Workspace.Map"
for index = 1, 14 do long ..= ".VeryLongFolderName" .. index end
long ..= ".Leaf"
P.EditBox.Text = long
P.EditBox.CursorPosition = #long + 1
H.step()
check("long typed paths slide to show the cursor", P.EditBox.Position.X.Offset < 0 and P.EditBox.AbsoluteSize.X > P.EditClip.AbsoluteSize.X, P.EditBox.Position.X.Offset)
P.EditBox.CursorPosition = 1
H.step()
check("and slide back for the start", P.EditBox.Position.X.Offset == 0, P.EditBox.Position.X.Offset)
H.focused = nil
P.EditBox.FocusLost:Fire(true)
H.advance(0.3)
check("long paths resolve", shownName() == "Leaf")

----------------------------------------------------------------------
-- 7. What is shown
----------------------------------------------------------------------
E.load({ spawn })
H.advance(0.2)
P.show(leaf, "documentation") -- the old tab argument is ignored: one loaded target
check("show loads for every tab at once", (crumbs()):sub(-4) == "Leaf", (crumbs()))
T.Tabs:Select("documentation")
H.advance(0.3)
check("the same on another tab", (crumbs()):sub(-4) == "Leaf")
T.Tabs:Select("console")
H.advance(0.3)
check("…and back (nothing kept per tab)", (crumbs()):sub(-4) == "Leaf")
P.clear("documentation")
H.advance(0.1)
check("clear unloads for every tab", P.Crumbs:FindFirstChild("Empty") ~= nil and T.Loaded.get() == nil)
E.load({ spawn })
H.advance(0.2)
spawn.Name = "Start"
H.advance(0.2)
check("renames update the bar", (crumbs()) == "game > Workspace > Map > Start")
spawn:Destroy()
H.advance(0.3)
check("a destroyed object clears the bar", P.Crumbs:FindFirstChild("Empty") ~= nil)
check("no runtime errors", #H.ERRORS == 0, H.ERRORS[1])

for _, e in H.ERRORS do print("ERR: " .. e) end
print(("pathbar: %d passed, %d failed, %d runtime errors"):format(passed, failed, #H.ERRORS))
