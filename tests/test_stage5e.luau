-- Stage 5 Round B, part 1: the Plugins tab lists the host's plugins:
-- cards with a state chip and a line, live updates, search, multi-select,
-- the plugins.entry right-click menu, the failed-count badge and the
-- empty state with Rescan.
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
H.ABS_SHIFT = SHIFT or 0
local genv = H.genv

local ROOT = "Tungsten/plugins/"
local function install(...)
	for _, folder in { ... } do
		local prefix = "fixtures/plugins/" .. folder .. "/"
		for path, content in H.FILES do
			if path:sub(1, #prefix) == prefix then
				H.FILES[ROOT .. folder .. "/" .. path:sub(#prefix + 1)] = content
			end
		end
	end
end
local function uninstall(folder)
	for path in table.clone(H.FILES) do
		if path:sub(1, #ROOT + #folder + 1) == ROOT .. folder .. "/" then
			H.FILES[path] = nil
		end
	end
end

install("Good", "Crash", "Scanner", "Needy", "Broken", "NoId", "SlowOk")
H.FILES["Tungsten/base/plugins.json"] = '{"On":["good","crash"]}'

local ok, err = H.run("Tungsten/Tungsten.luau")
check("loader runs", ok, err)
H.advance(5)
local T = genv.Tungsten.Context
local M = T.Manager
local Plugins = T.Plugins
local C = T.Console

local function itemsFor(ids)
	local out = {}
	for _, item in T.Menus.build("plugins.entry", { Ids = ids, Manager = M }) do
		if item.Text then
			out[item.Text] = item
		end
	end
	return out
end
local function lastLines(count)
	local out = {}
	for index = math.max(1, #C.Lines - count + 1), #C.Lines do
		table.insert(out, C.Lines[index].Plain)
	end
	return table.concat(out, "\n")
end

----------------------------------------------------------------------
-- 1. the badge works before the tab is ever opened
----------------------------------------------------------------------
check("the Plugins tab's badge counts plugins that didn't start", T.Registry.getTab("plugins").Badge == 1, T.Registry.getTab("plugins").Badge)

T.Tabs:Select("plugins")
H.advance(0.5)
local page = T.Tabs.Pages.plugins

----------------------------------------------------------------------
-- 2. cards
----------------------------------------------------------------------
do
	check("tungsten stays first", H.find(page, "Entry_tungsten") ~= nil and M.Entries.tungsten.Frame.LayoutOrder < M.Entries.good.Frame.LayoutOrder)
	local good = M.Entries.good
	check("a card per plugin", good ~= nil and M.Entries.crash ~= nil and M.Entries.scanner ~= nil and M.Entries.needy ~= nil and M.Entries.noid ~= nil and M.Entries.slowok ~= nil)
	check("a plugin without an id is listed by its folder", M.Entries["@Broken"] ~= nil)
	check("state chip: on", good.Chip and good.Chip.Text == "on")
	check("state chip: failed", M.Entries.crash.Chip.Text == "failed")
	check("state chip: problem", M.Entries["@Broken"].Chip.Text == "problem")
	check("state chip: off", M.Entries.scanner.Chip.Text == "off")
	check("line: version and description", H.find(good.Frame, "Note").Text == "v1.2 · does everything right", H.find(good.Frame, "Note").Text)
	check("line: the problem for one that didn't start", H.find(M.Entries.crash.Frame, "Note").Text:find("boom in Load", 1, true) ~= nil)
	check("prime plugins first among plugins", M.Entries.scanner.Frame.LayoutOrder < M.Entries.good.Frame.LayoutOrder)
	check("the empty note hides", H.find(page, "Empty").Visible == false)
end

----------------------------------------------------------------------
-- 3. live updates
----------------------------------------------------------------------
do
	C.run("/plugin on scanner")
	H.advance(0.2)
	check("turning one on shows 'on at next start' right away", H.find(M.Entries.scanner.Frame, "Note").Text == "on at next start", H.find(M.Entries.scanner.Frame, "Note").Text)
	check("…its chip still says off", M.Entries.scanner.Chip.Text == "off")
	C.run("/plugin off scanner")
	H.advance(0.2)
	check("…and back", H.find(M.Entries.scanner.Frame, "Note").Text == "")
	H.FILES[ROOT .. "Late/plugin.luau"] = "return { Id = 'late', Name = 'Late', Description = 'came later' }"
	C.run("/plugins rescan")
	H.advance(0.2)
	check("a rescanned folder gets a card", M.Entries.late ~= nil)
	uninstall("Late")
	C.run("/plugins rescan")
	H.advance(0.2)
	check("a folder that's gone loses its card", M.Entries.late == nil and H.find(page, "Entry_late") == nil)
end

----------------------------------------------------------------------
-- 4. search
----------------------------------------------------------------------
do
	check("the search box shows with more than a few plugins", M.Search.Instance.Visible)
	M.Search:SetText("scan")
	M.Query = "scan"
	M.sync()
	H.advance(0.1)
	check("search keeps matching cards and tungsten", M.Entries.scanner.Frame.Visible and M.Entries.tungsten.Frame.Visible)
	check("…and hides the rest", not M.Entries.good.Frame.Visible and not M.Entries.crash.Frame.Visible)
	M.Query = "everything right"
	M.sync()
	check("search finds a description", M.Entries.good.Frame.Visible and not M.Entries.scanner.Frame.Visible)
	M.Search:SetText("")
	M.Query = ""
	M.sync()
	check("clearing it shows every card", M.Entries.good.Frame.Visible and M.Entries.scanner.Frame.Visible)
end

----------------------------------------------------------------------
-- 5. multi-select
----------------------------------------------------------------------
do
	M.select("good")
	check("a click selects one", #M.selected() == 1 and M.selected()[1] == "good")
	M.click("crash", true)
	local sel = M.selected()
	check("Ctrl+click adds one", #sel == 2 and table.find(sel, "good") and table.find(sel, "crash"))
	check("…the page shows the last clicked", M.Selected == "crash")
	M.click("good", true)
	check("Ctrl+click again takes it out", #M.selected() == 1 and M.selected()[1] == "crash")
	M.select("scanner")
	M.click("noid", false, true)
	local order = {}
	for _, id in M.selected() do
		table.insert(order, id)
	end
	check("Shift+click selects the range in list order", #order >= 3 and order[1] == "scanner" and order[#order] == "noid", table.concat(order, ","))
	M.click("tungsten", true)
	check("tungsten is never part of a multi-selection", M.Selected == "tungsten" and #M.selected() == 0)
	M.select("good")
	H.clickObject(M.Entries.crash.Frame)
	check("clicking a card (no keys) selects just it", #M.selected() == 1 and M.selected()[1] == "crash")
end

----------------------------------------------------------------------
-- 6. the right-click menu
----------------------------------------------------------------------
do
	local items = itemsFor({ "good", "scanner" })
	check("menu: Turn on, Turn off, Reload, Open its tab, Documentation, Copy id, Reset its settings…",
		items["Turn on"] and items["Turn off"] and items["Reload"] and items["Open its tab"] and items["Documentation"] and items["Copy id"] and items["Reset its settings…"])
	check("Open its tab / Documentation need exactly one plugin", items["Open its tab"].Disabled and items["Documentation"].Disabled)
	items = itemsFor({ "good" })
	check("…with one that has them, they work", not items["Open its tab"].Disabled and not items["Documentation"].Disabled)
	check("Turn on is greyed when it's already on for the next start", items["Turn on"].Disabled and not items["Turn off"].Disabled)

	items = itemsFor({ "scanner", "noid" })
	items["Turn on"].Callback()
	H.advance(0.2)
	check("Turn on (two at once): both on for the next start", Plugins.wanted("scanner") and Plugins.wanted("noid"))
	check("…and the console says so", lastLines(2):find("scanner, noid will be on at the next start", 1, true) ~= nil, lastLines(2))
	itemsFor({ "scanner", "noid" })["Turn off"].Callback()
	H.advance(0.2)
	check("Turn off (two at once)", not Plugins.wanted("scanner") and not Plugins.wanted("noid"))

	itemsFor({ "good" })["Copy id"].Callback()
	check("Copy id", H.CLIPBOARD == "good", H.CLIPBOARD)

	itemsFor({ "good" })["Documentation"].Callback()
	H.advance(0.3)
	check("Documentation opens its topic in the Documentation tab", T.Tabs.Selected == "documentation", T.Tabs.Selected)
	itemsFor({ "good" })["Open its tab"].Callback()
	H.advance(0.3)
	check("Open its tab", T.Tabs.Selected == "good")
	T.Tabs:Select("plugins")
	H.advance(0.3)

	H.FILES[ROOT .. "Crash/plugin.luau"] = H.FILES[ROOT .. "Crash/plugin.luau"]:gsub('error%("boom in Load"%)', "")
	itemsFor({ "crash" })["Reload"].Callback()
	H.advance(0.5)
	check("Reload: a fixed plugin is on again", Plugins.get("crash").State == "on" and M.Entries.crash.Chip.Text == "on")
	check("…and the badge is clear", T.Registry.getTab("plugins").Badge == 0)

	local store = Plugins.get("good").Api.settings
	store.set("speed", 70)
	itemsFor({ "good" })["Reset its settings…"].Callback()
	H.advance(0.3)
	local dialog = T.Overlay.top()
	local resetButton
	for _, d in dialog.Frame:GetDescendants() do
		if (d.ClassName == "TextButton" or d.ClassName == "TextLabel") and d.Text == "Reset" then
			resetButton = d
		end
	end
	check("Reset its settings asks first", resetButton ~= nil and store.get("speed") == 70)
	if resetButton then
		H.clickObject(resetButton)
		H.advance(0.3)
	end
	check("…then puts them back to the defaults", store.get("speed") == 16, store.get("speed"))
	check("an off plugin with settings can be reset too (no running needed)", not itemsFor({ "scanner" })["Reset its settings…"] or itemsFor({ "scanner" })["Reset its settings…"].Disabled == true)

	local tungstenItems = T.Menus.build("plugins.entry", { Ids = {}, Manager = M })
	check("right-click on tungsten: nothing to do", #tungstenItems == 1 and tungstenItems[1].Disabled)
	M.openMenu("needy")
	H.advance(0.2)
	check("right-click on a card that isn't selected selects it", #M.selected() == 1 and M.selected()[1] == "needy" and T.Overlay.isOpen())
	T.Overlay.closeAll()
end

----------------------------------------------------------------------
-- 7. empty state and Rescan
----------------------------------------------------------------------
do
	for _, folder in { "Good", "Crash", "Scanner", "Needy", "Broken", "NoId", "SlowOk" } do
		uninstall(folder)
	end
	C.run("/plugins rescan")
	H.advance(0.3)
	-- running plugins stay until the next start; the off ones are gone
	check("Rescan drops the folders that are gone (off ones)", M.Entries.scanner == nil and M.Entries.noid == nil and M.Entries["@Broken"] == nil)
	check("…running ones stay until the next start", M.Entries.good ~= nil)
	check("the search box hides with few plugins", not M.Search.Instance.Visible)

	-- with nothing left at all, the empty state shows Rescan and the guide
	local co = coroutine.create(function()
		Plugins.stop()
		Plugins.start()
	end)
	coroutine.resume(co)
	H.advance(0.3)
	M.sync()
	H.advance(0.2)
	local empty = H.find(page, "Empty")
	check("no plugins: the empty state shows", empty and empty.Visible)
	check("…with Rescan and the guide", H.find(empty, "Rescan") ~= nil and H.find(empty, "Guide") ~= nil)
	local guideLabel
	for _, d in H.find(empty, "Guide"):GetDescendants() do
		if d.ClassName == "TextLabel" and d.Text == "How plugins work" then
			guideLabel = d
		end
	end
	H.clickObject(guideLabel or H.find(empty, "Guide"))
	H.advance(0.3)
	check("the guide opens the Plugins topic", T.Tabs.Selected == "documentation", T.Tabs.Selected)
	T.Tabs:Select("plugins")
	H.advance(0.3)
	H.FILES[ROOT .. "Late/plugin.luau"] = "return { Id = 'late', Name = 'Late' }"
	local rescanLabel
	for _, d in H.find(empty, "Rescan"):GetDescendants() do
		if d.ClassName == "TextLabel" and d.Text == "Rescan" then
			rescanLabel = d
		end
	end
	H.clickObject(rescanLabel or H.find(empty, "Rescan"))
	H.advance(0.3)
	check("Rescan finds a new folder", M.Entries.late ~= nil and not empty.Visible)
end

check("no runtime errors", #H.ERRORS == 0, H.ERRORS[1])
print(("stage5e: %d passed, %d failed, %d runtime errors"):format(passed, failed, #H.ERRORS))
