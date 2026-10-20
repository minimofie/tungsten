-- Script Viewer revamp, views: a work area that keeps the list tall (and
-- scrolls in a small window), References as a toggle, view switches that
-- run after the dropdown and can't leave it broken, the List view's search
-- and type filter, and a cap on the Table view's text.
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

local function onTouched() end
H.FN[onTouched] = { Constants = { "Touched", 5, "Humanoid" }, Upvalues = { 1, "two" }, Info = { name = "onTouched", nups = 2 } }
local data = { alpha = 1, beta = "x", gamma = { delta = 2 }, pos = E_.Vector3.new(1, 2, 3) }

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
local View = getmetatable(view)
local function open(id)
	view:Select(id)
	H.advance(0.3)
	return view.Panels[id]
end
local function keys(panel)
	local out = {}
	for _, node in panel.List:GetItems() do
		table.insert(out, node.Path or node.Key)
	end
	return table.concat(out, ",")
end

Loaded.load(Loaded.target(onTouched))
H.advance(0.3)

----------------------------------------------------------------------
-- 1. The work area
----------------------------------------------------------------------
local constants = open("constants")
check("a data sub-tab has a scrolling work area", constants.Scroll ~= nil and constants.Canvas ~= nil and constants.Canvas.Parent == constants.Scroll.Content)
local function listHeight(panel)
	return panel.ListHolder.AbsoluteSize.Y
end
check("the list is at least View.ListMin tall", listHeight(constants) >= View.ListMin, listHeight(constants))
check("the work area is at least the body's height", constants.Canvas.AbsoluteSize.Y >= constants.Body.AbsoluteSize.Y - 1)
check("References is off by default: hidden, the list takes the height", constants.RefsFrame.Visible == false and math.abs(listHeight(constants) - (constants.Canvas.AbsoluteSize.Y - 16)) <= 1, listHeight(constants))
check("…and nothing is searched", constants.RefsInfo.Text == "References: off", constants.RefsInfo.Text)
local fullHeight = listHeight(constants)
constants.RefsToggle:Set(true)
H.advance(0.2)
check("the toggle turns References on (saved)", api.settings.get("showReferences") == true and constants.RefsFrame.Visible)
check("…under the list, the list keeps its least height", listHeight(constants) >= View.ListMin and constants.RefsFrame.AbsolutePosition.Y >= constants.ListHolder.AbsolutePosition.Y + listHeight(constants), listHeight(constants))
check("…the work area grows when needed (it scrolls)", constants.Canvas.AbsoluteSize.Y >= View.ListMin + View.RefsHeight + 24)
local upvalues = open("upvalues")
check("…every panel with References follows the setting", upvalues.RefsFrame.Visible and upvalues.RefsToggle.Value == true)
constants.RefsToggle:Set(false)
H.advance(0.2)
check("off again: the list gets its height back", constants.RefsFrame.Visible == false and math.abs(listHeight(constants) - fullHeight) <= 1)

----------------------------------------------------------------------
-- 2. Switching views can't break the dropdown
----------------------------------------------------------------------
local listBefore = constants.List
constants.Switch:SetValue("List")
check("the switch is recorded at once", constants.Mode == "List" and api.settings.get("constantsView") == "List")
check("…but the work waits until after the dropdown", constants.List == listBefore and constants.Info.Text == "…", constants.Info.Text)
H.step()
check("…then the List view shows", constants.List ~= listBefore and constants.List.Columns[1].Key == "Path")
check("…with its filter row", constants.FilterRow.Visible)
constants.Switch:SetValue("Table")
constants.Switch:SetValue("Tree")
H.step()
check("a newer switch wins", constants.Mode == "Tree" and constants.ListHolder.Visible and not constants.Text.Instance.Visible and constants.Switch:GetValue() == "Tree")
check("…the filter row hides outside List", constants.FilterRow.Visible == false)
-- a view that fails says why and leaves the dropdown in step
local realCount = View.count
View.count = function()
	error("too many values")
end
constants.Switch:SetValue("List")
H.step()
View.count = realCount
check("a failing view: the bar says why", constants.Info.Text:find("couldn't show the List view", 1, true) ~= nil and constants.Info.Text:find("too many values", 1, true) ~= nil, constants.Info.Text)
check("…the dropdown still shows the view", constants.Switch:GetValue() == "List" and constants.Mode == "List")
constants.Switch:SetValue("Tree")
H.step()
check("…and the next switch works", constants.Mode == "Tree" and keys(constants) == "constant 1,constant 2,constant 3", keys(constants))
check("no runtime errors from it", #H.ERRORS == 0, H.ERRORS[1])

----------------------------------------------------------------------
-- 3. List: search and type filter
----------------------------------------------------------------------
Loaded.load(Loaded.target(data, { Label = "data" }))
H.advance(0.3)
local contents = open("contents")
contents.Switch:SetValue("List")
H.advance(0.2)
check("List: every row flat with its path", keys(contents) == "alpha,beta,gamma,gamma.delta,pos", keys(contents))
check("…the count", contents.Count.Text == "5 rows", contents.Count.Text)
contents.SearchBox:SetText("a.del")
H.advance(0.1)
check("search by key or path", keys(contents) == "gamma.delta" and contents.Count.Text == "1 of 5", keys(contents) .. " / " .. contents.Count.Text)
contents.SearchBox:SetText("X")
H.advance(0.1)
check("search by value text, any case", keys(contents) == "beta", keys(contents))
contents.SearchBox:SetText("")
contents.TypeSwitch:SetValue("number")
H.advance(0.1)
check("type filter: numbers", keys(contents) == "alpha,gamma.delta" and contents.Count.Text == "2 of 5", keys(contents))
contents.TypeSwitch:SetValue("other")
H.advance(0.1)
check("type filter: other types (a Vector3)", keys(contents) == "pos", keys(contents))
contents.SearchBox:SetText("nothing like this")
H.advance(0.1)
check("nothing matches: says so", #contents.List:GetItems() == 0 and contents.List.EmptyLabel.Text == "Nothing matches", contents.List.EmptyLabel.Text)
contents.SearchBox:SetText("")
contents.TypeSwitch:SetValue("Any type")
H.advance(0.1)
check("cleared: everything again", keys(contents) == "alpha,beta,gamma,gamma.delta,pos")

----------------------------------------------------------------------
-- 4. The Table view's text is capped
----------------------------------------------------------------------
local big = {}
for i = 1, 450 do
	local inner = {}
	for j = 1, 50 do
		inner[j] = j
	end
	big[i] = inner
end
Loaded.load(Loaded.target(big, { Label = "big" }))
H.advance(0.3)
contents.Switch:SetValue("Table")
H.advance(0.2)
local text = contents.Text:GetText()
check("a long table: a note at the top", text:sub(1, 8) == "-- long:", text:sub(1, 60))
check("…tables past the cap are KEEP", text:find("not shown: the text stops at", 1, true) ~= nil)
check("…still editable (KEEP keeps them as they are)", contents.Text.ReadOnly == false)
contents.Switch:SetValue("Tree")
H.advance(0.2)

check("no runtime errors", #H.ERRORS == 0, H.ERRORS[1])
print(("svviews: %d passed, %d failed, %d runtime errors"):format(passed, failed, #H.ERRORS))
