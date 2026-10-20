-- Plugins stage, round 1 part 1.3: the script viewer's Source sub-tab
-- (decompiled in a thread, only when looked at, once per script, errors
-- in place, a stale result dropped, Copy) and Contents sub-tab (a loaded
-- table, what a required ModuleScript returns; Tree / List).
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
H.keepPrimes()
H.FILES["Tungsten/base/plugins.json"] = '{"On":["scriptviewer"]}'

local folder = E_.Instance.new("Folder")
folder.Name = "Game"
folder.Parent = E_.workspace
local function script(class, name, source)
	local s = E_.Instance.new(class)
	s.Name = name
	s._props.Source = source
	s.Parent = folder
	return s
end
local doorScript = script("LocalScript", "DoorScript", "local door = script.Parent\nprint(door)\nreturn door")
local otherScript = script("LocalScript", "Other", "print(\"other\")")
local broken = script("LocalScript", "Broken", nil)
local config = script("ModuleScript", "Config", "return { Speed = 16 }")
local numberModule = script("ModuleScript", "Number", "return 5")
local unrequired = script("ModuleScript", "Later", "return {}")
local function main() end
H.FN[main] = { Constants = {} }
H.SCRIPT_CLOSURES = { [doorScript] = main, [otherScript] = main, [broken] = main, [config] = main, [numberModule] = main, [unrequired] = main }
H.LOADED = { config, numberModule }
H.MODULE_VALUES = { [config] = { Speed = 16, Name = "door", Parts = { "a", "b" } }, [numberModule] = 5 }

local ok, err = H.run("Tungsten/Tungsten.luau")
check("loader runs", ok, err)
H.advance(5)
local T = genv.Tungsten.Context
local Plugins, Loaded, C = T.Plugins, T.Loaded, T.Console
local record = Plugins.get("scriptviewer")
check("the script viewer is on", record and record.State == "on")
local exports = record.Exports
local api = record.Api

T.Tabs:Select("scriptviewer")
H.advance(0.4)
local view = exports.view()
local function open(id)
	view:Select(id)
	H.advance(0.3)
	return view.Panels[id]
end
local function badge(id)
	local pill = H.find(view.Tabs.Instance, "Tab_" .. id)
	local b = pill and H.find(pill, "Badge")
	return if b and b.Visible then H.find(b, "Text").Text else nil
end
local function keys(panel)
	local out = {}
	for _, node in panel.List:GetItems() do
		table.insert(out, node.Key)
	end
	return table.concat(out, ",")
end

check("six sub-tabs: Source and Contents joined", H.find(view.Tabs.Instance, "Tab_source") ~= nil and H.find(view.Tabs.Instance, "Tab_contents") ~= nil)

----------------------------------------------------------------------
-- 1. Source: only when looked at, in a thread, once per script
----------------------------------------------------------------------
H.DECOMPILED = 0
view:Select("constants") -- Source is first and open: look elsewhere while loading
H.advance(0.2)
T.Explorer.load({ doorScript })
H.advance(0.3)
check("loading a script while another sub-tab is open doesn't decompile it", H.DECOMPILED == 0)
H.DECOMPILE_WAIT = 0.5
local source = open("source")
check("opening Source starts decompiling and says so", source.Status.Visible and source.Status.Text == "Decompiling…" and H.DECOMPILED == 1, source.Status.Text)
check("…Copy waits", source.Copy.Enabled == false)
H.advance(0.8)
check("the decompiled source shows, read-only", not source.Status.Visible and source.Editor:GetText():find("local door = script.Parent", 1, true) ~= nil and source.Editor.ReadOnly == true)
check("…with line numbers and syntax colors (the text editor)", source.Editor.ShowNumbers == true)
view:Select("overview")
H.advance(0.2)
view:Select("source")
H.advance(0.3)
check("coming back doesn't decompile again (once per script)", H.DECOMPILED == 1 and source.Editor:GetText():find("local door", 1, true) ~= nil)
T.Explorer.load({ otherScript })
H.advance(0.1)
T.Explorer.load({ doorScript })
H.advance(1.2)
check("back to an earlier script: from memory", H.DECOMPILED == 2 and source.Editor:GetText():find("local door", 1, true) ~= nil, H.DECOMPILED)
-- Copy
local at = #C.Lines + 1
check("Copy copies the whole source", view:CopySource() and H.CLIPBOARD == doorScript._props.Source)
check("…and says so", C.Lines[#C.Lines].Plain:find("copied the source of DoorScript (3 lines)", 1, true) ~= nil, C.Lines[#C.Lines].Plain)
-- Decompile again
H.DECOMPILE_WAIT = nil
H.clickObject(source.Again.Instance)
H.advance(0.3)
check("Decompile again does", H.DECOMPILED == 3)

----------------------------------------------------------------------
-- 2. a stale result is dropped; failures show in place
----------------------------------------------------------------------
H.DECOMPILE_WAIT = 0.5
T.Explorer.load({ broken })
H.advance(0.1)
T.Explorer.load({ otherScript })
H.advance(1.5)
check("something loaded while decompiling: only the newest shows", source.Editor:GetText() == "print(\"other\")" and not source.Status.Visible, source.Editor:GetText())
H.DECOMPILE_WAIT = nil
T.Explorer.load({ broken })
H.advance(0.4)
check("a script that won't decompile: the reason, in place", source.Status.Visible and source.Status.Text:find("decompile failed", 1, true) ~= nil and source.Editor.Instance.Visible == false, source.Status.Text)
check("…Copy does nothing then", view:CopySource() == false)
check("…and no runtime error", #H.ERRORS == 0, H.ERRORS[1])

----------------------------------------------------------------------
-- 3. other subjects in Source
----------------------------------------------------------------------
local function onTouched() end
H.FN[onTouched] = {}
Loaded.load(Loaded.target(onTouched, { Origin = doorScript }))
H.advance(0.4)
check("a function from a script: that script's source, and a note", source.Editor:GetText():find("local door", 1, true) ~= nil and source.Info.Text:find("the script this function came from", 1, true) ~= nil, source.Info.Text)
Loaded.load(Loaded.target(onTouched))
H.advance(0.3)
check("a function on its own: says to load its script", source.Status.Text:find("load the script it is in", 1, true) ~= nil, source.Status.Text)
Loaded.load(Loaded.target({ a = 1 }))
H.advance(0.3)
check("a table: no source, and where its entries are", source.Status.Text:find("Contents sub-tab", 1, true) ~= nil)

----------------------------------------------------------------------
-- 4. Table
----------------------------------------------------------------------
Loaded.load(Loaded.target({ speed = 3, [1] = "x", sub = { y = 2 } }, { Label = "cfg" }))
H.advance(0.3)
check("a loaded table: a count on the Table pill", badge("contents") == "3", badge("contents"))
local tbl = open("contents")
check("its entries, numbers first", keys(tbl) == "[1],speed,sub", keys(tbl))
check("…counted", tbl.Info.Text == "3 entries", tbl.Info.Text)
check("first column is Key in Tree view", tbl.List.Columns[1].Title == "Key")
view:Toggle("contents", (function()
	for _, node in tbl.List:GetItems() do
		if node.Key == "sub" then
			return node.Id
		end
	end
	return ""
end)())
H.advance(0.1)
check("a nested table opens", keys(tbl) == "[1],speed,sub,y", keys(tbl))
tbl.Switch:SetValue("List")
H.advance(0.2)
check("List view: paths", api.settings.get("contentsView") == "List" and tbl.List.Columns[1].Title == "Path" and tbl.List:GetItems()[4].Path == "sub.y", tbl.List:GetItems()[4] and tbl.List:GetItems()[4].Path)
tbl.Switch:SetValue("Tree")
H.advance(0.2)
T.Explorer.load({ config })
H.advance(0.3)
check("a required ModuleScript: the table it returns", keys(tbl) == "Name,Parts,Speed" and tbl.Info.Text == "3 entries", keys(tbl))
T.Explorer.load({ numberModule })
H.advance(0.3)
check("a module that returns a number: says so", tbl.Info.Text == "it returns a number, not a table", tbl.Info.Text)
local required = H.REQUIRED or 0
T.Explorer.load({ unrequired })
H.advance(0.3)
check("a module the game hasn't required: not required here, and why", tbl.Info.Text:find("hasn't required it yet", 1, true) ~= nil and (H.REQUIRED or 0) == required, tbl.Info.Text)
local function f() end
H.FN[f] = {}
Loaded.load(Loaded.target(f))
H.advance(0.3)
check("a function: what to load instead", tbl.Info.Text == "load a table, or a ModuleScript the game has required" and badge("contents") == nil)

check("its settings include the Table view", (function()
	for _, item in api.settings.items() do
		if item.Id == "contentsView" then
			return true
		end
	end
	return false
end)())

----------------------------------------------------------------------
-- 5. stopping while decompiling
----------------------------------------------------------------------
H.DECOMPILE_WAIT = 1
T.Explorer.load({ otherScript })
view:Select("overview")
H.advance(0.1)
view:Select("source")
H.advance(0.1)
Plugins._disable(record)
H.advance(1.5)
check("stopping the plugin mid-decompile leaves no errors", #H.ERRORS == 0, H.ERRORS[1])

check("no runtime errors", #H.ERRORS == 0, H.ERRORS[1])
for _, e in H.ERRORS do
	print("ERR: " .. e)
end
print(("p1c: %d passed, %d failed, %d runtime errors"):format(passed, failed, #H.ERRORS))
