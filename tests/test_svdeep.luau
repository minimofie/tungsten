-- Script Viewer: everything inside a table, viewable and changeable.
-- Contents has a Deep view (tables only): functions open into Constants,
-- Upvalues and Nested functions (each nested function into its own
-- constants); a loaded table's Constants and Functions sub-tabs list its
-- functions by key path.
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
local rs = E_.game:GetService("ReplicatedStorage")
local module = E_.Instance.new("ModuleScript")
module.Name = "Data"
module.Parent = rs

local cfg = { mult = 2 }
local spark = { Info = { name = "spark", nups = 0 }, Constants = { "deep", 7 } }
local function onHit() end
local function inner() end
H.FN[onHit] = { Constants = { "Hit", 5 }, Upvalues = { cfg, "label" }, Protos = { spark }, Info = { name = "onHit", nups = 2 } }
H.FN[inner] = { Constants = { "in" }, Upvalues = {}, Info = { name = "inner" } }
local data = { name = "Sword", damage = 25, onHit = onHit, sub = { inner = inner } }
H.LOADED = { module }
H.MODULE_VALUES = { [module] = data }

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
local Actions = view.Actions
local function open(id)
	view:Select(id)
	H.advance(0.3)
	return view.Panels[id]
end
local function keys(panel)
	local out = {}
	for _, node in panel.List:GetItems() do
		table.insert(out, node.Key)
	end
	return table.concat(out, ",")
end
local function row(panel, test)
	for _, node in panel.List:GetItems() do
		if test(node) then
			return node
		end
	end
	return nil
end
local function code(node)
	local access = Actions.accessOf(api, exports.subject(), node)
	return if access then T.Access.code(access) else nil
end
local function write(node, value)
	return view.Edit.write(node, value, { Subject = exports.subject() })
end

P.go("require(game.ReplicatedStorage.Data)")
H.advance(0.3)

----------------------------------------------------------------------
-- 1. The Deep view
----------------------------------------------------------------------
local contents = open("contents")
check("Contents offers Deep", table.concat((function()
	local out = {}
	for _, o in contents.Switch.Options do
		table.insert(out, if type(o) == "table" then o.Value else o)
	end
	return out
end)(), ",") == "Tree,Deep,List,Table")
-- Tree: a function opens into its upvalues only
local hitTree = row(contents, function(n)
	return n.Key == "onHit"
end)
view:Toggle("contents", hitTree.Id)
H.advance(0.1)
check("Tree: a function opens into its upvalues", keys(contents) == "damage,name,onHit,upvalue 1,upvalue 2,sub", keys(contents))
contents.Switch:SetValue("Deep")
H.advance(0.2)
check("Deep: the same entries", keys(contents) == "damage,name,onHit,sub", keys(contents))
local hit = row(contents, function(n)
	return n.Key == "onHit"
end)
view:Toggle("contents", hit.Id)
H.advance(0.1)
check("a function opens into Constants, Upvalues and Nested functions", keys(contents) == "damage,name,onHit,Constants,Upvalues,Nested functions,sub", keys(contents))
local constantsGroup = row(contents, function(n)
	return n.Kind == "group" and n.Key == "Constants"
end)
check("…a group says how many", constantsGroup.ValueText == "2 constants", constantsGroup.ValueText)
view:Toggle("contents", constantsGroup.Id)
H.advance(0.1)
local five = row(contents, function(n)
	return n.Kind == "constant" and n.Value == 5
end)
check("its constants show", five ~= nil and row(contents, function(n)
	return n.Kind == "constant" and n.Value == "Hit"
end) ~= nil)
check("…and can be changed", write(five, 9) and H.FN[onHit].Constants[2] == 9)
check("…the menu offers Change value…", (function()
	for _, item in T.Menus.build("scriptviewer.row", { Item = five, Panel = "contents", View = view }) do
		if item.Text == "Change value…" then
			return true
		end
	end
	return false
end)())
local upGroup = row(contents, function(n)
	return n.Kind == "group" and n.Key == "Upvalues"
end)
view:Toggle("contents", upGroup.Id)
H.advance(0.1)
local cfgRow = row(contents, function(n)
	return n.Value == cfg
end)
check("its upvalues show", cfgRow ~= nil and row(contents, function(n)
	return n.Value == "label"
end) ~= nil)
check("…an upvalue's path", code(cfgRow) == "debug.getupvalues(require(game.ReplicatedStorage.Data).onHit)[1]", code(cfgRow))
local label = row(contents, function(n)
	return n.Value == "label"
end)
check("…a string upvalue can be changed", write(label, "new label") and H.FN[onHit].Upvalues[2] == "new label")
view:Toggle("contents", cfgRow.Id)
H.advance(0.1)
local mult = row(contents, function(n)
	return n.RawKey == "mult"
end)
check("a table upvalue's entries", mult ~= nil and code(mult) == "debug.getupvalues(require(game.ReplicatedStorage.Data).onHit)[1].mult", mult and code(mult))
check("…can be changed", write(mult, 3) and cfg.mult == 3)
local nestedGroup = row(contents, function(n)
	return n.Kind == "group" and n.Key == "Nested functions"
end)
view:Toggle("contents", nestedGroup.Id)
H.advance(0.1)
local sparkRow = row(contents, function(n)
	return n.Kind == "proto" and n.Key == "spark"
end)
check("its nested functions", sparkRow ~= nil and code(sparkRow) == "debug.getproto(require(game.ReplicatedStorage.Data).onHit, 1)", sparkRow and code(sparkRow))
view:Toggle("contents", sparkRow.Id)
H.advance(0.1)
local sparkConstants = row(contents, function(n)
	return n.Kind == "group" and n.Up == sparkRow
end)
check("a nested function opens into its constants (no upvalues: a prototype has none)", sparkConstants ~= nil and sparkConstants.Key == "Constants" and row(contents, function(n)
	return n.Kind == "group" and n.Up == sparkRow and n.Key == "Upvalues"
end) == nil)
view:Toggle("contents", sparkConstants.Id)
H.advance(0.1)
local seven = row(contents, function(n)
	return n.Kind == "constant" and n.Value == 7
end)
check("…its constants change through the prototype", seven ~= nil and write(seven, 8) and spark.Constants[2] == 8)
local nameRow = row(contents, function(n)
	return n.RawKey == "name"
end)
check("a string entry can be changed", write(nameRow, "Axe") and data.name == "Axe")
local sub = row(contents, function(n)
	return n.RawKey == "sub"
end)
view:Toggle("contents", sub.Id)
H.advance(0.1)
local innerRow = row(contents, function(n)
	return n.RawKey == "inner"
end)
view:Toggle("contents", innerRow.Id)
H.advance(0.1)
check("a function in a nested table opens the same way", row(contents, function(n)
	return n.Kind == "group" and n.Up == innerRow and n.Key == "Constants"
end) ~= nil)
check("…its path", code(innerRow) == "require(game.ReplicatedStorage.Data).sub.inner", code(innerRow))
contents.Switch:SetValue("Tree")
H.advance(0.2)

----------------------------------------------------------------------
-- 2. A table's Constants and Functions
----------------------------------------------------------------------
local constants = open("constants")
check("Constants: every function's constants by key path", keys(constants) == "onHit   onHit,1,2,inner   sub.inner,1", keys(constants))
local hitConst = row(constants, function(n)
	return n.Kind == "constant" and n.Value == "Hit"
end)
check("…changeable", write(hitConst, "Struck") and H.FN[onHit].Constants[1] == "Struck")
local constHeading = row(constants, function(n)
	return n.Kind == "heading" and n.Value == inner
end)
check("…a heading's path", Actions.pathOf(view, constHeading) == "require(game.ReplicatedStorage.Data).sub.inner")
local functions = open("functions")
check("Functions: the table's functions by key path", keys(functions) == "onHit,sub.inner", keys(functions))
local fnRow = row(functions, function(n)
	return n.Value == onHit
end)
functions.List:SetSelected({ fnRow })
H.advance(0.1)
check("…the details pane gives its path", (function()
	for _, fact in functions.Details.Facts do
		if fact.Text == "Path" then
			return fact.Value == "require(game.ReplicatedStorage.Data).onHit"
		end
	end
	return false
end)())

check("no runtime errors", #H.ERRORS == 0, H.ERRORS[1])
print(("svdeep: %d passed, %d failed, %d runtime errors"):format(passed, failed, #H.ERRORS))
