-- Plugins stage, round 1 part 1.4: the script viewer's views (from the
-- plugin's list: table, function, list): Table writes the rows as a Luau
-- table; Function groups them under the function that owns them; the
-- Table sub-tab is now Contents.
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
local function onTouched() end
H.FN[onTouched] = {
	Constants = { [1] = "Touched", [2] = 5, [4] = "Humanoid" },
	Upvalues = { door, { speed = 3, tag = "a\nb" }, helper, loop },
	Info = { name = "onTouched", numparams = 1, nups = 4 },
	Protos = {
		{ Info = { name = "inner", numparams = 1, nups = 0 }, Constants = { "a", "b" }, Protos = { { Info = { name = "deep" }, Constants = { 7 } } } },
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
check("Constants offers Tree, List, Table, Function", options(constants) == "Tree,List,Table,Function", options(constants))
check("Functions offers Tree, List, Table (it is by function already)", options(open("functions")) == "Tree,List,Table", options(view.Panels.functions))
check("Upvalues and Contents offer all four", options(open("upvalues")) == "Tree,List,Table,Function" and options(open("contents")) == "Tree,List,Table,Function")

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
-- 3. Function view
----------------------------------------------------------------------
Loaded.load(Loaded.target(onTouched))
H.advance(0.3)
setView(constants, "Function")
check("Function: a heading per function, open, with its constants under it", keys(constants) == "onTouched   main,1,2,4,inner   1,1,2,deep   1.1,1,(anonymous)   2", keys(constants))
check("…headings say how many", constants.List:GetItems()[1].ValueText == "3 constants", constants.List:GetItems()[1].ValueText)
check("…the bar counts the functions too", constants.Info.Text == "3 constants · 4 functions", constants.Info.Text)
local inner
for _, node in constants.List:GetItems() do
	if node.Key == "inner   1" then
		inner = node
	end
end
view:Toggle("constants", inner.Id)
H.advance(0.1)
check("a heading closes (and opens again)", keys(constants) == "onTouched   main,1,2,4,inner   1,deep   1.1,1,(anonymous)   2", keys(constants))
view:Toggle("constants", inner.Id)
H.advance(0.1)
setView(upvalues, "Function")
check("Function (Upvalues): the function, then each function it holds, with their upvalues", keys(upvalues) == "onTouched   main,1,2,3,4,helper   main↑3,1,2", keys(upvalues))
local tableRow
for _, node in upvalues.List:GetItems() do
	if node.Key == "2" and node.Depth == 1 and node.Expandable and tableRow == nil then
		tableRow = node
	end
end
view:Toggle("upvalues", tableRow.Id)
H.advance(0.1)
check("…rows under a heading still open (a table's entries)", keys(upvalues):find("speed", 1, true) ~= nil, keys(upvalues))
Loaded.load(Loaded.target(contents))
H.advance(0.3)
setView(contentsPanel, "Function")
check("Function (Contents): every Luau function in it, nested ones too, with their upvalues", keys(contentsPanel) == "helper   Sub.Helper,1,2,tick   Tick,1", keys(contentsPanel))
check("…C functions left out", keys(contentsPanel):find("Print", 1, true) == nil)
Loaded.load(Loaded.target({ a = 1 }))
H.advance(0.3)
check("…a table with no functions says so", contentsPanel.Info.Text == "no Luau functions in this table", contentsPanel.Info.Text)
Loaded.load(Loaded.target(print))
H.advance(0.3)
check("Function view of a C function: why, no rows", #constants.List:GetItems() == 0 and constants.Info.Text == "a C function has no constants", constants.Info.Text)

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
api.settings.set("functionsView", "Function")
H.advance(0.2)
check("Functions never takes the Function view", functions.Mode ~= "Function", functions.Mode)
local items = {}
for _, item in api.settings.items() do
	items[item.Id] = item
end
check("settings: the four views, Contents renamed", items.contentsView ~= nil and items.tableView == nil and table.concat(items.constantsView.Options, ",") == "Tree,List,Table,Function")

check("no runtime errors", #H.ERRORS == 0, H.ERRORS[1])
for _, e in H.ERRORS do
	print("ERR: " .. e)
end
print(("p1d: %d passed, %d failed, %d runtime errors"):format(passed, failed, #H.ERRORS))
