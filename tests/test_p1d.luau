-- Plugins stage, round 1 part 1.4 (revamped): the script viewer's views:
-- Table writes the rows as a Luau table; the scope "With nested
-- functions" groups rows under the function that owns them (it replaced
-- the Function view); the Table sub-tab is now Contents.
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
local function helper() end
local loop = { name = "loop" }
loop.self = loop
H.FN[helper] = { Upvalues = { "x", 2 }, Info = { name = "helper", numparams = 0, nups = 2 } }
local function innerRunning() end
H.FN[innerRunning] = { Upvalues = { "u1" }, Info = { name = "innerRunning" } }
local function onTouched() end
H.FN[onTouched] = {
	Constants = { [1] = "Touched", [2] = 5, [4] = "Humanoid" },
	Upvalues = { door, { speed = 3, tag = "a\nb" }, helper, loop },
	Info = { name = "onTouched", numparams = 1, nups = 4 },
	Protos = {
		{ Info = { name = "inner", numparams = 1, nups = 0 }, Constants = { "a", "b" }, Protos = { { Info = { name = "deep" }, Constants = { 7 } } }, Closures = { innerRunning } },
		{ Info = { name = "" }, Constants = {} },
	},
}
local function tick() end
H.FN[tick] = { Upvalues = { 10 }, Info = { name = "tick" } }
local contents = { Speed = 16, Tick = tick, Sub = { Helper = helper }, Print = print }

local ok, err = H.run("Tungsten/Tungsten.luau")
check("loader runs", ok, err)
H.advance(5)
local T = genv.Tungsten.Context
local Plugins, Loaded = T.Plugins, T.Loaded
local record = Plugins.get("scriptviewer")
local exports, api = record.Exports, record.Api
T.Tabs:Select("scriptviewer")
H.advance(0.4)
local view = exports.view()
local function open(id)
	view:Select(id)
	H.advance(0.3)
	return view.Panels[id]
end
local function setView(panel, mode)
	panel.Switch:SetValue(mode)
	H.advance(0.2)
end
local function keys(panel)
	local out = {}
	for _, node in panel.List:GetItems() do
		table.insert(out, node.Key)
	end
	return table.concat(out, ",")
end
local function options(panel)
	local out = {}
	for _, option in panel.Switch.Options do
		table.insert(out, if type(option) == "table" then option.Text or option.Value else option)
	end
	return table.concat(out, ",")
end

Loaded.load(Loaded.target(onTouched))
H.advance(0.3)

----------------------------------------------------------------------
-- 1. the views on offer; the sub-tab renamed
----------------------------------------------------------------------
check("the Table sub-tab is now Contents", H.find(view.Tabs.Instance, "Tab_contents") ~= nil and H.find(view.Tabs.Instance, "Tab_table") == nil)
local constants = open("constants")
check("Constants offers Tree, List, Table (no Function view)", options(constants) == "Tree,List,Table", options(constants))
check("Functions offers Tree, List, Table", options(open("functions")) == "Tree,List,Table", options(view.Panels.functions))
local upOptions, contentOptions = options(open("upvalues")), options(open("contents"))
check("Upvalues offers the same three; Contents also Deep (tables only)", upOptions == "Tree,List,Table" and contentOptions == "Tree,Deep,List,Table", upOptions .. " / " .. contentOptions)
check("Constants and Upvalues have a scope; Contents and Functions don't", constants.ScopeSwitch ~= nil and view.Panels.upvalues.ScopeSwitch ~= nil and view.Panels.contents.ScopeSwitch == nil and view.Panels.functions.ScopeSwitch == nil)

----------------------------------------------------------------------
-- 2. Table view
----------------------------------------------------------------------
setView(constants, "Table")
local text = constants.Text:GetText()
check("Table: the constants as a Luau table, in order (an empty slot is nil)", text == "{\n\t\"Touched\",\n\t5,\n\tnil,\n\t\"Humanoid\",\n}", text)
check("…the text shows, the list doesn't", constants.Text.Instance.Visible and not constants.ListHolder.Visible)
check("…editable now (Apply writes it back)", constants.Text.ReadOnly == false and constants.Apply ~= nil)
check("…saved as the Constants view", api.settings.get("constantsView") == "Table")
local upvalues = view.Panels.upvalues
setView(upvalues, "Table")
text = upvalues.Text:GetText()
check("Table: an Instance can't be written: KEEP and what it is", text:find("KEEP --[[ Instance Workspace.Door ]]", 1, true) ~= nil, text)
check("…a table written out, strings escaped", text:find("speed = 3", 1, true) ~= nil and text:find("tag = \"a\\nb\"", 1, true) ~= nil, text)
check("…a function as KEEP with its name", text:find("KEEP --[[ function helper ]]", 1, true) ~= nil or text:find("KEEP --[[ function", 1, true) ~= nil, text)
check("…a table holding itself: KEEP, shown once", text:find("a table shown earlier", 1, true) ~= nil, text)
local ok2 = pcall(function()
	return (loadstring or load)("return " .. text)
end)
check("…the text is valid Luau (KEEP aside)", ok2)
local functions = view.Panels.functions
setView(functions, "Table")
text = functions.Text:GetText()
check("Table: nested functions as data (name, counts, constants, nested)", text:find("name = \"inner\"", 1, true) ~= nil and text:find("name = \"deep\"", 1, true) ~= nil and text:find("params = 1", 1, true) ~= nil, text)
local contentsPanel = view.Panels.contents
Loaded.load(Loaded.target(contents, { Label = "cfg" }))
H.advance(0.3)
setView(contentsPanel, "Table")
text = contentsPanel.Text:GetText()
check("Table: a loaded table's contents", text:find("Speed = 16", 1, true) ~= nil and text:find("Sub = {", 1, true) ~= nil, text)
Loaded.load(Loaded.target(print))
H.advance(0.3)
check("Table: nothing to write says why, as a comment", view.Panels.constants.Text:GetText():sub(1, 3) == "-- ", view.Panels.constants.Text:GetText())
setView(constants, "Tree")
check("back to Tree: the list again", constants.ListHolder.Visible and not constants.Text.Instance.Visible)

----------------------------------------------------------------------
-- 3. Scope: with nested functions
----------------------------------------------------------------------
Loaded.load(Loaded.target(onTouched))
H.advance(0.3)
setView(constants, "Tree")
check("scope starts as This function", constants.Scope == "This function" and keys(constants) == "1,2,4", keys(constants))
view:SetScope("constants", "With nested functions")
H.advance(0.2)
check("with nested functions: a heading per function, open, with its constants under it", keys(constants) == "onTouched   main,1,2,4,inner   1,1,2,deep   1.1,1,(anonymous)   2", keys(constants))
check("…saved", api.settings.get("constantsScope") == "With nested functions")
check("…the scope dropdown shows it", constants.ScopeSwitch:GetValue() == "With nested functions")
check("…headings say how many", constants.List:GetItems()[1].ValueText == "3 constants", constants.List:GetItems()[1].ValueText)
check("…the bar counts every row and the functions", constants.Info.Text == "6 constants · 4 functions", constants.Info.Text)
local inner, deep
for _, node in constants.List:GetItems() do
	if node.Key == "inner   1" then
		inner = node
	elseif node.Key == "deep   1.1" then
		deep = node
	end
end
check("a heading knows how its function is reached (nested 1)", inner and #inner.Chain == 1 and inner.Chain[1].Kind == "proto" and inner.Chain[1].Index == 1)
check("…and a deeper one (nested 1, nested 1)", deep and #deep.Chain == 2 and deep.Chain[2].Index == 1)
view:Toggle("constants", inner.Id)
H.advance(0.1)
check("a heading closes (and opens again)", keys(constants) == "onTouched   main,1,2,4,inner   1,deep   1.1,1,(anonymous)   2", keys(constants))
view:Toggle("constants", inner.Id)
H.advance(0.1)
setView(constants, "List")
check("List with nested functions: flat rows, the function in the path", (function()
	for _, node in constants.List:GetItems() do
		if node.Path == "inner   1 · constant 2" or node.Path:find("constant 2", 1, true) and node.Path:find("1", 1, true) then
			return node.Kind ~= "heading"
		end
	end
	return false
end)())
setView(constants, "Table")
check("Table with nested functions: by function, read-only", constants.Text:GetText():find("inner", 1, true) ~= nil and constants.Text.ReadOnly == true, constants.Text:GetText())
setView(constants, "Tree")
view:SetScope("constants", "This function")
H.advance(0.2)
check("back to This function", keys(constants) == "1,2,4", keys(constants))

setView(upvalues, "Tree")
view:SetScope("upvalues", "With nested functions")
H.advance(0.2)
check("Upvalues with nested functions: its own, then each running copy of a nested function", keys(upvalues) == "onTouched   main,1,2,3,4,innerRunning   nested 1 · running 1,1", keys(upvalues))
local copyHeading
for _, node in upvalues.List:GetItems() do
	if node.Kind == "heading" and node.Value == innerRunning then
		copyHeading = node
	end
end
check("…a running copy's heading knows its path", copyHeading and copyHeading.Chain[1].Kind == "closure" and copyHeading.Chain[1].Index == 1 and copyHeading.Chain[1].Copy == 1)
check("…its upvalues belong to the copy (editable)", (function()
	for _, node in upvalues.List:GetItems() do
		if node.Kind == "upvalue" and node.Owner == innerRunning then
			return node.Value == "u1"
		end
	end
	return false
end)())
local tableRow
for _, node in upvalues.List:GetItems() do
	if node.Key == "2" and node.Depth == 1 and node.Expandable and tableRow == nil then
		tableRow = node
	end
end
view:Toggle("upvalues", tableRow.Id)
H.advance(0.1)
check("…rows under a heading still open (a table's entries)", keys(upvalues):find("speed", 1, true) ~= nil, keys(upvalues))
view:SetScope("upvalues", "This function")
H.advance(0.2)
Loaded.load(Loaded.target(print))
H.advance(0.3)
check("a C function: why, no rows", #constants.List:GetItems() == 0 and constants.Info.Text == "a C function has no constants", constants.Info.Text)

----------------------------------------------------------------------
-- 4. settings and counts
----------------------------------------------------------------------
check("pill counts don't depend on the view", (function()
	Loaded.load(Loaded.target(onTouched))
	H.advance(0.3)
	local pill = H.find(view.Tabs.Instance, "Tab_constants")
	return H.find(H.find(pill, "Badge"), "Text").Text == "3"
end)())
api.settings.set("upvaluesView", "Table")
H.advance(0.2)
check("a view chosen on the plugin's page applies", upvalues.Mode == "Table" and upvalues.Text.Instance.Visible)
api.settings.set("constantsView", "Function")
H.advance(0.2)
check("an old Function setting falls back to Tree", constants.Mode == "Tree", constants.Mode)
local items = {}
for _, item in api.settings.items() do
	items[item.Id] = item
end
check("settings: three views, Contents renamed", items.contentsView ~= nil and items.tableView == nil and table.concat(items.constantsView.Options, ",") == "Tree,List,Table")
check("settings: the scopes and References", items.constantsScope ~= nil and items.upvaluesScope ~= nil and items.showReferences ~= nil and items.showReferences.Default == false)

check("no runtime errors", #H.ERRORS == 0, H.ERRORS[1])
for _, e in H.ERRORS do
	print("ERR: " .. e)
end
print(("p1d: %d passed, %d failed, %d runtime errors"):format(passed, failed, #H.ERRORS))
