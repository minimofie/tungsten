-- Script Viewer revamp, menus: "Inspect" (it replaced "Look into it")
-- loads a row's table, function or Instance and opens the sub-tab that
-- fits; "Copy path" shows only where Inspect applies and a real path
-- exists, and copies code that reaches the value.
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
local rs = E_.game:GetService("ReplicatedStorage")
local module = new("ModuleScript")
module.Name = "Combat"
module.Parent = rs
local door = H.part("Door", E_.workspace)

local function running() end
H.FN[running] = { Upvalues = { "u1" }, Info = { name = "running" } }
local settingsTable = { speed = 3 }
local function helper() end
H.FN[helper] = { Upvalues = { 1 }, Info = { name = "helper" } }
local function swing() end
H.FN[swing] = {
	Constants = { "Hit", 5 },
	Upvalues = { settingsTable, door, 7, helper },
	Info = { name = "swing", nups = 4 },
	Protos = { { Info = { name = "inner" }, Constants = { "deep" }, Closures = { running } } },
}
local loose = { inner = { x = 1 } }
H.LOADED = { module }
H.MODULE_VALUES = { [module] = { swing = swing } }

local ok, err = H.run("Tungsten/Tungsten.luau")
check("loader runs", ok, err)
H.advance(5)
local T = genv.Tungsten.Context
local Loaded, P = T.Loaded, T.PathBar
local record = T.Plugins.get("scriptviewer")
local exports, api = record.Exports, record.Api
T.Tabs:Select("scriptviewer")
H.advance(0.4)
local view = exports.view()
local function open(id)
	view:Select(id)
	H.advance(0.3)
	return view.Panels[id]
end
local function row(panel, test)
	for _, node in panel.List:GetItems() do
		if test(node) then
			return node
		end
	end
	return nil
end
local function menu(panel, id, node)
	return T.Menus.build("scriptviewer.row", { Item = node, Panel = id, View = view })
end
local function texts(items)
	local out = {}
	for _, item in items do
		table.insert(out, item.Text)
	end
	return table.concat(out, "|")
end
local function run(items, text)
	for _, item in items do
		if item.Text == text then
			item.Callback()
			H.advance(0.3)
			return true
		end
	end
	return false
end

P.go("require(game.ReplicatedStorage.Combat).swing")
H.advance(0.3)
check("a function with a path is loaded", Loaded.value() == swing and Loaded.get().Access ~= nil)
local upvalues = open("upvalues")
upvalues.Switch:SetValue("Tree")
H.advance(0.2)

----------------------------------------------------------------------
-- 1. What the menu offers
----------------------------------------------------------------------
local tableRow = row(upvalues, function(n)
	return n.Value == settingsTable
end)
local numberRow = row(upvalues, function(n)
	return n.Value == 7
end)
local doorRow = row(upvalues, function(n)
	return n.Value == door
end)
check("a table upvalue: Inspect and Copy path", texts(menu(upvalues, "upvalues", tableRow)):find("Inspect|Keep in a variable…|Copy value|Copy path", 1, true) ~= nil, texts(menu(upvalues, "upvalues", tableRow)))
check("a number upvalue: no Inspect, no Copy path", not texts(menu(upvalues, "upvalues", numberRow)):find("Inspect", 1, true) and not texts(menu(upvalues, "upvalues", numberRow)):find("Copy path", 1, true), texts(menu(upvalues, "upvalues", numberRow)))
check("an Instance upvalue: Inspect and Copy path", texts(menu(upvalues, "upvalues", doorRow)):find("Inspect", 1, true) ~= nil and texts(menu(upvalues, "upvalues", doorRow)):find("Copy path", 1, true) ~= nil)
local constants = open("constants")
local hit = row(constants, function(n)
	return n.Value == "Hit"
end)
check("a constant: no Inspect, no Copy path (it was a bare number before)", texts(menu(constants, "constants", hit)) == "Change value…|Keep in a variable…|Copy value", texts(menu(constants, "constants", hit)))
check("nowhere says Look into it", not texts(menu(upvalues, "upvalues", tableRow)):find("Look into", 1, true))

----------------------------------------------------------------------
-- 2. Copy path copies code
----------------------------------------------------------------------
run(menu(upvalues, "upvalues", tableRow), "Copy path")
check("Copy path of an upvalue: the code reaching it", H.CLIPBOARD == "debug.getupvalues(require(game.ReplicatedStorage.Combat).swing)[1]", H.CLIPBOARD)
run(menu(upvalues, "upvalues", doorRow), "Copy path")
check("Copy path of an Instance: its path", H.CLIPBOARD == "game.Workspace.Door", H.CLIPBOARD)
view:SetScope("upvalues", "With nested functions")
H.advance(0.2)
local copyRow = row(upvalues, function(n)
	return n.Kind == "upvalue" and n.Owner == running
end)
local copyHeading = row(upvalues, function(n)
	return n.Kind == "heading" and n.Value == running
end)
run(menu(upvalues, "upvalues", copyHeading), "Copy path")
check("Copy path of a nested function's running copy", H.CLIPBOARD == "debug.getproto(require(game.ReplicatedStorage.Combat).swing, 1, true)[1]", H.CLIPBOARD)
check("…its upvalue is a number: no Copy path", not texts(menu(upvalues, "upvalues", copyRow)):find("Copy path", 1, true))
view:SetScope("upvalues", "This function")
H.advance(0.2)

----------------------------------------------------------------------
-- 3. Inspect
----------------------------------------------------------------------
tableRow = row(upvalues, function(n)
	return n.Value == settingsTable
end)
run(menu(upvalues, "upvalues", tableRow), "Inspect")
check("Inspect a table: loaded", Loaded.value() == settingsTable)
check("…with its path", Loaded.get().Access ~= nil and T.Access.code(Loaded.get().Access) == "debug.getupvalues(require(game.ReplicatedStorage.Combat).swing)[1]")
check("…and Contents opens", view.Tabs.Selected == "contents", view.Tabs.Selected)
P.back()
H.advance(0.3)
open("upvalues")
local helperRow = row(view.Panels.upvalues, function(n)
	return n.Value == helper
end)
run(menu(view.Panels.upvalues, "upvalues", helperRow), "Inspect")
check("Inspect a function from Upvalues: loaded, Upvalues stays open", Loaded.value() == helper and view.Tabs.Selected == "upvalues", view.Tabs.Selected)
Loaded.load(Loaded.target({ fn = helper, sub = { y = 2 } }, { Label = "cfg" }))
H.advance(0.3)
local contents = open("contents")
local fnRow = row(contents, function(n)
	return n.Value == helper
end)
run(menu(contents, "contents", fnRow), "Inspect")
check("Inspect a function from Contents: Constants opens", Loaded.value() == helper and view.Tabs.Selected == "constants", view.Tabs.Selected)
Loaded.load(Loaded.target(swing))
H.advance(0.3)
open("upvalues")
doorRow = row(view.Panels.upvalues, function(n)
	return n.Value == door
end)
run(menu(view.Panels.upvalues, "upvalues", doorRow), "Inspect")
check("Inspect an Instance: it is loaded", Loaded.get() == door)

-- a value no path reaches: Inspect, but no Copy path
Loaded.load(Loaded.target(loose, { Label = "loose" }))
H.advance(0.3)
contents = open("contents")
local innerRow = row(contents, function(n)
	return n.Key == "inner"
end)
local items = menu(contents, "contents", innerRow)
check("a table nothing reaches: Inspect, no Copy path", texts(items):find("Inspect", 1, true) ~= nil and not texts(items):find("Copy path", 1, true), texts(items))

check("no runtime errors", #H.ERRORS == 0, H.ERRORS[1])
print(("svinspect: %d passed, %d failed, %d runtime errors"):format(passed, failed, #H.ERRORS))
