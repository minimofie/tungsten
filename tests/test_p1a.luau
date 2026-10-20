-- Plugins stage, round 1 part 1.1: the script viewer ships in
-- plugins/ScriptViewer (prime, off until turned on), its tab, the
-- Overview of what is loaded (scripts, ModuleScripts, functions, tables,
-- other values), missing Volt functions, reveal, integrity entries.
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
H.keepPrimes() -- this suite tests the shipped prime plugin

-- what the game has
local map = E_.Instance.new("Model")
map.Name = "Map"
map.Parent = E_.workspace
local door = H.part("Door", map)
local doorScript = E_.Instance.new("LocalScript")
doorScript.Name = "DoorScript"
doorScript.Parent = door
local idleScript = E_.Instance.new("LocalScript")
idleScript.Name = "IdleScript"
idleScript.Parent = door
local config = E_.Instance.new("ModuleScript")
config.Name = "Config"
config.Parent = map
local unused = E_.Instance.new("ModuleScript")
unused.Name = "Unused"
unused.Parent = map

local function onTouched(hit, extra, ...) return hit end
H.FN[onTouched] = {
	Constants = { "Touched", 5, "Humanoid" },
	Upvalues = { door, 3, "open" },
	Protos = { { Info = { name = "inner" } }, { Info = { name = "other" } } },
	Info = { name = "onTouched", numparams = 2, is_vararg = 1, nups = 3 },
	Hash = string.rep("9f", 48),
}
local function scriptMain() end
H.FN[scriptMain] = { Constants = { "a", "b", "c", "d" }, Protos = { {}, {}, {} } }
H.SCRIPT_CLOSURES = { [doorScript] = scriptMain, [idleScript] = scriptMain, [config] = scriptMain, [unused] = scriptMain }
H.RUNNING = { doorScript }
H.SENV = { [doorScript] = { open = true, toggle = function() end, speed = 3 } }
H.LOADED = { config }
H.MODULE_VALUES = { [config] = { Speed = 16, Name = "door", [1] = "a", [2] = "b" } }
local function tool() end
H.FN[tool] = { Executor = true }

local ok, err = H.run("Tungsten/Tungsten.luau")
check("loader runs", ok, err)
H.advance(5)
local T = genv.Tungsten.Context
local Plugins, C, Loaded = T.Plugins, T.Console, T.Loaded
check("no errors at start", #H.ERRORS == 0, H.ERRORS[1])

----------------------------------------------------------------------
-- 1. it ships, off until turned on
----------------------------------------------------------------------
local record = Plugins.get("scriptviewer")
check("the script viewer is found in plugins/ScriptViewer", record ~= nil and record.Folder == "ScriptViewer", record and record.Folder)
check("…as the prime plugin scriptviewer", record and record.Definition.Prime == true and record.Name == "Script Viewer")
check("…off until you turn it on (P1)", record and record.State == "off", record and record.State)
check("…with no problem or warning", record and record.Problem == nil and #record.Warnings == 0, record and (record.Problem or record.Warnings[1]))
local function lines(from)
	local out = {}
	for index = from or 1, #C.Lines do
		table.insert(out, C.Lines[index].Plain)
	end
	return table.concat(out, "\n")
end
check("integrity ok with it shipped, its Volt functions listed", lines():find("integrity ok", 1, true) ~= nil and lines():find("51/51 executor functions", 1, true) ~= nil, lines():match("[^\n]*integrity[^\n]*"))
local Integrity = T.import("base/integrity")
local listed = {}
for _, entry in Integrity.Functions do
	listed[entry[1]] = true
end
local usesAll = true
for _, name in { "debug.getconstants", "debug.getupvalues", "debug.getprotos", "debug.getinfo", "getscripthash", "getfunctionhash", "getsenv", "getrunningscripts", "iscclosure", "isexecutorclosure", "isreadonly", "getrawmetatable" } do
	usesAll = usesAll and listed[name] == true
end
check("every Volt function 1.1 uses is in the integrity list", usesAll)

-- turn it on and restart the plugins (as on the next run)
Plugins.setWanted("scriptviewer", true)
local function async(fn)
	local done = false
	local co = coroutine.create(function()
		fn()
		done = true
	end)
	local okResume, errResume = coroutine.resume(co)
	assert(okResume, errResume)
	local guard = 0
	while not done and guard < 4000 do
		guard += 1
		H.step()
	end
end
async(Plugins.stop)
async(Plugins.start)
H.advance(0.5)
record = Plugins.get("scriptviewer")
check("turned on, it starts", record and record.State == "on", record and (record.State .. " " .. tostring(record.Problem or record.Error)))
check("…with its tab in the side bar", T.Registry.getTab("scriptviewer") ~= nil and T.Registry.getTab("scriptviewer").Title == "Script Viewer")
local exports = record and record.Exports
check("…and its exports", type(exports) == "table" and type(exports.reveal) == "function" and type(exports.subject) == "function")

----------------------------------------------------------------------
-- helpers on the built tab
----------------------------------------------------------------------
local function openTab()
	T.Tabs:Select("scriptviewer")
	H.advance(0.4)
end
-- what is shown now (lib/inspect), read from the plugin's exports: the
-- Overview sub-tab is gone, the facts still describe what is loaded
local function subjectFacts()
	local subject = exports.subject()
	local out = {}
	for _, item in (subject and subject.Facts or {}) do
		out[item.Id] = item.Value
	end
	return out
end
local function fact(id)
	local value = subjectFacts()[id]
	return if value ~= nil then tostring(value) else nil
end
local function facts()
	local out = {}
	for id in subjectFacts() do
		table.insert(out, id)
	end
	table.sort(out)
	return table.concat(out, ",")
end
local function notes()
	local subject = exports.subject()
	return table.concat(subject and subject.Notes or {}, " | ")
end
local function view()
	return exports.view()
end
local function title()
	local v = view()
	return v and v.TitleLabel.Text
end
local function kind()
	local v = view()
	return v and v.Kind.Text
end

----------------------------------------------------------------------
-- 2. nothing loaded
----------------------------------------------------------------------
Loaded.clear()
openTab()
check("the tab builds with Source first and no Overview", view() and view().Tabs.Order[1] == "source" and H.find(T.Window.Root, "Tab_overview") == nil, view() and table.concat(view().Tabs.Order, ","))
check("…Source is open", view().Tabs.Selected == "source")
check("nothing loaded: the title says so", title() == "Nothing loaded", title())
check("…and the line under it says what to load", kind() == "load a script, a ModuleScript, a function or a table", kind())

----------------------------------------------------------------------
-- 3. a Luau function
----------------------------------------------------------------------
Loaded.load(Loaded.target(onTouched, { Origin = doorScript }))
H.advance(0.3)
check("a function: the title is its name", title() == "onTouched", title())
check("…and the kind line says what it is", kind() == "Luau function", kind())
check("kind and maker", fact("kind") == "Luau function" and fact("made") == "the game", tostring(fact("kind")) .. "/" .. tostring(fact("made")))
check("parameters with ...", fact("params") == "2 + ...", fact("params"))
check("upvalue, constant and nested-function counts", fact("upvalues") == "3" and fact("constants") == "3" and fact("functions") == "2", facts())
check("its hash, shortened", fact("hash") == string.rep("9f", 6) .. "…", fact("hash"))
check("where it is defined (Luau's own debug.info)", fact("line") ~= nil and fact("line"):match("^line %d+$") ~= nil and fact("source") ~= nil, fact("line"))
check("the subject is exported", exports.subject().Kind == "function" and exports.subject().Fn == onTouched)

-- a C function
Loaded.load(Loaded.target(print))
H.advance(0.3)
check("a C function: kind", fact("kind") == "C function", fact("kind"))
check("…no constants, hash or source", fact("constants") == nil and fact("hash") == nil and fact("source") == nil, facts())
check("…and a note why", notes():find("C function has no constants", 1, true) ~= nil, notes())

-- the executor's own
Loaded.load(Loaded.target(tool))
H.advance(0.3)
check("an executor function says so", fact("made") == "the executor" and kind() == "Luau function · made by the executor", kind())

----------------------------------------------------------------------
-- 4. tables
----------------------------------------------------------------------
local data = setmetatable({ 1, 2, 3, a = 1, b = 2 }, {})
Loaded.load(Loaded.target(data, { Label = "data" }))
H.advance(0.3)
check("a table: title from its label", title() == "data", title())
check("entries counted in order and by key", fact("entries") == "5 (3 in order, 2 by key)", fact("entries"))
check("metatable yes, read-only no", fact("metatable") == "yes" and fact("readonly") == "no")
Loaded.load(Loaded.target(table.freeze({ x = 1 })))
H.advance(0.3)
check("a frozen table is read-only", fact("readonly") == "yes" and fact("metatable") == "no")

----------------------------------------------------------------------
-- 5. scripts
----------------------------------------------------------------------
T.Explorer.load({ doorScript })
H.advance(0.3)
check("a running LocalScript: title, class, path", title() == "DoorScript" and fact("class") == "LocalScript" and fact("path") == "Workspace.Map.Door.DoorScript", tostring(fact("path")))
check("…running, with its globals", fact("running") == "yes" and fact("globals") == "3", tostring(fact("running")) .. "/" .. tostring(fact("globals")))
check("…its hash", fact("hash") == string.rep("ab", 6) .. "…")
check("…its main function's constants and nested functions", fact("constants") == "4" and fact("functions") == "3", facts())
check("…and a note that the main function is compiled again", notes():find("compiled again", 1, true) ~= nil, notes())
check("the subject's function is the main function", exports.subject().Fn == scriptMain and exports.subject().Env == H.SENV[doorScript])
T.Explorer.load({ idleScript })
H.advance(0.3)
check("a script that isn't running: no globals", fact("running") == "no" and fact("globals") == nil)
H.SCRIPT_HASH = { [idleScript] = false }
T.Explorer.load({ idleScript })
H.advance(0.3)
check("no bytecode: no hash, and a note", fact("hash") == nil and notes():find("no bytecode", 1, true) ~= nil, notes())
H.SCRIPT_HASH = nil
-- bytecode that doesn't compile
H.SCRIPT_CLOSURES[idleScript] = "bad bytecode at line 1"
T.Explorer.load({ idleScript })
H.advance(0.3)
check("bytecode that doesn't compile: said in a note, no counts", notes():find("didn't compile: bad bytecode", 1, true) ~= nil and fact("constants") == nil, notes())
H.SCRIPT_CLOSURES[idleScript] = scriptMain

----------------------------------------------------------------------
-- 6. ModuleScripts (never required by the viewer)
----------------------------------------------------------------------
local required = H.REQUIRED or 0
T.Explorer.load({ unused })
H.advance(0.3)
check("a module the game hasn't required: not required here either", fact("required") == "no" and (H.REQUIRED or 0) == required)
check("…and a note why", notes():find("requiring it would run it", 1, true) ~= nil, notes())
T.Explorer.load({ config })
H.advance(0.3)
check("a required module: what it returns", fact("required") == "yes" and fact("returns") == "table (4 entries)", fact("returns"))
check("…its table is the subject's table", exports.subject().Table == H.MODULE_VALUES[config])

----------------------------------------------------------------------
-- 7. other things, several, missing Volt functions
----------------------------------------------------------------------
T.Explorer.load({ door })
H.advance(0.3)
check("a Part: its class and a note on what can be looked into", fact("class") == "Part" and notes():find("load a script", 1, true) ~= nil)
T.Explorer.load({ doorScript, config })
H.advance(0.3)
check("two loaded: the first, and a note", title() == "DoorScript" and notes():find("2 things are loaded", 1, true) ~= nil, notes())
local saved = E_.getfunctionhash
E_.getfunctionhash = nil
Loaded.load(Loaded.target(onTouched))
H.advance(0.3)
check("a missing Volt function leaves its fact out, nothing breaks", fact("hash") == nil and fact("constants") == "3" and #H.ERRORS == 0, H.ERRORS[1])
E_.getfunctionhash = saved
local savedInfo = E_.debug.getinfo
rawset(E_.debug, "getinfo", function() error("no info") end)
Loaded.load(Loaded.target(onTouched))
H.advance(0.3)
check("a failing one too, with a note", fact("params") == nil and notes():find("debug.getinfo didn't answer", 1, true) ~= nil, notes())
rawset(E_.debug, "getinfo", savedInfo)

----------------------------------------------------------------------
-- 8. loads while the tab is closed; reveal
----------------------------------------------------------------------
T.Tabs:Select("console")
H.advance(0.3)
T.Explorer.load({ config })
H.advance(0.3)
openTab()
check("a load while the tab was closed shows when it opens", title() == "Config" and fact("returns") ~= nil)
T.Tabs:Select("console")
H.advance(0.3)
local okOpen = Plugins.open("you", "scriptviewer", { Target = onTouched, Panel = "constants" })
H.advance(0.3)
check("open with a raw function: it is loaded and the tab opens", okOpen and T.Tabs.Selected == "scriptviewer" and title() == "onTouched" and Loaded.value() == onTouched)
check("…at the sub-tab asked for", view().Tabs.Selected == "constants")
check("…as a target for every tab", Loaded.isTarget(Loaded.get()) and T.Variables.get("loaded") == onTouched)

----------------------------------------------------------------------
-- 9. turning it off
----------------------------------------------------------------------
Plugins._disable(record)
H.advance(0.3)
check("stopping it removes its tab", T.Registry.getTab("scriptviewer") == nil)
Loaded.load(Loaded.target(onTouched))
H.advance(0.2)
check("loads after it stopped don't reach it (no errors)", #H.ERRORS == 0, H.ERRORS[1])

check("no runtime errors", #H.ERRORS == 0, H.ERRORS[1])
for _, e in H.ERRORS do
	print("ERR: " .. e)
end
print(("p1a: %d passed, %d failed, %d runtime errors"):format(passed, failed, #H.ERRORS))
