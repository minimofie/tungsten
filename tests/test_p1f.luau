-- Plugins stage, round 1 fixes (19 Oct): no Overview, Source first (and
-- decompiled only while the tab is open), a script's upvalues from its
-- running functions (filtergc by its environment), reloading and
-- re-running with the tab open; no fault lines from the plugin anywhere.
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
local doorScript = E_.Instance.new("LocalScript")
doorScript.Name = "DoorScript"
doorScript._props.Source = "local open = false\nlocal function toggle() open = not open end\nreturn toggle"
doorScript.Parent = folder
local config = E_.Instance.new("ModuleScript")
config.Name = "Config"
config._props.Source = "return {}"
config.Parent = folder

local doorEnv = { script = doorScript }
local configEnv = { script = config }
local shared = { speed = 3 }
local function main() end
local function toggle() end
local function onTouched() end
local function noUpvalues() end
local function other() end
H.FN[main] = { Constants = { "open" } }
H.FN[toggle] = { Upvalues = { false, shared }, Env = doorEnv, Info = { name = "toggle" } }
H.FN[onTouched] = { Upvalues = { shared }, Env = doorEnv, Info = { name = "onTouched" } }
H.FN[noUpvalues] = { Env = doorEnv }
H.FN[other] = { Upvalues = { 1 }, Env = configEnv, Info = { name = "get" } }
H.GC = { toggle, onTouched, noUpvalues, other }
H.SCRIPT_CLOSURES = { [doorScript] = main, [config] = main }
H.RUNNING = { doorScript }
H.SENV = { [doorScript] = doorEnv, [config] = configEnv }
H.LOADED = { config }
H.MODULE_VALUES = { [config] = { Speed = 1 } }

local ok, err = H.run("Tungsten/Tungsten.luau")
check("loader runs", ok, err)
H.advance(5)
local T = genv.Tungsten.Context
local Plugins, Loaded, C = T.Plugins, T.Loaded, T.Console
local function exports()
	return Plugins.get("scriptviewer").Exports
end
Plugins.get("scriptviewer").Api.settings.set("showReferences", true) -- References is off by default
local function faultLines()
	local out = {}
	for _, line in C.Lines do
		if line.Plain:find("[x]", 1, true) and line.Plain:find("Script Viewer", 1, true) then
			table.insert(out, line.Plain)
		end
	end
	return table.concat(out, " | ")
end
local function keys(panel)
	local out = {}
	for _, node in panel.List:GetItems() do
		table.insert(out, node.Key)
	end
	return table.concat(out, ",")
end
local function async(fn, ...)
	local args = table.pack(...)
	local done = false
	local co = coroutine.create(function()
		fn(table.unpack(args, 1, args.n))
		done = true
	end)
	assert(coroutine.resume(co))
	local guard = 0
	while not done and guard < 4000 do
		guard += 1
		H.step()
	end
end

----------------------------------------------------------------------
-- 1. Source first; decompiled only while the tab is open
----------------------------------------------------------------------
H.DECOMPILED = 0
T.Explorer.load({ doorScript })
H.advance(0.3)
check("a load while the tab isn't open doesn't decompile", H.DECOMPILED == 0)
T.Tabs:Select("scriptviewer")
H.advance(0.5)
local view = exports().view()
check("Source is the first sub-tab and opens", view.Tabs.Order[1] == "source" and view.Tabs.Selected == "source")
check("no Overview sub-tab", view.Tabs.Entries.overview == nil)
check("opening the tab decompiles what is loaded", H.DECOMPILED == 1 and view.Panels.source.Editor:GetText():find("local open", 1, true) ~= nil, H.DECOMPILED)
check("the kind line: LocalScript · running", view.Kind.Text == "LocalScript · running", view.Kind.Text)
check("no fault lines from building the tab", faultLines() == "", faultLines())
T.Tabs:Select("console")
H.advance(0.3)
T.Explorer.load({ config })
H.advance(0.3)
check("tab closed again: the next load waits", H.DECOMPILED == 1)
T.Tabs:Select("scriptviewer")
H.advance(0.4)
check("…until the tab opens", H.DECOMPILED == 2 and view.Panels.source.Editor:GetText() == "return {}")

----------------------------------------------------------------------
-- 2. a script's upvalues: its running functions
----------------------------------------------------------------------
T.Explorer.load({ doorScript })
H.advance(0.3)
view:Select("upvalues")
H.advance(0.3)
local upvalues = view.Panels.upvalues
check("a running script: its running functions with upvalues, each open, by line", keys(upvalues):find("toggle", 1, true) ~= nil and keys(upvalues):find("onTouched", 1, true) ~= nil, keys(upvalues))
check("…functions without upvalues left out", #upvalues.Roots == 2, #upvalues.Roots)
check("…their upvalues under them", (function()
	for _, node in upvalues.List:GetItems() do
		if node.Kind == "upvalue" and rawequal(node.Value, shared) then
			return true
		end
	end
	return false
end)())
check("…counted: upvalues in functions", upvalues.Info.Text == "3 upvalues · 2 functions", upvalues.Info.Text)
check("…the pill counts the upvalues", H.find(H.find(H.find(view.Tabs.Instance, "Tab_upvalues"), "Badge"), "Text").Text == "3")
check("…another script's functions aren't in it", keys(upvalues):find("get", 1, true) == nil)
local heading = upvalues.Roots[1]
view:Toggle("upvalues", heading.Id)
H.advance(0.1)
check("a function heading closes", #upvalues.List:GetItems() < 5, #upvalues.List:GetItems())
view:Toggle("upvalues", heading.Id)
H.advance(0.1)
upvalues.Switch:SetValue("Table")
H.advance(0.2)
check("Table view: upvalues by function", upvalues.Text:GetText():find("toggle", 1, true) ~= nil and upvalues.Text:GetText():find("speed = 3", 1, true) ~= nil, upvalues.Text:GetText())
upvalues.Switch:SetValue("Tree")
H.advance(0.2)
check("Tree view: the same functions", #upvalues.Roots == 2 and keys(upvalues):find("toggle", 1, true) ~= nil)
upvalues.Switch:SetValue("Tree")
H.advance(0.2)
-- references from a script's upvalue
for _, node in upvalues.List:GetItems() do
	if node.Kind == "upvalue" and rawequal(node.Value, shared) then
		upvalues.List:SetSelected({ node })
		break
	end
end
H.advance(0.3)
check("references of a running function's upvalue", upvalues.RefsList and #upvalues.RefsList:GetItems() == 2, upvalues.RefsInfo and upvalues.RefsInfo.Text)
T.Explorer.load({ config })
H.advance(0.3)
check("a required module: its running functions", keys(upvalues):find("get", 1, true) ~= nil and keys(upvalues):find("toggle", 1, true) == nil, keys(upvalues))
H.RUNNING = {}
T.Explorer.load({ doorScript })
H.advance(0.3)
check("not listed as running but its functions are alive: they still show", keys(upvalues):find("toggle", 1, true) ~= nil, keys(upvalues))
local savedSenv, savedGC0 = H.SENV, H.GC
H.SENV = {}
H.GC = { other }
T.Explorer.load({ config })
H.advance(0.2)
T.Explorer.load({ doorScript })
H.advance(0.3)
check("a script that isn't running: says so", upvalues.Info.Text:find("no running functions", 1, true) ~= nil, upvalues.Info.Text)
H.SENV, H.GC = savedSenv, savedGC0
H.RUNNING = { doorScript }
local savedGC = H.GC
H.GC = { noUpvalues }
T.Explorer.load({ doorScript })
H.advance(0.3)
check("running functions without upvalues: says so", upvalues.Info.Text:find("none of its 1 running functions has upvalues", 1, true) ~= nil, upvalues.Info.Text)
H.GC = savedGC

----------------------------------------------------------------------
-- 2b. bug pass: no work while the tab is closed, no search per click,
-- one count everywhere, odd table keys
----------------------------------------------------------------------
T.Tabs:Select("console")
H.advance(0.3)
local compiles, searches = H.SCRIPT_CLOSURE_CALLS or 0, H.FILTERGC_CALLS or 0
T.Explorer.load({ doorScript })
H.advance(0.3)
T.Explorer.load({ config })
H.advance(0.3)
check("loads while the tab is closed don't compile scripts or search memory", (H.SCRIPT_CLOSURE_CALLS or 0) == compiles and (H.FILTERGC_CALLS or 0) == searches, tostring(H.SCRIPT_CLOSURE_CALLS) .. "/" .. tostring(H.FILTERGC_CALLS))
check("…what is loaded is still known to other plugins (worked out on asking)", exports().subject().Title == "Config")
T.Explorer.load({ doorScript })
H.advance(0.2)
T.Tabs:Select("scriptviewer")
H.advance(0.5)
check("opening the tab catches up", view.TitleLabel.Text == "DoorScript" and keys(upvalues):find("toggle", 1, true) ~= nil)
check("the Upvalues pill counts upvalues, the same as its bar", H.find(H.find(H.find(view.Tabs.Instance, "Tab_upvalues"), "Badge"), "Text").Text == "3")
searches = H.FILTERGC_CALLS or 0
view:Toggle("upvalues", upvalues.Roots[1].Id)
H.advance(0.1)
view:Toggle("upvalues", upvalues.Roots[1].Id)
H.advance(0.1)
check("opening and closing function headings doesn't search again", (H.FILTERGC_CALLS or 0) == searches, (H.FILTERGC_CALLS or 0) - searches)
upvalues.Switch:SetValue("Tree")
H.advance(0.2)
local badKey = setmetatable({}, { __tostring = function() error("no text for you") end })
local otherKey = setmetatable({}, { __tostring = function() error("nor you") end })
Loaded.load(Loaded.target({ [badKey] = 1, [otherKey] = 2, [1.5] = 3, plain = 4, [true] = 5 }))
H.advance(0.3)
view:Select("contents")
H.advance(0.3)
check("a table with keys whose __tostring errors still lists", #view.Panels.contents.List:GetItems() == 5 and #H.ERRORS == 0, H.ERRORS[1])
T.Explorer.load({ doorScript })
H.advance(0.3)
view:Select("source")
H.advance(0.3)

----------------------------------------------------------------------
-- 3. reloading and re-running with the tab open
----------------------------------------------------------------------
local function usable(label)
	T.Tabs:Select("scriptviewer")
	H.advance(0.5)
	local v = exports().view()
	check(label .. ": the tab has a working view", v ~= nil and not v.Destroyed and v.TitleLabel.Parent ~= nil and v.Tabs.Selected ~= nil)
	if v then
		T.Explorer.load({ doorScript })
		H.advance(0.4)
		v:Select("constants")
		H.advance(0.3)
		check(label .. ": loads still reach it", v.TitleLabel.Text == "DoorScript" and #v.Panels.constants.List:GetItems() == 1, v.TitleLabel.Text)
		v:Select("source")
		H.advance(0.3)
		check(label .. ": Source works", v.Panels.source.Editor:GetText():find("local open", 1, true) ~= nil)
	end
	check(label .. ": no fault lines, no errors", faultLines() == "" and #H.ERRORS == 0, faultLines() .. " " .. tostring(H.ERRORS[1]))
	return v
end
-- reload while the tab is open, mid-decompile
H.DECOMPILE_WAIT = 0.5

T.Explorer.load({ config })
H.advance(0.1)
async(Plugins.reload, "scriptviewer")
H.DECOMPILE_WAIT = nil
H.advance(0.8)
usable("reload mid-decompile, tab open")
-- reload from the console while a reference search runs
local v = exports().view()
v:Select("upvalues")
H.advance(0.3)
H.FILTERGC_WAIT = 0.5
for _, node in v.Panels.upvalues.List:GetItems() do
	if node.Kind == "upvalue" then
		v.Panels.upvalues.List:SetSelected({ node })
		break
	end
end
H.advance(0.1)
C.run("/plugin reload scriptviewer")
for _ = 1, 600 do
	H.step()
end
H.FILTERGC_WAIT = nil
H.advance(1)
usable("/plugin reload mid-search")
-- reload while the tab is closed
T.Tabs:Select("console")
H.advance(0.3)
async(Plugins.reload, "scriptviewer")
H.advance(0.5)
usable("reload with the tab closed")
-- the views chosen are kept across a reload
exports().view().Panels.constants.Switch:SetValue("List")
H.advance(0.2)
async(Plugins.reload, "scriptviewer")
H.advance(0.5)
T.Tabs:Select("scriptviewer")
H.advance(0.5)
exports().view():Select("constants")
H.advance(0.3)
check("views chosen survive a reload", exports().view().Panels.constants.Mode == "List")
-- re-running Tungsten with the tab open
H.run("Tungsten/Tungsten.luau")
H.advance(5)
T = genv.Tungsten.Context
Plugins, Loaded, C = T.Plugins, T.Loaded, T.Console
check("re-run: the plugin starts again", Plugins.get("scriptviewer").State == "on")
usable("re-run")

check("no runtime errors", #H.ERRORS == 0, H.ERRORS[1])
for _, e in H.ERRORS do
	print("ERR: " .. e)
end
print(("p1f: %d passed, %d failed, %d runtime errors"):format(passed, failed, #H.ERRORS))
