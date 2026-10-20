-- Stage 5 Round C, part 1: the api a plugin builds with. Owners set for
-- it on everything it registers; owned listeners and threads (connect,
-- spawn, delay, every, bin) stopped with it and guarded; api.files in its
-- folder; owned explorer signals; nothing left behind.
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
local prefix = "fixtures/plugins/Helper/"
for path, content in H.FILES do
	if path:sub(1, #prefix) == prefix then
		H.FILES[ROOT .. "Helper/" .. path:sub(#prefix + 1)] = content
	end
end
H.FILES["Tungsten/base/plugins.json"] = '{"On":["helper"]}'
local part = H.part("Thing", E_.workspace)

local ok, err = H.run("Tungsten/Tungsten.luau")
check("loader runs", ok, err)
local T = genv.Tungsten.Context
local Plugins = T.Plugins
local C = T.Console
check("helper is on", Plugins.get("helper") and Plugins.get("helper").State == "on", Plugins.get("helper") and Plugins.get("helper").Problem)
local api = genv.HelperApi

local function lines(from)
	local out = {}
	for index = from or 1, #C.Lines do
		table.insert(out, C.Lines[index].Plain)
	end
	return table.concat(out, "\n")
end

----------------------------------------------------------------------
-- 1. owned listeners and threads
----------------------------------------------------------------------
do
	genv.HelperSignal:Fire("x")
	check("api.connect: the listener runs", genv.HelperHeard == 1)
	local before = #C.Lines
	genv.HelperSignal:Fire("boom")
	check("api.connect: a fault prints under the plugin's name", lines(before + 1):find("[x] Helper: a connection failed: ", 1, true) ~= nil and lines(before + 1):find("connection broke", 1, true) ~= nil, lines(before + 1))
	genv.HelperSignal:Fire("y")
	check("…and the listener keeps working", genv.HelperHeard == 2)
	check("…the fault is counted", Plugins.get("helper").Faults >= 1)
	H.advance(1)
	check("api.spawn: the thread ran", genv.HelperSpawned == true)
	H.advance(3)
	check("api.every: runs every second", genv.HelperTicks >= 3, genv.HelperTicks)
	local ticks = genv.HelperTicks
	genv.HelperEvery.Stop()
	H.advance(3)
	check("api.every: Stop stops it", genv.HelperTicks == ticks)
	T.Explorer.select({ part })
	H.advance(0.1)
	check("explorer.SelectionChanged:Connect works", genv.HelperSel >= 1)
end

----------------------------------------------------------------------
-- 2. owners set for the plugin
----------------------------------------------------------------------
do
	check("api.ui.new: Origin is the plugin", genv.HelperButton and (genv.HelperButton.Origin == "helper" or genv.HelperButton.Props and genv.HelperButton.Props.Origin == "helper"))
	local menuOwned = 0
	for _, entry in T.Menus.entries("helper.menu") do
		if entry.Owner == "helper" then
			menuOwned += 1
		end
	end
	check("api.menus.addMany: owned entries", menuOwned == 2)
	check("api.menus.remove", api.menus.remove("helper.menu", "b") and #T.Menus.entries("helper.menu") == 1)

	local handle = api.prompt.confirm({ Title = "Helper?" })
	H.advance(0.2)
	check("api.prompt: Origin is the plugin", handle and handle.Origin == "helper")
	T.Overlay.closeAll()
	H.advance(0.2)
	local toast = api.notify.show("from helper")
	check("api.notify.show takes text", toast ~= nil)
	check("api.docs.open opens a topic in the Documentation tab", api.docs.open("helper") and T.Tabs.Selected == "documentation")
	T.Tabs:Select("console")
	H.advance(0.2)
	check("api.types reads like Types", api.types.parse ~= nil and table.find(T.import("base/types").registered(), "HelperType") ~= nil)
end

----------------------------------------------------------------------
-- 3. files in the plugin's folder
----------------------------------------------------------------------
do
	check("files.path", api.files.path("a.txt") == "Tungsten/plugins/Helper/a.txt" and api.files.path() == "Tungsten/plugins/Helper")
	api.files.write("notes/a.txt", "one")
	check("files.write / read", api.files.read("notes/a.txt") == "one" and H.FILES["Tungsten/plugins/Helper/notes/a.txt"] == "one")
	api.files.append("notes/a.txt", " two")
	api.files.append("notes/b.txt", "new")
	check("files.append (and makes the file)", api.files.read("notes/a.txt") == "one two" and api.files.read("notes/b.txt") == "new")
	check("files.exists / isFolder", api.files.exists("notes/a.txt") and api.files.isFolder("notes") and not api.files.exists("nope.txt"))
	local names = api.files.list("notes")
	check("files.list gives names", #names == 2 and names[1] == "a.txt" and names[2] == "b.txt", table.concat(names, ","))
	api.files.delete("notes/b.txt")
	check("files.delete a file", not api.files.exists("notes/b.txt"))
	api.files.delete("notes")
	check("files.delete a folder", not api.files.exists("notes") and H.FILES["Tungsten/plugins/Helper/notes/a.txt"] == nil)
	local console = T.api("consoletest", { Name = "Console test" })
	local okFiles, why = pcall(console.files.read, "x")
	check("an api made in the console has no folder", not okFiles and tostring(why):find("no plugin folder", 1, true) ~= nil, why)
	console:remove()
end

----------------------------------------------------------------------
-- 4. stopping takes everything
----------------------------------------------------------------------
do
	local heard = genv.HelperHeard
	local sel = genv.HelperSel
	Plugins._disable(Plugins.get("helper"))
	check("off", Plugins.get("helper").State == "off")
	genv.HelperSignal:Fire("x")
	check("its connections ended", genv.HelperHeard == heard)
	T.Explorer.select({})
	H.advance(0.1)
	check("its explorer listener ended", genv.HelperSel == sel)
	check("its delayed call hadn't run yet", genv.HelperDelayed == false)
	H.advance(62)
	check("…and never runs now", genv.HelperDelayed == false)
	check("its bin was cleaned", genv.HelperBinCleaned == true)
	check("no registry holds anything of it (removeOwner finds 0)", T.UI.removeOwner("helper") == 0)
	check("…its insert and filter groups, editor, type, class, picker kind, row kind, field kind, toast kind, docs, menus and icon are gone",
		table.find(T.import("base/types").registered(), "HelperType") == nil and not T.Menus.exists("helper.menu") and T.Docs.get("helper") == nil
		and table.find(T.Icons.list(), "helper.icon") == nil)
	local okDead, deadWhy = pcall(api.spawn, function() end)
	check("its api can't start anything now", not okDead and tostring(deadWhy):find("was unloaded", 1, true) ~= nil, deadWhy)
end

check("no runtime errors", #H.ERRORS == 0, H.ERRORS[1])
print(("stage5g: %d passed, %d failed, %d runtime errors"):format(passed, failed, #H.ERRORS))
