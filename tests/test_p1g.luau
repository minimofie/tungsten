-- Plugins stage, round 1 part 1.6: editing in the script viewer (from the
-- plugin's list: "easily change constants and upvalues"). Right-click
-- menu on rows, dropdown forms, the editable Table view, Undo, and
-- read-only tables made writable only after a confirm (Q10).
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

local function helper() end
H.FN[helper] = { Upvalues = { "x", 2 }, Info = { name = "helper", numparams = 0, nups = 2 } }
local function onTouched() end
H.FN[onTouched] = {
	Constants = { [1] = "Touched", [2] = 5, [4] = "Humanoid" },
	Upvalues = { 10, { speed = 3 }, helper },
	Info = { name = "onTouched", numparams = 1, nups = 3 },
}
local config = { Speed = 16, Name = "door", Sub = { Depth = 1 }, Fn = helper }

local ok, err = H.run("Tungsten/Tungsten.luau")
check("loader runs", ok, err)
H.advance(5)
local T = genv.Tungsten.Context
local Plugins, Loaded, Menus, Undo, UI = T.Plugins, T.Loaded, T.Menus, T.Undo, T.UI
local record = Plugins.get("scriptviewer")
local exports, api = record.Exports, record.Api
T.Tabs:Select("scriptviewer")
H.advance(0.4)
local view = exports.view()
check("the view is built", view ~= nil)
local function open(id)
	view:Select(id)
	H.advance(0.3)
	return view.Panels[id]
end
local function setView(panel, mode)
	panel.Switch:SetValue(mode)
	H.advance(0.2)
end
local function rows(panel)
	return panel.List:GetItems()
end
local function rowWhere(panel, fn)
	for _, node in rows(panel) do
		if fn(node) then
			return node
		end
	end
	return nil
end
local function texts(items)
	local out = {}
	for _, item in items do
		if not item.Separator and not item.Header and item.Text then
			table.insert(out, item.Text .. (if item.Disabled then "(x)" else "") .. (if item.Danger then "(!)" else ""))
		end
	end
	return table.concat(out, "|")
end
local function menuFor(panelId, node)
	return Menus.build("scriptviewer.row", { Item = node, Panel = panelId, View = view })
end
local function pick(items, text)
	for _, item in items do
		if item.Text == text then
			return item
		end
	end
	return nil
end
-- the next prompt opened (confirm / form / input)
local lastPrompt
UI.on("Prompt", "Opened", function(handle)
	lastPrompt = handle
end)

----------------------------------------------------------------------
-- 1. constants
----------------------------------------------------------------------
Loaded.load(Loaded.target(onTouched))
H.advance(0.3)
local constants = open("constants")
local touched = rowWhere(constants, function(n) return n.Value == "Touched" end)
check("a constant row", touched ~= nil)
local menu = menuFor("constants", touched)
check("constant menu: change, no remove (constants can't be nil), use entries, no Copy path (no path to a number)", texts(menu) == "Change value…|Keep in a variable…|Copy value", texts(menu))

Undo.clear()
local form
lastPrompt = nil
pick(menu, "Change value…").Callback()
H.advance(0.1)
form = lastPrompt
check("Change value… opens a form with one Value field (Type + value)", form ~= nil and form.Fields and form.Fields.value ~= nil and form.Fields.value.TypeBox ~= nil and form.Fields.type == nil)
check("…Value starts as the constant", form.Fields.value.Get().Text == "Touched", form.Fields.value.Get().Text)
check("…the Type dropdown keeps the constant's type, or a variable (setting off)", form.Fields.value.Get().Type == "string" and table.concat(form.Fields.value.Field.Types, ",") == "string,variable", table.concat(form.Fields.value.Field.Types, ","))
form.Fields.value.Set({ Text = "Hit" })
form.Submit()
H.advance(0.2)
check("the constant changed in the function", H.FN[onTouched].Constants[1] == "Hit", H.FN[onTouched].Constants[1])
check("…the form closed", form.Closed == true)
check("…an undo step", Undo.count() == 1 and tostring(Undo.peek().Text):find("change", 1, true) ~= nil, Undo.peek() and Undo.peek().Text)
check("…the row shows the new value", rowWhere(constants, function(n) return n.Value == "Hit" end) ~= nil)
Undo.undo()
H.advance(0.2)
check("undo puts the constant back", H.FN[onTouched].Constants[1] == "Touched")
check("…and the row follows", rowWhere(constants, function(n) return n.Value == "Touched" end) ~= nil)

-- number constant, wrong text: the form stays open with the problem
local five = rowWhere(constants, function(n) return n.Value == 5 end)
-- through the double-click path (a row that doesn't open)
lastPrompt = nil
constants.List._onActivate(five)
H.advance(0.1)
form = lastPrompt
check("double-click on a constant opens the form", form ~= nil and form.Fields and form.Fields.value.Get().Text == "5", form and form.Fields and form.Fields.value.Get().Text)
form.Fields.value.Set({ Text = "not a number" })
form.Submit()
H.advance(0.1)
check("bad text: the form stays open and says why", not form.Closed and form.Problem.Text ~= "", form.Problem and form.Problem.Text)
form.Fields.value.Set({ Text = "7.5" })
form.Submit()
H.advance(0.2)
check("…fixed text writes it", H.FN[onTouched].Constants[2] == 7.5 and form.Closed)

-- type change only with the setting on
local humanoid = rowWhere(constants, function(n) return n.Value == "Humanoid" end)
api.settings.set("constantAnyType", true)
lastPrompt = nil
pick(menuFor("constants", humanoid), "Change value…").Callback({ Item = humanoid, Panel = "constants", View = view })
H.advance(0.1)
form = lastPrompt
check("setting on: Type offers string, number, boolean and variable", table.concat(form.Fields.value.Field.Types, ",") == "string,number,boolean,variable", table.concat(form.Fields.value.Field.Types, ","))
form.Fields.value.Set({ Type = "boolean" })
form.Fields.value.Set({ Text = "true" })
form.Submit()
H.advance(0.2)
check("…a constant can change type", H.FN[onTouched].Constants[4] == true, H.FN[onTouched].Constants[4])
api.settings.set("constantAnyType", false)
H.SETCONSTANT_FAIL = true
humanoid = rowWhere(constants, function(n) return n.Value == true end)
lastPrompt = nil
pick(menuFor("constants", humanoid), "Change value…").Callback({ Item = humanoid, Panel = "constants", View = view })
H.advance(0.1)
form = lastPrompt
form.Fields.value.Set({ Text = "false" })
form.Submit()
H.advance(0.1)
check("a refused setconstant keeps the form open", not form.Closed and H.FN[onTouched].Constants[4] == true, form.Problem and form.Problem.Text)
form:Close("cancel")
H.SETCONSTANT_FAIL = nil
H.advance(0.1)

----------------------------------------------------------------------
-- 2. upvalues
----------------------------------------------------------------------
local upvalues = open("upvalues")
local ten = rowWhere(upvalues, function(n) return n.Value == 10 end)
check("an upvalue row", ten ~= nil)
check("upvalue menu: change, set to nil (danger), use", texts(menuFor("upvalues", ten)) == "Change value…|Set to nil(!)|Keep in a variable…|Copy value", texts(menuFor("upvalues", ten)))
lastPrompt = nil
pick(menuFor("upvalues", ten), "Change value…").Callback({ Item = ten, Panel = "upvalues", View = view })
H.advance(0.1)
form = lastPrompt
check("a number upvalue's form offers only the plain types and variable", table.concat(form.Fields.value.Field.Types, ",") == "string,number,boolean,nil,variable", table.concat(form.Fields.value.Field.Types, ","))
form.Fields.value.Set({ Type = "string" })
form.Fields.value.Set({ Text = "ten" })
form.Submit()
H.advance(0.2)
check("an upvalue can change type", H.FN[onTouched].Upvalues[1] == "ten", H.FN[onTouched].Upvalues[1])
lastPrompt = nil
ten = rowWhere(upvalues, function(n) return n.Value == "ten" end)
pick(menuFor("upvalues", ten), "Change value…").Callback({ Item = ten, Panel = "upvalues", View = view })
H.advance(0.1)
form = lastPrompt
check("…a string upvalue offers no Vector3 (only through a variable)", table.find(form.Fields.value.Field.Types, "Vector3") == nil)
T.Variables.set("vec", E_.Vector3.new(1, 2, 3))
form.Fields.value.Set({ Type = "variable", Variable = "vec" })
form.Submit()
H.advance(0.2)
check("…to a Vector3 from a variable", H.FN[onTouched].Upvalues[1] == E_.Vector3.new(1, 2, 3), H.FN[onTouched].Upvalues[1])
local vec = rowWhere(upvalues, function(n) return n.Value == E_.Vector3.new(1, 2, 3) end)
pick(menuFor("upvalues", vec), "Set to nil").Callback({ Item = vec, Panel = "upvalues", View = view })
H.advance(0.2)
check("Set to nil", H.FN[onTouched].Upvalues[1] == nil)
Undo.undo()
H.advance(0.2)
check("…undone", H.FN[onTouched].Upvalues[1] == E_.Vector3.new(1, 2, 3))

-- a function from a $variable
T.Variables.set("fn", helper)
lastPrompt = nil
pick(menuFor("upvalues", vec), "Change value…").Callback({ Item = rowWhere(upvalues, function(n) return n.Value == E_.Vector3.new(1, 2, 3) end), Panel = "upvalues", View = view })
H.advance(0.1)
form = lastPrompt
check("a Vector3 upvalue offers Vector3, nil and variable", table.concat(form.Fields.value.Field.Types, ",") == "Vector3,nil,variable", table.concat(form.Fields.value.Field.Types, ","))
form.Fields.value.Set({ Type = "variable" })
form.Submit()
H.advance(0.1)
check("variable with none picked: the form stays open", not form.Closed and form.Problem.Text:find("pick a variable", 1, true) ~= nil, form.Problem and form.Problem.Text)
check("…the picker lists the variables", (function()
	for _, option in form.Fields.value.VariableBox.Options do
		if option.Value == "fn" then
			return option.Text == "$fn" and option.Hint == "function"
		end
	end
	return false
end)())
form.Fields.value.Set({ Variable = "fn" })
form.Submit()
H.advance(0.2)
check("…$fn picked sets it", H.FN[onTouched].Upvalues[1] == helper)

----------------------------------------------------------------------
-- 3. table entries inside an upvalue (Tree)
----------------------------------------------------------------------
local tbl = rowWhere(upvalues, function(n) return rawequal(n.Value, H.FN[onTouched].Upvalues[2]) end)
check("a table upvalue row", tbl ~= nil and tbl.Expandable)
check("table row menu: add, inspect", texts(menuFor("upvalues", tbl)):find("Add entry to", 1, true) ~= nil and texts(menuFor("upvalues", tbl)):find("Inspect", 1, true) ~= nil, texts(menuFor("upvalues", tbl)))
lastPrompt = nil
pick(menuFor("upvalues", tbl), "Add entry to " .. tostring(tbl.Path or tbl.Key) .. "…").Callback({ Item = tbl, Panel = "upvalues", View = view })
H.advance(0.1)
form = lastPrompt
check("Add entry form: key type, key, value (type + value)", form and form.Fields.keyType and form.Fields.key and form.Fields.value and table.find(form.Fields.value.Field.Types, "variable") ~= nil)
form.Fields.key.Set("jump")
form.Fields.value.Set({ Type = "number", Text = "50" })
form.Submit()
H.advance(0.2)
local upTable = H.FN[onTouched].Upvalues[2]
check("…the entry is added", upTable.jump == 50)
view:Toggle("upvalues", tbl.Id)
H.advance(0.2)
local speed = rowWhere(upvalues, function(n) return n.Key == "speed" or n.RawKey == "speed" end)
check("an entry row inside the table", speed ~= nil and speed.Parent == upTable)
check("entry menu: change, remove (danger), rename", texts(menuFor("upvalues", speed)):find("Change value…|Remove entry(!)|Add entry to", 1, true) == 1 and texts(menuFor("upvalues", speed)):find("Rename key…", 1, true) ~= nil, texts(menuFor("upvalues", speed)))
lastPrompt = nil
pick(menuFor("upvalues", speed), "Rename key…").Callback({ Item = speed, Panel = "upvalues", View = view })
H.advance(0.1)
form = lastPrompt
form.Fields.key.Set("pace")
form.Submit()
H.advance(0.2)
check("Rename key moves the value", upTable.pace == 3 and upTable.speed == nil)
Undo.undo()
H.advance(0.2)
check("…undone", upTable.speed == 3 and upTable.pace == nil)

----------------------------------------------------------------------
-- 4. a read-only table (Q10)
----------------------------------------------------------------------
Loaded.load(Loaded.target(config))
H.advance(0.3)
local contents = open("contents")
H.READONLY = H.READONLY or setmetatable({}, { __mode = "k" })
H.READONLY[config] = true
local speedRow = rowWhere(contents, function(n) return n.RawKey == "Speed" end)
check("a contents row", speedRow ~= nil)
lastPrompt = nil
pick(menuFor("contents", speedRow), "Change value…").Callback({ Item = speedRow, Panel = "contents", View = view })
H.advance(0.1)
form = lastPrompt
form.Fields.value.Set({ Text = "20" })
lastPrompt = nil
form.Submit()
H.advance(0.1)
local confirm = lastPrompt
check("read-only: asks before making it writable", confirm ~= nil and confirm ~= form and config.Speed == 16)
H.clickObject(confirm.Buttons.Cancel.Instance)
H.advance(0.2)
check("…cancel leaves it", config.Speed == 16 and H.READONLY[config] == true)
lastPrompt = nil
pick(menuFor("contents", speedRow), "Change value…").Callback({ Item = speedRow, Panel = "contents", View = view })
H.advance(0.1)
form = lastPrompt
form.Fields.value.Set({ Text = "20" })
lastPrompt = nil
form.Submit()
H.advance(0.1)
H.clickObject(lastPrompt.Buttons.Confirm.Instance)
H.advance(0.2)
check("…confirm writes it and makes it read-only again", config.Speed == 20 and H.READONLY[config] == true)
Undo.undo()
H.advance(0.2)
check("…undo works on the read-only table, still read-only", config.Speed == 16 and H.READONLY[config] == true)
H.READONLY[config] = nil

local frozen = table.freeze({ a = 1 })
local node = { Kind = "entry", Parent = frozen, RawKey = "a", Key = "a", Value = 1 }
local okW, why = view.Edit.write(node, 2, { Unlock = true })
check("a frozen table is never written", not okW and frozen.a == 1, why)

-- the Add entry button on Contents
check("Contents has an Add entry button", contents.Add ~= nil and contents.Add.Instance.Visible)
lastPrompt = nil
H.clickObject(contents.Add.Instance)
H.advance(0.1)
form = lastPrompt
check("…it opens the Add form", form ~= nil and form.Fields and form.Fields.key ~= nil)
form.Fields.keyType.Set("number")
form.Fields.key.Set("1")
form.Fields.value.Set({ Type = "boolean" })
form.Fields.value.Set({ Text = "true" })
form.Submit()
H.advance(0.2)
check("…a number key", config[1] == true)
lastPrompt = nil
H.clickObject(contents.Add.Instance)
H.advance(0.1)
form = lastPrompt
form.Fields.key.Set("Empty")
form.Fields.value.Set({ Type = "nil" })
form.Submit()
H.advance(0.1)
check("a new entry needs a value", not form.Closed and config.Empty == nil)
form:Close("cancel")
H.advance(0.1)

-- Keep in a variable
local nameRow = rowWhere(contents, function(n) return n.RawKey == "Name" end)
lastPrompt = nil
pick(menuFor("contents", nameRow), "Keep in a variable…").Callback({ Item = nameRow, Panel = "contents", View = view })
H.advance(0.1)
local input = lastPrompt
if input and input.Box then
	input.Box:SetText("doorName")
elseif input and input.Fields and input.Fields.value then
	input.Fields.value.Set("doorName")
end
if input and input.Submit then input.Submit() end
H.advance(0.1)
check("Keep in a variable sets $doorName", T.Variables.get("doorName") == "door", T.Variables.get("doorName"))
pick(menuFor("contents", nameRow), "Copy value").Callback({ Item = nameRow, Panel = "contents", View = view })
check("Copy value", H.CLIPBOARD ~= nil and H.CLIPBOARD:find("door", 1, true) ~= nil, H.CLIPBOARD)

----------------------------------------------------------------------
-- 5. the Table view: Apply / Revert
----------------------------------------------------------------------
setView(contents, "Table")
check("Table view: Apply and Revert show, editable", contents.Apply.Instance.Visible and contents.Revert.Instance.Visible and contents.Text.ReadOnly == false)
check("…Add entry hides in Table view", not contents.Add.Instance.Visible)
local text = contents.Text:GetText()
check("the text holds the entries", text:find("Speed = 16", 1, true) ~= nil, text)
contents.Text:SetText((text:gsub("Speed = 16", "Speed = 30")))
Undo.clear()
H.clickObject(contents.Apply.Instance)
H.advance(0.2)
check("Apply writes the changed entry", config.Speed == 30, config.Speed)
check("…keeps the function (KEEP) and the nested table by identity", config.Fn == helper and type(config.Sub) == "table" and config.Sub.Depth == 1)
check("…one undo step", Undo.count() == 1)
Undo.undo()
H.advance(0.2)
check("…undone", config.Speed == 16)
contents.Text:SetText("{ broken =")
H.clickObject(contents.Apply.Instance)
H.advance(0.2)
check("text that doesn't read leaves the table as it was", config.Speed == 16 and config.Name == "door")
H.clickObject(contents.Revert.Instance)
H.advance(0.2)
check("Revert shows the table again", contents.Text:GetText():find("Speed = 16", 1, true) ~= nil, contents.Text:GetText())
contents.Text:SetText((contents.Text:GetText():gsub("Name = \"door\",?\n?", "")))
H.clickObject(contents.Apply.Instance)
H.advance(0.2)
check("an entry taken out of the text is removed", config.Name == nil)
Undo.undo()
H.advance(0.2)
check("…undone", config.Name == "door")
contents.Text:SetText("{ Speed = os.exit() }")
H.clickObject(contents.Apply.Instance)
H.advance(0.2)
check("text runs no code (no os, no globals)", config.Speed == 16)

-- the constants Table view writes constants
Loaded.load(Loaded.target(onTouched))
H.advance(0.3)
constants = open("constants")
setView(constants, "Table")
local ctext = constants.Text:GetText()
check("constants as a table", ctext:find("\"Touched\"", 1, true) ~= nil, ctext)
constants.Text:SetText((ctext:gsub("\"Touched\"", "\"Clicked\"")))
H.clickObject(constants.Apply.Instance)
H.advance(0.2)
check("Apply on constants sets the constant", H.FN[onTouched].Constants[1] == "Clicked", H.FN[onTouched].Constants[1])
Undo.undo()
H.advance(0.2)
check("…undone", H.FN[onTouched].Constants[1] == "Touched")
setView(constants, "Tree")
local functions = open("functions")
setView(functions, "Table")
check("Functions Table view stays read-only", functions.Text.ReadOnly == true and not functions.Apply.Instance.Visible)

----------------------------------------------------------------------
-- 6. a script's constants go to its running functions
----------------------------------------------------------------------
local doorScript = E_.Instance.new("LocalScript")
doorScript.Name = "DoorScript"
doorScript._props.Source = "print('open')"
doorScript.Parent = E_.workspace
local doorEnv = { script = doorScript }
local proto = { Info = { name = "hit" }, Constants = { "Hit", 3 } }
local function copyMain() end -- what getscriptclosure gives: compiled again
local function liveMain() end -- the running main function
local function liveHit() end
H.FN[copyMain] = { Constants = { "open", 1 }, Hash = string.rep("aa", 48), Protos = { proto } }
H.FN[liveMain] = { Constants = { "open", 1 }, Hash = string.rep("aa", 48), Env = doorEnv, Info = { name = "" } }
H.FN[liveHit] = { Constants = { "Hit", 3 }, Hash = string.rep("bb", 48), Env = doorEnv, Info = { name = "hit" } }
H.GC = { liveMain, liveHit }
H.SCRIPT_CLOSURES = { [doorScript] = copyMain }
H.RUNNING = { doorScript }
H.SENV = { [doorScript] = doorEnv }
Loaded.load({ doorScript })
H.advance(0.3)
constants = open("constants")
check("a script's constants show (from the copy)", view.Subject.Kind == "script" and rowWhere(constants, function(n) return n.Value == "open" end) ~= nil)
local openRow = rowWhere(constants, function(n) return n.Value == "open" end)
lastPrompt = nil
pick(menuFor("constants", openRow), "Change value…").Callback()
H.advance(0.1)
form = lastPrompt
form.Fields.value.Set({ Text = "shut" })
form.Submit()
H.advance(0.2)
check("…written to the running main function", H.FN[liveMain].Constants[1] == "shut", H.FN[liveMain].Constants[1])
check("…and the copy (the view shows it)", H.FN[copyMain].Constants[1] == "shut" and rowWhere(constants, function(n) return n.Value == "shut" end) ~= nil)
Undo.undo()
H.advance(0.2)
check("…undo puts both back", H.FN[liveMain].Constants[1] == "open" and H.FN[copyMain].Constants[1] == "open")

-- a nested function (ProtoProxy) of the copy: matched by its constants
local protoNode = { Kind = "constant", Owner = proto, Index = 1, Value = "Hit", Key = "1" }
local okP, whyP, undoP = view.Edit.write(protoNode, "Smash", { Subject = view.Subject })
check("a nested function's constant goes to its running closure", okP and H.FN[liveHit].Constants[1] == "Smash" and proto.Constants[1] == "Smash", whyP)
undoP()
check("…undone", H.FN[liveHit].Constants[1] == "Hit" and proto.Constants[1] == "Hit")
local function liveTwin() end
H.FN[liveTwin] = { Constants = { "Hit", 3 }, Hash = string.rep("cc", 48), Env = doorEnv, Info = { name = "other" } }
H.GC = { liveMain, liveHit, liveTwin }
okP, whyP = view.Edit.write(protoNode, "Smash", { Subject = view.Subject })
check("two different running functions look the same: refused, says what to do", not okP and tostring(whyP):find("look the same", 1, true) ~= nil and H.FN[liveHit].Constants[1] == "Hit", whyP)

-- the main chunk finished: nothing running is this function
H.GC = { liveHit }
lastPrompt = nil
pick(menuFor("constants", openRow), "Change value…").Callback()
H.advance(0.1)
form = lastPrompt
form.Fields.value.Set({ Text = "shut" })
form.Submit()
H.advance(0.1)
check("no running copy: refused, the form says why", not form.Closed and form.Problem.Text:find("change nothing", 1, true) ~= nil and H.FN[copyMain].Constants[1] == "open", form.Problem and form.Problem.Text)
form:Close("cancel")
H.advance(0.1)
-- the Table view of a script's constants goes the same way
H.GC = { liveMain, liveHit }
setView(constants, "Table")
constants.Text:SetText((constants.Text:GetText():gsub('"open"', '"ajar"')))
H.clickObject(constants.Apply.Instance)
H.advance(0.2)
check("Table view Apply on a script's constants writes the running function", H.FN[liveMain].Constants[1] == "ajar" and H.FN[copyMain].Constants[1] == "ajar", H.FN[liveMain].Constants[1])
Undo.undo()
H.advance(0.2)
check("…undone", H.FN[liveMain].Constants[1] == "open")
H.RUNNING = {}
H.SENV = {}
Loaded.load(Loaded.target(onTouched))
H.advance(0.3)
local fnConstants = open("constants")
setView(fnConstants, "Table")
fnConstants.Text:SetText((fnConstants.Text:GetText():gsub('"Touched"', '"Pressed"')))
H.clickObject(fnConstants.Apply.Instance)
H.advance(0.2)
check("a loaded function's constants are written to it directly", H.FN[onTouched].Constants[1] == "Pressed")
setView(fnConstants, "Tree")

----------------------------------------------------------------------
-- 6b. a script's upvalues when filtergc's Environment finds nothing
----------------------------------------------------------------------
local fullName = doorScript:GetFullName()
local function liveLoop() end
H.FN[liveLoop] = { Upvalues = { 0, "idle" }, Source = fullName, Info = { name = "loop" } } -- no Env: Environment can't find it
local function elsewhere() end
H.FN[elsewhere] = { Upvalues = { 99 }, Source = "Workspace.Other", Info = { name = "other" } }
H.GC = { liveLoop, elsewhere }
H.RUNNING = { doorScript }
H.SENV = { [doorScript] = doorEnv }
H.SCRIPT_CLOSURES = { [doorScript] = copyMain }
H.FILTERGC_ENV_MISS = true
Loaded.load({ doorScript })
H.advance(0.3)
upvalues = open("upvalues")
local function hasValue(panel, value)
	for _, n in rows(panel) do
		if n.Value == value then
			return n
		end
	end
	return nil
end
check("Environment finds nothing: found by the script's source name", hasValue(upvalues, "idle") ~= nil and hasValue(upvalues, 99) == nil, upvalues.Info.Text)
H.FILTERGC_SOURCE_MISS = true
Loaded.load({ doorScript })
H.advance(0.3)
check("…and by getgc when filtergc finds nothing at all", hasValue(upvalues, "idle") ~= nil and hasValue(upvalues, 99) == nil, upvalues.Info.Text)
local idle = hasValue(upvalues, "idle")
lastPrompt = nil
pick(menuFor("upvalues", idle), "Change value…").Callback()
H.advance(0.1)
form = lastPrompt
form.Fields.value.Set({ Text = "busy" })
form.Submit()
H.advance(0.2)
check("…its upvalue can be changed", H.FN[liveLoop].Upvalues[2] == "busy", H.FN[liveLoop].Upvalues[2])
check("…and the row shows it", hasValue(upvalues, "busy") ~= nil)
-- no compiled copy (getscriptclosure failed): upvalues still show
H.SCRIPT_CLOSURES = {}
Loaded.load({ doorScript })
H.advance(0.3)
check("no compiled copy: the running functions' upvalues still show", hasValue(upvalues, "busy") ~= nil, upvalues.Info.Text)
H.GC = {}
Loaded.load({ doorScript })
H.advance(0.3)
check("nothing alive: says no running functions were found", upvalues.Info.Text:find("no running functions", 1, true) ~= nil, upvalues.Info.Text)
H.FILTERGC_ENV_MISS, H.FILTERGC_SOURCE_MISS = nil, nil

----------------------------------------------------------------------
-- 7. reload: the menu goes and comes back
----------------------------------------------------------------------
-- api.loaded.back for plugins
Loaded.load(Loaded.target(config))
H.advance(0.2)
Loaded.load(Loaded.target(onTouched))
H.advance(0.2)
check("api.loaded.canGoBack / previous", api.loaded.canGoBack() == true and api.loaded.previous()[1].Value == config)
check("api.loaded.back loads what was loaded before", api.loaded.back() == true and Loaded.value() == config)
Plugins.reload("scriptviewer")
H.advance(1)
record = Plugins.get("scriptviewer")
check("after reload the menu is defined once", #Menus.build("scriptviewer.row", { Item = { Kind = "entry", Parent = {}, RawKey = "a", Key = "a", Value = 1 }, Panel = "contents" }) > 0)
Plugins.stop()
H.advance(0.5)
check("stopped, its menu entries go", #Menus.build("scriptviewer.row", { Item = {}, Panel = "contents" }) <= 1)

print(("p1g: %d passed, %d failed, 0 runtime errors"):format(passed, failed))
