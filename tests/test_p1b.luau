-- Plugins stage, round 1 part 1.2: the script viewer's Constants, Upvalues
-- and Functions sub-tabs (read-only): Tree and List views, opening
-- tables / functions / nested functions, cycles, empty slots, counts on
-- the pills, the view kept in the plugin's settings.
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

local door = H.part("Door", E_.workspace)
local doorScript = E_.Instance.new("LocalScript")
doorScript.Name = "DoorScript"
doorScript.Parent = door

local function helper() end
H.FN[helper] = { Upvalues = { "x", 2 } }
local settingsTable = { speed = 3, nested = { a = 1 }, [1] = "first" }
local loop = { name = "loop" }
loop.self = loop
local big = {}
for index = 1, 600 do
	big["k" .. string.format("%03d", index)] = index
end
local function onTouched() end
H.FN[onTouched] = {
	Constants = { [1] = "Touched", [2] = 5, [4] = "Humanoid" },
	Upvalues = { door, settingsTable, helper, loop, big },
	Protos = {
		{ Info = { name = "inner", numparams = 1, nups = 2 }, Constants = { "a" }, Protos = { { Info = { name = "deep", numparams = 0, nups = 0 } } } },
		{ Info = { name = "", numparams = 0, nups = 0 } },
	},
}
local function scriptMain() end
H.FN[scriptMain] = { Constants = { "x" } }
H.SCRIPT_CLOSURES = { [doorScript] = scriptMain }

local ok, err = H.run("Tungsten/Tungsten.luau")
check("loader runs", ok, err)
H.advance(5)
local T = genv.Tungsten.Context
local Plugins, Loaded = T.Plugins, T.Loaded
local record = Plugins.get("scriptviewer")
check("the script viewer is on", record and record.State == "on", record and record.State)
local exports = record.Exports
local api = record.Api

Loaded.load(Loaded.target(onTouched))
H.advance(0.2)
T.Tabs:Select("scriptviewer")
H.advance(0.4)
local view = exports.view()
check("the view is built", view ~= nil)

local function badge(id)
	local pill = H.find(view.Tabs.Instance, "Tab_" .. id)
	local b = pill and H.find(pill, "Badge")
	return if b and b.Visible then H.find(b, "Text").Text else nil
end
local function open(id)
	view:Select(id)
	H.advance(0.3)
	return view.Panels[id]
end
local function names(panel)
	local out = {}
	for _, node in panel.List:GetItems() do
		table.insert(out, node.Key)
	end
	return table.concat(out, ",")
end
local function find(panel, key, depth)
	for _, node in panel.List:GetItems() do
		if node.Key == key and (depth == nil or node.Depth == depth) then
			return node
		end
	end
	return nil
end

----------------------------------------------------------------------
-- 1. sub-tabs and counts
----------------------------------------------------------------------
check("five sub-tabs, Source first, no Overview", table.concat(view.Tabs.Order, ",") == "source,constants,upvalues,functions,contents", table.concat(view.Tabs.Order, ","))
check("counts on the pills before they open", badge("constants") == "3" and badge("upvalues") == "5" and badge("functions") == "2", tostring(badge("constants")) .. "/" .. tostring(badge("upvalues")) .. "/" .. tostring(badge("functions")))
check("the panels aren't built until they open", view.Panels.constants == nil)

----------------------------------------------------------------------
-- 2. constants
----------------------------------------------------------------------
local constants = open("constants")
check("constants: one row per constant, in order (empty slot left out)", names(constants) == "1,2,4", names(constants))
check("…with types and values", find(constants, "1").Type == "string" and find(constants, "1").ValueText == "Touched" and find(constants, "2").ValueText == "5")
check("…and a count", constants.Info.Text == "3 constants", constants.Info.Text)
api.settings.set("showEmpty", true)
H.advance(0.2)
check("Show empty constant slots: slot 3 appears, marked", names(constants) == "1,2,3,4" and find(constants, "3").ValueText == "(empty slot)", names(constants))
api.settings.set("showEmpty", false)
H.advance(0.2)
check("…and goes again", names(constants) == "1,2,4")

----------------------------------------------------------------------
-- 3. upvalues: tables, functions, cycles (Tree)
----------------------------------------------------------------------
local upvalues = open("upvalues")
check("upvalues: one row each", names(upvalues) == "1,2,3,4,5", names(upvalues))
check("an Instance upvalue shows its value", find(upvalues, "1").Type == "Instance" and not find(upvalues, "1").Expandable)
local tableRow = find(upvalues, "2")
check("a table upvalue opens", tableRow.Expandable and not tableRow.Expanded)
view:Toggle("upvalues", tableRow.Id)
H.advance(0.1)
check("opened: its entries under it, numbers first then names", names(upvalues) == "1,2,[1],nested,speed,3,4,5", names(upvalues))
check("…one level deeper", find(upvalues, "speed").Depth == 1 and find(upvalues, "speed").Path == "upvalue 2.speed", find(upvalues, "speed").Path)
view:Toggle("upvalues", find(upvalues, "nested").Id)
H.advance(0.1)
check("a nested table opens too", find(upvalues, "a") ~= nil and find(upvalues, "a").Depth == 2 and find(upvalues, "a").Path == "upvalue 2.nested.a")
view:Toggle("upvalues", find(upvalues, "3").Id)
H.advance(0.1)
check("a function upvalue opens into its upvalues", find(upvalues, "upvalue 1") ~= nil and find(upvalues, "upvalue 1").ValueText == "x", names(upvalues))
view:Toggle("upvalues", find(upvalues, "4").Id)
H.advance(0.1)
local selfRow = find(upvalues, "self")
check("a table that holds itself: marked as a cycle and doesn't open", selfRow and selfRow.Note == "cycle" and not selfRow.Expandable and selfRow.ValueText:find("(cycle)", 1, true) ~= nil, selfRow and selfRow.ValueText)
view:Toggle("upvalues", find(upvalues, "5").Id)
H.advance(0.1)
local more = nil
for _, node in upvalues.List:GetItems() do
	if node.Kind == "more" then
		more = node
	end
end
check("a big table shows 500 entries and a 'more' row", more ~= nil and more.Key == "… 100 more", more and more.Key)
view:Toggle("upvalues", find(upvalues, "5").Id)
H.advance(0.1)
check("closing a row hides what was under it", more ~= nil and find(upvalues, "k001") == nil)
-- double-click (activate) opens a row
upvalues.List.Activated:Fire(find(upvalues, "2"))
local before = names(upvalues)
upvalues.List._onActivate(find(upvalues, "2"))
H.advance(0.1)
check("activating a row (double-click) opens or closes it", names(upvalues) ~= before, names(upvalues))

----------------------------------------------------------------------
-- 4. List view, kept in the plugin's settings
----------------------------------------------------------------------
upvalues.Switch:SetValue("List")
H.advance(0.2)
check("switching to List saves the setting", api.settings.get("upvaluesView") == "List")
check("…and shows every row with its path", upvalues.Mode == "List" and find(upvalues, "speed") and find(upvalues, "speed").Path == "upvalue 2.speed" and find(upvalues, "a") ~= nil)
check("…down to 3 levels (no cycle loops)", find(upvalues, "self") ~= nil and #upvalues.List:GetItems() < 1000, #upvalues.List:GetItems())
check("…its first column is the path", upvalues.List.Columns[1].Key == "Path")
api.settings.set("upvaluesView", "Tree")
H.advance(0.2)
check("changing the setting elsewhere switches the panel back", upvalues.Mode == "Tree" and upvalues.Switch:GetValue() == "Tree" and upvalues.List.Columns[1].Key == "Name")

----------------------------------------------------------------------
-- 5. functions
----------------------------------------------------------------------
local functions = open("functions")
check("nested functions, by name", names(functions) == "inner,(anonymous)", names(functions))
check("…with their params, upvalues, constants and nested counts", find(functions, "inner").Params == 1 and find(functions, "inner").Upvalues == 2 and find(functions, "inner").Constants == 1 and find(functions, "inner").Nested == 1)
check("…a function with nothing nested doesn't open", not find(functions, "(anonymous)").Expandable)
view:Toggle("functions", find(functions, "inner").Id)
H.advance(0.1)
check("opening one shows its nested functions", find(functions, "deep") ~= nil and find(functions, "deep").Depth == 1 and find(functions, "deep").Path == "1.1")
functions.Switch:SetValue("List")
H.advance(0.2)
check("List view: every function with its path", names(functions) == "inner,deep,(anonymous)" and functions.List.Columns[1].Key == "Path", names(functions))
functions.Switch:SetValue("Tree")
H.advance(0.2)

----------------------------------------------------------------------
-- 6. other subjects
----------------------------------------------------------------------
view:Toggle("upvalues", find(open("upvalues"), "2").Id)
Loaded.load(Loaded.target(print))
H.advance(0.3)
check("a C function: no rows, and why", #open("constants").List:GetItems() == 0 and view.Panels.constants.Info.Text == "a C function has no constants", view.Panels.constants.Info.Text)
check("…no counts on the pills", badge("constants") == nil and badge("upvalues") == nil)
Loaded.load(Loaded.target(onTouched))
H.advance(0.3)
check("a new subject: Tree rows start closed again", find(open("upvalues"), "speed") == nil, names(view.Panels.upvalues))
Loaded.load(Loaded.target({ a = 1 }))
H.advance(0.3)
check("a table: says where its entries are", view.Panels.constants.Info.Text:find("Contents sub-tab", 1, true) ~= nil, view.Panels.constants.Info.Text)
T.Explorer.load({ doorScript })
H.advance(0.3)
check("a script: its main function's constants", names(open("constants")) == "1" and find(view.Panels.constants, "1").ValueText == "x")
check("…a script that isn't running has no running functions to hold upvalues", view.Panels.upvalues.Info.Text:find("no running functions", 1, true) ~= nil, view.Panels.upvalues.Info.Text)
Loaded.clear()
H.advance(0.3)
check("nothing loaded: empty panels", #view.Panels.constants.List:GetItems() == 0 and view.Panels.constants.Info.Text == "nothing loaded")

----------------------------------------------------------------------
-- 7. the settings on the plugin's page
----------------------------------------------------------------------
local items = {}
for _, item in api.settings.items() do
	items[item.Id] = item
end
check("its settings: three views and empty slots", items.constantsView and items.upvaluesView and items.functionsView and items.showEmpty and items.constantsView.Default == "Tree")

check("no runtime errors", #H.ERRORS == 0, H.ERRORS[1])
for _, e in H.ERRORS do
	print("ERR: " .. e)
end
print(("p1b: %d passed, %d failed, %d runtime errors"):format(passed, failed, #H.ERRORS))
