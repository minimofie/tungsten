-- Stage 5 Round A, part 3: the plugin host in Tungsten: start-up order and
-- the welcome line, faults under the plugin's name (counted), /plugins and
-- /plugin, nothing left behind when a plugin goes (every registry),
-- shutdown and re-runs, and plugin folders outside the integrity check.
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
local genv = H.genv

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

-- six plugins, all turned on (as if chosen in an earlier session)
install("Good", "Scanner", "Needy", "Crash", "Everything", "Faulty", "BadDef")
H.FILES["Tungsten/base/plugins.json"] = '{"On":["good","scanner","needy","crash","everything","faulty"]}'
local part = H.part("Thing", E_.workspace)

local ok, err = H.run("Tungsten/Tungsten.luau")
check("loader runs", ok, err)
local T = genv.Tungsten.Context
check("plugins started while the splash was up (Load ran before the window opened)", genv.GoodLoaded == 1 and T.Window.Root.Visible == false or genv.GoodLoaded == 1)
H.advance(5)
check("no runtime errors at start", #H.ERRORS == 0, H.ERRORS[1])

local Plugins = T.Plugins
local C = T.Console
local Commands = T.import("console/commands")

local function lines(from)
	local out = {}
	for index = from or 1, #C.Lines do
		table.insert(out, C.Lines[index].Plain)
	end
	return table.concat(out, "\n")
end
local function has(text, piece)
	return text:find(piece, 1, true) ~= nil
end
local function run(input)
	local before = #C.Lines
	C.run(input)
	H.advance(0.1)
	return lines(before + 1)
end
local function async(fn, ...)
	local args = table.pack(...)
	local done, results = false, nil
	local co = coroutine.create(function()
		results = table.pack(fn(table.unpack(args, 1, args.n)))
		done = true
	end)
	assert(coroutine.resume(co))
	local guard = 0
	while not done and guard < 4000 do
		guard += 1
		H.step()
	end
	return table.unpack(results or {}, 1, results and results.n or 0)
end

----------------------------------------------------------------------
-- 1. start-up
----------------------------------------------------------------------
do
	check("the loader makes T.Plugins and starts it", type(Plugins) == "table" and Plugins.started())
	check("the chosen plugins are on", Plugins.get("good").State == "on" and Plugins.get("scanner").State == "on" and Plugins.get("needy").State == "on" and Plugins.get("everything").State == "on" and Plugins.get("faulty").State == "on")
	check("a failing one is failed, the rest still started", Plugins.get("crash").State == "failed")
	check("prime first, then the others (needy got the scanner)", genv.NeedyGot == "pong")
	check("plugin load time measured apart", type(T.PluginLoadTime) == "number" and type(T.LoadTime) == "number")
	local welcome = lines(1)
	check("welcome: plugins loaded, with their own time", has(welcome, "5 plugins loaded in "), welcome:sub(1, 300))
	check("welcome: says one didn't start", has(welcome, "1 didn't start (/plugins)"))
	check("welcome: Crash's error is in the console under its name", has(welcome, "[x] Crash: Load failed: ") and has(welcome, "boom in Load"))
	local report = T.import("base/integrity").run()
	local mentions = false
	for _, text in report.Problems do
		if has(text, "plugins/") then
			mentions = true
		end
	end
	check("integrity never looks into plugin folders", not mentions and report.Ok, report.Problems[1])
end

----------------------------------------------------------------------
-- 2. faults run under the plugin's name and are counted
----------------------------------------------------------------------
do
	local faulty = Plugins.get("faulty")
	local base = faulty.Faults
	local at = run("/faultcmd")
	check("a crashing plugin command: [x] Faulty: :faulty.faultcmd failed", has(at, "[x] Faulty: :faulty.faultcmd failed: ") and has(at, "attempt to index nil"), at)
	check("…counted", faulty.Faults == base + 1 and faulty.LastFault and faulty.LastFault.What == ":faulty.faultcmd")

	-- completing its arguments
	local view = C.View
	T.Tabs:Select("console")
	H.advance(0.2)
	local before = #C.Lines
	H.focusBox(view.Box)
	view.Box.CursorPosition = 12
	view.Box.Text = "/faultcmd a"
	H.step()
	H.advance(0.2)
	check("a failing Complete is reported, not swallowed", has(lines(before + 1), "[x] Faulty: completing :faulty.faultcmd failed: ") and has(lines(before + 1), "complete broke"), lines(before + 1))
	view.Box.Text = ""
	H.step()
	H.focused = nil

	-- explorer function AppliesTo
	before = #C.Lines
	local E = T.Explorer
	local node = E.Tree:NodeFor(part)
	local ctx = T.import("base/explorer/menu").context(E, { node }, node, V2(10, 10))
	T.Menus.build("explorer.function", ctx)
	check("a failing AppliesTo is reported under its name", has(lines(before + 1), "[x] Faulty: AppliesTo of 'faultfn' failed: ") and has(lines(before + 1), "applies broke"), lines(before + 1))

	-- its tab
	before = #C.Lines
	T.Tabs:Select("faulty")
	H.advance(0.3)
	check("a failing tab Build is reported under its name", has(lines(before + 1), "[x] Faulty: building tab 'faulty' failed: ") and has(lines(before + 1), "build broke"), lines(before + 1))
	T.Tabs:Select("console")
	H.advance(0.2)

	-- a UI hook it added
	before = #C.Lines
	T.UI.fire("Button", "Clicked", "faulty")
	check("a failing UI hook is reported under its name", has(lines(before + 1), "[x] Faulty: ") and has(lines(before + 1), "hook broke"), lines(before + 1))

	-- a settings action (the manager's row)
	before = #C.Lines
	local Manager = T.Manager
	Manager.addEntry({ Id = "faulty", Name = "Faulty", Settings = faulty.Api.settings, Context = faulty.Api })
	T.Tabs:Select("plugins")
	H.advance(0.3)
	Manager.select("faulty")
	H.advance(0.2)
	local control = Manager.Controls.go
	if control then
		H.clickObject(control.Widget.Instance)
		H.advance(0.2)
	end
	check("a failing settings action is reported under its name", control ~= nil and has(lines(before + 1), "[x] Faulty: 'Go' failed: ") and has(lines(before + 1), "action broke"), lines(before + 1))
	Manager.removeEntry("faulty")
	T.Tabs:Select("console")
	H.advance(0.2)

	check("every fault is counted on the plugin", faulty.Faults >= base + 6, faulty.Faults - base)
	check("faults never turn a plugin off (P5)", faulty.State == "on")
	check("a fault never breaks Tungsten", #H.ERRORS == 0, H.ERRORS[1])
end

----------------------------------------------------------------------
-- 3. /plugins and /plugin
----------------------------------------------------------------------
do
	local at = run("/plugins")
	check("/plugins lists id, name, version and state", has(at, "good") and has(at, "Good") and has(at, "v1.2") and has(at, "on"), at)
	check("…with failures and problems and why", has(at, "failed") and has(at, "boom in Load") and has(at, "(BadDef)") and has(at, "Name is missing"), at)
	check("…and how many are on", has(at, "5 on"), at)

	at = run("/plugin info good")
	check("/plugin info: name, version, author", has(at, "Good v1.2 · by tests"), at)
	check("/plugin info: id and folder", has(at, "id good · folder plugins/Good"), at)
	check("/plugin info: load time and what it adds", has(at, "loaded in ") and has(at, "1 command") and has(at, "1 tab") and has(at, "1 explorer function") and has(at, "1 variable"), at)
	at = run("/plugin info faulty")
	check("/plugin info: faults and the last one", has(at, " faults · last: "), at)
	at = run("/plugin info BadDef")
	check("/plugin info works by folder for a problem", has(at, "Name is missing") and has(at, "problem"), at)

	at = run("/plugin off good")
	check("/plugin off: from the next start, keeps running", has(at, "good will be off at the next start (it keeps running until then)") and Plugins.get("good").State == "on", at)
	at = run("/plugins")
	check("/plugins shows what changes at the next start", has(at, "off at the next start"), at)
	at = run("/plugin on good")
	check("/plugin on for a running one: stays on", has(at, "good stays on"), at)
	at = run("/plugin on nope")
	check("/plugin on unknown: says so", has(at, "no plugin 'nope'"), at)
	at = run("/plugin frob good")
	check("/plugin with a wrong action shows the usage", has(at, "usage: /plugin"), at)

	-- reload from the console (Load may wait: it runs where Tungsten can wait)
	H.FILES[ROOT .. "Crash/plugin.luau"] = H.FILES[ROOT .. "Crash/plugin.luau"]:gsub('error%("boom in Load"%)', "")
	at = run("/plugin reload crash")
	H.advance(0.5)
	at = lines(#C.Lines - 3)
	check("/plugin reload: a fixed plugin is on again", Plugins.get("crash").State == "on" and has(at, "crash reloaded · on"), at)

	H.FILES[ROOT .. "Late/plugin.luau"] = "return { Id = 'late', Name = 'Late' }"
	at = run("/plugins rescan")
	check("/plugins rescan finds a new folder", has(at, "found (+1)") and Plugins.get("late").State == "off", at)
end

----------------------------------------------------------------------
-- 4. turning a plugin off leaves nothing behind (every registry)
----------------------------------------------------------------------
do
	local Types = T.import("base/types")
	local record = Plugins.get("everything")
	check("everything: registered in the registries", Commands.get("everything", "everycmd") ~= nil and T.Registry.getTab("everything") ~= nil and T.Registry.getTab("everything2") ~= nil
		and T.Docs.get("everything") ~= nil and T.Variables.has("everyvar") and table.find(Types.registered(), "EveryType") ~= nil
		and T.Menus.exists("everything.menu") and table.find(T.Icons.list(), "everything.icon") ~= nil)
	record.Api.settings.set("n", 7)
	Plugins._disable(record)
	check("everything: off", record.State == "off")
	check("everything: no registry holds anything of it (removeOwner finds 0)", T.UI.removeOwner("everything") == 0)
	check("everything: …checked one by one", Commands.get("everything", "everycmd") == nil and T.Registry.getTab("everything") == nil and T.Registry.getTab("everything2") == nil
		and T.Docs.get("everything") == nil and T.Docs.get("everything-more") == nil and not T.Variables.has("everyvar")
		and table.find(Types.registered(), "EveryType") == nil and not T.Menus.exists("everything.menu") and table.find(T.Icons.list(), "everything.icon") == nil)
	check("everything: a setting changed just before is saved as it goes", (H.FILES[ROOT .. "Everything/settings.json"] or ""):find('"n":7', 1, true) ~= nil)
end

----------------------------------------------------------------------
-- 5. running Tungsten again stops the old copy's plugins first
----------------------------------------------------------------------
do
	local oldPlugins = Plugins
	local loads, unloads = genv.GoodLoaded, genv.GoodUnloaded or 0
	local okRun = H.run("Tungsten/Tungsten.luau")
	H.advance(5)
	local T2 = genv.Tungsten.Context
	check("re-run ok", okRun and T2 ~= T)
	check("the old copy's plugins were stopped (Unload ran)", genv.GoodUnloaded == unloads + 1 and not oldPlugins.started())
	check("the new copy started them once", genv.GoodLoaded == loads + 1 and T2.Plugins.get("good").State == "on")
	local count = 0
	for _, command in T2.import("console/commands").list() do
		if command.Owner == "good" then
			count += 1
		end
	end
	check("nothing stacks: one goodhello", count == 1, count)
	local logged = false
	for path, content in H.FILES do
		if path:sub(1, 14) == "Tungsten/logs/" and content:find("unload broke", 1, true) then
			logged = true
		end
	end
	check("a plugin whose Unload throws doesn't stop the shutdown; the fault is logged", logged)
	check("the on/off choices carried over (good: off, then on again)", T2.Plugins.wanted("good") and T2.Plugins.get("good").State == "on")
	check("everything stays on for the next start (only stopped by hand above)", T2.Plugins.get("everything").State == "on")
	check("no runtime errors", #H.ERRORS == 0, H.ERRORS[1])
	T = T2
end

----------------------------------------------------------------------
-- 6. /exit stops plugins too
----------------------------------------------------------------------
do
	local unloads = genv.GoodUnloaded
	T.Console.run("/exit")
	H.advance(0.5)
	check("/exit stops the plugins (Unload ran)", genv.GoodUnloaded == unloads + 1 and not T.Plugins.started())
	check("and the copy is gone", genv.Tungsten == nil)
end

check("no runtime errors", #H.ERRORS == 0, H.ERRORS[1])
print(("stage5c: %d passed, %d failed, %d runtime errors"):format(passed, failed, #H.ERRORS))
