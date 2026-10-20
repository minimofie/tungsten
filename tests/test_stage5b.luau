-- Stage 5 Round A, part 2: the plugin host core (base/plugins): finding
-- plugin folders, reading plugin.luau with its P context, definition and
-- id checks, prime plugins and Requires, Exports, the states, on/off at
-- the next start, Load in its own thread with a time limit, failures,
-- reload, rescan, stop, id locks and dead apis.
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

local ok, err = H.run("Tungsten/Tungsten.luau")
check("loader runs", ok, err)
H.advance(5)
local T = genv.Tungsten.Context
check("no errors at start", #H.ERRORS == 0, H.ERRORS[1])

local Plugins = T.import("base/plugins")
T.Plugins = Plugins -- the loader does this from A3 on
local Api = T.import("base/api")
local Commands = T.import("console/commands")
local Menus = T.Menus

-- Runs fn where Tungsten can wait (like the loader), stepping time.
local function async(fn, ...)
	local args = table.pack(...)
	local done, results = false, nil
	local co = coroutine.create(function()
		results = table.pack(fn(table.unpack(args, 1, args.n)))
		done = true
	end)
	local okResume, errResume = coroutine.resume(co)
	if not okResume then
		error(errResume, 2)
	end
	local guard = 0
	while not done and guard < 4000 do
		guard += 1
		H.step()
	end
	assert(done, "never finished")
	return table.unpack(results, 1, results.n)
end

local ROOT = "Tungsten/plugins/"
local function install(...)
	for _, folder in { ... } do
		local prefix = "fixtures/plugins/" .. folder .. "/"
		local any = false
		for path, content in H.FILES do
			if path:sub(1, #prefix) == prefix then
				H.FILES[ROOT .. folder .. "/" .. path:sub(#prefix + 1)] = content
				any = true
			end
		end
		assert(any, "no fixture " .. folder)
	end
end
local function uninstall(folder)
	for path in table.clone(H.FILES) do
		if path:sub(1, #ROOT + #folder + 1) == ROOT .. folder .. "/" then
			H.FILES[path] = nil
		end
	end
end
local function restart()
	async(Plugins.stop)
	return async(Plugins.start)
end
local function state(key)
	local record = Plugins.get(key) or Plugins.byFolder(key)
	return record and record.State
end
local function consoleText(from)
	local out = {}
	for index = from or 1, #T.Console.Lines do
		table.insert(out, T.Console.Lines[index].Plain)
	end
	return table.concat(out, "\n")
end

----------------------------------------------------------------------
-- 1. nothing installed
----------------------------------------------------------------------
do
	check("no plugins: start finds none", async(Plugins.start) == 0 and #Plugins.list() == 0)
	check("the welcome count works through T.Plugins", T.Console.pluginCount() == 0)
	check("plugins/manager.luau is not a plugin", Plugins.byFolder("manager.luau") == nil)
	async(Plugins.stop)
end

----------------------------------------------------------------------
-- 2. finding and reading plugins; new ones start off
----------------------------------------------------------------------
install("Good", "Broken", "BadDef", "Crash", "Slow", "SlowOk", "Twin", "Squat", "Scanner", "Needy", "Greedy", "NoId", "TopFail", "_template", "NotAPlugin")
H.FILES[ROOT .. "Hooky/plugin.luau"] = "-- uses hookmetamethod\nreturn { Id = 'hooky', Name = 'Hooky' }"
async(Plugins.start)
do
	local list = Plugins.list()
	check("every folder with a plugin.luau is found", #list == 14, #list)
	check("a folder starting with _ is skipped (never run)", Plugins.byFolder("_template") == nil and genv.TemplateRan == nil)
	check("a folder without plugin.luau is skipped", Plugins.byFolder("NotAPlugin") == nil)
	check("new plugins start off (P1)", state("good") == "off" and state("crash") == "off" and state("scanner") == "off")
	check("…and their Load didn't run", genv.GoodLoaded == nil)
	check("nothing counted as running", Plugins.count() == 0)
	check("prime plugins come first in the order", list[1].Id == "scanner", list[1].Folder)
	check("then Order: Needy (Order 1) before the rest", list[2].Folder == "Needy", list[2].Folder)

	local good = Plugins.get("good")
	check("definition read: name, version, author, description", good.Name == "Good" and good.Version == "1.2" and good.Author == "tests" and good.Description == "does everything right")
	check("P.import ran lib/util with P (folder known)", genv.GoodUtilRuns == 1)
	check("no hooks in Good", #good.Hooks == 0)
	check("hook use is noted (information only)", Plugins.get("hooky").Hooks[1] == "hookmetamethod")

	local broken = Plugins.byFolder("Broken")
	check("a compile error is a problem", broken.State == "problem" and broken.CompileError == true and broken.Problem:find("doesn't compile", 1, true) ~= nil, broken.Problem)
	local baddef = Plugins.byFolder("BadDef")
	check("a bad definition is a problem with the reason", baddef.State == "problem" and baddef.Problem == "Name is missing", baddef.Problem)
	local top = Plugins.byFolder("TopFail")
	check("a failing top level is a problem with a trace", top.State == "problem" and top.Problem:find("top level fails", 1, true) ~= nil and top.Trace ~= nil)
	local twin = Plugins.byFolder("Twin")
	check("a duplicate id: the first folder (A–Z) wins", twin.State == "problem" and twin.Problem:find("already used by plugins/Good", 1, true) ~= nil and Plugins.get("good").Folder == "Good", twin.Problem)
	local squat = Plugins.byFolder("Squat")
	check("a prime id without Prime = true is refused", squat.State == "problem" and squat.Problem:find("reserved for a prime plugin", 1, true) ~= nil, squat.Problem)
	check("…and doesn't take the id from the real one", Plugins.get("scanner").Folder == "Scanner")
	local greedy = Plugins.byFolder("Greedy")
	check("Requires can only name prime plugins", greedy.State == "problem" and greedy.Problem:find("can only name the prime plugins", 1, true) ~= nil, greedy.Problem)
	local noid = Plugins.get("noid")
	check("no Id: goes by the folder name, with a warning", noid and noid.State == "off" and noid.Warnings[1] and noid.Warnings[1]:find("set Id", 1, true) ~= nil)
	check("no runtime errors from bad plugins", #H.ERRORS == 0, H.ERRORS[1])
end

----------------------------------------------------------------------
-- 3. id locks
----------------------------------------------------------------------
do
	local okMake, message = pcall(T.api, "good", { Name = "Fake" })
	check("console code can't take a plugin folder's id", not okMake and tostring(message):find("belongs to the plugin in plugins/Good", 1, true) ~= nil, message)
	local free = T.api("freeid", { Name = "Free" })
	check("…any other id still works", free ~= nil and free:remove() >= 0)
	check("Api.lockedBy names the folder", Api.lockedBy("good") == "Good" and Api.lockedBy("freeid") == nil)
	check("a problem folder doesn't lock an id", Api.lockedBy("baddef") == nil)
end

----------------------------------------------------------------------
-- 4. on / off at the next start (P1, P3)
----------------------------------------------------------------------
do
	check("turning on an unknown plugin fails", Plugins.setWanted("nope", true) == false)
	check("turning on Good is only for the next start", Plugins.setWanted("good", true) and state("good") == "off" and genv.GoodLoaded == nil)
	check("…shown as pending on", Plugins.pending("good") == "on" and Plugins.wanted("good"))
	H.advance(0.6)
	check("…and saved in base/plugins.json", (H.FILES["Tungsten/base/plugins.json"] or ""):find('"good"', 1, true) ~= nil, H.FILES["Tungsten/base/plugins.json"])
	restart()
	check("after a restart it is on", state("good") == "on" and Plugins.count() == 1 and Plugins.pending("good") == nil)
	check("Load ran once", genv.GoodLoaded == 1)
	check("turning it off keeps it running until the next start (P3)", Plugins.setWanted("good", false) and state("good") == "on" and Plugins.pending("good") == "off")
	Plugins.setWanted("good", true)
	check("turning it back on clears the pending note", Plugins.pending("good") == nil)
end

----------------------------------------------------------------------
-- 5. a running plugin: everything it declared is registered
----------------------------------------------------------------------
do
	local good = Plugins.get("good")
	local api = good.Api
	check("its api is the plugin's", api and api.Id == "good" and api.Folder == "Good" and api.Version == "1.2" and api.Path == "Tungsten/plugins/Good")
	check("its command", Commands.get("good", "goodhello") ~= nil)
	local before = #T.Console.Lines
	T.Console.run("/goodhello")
	check("…runs (with lib/util)", consoleText(before + 1):find("hello tests", 1, true) ~= nil, consoleText(before + 1))
	local found = false
	for _, entry in Menus.entries("explorer.function") do
		if entry.Owner == "good" then
			found = true
		end
	end
	check("its explorer function", found)
	check("its tab (closable, owned)", T.Registry.getTab("good") ~= nil and T.Registry.getTab("good").Owner == "good" and T.Registry.getTab("good").Closable == true)
	check("its docs topic from docs.md", T.Docs.get("good") ~= nil and T.Docs.get("good").Owner == "good")
	check("Load set its variable", T.Variables.get("goodvar") == 42)
	check("its settings are kept in its folder", api.settings.Path == "Tungsten/plugins/Good/settings.json" and api.settings.get("speed") == 16)
	check("load time is measured", type(good.LoadTime) == "number" and good.LoadTime >= 0)
	T.Tabs:Select("good")
	H.advance(0.3)
	local page = T.Tabs.Pages.good
	local label = page and H.find(page, "GoodLabel")
	check("the tab is built the first time it opens, with P.read", label ~= nil and label.Text == "from data.txt")
	T.Tabs:Select("console")
	H.advance(0.2)
end

----------------------------------------------------------------------
-- 6. failures: Load throws, Load too slow, a slow Load within the limit
----------------------------------------------------------------------
do
	Plugins.setWanted("crash", true)
	Plugins.setWanted("slow", true)
	Plugins.setWanted("slowok", true)
	local before = #T.Console.Lines
	local t0 = H.TIME
	restart()
	local elapsed = H.TIME - t0
	local crash = Plugins.get("crash")
	check("a throwing Load: failed", crash.State == "failed" and crash.Problem:find("boom in Load", 1, true) ~= nil, crash.Problem)
	check("…the error is in the console under its name", consoleText(before + 1):find("Crash", 1, true) ~= nil and consoleText(before + 1):find("boom in Load", 1, true) ~= nil)
	check("…what it registered is gone", Commands.get("crash", "crashcmd") == nil and not T.Variables.has("crashvar"))
	check("…with a trace kept", crash.Trace ~= nil and crash.Faults == 1)
	local slow = Plugins.get("slow")
	check("a Load past 5 s: failed", slow.State == "failed" and slow.Problem == "Load took longer than 5 s", slow.Problem)
	check("…start-up waited about 5 s for it, not longer", elapsed >= 5 and elapsed < 8, elapsed)
	H.advance(30)
	check("…and its Load was stopped (never finishes later)", genv.SlowFinished == nil and not T.Variables.has("slowvar"))
	local slowok = Plugins.get("slowok")
	check("a Load that waits 1 s is fine", slowok.State == "on" and genv.SlowOkDone == true and slowok.LoadTime >= 1 - 1e-6, slowok.LoadTime)
	check("the others still started", state("good") == "on")
	check("failed plugins aren't counted", Plugins.count() == 2, Plugins.count())
	Plugins.setWanted("slow", false)
	Plugins.setWanted("slowok", false)
end

----------------------------------------------------------------------
-- 7. prime plugins, Requires and Exports
----------------------------------------------------------------------
do
	Plugins.setWanted("needy", true)
	restart()
	local needy = Plugins.get("needy")
	check("a plugin whose prime plugin is off can't run", needy.State == "problem" and needy.Problem:find("which isn't on", 1, true) ~= nil, needy.Problem)
	Plugins.setWanted("scanner", true)
	restart()
	check("with the prime plugin on, both run", state("scanner") == "on" and state("needy") == "on")
	check("api.plugins.get gives the prime plugin's Exports", genv.NeedyGot == "pong", genv.NeedyGot)
	check("…only for plugins listed in Requires", type(genv.NeedyNotListed) == "string" and genv.NeedyNotListed:find("doesn't list 'good'", 1, true) ~= nil, genv.NeedyNotListed)
	check("Exports made by a function get the api", Plugins.exportsFor("needy", "scanner").owner == "scanner")
	check("a plugin that doesn't list it gets nothing", Plugins.exportsFor("good", "scanner") == nil)
end

----------------------------------------------------------------------
-- 8. reload
----------------------------------------------------------------------
do
	local api = Plugins.get("good").Api
	api.settings.set("speed", 50)
	H.FILES[ROOT .. "Good/plugin.luau"] = H.FILES[ROOT .. "Good/plugin.luau"]:gsub('Version = "1.2"', 'Version = "1.3"')
	local loadsBefore, unloadsBefore = genv.GoodLoaded, genv.GoodUnloaded or 0
	local okReload = async(Plugins.reload, "good")
	local good = Plugins.get("good")
	check("reload: on again with the new files", okReload and good.State == "on" and good.Version == "1.3")
	check("reload: Unload then Load ran", genv.GoodUnloaded == unloadsBefore + 1 and genv.GoodLoaded == loadsBefore + 1)
	check("reload: settings kept", good.Api.settings.get("speed") == 50, good.Api.settings.get("speed"))
	check("reload: the old api is dead", not Api.isAlive(api) and Api.isAlive(good.Api))
	local okDead, deadError = pcall(api.console.register, { Name = "late", Run = function() end })
	check("…and can't register anything", not okDead and tostring(deadError):find("was unloaded", 1, true) ~= nil, deadError)

	check("a failed plugin keeps its state and error through another plugin's reload", state("crash") == "failed" and Plugins.get("crash").Problem ~= nil)
	-- a failed plugin, fixed and reloaded
	H.FILES[ROOT .. "Crash/plugin.luau"] = H.FILES[ROOT .. "Crash/plugin.luau"]:gsub('error%("boom in Load"%)', "")
	local okCrash, crashWhy = async(Plugins.reload, "crash")
	check("reload a fixed failed plugin: on", okCrash and state("crash") == "on", crashWhy)

	-- reloading a prime plugin restarts the plugins that need it
	genv.NeedyGot = nil
	check("reload the prime plugin", async(Plugins.reload, "scanner") and state("scanner") == "on")
	check("…plugins that need it start again with its new Exports", state("needy") == "on" and genv.NeedyGot == "pong")

	-- reload never starts a plugin that is only on for the next start
	Plugins.setWanted("noid", true)
	async(Plugins.reload, "noid")
	check("reload doesn't start a plugin turned on for the next start", state("noid") == "off")
	Plugins.setWanted("noid", false)
	check("reload of an unknown plugin says so", async(Plugins.reload, "nope") == false)
end

----------------------------------------------------------------------
-- 9. rescan
----------------------------------------------------------------------
do
	H.FILES[ROOT .. "Late/plugin.luau"] = "return { Id = 'late', Name = 'Late' }"
	H.FILES[ROOT .. "Broken/plugin.luau"] = "return { Id = 'broken', Name = 'Broken' }"
	uninstall("NoId")
	Plugins.rescan()
	check("rescan finds a new folder, off", state("late") == "off")
	check("rescan reads a fixed folder again", state("broken") == "off")
	check("rescan drops a folder that is gone", Plugins.get("noid") == nil and Plugins.byFolder("NoId") == nil)
	check("running plugins are left alone", state("good") == "on" and state("scanner") == "on")
	uninstall("Late")
end

----------------------------------------------------------------------
-- 10. stopping
----------------------------------------------------------------------
do
	local goodApi = Plugins.get("good").Api
	local unloads = genv.GoodUnloaded
	async(Plugins.stop)
	check("stop: Unload ran", genv.GoodUnloaded == unloads + 1)
	check("stop: nothing running", Plugins.count() == 0 and #Plugins.list() == 0)
	check("stop: its registrations are gone", Commands.get("good", "goodhello") == nil and T.Registry.getTab("good") == nil and T.Docs.get("good") == nil and not T.Variables.has("goodvar"))
	check("stop: its api is dead", not Api.isAlive(goodApi))
	check("stop: the ids are free again", Api.lockedBy("good") == nil)
	local okNow, made = pcall(T.api, "good", { Name = "Now free" })
	check("…so console code can use them", okNow and made ~= nil)
	if okNow then
		made:remove()
	end
	check("stop: which plugins are on is saved", (H.FILES["Tungsten/base/plugins.json"] or ""):find('"scanner"', 1, true) ~= nil)
end

----------------------------------------------------------------------
-- 11. Reset all doesn't touch which plugins are on (P7)
----------------------------------------------------------------------
do
	local saved = H.FILES["Tungsten/base/plugins.json"]
	T.Preferences.resetAll()
	H.advance(0.6)
	check("Reset all settings leaves plugins.json alone", H.FILES["Tungsten/base/plugins.json"] == saved)
end

check("no runtime errors", #H.ERRORS == 0, H.ERRORS[1])
print(("stage5b: %d passed, %d failed, %d runtime errors"):format(passed, failed, #H.ERRORS))
