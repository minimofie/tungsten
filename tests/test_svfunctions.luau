-- Script Viewer revamp, functions: the Functions sub-tab lists functions
-- with a details pane (facts, Inspect, Load, Running copy…, Keep in a
-- variable…, Copy path, Copy hash); a nested function (ProtoProxy) can be
-- inspected: its constants are read and changed through the proxy, its
-- running copies hold the upvalues; a script lists its running functions
-- and the nested functions in its bytecode.
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
local mainScript = new("LocalScript")
mainScript.Name = "Main"
mainScript.Parent = E_.workspace

-- a module function with nested functions; the first has two running copies
local function copyA() end
local function copyB() end
H.FN[copyA] = { Upvalues = { "a1", 10 }, Info = { name = "copyA" } }
H.FN[copyB] = { Upvalues = { "b1" }, Info = { name = "copyB" } }
local deepProto = { Info = { name = "deep", numparams = 0, nups = 0 }, Constants = { "d" }, Line = 30 }
local stepProto = { Info = { name = "step", numparams = 2, is_vararg = 0, nups = 2 }, Constants = { "hit", 5 }, Protos = { deepProto }, Closures = { copyA, copyB }, Line = 20, CodeHash = -12345 }
local loneProto = { Info = { name = "", nups = 0 }, Constants = {}, Closures = {}, Line = 40 }
local function swing() end
H.FN[swing] = { Constants = { "Hit" }, Upvalues = {}, Info = { name = "swing", numparams = 1, nups = 0 }, Protos = { stepProto, loneProto }, Hash = string.rep("ef", 48) }
H.LOADED = { module }
H.MODULE_VALUES = { [module] = { swing = swing } }

-- a script: its bytecode copy has a nested function; one running function matches it
local copyProto = { Info = { name = "jump", nups = 1 }, Constants = { "jump", 50 } }
local mainCopy = function() end
H.FN[mainCopy] = { Constants = { "Main" }, Protos = { copyProto } }
H.SCRIPT_CLOSURES = { [mainScript] = mainCopy }
local env = {}
local function liveJump() end
local function liveOther() end
H.FN[liveJump] = { Constants = { "jump", 50 }, Upvalues = { 1 }, Env = env, Info = { name = "liveJump", nups = 1 } }
H.FN[liveOther] = { Constants = { "other" }, Upvalues = {}, Env = env, Info = { name = "liveOther" } }
H.GC = { liveJump, liveOther }
H.SENV = { [mainScript] = env }
H.RUNNING = { mainScript }

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
local function keys(panel)
	local out = {}
	for _, node in panel.List:GetItems() do
		table.insert(out, node.Key)
	end
	return table.concat(out, ",")
end
local function fact(pane, text)
	for _, f in pane.Facts do
		if f.Text == text then
			return f.Value
		end
	end
	return nil
end
local function select(panel, node)
	panel.List:SetSelected({ node })
	H.advance(0.1)
end

P.go("require(game.ReplicatedStorage.Combat).swing")
H.advance(0.3)

----------------------------------------------------------------------
-- 1. The Functions sub-tab of a function
----------------------------------------------------------------------
local functions = open("functions")
check("its nested functions, with lines and counts", keys(functions) == "step,(anonymous)", keys(functions))
check("…a Line column", functions.List.Columns[2].Key == "Line" and row(functions, function(n) return n.Key == "step" end).Line == 20)
local pane = functions.Details
check("a details pane beside the list", pane ~= nil and pane.Instance.Visible and pane.Instance.AbsolutePosition.X > functions.ListHolder.AbsolutePosition.X + functions.ListHolder.AbsoluteSize.X - 1)
check("…empty until a row is picked", pane.Title.Text == "Select a function" and pane.Buttons.Inspect.Enabled == false)
local stepRow = row(functions, function(n)
	return n.Key == "step"
end)
select(functions, stepRow)
check("picking a row shows its facts", pane.Title.Text == "step" and fact(pane, "Kind") == "nested function prototype", fact(pane, "Kind"))
check("…parameters, constants, nested", fact(pane, "Parameters") == "2" and fact(pane, "Constants") == "2" and fact(pane, "Nested functions") == "1")
check("…its code hash", fact(pane, "Code hash") == "-12345", fact(pane, "Code hash"))
check("…running copies (counted when picked)", fact(pane, "Running copies") == "2", fact(pane, "Running copies"))
check("…its path", fact(pane, "Path") == "debug.getproto(require(game.ReplicatedStorage.Combat).swing, 1)", fact(pane, "Path"))
check("…buttons on: Running copy…, Copy path, Copy hash", pane.Buttons.Copy.Enabled and pane.Buttons.Path.Enabled and pane.Buttons.Hash.Enabled)
H.clickObject(pane.Buttons.Path.Instance)
H.advance(0.1)
check("Copy path copies it", H.CLIPBOARD == "debug.getproto(require(game.ReplicatedStorage.Combat).swing, 1)", H.CLIPBOARD)
H.clickObject(pane.Buttons.Hash.Instance)
H.advance(0.1)
check("Copy hash copies the code hash", H.CLIPBOARD == "-12345", H.CLIPBOARD)
view:Toggle("functions", stepRow.Id)
H.advance(0.1)
local deepRow = row(functions, function(n)
	return n.Key == "deep"
end)
select(functions, deepRow)
check("a deeper nested function's path", fact(pane, "Path") == "debug.getproto(debug.getproto(require(game.ReplicatedStorage.Combat).swing, 1), 1)", fact(pane, "Path"))
check("the right-click menu: Inspect, Load (stay here), Inspect running copy…", (function()
	local texts = {}
	for _, item in T.Menus.build("scriptviewer.row", { Item = stepRow, Panel = "functions", View = view }) do
		table.insert(texts, item.Text)
	end
	local t = table.concat(texts, "|")
	return t:find("Inspect|Load (stay here)|Inspect running copy…", 1, true) ~= nil and t:find("Keep in a variable…", 1, true) ~= nil
end)())

----------------------------------------------------------------------
-- 2. Load and Inspect a nested function
----------------------------------------------------------------------
select(functions, stepRow)
H.clickObject(pane.Buttons.Load.Instance)
H.advance(0.3)
check("Load: the nested function is loaded, Functions stays open", Loaded.value() == stepProto and view.Tabs.Selected == "functions", view.Tabs.Selected)
check("…the path bar shows 'nested 1'", T.Access.code(Loaded.get().Access) == "debug.getproto(require(game.ReplicatedStorage.Combat).swing, 1)")
local subject = exports.subject()
check("…the viewer shows a nested function", subject.Kind == "proto" and subject.Title == "step" and view.Kind.Text:find("nested function", 1, true) == 1, view.Kind.Text)
check("…it knows where it came from", subject.Proto and subject.Proto.Owner == swing and subject.Proto.Index == 1)
check("…its nested functions in Functions", keys(view.Panels.functions) == "deep", keys(view.Panels.functions))
P.go("require(game.ReplicatedStorage.Combat).swing")
H.advance(0.3)
functions = open("functions")
stepRow = row(functions, function(n)
	return n.Key == "step"
end)
select(functions, stepRow)
H.clickObject(pane.Buttons.Inspect.Instance)
H.advance(0.3)
check("Inspect: loaded and Constants opens", Loaded.value() == stepProto and view.Tabs.Selected == "constants")
local constants = view.Panels.constants
check("…its constants (read through the proxy)", keys(constants) == "1,2", keys(constants))
local five = row(constants, function(n)
	return n.Value == 5
end)
local okWrite = view.Edit.write(five, 9, { Subject = exports.subject() })
check("a nested function's constant changes through the proxy", okWrite and stepProto.Constants[2] == 9, stepProto.Constants[2])
local upvalues = open("upvalues")
check("Upvalues: each running copy with its upvalues", keys(upvalues) == "copyA   running 1,1,2,copyB   running 2,1", keys(upvalues))
local a1 = row(upvalues, function(n)
	return n.Value == "a1"
end)
okWrite = view.Edit.write(a1, "changed", { Subject = exports.subject() })
check("…a running copy's upvalue can be changed", okWrite and H.FN[copyA].Upvalues[1] == "changed")
local copyHeading = row(upvalues, function(n)
	return n.Kind == "heading" and n.Value == copyB
end)
check("…a copy's path", view.Actions.pathOf(view, copyHeading) == "debug.getproto(require(game.ReplicatedStorage.Combat).swing, 1, true)[2]", view.Actions.pathOf(view, copyHeading))
check("…an upvalue of a copy has a path too (when it can be inspected)", view.Actions.accessOf(api, exports.subject(), a1) ~= nil and T.Access.code(view.Actions.accessOf(api, exports.subject(), a1)) == "debug.getupvalues(debug.getproto(require(game.ReplicatedStorage.Combat).swing, 1, true)[1])[1]")
local contents = open("contents")
check("Contents says a nested function has none", contents.Why ~= nil and contents.Why:find("no contents", 1, true) ~= nil, contents.Why)

----------------------------------------------------------------------
-- 3. Running copies
----------------------------------------------------------------------
P.go("require(game.ReplicatedStorage.Combat).swing")
H.advance(0.3)
functions = open("functions")
stepRow = row(functions, function(n)
	return n.Key == "step"
end)
local chosen = nil
local realChoice = api.prompt.choice
api.prompt.choice = function(opts)
	chosen = opts
	opts.OnChoose(2)
end
view.Actions.inspectCopy(view, stepRow)
H.advance(0.3)
api.prompt.choice = realChoice
check("several running copies: asks which", chosen ~= nil and #chosen.Options == 2)
check("…the copy chosen is loaded, Upvalues opens", Loaded.value() == copyB and view.Tabs.Selected == "upvalues")
check("…with its path", T.Access.code(Loaded.get().Access) == "debug.getproto(require(game.ReplicatedStorage.Combat).swing, 1, true)[2]")
P.go("require(game.ReplicatedStorage.Combat).swing")
H.advance(0.3)
functions = open("functions")
local lone = row(functions, function(n)
	return n.Key == "(anonymous)"
end)
select(functions, lone)
check("none running: says 0", fact(functions.Details, "Running copies") == "0", fact(functions.Details, "Running copies"))
local before = Loaded.value()
view.Actions.inspectCopy(view, lone)
H.advance(0.2)
check("…Running copy… loads nothing", Loaded.value() == before)

----------------------------------------------------------------------
-- 4. A script: running functions and its bytecode
----------------------------------------------------------------------
T.Explorer.load({ mainScript })
H.advance(0.3)
functions = open("functions")
check("a script: Running, then In the bytecode", keys(functions) == "Running,liveJump,liveOther,In the bytecode,jump", keys(functions))
local liveRow = row(functions, function(n)
	return n.Value == liveJump
end)
select(functions, liveRow)
check("a running function's facts", fact(functions.Details, "Kind") == "running function" and fact(functions.Details, "Upvalues") ~= nil, fact(functions.Details, "Kind"))
local jumpRow = row(functions, function(n)
	return n.Key == "jump"
end)
select(functions, jumpRow)
check("a nested function in the bytecode: no path reaches it", fact(functions.Details, "Path") == "no path reaches it" and functions.Details.Buttons.Path.Enabled == false)
check("…its running copies are matched (same constants)", fact(functions.Details, "Running copies") == "1", fact(functions.Details, "Running copies"))
check("…its kind says where it is", fact(functions.Details, "Kind") == "nested function (in the script's bytecode)")
view.Actions.inspect(view, jumpRow, { Tab = "constants" })
H.advance(0.3)
subject = exports.subject()
check("inspected: from the bytecode copy", subject.Kind == "proto" and subject.Proto.FromCopy == true and view.Kind.Text:find("from the script's bytecode", 1, true) ~= nil, view.Kind.Text)
constants = view.Panels.constants
local fifty = row(constants, function(n)
	return n.Value == 50
end)
okWrite = view.Edit.write(fifty, 75, { Subject = subject })
check("its constant goes to the running copy (and the copy)", okWrite and H.FN[liveJump].Constants[2] == 75 and copyProto.Constants[2] == 75, H.FN[liveJump].Constants[2])
upvalues = open("upvalues")
check("its Upvalues: the running copy's", keys(upvalues) == "liveJump   running 1,1", keys(upvalues))
-- no running copy: refused
H.FN[liveJump].Constants[1] = "changed"
local okNone, whyNone = view.Edit.write(row(view.Panels.constants, function(n)
	return n.Value == "jump"
end), "x", { Subject = subject })
check("no running copy matches: refused, says why", not okNone and tostring(whyNone):find("none of its running copies", 1, true) ~= nil, whyNone)

check("Keep in a variable works for a nested function", (function()
	local done = false
	local realInput = api.prompt.input
	api.prompt.input = function(opts)
		done = opts.OnSubmit("proto1")
	end
	view.Actions.setVariable(view, jumpRow)
	api.prompt.input = realInput
	return done == true and T.Variables.get("proto1") == copyProto
end)())

check("no runtime errors", #H.ERRORS == 0, H.ERRORS[1])
print(("svfunctions: %d passed, %d failed, %d runtime errors"):format(passed, failed, #H.ERRORS))
