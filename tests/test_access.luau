-- The path bar for values inside scripts: functions and tables are shown by
-- how they are reached, e.g. require(game.ReplicatedStorage.Combat).Weapons.
-- Sword.swing (base/access), Copy gives that code, typed and /load paths
-- take it, and the script viewer's Look into it passes it on.
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
local new = E_.Instance.new
local function make(class, name, parent)
	local o = new(class)
	o.Name = name
	o.Parent = parent
	return o
end
local rs = E_.game:GetService("ReplicatedStorage")
local combat = make("ModuleScript", "Combat", rs)
local unused = make("ModuleScript", "Unused", rs)
local mainScript = make("LocalScript", "Main", E_.workspace)

local function swing() end
local function update() end
local function oddFn() end
local function third() end
local secret = { level = 3 }
H.FN[swing] = { Upvalues = { 10, secret }, Info = { name = "swing" } }
local sword = { swing = swing, damage = 5 }
local combatValue = { Weapons = { Sword = sword }, ["odd key"] = { f = oddFn }, [3] = third }
H.LOADED = { combat }
H.MODULE_VALUES = { [combat] = combatValue, [unused] = { never = true } }
local mainEnv = { update = update, script = mainScript }
H.RUNNING = { mainScript }
H.SENV = { [mainScript] = mainEnv }

local ok, err = H.run("Tungsten/Tungsten.luau")
check("loader runs", ok, err)
H.advance(5)
local T = genv.Tungsten.Context
local A, P, Loaded, C = T.Access, T.PathBar, T.Loaded, T.Console

----------------------------------------------------------------------
-- 1. base/access
----------------------------------------------------------------------
check("T.Access is base/access", A ~= nil and A == T.import("base/access"))
local found = A.find(swing)
check("a function in a required module's table is found", found ~= nil and A.code(found) == "require(game.ReplicatedStorage.Combat).Weapons.Sword.swing", found and A.code(found))
check("…as crumbs: require(), Weapons, Sword, swing", found and table.concat((function()
	local out = {}
	for _, c in A.crumbs(found) do
		table.insert(out, c.Text)
	end
	return out
end)(), ",") == "require(),Weapons,Sword,swing")
local foundEnv = A.find(update)
check("a running script's global function: getsenv(...)", foundEnv ~= nil and A.code(foundEnv) == "getsenv(game.Workspace.Main).update", foundEnv and A.code(foundEnv))
check("odd keys are written as code", A.find(oddFn) and A.code(A.find(oddFn)) == 'require(game.ReplicatedStorage.Combat)["odd key"].f', A.find(oddFn) and A.code(A.find(oddFn)))
check("number keys", A.find(third) and A.code(A.find(third)) == "require(game.ReplicatedStorage.Combat)[3]", A.find(third) and A.code(A.find(third)))
check("the module's value itself", A.find(combatValue) and A.code(A.find(combatValue)) == "require(game.ReplicatedStorage.Combat)")
check("a value nobody reaches: nil", A.find(function() end) == nil)
local function walk(list)
	local o = {}
	for _, c in list do
		table.insert(o, c.Text)
	end
	return table.concat(o, ",")
end
local up = A.upvalue(found, 2)
check("an upvalue step", A.code(up) == "debug.getupvalues(require(game.ReplicatedStorage.Combat).Weapons.Sword.swing)[2]" and walk(A.crumbs(up)) == "require(),Weapons,Sword,swing,upvalue 2", A.code(up))
local okR, value = A.resolve(up)
check("…resolves", okR and value == secret)

-- parsing: only walked, never run
local parsed, why = A.parse("require(game.ReplicatedStorage.Combat).Weapons.Sword.swing")
check("parse a require path", parsed and select(2, A.resolve(parsed)) == swing, why)
parsed = A.parse("require(game:GetService(\"ReplicatedStorage\").Combat)['odd key'][\"f\"]")
check("parse quotes and GetService", parsed and select(2, A.resolve(parsed)) == oddFn)
parsed = A.parse("debug.getupvalues(require(game.ReplicatedStorage.Combat).Weapons.Sword.swing)[2].level")
check("parse an upvalue and a key after it", parsed and select(2, A.resolve(parsed)) == 3)
parsed = A.parse("getsenv(game.Workspace.Main).update")
check("parse getsenv", parsed and select(2, A.resolve(parsed)) == update)
check("round trip: parse(code(x)) reaches the same value", select(2, A.resolve(A.parse(A.code(A.find(oddFn))))) == oddFn)
local bad, badWhy = A.parse("require(game.Workspace.Main)")
check("require on a LocalScript is refused", bad == nil and tostring(badWhy):find("getsenv", 1, true) ~= nil, badWhy)
bad, badWhy = A.parse("require(game.ReplicatedStorage.Combat).Weapons:Destroy()")
check("method calls are refused (not run)", bad == nil, badWhy)
local requiredBefore = H.REQUIRED or 0
local unusedAccess = A.parse("require(game.ReplicatedStorage.Unused).never")
local okU, whyU = A.resolve(unusedAccess)
check("a module the game hasn't required isn't required", not okU and tostring(whyU):find("hasn't been required", 1, true) ~= nil and (H.REQUIRED or 0) == requiredBefore, whyU)

----------------------------------------------------------------------
-- 2. the path bar
----------------------------------------------------------------------
local function crumbs()
	local list = {}
	for _, c in P.Crumbs:GetChildren() do
		if c.Name:sub(1, 5) == "Crumb" then
			local text = c:FindFirstChild("Text")
			table.insert(list, { Order = c.LayoutOrder, Text = if text then text.Text else c.Name, Name = c.Name })
		end
	end
	table.sort(list, function(a, b)
		return a.Order < b.Order
	end)
	local out = {}
	for _, c in list do
		table.insert(out, c.Text)
	end
	return table.concat(out, " › "), list
end
Loaded.load({ Loaded.target(swing) })
H.advance(0.2)
local text, list = crumbs()
check("a function loaded with no path: its path is found and shown", text == "game › ReplicatedStorage › Combat › require() › Weapons › Sword › swing", text)
check("…the last crumb is the value", list[#list].Name == "Crumb_value")
local items = P.menuItems()
local copyItem
for _, item in items do
	if item.Text == "Copy" then
		copyItem = item
	end
end
check("Copy is on for it", copyItem and not copyItem.Disabled)
copyItem.Callback()
check("…and copies the code", H.CLIPBOARD == "require(game.ReplicatedStorage.Combat).Weapons.Sword.swing", H.CLIPBOARD)
for _, item in P.menuItems() do
	if item.Text == "Highlight" then
		check("Highlight is on (it selects the script)", not item.Disabled)
		item.Callback()
	end
end
H.advance(0.5)
local selection = T.Explorer.getSelection()
check("…the module is selected", selection[1] == combat)

-- a step crumb loads that table, still with its path
local stepCrumb = P.Crumbs:FindFirstChild("Crumb_step1")
check("a crumb per step", stepCrumb ~= nil)
H.clickObject(stepCrumb)
H.advance(0.2)
check("clicking Weapons loads that table", Loaded.value() == combatValue.Weapons and (crumbs()) == "game › ReplicatedStorage › Combat › require() › Weapons", (crumbs()))
H.clickObject(P.Crumbs:FindFirstChild("Crumb_step0"))
H.advance(0.2)
check("clicking require() loads what the module returns", Loaded.value() == combatValue and (crumbs()) == "game › ReplicatedStorage › Combat › require()", (crumbs()))
check("back still works through them", Loaded.back() and Loaded.value() == combatValue.Weapons)

-- typing a path
P.edit()
H.advance(0.1)
check("editing a value in a script starts with its code", P.EditBox.Text == "require(game.ReplicatedStorage.Combat).Weapons", P.EditBox.Text)
local okGo = P.go("require(game.ReplicatedStorage.Combat).Weapons.Sword.swing")
H.advance(0.2)
check("a typed require path loads it", okGo and Loaded.value() == swing and (crumbs()):sub(-5) == "swing", (crumbs()))
local target = Loaded.get()
check("…as a target with that path", Loaded.isTarget(target) and target.Access ~= nil and A.code(target.Access):find("Sword.swing", 1, true) ~= nil)
local okBad, whyBad = P.go("require(game.ReplicatedStorage.Unused).never")
H.advance(0.1)
check("a module not required yet: says why, nothing loaded", not okBad and Loaded.value() == swing and tostring(whyBad):find("hasn't been required", 1, true) ~= nil, whyBad)
P.cancelEdit()
okGo = P.go("debug.getupvalues(require(game.ReplicatedStorage.Combat).Weapons.Sword.swing)[2]")
H.advance(0.2)
check("a typed upvalue path", okGo and Loaded.value() == secret and (crumbs()):sub(-9) == "upvalue 2", (crumbs()))

-- /load
C.run("/load require(game.ReplicatedStorage.Combat)[\"odd key\"].f")
H.advance(0.2)
check("/load takes a require path", Loaded.value() == oddFn and (crumbs()):find("odd key", 1, true) ~= nil, (crumbs()))
C.run("/load getsenv(game.Workspace.Main).update")
H.advance(0.2)
check("/load takes a getsenv path", Loaded.value() == update and (crumbs()) == "game › Workspace › Main › getsenv() › update", (crumbs()))
T.Explorer.clearSelection()
C.run("/load")
H.advance(0.1)
local lastLine = C.Lines[#C.Lines] and C.Lines[#C.Lines].Plain or ""
check("/load with nothing says the path as code", lastLine:find("getsenv(game.Workspace.Main).update", 1, true) ~= nil, lastLine)

-- a value nobody reaches: one crumb as before; Copy greyed
local loose = function() end
Loaded.load({ Loaded.target(loose, { Label = "function loose" }) })
H.advance(0.2)
check("a value with no path: one crumb as before", (crumbs()) == "function loose", (crumbs()))
for _, item in P.menuItems() do
	if item.Text == "Copy" then
		check("…Copy greyed", item.Disabled == true)
	end
end

----------------------------------------------------------------------
-- 3. the script viewer passes the path on
----------------------------------------------------------------------
local record = T.Plugins.get("scriptviewer")
local api, exports = record.Api, record.Exports
check("api.loaded.access for plugins", api.loaded.access ~= nil and api.loaded.access.code ~= nil)
T.Tabs:Select("scriptviewer")
H.advance(0.4)
Loaded.load({ combat })
H.advance(0.3)
local view = exports.view()
view:Select("contents")
H.advance(0.3)
local contents = view.Panels.contents
local weaponsRow
for _, node in contents.List:GetItems() do
	if node.RawKey == "Weapons" then
		weaponsRow = node
	end
end
check("a module's Contents row", weaponsRow ~= nil)
for _, item in T.Menus.build("scriptviewer.row", { Item = weaponsRow, Panel = "contents", View = view }) do
	if item.Text == "Look into it" then
		item.Callback()
	end
end
H.advance(0.3)
check("Look into it: the path bar shows where it is", Loaded.value() == combatValue.Weapons and (crumbs()) == "game › ReplicatedStorage › Combat › require() › Weapons", (crumbs()))
view:Select("contents")
H.advance(0.3)
local swordRow
for _, node in view.Panels.contents.List:GetItems() do
	if node.RawKey == "Sword" then
		swordRow = node
	end
end
for _, item in T.Menus.build("scriptviewer.row", { Item = swordRow, Panel = "contents", View = view }) do
	if item.Text == "Look into it" then
		item.Callback()
	end
end
H.advance(0.3)
check("…and again one deeper", (crumbs()) == "game › ReplicatedStorage › Combat › require() › Weapons › Sword", (crumbs()))
Loaded.load({ Loaded.target(swing) })
H.advance(0.3)
view:Select("upvalues")
H.advance(0.3)
local secretRow
for _, node in view.Panels.upvalues.List:GetItems() do
	if node.Value == secret then
		secretRow = node
	end
end
for _, item in T.Menus.build("scriptviewer.row", { Item = secretRow, Panel = "upvalues", View = view }) do
	if item.Text == "Look into it" then
		item.Callback()
	end
end
H.advance(0.3)
check("an upvalue: …› swing › upvalue 2", Loaded.value() == secret and (crumbs()) == "game › ReplicatedStorage › Combat › require() › Weapons › Sword › swing › upvalue 2", (crumbs()))

print(("access: %d passed, %d failed, 0 runtime errors"):format(passed, failed))
