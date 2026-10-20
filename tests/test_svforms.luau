-- Script Viewer revamp, forms: the value field ("scriptviewer_value") is a
-- Type dropdown with only the types that fit and a value box that turns
-- into a variable picker for "variable"; every change can take a
-- $variable's value; Keep in a variable suggests a name.
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
local cfg = { speed = 3, color = E_.Color3.new(1, 0, 0) }
local function onTouched() end
H.FN[onTouched] = { Constants = { "Touched", 5 }, Upvalues = { 10, cfg, door, onTouched }, Info = { name = "onTouched", nups = 4 } }

local ok, err = H.run("Tungsten/Tungsten.luau")
check("loader runs", ok, err)
H.advance(5)
local T = genv.Tungsten.Context
local Loaded = T.Loaded
local record = T.Plugins.get("scriptviewer")
local exports, api = record.Exports, record.Api
T.Tabs:Select("scriptviewer")
H.advance(0.4)
local view = exports.view()
local Actions = view.Actions
local lastPrompt
T.UI.on("Prompt", "Opened", function(handle)
	lastPrompt = handle
end)
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
local function joined(list)
	return table.concat(list, ",")
end

----------------------------------------------------------------------
-- 1. Only the types that fit
----------------------------------------------------------------------
check("a string constant: string or a variable", joined(Actions.typesFor("constant", "a", false)) == "string,variable")
check("…with type changes on: string, number, boolean, variable", joined(Actions.typesFor("constant", "a", true)) == "string,number,boolean,variable")
check("an empty constant slot: string", joined(Actions.typesFor("constant", nil, false)) == "string,variable")
check("a number upvalue: the plain types", joined(Actions.typesFor("upvalue", 1)) == "string,number,boolean,nil,variable")
check("a table: table, nil, variable", joined(Actions.typesFor("entry", {})) == "table,nil,variable")
check("a function: function, nil, variable", joined(Actions.typesFor("upvalue", print)) == "function,nil,variable")
check("an Instance: Instance, nil, variable", joined(Actions.typesFor("entry", door)) == "Instance,nil,variable")
check("a datatype: itself, nil, variable", joined(Actions.typesFor("entry", E_.Color3.new(0, 0, 0))) == "Color3,nil,variable")
check("a new entry: the common types and variable", joined(Actions.NewEntryTypes) == "string,number,boolean,table,Instance,Vector3,CFrame,Color3,UDim2,EnumItem,function,variable")

----------------------------------------------------------------------
-- 2. The field
----------------------------------------------------------------------
Loaded.load(Loaded.target(onTouched))
H.advance(0.3)
local upvalues = open("upvalues")
local tableRow = row(upvalues, function(n)
	return n.Value == cfg
end)
T.Variables.set("other", { fresh = true })
T.Variables.set("name", "Hit")
lastPrompt = nil
Actions.editValue(view, "upvalues", tableRow)
H.advance(0.1)
local form = lastPrompt
local field = form and form.Fields.value
check("the form has one value field", field ~= nil and field.TypeBox ~= nil and field.TextBox ~= nil and field.VariableBox ~= nil)
check("…a table offers table, nil, variable", joined(field.Field.Types) == "table,nil,variable", joined(field.Field.Types))
check("…the text box shows, the picker doesn't", field.TextBox.Instance.Visible and not field.VariableBox.Instance.Visible)
field.Set({ Type = "variable" })
check("choosing variable swaps the box for the picker", not field.TextBox.Instance.Visible and field.VariableBox.Instance.Visible)
check("…which lists the variables with their types", (function()
	local seen = {}
	for _, option in field.VariableBox.Options do
		seen[option.Value] = option.Hint
	end
	return seen.other == "table" and seen.name == "string"
end)())
field.Set({ Variable = "other" })
form.Submit()
H.advance(0.2)
check("a table upvalue set from a variable", type(H.FN[onTouched].Upvalues[2]) == "table" and H.FN[onTouched].Upvalues[2].fresh == true)
check("…an undo step", T.Undo.count() >= 1)
T.Undo.undo()
H.advance(0.2)
check("…undone", H.FN[onTouched].Upvalues[2] == cfg)
-- the hint follows the type
lastPrompt = nil
Actions.editValue(view, "upvalues", row(view.Panels.upvalues, function(n)
	return n.Value == door
end))
H.advance(0.1)
field = lastPrompt.Fields.value
check("an Instance's value box hints at a path", field.TextBox.Box.PlaceholderText:find("Instance", 1, true) ~= nil, field.TextBox.Box.PlaceholderText)
check("…its text starts as the path", field.Get().Text == "game.Workspace.Door", field.Get().Text)
lastPrompt:Close("cancel")
H.advance(0.1)

-- a constant from a variable; the picker lists only what a constant can be
local constants = open("constants")
lastPrompt = nil
Actions.editValue(view, "constants", row(constants, function(n)
	return n.Value == "Touched"
end))
H.advance(0.1)
form = lastPrompt
field = form.Fields.value
check("a constant's picker leaves out tables", (function()
	for _, option in field.VariableBox.Options do
		if option.Value == "other" then
			return false
		end
	end
	return true
end)())
field.Set({ Type = "variable", Variable = "name" })
form.Submit()
H.advance(0.2)
check("a constant set from a variable", H.FN[onTouched].Constants[1] == "Hit", H.FN[onTouched].Constants[1])
check("readField: a missing variable", select(2, Actions.readField(api, { Type = "variable", Variable = "gone" })) == "$gone doesn't exist")
check("readField: text is parsed (never run)", select(2, Actions.readField(api, { Type = "number", Text = "12" })) == 12)

-- a new entry from a variable
lastPrompt = nil
Actions.addEntry(view, "upvalues", cfg, "cfg")
H.advance(0.1)
form = lastPrompt
form.Fields.key.Set("door")
form.Fields.value.Set({ Type = "variable", Variable = "other" })
form.Submit()
H.advance(0.2)
check("a new entry from a variable", type(cfg.door) == "table" and cfg.door.fresh == true)

----------------------------------------------------------------------
-- 3. Keep in a variable
----------------------------------------------------------------------
check("a name from the key", Actions.suggestName({ Key = "max speed" }) == "max", Actions.suggestName({ Key = "max speed" }))
check("…from a raw key", Actions.suggestName({ RawKey = "walk-speed", Key = "x" }) == "walk_speed")
check("…a number key gets a prefix", Actions.suggestName({ Key = "3" }) == "value_3")

check("no runtime errors", #H.ERRORS == 0, H.ERRORS[1])
print(("svforms: %d passed, %d failed, %d runtime errors"):format(passed, failed, #H.ERRORS))
