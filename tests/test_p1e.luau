-- Plugins stage, round 1 part 1.5: references of constants and upvalues
-- (from the plugin's list: "show upvalues, constants, and their
-- respective references"): filtergc, re-checked, in a thread, capped,
-- the function being looked at marked, a click loads a reference.
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

local shared = { speed = 3 }
local function onTouched() end
local function onClick() end
local function onHover() end
local function toolFn() end
local function unrelated() end
H.FN[onTouched] = { Constants = { "Touched", 5, "Humanoid" }, Upvalues = { shared, true }, Info = { name = "onTouched" } }
H.FN[onClick] = { Constants = { "Touched", "Click" }, Upvalues = { shared }, Info = { name = "onClick" } }
H.FN[onHover] = { Constants = { "Hover" }, Upvalues = { shared }, Info = { name = "onHover" } }
H.FN[toolFn] = { Constants = { "Touched" }, Upvalues = { shared }, Executor = true }
H.FN[unrelated] = { Constants = { "Other" }, Upvalues = { {} } }
H.GC = { onTouched, onClick, onHover, toolFn, unrelated, print }

local ok, err = H.run("Tungsten/Tungsten.luau")
check("loader runs", ok, err)
H.advance(5)
local T = genv.Tungsten.Context
local Plugins, Loaded, C = T.Plugins, T.Loaded, T.Console
local record = Plugins.get("scriptviewer")
local exports, api = record.Exports, record.Api
check("integrity lists filtergc (46 functions)", (function()
	for _, line in C.Lines do
		if line.Plain:find("50/50 executor functions", 1, true) then
			return true
		end
	end
	return false
end)())
T.Tabs:Select("scriptviewer")
H.advance(0.4)
local view = exports.view()
Loaded.load(Loaded.target(onTouched))
H.advance(0.3)
local function open(id)
	view:Select(id)
	H.advance(0.3)
	return view.Panels[id]
end
local function row(panel, key, depth)
	for _, node in panel.List:GetItems() do
		if node.Key == key and (depth == nil or node.Depth == depth) then
			return node
		end
	end
	return nil
end
local function pick(panel, node)
	panel.List:SetSelected({ node })
	H.advance(0.3)
end
local function results(panel)
	local out = {}
	for _, result in panel.RefsList:GetItems() do
		table.insert(out, result.Name)
	end
	return table.concat(out, ",")
end

----------------------------------------------------------------------
-- 1. the References area
----------------------------------------------------------------------
local constants = open("constants")
check("Constants has a References area under its list", constants.RefsFrame ~= nil and constants.RefsFrame.Visible)
check("…which says what to do first", constants.RefsInfo.Text:find("select a constant or an upvalue", 1, true) ~= nil, constants.RefsInfo.Text)
check("Functions has none (nothing to look up)", open("functions").RefsFrame == nil)

----------------------------------------------------------------------
-- 2. a constant
----------------------------------------------------------------------
pick(constants, row(constants, "1"))
check("selecting \"Touched\": the functions with that constant, this one first", results(constants) == "onTouched (this one),onClick", results(constants))
check("…where in each", constants.RefsList:GetItems()[2].Match == "constant 1")
check("…counted, without this one", constants.RefsInfo.Text == "References of constant 1: 1 other function", constants.RefsInfo.Text)
check("…executor-made functions left out (filtergc's default)", results(constants):find("toolFn", 1, true) == nil)
check("…with where each is defined", constants.RefsList:GetItems()[2].Place:find(":%d+$") ~= nil, constants.RefsList:GetItems()[2].Place)
pick(constants, row(constants, "3"))
check("a constant only this function has: 0 others", constants.RefsInfo.Text == "References of constant 3: 0 other functions", constants.RefsInfo.Text)

----------------------------------------------------------------------
-- 3. an upvalue (shared table)
----------------------------------------------------------------------
local upvalues = open("upvalues")
pick(upvalues, row(upvalues, "1", 0))
check("selecting a shared table upvalue: every function holding the same table", results(upvalues) == "onTouched (this one),onClick,onHover", results(upvalues))
check("…matched by identity (another table with the same contents isn't)", results(upvalues):find("unrelated", 1, true) == nil)
check("…as which upvalue", upvalues.RefsList:GetItems()[3].Match == "upvalue 1")
view:Toggle("upvalues", row(upvalues, "1", 0).Id)
H.advance(0.1)
pick(upvalues, row(upvalues, "speed"))
check("a table entry isn't a constant or upvalue: says so", upvalues.RefsInfo.Text:find("references are found for constants and upvalues", 1, true) ~= nil, upvalues.RefsInfo.Text)

----------------------------------------------------------------------
-- 4. re-checked, threaded, capped
----------------------------------------------------------------------
H.FILTERGC_LOOSE = true -- filtergc hands back everything
pick(upvalues, row(upvalues, "1", 0))
check("whatever filtergc returns is checked again before it is listed", results(upvalues) == "onTouched (this one),onClick,onHover", results(upvalues))
H.FILTERGC_LOOSE = nil
H.FILTERGC_WAIT = 0.5
pick(constants, row(constants, "1"))
check("searching runs in a thread and says so", constants.RefsInfo.Text:find("searching", 1, true) ~= nil, constants.RefsInfo.Text)
pick(constants, row(constants, "2"))
H.advance(1.2)
check("a newer selection wins", constants.RefsInfo.Text:find("constant 2", 1, true) ~= nil, constants.RefsInfo.Text)
H.FILTERGC_WAIT = nil
local many = {}
for index = 1, 250 do
	local fn = function() end
	H.FN[fn] = { Constants = { "Touched" } }
	table.insert(many, fn)
	table.insert(H.GC, fn)
end
pick(constants, row(constants, "1"))
check("at most 200 listed, and the bar says so", #constants.RefsList:GetItems() == 200 and constants.RefsInfo.Text:find("(first 200)", 1, true) ~= nil, constants.RefsInfo.Text)
for _ = 1, 250 do
	table.remove(H.GC)
end

----------------------------------------------------------------------
-- 5. opening a reference; Function view; missing filtergc
----------------------------------------------------------------------
pick(constants, row(constants, "1"))
local clickRow = constants.RefsList:GetItems()[2]
view:OpenReference(clickRow)
H.advance(0.3)
check("double-clicking a reference loads that function", Loaded.value() == onClick and exports.subject().Title == "onClick")
check("…and the References area clears for the new rows", constants.RefsInfo.Text:find("select a constant or an upvalue", 1, true) ~= nil, constants.RefsInfo.Text)
constants.Switch:SetValue("Function")
H.advance(0.2)
pick(constants, row(constants, "2", 1))
check("in the Function view too", results(constants) == "onClick (this one)", results(constants))
constants.Switch:SetValue("Table")
H.advance(0.2)
check("the Table view hides the References area", constants.RefsFrame.Visible == false)
constants.Switch:SetValue("Tree")
H.advance(0.2)
local saved = E_.filtergc
E_.filtergc = nil
pick(constants, row(constants, "1"))
check("filtergc missing: says so, nothing breaks", constants.RefsInfo.Text:find("filtergc is missing", 1, true) ~= nil and #H.ERRORS == 0, constants.RefsInfo.Text)
E_.filtergc = saved

check("no runtime errors", #H.ERRORS == 0, H.ERRORS[1])
for _, e in H.ERRORS do
	print("ERR: " .. e)
end
print(("p1e: %d passed, %d failed, %d runtime errors"):format(passed, failed, #H.ERRORS))
