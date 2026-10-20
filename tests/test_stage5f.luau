-- Stage 5 Round B, part 2: a plugin's page in the Plugins tab: header with
-- the Enabled switch, state and pending note, Open tab · Reload · Docs ·
-- Copy id, what it adds (from the registries), its settings and Reset,
-- its problems (Details shows the trace), faults and warnings, and the
-- page following the host live.
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
for _, folder in { "Good", "Crash", "Faulty", "Broken", "NoId", "Scanner" } do
	local prefix = "fixtures/plugins/" .. folder .. "/"
	for path, content in H.FILES do
		if path:sub(1, #prefix) == prefix then
			H.FILES[ROOT .. folder .. "/" .. path:sub(#prefix + 1)] = content
		end
	end
end
H.FILES["Tungsten/base/plugins.json"] = '{"On":["good","crash","faulty"]}'

local ok, err = H.run("Tungsten/Tungsten.luau")
check("loader runs", ok, err)
H.advance(5)
local T = genv.Tungsten.Context
local M = T.Manager
local Plugins = T.Plugins
local C = T.Console

T.Tabs:Select("plugins")
H.advance(0.5)
local page = T.Tabs.Pages.plugins
local panel = H.find(page, "Panel")

local function clickText(root, text)
	for _, d in root:GetDescendants() do
		if (d.ClassName == "TextLabel" or d.ClassName == "TextButton") and d.Text == text and H.shown(d) then
			H.clickObject(d)
			return true
		end
	end
	return false
end

----------------------------------------------------------------------
-- 1. a running plugin
----------------------------------------------------------------------
do
	M.select("good")
	H.advance(0.2)
	check("header: name and byline", H.find(panel, "Title").Text == "Good" and H.find(panel, "Byline").Text == "v1.2 · by tests", H.find(panel, "Byline").Text)
	local enabled = M.Controls.__enabled
	check("header: the Enabled switch is on", enabled and enabled.Widget.Value == true)
	check("state: on, with its load time", H.find(panel, "State").Text == "on" and H.find(panel, "LoadTime") ~= nil)
	check("description", H.find(panel, "Description").Text == "does everything right")
	check("actions: Open tab · Reload · Docs · Copy id", H.find(panel, "OpenTab") and H.find(panel, "Reload") and H.find(panel, "Docs") and H.find(panel, "CopyId"))
	check("adds: counted from the registries", H.find(panel, "Add_tabs") and H.find(panel, "Add_tabs").Text == "1 tab"
		and H.find(panel, "Add_commands").Text == "1 command" and H.find(panel, "Add_functions").Text == "1 explorer function"
		and H.find(panel, "Add_docs").Text == "1 docs topic" and H.find(panel, "Add_variables").Text == "1 variable")
	check("settings: a row per setting and Reset", H.find(panel, "Pref_speed") ~= nil and H.find(panel, "Pref___reset") ~= nil)
	check("problems: none", H.find(panel, "NoProblems") ~= nil)
	check("footer: id and folder", H.find(panel, "Footer").Text == "id good · folder plugins/Good")

	-- the Enabled switch: on / off from the next start
	enabled.Widget:Set(false)
	H.advance(0.2)
	check("switching off: off at the next start, still running", not Plugins.wanted("good") and Plugins.get("good").State == "on")
	check("…the page shows it", H.find(panel, "Pending") and H.find(panel, "Pending").Text == "off at next start", H.find(panel, "Pending") and H.find(panel, "Pending").Text)
	M.Controls.__enabled.Widget:Set(true)
	H.advance(0.2)
	check("switching back on clears it", Plugins.wanted("good") and H.find(panel, "Pending") == nil)

	-- settings and Reset
	local store = Plugins.get("good").Api.settings
	M.Controls.speed.Update(30)
	store.set("speed", 30)
	H.advance(0.1)
	check("a setting changed by the plugin shows on its page", M.Controls.speed.Widget.Value == 30)
	clickText(H.find(panel, "Pref___reset"), "Reset")
	H.advance(0.2)
	check("Reset puts its settings back", store.get("speed") == 16, store.get("speed"))

	-- buttons
	clickText(H.find(panel, "CopyId"), "Copy id")
	check("Copy id", H.CLIPBOARD == "good")
	clickText(H.find(panel, "Docs"), "Docs")
	H.advance(0.3)
	check("Docs opens its topic", T.Tabs.Selected == "documentation")
	T.Tabs:Select("plugins")
	H.advance(0.3)
	M.select("good")
	clickText(H.find(panel, "OpenTab"), "Open tab")
	H.advance(0.3)
	check("Open tab opens it", T.Tabs.Selected == "good")
	T.Tabs:Select("plugins")
	H.advance(0.3)
end

----------------------------------------------------------------------
-- 2. one that failed, and Details
----------------------------------------------------------------------
do
	M.select("crash")
	H.advance(0.2)
	check("failed: its state", H.find(panel, "State").Text == "failed")
	check("failed: the Load error", H.find(panel, "Problem") and H.find(panel, "Problem").Text:find("boom in Load", 1, true) ~= nil)
	check("failed: adds nothing while it isn't running", H.find(panel, "AddsNone") ~= nil)
	check("failed: Open tab is greyed (no tab)", H.find(panel, "OpenTab") ~= nil)
	local before = #C.Lines
	clickText(H.find(panel, "ProblemRow"), "Details")
	H.advance(0.2)
	local out = {}
	for index = before + 1, #C.Lines do
		table.insert(out, C.Lines[index].Plain)
	end
	local text = table.concat(out, "\n")
	check("Details: the error and its trace in the console", text:find("boom in Load", 1, true) ~= nil and #out >= 2 and T.Tabs.Selected == "console", text)
	T.Tabs:Select("plugins")
	H.advance(0.3)

	-- Reload from the page after fixing it
	H.FILES[ROOT .. "Crash/plugin.luau"] = H.FILES[ROOT .. "Crash/plugin.luau"]:gsub('error%("boom in Load"%)', "")
	M.select("crash")
	clickText(H.find(panel, "Reload"), "Reload")
	H.advance(0.5)
	check("Reload: on now, and the page follows", Plugins.get("crash").State == "on" and H.find(panel, "State").Text == "on" and M.Selected == "crash")
	check("…adds now lists its command", H.find(panel, "Add_commands") and H.find(panel, "Add_commands").Text == "1 command")
end

----------------------------------------------------------------------
-- 3. faults, a problem without an id, a warning, an off plugin
----------------------------------------------------------------------
do
	C.run("/faultcmd")
	H.advance(0.2)
	M.select("faulty")
	H.advance(0.2)
	check("faults: the count and the last one", H.find(panel, "Faults") and H.find(panel, "Faults").Text:find(":faulty.faultcmd failed", 1, true) ~= nil, H.find(panel, "Faults") and H.find(panel, "Faults").Text)

	M.select("@Broken")
	H.advance(0.2)
	check("a problem without an id: no Enabled switch", M.Controls.__enabled == nil and H.find(panel, "Enabled") == nil)
	check("…its problem", H.find(panel, "Problem").Text:find("doesn't compile", 1, true) ~= nil)
	check("…footer names the folder", H.find(panel, "Footer").Text == "id — · folder plugins/Broken")

	M.select("noid")
	H.advance(0.2)
	check("a warning shows (no Id)", H.find(panel, "Warning1") and H.find(panel, "Warning1").Text:find("set Id", 1, true) ~= nil)
	check("off: the switch is off", M.Controls.__enabled.Widget.Value == false)
	M.Controls.__enabled.Widget:Set(true)
	H.advance(0.2)
	check("switching on an off plugin: on at the next start, not now", Plugins.wanted("noid") and Plugins.get("noid").State == "off" and H.find(panel, "Pending").Text == "on at next start")
	M.Controls.__enabled.Widget:Set(false)
	H.advance(0.2)
end

----------------------------------------------------------------------
-- 4. the page follows the host; multi-selection survives a refresh
----------------------------------------------------------------------
do
	M.select("good")
	M.click("faulty", true)
	H.advance(0.1)
	C.run("/plugin off faulty")
	H.advance(0.2)
	check("a host change refreshes the shown page", H.find(panel, "Pending") and H.find(panel, "Pending").Text == "off at next start")
	check("…and keeps the multi-selection", #M.selected() == 2)
	C.run("/plugin on faulty")
	H.advance(0.2)
end

check("no runtime errors", #H.ERRORS == 0, H.ERRORS[1])
print(("stage5f: %d passed, %d failed, %d runtime errors"):format(passed, failed, #H.ERRORS))
