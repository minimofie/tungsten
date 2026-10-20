-- UI components on a blank page (the former Component Test tab, now a test
-- fixture): scale, menus, list, dropdowns, pickers, editor, scrolling, re-run.
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
local rawWheel, rawPan = H.wheel, H.pan
H.wheel = function(p, d, m) rawWheel(H.toScreen(p), d, m) end
H.pan = function(p, x) rawPan(H.toScreen(p), x) end

local ok, err = H.run("Tungsten/Tungsten.luau")
check("loader runs", ok, err)
H.advance(1)
local T = H.genv.Tungsten.Context
local W, Overlay, Scale = T.Window, T.Overlay, T.Scale
local imp = T.import

-- The component page is a test fixture now; register it as a tab here.
H.FILES["Tungsten/base/testtab.luau"] = H.FILES["fixtures/component_page.luau"]
T.Registry.addTab(imp("base/testtab"))

----------------------------------------------------------------------
-- 1. Scale (screen limit counts the window and the explorer)
----------------------------------------------------------------------
check("screen limit computed (window + the 200 px explorer)", Scale.limit() == 1.3, Scale.limit())
check("starts at 1", Scale.effective() == 1)
for _ = 1, 10 do Scale.step(Scale.KeyStep) end
H.advance(0.5)
check("stepping up stops at screen limit", Scale.effective() == 1.3, Scale.effective())
check("stored value capped too", T.Settings.get("Scale") == 1.3, T.Settings.get("Scale"))
check("window + explorer fit the screen at the limit", W:Footprint().X <= H.SCREEN.X - 16 and W.Pos.X >= 0 and W.Pos.X + W:Footprint().X <= H.SCREEN.X, tostring(W:Footprint()) .. " at " .. tostring(W.Pos))
local big = W.Size
Scale.step(-Scale.KeyStep)
H.advance(0.5)
check("first step down after max shrinks the window", W.Size.X < big.X, tostring(W.Size) .. " vs " .. tostring(big))
check("scale 1.2", Scale.effective() == 1.2, Scale.effective())
-- old settings.json from a bigger screen
T.Settings.set("Scale", 1.75)
check("a stored scale bigger than the screen is kept (the screen never changes it)", Scale.effective() == 1.75, Scale.effective())
W:Fit(false) -- as on start-up with an old settings.json
check("…the window is that big (contents 1:1)", W.Size.X == 1330 and math.abs(W.RootScale.Scale - 1) < 1e-6, tostring(W.Size))
local before = W.Size
Scale.step(-Scale.KeyStep)
H.advance(0.5)
check("stepping down from an oversized scale goes straight to what fits", Scale.effective() == 1.3 and W.Size.X < before.X, Scale.effective())
for _ = 1, 10 do Scale.step(-Scale.KeyStep) end
H.advance(0.5)
check("stops at minimum", Scale.effective() == 0.75)
check("window at min scale", W.Size.X == 570 and W.Size.Y == 345, tostring(W.Size))
Scale.step(Scale.KeyStep)
check("steps up again", Scale.effective() == 0.85, Scale.effective())
check("no F-key scale shortcuts any more", (function()
	H.key("F8")
	return Scale.effective() == 0.85
end)())
Scale.set(1)
H.advance(0.5)

----------------------------------------------------------------------
-- 2. Context menus on the overlay
----------------------------------------------------------------------
local ContextMenu = imp("base/ui/components/contextmenu")
local hits = {}
local function menuItems()
	return {
		{ Header = "Edit" },
		{ Text = "Copy", Icon = "copy", Shortcut = "Ctrl+C", Callback = function() table.insert(hits, "copy") end },
		{ Text = "Off", Disabled = true, Callback = function() table.insert(hits, "disabled!") end },
		{ Separator = true },
		{ Text = "Sub", Items = { { Text = "Deep", Callback = function() table.insert(hits, "deep") end } } },
	}
end

local menu = ContextMenu.open(menuItems(), { Position = V2(1270, 710) })
H.step()
local panel = menu.Frame
local p, s = panel.AbsolutePosition, panel.AbsoluteSize
check("menu on screen near bottom-right", p.X >= 6 and p.Y >= 6 and p.X + s.X <= 1274 and p.Y + s.Y <= 714, tostring(p) .. " " .. tostring(s))
check("menu flipped left/up", p.X + s.X <= 1272 and p.Y + s.Y <= 712)
check("menu is outside the window's gui", panel:IsDescendantOf(Overlay.layer()) and not panel:IsDescendantOf(W.Gui))
H.key("Escape")
check("Escape closes", not menu:IsOpen())

menu = ContextMenu.open(menuItems(), { Position = V2(100, 100) })
H.step()
H.click(V2(5, 700))
check("outside click closes", not menu:IsOpen())

menu = ContextMenu.open(menuItems(), { Position = V2(100, 100) })
W.DragStarted:Fire()
check("window drag closes", not menu:IsOpen())
menu = ContextMenu.open(menuItems(), { Position = V2(100, 100) })
W:Minimize()
H.advance(0.5)
check("minimize closes", not menu:IsOpen())
W:Restore()
H.advance(0.5)
menu = ContextMenu.open(menuItems(), { Position = V2(100, 100) })
T.Tabs:Select("documentation")
check("tab switch closes", not menu:IsOpen())
T.Tabs:Select("console")

-- click inside doesn't close; disabled does nothing; leaf runs + closes
menu = ContextMenu.open(menuItems(), { Position = V2(100, 100) })
H.step()
local disabledRow = H.find(menu.Frame, "Item3")
H.clickObject(disabledRow)
check("click on disabled keeps menu open", menu:IsOpen())
check("disabled callback not run", #hits == 0)
H.hover(H.find(menu.Frame, "Item5"))
H.advance(0.3)
check("submenu opens on hover", menu.Child ~= nil and menu.Child.Menu:IsOpen())
local child = menu.Child and menu.Child.Menu
if child then
	local cp = child.Frame.AbsolutePosition
	check("submenu to the right", cp.X >= menu.Frame.AbsolutePosition.X + menu.Frame.AbsoluteSize.X - 2, tostring(cp))
	H.clickObject(H.find(child.Frame, "Item1"))
	H.advance(0.1)
	check("submenu leaf ran", hits[1] == "deep", hits[1])
	check("all menus closed after choosing", not menu:IsOpen() and not child:IsOpen() and not Overlay.isOpen())
end
-- click to open submenu
menu = ContextMenu.open(menuItems(), { Position = V2(100, 100) })
H.step()
H.clickObject(H.find(menu.Frame, "Item5"))
check("submenu opens on click", menu.Child ~= nil and menu.Child.Menu:IsOpen())
-- submenu near right edge flips left
Overlay.closeAll()
menu = ContextMenu.open(menuItems(), { Position = V2(1150, 100) })
H.step()
H.clickObject(H.find(menu.Frame, "Item5"))
child = menu.Child and menu.Child.Menu
check("submenu near edge flips left", child and child.Frame.AbsolutePosition.X < menu.Frame.AbsolutePosition.X, child and tostring(child.Frame.AbsolutePosition))
Overlay.closeAll()

-- Component Test > Menus: right-click area opens the sample menu
T.Tabs:Select("componenttest")
H.advance(0.4)
do
	local pg = T.Tabs.Pages.componenttest
	H.clickObject(H.find(pg, "menus"))
	H.advance(0.3)
	local area = H.find(pg.Body.menus, "RightClickArea")
	H.clickObject(area, "MouseButton2")
	check("right-click area opens a menu that stays open", Overlay.isOpen())
	local opened = Overlay.top()
	H.clickObject(area, "MouseButton2")
	check("right-clicking again replaces it with a new menu", Overlay.isOpen() and Overlay.top() ~= opened)
	H.clickObject(H.find(pg.Body.menus, "Hint"), "MouseButton1")
	check("left-click outside the menu closes it", not Overlay.isOpen())
	T.Tabs:Select("console")
	H.advance(0.3)
end

-- check items toggle in place
do
	local seen = {}
	local m = ContextMenu.open({
		{ Text = "Show grid", Checked = true, Callback = function(item) table.insert(seen, item.Checked) end },
		{ Text = "Other" },
	}, { Position = V2(200, 200) })
	H.step()
	local row = H.find(m.Frame, "Item1")
	local tick = H.find(row, "Icon")
	H.clickObject(row)
	H.advance(0.1)
	check("check item stays open after click", m:IsOpen())
	check("check mark turns off", tick and not tick.Visible)
	check("callback sees new state (off)", seen[1] == false, tostring(seen[1]))
	H.clickObject(row)
	H.advance(0.1)
	check("check mark turns back on", tick.Visible and seen[2] == true)
	Overlay.closeAll()
	H.advance(0.2)
end

-- nested submenu overlapping its grandparent menu
do
	local deep = {}
	local items = {
		{ Text = "A1" }, { Text = "A2" }, { Text = "A3" },
		{ Text = "Nested", Items = {
			{ Text = "B1" },
			{ Text = "More", Items = {
				{ Text = "C1", Callback = function() table.insert(deep, "C1") end },
				{ Text = "C2", Callback = function() table.insert(deep, "C2") end },
				{ Text = "C3", Callback = function() table.insert(deep, "C3") end },
			} },
		} },
		{ Text = "A5" }, { Text = "A6" },
	}
	-- near the right edge: level 2 flips left, level 3 opens right over level 1
	local m1 = ContextMenu.open(items, { Position = V2(1050, 150) })
	H.step()
	H.hover(H.find(m1.Frame, "Item4"))
	H.advance(0.3)
	local m2 = m1.Child and m1.Child.Menu
	check("level 2 open", m2 and m2:IsOpen())
	H.hover(H.find(m2.Frame, "Item2"))
	H.advance(0.3)
	local m3 = m2.Child and m2.Child.Menu
	check("level 3 open", m3 and m3:IsOpen())
	local f1, f3 = m1.Frame, m3.Frame
	local overlapX = f3.AbsolutePosition.X < f1.AbsolutePosition.X + f1.AbsoluteSize.X and f3.AbsolutePosition.X + f3.AbsoluteSize.X > f1.AbsolutePosition.X
	check("level 3 overlaps level 1 (test setup)", overlapX, tostring(f3.AbsolutePosition) .. " / " .. tostring(f1.AbsolutePosition))
	-- move over each level-3 row: rows of level 1 underneath get MouseEnter too
	for _, name in { "Item1", "Item2", "Item3" } do
		H.hover(H.find(f3, name))
		H.advance(0.3)
	end
	check("level 3 stays open while hovering it", m3:IsOpen() and m2:IsOpen())
	local litBelow = false
	for _, e in m1.Rows do
		if e.Row.BackgroundTransparency == 0 and e.Item.Text ~= "Nested" then litBelow = true end
	end
	check("rows under the submenu don't light up", not litBelow)
	H.clickObject(H.find(f3, "Item3"))
	H.advance(0.1)
	check("clicking the top submenu's row runs it", deep[1] == "C3", deep[1])
	check("menus closed after choosing", not Overlay.isOpen())
	-- moving back onto level 1 still works: hover A5 closes the submenus
	m1 = ContextMenu.open(items, { Position = V2(1050, 150) })
	H.step()
	H.hover(H.find(m1.Frame, "Item4"))
	H.advance(0.3)
	H.hover(H.find(m1.Frame, "Item6"))
	H.advance(0.3)
	check("hovering another row closes the submenu", m1.Child == nil and m1:IsOpen())
	check("that row lights up", H.find(m1.Frame, "Item6").BackgroundTransparency == 0)
	Overlay.closeAll()
	H.advance(0.2)
end

-- long menu scrolls
local many = {}
for i = 1, 80 do
	table.insert(many, { Text = "Entry " .. i })
end
menu = ContextMenu.open(many, { Position = V2(300, 50) })
H.step()
check("long menu fits screen", menu.Frame.AbsoluteSize.Y <= 720 - 12, menu.Frame.AbsoluteSize.Y)
-- content AbsoluteSize in mock comes from the layout
check("long menu can scroll", menu.Scroll:CanScroll("Y"), tostring(menu.Scroll.Canvas))
local before = menu.Scroll.Offset.Y
H.wheel(menu.Frame.AbsolutePosition + V2(20, 40), -3)
H.advance(0.5)
check("wheel scrolls the menu", menu.Scroll.Offset.Y > before, menu.Scroll.Offset.Y)
check("camera zoom blocked while over menu", H.CAS.bound.TungstenWheelSink ~= nil)
Overlay.closeAll()
H.wheel(V2(5, 5), -1)
check("zoom block released off the UI", H.CAS.bound.TungstenWheelSink == nil)

----------------------------------------------------------------------
-- 3. Component Test tab: list
----------------------------------------------------------------------
T.Tabs:Select("componenttest")
H.advance(0.4)
local page = T.Tabs.Pages.componenttest
H.clickObject(H.find(page, "list"))
H.advance(0.3)
local listPage = page.Body.list
local listRoot = H.find(listPage, "List")
check("list exists", listRoot ~= nil)
local rows = 0
for _, d in listRoot:GetDescendants() do
	if d.Name:match("^Row%d+$") then rows += 1 end
end
check("only visible rows exist (10,000 items)", rows > 5 and rows < 40, rows)

-- Find list object through a row click: rows are TextButtons named RowN
local row1 = H.find(listRoot, "Row1")
local row3 = H.find(listRoot, "Row3")
local row6 = H.find(listRoot, "Row6")
H.clickObject(row1)
H.advance(0.5)
local countLabel = H.find(listPage, "Label")
check("click selects one", countLabel.Text == "1 selected", countLabel.Text)
H.keys.LeftControl = true
H.clickObject(row3)
H.keys.LeftControl = nil
H.advance(0.5)
check("ctrl+click adds", countLabel.Text == "2 selected", countLabel.Text)
H.keys.LeftShift = true
H.clickObject(row6)
H.keys.LeftShift = nil
H.advance(0.5)
check("shift+click selects range from anchor", countLabel.Text == "4 selected", countLabel.Text)
H.keys.LeftControl = true
H.clickObject(row3)
H.keys.LeftControl = nil
H.advance(0.5)
check("ctrl+click toggles off", countLabel.Text == "3 selected", countLabel.Text)
H.clickObject(row1)
H.advance(0.5)
check("plain click resets to one", countLabel.Text == "1 selected", countLabel.Text)
-- right-click opens the menu with the selection
H.clickObject(row1, "MouseButton2")
check("right-click opens a menu", Overlay.isOpen())
local top = Overlay.top()
check("menu header shows selection", top and H.find(top.Frame, "Header1") and H.find(top.Frame, "Header1").Text == "1 SELECTED", top and H.find(top.Frame, "Header1") and H.find(top.Frame, "Header1").Text)
Overlay.closeAll()
-- scroll the list
local scrollView = listRoot:FindFirstChild("Scroll")
local firstText = H.find(listRoot, "Row1").Cell1.Text
H.wheel(scrollView.AbsolutePosition + V2(50, 50), -5)
H.advance(0.6)
check("wheel scrolls list rows", H.find(listRoot, "Row1").Cell1.Text ~= firstText, H.find(listRoot, "Row1").Cell1.Text)
-- typed column icons
local icon = H.find(H.find(listRoot, "Row2"), "Icon")
check("class column shows an icon", icon and icon.Visible and icon.Image:find("class_") ~= nil, icon and icon.Image)
-- double click activates (on a cell that isn't editable: Name)
local nameSpot = H.toScreen(row1.AbsolutePosition + V2(30, row1.AbsoluteSize.Y / 2))
H.click(nameSpot)
H.advance(0.1)
H.click(nameSpot)
local status = H.find(page, "Status")
check("double-click activates", status.Text:find("double%-clicked") ~= nil, status.Text)
Overlay.closeAll()
H.advance(1)

----------------------------------------------------------------------
-- 4. Basics: dropdown, multi, type pickers, number input
----------------------------------------------------------------------
H.clickObject(H.find(page, "basics"))
H.advance(0.3)
local basics = page.Body.basics
local dropdowns = {}
for _, d in basics:GetDescendants() do
	if d.Name == "Dropdown" then table.insert(dropdowns, d) end
end
check("dropdowns built", #dropdowns >= 9, #dropdowns)
table.sort(dropdowns, function(a, b)
	local pa, pb = a.AbsolutePosition, b.AbsolutePosition
	if pa.Y ~= pb.Y then return pa.Y < pb.Y end
	return pa.X < pb.X
end)
-- single
H.clickObject(dropdowns[1])
check("dropdown opens", Overlay.isOpen())
local pop = Overlay.top().Frame
local pp = pop.AbsolutePosition
check("dropdown opens below its button", pp.Y >= dropdowns[1].AbsolutePosition.Y + dropdowns[1].AbsoluteSize.Y, tostring(pp))
H.clickObject(H.find(pop, "Row3"))
H.advance(0.2)
check("pick closes and sets value", not Overlay.isOpen() and dropdowns[1]:FindFirstChild("Text").Text == "High", dropdowns[1]:FindFirstChild("Text").Text)
-- clicking the button while open closes it (not reopen)
H.clickObject(dropdowns[1])
check("reopen", Overlay.isOpen())
H.clickObject(dropdowns[1])
check("second click closes", not Overlay.isOpen())
H.advance(0.5)
-- multi
H.clickObject(dropdowns[2])
pop = Overlay.top().Frame
H.clickObject(H.find(pop, "Row2"))
check("multi stays open", Overlay.isOpen())
H.clickObject(H.find(pop, "Row3"))
Overlay.closeAll()
check("multi shows count", dropdowns[2]:FindFirstChild("Text").Text == "3 selected", dropdowns[2]:FindFirstChild("Text").Text)
H.advance(0.5)
-- searchable long list
H.clickObject(dropdowns[3])
pop = Overlay.top().Frame
local box = H.find(pop, "Box")
check("long dropdown has search", box ~= nil)
H.advance(0.1)
check("search box focused", H.focused == box)
box.Text = "042"
H.step()
local r1 = H.find(pop, "Row1")
check("search filters", r1.Visible and r1:FindFirstChild("Text").Text == "Option 042" and not H.find(pop, "Row2").Visible, r1:FindFirstChild("Text").Text)
box.Text = "zzz"
H.step()
check("no matches label", H.find(pop, "Empty").Visible)
box.Text = "Option 1"
H.step()
H.key("Down")
H.focusBox(nil) -- FocusLost(false)
check("still open after focus lost without Enter", Overlay.isOpen())
box.FocusLost:Fire(true)
H.advance(0.1)
check("Enter picks highlighted", dropdowns[3]:FindFirstChild("Text").Text == "Option 010" or dropdowns[3]:FindFirstChild("Text").Text:find("Option 1") ~= nil, dropdowns[3]:FindFirstChild("Text").Text)
Overlay.closeAll()
H.advance(0.5)
-- class picker with icons
H.clickObject(dropdowns[4])
pop = Overlay.top().Frame
check("class picker shows icons", H.find(pop, "Row1").Icon.Visible and H.find(pop, "Row1").Icon.Image:find("class_") ~= nil)
local search = H.find(pop, "Box")
search.Text = "remote"
H.step()
check("class search filters", H.find(pop, "Row1"):FindFirstChild("Text").Text:lower():find("remote") ~= nil, H.find(pop, "Row1"):FindFirstChild("Text").Text)
Overlay.closeAll()
H.advance(0.5)
-- enum picker
H.clickObject(dropdowns[6])
pop = Overlay.top().Frame
check("enum picker lists items", H.find(pop, "Row1").Visible and H.find(pop, "Row1"):FindFirstChild("Text").Text ~= "", H.find(pop, "Row1"):FindFirstChild("Text").Text)
check("enum picker icon", H.find(pop, "Row1").Icon.Image:find("type_enum") ~= nil)
Overlay.closeAll()
H.advance(0.5)
local TypePicker = imp("base/ui/components/typepicker")
local valueTypes = TypePicker.options("valueType")
check("value types have icons", valueTypes[1].Icon ~= nil and #valueTypes > 30)
local creatable = TypePicker.options("creatable")
local hasService = false
for _, o in creatable do if o.Value == "Workspace" then hasService = true end end
check("creatable excludes services", not hasService and #creatable > 100, #creatable)
-- number input for scale
local inputs = {}
for _, d in basics:GetDescendants() do
	if d.Name == "Input" then table.insert(inputs, d) end
end
local numberBox
for _, i in inputs do
	if i.Box.Text == "1" then numberBox = i.Box end
end
check("scale number box", numberBox ~= nil)
if numberBox then
	numberBox:CaptureFocus()
	numberBox.Text = "1.08"
	H.focusBox(nil)
	H.advance(0.5)
	check("number commit sets scale (rounded to step)", Scale.effective() == 1.1, Scale.effective())
	check("box shows applied value", numberBox.Text == "1.1", numberBox.Text)
	numberBox:CaptureFocus()
	numberBox.Text = "abc"
	H.focusBox(nil)
	check("invalid number reverts", numberBox.Text == "1.1", numberBox.Text)
	numberBox:CaptureFocus()
	H.key("Up")
	H.advance(0.3)
	check("Up arrow steps number", Scale.effective() == 1.15, Scale.effective())
	H.focusBox(nil)
	Scale.set(1)
	H.advance(0.5)
end
-- buttons + toggles
local status2 = H.find(page, "Status")
local disabledBtn
for _, d in basics:GetDescendants() do
	if d.Name == "Button" and d:FindFirstChild("Label") and d.Label.Text == "Disabled" then disabledBtn = d end
end
H.clickObject(disabledBtn)
check("disabled button does nothing", status2.Text ~= "this should never show")
local toggle
for _, d in basics:GetDescendants() do
	if d.Name == "Toggle" then toggle = d break end
end
H.clickObject(toggle)
check("toggle reports", status2.Text == "Option A on", status2.Text)

----------------------------------------------------------------------
-- 5. Editor
----------------------------------------------------------------------
H.clickObject(H.find(page, "editor"))
H.advance(0.3)
local edPage = page.Body.editor
local edRoot = H.find(edPage, "Editor")
local hit = H.find(edRoot, "Hit")
local input = H.find(edRoot, "Input")
check("editor built", edRoot ~= nil and hit ~= nil and input ~= nil)
-- syntax colors present
local line3 = H.find(edRoot, "Line3")
check("syntax colored rich text", line3 and line3.RichText and line3.Text:find("<font color=") ~= nil, line3 and line3.Text)
check("keyword colored", line3.Text:find("local") ~= nil)
-- click into the editor at line 1 start
local origin = H.find(edRoot, "Scroll").AbsolutePosition
H.click(H.toScreen(origin + V2(2, 4)))
H.advance(0.1)
check("editor focused by click", H.focused == input)
-- Retrieve editor object via the module (need it for state); build our own instance for unit checks
local TextEditor = imp("base/ui/components/texteditor")
local holder = H.env.Instance.new("Frame")
holder.Size = H.env.UDim2.fromOffset(500, 300)
holder.Parent = W.Content
local ed = TextEditor.new({ Parent = holder, Text = "local a = 1\n\tif a then\n\t\tprint(a)\n\tend" })
ed:Focus()
H.step()
check("focus via API", ed.Focused)
ed.CursorLine, ed.CursorCol = 1, 11
ed.Box.Text = "2"
H.step()
check("typing inserts", ed.Lines[1] == "local a = 12", ed.Lines[1])
ed.CursorLine, ed.CursorCol = 3, #ed.Lines[3]
ed.Box.Text = "\n"
H.step()
check("enter keeps indent", ed.Lines[4] == "\t\t" and ed.CursorLine == 4 and ed.CursorCol == 2, ("%q"):format(ed.Lines[4]))
H.key("Backspace")
check("backspace deletes", ed.Lines[4] == "\t", ("%q"):format(ed.Lines[4]))
H.key("Tab")
ed.Box.Text = "\t" -- the box's own tab must be dropped
H.step()
check("tab inserts one tab", ed.Lines[4] == "\t\t", ("%q"):format(ed.Lines[4]))
ed:UndoStep()
ed:UndoStep()
ed:UndoStep()
check("undo restores", ed:GetText() == "local a = 12\n\tif a then\n\t\tprint(a)\n\tend" or ed:GetText() == "local a = 1\n\tif a then\n\t\tprint(a)\n\tend", ed:GetText())
ed:SetText("hello world\nsecond line")
ed:Focus()
ed.CursorLine, ed.CursorCol = 1, 0
H.keys.LeftShift = true
H.key("End")
H.keys.LeftShift = nil
check("shift+end selects line", ed:GetSelectedText() == "hello world", ed:GetSelectedText())
H.keys.LeftControl = true
H.key("C")
H.keys.LeftControl = nil
check("ctrl+c copies selection", H.CLIPBOARD == "hello world", H.CLIPBOARD)
H.keys.LeftControl = true
H.key("A")
H.keys.LeftControl = nil
check("ctrl+a selects all", ed:GetSelectedText() == "hello world\nsecond line")
H.keys.LeftControl = true
H.key("X")
H.keys.LeftControl = nil
check("ctrl+x cuts", ed:GetText() == "" and H.CLIPBOARD == "hello world\nsecond line", ed:GetText())
H.keys.LeftControl = true
H.key("Z")
H.keys.LeftControl = nil
check("ctrl+z undoes cut", ed:GetText() == "hello world\nsecond line", ed:GetText())
ed.Box.Text = "pasted\ntext" -- Ctrl+V arrives as box text
H.step()
check("paste multi-line", ed:GetText():find("pasted\ntext") ~= nil, ed:GetText())
ed:SetReadOnly(true)
local snapshot = ed:GetText()
ed.Box.Text = "x"
H.step()
H.key("Backspace")
check("read-only blocks edits", ed:GetText() == snapshot)
ed:SetReadOnly(false)
-- word movement
ed:SetText("alpha beta.gamma")
ed:Focus()
ed.CursorLine, ed.CursorCol = 1, 0
H.keys.LeftControl = true
H.key("Right")
H.keys.LeftControl = nil
check("ctrl+right jumps a word", ed.CursorCol == 6, ed.CursorCol)
-- long lines scroll sideways
local long = string.rep("x", 600)
ed:SetText(long)
check("wide canvas for long line", ed.Scroll.Canvas.X > 600 * ed.CharWidth, ed.Scroll.Canvas.X)
ed:Focus()
ed.CursorLine, ed.CursorCol = 1, 0
H.key("End")
check("cursor reveal scrolls right", ed.Scroll.Offset.X > 0, ed.Scroll.Offset.X)
-- many lines + vertical scroll
local big = {}
for i = 1, 5000 do big[i] = "local v" .. i .. " = " .. i end
ed:SetText(table.concat(big, "\n"))
local labels = 0
for _, d in holder:GetDescendants() do
	if d.Name:match("^Line%d+$") then labels += 1 end
end
check("only visible lines drawn", labels < 40, labels)
H.wheel(ed.View.AbsolutePosition + V2(20, 20), -10)
H.advance(0.6)
check("wheel scrolls editor", ed.Scroll.Offset.Y > 0)
H.keys.LeftShift = true
H.wheel(ed.View.AbsolutePosition + V2(20, 20), -3)
H.keys.LeftShift = nil
H.advance(0.6)
-- 5000-line text is narrow (fits) so shift-wheel shouldn't move; check horizontal on long line instead
ed:SetText(long .. "\n" .. long)
H.keys.LeftShift = true
H.wheel(ed.View.AbsolutePosition + V2(20, 20), 3) -- wheel up = right
H.keys.LeftShift = nil
H.advance(0.6)
check("shift+wheel scrolls sideways", ed.Scroll.Offset.X > 0 and ed.Scroll.Offset.Y == 0, tostring(ed.Scroll.Offset))
-- multi-line string state carries across lines
ed:SetText("local s = [[a\nb]] local x = 1")
local tokens2 = ed:_tokens(2)
check("long string continues on next line", tokens2[1].Kind == "String" and tokens2[1].Text == "b]]", tokens2[1].Kind .. " " .. tokens2[1].Text)
local hasKeyword = false
for _, t in tokens2 do if t.Kind == "Keyword" and t.Text == "local" then hasKeyword = true end end
check("code after long string colored", hasKeyword)
-- unicode + tabs columns
ed:SetText("\tä = 1")
ed:Focus()
ed.CursorLine, ed.CursorCol = 1, 0
H.key("Right")
H.key("Right")
check("cursor steps over multi-byte char", ed.CursorCol == 3, ed.CursorCol)
ed:Destroy()
holder:Destroy()
H.focusBox(nil)

----------------------------------------------------------------------
-- 6. Scroll section
----------------------------------------------------------------------
H.clickObject(H.find(page, "scroll"))
H.advance(0.3)
local scrollPage = page.Body.scroll
local views = {}
for _, d in scrollPage:GetDescendants() do
	if d.Name == "Scroll" then table.insert(views, d) end
end
check("two scroll areas", #views == 2, #views)
local strip, grid = views[1], views[2]
local stripContent = strip.Content
H.wheel(strip.AbsolutePosition + V2(30, 10), -2) -- wheel down at the left edge: can't go further left
H.advance(0.6)
check("plain wheel down on a strip moves left (stays at start)", stripContent.Position.X.Offset == 0, tostring(stripContent.Position))
H.wheel(strip.AbsolutePosition + V2(30, 10), 2) -- wheel up
H.advance(0.6)
check("plain wheel up on a strip moves right", stripContent.Position.X.Offset < 0, tostring(stripContent.Position))
local stripX = stripContent.Position.X.Offset
H.wheel(strip.AbsolutePosition + V2(30, 10), -1) -- wheel down
H.advance(0.6)
check("plain wheel down on a strip moves left", stripContent.Position.X.Offset > stripX, stripContent.Position.X.Offset - stripX)
local gridContent = grid.Content
H.wheel(grid.AbsolutePosition + V2(30, 30), -2)
H.advance(0.6)
check("grid scrolls down", gridContent.Position.Y.Offset < 0)
H.keys.LeftShift = true
H.wheel(grid.AbsolutePosition + V2(30, 30), 2) -- wheel up = right
H.keys.LeftShift = nil
H.advance(0.6)
check("grid shift+wheel sideways", gridContent.Position.X.Offset < 0)
check("bars visible on overflow", grid.BarY.Visible and grid.BarX.Visible)
-- direction: shift + wheel down (Z = -1) moves left, wheel up moves right
H.wheel(grid.AbsolutePosition + V2(30, 30), -3, { Shift = true }) -- make room to the left
H.advance(0.6)
do
	local before = gridContent.Position.X.Offset
	H.wheel(grid.AbsolutePosition + V2(30, 30), 2, { Shift = true }) -- wheel up
	H.advance(0.6)
	check("shift + wheel up moves right", gridContent.Position.X.Offset < before, gridContent.Position.X.Offset - before)
	before = gridContent.Position.X.Offset
	H.wheel(grid.AbsolutePosition + V2(30, 30), -1, { Shift = true }) -- wheel down
	H.advance(0.6)
	check("shift + wheel down moves left", gridContent.Position.X.Offset > before, gridContent.Position.X.Offset - before)
end
-- Shift reported only on the wheel input itself (IsKeyDown says no)
local function gx() return gridContent.Position.X.Offset end
local function gy() return gridContent.Position.Y.Offset end
local x0 = gx()
H.wheel(grid.AbsolutePosition + V2(30, 30), -2, { Shift = true })
H.advance(0.6)
check("shift flag on the wheel input scrolls sideways", gx() ~= x0, gx() - x0)
-- Shift seen as a key press but IsKeyDown misses it
x0 = gx()
H.UIS.InputBegan:Fire(H.input("Keyboard", { KeyCode = H.env.Enum.KeyCode.LeftShift }), true)
H.wheel(grid.AbsolutePosition + V2(30, 30), 2)
H.advance(0.6)
check("tracked shift press scrolls sideways", gx() ~= x0, gx() - x0)
H.UIS.InputEnded:Fire(H.input("Keyboard", { KeyCode = H.env.Enum.KeyCode.LeftShift }), true)
local y0 = gy()
x0 = gx()
H.wheel(grid.AbsolutePosition + V2(30, 30), -1)
H.advance(0.6)
check("after shift release the wheel scrolls down again", gy() < y0 and gx() == x0)
-- Shift+wheel arriving as a sideways pan (Windows)
x0 = gx()
H.pan(grid.AbsolutePosition + V2(30, 30), 2)
H.advance(0.6)
check("sideways input reversed: positive pan moves left", gx() > x0 or x0 == 0, gx() - x0)
x0 = gx()
H.pan(grid.AbsolutePosition + V2(30, 30), -1)
H.advance(0.6)
check("sideways input reversed: negative pan moves right", gx() < x0, gx() - x0)
-- shift+wheel where nothing scrolls sideways falls back to down

check("strip has no vertical bar", strip:FindFirstChild("BarY") == nil)
-- tab bar scroll uses the shared component (15 extra tabs)
for index = 1, 15 do
	T.Registry.addTab({ Id = "test_tab_" .. index, Title = "Test tab " .. index, Icon = "dummy", Order = index })
end
H.advance(0.5)
local tabsView = W.Sidebar:FindFirstChild("Tabs")
check("tab bar overflow shows bar", tabsView.BarY.Visible)
H.wheel(tabsView.AbsolutePosition + V2(10, 10), -3)
H.advance(0.6)
check("tab bar scrolls", tabsView.Content.Position.Y.Offset < 0)
for index = 1, 15 do
	T.Registry.removeTab("test_tab_" .. index)
end
H.advance(0.5)
check("bar hides again when it fits", not tabsView.BarY.Visible)

----------------------------------------------------------------------
-- 6b. Dragging scrollbar thumbs
----------------------------------------------------------------------
H.clickObject(H.find(page, "list"))
H.advance(0.3)
local lr = H.find(page.Body.list, "List")
local lscroll = lr:FindFirstChild("Scroll")
local barY = lscroll.BarY
local holderY = barY.Holder
lscroll.Content = nil
local function center(o) local p0, s0 = o.AbsolutePosition, o.AbsoluteSize return p0 + s0 / 2 end
-- scroll back to top first
local listTopText = H.find(lr, "Row1"):FindFirstChild("Cell1").Text
local startY = holderY.AbsolutePosition.Y
H.press(H.toScreen(center(holderY)))
check("pressing the thumb starts a drag (no page jump)", holderY.AbsolutePosition.Y == startY, holderY.AbsolutePosition.Y - startY)
H.moveTo(H.toScreen(center(holderY) + V2(0, 40)))
H.moveTo(H.toScreen(center(holderY) + V2(0, 40)))
local moved = holderY.AbsolutePosition.Y - startY
check("thumb follows the mouse", moved > 60 and moved < 100, moved)
H.release()
H.advance(0.3)
local afterRelease = holderY.AbsolutePosition.Y
H.moveTo(H.toScreen(center(holderY) + V2(0, 50)))
check("thumb stops after release", holderY.AbsolutePosition.Y == afterRelease)
-- track click below the thumb pages down
local trackBottom = barY.AbsolutePosition + V2(barY.AbsoluteSize.X / 2, barY.AbsoluteSize.Y - 3)
local beforePage = holderY.AbsolutePosition.Y
H.press(H.toScreen(trackBottom))
H.release()
H.advance(0.6)
check("track click pages toward the click", holderY.AbsolutePosition.Y > beforePage)
-- horizontal thumb in the editor-style XY grid
H.clickObject(H.find(page, "scroll"))
H.advance(0.3)
local gridView
for _, d in page.Body.scroll:GetDescendants() do
	if d.Name == "Scroll" and d:FindFirstChild("BarX") and d:FindFirstChild("BarY") then gridView = d end
end
local hx = gridView.BarX.Holder
local sx = hx.AbsolutePosition.X
H.press(H.toScreen(center(hx)))
H.moveTo(H.toScreen(center(hx) + V2(60, 0)))
H.release()
check("horizontal thumb drags", hx.AbsolutePosition.X - sx > 40, hx.AbsolutePosition.X - sx)
-- menus open at the mouse even with the top-bar offset
H.mouse = V2(400, 300)
local m = ContextMenu.open({ { Text = "A" } })
H.step()
local mp = m.Frame.AbsolutePosition
check("menu appears at the mouse", math.abs(H.toScreen(mp).Y - 302) <= 1 and math.abs(mp.X - 402) <= 1, tostring(H.toScreen(mp)))
Overlay.closeAll()

----------------------------------------------------------------------
-- 7. Re-run replaces everything
----------------------------------------------------------------------
local oldGuis = H.HUI:GetChildren()
-- listeners of a fresh run (component tab not opened) for comparison
local counts = {}
local ok2 = H.run("Tungsten/Tungsten.luau")
H.advance(1)
check("re-run ok", ok2)
check("re-run leaves three guis (window, overlay, command bar)", #H.HUI:GetChildren() == 3, #H.HUI:GetChildren())
check("old guis destroyed", oldGuis[1]._destroyed and oldGuis[2]._destroyed)
local firstCounts = { H.UIS.InputBegan:Count(), H.UIS.InputChanged:Count(), H.UIS.InputEnded:Count(), H.UIS.PointerAction:Count() }
H.run("Tungsten/Tungsten.luau")
H.advance(1)
local secondCounts = { H.UIS.InputBegan:Count(), H.UIS.InputChanged:Count(), H.UIS.InputEnded:Count(), H.UIS.PointerAction:Count() }
check("re-running doesn't add listeners", table.concat(firstCounts, ",") == table.concat(secondCounts, ","), table.concat(firstCounts, ",") .. " -> " .. table.concat(secondCounts, ","))
check("one wheel/pan router", H.UIS.PointerAction:Count() == 1, H.UIS.PointerAction:Count())

for _, e in H.ERRORS do print("ERR: " .. e) end
print(("components: %d passed, %d failed, %d runtime errors"):format(passed, failed, #H.ERRORS))
