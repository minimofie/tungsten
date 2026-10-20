-- Script Viewer: upvalues found and changed the way they should be.
-- A script's running functions are also found by their environment's
-- `script` (a script cloned and moved keeps its old source name); a loaded
-- table (or a ModuleScript's) shows the upvalues of every function in it,
-- by key path, with real paths for the path bar; "Search all functions"
-- looks through every game function's upvalues (inside tables too) and
-- its results can be changed.
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
module.Name = "Mod"
module.Parent = rs
local moved = new("LocalScript")
moved.Name = "Moved"
moved.Parent = E_.workspace

-- a module whose table holds functions (one inside a nested table)
local settingsTable = { speed = 16, label = "fast" }
local function fnA() end
local function fnB() end
local function helperLive() end
H.FN[fnA] = { Upvalues = { 10, settingsTable }, Info = { name = "fnA" } }
H.FN[fnB] = { Upvalues = { "hello world" }, Info = { name = "fnB" } }
H.FN[helperLive] = { Upvalues = { "runner" }, Info = { name = "helperLive" } }
local modTable = { a = fnA, sub = { b = fnB }, n = 1 }
H.LOADED = { module }
H.MODULE_VALUES = { [module] = modTable }

-- a running function of the moved script: its environment says script =
-- the script, but its source name is where it was made
local movedFn = E_.loadstring("return function() end")()
setfenv(movedFn, { script = moved })
H.FN[movedFn] = { Upvalues = { "moved up", 3 }, Source = "StarterPlayer.StarterPlayerScripts.Moved", Info = { name = "movedFn" } }
local executorFn = function() end
H.FN[executorFn] = { Upvalues = { "hello there" }, Executor = true }
H.GC = { fnA, fnB, helperLive, movedFn, executorFn }
H.RUNNING = { moved }
H.FILTERGC_ENV_MISS = true

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
local function pathOf(node)
	return Actions.pathOf(view, node)
end

----------------------------------------------------------------------
-- 1. A script that was cloned and moved
----------------------------------------------------------------------
T.Explorer.load({ moved })
H.advance(0.3)
local upvalues = open("upvalues")
check("its running function is found by its environment's script", keys(upvalues) == "movedFn   line 1,1,2", keys(upvalues))
local movedRow = row(upvalues, function(n)
	return n.Value == "moved up"
end)
check("…its upvalues show", movedRow ~= nil)
local okWrite = view.Edit.write(movedRow, "changed", { Subject = exports.subject() })
check("…and can be changed", okWrite and H.FN[movedFn].Upvalues[1] == "changed")

----------------------------------------------------------------------
-- 2. A loaded table: the upvalues of the functions in it
----------------------------------------------------------------------
P.go("require(game.ReplicatedStorage.Mod)")
H.advance(0.3)
local table1 = exports.subject()
check("a loaded table", table1.Kind == "table" and view.Kind.Text:find("2 functions", 1, true) ~= nil, view.Kind.Text)
upvalues = open("upvalues")
check("Upvalues lists its functions by key path", keys(upvalues) == "fnA   a,1,2,fnB   sub.b,1", keys(upvalues))
local ten = row(upvalues, function(n)
	return n.Value == 10
end)
check("an upvalue's path from the table", pathOf(ten) == nil, pathOf(ten)) -- a number: no Copy path
check("…but its path is known", T.Access.code(Actions.accessOf(api, exports.subject(), ten)) == "debug.getupvalues(require(game.ReplicatedStorage.Mod).a)[1]")
local tableUp = row(upvalues, function(n)
	return n.Value == settingsTable
end)
check("a table upvalue: Copy path", pathOf(tableUp) == "debug.getupvalues(require(game.ReplicatedStorage.Mod).a)[2]", pathOf(tableUp))
view:Toggle("upvalues", tableUp.Id)
H.advance(0.1)
local speed = row(upvalues, function(n)
	return n.RawKey == "speed"
end)
check("its entries show when opened", speed ~= nil and speed.Value == 16)
check("an entry's path goes through the upvalue", T.Access.code(Actions.accessOf(api, exports.subject(), speed)) == "debug.getupvalues(require(game.ReplicatedStorage.Mod).a)[2].speed")
okWrite = view.Edit.write(speed, 32, { Subject = exports.subject() })
check("an entry of a table upvalue can be changed", okWrite and settingsTable.speed == 32)
local fnHeading = row(upvalues, function(n)
	return n.Kind == "heading" and n.Value == fnB
end)
check("a function heading's path", pathOf(fnHeading) == "require(game.ReplicatedStorage.Mod).sub.b", pathOf(fnHeading))
Actions.inspect(view, tableUp)
H.advance(0.3)
check("Inspect the table upvalue: the path bar shows where it is", Loaded.value() == settingsTable and T.Access.code(Loaded.get().Access) == "debug.getupvalues(require(game.ReplicatedStorage.Mod).a)[2]")
check("…its summary", view.Kind.Text:find("table", 1, true) == 1 and view.Kind.Text:find("2 entries", 1, true) ~= nil, view.Kind.Text)
check("…its Upvalues says it has no functions", view.Panels.upvalues.Why ~= nil and view.Panels.upvalues.Why:find("no Luau functions", 1, true) ~= nil, view.Panels.upvalues.Why)

-- Contents: a nested entry's path
P.go("require(game.ReplicatedStorage.Mod)")
H.advance(0.3)
local contents = open("contents")
local sub = row(contents, function(n)
	return n.RawKey == "sub"
end)
view:Toggle("contents", sub.Id)
H.advance(0.1)
local bRow = row(contents, function(n)
	return n.RawKey == "b"
end)
check("a nested entry's Copy path", pathOf(bRow) == "require(game.ReplicatedStorage.Mod).sub.b", pathOf(bRow))

-- a ModuleScript: its table's functions first, then other running ones
T.Explorer.load({ module })
H.advance(0.3)
H.SENV = { [module] = {} }
upvalues = open("upvalues")
check("a ModuleScript: its table's functions by path", keys(upvalues):find("fnA   a", 1, true) == 1, keys(upvalues))

----------------------------------------------------------------------
-- 3. Search all functions
----------------------------------------------------------------------
Loaded.load(Loaded.target(fnA))
H.advance(0.3)
upvalues = open("upvalues")
check("the scope offers Search all functions", table.find(upvalues.ScopeSwitch.Options, "Search all functions") ~= nil or (function()
	for _, o in upvalues.ScopeSwitch.Options do
		if (type(o) == "table" and o.Value or o) == "Search all functions" then
			return true
		end
	end
	return false
end)())
view:SetScope("upvalues", "Search all functions")
H.advance(0.2)
check("…a search row shows", upvalues.ScanRow.Visible and upvalues.ListHolder.AbsolutePosition.Y > upvalues.ScanRow.AbsolutePosition.Y)
check("…and says what to do", upvalues.Why ~= nil and upvalues.Why:find("press Search", 1, true) ~= nil, upvalues.Why)
upvalues.ScanBox:SetText("hello")
H.clickObject(upvalues.ScanButton.Instance)
H.advance(0.5)
check("a text search: the functions whose upvalues match", keys(upvalues):find("fnB", 1, true) == 1 and #upvalues.List:GetItems() == 2, keys(upvalues))
check("…the executor's own functions are left out", not keys(upvalues):find("hello there", 1, true))
check("…the bar counts what was looked at", upvalues.Info.Text:find("functions looked at", 1, true) ~= nil, upvalues.Info.Text)
local hello = row(upvalues, function(n)
	return n.Value == "hello world"
end)
check("a result's path", T.Access.code(Actions.accessOf(api, exports.subject(), hello)) == "debug.getupvalues(require(game.ReplicatedStorage.Mod).sub.b)[1]")
okWrite = view.Edit.write(hello, "bye", { Subject = exports.subject() })
view:Refresh()
H.advance(0.2)
check("a result can be changed, and shows its new value", okWrite and H.FN[fnB].Upvalues[1] == "bye" and row(upvalues, function(n)
	return n.Value == "bye"
end) ~= nil)
upvalues.ScanBox:SetText("16")
view:ScanUpvalues("upvalues")
H.advance(0.5)
check("a number search without tables finds nothing in tables (and says so)", upvalues.Why ~= nil and upvalues.Why:find("Search inside tables", 1, true) ~= nil, upvalues.Why)
upvalues.ScanBox:SetText("speed")
upvalues.ScanTables:Set(true)
view:ScanUpvalues("upvalues")
H.advance(0.5)
local found = row(upvalues, function(n)
	return n.Value == settingsTable
end)
check("inside tables: the table upvalue, with how many entries match", found ~= nil and found.Note == "1 matching entry", found and found.Note)
view:Toggle("upvalues", found.Id)
H.advance(0.1)
local speedHit = row(upvalues, function(n)
	return n.RawKey == "speed"
end)
check("…it opens into the matching entries", speedHit ~= nil and speedHit.Value == 32 and #upvalues.List:GetItems() == 3, #upvalues.List:GetItems())
okWrite = view.Edit.write(speedHit, 50, { Subject = exports.subject() })
check("…which can be changed", okWrite and settingsTable.speed == 50)
upvalues.ScanBox:SetText("x")
view:ScanUpvalues("upvalues")
H.advance(0.5)
check("too short a search says so", upvalues.Why ~= nil and upvalues.Why:find("two characters", 1, true) ~= nil, upvalues.Why)
view:SetScope("upvalues", "This function")
H.advance(0.2)
check("back to This function: the search row hides", upvalues.ScanRow.Visible == false and keys(upvalues) == "1,2", keys(upvalues))

check("no runtime errors", #H.ERRORS == 0, H.ERRORS[1])
print(("svupvalues: %d passed, %d failed, %d runtime errors"):format(passed, failed, #H.ERRORS))
