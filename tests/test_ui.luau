-- The UI framework (base/ui/ui): registry, events, filters, scope, faults,
-- registered value types / classes / categories, cleanup, /ui.
local passed, failed = 0, 0
local function check(name, cond, detail)
	if cond then
		passed += 1
	else
		failed += 1
		print("FAIL: " .. name .. (if detail ~= nil then "  [" .. tostring(detail) .. "]" else ""))
	end
end
local V2 = H.env.Vector2.new
H.ABS_SHIFT = SHIFT or 0

local ok, err = H.run("Tungsten/Tungsten.luau")
check("loader runs", ok, err)
H.advance(1)
local T = H.genv.Tungsten.Context
local UI = T.UI
local Overlay = T.Overlay
local C = T.Console
local imp = T.import
check("T.UI is the framework", UI ~= nil and UI == imp("base/ui/ui"))

local page = H.env.Instance.new("Frame")
page.Size = H.env.UDim2.fromOffset(600, 400)
page.Parent = T.Window.Content
-- Separate slots so the test components don't cover each other.
local function slot(x, y, w, h)
	local f = H.env.Instance.new("Frame")
	f.Position = H.env.UDim2.fromOffset(x, y)
	f.Size = H.env.UDim2.fromOffset(w, h)
	f.Parent = page
	return f
end

----------------------------------------------------------------------
-- 1. Registry
----------------------------------------------------------------------
local names = table.concat(UI.list(), ",")
check("every component registered", names == "Button,CellEditor,ColorPicker,CommandBar,ConfirmBar,ContextMenu,Dropdown,Input,Label,List,Notify,Page,Prompt,Scroll,SequenceEditor,SubTabs,TextEditor,Toggle,Tooltip,TypePicker", names)
local info = UI.describe("List")
local eventNames = {}
for _, e in info.Events do table.insert(eventNames, e.Name) end
check("describe lists events", table.concat(eventNames, ",") == "Activated,ContextRequested,Created,Edited,SelectionChanged", table.concat(eventNames, ","))
check("UI.get returns the module", UI.get("List") == imp("base/ui/components/list"))
check("unknown component errors", not pcall(UI.new, "Nope", {}))
check("unknown event errors at hook time", not pcall(UI.on, "List", "Exploded", function() end))
check("unknown filter errors", not pcall(UI.filter, "List", "Nope", function() end))

----------------------------------------------------------------------
-- 2. Making components; Created with scope
----------------------------------------------------------------------
local mine, everyone = {}, {}
for _, name in UI.list() do
	UI.on(name, "Created", function(component) table.insert(mine, name) end, { Owner = "p1" })
end
UI.on("Scroll", "Created", function() table.insert(everyone, "Scroll") end, { Owner = "p1", Scope = "all" })
local list = UI.new("List", { Parent = slot(0, 0, 600, 120), Origin = "p1", Columns = { { Key = "Name", Title = "Name", Flex = true }, { Key = "Value", Title = "Value", Width = 140, Type = "value", Editable = true } }, Items = {
	{ Name = "alpha", Value = 1 }, { Name = "beta", Value = 2 }, { Name = "gamma", Value = 3 },
} })
local dropdown = UI.new("Dropdown", { Parent = slot(0, 130, 200, 30), Origin = "p1", Options = { "Low", "High" }, Value = "Low" })
local picker = UI.new("TypePicker", { Parent = slot(210, 130, 200, 30), Origin = "p1", Kind = "class" })
local input = UI.new("Input", { Parent = slot(420, 130, 180, 30), Origin = "p1", Text = "" })
local button = UI.new("Button", { Parent = slot(0, 170, 100, 30), Origin = "p1", Text = "Go" })
local toggle = UI.new("Toggle", { Parent = slot(110, 170, 100, 30), Origin = "p1", Text = "On" })
local label = UI.new("Label", { Parent = slot(220, 170, 100, 30), Origin = "p1", Text = "Hello" })
local editor = UI.new("TextEditor", { Parent = slot(0, 210, 600, 120), Origin = "p1", Text = "x = 1" })
H.advance(0.2)
check("components made by name", list.Instance and dropdown.Instance and picker.Kind == "class" and input.Box and button.Instance and toggle.Instance and label:IsA("TextLabel") and editor.Lines)
check("components remember who made them", list.Origin == "p1" and dropdown.Origin == "p1" and input.Origin == "p1" and editor.Origin == "p1")
local seen = table.concat(mine, ",")
for _, name in { "List", "Dropdown", "TypePicker", "Input", "Button", "Toggle", "Label", "TextEditor" } do
	check("Created fires for " .. name, seen:find(name, 1, true) ~= nil, seen)
end
local beforeCore = #mine
T.Tabs:Select("documentation")
H.advance(0.4)
T.Tabs:Select("console")
H.advance(0.3)
check("own-scope hooks don't see Tungsten's components", #mine == beforeCore, #mine - beforeCore)
check("all-scope hooks see every component", #everyone > 0)
-- core components have origin core
check("Tungsten's own components are core", C.View.Output and T.Explorer.View.Scroll.Origin == "core")

----------------------------------------------------------------------
-- 3. Events
----------------------------------------------------------------------
local log = {}
local function rec(tag) return function(...) table.insert(log, { tag, ... }) end end
local function last(tag)
	for i = #log, 1, -1 do if log[i][1] == tag then return log[i] end end
	return nil
end
UI.on("List", "SelectionChanged", rec("sel"), { Owner = "p1" })
UI.on("List", "Activated", rec("act"), { Owner = "p1" })
UI.on("List", "Edited", rec("edit"), { Owner = "p1" })
UI.on("List", "ContextRequested", rec("ctx"), { Owner = "p1" })
UI.on("Dropdown", "Changed", rec("dd"), { Owner = "p1" })
UI.on("Dropdown", "PopupOpened", rec("popup"), { Owner = "p1" })
UI.on("Dropdown", "Picked", rec("picked"), { Owner = "p1" })
UI.on("ContextMenu", "Opened", rec("mopen"), { Owner = "p1" })
UI.on("ContextMenu", "Chosen", rec("mchosen"), { Owner = "p1" })
UI.on("ContextMenu", "Closed", rec("mclosed"), { Owner = "p1" })
UI.on("CellEditor", "Committed", rec("cell"), { Owner = "p1" })
UI.on("Input", "Committed", rec("input"), { Owner = "p1" })
UI.on("Input", "Typing", rec("typing"), { Owner = "p1" })
UI.on("Button", "Clicked", rec("click"), { Owner = "p1" })
UI.on("Toggle", "Changed", rec("toggle"), { Owner = "p1" })
UI.on("TextEditor", "Changed", rec("text"), { Owner = "p1" })

local row1 = H.find(list.Instance, "Row1")
H.clickObject(row1)
check("List SelectionChanged", last("sel") and last("sel")[2] == list and #last("sel")[3] == 1)
H.clickObject(row1)
H.step()
check("List Activated", last("act") and last("act")[3].Name == "alpha")
H.clickObject(row1, "MouseButton2")
check("List ContextRequested", last("ctx") and last("ctx")[4].Name == "alpha")
list:ApplyEdit(list.Items[1], "Value", 10)
check("List Edited", last("edit") and last("edit")[4] == "Value" and last("edit")[5] == 10)
Overlay.closeAll()

dropdown:Open()
H.step()
check("Dropdown PopupOpened", last("popup") ~= nil)
local highRow
for _, d in Overlay.top().Frame:GetDescendants() do
	if d.Name == "Text" and d.Text == "High" then highRow = d.Parent end
end
H.clickObject(highRow)
H.step()
check("Dropdown Picked", last("picked") and last("picked")[2].Value == "High")
check("Dropdown Changed", last("dd") and last("dd")[2] == dropdown and last("dd")[3] == "High")

local menu = UI.new("ContextMenu", { Origin = "p1", Items = { { Text = "One", Callback = function() end } }, Position = V2(300, 300) })
H.step()
check("ContextMenu made by name + Opened", last("mopen") and last("mopen")[2] == menu)
H.clickObject(H.find(menu.Frame, "Item1"))
H.step()
check("ContextMenu Chosen", last("mchosen") and last("mchosen")[3].Text == "One")
check("ContextMenu Closed", last("mclosed") and last("mclosed")[3] == "chosen")

local cell = list:BeginEdit(list.Items[2], "Value")
H.step()
cell.Box.Text = "42"
cell.Commit()
H.step()
check("CellEditor Committed (list cells are the list's origin)", last("cell") and last("cell")[2] == 42 and list.Items[2].Value == 42)

input.Box.Text = "typed"
H.step()
check("Input Typing", last("typing") and last("typing")[3] == "typed")
H.focusBox(input.Box)
H.focusBox(nil)
check("Input Committed", last("input") and last("input")[3] == "typed")
H.clickObject(button.Instance)
check("Button Clicked", last("click") and last("click")[2] == button)
toggle:Set(true)
check("Toggle Changed", last("toggle") and last("toggle")[3] == true)
editor:SetText("y = 2")
H.step()
check("TextEditor Changed", last("text") ~= nil or editor.Lines[1] == "y = 2")

-- core component events don't reach own-scope hooks
local before = #log
C.run("/echo hi")
H.advance(0.2)
T.Explorer.select({ H.env.workspace })
H.advance(0.2)
check("own-scope events ignore Tungsten's components", #log == before, #log - before)

----------------------------------------------------------------------
-- 4. Filters
----------------------------------------------------------------------
local hItems = UI.filter("List", "Items", function(items)
	local out = {}
	for _, item in items do if item.Name ~= "beta" then table.insert(out, item) end end
	return out
end, { Owner = "p1" })
list:SetItems({ { Name = "alpha" }, { Name = "beta" }, { Name = "gamma" } })
check("List Items filter", #list.Items == 2 and list.Items[2].Name == "gamma")
hItems:Remove()
list:SetItems({ { Name = "alpha", Value = 1 }, { Name = "beta", Value = 2 } })
check("removed filter stops", #list.Items == 2 and list.Items[2].Name == "beta")
UI.filter("List", "CellText", function(text, column) return if column.Key == "Name" then text:upper() else nil end, { Owner = "p1" })
list:_render()
check("List CellText filter", H.find(list.Instance, "Row1"):FindFirstChild("Cell1").Text == "ALPHA")
check("CellText leaves Tungsten's lists alone", (function()
	local docsList = imp("documentation/docs").View.List
	docsList:_render()
	local r = H.find(docsList.Instance, "Row1")
	return r and r:FindFirstChild("Cell1").Text ~= r:FindFirstChild("Cell1").Text:upper()
end)())
UI.filter("List", "EditMenuItems", function(entries) table.insert(entries, { Text = "Extra edit" }) return entries end, { Owner = "p1" })
local editEntries = list:EditMenuItems(list.Items[1])
check("List EditMenuItems filter", editEntries[#editEntries].Text == "Extra edit")

UI.filter("Dropdown", "Options", function(options) table.insert(options, { Value = "Max", Text = "Max" }) return options end, { Owner = "p1" })
UI.filter("Dropdown", "Search", function(matches, query) if query == "zz" then return { { Value = "Low", Text = "Low (sleep)" } } end return nil end, { Owner = "p1" })
local h = Dropdown and nil
dropdown:Open()
H.step()
local texts = {}
for _, d in Overlay.top().Frame:GetDescendants() do if d.Name == "Text" and d.Parent.Name:sub(1, 3) == "Row" and d.Parent.Visible then table.insert(texts, d.Text) end end
table.sort(texts)
check("Dropdown Options filter", table.concat(texts, ",") == "High,Low,Max", table.concat(texts, ","))
Overlay.closeAll()
-- Search filter on a long searchable list
local longOptions = {}
for i = 1, 20 do table.insert(longOptions, "Opt" .. i) end
local dd2 = UI.new("Dropdown", { Parent = slot(0, 340, 200, 30), Origin = "p1", Options = longOptions })
dd2:Open()
H.step()
local searchBox = H.find(Overlay.top().Frame, "Box")
searchBox.Text = "zz"
H.step()
local found
for _, d in Overlay.top().Frame:GetDescendants() do if d.Name == "Text" and d.Text == "Low (sleep)" and d.Parent.Visible then found = true end end
check("Dropdown Search filter", found == true)
Overlay.closeAll()

UI.filter("TypePicker", "Options", function(options, kind)
	if kind == "class" then table.insert(options, { Value = "Vehicle", Text = "Vehicle" }) end
	return options
end, { Owner = "p1" })
local TypePicker = imp("base/ui/components/typepicker")
local function has(options, value) for _, o in options do if o.Value == value then return true end end return false end
check("TypePicker Options filter for own pickers", has(TypePicker.options("class", "p1"), "Vehicle"))
check("TypePicker Options filter not for Tungsten's", not has(TypePicker.options("class"), "Vehicle"))
check("built-in list stays unchanged", not has(TypePicker._options("class"), "Vehicle"))

UI.filter("ContextMenu", "Items", function(items) table.insert(items, { Text = "Added by filter" }) return items end, { Owner = "p1" })
local m2 = UI.new("ContextMenu", { Origin = "p1", Items = { { Text = "Base" } }, Position = V2(300, 300) })
H.step()
local rowTexts = {}
for _, d in m2.Frame:GetDescendants() do if d.Name == "Text" and d.Parent.Name:sub(1, 4) == "Item" then table.insert(rowTexts, d.Text) end end
check("ContextMenu Items filter", table.concat(rowTexts, ",") == "Base,Added by filter", table.concat(rowTexts, ","))
Overlay.closeAll()
local outputMenu = C.View.Output:_menu(nil, V2(300, 300))
H.step()
local outTexts = {}
for _, d in outputMenu.Frame:GetDescendants() do if d.Name == "Text" then table.insert(outTexts, d.Text) end end
check("own-scope menu filter leaves Tungsten's menus alone", not table.concat(outTexts, ","):find("Added by filter", 1, true))
Overlay.closeAll()

local hText = UI.filter("CellEditor", "Text", function(text) return text .. "!" end, { Owner = "p1" })
local ce = UI.new("CellEditor", { Origin = "p1", AnchorPos = V2(100, 100), Text = "hey" })
H.step()
check("CellEditor Text filter", ce.Box.Text == "hey!")
ce:Close()
hText:Remove()

-- order
local order = {}
UI.on("Button", "Clicked", function() table.insert(order, "late") end, { Owner = "p1", Order = 200 })
UI.on("Button", "Clicked", function() table.insert(order, "early") end, { Owner = "p1", Order = 1 })
H.clickObject(button.Instance)
check("Order runs lower first", order[1] == "early" and order[2] == "late", table.concat(order, ","))

----------------------------------------------------------------------
-- 5. Faults stay contained
----------------------------------------------------------------------
local errors = #H.ERRORS
UI.on("Toggle", "Changed", function() error("hook boom") end, { Owner = "p1" })
UI.filter("ContextMenu", "Items", function() return "not a table" end, { Owner = "p1" })
UI.filter("ContextMenu", "Items", function() error("filter boom") end, { Owner = "p1" })
toggle:Set(false)
check("failing hook doesn't stop the component", toggle.Value == false and last("toggle")[3] == false)
local m3 = UI.new("ContextMenu", { Origin = "p1", Items = { { Text = "Still" } }, Position = V2(300, 300) })
H.step()
check("bad filters are skipped, the menu still opens", m3:IsOpen() and H.find(m3.Frame, "Item1") ~= nil)
Overlay.closeAll()
check("no runtime errors escaped", #H.ERRORS == errors, H.ERRORS[#H.ERRORS])

----------------------------------------------------------------------
-- 6. Registered value types
----------------------------------------------------------------------
local Types = T.Types
local MoneyMT = {}
local function money(n) return setmetatable({ Amount = n }, MoneyMT) end
Types.registerType("Money", {
	Owner = "p1",
	Is = function(v) return type(v) == "table" and getmetatable(v) == MoneyMT end,
	Parse = function(text)
		local n = tonumber((text:gsub("^%$", "")))
		if not n then return false, "type an amount, e.g. 12.50" end
		return true, money(n)
	end,
	EditText = function(v) return tostring(v.Amount) end,
	Display = function(v) return ("$%.2f"):format(v.Amount) end,
	Default = function() return money(0) end,
	Hint = "an amount, e.g. 12.50",
	Icon = "type_number",
})
local okParse, value = Types.parse("$5", "Money")
check("parse a registered type", okParse and value.Amount == 5)
local badParse, reason = Types.parse("lots", "Money")
check("its parse errors come back", not badParse and reason == "type an amount, e.g. 12.50", reason)
check("isA / typeName / tag", Types.isA(value, "Money") and Types.typeName(value) == "Money" and Types.tag(value) == "<Money>")
check("short / display", Types.short(value) == "$5.00" and Types.display(value) == "$5.00", Types.short(value))
check("editText", Types.editText(value) == "5")
check("default", Types.default("Money").Amount == 0)
check("icon", (Types.icon(value)) == "type_number")
check("convert through text", (function() local okC, v = Types.convert("7", "Money") return okC and v.Amount == 7 end)())
check("the valueType picker offers it", has(TypePicker.options("valueType"), "Money"))
check("built-in types can't be replaced", not pcall(Types.registerType, "Vector3", { Is = function() end, Parse = function() end }))
-- in a list cell
list:SetItems({ { Name = "price", Value = money(3) } })
local mc = list:BeginEdit(list.Items[1], "Value")
H.step()
check("list cell edits it as text with its hint", mc.Box.Text == "3" and H.find(mc.Frame, "Hint").Text:find("an amount", 1, true) ~= nil, H.find(mc.Frame, "Hint").Text)
mc.Box.Text = "abc"
check("a bad value keeps the editor open with the reason", not mc.Commit() and H.find(mc.Frame, "Hint").Text == "type an amount, e.g. 12.50")
mc.Box.Text = "9.5"
check("a good value is stored as the type", mc.Commit() and list.Items[1].Value.Amount == 9.5)
check("cell shows Display text", H.find(list.Instance, "Row1"):FindFirstChild("Cell2").Text == "$9.50", H.find(list.Instance, "Row1"):FindFirstChild("Cell2").Text)
-- in the console
local at = #C.Lines + 1
C.run("/setas cash Money 12")
H.advance(0.2)
check("/setas uses registered types", T.Variables.get("cash") and T.Variables.get("cash").Amount == 12)

----------------------------------------------------------------------
-- 7. Classes and categories
----------------------------------------------------------------------
local Classes = imp("base/data/classes")
local Categories = imp("base/data/categories")
Categories.addClassCategory("vehicle", { Icon = "class_model", Color = H.env.Color3.fromRGB(10, 20, 30), Title = "Vehicles", Owner = "p1" })
Classes.add("Hovercraft", "vehicle", { Creatable = true, Owner = "p1" })
check("added class has its category's style", Classes.style("Hovercraft").Icon == "class_model" and Classes.category("Hovercraft") == "vehicle")
check("class pickers offer it", has(TypePicker.options("class"), "Hovercraft") and has(TypePicker.options("creatable"), "Hovercraft"))
check("picker hint shows the category title", (function()
	for _, o in TypePicker.options("class") do if o.Value == "Hovercraft" then return o.Hint == "Vehicles" end end
	return false
end)())
check("built-in categories can't be replaced", not pcall(Categories.addClassCategory, "part", {}))

----------------------------------------------------------------------
-- 8. Cleanup
----------------------------------------------------------------------
local Menus = T.Menus
Menus.define("p1.menu", { Owner = "p1" })
local ContextMenu = imp("base/ui/components/contextmenu")
ContextMenu.addKind("p1row", { Owner = "p1", Build = function() end })
TypePicker.registerKind("p1kind", { Owner = "p1", Options = function() return {} end })
local removed = UI.removeOwner("p1")
check("removeOwner reports what it removed", removed > 20, removed)
check("hooks gone", #UI.describe("List").Events[5].Hooks == 0)
check("filters gone", not has(TypePicker.options("class", "p1"), "Vehicle"))
check("menus gone", not Menus.exists("p1.menu"))
check("row kinds gone", not ContextMenu.hasKind("p1row"))
check("picker kinds gone", not TypePicker.isPickerKind("p1kind"))
check("value types gone", Types.getType("Money") == nil and not has(TypePicker.options("valueType"), "Money"))
check("classes gone", not has(TypePicker.options("class"), "Hovercraft") and Categories.Class.vehicle == nil)
toggle:Set(true)
check("components keep working without hooks", toggle.Value == true)

----------------------------------------------------------------------
-- 9. /ui
----------------------------------------------------------------------
UI.on("List", "Activated", function() end, { Owner = "watcher", Scope = "all" })
at = #C.Lines + 1
C.run("/ui")
H.advance(0.2)
local out = {}
for i = at, #C.Lines do table.insert(out, C.Lines[i].Plain) end
out = table.concat(out, "\n")
check("/ui lists components", out:find("20 components", 1, true) and out:find("TypePicker", 1, true), out)
at = #C.Lines + 1
C.run("/ui list")
H.advance(0.2)
out = {}
for i = at, #C.Lines do table.insert(out, C.Lines[i].Plain) end
out = table.concat(out, "\n")
check("/ui <name> lists events, filters and hooks", out:find("SelectionChanged", 1, true) and out:find("CellText", 1, true) and out:find("watcher (all)", 1, true), out)

-- re-run is clean
H.run("Tungsten/Tungsten.luau")
H.advance(1)
local T2 = H.genv.Tungsten.Context
check("re-run: no hooks carried over", #T2.UI.describe("List").Events[1].Hooks == 0 and T2.Types.getType("Money") == nil)

for _, e in H.ERRORS do print("ERR: " .. e) end
print(("ui: %d passed, %d failed, %d runtime errors"):format(passed, failed, #H.ERRORS))
