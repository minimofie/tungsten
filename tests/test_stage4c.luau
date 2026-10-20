-- Stage 4 additions: explorer filter (and every search), shared filter
-- words, modular documentation, prompts / toasts / tooltips, the command
-- bar, tabs and icons for plugins, the pill and fade, the welcome lines
-- with integrity checks, and Explorer › Load.
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
local game = H.game
local workspace = E_.workspace

local function make(class, name, parent)
	local o = new(class)
	o.Name = name
	o.Parent = parent
	return o
end
local base = H.part("Baseplate", workspace)
local map = make("Model", "Map", workspace)
local door = H.part("Door", map)
local lamp = make("PointLight", "Lamp", door)
local folder = make("Folder", "Stuff", workspace)
local note = make("StringValue", "Note", folder)
local camera = workspace.CurrentCamera
camera.Name = "Camera"
camera.Parent = workspace
local rs = H.services.ReplicatedStorage
local remotes = make("Folder", "Remotes", rs)
local fire = make("RemoteEvent", "Fire", remotes)
H.FILES["Tungsten/plugins/demo/icon.png"] = "<binary>"

local ok, err = H.run("Tungsten/Tungsten.luau")
check("loader runs", ok, err)
H.advance(1)
local T = H.genv.Tungsten.Context
local E, C, P, W = T.Explorer, T.Console, T.PathBar, T.Window
local Overlay = T.Overlay
local Filter = E.Filter
local Settings = T.Settings
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
local function rowNames()
	local out = {}
	for _, node in E.View.Rows do
		table.insert(out, node.Name)
	end
	return table.concat(out, ",")
end
local function hasRow(name)
	for _, node in E.View.Rows do
		if node.Name == name then
			return true
		end
	end
	return false
end

----------------------------------------------------------------------
-- 1. Welcome lines and integrity
----------------------------------------------------------------------
check("welcome names tungsten (unified)", C.Lines[1].Plain:find("tungsten (unified) v0.4.0", 1, true) ~= nil, C.Lines[1].Plain)
check("welcome has load time and plugins", C.Lines[2].Plain:find("loaded in %d+ ms · 0 plugins loaded") ~= nil, C.Lines[2].Plain)
check("welcome integrity ok", C.Lines[3].Plain:find("integrity ok", 1, true) and C.Lines[3].Plain:find("files", 1, true) and C.Lines[3].Plain:find("51/51 executor functions", 1, true), C.Lines[3].Plain)
local Integrity = T.import("base/integrity")
local report = Integrity.run()
check("integrity clean in a full copy", report.Clean, table.concat(report.Problems, "; "))
local saved = H.FILES["Tungsten/base/data/icons/copy.png"]
H.FILES["Tungsten/base/data/icons/copy.png"] = nil
H.FILES["Tungsten/documentation/topics/05_errors.md"] ..= "\nextra line"
local at = run("/integrity")
check("/integrity finds a missing file", has(at, "missing base/data/icons/copy.png"), lines(at))
check("/integrity finds a changed file", has(at, "changed documentation/topics/05_errors.md"), lines(at))
H.FILES["Tungsten/base/data/icons/copy.png"] = saved
H.FILES["Tungsten/documentation/topics/05_errors.md"] = H.FILES["Tungsten/documentation/topics/05_errors.md"]:gsub("\nextra line$", "")
check("integrity clean again", Integrity.run().Clean)
local fn = H.env.getproperties
H.env.getproperties = nil
local noted = Integrity.run()
check("a missing executor function is a note, not a failure", noted.Ok and not noted.Clean and table.concat(noted.Problems, ";"):find("getproperties is missing", 1, true), table.concat(noted.Problems, ";"))
H.env.getproperties = fn
at = run("/about")
check("/about shows the load time", has(at, "load ") and has(at, "tungsten (unified)"), lines(at))

----------------------------------------------------------------------
-- 2. Window: name, pill, fade
----------------------------------------------------------------------
local title = H.find(W.TitleBar, "Title")
local unified = H.find(W.TitleBar, "Unified")
check("title: tungsten, large and accent-colored", title and title.Text == "tungsten" and title.TextColor3 == T.Theme.Colors.Accent and title.TextSize > T.Theme.Sizes.Title, title and title.Text)
check("title: (unified), small and white", unified and unified.Text == "(unified)" and unified.TextColor3 == T.Theme.Colors.Text and unified.TextSize < title.TextSize)
local pill = W.Pill
local corner = pill:FindFirstChildOfClass("UICorner")
check("pill is a rounded square", corner and corner.CornerRadius.Scale == 0 and corner.CornerRadius.Offset > 0 and pill.Size.X.Offset == pill.Size.Y.Offset)
local mark = H.find(pill, "Mark")
check("pill is 20% smaller (35 px)", pill.Size.X.Offset == 35)
local titleLogo = H.find(W.Root, "Heading") and H.find(W.Root, "Heading"):FindFirstChild("Icon")
check("title bar icon is the brand icon (same as the pill)", T.Icons.Brand == "mark_w" and titleLogo and mark and titleLogo.Image == mark.Image and titleLogo.ImageColor3 == T.Theme.Colors.Accent, titleLogo and titleLogo.Image)
local historyHint = false
for _, d in W.Gui:GetDescendants() do
	if d:IsA("TextLabel") and d.Text:find("Up/Down", 1, true) then
		historyHint = true
	end
end
check("console input shows no Up/Down hint", not historyHint)
check("pill shows a plain W in the accent color", mark and mark.Image:find("mark_w", 1, true) and mark:GetAttribute("TungstenColored") ~= true and mark.ImageColor3 == T.Theme.Colors.Accent, mark and mark.Image)
local backing = W.Backing
local rootBack = backing.BackgroundTransparency
check("the window has a faint outline in the accent color", W.Outline and W.Outline.Color == T.Theme.Colors.Accent and W.Outline.Transparency > 0.3 and W.Outline.Transparency < 0.9)
check("…around the window and the explorer together", W.Outline.Parent == W.OutlineFrame and E.Panel:FindFirstChildOfClass("UIStroke") == nil and math.abs(W.OutlineFrame.AbsoluteSize.X - (W.Root.AbsoluteSize.X + E.Panel.AbsoluteSize.X)) <= 1)
check("a thin seam where they meet", H.find(E.Panel, "Seam") ~= nil)
W:Minimize()
H.step()
H.step()
local midFade = backing.BackgroundTransparency
check("minimize fades the window", W.Root.Visible and midFade > rootBack and midFade < 1, midFade)
check("pill fades in where it sits (no drop)", pill.Visible and pill.Position.Y.Offset == 22)
H.advance(0.5)
check("window hidden after the fade", not W.Root.Visible)
check("its look is kept for the way back", backing.BackgroundTransparency == rootBack)
check("scale untouched (no shrink)", W.RootScale.Scale == 1)
W:Restore()
H.step()
check("restore fades in", W.Root.Visible and backing.BackgroundTransparency > rootBack)
H.advance(0.5)
check("restored look", backing.BackgroundTransparency == rootBack and not pill.Visible)

----------------------------------------------------------------------
-- 3. Explorer filter
----------------------------------------------------------------------
E.expand(workspace)
E.expand(map)
H.advance(0.2)
check("filter button beside the search box", E.FilterButton and E.FilterButton.AbsolutePosition.X > E.SearchInput.Instance.AbsolutePosition.X)
H.clickObject(E.FilterButton)
H.advance(0.2)
local panel = E.FilterPanel
check("the button opens the filter panel", panel and panel.Kind == "filter" and not panel.Closed)
local partsChip = panel and H.find(panel.Body, "Group_parts")
check("panel lists the groups", partsChip ~= nil and H.find(panel.Body, "Group_scripts") ~= nil)
H.clickObject(partsChip)
H.advance(0.5)
check("ticking Parts filters the tree", Filter.showsOnly() and hasRow("Door") and hasRow("Baseplate") and not hasRow("Stuff") and not hasRow("Lamp"), rowNames())
check("parents of matches stay", hasRow("Workspace") and hasRow("Map"))
check("footer says so", E.Status.Text:find("filter:", 1, true) ~= nil, E.Status.Text)
check("filter button lit", E.FilterButton.BackgroundColor3 == T.Theme.Colors.AccentSoft)
check("filter saved", table.find(Settings.get("ExplorerFilter").Only, "parts") ~= nil)
panel = E.FilterPanel
local clear = panel and H.find(panel.Body, "Clear")
if clear then
	H.clickObject(clear)
	H.advance(0.5)
end
check("Clear shows everything", not Filter.active() and hasRow("Stuff"), rowNames())
Overlay.closeAll()
-- hiding classes
Filter.hideClass("Camera")
H.advance(0.5)
check("hidden classes leave the tree", not hasRow("Camera") and hasRow("Baseplate"), rowNames())
check("footer names what is hidden", E.Status.Text:find("hiding Camera", 1, true) ~= nil, E.Status.Text)
local list = E.find("Camera")
check("searches leave hidden classes out", list and #list == 0)
local all = E.find("Camera", nil, { NoFilter = true })
check("NoFilter finds them", all and #all == 1)
local okHigh, why = E.highlight(camera)
check("highlight says the filter hides it", okHigh == false and tostring(why):find("filter", 1, true), why)
at = run("/find Camera")
check("/find follows the filter", has(at, "nothing matches"), lines(at))
E.clearSearch()
-- show classes + search together
Filter.set({ Hide = {}, Classes = { "PointLight" } })
H.advance(0.5)
check("a class to show (with its parents)", hasRow("Lamp") and hasRow("Door") and not hasRow("Baseplate"), rowNames())
E.setSearch("La")
H.advance(0.5)
check("search inside the filter", hasRow("Lamp"), rowNames())
E.setSearch("Base")
H.advance(0.5)
check("search can't reach past the filter", not hasRow("Baseplate"), rowNames())
E.clearSearch()
H.advance(0.3)
E.select({ base })
H.advance(0.3)
check("selecting a filtered-out object still shows it", hasRow("Baseplate"), rowNames())
Filter.clear()
H.advance(0.3)
-- /filter
at = run("/filter show remotes")
check("/filter show <group>", Filter.showsOnly() and has(at, "only Remotes"), lines(at))
at = run("/filter hide camera")
check("/filter hide <class> (any case)", table.find(Filter.get().Hide, "Camera") ~= nil, lines(at))
at = run("/filter")
check("/filter shows the filter", has(at, "only Remotes") and has(at, "hiding Camera"), lines(at))
at = run("/filter show NotAThing")
check("/filter unknown name", has(at, "is not a group or a class"), lines(at))
at = run("/filter groups")
check("/filter groups lists them", has(at, "parts") and has(at, "remotes"), lines(at))
at = run("/filter clear")
check("/filter clear", not Filter.active(), lines(at))
-- path bar child lists
Filter.hideClass("Camera")
E.load({ base })
H.advance(0.3)
local chev
for _, c in P.Crumbs:GetChildren() do
	if c.Name == "Chevron" then
		chev = chev or c
	end
end
if chev then
	H.clickObject(chev)
	H.advance(0.2)
end
local listed = {}
local top = Overlay.top()
if top and top.Frame then
	for _, d in top.Frame:GetDescendants() do
		if d:IsA("TextLabel") then
			listed[d.Text] = true
		end
	end
end
check("path bar child lists skip hidden classes", listed.Workspace or listed.Baseplate or listed.Map or next(listed) ~= nil)
check("…Camera not offered", not listed.Camera)
Overlay.closeAll()
local crumbList = {}
for _, c in P.Crumbs:GetChildren() do
	if c.Name == "Crumb" then
		table.insert(crumbList, c)
	end
end
table.sort(crumbList, function(a, b) return a.LayoutOrder < b.LayoutOrder end)
H.clickObject(crumbList[1], "MouseButton2")
H.advance(0.2)
local crumbMenu = P.Menu
local copyItem = nil
for _, d in crumbMenu.Frame:GetDescendants() do
	if d.Name == "Text" and d.Text == "Copy" then
		copyItem = d.Parent
	end
end
H.clickObject(copyItem)
H.advance(0.1)
check("right-click a part of the path: its own Copy", H.CLIPBOARD == "game.Workspace", H.CLIPBOARD)
Filter.clear()
-- plugin groups
Filter.addGroup("doors", { Text = "Doors", Test = function(obj) return obj.Name:find("Door") ~= nil end, Owner = "demo" })
Filter.toggleGroup("doors", true)
H.advance(0.5)
check("plugin filter group", hasRow("Door") and not hasRow("Baseplate"), rowNames())
T.UI.removeOwner("demo")
H.advance(0.5)
check("removing the plugin drops its group", Filter.group("doors") == nil and not Filter.active() and hasRow("Baseplate"))

----------------------------------------------------------------------
-- 4. Filter words in every search
----------------------------------------------------------------------
local TextFilter = T.import("base/textfilter")
local test = TextFilter.compile('part !wedge "Exact" hint:Base')
check("text filter words", test({ "PartName", "Exact" }, { hint = "BasePart" }) and not test({ "WedgePart", "Exact" }, { hint = "BasePart" }))
check("text filter plain word", TextFilter.isPlain("door") and not TextFilter.isPlain("a b") and not TextFilter.isPlain("!x"))
local Dropdown = T.import("base/ui/components/dropdown")
local popup = Dropdown.popup({
	Options = { { Value = 1, Text = "Red Part", Hint = "Part" }, { Value = 2, Text = "Red Wedge", Hint = "WedgePart" }, { Value = 3, Text = "Blue Part", Hint = "Part" } },
	AnchorPos = V2(100, 100),
	AnchorSize = V2(100, 20),
	Searchable = true,
	OnPick = function() end,
})
local searchBox
for _, d in popup.Frame:GetDescendants() do
	if d:IsA("TextBox") then
		searchBox = d
	end
end
searchBox.Text = "red !wedge"
H.step()
check("dropdown search takes several words and !not", popup.State.Filtered and #popup.State.Filtered == 1 and popup.State.Filtered[1].Value == 1, popup.State.Filtered and #popup.State.Filtered)
searchBox.Text = "hint:wedge"
H.step()
check("dropdown search by hint", popup.State.Filtered and #popup.State.Filtered == 1 and popup.State.Filtered[1].Value == 2)
popup:Close()
local Docs = T.Docs
local found = Docs.search("group:Tungsten explorer !menus")
local ids = {}
for _, topic in found do
	ids[topic.Id] = true
end
check("documentation search uses the same words", ids.explorer and not ids.menus)

----------------------------------------------------------------------
-- 5. Modular documentation
----------------------------------------------------------------------
Docs.addTopic({ Id = "demo", Title = "Demo Plugin", Group = "Demo", Order = 5, Source = "# Demo Plugin\n\nHello from a plugin.\n\n{{demo-live:7}}", Owner = "demo" })
Docs.addDirective("demo-live", { Source = function(arg) return "Live value " .. tostring(arg) end, Owner = "demo" })
Docs.addSection("commands", { Id = "demo", Title = "Demo commands", Source = "| A | B |\n|---|---|\n| x | y |", Order = 99, Owner = "demo" })
local topics = Docs.topics()
check("plugin topics come after Tungsten's", topics[#topics].Id == "demo", topics[#topics].Id)
local demo = Docs.get("demo")
check("directives fill in", demo.Text:find("Live value 7", 1, true) ~= nil, demo.Text)
check("sections join other topics", Docs.get("commands").Text:find("Demo commands", 1, true) ~= nil)
T.Console.Commands.register({ Name = "demohi", Group = "Demo", Usage = "/demohi", Description = "say hi", Owner = "demo", Run = function() end })
local commandsText = Docs.get("commands").Text
check("command tables are made from the commands", commandsText:find("/filter", 1, true) and commandsText:find("/props", 1, true), "")
check("plugin commands show up by themselves", commandsText:find(":demo.demohi", 1, true) ~= nil and commandsText:find("from demo", 1, true) ~= nil)
check("a new group gets its own table", Docs.get("commands").Text:find("Demo", 1, true) ~= nil)
T.Tabs:Select("documentation")
H.advance(0.3)
Docs.open("demo")
H.advance(0.2)
local DV = Docs.View
check("docs tab shows plugin topics", DV.Current and DV.Current.Id == "demo")
local listedDemo = false
for _, item in DV.List:GetItems() do
	if item.Id == "demo" then
		listedDemo = true
	end
end
check("…listed with their group", listedDemo)
Docs.addTopic({ Id = "custom", Title = "Custom", Group = "Demo", Owner = "demo", Build = function(content)
	local label = new("TextLabel")
	label.Name = "Mine"
	label.Text = "built by a plugin"
	label.Parent = content
end })
Docs.open("custom")
H.advance(0.2)
check("topics with their own UI", H.find(DV.Scroll.Content, "Mine") ~= nil)
DV.Search:SetText("group:demo")
DV.Filter = "group:demo"
DV:_refreshList()
check("topic list search by group", #DV.List:GetItems() == 2, #DV.List:GetItems())
DV.Filter = ""
DV:_refreshList()
T.UI.removeOwner("demo")
H.advance(0.2)
check("removing the plugin removes its docs", Docs.get("demo") == nil and not Docs.get("commands").Text:find("Demo commands", 1, true))
at = run("/help")
check("/help still fine", has(at, "EXPLORER"), "")
local broken = {}
for _, topic in Docs.topics() do
	if topic.Text:find("unknown block", 1, true) or topic.Text:find("could not be shown", 1, true) then
		table.insert(broken, topic.Id)
	end
end
check("every topic's live blocks fill in", #broken == 0, table.concat(broken, ","))
check("the menus block lists the tab bar menu", Docs.get("menus").Text:find("tabbar", 1, true) ~= nil)
check("the components block lists Prompt", Docs.get("ui").Text:find("Prompt", 1, true) ~= nil)
check("the filter groups block", Docs.get("explorer").Text:find("Constraints", 1, true) ~= nil)
for _, topic in Docs.topics() do
	Docs.open(topic.Id)
	H.advance(0.05)
end
check("every topic renders without errors", #H.ERRORS == 0, H.ERRORS[1])

----------------------------------------------------------------------
-- 6. Explorer › Load
----------------------------------------------------------------------
T.Tabs:Select("console")
H.advance(0.3)
E.select({ door })
H.advance(0.2)
local Menus = T.Menus
local ctx = T.import("base/explorer/menu").context(E, E.View:GetSelected(), E.View:GetSelected()[1], V2(10, 10))
local built = Menus.build("explorer", ctx)
check("Load is first and emphasized", built[2] and built[2].Text == "Load" and built[2].Emphasis == true and built[2].Shortcut == "every tab", built[2] and built[2].Shortcut)
at = #C.Lines + 1
built[2].Callback(ctx, built[2])
H.advance(0.2)
check("Load into the console: $loaded", T.Variables.get("loaded") == door, tostring(T.Variables.get("loaded")))
check("…shown in the console", has(at, "loaded = ") and has(at, "Door"), lines(at))
check("…and in the path bar", P.current() == door)
T.Tabs:Select("documentation")
H.advance(0.3)
E.load({ lamp })
H.advance(0.3)
check("Load into Documentation opens the class page", Docs.View.Current and Docs.View.Current.Title == "PointLight", Docs.View.Current and Docs.View.Current.Title)
check("…with its properties", Docs.View.Current.Text:find("Brightness", 1, true) ~= nil)
check("path bar of that tab shows it", P.current() == lamp)
-- a plugin tab decides what loading means
local got
T.Registry.addTab({ Id = "demo", Title = "Demo", Icon = "Tungsten/plugins/demo/icon.png", Owner = "demo", OnLoad = function(instances) got = instances end, Build = function() end })
H.advance(0.2)
T.Tabs:Select("demo")
H.advance(0.3)
E.load({ base, door })
H.advance(0.2)
check("plugin tab OnLoad gets the objects", got and #got == 2 and got[1] == base)

----------------------------------------------------------------------
-- 7. Tabs and icons for plugins
----------------------------------------------------------------------
local Registry = T.Registry
local Icons = T.Icons
local demoEntry = T.Tabs.Entries.demo
check("plugin tab with an icon file", demoEntry and demoEntry.Icon.Image:find("plugins/demo/icon.png", 1, true), demoEntry and demoEntry.Icon.Image)
Icons.register("demo.star", "rbxassetid://123", { Owner = "demo" })
Registry.updateTab("demo", { Title = "Demo Tool", Icon = "demo.star", Badge = 7 })
H.advance(0.1)
check("tab updates: icon", demoEntry.Icon.Image == "rbxassetid://123")
check("tab updates: badge", demoEntry.Badge.Visible and demoEntry.BadgeText.Text == "7")
check("tab updates: title in the title bar", W.Subtitle.Text:find("Demo Tool", 1, true) ~= nil, W.Subtitle.Text)
Registry.updateTab("demo", { Badge = 0 })
check("badge 0 hides", not demoEntry.Badge.Visible)
-- tooltip
H.hover(demoEntry.Button)
H.advance(0.6)
local Tooltip = T.import("base/ui/components/tooltip")
local tip = Tooltip.current()
check("hovering a tab shows its title", tip and H.find(tip, "Text").Text == "Demo Tool")
H.moveMouse(V2(5, 5))
H.advance(0.1)
check("leaving hides it", Tooltip.current() == nil)
H.hover(demoEntry.Button)
H.advance(0.6)
check("tooltip back", Tooltip.current() ~= nil)
W:Minimize()
H.advance(0.5)
check("minimizing removes the tooltip", Tooltip.current() == nil)
H.moveMouse(V2(5, 5))
H.hover(W.Pill)
H.advance(1)
check("the minimized button has no tooltip", Tooltip.current() == nil)
H.moveMouse(V2(5, 5))
W:Restore()
H.advance(0.5)
-- order and menu
local before = table.concat(T.Tabs:Order(), ",")
local selected = {}
Registry.addTab({ Id = "demo2", Title = "Demo Two", Owner = "demo", OnSelect = function() table.insert(selected, "in") end, OnDeselect = function() table.insert(selected, "out") end })
H.advance(0.1)
check("tabs listed in order", table.concat(T.Tabs:Order(), ",") == before .. ",demo2", table.concat(T.Tabs:Order(), ","))
local tabMenu = T.Tabs:OpenMenu(Registry.getTab("demo2"), V2(50, 50))
H.advance(0.1)
local function menuItem(menu, text)
	for _, d in menu.Frame:GetDescendants() do
		if d.Name == "Text" and d.Text == text and d.Parent.Name:sub(1, 4) == "Item" then
			return d.Parent
		end
	end
	return nil
end
check("tab menu", menuItem(tabMenu, "Open") and menuItem(tabMenu, "Move up") and menuItem(tabMenu, "Hide tab"))
H.clickObject(menuItem(tabMenu, "Move up"))
H.advance(0.2)
check("Move up", table.concat(T.Tabs:Order(), ","):find("demo2,demo", 1, true) ~= nil, table.concat(T.Tabs:Order(), ","))
check("order saved", table.find(Settings.get("TabOrder"), "demo2") ~= nil)
T.Tabs:Select("demo2")
T.Tabs:Select("console")
check("OnSelect / OnDeselect", table.concat(selected, ",") == "in,out", table.concat(selected, ","))
Registry.setHidden("demo2", true)
H.advance(0.1)
check("hide a tab", T.Tabs.Entries.demo2 == nil)
check("built-in tabs can't be hidden", not Registry.setHidden("console", true))
Registry.setHidden("demo2", false)
H.advance(0.1)
check("show it again", T.Tabs.Entries.demo2 ~= nil)
-- Ctrl+Down
H.focusBox(nil)
H.keys.LeftControl = true
H.key("Down")
H.keys.LeftControl = nil
check("Ctrl+Down opens the next tab", T.Tabs.Selected == "plugins", T.Tabs.Selected)
-- scrolling
for i = 1, 20 do
	Registry.addTab({ Id = "many" .. i, Title = "Many " .. i, Owner = "demo" })
end
H.advance(0.3)
check("the side bar scrolls when tabs don't fit", T.Tabs.Scroll:CanScroll("Y"))
T.Tabs:Select("many20")
H.advance(0.4)
check("opening a tab scrolls it into view", T.Tabs.Scroll.Offset.Y > 0, T.Tabs.Scroll.Offset.Y)
T.UI.removeOwner("demo")
H.advance(0.3)
check("removing the plugin removes its tabs and icons", Registry.getTab("demo") == nil and Registry.getTab("many3") == nil and Icons.resolve("demo.star") == nil)
check("an open plugin tab falls back to the first", T.Tabs.Selected == "console", T.Tabs.Selected)

----------------------------------------------------------------------
-- 8. Prompts, toasts
----------------------------------------------------------------------
local Prompt = T.Prompt
local result = "unset"
E_.task.spawn(function()
	result = Prompt.await(Prompt.confirm({ Title = "Delete?", Text = "This can't be undone.", Danger = true, ConfirmText = "Delete" }))
end)
H.advance(0.1)
local dialog = Overlay.top()
check("confirm opens a dialog", dialog and dialog.Frame.Name == "Prompt" and H.find(dialog.Frame, "Card") ~= nil)
check("…not darkened", dialog.Frame.BackgroundTransparency == 1)
check("…over the main window, not the whole screen", dialog.Frame.AbsoluteSize == W.Root.AbsoluteSize and math.abs(dialog.Frame.AbsolutePosition.X - W.Root.AbsolutePosition.X) <= 1)
H.click(H.toScreen(V2(5, 5)))
H.advance(0.1)
check("clicking outside doesn't close it", not dialog.Closed)
local confirmButton = H.find(dialog.Frame, "Confirm")
H.clickObject(confirmButton)
H.advance(0.1)
check("await returns true on confirm", result == true, tostring(result))
E_.task.spawn(function()
	result = Prompt.await(Prompt.confirm({ Title = "Again?" }))
end)
H.advance(0.1)
H.key("Escape")
H.advance(0.1)
check("Escape cancels (false)", result == false, tostring(result))
-- input with a type
local inputHandle = Prompt.input({ Title = "How many?", Type = "number", Validate = function(text)
	if tonumber(text) ~= nil and tonumber(text) > 0 then
		return true
	end
	return false, "must be above 0"
end })
E_.task.spawn(function()
	result = Prompt.await(inputHandle)
end)
H.advance(0.1)
inputHandle.Box:SetText("abc")
inputHandle.Submit()
check("input says what's wrong", inputHandle.Problem.Text ~= "" and not inputHandle.Closed, inputHandle.Problem.Text)
inputHandle.Box:SetText("-2")
inputHandle.Submit()
check("input Validate refuses", inputHandle.Problem.Text == "must be above 0", inputHandle.Problem.Text)
inputHandle.Box:SetText("12")
inputHandle.Submit()
H.advance(0.1)
check("input returns the typed value", result == 12, tostring(result))
-- choice
local choice = Prompt.choice({ Title = "Team", Options = { "Red", "Blue", "Green" } })
E_.task.spawn(function()
	result = Prompt.await(choice)
end)
H.advance(0.1)
H.clickObject(choice.OptionButtons[2])
H.advance(0.1)
check("choice returns the picked option", result == "Blue", tostring(result))
-- form + a field kind of a plugin
Prompt.registerFieldKind("upper", {
	Owner = "demo",
	Build = function(holder, field, form)
		local value = field.Default or ""
		return { Get = function() return value:upper() end, Set = function(v) value = v end }
	end,
})
local form = Prompt.form({
	Title = "Rule",
	Fields = {
		{ Key = "name", Label = "Name", Kind = "text", Default = "Rule", Required = true },
		{ Key = "max", Label = "Max", Kind = "number", Default = 5 },
		{ Key = "on", Label = "On", Kind = "toggle", Default = true },
		{ Key = "mode", Label = "Mode", Kind = "dropdown", Options = { "Log", "Block" }, Default = "Log" },
		{ Key = "class", Label = "Class", Kind = "class", Default = "Part" },
		{ Key = "pos", Label = "Where", Kind = "value", ValueType = "Vector3", Default = E_.Vector3.new(1, 2, 3) },
		{ Key = "tag", Label = "Tag", Kind = "upper", Default = "abc" },
	},
})
E_.task.spawn(function()
	result = Prompt.await(form)
end)
H.advance(0.1)
form.Fields.pos.Control:SetText("1, 2")
form.Submit()
check("form shows a field's problem", form.Problem.Text:find("Where", 1, true) ~= nil and not form.Closed, form.Problem.Text)
form.Fields.pos.Control:SetText("4, 5, 6")
form.Submit()
H.advance(0.1)
check("form returns every field", type(result) == "table" and result.name == "Rule" and result.max == 5 and result.on == true and result.mode == "Log" and result.class == "Part" and result.pos == E_.Vector3.new(4, 5, 6) and result.tag == "ABC")
T.UI.removeOwner("demo")
check("plugin field kinds go with the plugin", not table.find(Prompt.fieldKinds(), "upper"))
local custom = Prompt.custom({ Title = "Mine", Build = function(body) local l = new("TextLabel") l.Name = "Inside" l.Parent = body end })
H.advance(0.1)
check("custom dialog", H.find(custom.Card, "Inside") ~= nil)
custom:Close()
local pop = Prompt.popover({ AnchorPos = V2(200, 200), Build = function(frame) local l = new("TextLabel") l.Name = "Pop" l.Parent = frame end })
check("popover", pop.Kind == "popover" and H.find(pop.Frame, "Pop") ~= nil)
H.step()
H.click(H.toScreen(V2(5, 700)))
H.advance(0.1)
check("popovers close on outside clicks", pop.Closed)
-- toasts
local Notify = T.Notify
local clicked = false
local toast = Notify.show({ Title = "Saved", Text = "3 objects", Kind = "success", Duration = 1, Actions = { { Text = "Open", Callback = function() clicked = true end } } })
H.advance(0.1)
check("toast shows", toast and toast.Frame.Parent ~= nil and #Notify.Shown == 1)
H.clickObject(toast.Buttons.Open)
H.advance(0.1)
check("toast action runs and closes it", clicked and toast.Closed)
local timed = Notify.info("short", nil, { Duration = 0.5 })
H.advance(1)
check("toasts close by themselves", timed.Closed)
Notify.registerKind("demo", { Icon = "class_remote", Color = "Info", Owner = "demo" })
for i = 1, 7 do
	Notify.show({ Text = "n" .. i, Kind = "demo", Duration = 0 })
end
check("at most 5 toasts", #Notify.Shown == 5)
Notify.clear()
check("clear", #Notify.Shown == 0)

----------------------------------------------------------------------
-- 9. Command bar
----------------------------------------------------------------------
local Bar = T.CommandBar
W:Minimize()
H.advance(0.5)
H.key("Quote")
H.advance(0.2)
check("' opens the command bar", Bar.IsOpen and Bar.gui().Enabled)
check("the window stays minimized", W.Minimized and not W.Root.Visible)
local box = Bar.box()
check("the bar has focus", E_.game and H.focused == box)
box.Text = "/echo from the bar"
box.FocusLost:Fire(true)
H.advance(0.3)
local shown = {}
for _, line in Bar.lines() do
	table.insert(shown, line.Plain)
end
check("Enter runs it in the console", lines(1):find("from the bar", 1, true) ~= nil)
check("output shows under the bar", table.concat(shown, "\n"):find("from the bar", 1, true) ~= nil, table.concat(shown, "|"))
check("stays open for the next input", Bar.IsOpen)
H.focused = box
H.key("Up")
check("Up recalls history", box.Text == "/echo from the bar", box.Text)
box.Text = "> 6 * 7"
box.FocusLost:Fire(true)
H.advance(0.3)
check("Luau runs from the bar", lines(1):find("42", 1, true) ~= nil)
H.focused = box
H.key("Escape")
H.advance(0.3)
check("Escape closes it", not Bar.IsOpen)
H.focused = nil
at = run("/bar key F8")
check("/bar key changes the key", Settings.get("CommandBarKey") == "F8", lines(at))
H.key("F8")
H.advance(0.2)
check("the new key opens it", Bar.IsOpen)
Bar.close()
H.advance(0.3)
Settings.set("CommandBarKey", "Quote")
H.key("Quote", true)
H.advance(0.2)
check("' opens it even when the game marks the key as processed", Bar.IsOpen)
Bar.close()
H.advance(0.3)
H.focused = new("TextBox")
H.key("Quote")
H.advance(0.2)
check("a focused text box keeps the key from opening it", not Bar.IsOpen)
H.focused = nil
Bar.open()
H.advance(0.2)
box = Bar.box()
local function texts(root)
	local out = {}
	for _, d in root:GetDescendants() do
		if (d:IsA("TextLabel") or d:IsA("TextBox")) and d.Text ~= "" then
			table.insert(out, d.Text)
		end
		if d:IsA("TextBox") and d.PlaceholderText ~= "" then
			table.insert(out, d.PlaceholderText)
		end
	end
	return out
end
check("no instruction text on the bar", #texts(Bar.frame()) == 0, table.concat(texts(Bar.frame()), " | "))
check("the bar is see-through", H.find(Bar.frame(), "Bar").BackgroundTransparency > 0.05 and H.find(Bar.frame(), "Bar").BackgroundTransparency < 0.4)
-- live suggestions, like the console's
local function typeIn(text)
	box.CursorPosition = #text + 1
	box.Text = text
	H.step()
end
H.focused = box
typeIn("/ec")
H.advance(0.1)
local list = Bar.completion()
check("typing shows the console's suggestion list", list and list:IsOpen())
local expected = C.complete("/ec", 4).Items
local same = list and #list.Items == #expected
if same then
	for i, item in list.Items do
		if item.Label ~= expected[i].Label or item.Hint ~= expected[i].Hint then
			same = false
		end
	end
end
check("…with the same entries and hints as the console", same)
check("…see-through like the bar", list and list.Panel and list.Panel.BackgroundTransparency == Bar.Transparency)
local panelBottom = list.Panel.AbsolutePosition.Y + list.Panel.AbsoluteSize.Y
local barTop = H.find(Bar.frame(), "Bar").AbsolutePosition.Y
check("…next to the bar", panelBottom <= barTop or list.Panel.AbsolutePosition.Y >= barTop + 40)
H.key("Tab")
H.advance(0.1)
check("Tab completes", box.Text:sub(1, 5) == "/echo", box.Text)
typeIn("/he")
H.advance(0.1)
check("suggestions again", list:IsOpen())
H.key("Down")
check("Down moves the highlight", list.Highlight == 2 or #list.Items == 1)
H.key("Escape")
H.advance(0.1)
check("the first Escape closes only the suggestions", Bar.IsOpen and not list:IsOpen())
-- clicking a suggestion
typeIn("/ec")
H.advance(0.1)
if list:IsOpen() then
	local row = H.find(list.Panel, "Row1")
	H.clickObject(row)
	H.advance(0.1)
end
check("clicking a suggestion applies it and keeps the bar open", Bar.IsOpen and box.Text:sub(1, 5) == "/echo", box.Text)
-- click away
box.Text = "half typed"
H.advance(0.1)
H.click(V2(5, H.SCREEN.Y - 5))
H.advance(0.3)
check("clicking somewhere else closes the bar", not Bar.IsOpen)
H.focused = nil
Bar.open()
H.advance(0.3)
check("it opens empty (text isn't kept)", Bar.box().Text == "" and #Bar.lines() == 0, Bar.box().Text)
box = Bar.box()
H.focused = box
box.Text = "/echo kept?"
box.FocusLost:Fire(true)
H.advance(0.3)
check("output shows", #Bar.lines() > 0)
local resultsFrame = H.find(Bar.frame(), "Results")
check("the output is see-through too", resultsFrame.BackgroundTransparency > 0.05)
H.click(H.toScreen(H.find(Bar.frame(), "Bar").AbsolutePosition + V2(100, 10)))
H.advance(0.1)
check("clicking the bar itself keeps it open", Bar.IsOpen)
Bar.close()
H.advance(0.3)
Bar.open()
H.advance(0.3)
check("the output is gone after reopening", #Bar.lines() == 0 and not H.find(Bar.frame(), "Results").Visible)
local holderFrame = Bar.gui():FindFirstChild("CommandBarHolder")
local centre = holderFrame.AbsolutePosition.X + holderFrame.AbsoluteSize.X / 2
check("the bar is centred on the screen", math.abs(centre - H.SCREEN.X / 2) <= 1, centre - H.SCREEN.X / 2)
check("its holder is the bar's fixed width (the bar never scales)", math.abs(holderFrame.AbsoluteSize.X - 560) <= 1)
-- one click away, then the key opens it again straight away
H.focused = Bar.box()
H.click(V2(5, H.SCREEN.Y - 5))
H.advance(0.3)
check("one click closes it", not Bar.IsOpen)
H.focused = Bar.box() -- the game may leave the hidden box focused after that click
H.key("Quote")
H.advance(0.2)
check("the key opens it again on the first press", Bar.IsOpen)
Bar.close()
H.advance(0.3)
check("closing lets go of the keyboard", H.focused ~= Bar.box())
H.focused = nil
W:Restore()
H.advance(0.5)

----------------------------------------------------------------------
-- 10. Selecting vs loading; /clearvars
----------------------------------------------------------------------
T.Tabs:Select("console")
H.advance(0.3)
P.clear("console")
T.Variables.unset("loaded")
E.select({ base })
H.advance(0.2)
check("selecting doesn't fill the path bar", P.current() == nil)
check("…or load into the tab", T.Variables.get("loaded") == nil)
H.clickObject(P.GoButton)
H.advance(0.2)
check("the path bar arrow loads the selection", P.current() == base and T.Variables.get("loaded") == base)
T.Variables.set("a", 1)
T.Variables.set("b", "two")
at = run("/clearvars")
check("/clearvars removes every variable", T.Variables.get("a") == nil and T.Variables.get("b") == nil and T.Variables.get("loaded") == nil and has(at, "removed"), lines(at))
check("…but $sel stays", T.Variables.get("sel") == base)
at = run("/clearvars")
check("/clearvars with nothing left", has(at, "no variables"), lines(at))

----------------------------------------------------------------------
-- 11. Smooth explorer collapse
----------------------------------------------------------------------
local Ex = T.Explorer
local exHolder = T.Window.Root:FindFirstChild("Explorer")
local exPanel = Ex.Panel
local exToggle = Ex.ToggleButton
if not Ex.isOpen() then
	Ex.setOpen(true, false)
end
H.advance(0.5)
check("the explorer frame doesn't clip (no cut corners)", exHolder.ClipsDescendants == false)
check("it sits under the window", exHolder.ZIndex < W.Backing.ZIndex)
local restX = exPanel.AbsolutePosition.X
local windowRight = W.Root.AbsolutePosition.X + W.Root.AbsoluteSize.X
Ex.setOpen(false)
H.advance(0.08)
local function relX()
	return exPanel.AbsolutePosition.X - (W.Root.AbsolutePosition.X + W.Root.AbsoluteSize.X)
end
local midX = exPanel.AbsolutePosition.X
local midRel = relX()
check("collapsing slides the panel left, under the window", midX < restX and exPanel.Visible, midX - restX)
check("…without fading it", exPanel.BackgroundTransparency == 0)
check("…its height and top edge don't change while it slides", exPanel.AbsolutePosition.Y == W.Root.AbsolutePosition.Y and exPanel.AbsoluteSize.Y == W.Root.AbsoluteSize.Y, exPanel.AbsoluteSize.Y - W.Root.AbsoluteSize.Y)
check("…the window's right corners go round once the panel no longer covers them", W.BackingSquare.Visible == false)
check("…and the outline follows the panel back to the window", math.abs(W.OutlineFrame.AbsoluteSize.X - W.Root.AbsoluteSize.X) < 1, W.OutlineFrame.AbsoluteSize.X - W.Root.AbsoluteSize.X)
Ex.setOpen(true) -- reverse half-way
-- (the test harness applies tweens at once; in the game the slide back
-- starts from wherever the panel is)
check("reversing heads straight back out, still shown", exPanel.Visible and exHolder.Visible and relX() > midRel)
H.advance(0.6)
check("reopened where it was", exPanel.Visible and exHolder.Visible and math.abs(exPanel.AbsolutePosition.X - restX) < 1)
local toggleIcon = exToggle:FindFirstChild("Icon")
check("open: the title bar button's icon is lit", toggleIcon.ImageColor3 == T.Theme.Colors.Accent)
Ex.setOpen(false)
H.advance(0.15)
H.advance(0.6)
local hiddenRight = exPanel.AbsolutePosition.X + exPanel.AbsoluteSize.X
check("closed: the whole panel ends up behind the window", hiddenRight <= windowRight - 4, hiddenRight - windowRight)
check("…at full height (only the horizontal position animates)", exPanel.AbsolutePosition.Y == W.Root.AbsolutePosition.Y and exPanel.AbsoluteSize.Y == W.Root.AbsoluteSize.Y)
check("…its right edge a corner radius inside the window's, so nothing shows past the round corners", hiddenRight <= windowRight - T.Theme.Sizes.Radius + 0.5, hiddenRight - windowRight)
-- the corners follow how far the panel sticks out
W:SetAttached(0.01)
check("barely out: the window's corners stay round", W.BackingSquare.Visible == false)
W:SetAttached(0.5)
check("half out: the corners are square, the outline goes around both", W.BackingSquare.Visible == true and math.abs(W.OutlineFrame.Size.X.Scale - (1 + T.Scale.SideShare * 0.5)) < 1e-6)
W:SetAttached(0)
check("closed: round corners, outline around the window alone", W.BackingSquare.Visible == false and W.OutlineFrame.Size.X.Scale == 1)
check("collapsed: hidden after the slide", not exHolder.Visible)
check("collapsed: the icon is no longer lit", toggleIcon.ImageColor3 ~= T.Theme.Colors.Accent)
Ex.setOpen(true)
H.advance(0.6)
check("open again", exHolder.Visible and exPanel.Visible and toggleIcon.ImageColor3 == T.Theme.Colors.Accent and math.abs(exPanel.AbsolutePosition.X - restX) < 1)

----------------------------------------------------------------------
-- 12. Dragging rows to move objects
----------------------------------------------------------------------
local view = E.View
local function rowEntry(name)
	for _, entry in view.Entries do
		if entry.Index ~= 0 and entry.Row.Visible and view.Rows[entry.Index] and view.Rows[entry.Index].Name == name then
			return entry
		end
	end
	return nil
end
local function rowPoint(name)
	local entry = rowEntry(name)
	assert(entry, "no row " .. name)
	return entry.Row.AbsolutePosition + V2(60, 11)
end
local function dragLabel()
	return H.find(T.Overlay.gui(), "DragLabel")
end
E.clearSearch()
local crates = make("Folder", "Crates", workspace)
local crateA = H.part("CrateA", workspace)
local crateB = H.part("CrateB", workspace)
H.advance(0.3)
E.select({ crateA })
H.advance(0.2)
local fromPoint = rowPoint("CrateA")
H.press(H.toScreen(fromPoint))
H.moveTo(H.toScreen(fromPoint + V2(3, 0)))
check("a small move isn't a drag", not view:IsDragging())
H.moveTo(H.toScreen(rowPoint("Crates")))
check("moving further starts a drag", view:IsDragging())
check("the row under the mouse lights up", view.DropTarget ~= nil and view.DropTarget.Obj == crates)
local label = dragLabel()
check("a label follows the mouse", label ~= nil and label:FindFirstChild("Text").Text:find("CrateA", 1, true) and label:FindFirstChild("Text").Text:find("Crates", 1, true), label and label:FindFirstChild("Text").Text)
H.release()
H.advance(0.3)
check("dropping moves it into that row", crateA.Parent == crates)
check("the moved object stays selected", E.getSelection()[1] == crateA)
check("the label is gone", dragLabel() == nil and view.DropTarget == nil)
check("the move is reported", has(1, "moved CrateA into"), lines(1))

-- can't drop a folder into its own child
E.select({ crateA })
H.advance(0.2)
E.select({ crates })
H.advance(0.2)
H.press(H.toScreen(rowPoint("Crates")))
H.moveTo(H.toScreen(rowPoint("CrateA")))
check("no drop into its own descendant", view:IsDragging() and view.DropTarget == nil)
label = dragLabel()
check("the label says why", label and label:FindFirstChild("Text").Text:find("descendant", 1, true), label and label:FindFirstChild("Text").Text)
H.release()
H.advance(0.2)
check("nothing moved", crates.Parent == workspace)

-- Escape cancels
E.select({ crateB })
H.advance(0.2)
H.press(H.toScreen(rowPoint("CrateB")))
H.moveTo(H.toScreen(rowPoint("Crates")))
H.key("Escape")
H.advance(0.1)
check("Escape cancels the drag", not view:IsDragging() and dragLabel() == nil)
H.release()
H.advance(0.2)
check("…and nothing moves", crateB.Parent == workspace)

-- several at once
E.select({ crateB, base })
H.advance(0.2)
H.press(H.toScreen(rowPoint("CrateB")))
check("pressing a selected row keeps the selection", #E.getSelection() == 2)
H.moveTo(H.toScreen(rowPoint("Map")))
H.release()
H.advance(0.3)
check("dragging several moves them all", crateB.Parent == map and base.Parent == map)
check("both stay selected", #E.getSelection() == 2)
E.moveInto({ base }, workspace)
H.advance(0.2)
check("Explorer.moveInto moves back", base.Parent == workspace)
E.select({ crateB, base })
H.advance(0.2)
H.clickObject(rowEntry("CrateB").Row)
H.advance(0.2)
check("a plain click on a selected row selects just it", #E.getSelection() == 1 and E.getSelection()[1] == crateB)
at = run("/move game.Workspace.Crates")
check("/move moves the selection", crateB.Parent == crates, lines(at))
at = run("/move $sel")
check("/move into itself says why", has(at, "itself"), lines(at))

----------------------------------------------------------------------
-- 13. Object › Insert
----------------------------------------------------------------------
local Insert = E.Insert
local classes = Insert.classes()
check("insert knows hundreds of classes", #classes > 200, #classes)
check("…that Instance.new can make", table.find(classes, "Part") and table.find(classes, "ScreenGui") and not table.find(classes, "Workspace") and not table.find(classes, "BasePart"))
local groups = Insert.groups()
local groupIds = {}
for _, g in groups do
	table.insert(groupIds, g.Id)
end
check("classes are grouped", table.find(groupIds, "parts") and table.find(groupIds, "scripts") and table.find(groupIds, "gui") and table.find(groupIds, "other"), table.concat(groupIds, ","))
local split = Insert.split(classes, 40)
check("long lists split into letter ranges", #split > 3 and split[1].Title:sub(1, 1) == "A")

local ExplorerMenu = T.import("base/explorer/menu")
local Menus = T.import("base/ui/menus")
E.select({ map })
H.advance(0.2)
local mapNode = E.Tree:NodeFor(map)
local ictx = ExplorerMenu.context(E, { mapNode }, mapNode, V2(200, 200))
local objectItems = Menus.build("explorer.object", ictx)
local insertItem = objectItems[1]
check("Object menu starts with Insert", insertItem.Text == "Insert" and insertItem.Items ~= nil and not insertItem.Disabled)
check("it says where", insertItem.Shortcut == "into Map", insertItem.Shortcut)
local sub = insertItem.Items()
local texts = {}
for _, item in sub do
	table.insert(texts, item.Text or (item.Header and ("#" .. item.Header)) or "-")
end
local joined = table.concat(texts, "|")
check("Insert has search, Common and groups", joined:find("Search all classes", 1, true) and joined:find("#Common", 1, true) and joined:find("Parts", 1, true) and joined:find("Scripts", 1, true), joined)
local partItem
for _, item in sub do
	if item.Text == "Part" then
		partItem = item
		break
	end
end
local before = #map:GetChildren()
partItem.Callback(partItem)
H.advance(0.2)
local made = map:FindFirstChildOfClass("Part")
check("choosing a class inserts it into the right-clicked object", #map:GetChildren() == before + 1 and made ~= nil)
check("the new object is selected", E.getSelection()[1] ~= nil and E.getSelection()[1].Parent == map and E.getSelection()[1].ClassName == "Part")
check("insert is reported", has(1, "inserted Part into"), lines(1))
local scriptsItem
for _, item in sub do
	if item.Text == "Scripts" then
		scriptsItem = item
	end
end
local scriptEntries = scriptsItem.Items()
local names = {}
for _, item in scriptEntries do
	table.insert(names, item.Text)
end
check("a group lists its classes", table.find(names, "Script") and table.find(names, "LocalScript") and table.find(names, "ModuleScript"), table.concat(names, ","))
local otherItem
for _, item in sub do
	if item.Text == "Other" then
		otherItem = item
	end
end
local searchPopup = ExplorerMenu.insertSearch(ictx, V2(200, 200))
H.advance(0.1)
local searchBox = searchPopup and H.find(searchPopup.Frame or T.Overlay.gui(), "Box")
check("Search all classes opens with an empty search box", searchBox ~= nil and searchBox.Text == "", searchBox and searchBox.Text)
check("…showing its Search… hint", searchBox ~= nil and searchBox.PlaceholderText:find("Search", 1, true) ~= nil)
if searchPopup and searchPopup.Close then
	searchPopup:Close()
end
H.advance(0.1)
-- no text object anywhere starts with Roblox's default text
local leftovers = {}
for _, gui in { T.Window.Gui, T.Overlay.gui(), T.CommandBar.gui() } do
	for _, d in gui:GetDescendants() do
		if (d:IsA("TextBox") and d.Text == "TextBox") or (d:IsA("TextLabel") and d.Text == "Label") or (d:IsA("TextButton") and d.Text == "Button") then
			table.insert(leftovers, d:GetFullName())
		end
	end
end
check("no leftover default text (TextBox / Label / Button)", #leftovers == 0, leftovers[1])
local ranges = otherItem and otherItem.Items() or {}
check("a long group splits into letter ranges", #ranges > 1 and ranges[1].Items ~= nil, #ranges)
E.select({ map, crates })
H.advance(0.2)
E.insert("Folder", E.getSelection())
H.advance(0.2)
check("inserting with several selected puts one in each", map:FindFirstChildOfClass("Folder") ~= nil and crates:FindFirstChildOfClass("Folder") ~= nil)
at = run("/insert Configuration game.Workspace.Map")
check("/insert", map:FindFirstChildOfClass("Configuration") ~= nil, lines(at))
at = run("/insert Workspace game.Workspace.Map")
check("/insert refuses what can't be made", has(at, "can't be made"), lines(at))
Insert.addGroup({ Id = "mine", Title = "Mine", Classes = { "Part", "Folder" }, Order = 1 }, "myplugin")
local first = Insert.groups()[1]
check("plugins add groups", first.Id == "mine" and #first.Classes == 2)
Insert.removeOwner("myplugin")
check("…and remove them", Insert.groups()[1].Id ~= "mine")

----------------------------------------------------------------------
-- 13b. /undo
----------------------------------------------------------------------
local Undo = T.Undo
Undo.clear()
local Props = T.import("base/explorer/properties")
local Api = T.import("base/explorer/api")
local box1 = H.part("UndoBox", workspace)
H.advance(0.2)
local transparencyProp = Api.property("Part", "Transparency")
Props.set({ box1 }, transparencyProp, 0.5)
check("a property edit is recorded", Undo.count() == 1 and Undo.peek().Text == "set Transparency on UndoBox", Undo.peek() and Undo.peek().Text)
at = run("/undo")
check("/undo puts the old value back", box1.Transparency == 0 and has(at, "undid set Transparency on UndoBox"), lines(at))
at = run("/undo")
check("/undo with nothing left says so", has(at, "nothing to undo"), lines(at))
-- several steps
Props.set({ box1 }, transparencyProp, 0.2)
E.renameTo(box1, "Renamed")
E.moveInto({ box1 }, map)
at = run("/undo list")
check("/undo list shows the steps newest first", has(at, "3 steps") and lines(at):find("move Renamed into Map", 1, true) ~= nil, lines(at))
at = run("/undo")
check("undo a move puts it back where it was", box1.Parent == workspace, lines(at))
at = run("/undo 2")
check("/undo 2 takes back two steps", box1.Name == "UndoBox" and box1.Transparency == 0, lines(at))
-- insert and delete
local madeFolder = E.insert("Folder", { map })[1]
at = run("/undo")
check("undo an insert removes the new object", madeFolder and madeFolder.Parent == nil, lines(at))
local doomed = H.part("Doomed", workspace)
H.advance(0.2)
E.deleteNodes({ E.Tree:NodeFor(doomed) })
at = run("/undo")
check("/undo brings a deleted object back", doomed.Parent == workspace and has(at, "undid delete Doomed"), lines(at))
-- attributes
Props.setAttribute({ box1 }, "Health", 50)
Props.setAttribute({ box1 }, "Health", 70)
run("/undo")
check("undo an attribute change", box1:GetAttribute("Health") == 50)
run("/undo")
check("…and the first one removes it again", box1:GetAttribute("Health") == nil)
-- variables
run("/set undoA 1")
run("/set undoA 2")
run("/undo")
check("undo a variable change", T.Variables.get("undoA") == 1)
run("/clearvars")
check("cleared", T.Variables.get("undoA") == nil)
run("/undo")
check("undo /clearvars brings them back", T.Variables.get("undoA") == 1)
run("/rename undoA undoB")
run("/undo")
check("undo /rename is one step", T.Variables.get("undoA") == 1 and T.Variables.get("undoB") == nil)
-- a popup is one step
local colorProp = Api.property("Part", "Color")
local oldColor = box1.Color
local key = Props.undoKey("prop", "Color", { box1 })
Undo.beginGroup(key)
Props.set({ box1 }, colorProp, E_.Color3.new(1, 0, 0))
Props.set({ box1 }, colorProp, E_.Color3.new(0, 1, 0))
Props.set({ box1 }, colorProp, E_.Color3.new(0, 0, 1))
Undo.endGroup(key)
local before = Undo.count()
run("/undo")
check("edits in one popup undo together", box1.Color == oldColor and Undo.count() == before - 1, tostring(box1.Color))
-- Ctrl+Z in the tree
Props.set({ box1 }, transparencyProp, 0.9)
E.select({ box1 })
H.advance(0.2)
E.View.Active = true
H.focused = nil
H.keys.LeftControl = true
H.key("Z")
H.keys.LeftControl = nil
H.advance(0.1)
check("Ctrl+Z in the explorer undoes too", box1.Transparency == 0)
-- the loaded variable isn't an undo step
Undo.clear()
T.Variables.set("loaded", box1, { Source = "explorer", Undo = false })
check("Load's $loaded isn't recorded", Undo.count() == 0)
box1:Destroy()

----------------------------------------------------------------------
-- 14. Tab order, Accept label, a clean slate at every start
----------------------------------------------------------------------
local order = {}
for _, tab in T.Registry.allTabs() do
	if tab.Builtin then
		table.insert(order, tab.Id)
	end
end
check("default tabs: console, plugins, documentation", table.concat(order, ",") == "console,plugins,documentation", table.concat(order, ","))
local ColorPicker = T.import("base/ui/components/colorpicker")
local cp = ColorPicker.open({ AnchorPos = V2(100, 100), AnchorSize = V2(10, 10), Value = E_.Color3.new(1, 0, 0) })
H.advance(0.1)
check("the button says Accept", cp.Confirm.Accept.Instance:FindFirstChildWhichIsA("TextLabel", true) and cp.Confirm.Accept.Instance:FindFirstChildWhichIsA("TextLabel", true).Text == "Accept" or cp.Confirm.Accept.Instance.Text == "Accept")
cp:Close()
H.advance(0.1)

local Settings = T.Settings
T.Tabs:Select("documentation")
H.advance(0.2)
E.setOpen(false, false)
Settings.set("PropertiesCollapsed", { "Appearance" })
Settings.set("ExplorerFilter", { Only = { "parts" } })
Settings.set("PropertyDecimals", 2)
Settings.flush()
local file = H.FILES["Tungsten/base/settings.json"] or ""
check("open tab, explorer state, folds and filter are not saved", not file:find("LastTab", 1, true) and not file:find("ExplorerOpen", 1, true) and not file:find("PropertiesCollapsed", 1, true) and not file:find("ExplorerFilter", 1, true), file)
check("preferences are saved", file:find('"PropertyDecimals":2', 1, true) ~= nil, file)
check("session keys still work while running", Settings.get("LastTab") == "documentation" and Settings.get("ExplorerOpen") == false)
-- an older file that saved them is ignored without complaint
H.FILES["Tungsten/base/settings.json"] = file:sub(1, -2) .. ',"LastTab":"documentation","ExplorerOpen":false}'
local okRun = H.run("Tungsten/Tungsten.luau")
H.advance(1)
local T3 = H.genv.Tungsten.Context
check("re-run ok", okRun and T3 ~= nil)
check("always starts on the Console", T3.Tabs.Selected == "console", T3.Tabs.Selected)
check("explorer starts open", T3.Explorer.isOpen())
check("no filter, nothing folded", next(T3.Settings.get("ExplorerFilter")) == nil and #T3.Settings.get("PropertiesCollapsed") == 0)
check("preferences kept", T3.Settings.get("PropertyDecimals") == 2)
check("old session keys aren't reported as problems", #T3.Settings.Problems == 0, T3.Settings.Problems[1])
T3.Settings.set("PropertyDecimals", 3)
T3.Settings.flush()

check("no runtime errors", #H.ERRORS == 0, H.ERRORS[1])
print(("stage4c: %d passed, %d failed, %d runtime errors"):format(passed, failed, #H.ERRORS))
