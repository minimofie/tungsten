-- Plugins stage, round P0a: one loaded target for every tab (base/loaded),
-- the path bar showing it (several, values that aren't Instances), /load,
-- api.loaded / api.pathbar for plugins, Tab.OnLoad in plugin definitions,
-- the new prime order, Uses (soft dependency) and api.plugins.open.
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
local new = E_.Instance.new
local function make(class, name, parent)
	local o = new(class)
	o.Name = name
	o.Parent = parent
	return o
end
local map = make("Model", "Map", E_.workspace)
local door = make("Part", "Door", map)
local lamp = make("Part", "Lamp", map)
local doorScript = make("LocalScript", "DoorScript", door)
local spare = make("Part", "Spare", map)

-- plugin folders for part 6
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
install("Viewer", "Linker", "Overreach", "Scanner", "Good")
H.FILES["Tungsten/base/plugins.json"] = '{"On":["scriptviewer","linker","overreach","good"]}'

local ok, err = H.run("Tungsten/Tungsten.luau")
check("loader runs", ok, err)
H.advance(5)
local T = genv.Tungsten.Context
check("no errors at start", #H.ERRORS == 0, H.ERRORS[1])
local E, P, C, Loaded, Plugins = T.Explorer, T.PathBar, T.Console, T.Loaded, T.Plugins

local function lines(from)
	local out = {}
	for index = from or 1, #C.Lines do
		table.insert(out, C.Lines[index].Plain)
	end
	return table.concat(out, "\n")
end
local function has(at, text)
	return lines(at):find(text, 1, true) ~= nil
end
local function crumbs()
	local list = {}
	for _, c in P.Crumbs:GetChildren() do
		if c.Name:sub(1, 5) == "Crumb" then
			table.insert(list, c)
		end
	end
	table.sort(list, function(a, b)
		return a.LayoutOrder < b.LayoutOrder
	end)
	local out = {}
	for _, c in list do
		table.insert(out, c:FindFirstChild("Text").Text)
	end
	return table.concat(out, " > ")
end
local function more()
	local label = P.Crumbs:FindFirstChild("More")
	return label and label.Text
end
local function menuDisabled(text)
	for _, item in P.menuItems() do
		if item.Text == text then
			return item.Disabled == true
		end
	end
	return nil
end

----------------------------------------------------------------------
-- 1. one loaded target, every tab told
----------------------------------------------------------------------
do
	local told = {}
	local order = {}
	for _, id in { "one", "two" } do
		T.Registry.addTab({
			Id = id,
			Title = id,
			Owner = "core",
			Build = function() end,
			OnLoad = function(values, tab, items)
				told[id] = { Values = values, Items = items, Tab = tab }
				table.insert(order, id)
				return id == "two"
			end,
		})
	end
	H.advance(0.2)
	T.Tabs:Select("two")
	H.advance(0.3)
	local at = #C.Lines + 1
	local handled = E.load({ door, lamp })
	H.advance(0.2)
	check("every tab is told, open or not", told.one and told.two and #told.one.Values == 2 and told.one.Values[1] == door)
	check("the open tab is told first", order[1] == "two", table.concat(order, ","))
	check("handled = what the open tab answered", handled == true)
	check("the console got it too ($loaded holds both)", type(T.Variables.get("loaded")) == "table" and #T.Variables.get("loaded") == 2)
	check("the explorer reports it without a tab name", has(at, "loaded 2 objects") and not has(at, "into"), lines(at))
	check("Loaded.list / get / value", #Loaded.list() == 2 and Loaded.get() == door and Loaded.value() == door)
	check("the path bar shows the first, then +1", crumbs() == "game > Workspace > Map > Door" and more() == "+1", crumbs() .. " " .. tostring(more()))
	T.Tabs:Select("documentation")
	H.advance(0.3)
	check("every tab shows the same path", crumbs() == "game > Workspace > Map > Door" and more() == "+1")
	check("Documentation turned to the class page in the background", T.Docs.View == nil or (T.Docs.View.Current and T.Docs.View.Current.Title == "Part"), T.Docs.View and T.Docs.View.Current and T.Docs.View.Current.Title)
	T.Tabs:Select("console")
	H.advance(0.3)
	-- a tab whose OnLoad fails: reported, the others still told
	T.Registry.updateTab("one", { OnLoad = function() error("one broke") end })
	table.clear(told)
	at = #C.Lines + 1
	E.load({ lamp })
	H.advance(0.2)
	check("a failing OnLoad is reported", has(at, "OnLoad of tab 'one'") and has(at, "one broke"), lines(at))
	check("…and the others are still told", told.two and told.two.Values[1] == lamp)
	check("one object: no +N", more() == nil)
	T.Registry.removeTab("one")
	T.Registry.removeTab("two")
	H.advance(0.2)
end

----------------------------------------------------------------------
-- 2. values that aren't Instances
----------------------------------------------------------------------
do
	local function onTouched() end
	local target = Loaded.target(onTouched, { Origin = doorScript })
	check("a target: kind from the value, label from its name", target.Kind == "function" and target.Label == "function onTouched", target.Label)
	check("Loaded.isTarget", Loaded.isTarget(target) and not Loaded.isTarget(door) and not Loaded.isTarget({}))
	check("an Instance isn't wrapped", not pcall(Loaded.target, door))
	check("a raw value isn't loaded without a target", not pcall(Loaded.load, { onTouched }))
	Loaded.load(target)
	H.advance(0.2)
	check("path bar: the script it came from, then the value", crumbs() == "game > Workspace > Map > Door > DoorScript > function onTouched", crumbs())
	check("the value's crumb is the last (highlighted) one", P.Crumbs:FindFirstChild("Crumb_value") ~= nil)
	check("$loaded holds the function itself", T.Variables.get("loaded") == onTouched)
	check("Copy and Highlight are greyed for a value", menuDisabled("Copy") == true and menuDisabled("Highlight") == true)
	check("Loaded.value gives the value, get the target", Loaded.value() == onTouched and Loaded.get() == target)
	local data = { a = 1 }
	Loaded.load(Loaded.target(data, { Label = "settings table" }))
	H.advance(0.2)
	check("a value with no origin: one crumb", crumbs() == "settings table", crumbs())
	check("a table target's kind", Loaded.get().Kind == "table")
	P.edit()
	H.advance(0.1)
	check("editing a value with no origin starts at game.", P.EditBox.Text == "game.", P.EditBox.Text)
	P.cancelEdit()
	H.advance(0.1)
	-- a mix: an Instance first, then a value
	Loaded.load({ spare, Loaded.target(data) })
	H.advance(0.2)
	check("a mix shows the first and +1", crumbs() == "game > Workspace > Map > Spare" and more() == "+1", crumbs())
	check("Copy works again for an Instance", menuDisabled("Copy") == false)
end

----------------------------------------------------------------------
-- 3. destroyed objects drop out; loads made while tabs are told
----------------------------------------------------------------------
do
	local a = make("Part", "Gone1", map)
	local b = make("Part", "Gone2", map)
	E.load({ a, b })
	H.advance(0.2)
	local whoCleared
	local conn = Loaded.Changed:Connect(function(items, by)
		whoCleared = by
	end)
	a:Destroy()
	H.advance(0.2)
	check("a destroyed object drops out of the list", #Loaded.list() == 1 and Loaded.get() == b, #Loaded.list())
	check("…the path bar follows", crumbs() == "game > Workspace > Map > Gone2" and more() == nil, crumbs())
	check("…told as Tungsten", whoCleared == "tungsten")
	b:Destroy()
	H.advance(0.2)
	conn:Disconnect()
	check("nothing left: cleared", Loaded.get() == nil and P.Crumbs:FindFirstChild("Empty") ~= nil)
end

----------------------------------------------------------------------
-- 4. /load
----------------------------------------------------------------------
do
	local at = #C.Lines + 1
	C.run("/load game.Workspace.Map.Lamp")
	H.advance(0.2)
	check("/load <path>", Loaded.get() == lamp and has(at, "loaded Lamp"), lines(at))
	at = #C.Lines + 1
	C.run("/load")
	H.advance(0.2)
	if #E.getSelection() == 0 then
		check("/load alone says what is loaded", has(at, "loaded: game.Workspace.Map.Lamp"), lines(at))
	else
		check("/load alone loads the selection", Loaded.get() == E.getSelection()[1])
	end
	T.Variables.set("fn", function() end, { Source = "console" })
	at = #C.Lines + 1
	C.run("/load $fn")
	H.advance(0.2)
	check("/load $var with a function loads it as a value", Loaded.isTarget(Loaded.get()) and Loaded.get().Kind == "function" and Loaded.get().Label == "$fn (function)", Loaded.get() and tostring(Loaded.get()))
	T.Variables.set("both", { door, lamp }, { Source = "console" })
	C.run("/load $both")
	H.advance(0.2)
	check("/load $var with Instances loads them", #Loaded.list() == 2 and Loaded.get() == door)
	at = #C.Lines + 1
	C.run("/load none")
	H.advance(0.2)
	check("/load none unloads", Loaded.get() == nil and has(at, "nothing loaded"), lines(at))
	at = #C.Lines + 1
	C.run("/load game.Workspace.Nope")
	H.advance(0.2)
	check("/load with a wrong path fails", has(at, "[x]") and Loaded.get() == nil, lines(at))
end

----------------------------------------------------------------------
-- 5. prime order
----------------------------------------------------------------------
check("prime order: scriptviewer, instanceviewer, scanner", table.concat(Plugins.Prime, ",") == "scriptviewer,instanceviewer,scanner", table.concat(Plugins.Prime, ","))

----------------------------------------------------------------------
-- 6. plugins: Tab.OnLoad, api.loaded, Uses, api.plugins.open
----------------------------------------------------------------------
do
	local function state(id)
		local record = Plugins.get(id)
		return record and record.State
	end
	check("the prime stand-in and the linker are on", state("scriptviewer") == "on" and state("linker") == "on", tostring(state("scriptviewer")) .. "/" .. tostring(state("linker")))
	check("Uses with instanceviewer missing doesn't stop it (soft)", state("linker") == "on")
	local overreach = Plugins.byFolder("Overreach")
	check("Uses naming a non-prime plugin is a problem", overreach and overreach.State == "problem" and overreach.Problem:find("Uses can only name the prime plugins", 1, true) ~= nil, overreach and overreach.Problem)
	local api = genv.LinkerApi
	check("linker's api is there", api ~= nil)

	-- a plugin tab's OnLoad gets every load
	genv.ViewerLoads = 0
	E.load({ door })
	H.advance(0.2)
	check("Tab.OnLoad in a definition gets loads", genv.ViewerLoads == 1 and genv.ViewerGot[1] == door and genv.LinkerGot[1] == door)
	check("…while its tab isn't open", genv.ViewerOpenWhenLoaded == false)

	-- api.loaded
	local by
	local conn = api.loaded.Changed:Connect(function(_, who)
		by = who
	end)
	local function helper() end
	api.loaded.set(api.loaded.target(helper, { Label = "helper" }))
	H.advance(0.2)
	check("api.loaded.set loads as the plugin", by == "linker" and api.loaded.value() == helper)
	check("…every tab told (the viewer got the raw value)", genv.ViewerGot[1] == helper and Loaded.isTarget(genv.ViewerItems[1]))
	api.pathbar.show(lamp, "linker", "whatever")
	H.advance(0.2)
	check("api.pathbar.show = load (old arguments ignored)", Loaded.get() == lamp and by == "linker")
	api.loaded.clear()
	H.advance(0.2)
	check("api.loaded.clear", Loaded.get() == nil and by == "linker")
	conn:Disconnect()

	-- a load made while tabs are being told runs right after
	genv.LinkerReload, genv.LinkerReloadWith = 1, spare
	E.load({ door })
	H.advance(0.2)
	check("a load made inside OnLoad runs after the first", Loaded.get() == spare, Loaded.get() and tostring(Loaded.get()))
	-- a tab that always loads again doesn't loop forever
	genv.LinkerReload = 100
	E.load({ door })
	H.advance(0.3)
	check("endless reloads stop", genv.LinkerReload > 80, genv.LinkerReload)
	genv.LinkerReload = nil
	-- a plugin's failing OnLoad: a fault under its name
	genv.LinkerFail = true
	local faults = Plugins.get("linker").Faults or 0
	local at = #C.Lines + 1
	E.load({ lamp })
	H.advance(0.2)
	genv.LinkerFail = nil
	check("a plugin's failing OnLoad is reported under its name", has(at, "[x] Linker:") and has(at, "linker OnLoad broke"), lines(at))
	check("…and counted", (Plugins.get("linker").Faults or 0) == faults + 1)

	-- soft links
	local exports, why = api.plugins.get("scriptviewer")
	check("get: a used prime that is on", type(exports) == "table" and type(exports.reveal) == "function", why)
	local none, whyMissing = api.plugins.get("instanceviewer")
	check("get: a used prime that isn't installed -> nil + why", none == nil and whyMissing:find("isn't installed", 1, true) ~= nil, whyMissing)
	local _, notListed = api.plugins.get("scanner")
	check("get: a prime it doesn't list -> nil + why", notListed:find("Requires or Uses", 1, true) ~= nil, notListed)
	check("isOn", api.plugins.isOn("scriptviewer") and not api.plugins.isOn("instanceviewer"))

	T.Tabs:Select("console")
	H.advance(0.3)
	local okOpen, whyOpen = api.plugins.open("scriptviewer", { Target = "x", Panel = "constants" })
	H.advance(0.3)
	check("open: switches to the prime's tab", okOpen and T.Tabs.Selected == "scriptviewer", whyOpen)
	check("…and calls its reveal with the focus", genv.ViewerRevealed and genv.ViewerRevealed.Panel == "constants")
	check("…after the tab opened", genv.ViewerOpenOnReveal == true)
	local okMissing, whyMissingOpen = api.plugins.open("instanceviewer", {})
	check("open: a prime that isn't there -> false + why", okMissing == false and whyMissingOpen:find("isn't installed", 1, true) ~= nil, whyMissingOpen)
	at = #C.Lines + 1
	local okFail, whyFail = api.plugins.open("scriptviewer", { Fail = true })
	H.advance(0.2)
	check("open: a failing reveal -> false + why, reported under the prime", okFail == false and whyFail:find("can't reveal that", 1, true) ~= nil and has(at, "[x] Script Viewer:"), lines(at))
	check("open as the user (console) reaches any prime", Plugins.open("you", "scriptviewer", { Panel = "upvalues" }) and genv.ViewerRevealed.Panel == "upvalues")
	check("a plugin can't open a prime it doesn't list", select(2, Plugins.open("good", "scriptviewer", {})):find("Requires or Uses", 1, true) ~= nil)
	T.Tabs:Select("console")
	H.advance(0.3)
end

----------------------------------------------------------------------
-- 7. clean run
----------------------------------------------------------------------
do
	check("no runtime errors", #H.ERRORS == 0, H.ERRORS[1])
end

for _, e in H.ERRORS do
	print("ERR: " .. e)
end
print(("p0a: %d passed, %d failed, %d runtime errors"):format(passed, failed, #H.ERRORS))
