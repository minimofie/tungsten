-- The path bar's reload button (Loaded.reload), typed $variables, and
-- paths to nested functions: debug.getproto(f, n) and
-- debug.getproto(f, n, true)[k] (base/access).
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
local new = E_.Instance.new
local function make(class, name, parent)
	local o = new(class)
	o.Name = name
	o.Parent = parent
	return o
end
local rs = E_.game:GetService("ReplicatedStorage")
local util = make("ModuleScript", "Util", rs)
local door = make("Part", "Door", E_.workspace)

local function tick() end
local function copyA() end
local function copyB() end
local inner = { Info = { name = "inner", numparams = 1, is_vararg = 0, nups = 0 }, Constants = { "deep" } }
local proto1 = { Info = { name = "step", numparams = 2, is_vararg = 0, nups = 1 }, Constants = { "hit", 5 }, Protos = { inner }, Closures = { copyA, copyB } }
local proto2 = { Info = { name = "", numparams = 0, is_vararg = 1, nups = 0 }, Constants = {} }
local state = { hp = 10 }
H.FN[tick] = { Upvalues = { state, 7 }, Protos = { proto1, proto2 }, Info = { name = "tick" } }
H.FN[copyA] = { Upvalues = { 1 } }
local utilValue = { tick = tick }
H.LOADED = { util }
H.MODULE_VALUES = { [util] = utilValue }

local ok, err = H.run("Tungsten/Tungsten.luau")
check("loader runs", ok, err)
H.advance(5)
local T = genv.Tungsten.Context
local A, P, Loaded, C = T.Access, T.PathBar, T.Loaded, T.Console

----------------------------------------------------------------------
-- 1. The button
----------------------------------------------------------------------
local reload, go, field = P.ReloadButton, P.GoButton, P.Field
check("a reload button", reload ~= nil and reload.Name == "Reload")
check("…right of the arrow", reload and go and reload.AbsolutePosition.X > go.AbsolutePosition.X, reload and go and (reload.AbsolutePosition.X .. " vs " .. go.AbsolutePosition.X))
check("…at the bar's right end", reload and math.abs((reload.AbsolutePosition.X + reload.AbsoluteSize.X) - (P.Instance.AbsolutePosition.X + P.Instance.AbsoluteSize.X)) <= 1)
check("the field ends before the arrow", field and go and field.AbsolutePosition.X + field.AbsoluteSize.X <= go.AbsolutePosition.X)
check("greyed with nothing loaded", reload and reload:GetAttribute("Enabled") == false)
local reloaded, why = Loaded.reload()
check("Loaded.reload with nothing loaded says so", reloaded == false and why == "nothing is loaded", why)

----------------------------------------------------------------------
-- 2. Reloading
----------------------------------------------------------------------
Loaded.load({ door })
H.advance(0.1)
check("enabled once something is loaded", reload:GetAttribute("Enabled") == true)
local historyBefore = #Loaded.history()
local told = 0
local conn = Loaded.Changed:Connect(function()
	told += 1
end)
H.clickObject(reload)
H.advance(0.1)
check("clicking it loads again (every tab told)", told == 1, told)
check("…the same Instance", Loaded.get() == door)
check("…not remembered for back", #Loaded.history() == historyBefore, #Loaded.history())

-- a value inside a script is read again
local upAccess = A.upvalue(A.key(A.root(util), "tick"), 2)
Loaded.load({ Loaded.target(7, { Access = upAccess, Label = "upvalue 2" }) })
H.advance(0.1)
check("an upvalue is loaded", Loaded.value() == 7)
H.FN[tick].Upvalues[2] = 99
historyBefore = #Loaded.history()
local okReload, problem = P.reload()
H.advance(0.1)
check("reload reads it again", okReload and problem == nil and Loaded.value() == 99, Loaded.value())
check("…keeps its path", Loaded.get().Access == upAccess)
check("…not remembered for back", #Loaded.history() == historyBefore)
-- the path no longer resolves: kept as it was, the reason shown
H.LOADED = {}
okReload, problem = P.reload()
H.advance(0.1)
check("a path that no longer resolves: still loaded", okReload and Loaded.value() == 99)
check("…and says why", type(problem) == "string" and problem:find("hasn't been required", 1, true) ~= nil, problem)
check("…under the bar", type(P.LastError) == "string" and P.LastError == problem, P.LastError)
H.LOADED = { util }
-- a target without a path loads as it is
local plain = {}
Loaded.load({ Loaded.target(plain) })
okReload = P.reload()
check("a value without a path reloads as it is", okReload and Loaded.value() == plain)
conn:Disconnect()

----------------------------------------------------------------------
-- 3. Typed $variables
----------------------------------------------------------------------
T.Variables.set("door", door)
T.Variables.set("cfg", { speed = 3 })
local okGo = P.go("$door")
check("$name of an Instance loads it", okGo and Loaded.get() == door)
okGo = P.go("  $cfg ")
check("$name of a table loads it as a value", okGo and Loaded.isTarget(Loaded.get()) and Loaded.value().speed == 3)
check("…labelled $cfg", Loaded.get().Label == "$cfg", Loaded.get().Label)
local okMissing, whyMissing = P.go("$nope")
check("a missing variable is refused", not okMissing and whyMissing == "$nope doesn't exist", whyMissing)

----------------------------------------------------------------------
-- 4. Nested functions in paths
----------------------------------------------------------------------
local tickAccess = A.key(A.root(util), "tick")
local p1 = A.proto(tickAccess, 1)
check("a nested function step: code", A.code(p1) == "debug.getproto(require(game.ReplicatedStorage.Util).tick, 1)", A.code(p1))
local crumbs = A.crumbs(p1)
check("…crumb 'nested 1'", crumbs[#crumbs].Text == "nested 1", crumbs[#crumbs].Text)
local okP, value = A.resolve(p1)
check("…resolves to the ProtoProxy", okP and value == proto1 and E_.typeof(value) == "ProtoProxy", E_.typeof(value))
local deep = A.proto(p1, 1)
okP, value = A.resolve(deep)
check("a nested function of a nested function", okP and value == inner and A.code(deep) == "debug.getproto(debug.getproto(require(game.ReplicatedStorage.Util).tick, 1), 1)", A.code(deep))
local c2 = A.closure(tickAccess, 1, 2)
check("a running copy: code", A.code(c2) == "debug.getproto(require(game.ReplicatedStorage.Util).tick, 1, true)[2]", A.code(c2))
check("…crumb 'nested 1 · running 2'", A.crumbs(c2)[#A.crumbs(c2)].Text == "nested 1 · running 2")
okP, value = A.resolve(c2)
check("…resolves to the running copy", okP and value == copyB)
local up = A.upvalue(A.closure(tickAccess, 1, 1), 1)
okP, value = A.resolve(up)
check("a running copy's upvalue", okP and value == 1, value)
okP, value = A.resolve(A.closure(tickAccess, 1, 5))
check("a running copy that isn't there", not okP and tostring(value):find("no running copy 5", 1, true) ~= nil, value)
okP, value = A.resolve(A.upvalue(p1, 1))
check("a prototype has no upvalues (says to use running copies)", not okP and tostring(value):find("running copies", 1, true) ~= nil, value)
okP, value = A.resolve(A.proto(A.upvalue(tickAccess, 2), 1))
check("a nested function of a number is refused", not okP and tostring(value):find("isn't a function", 1, true) ~= nil, value)
okP, value = A.resolve(A.proto(tickAccess, 9))
check("a missing nested function: getproto's error", not okP and tostring(value):find("debug.getproto failed", 1, true) ~= nil, value)

-- parsing (never runs the text)
local parsed, whyParse = A.parse("debug.getproto(require(game.ReplicatedStorage.Util).tick, 1)")
check("parse a nested function path", parsed ~= nil and A.code(parsed) == A.code(p1), whyParse)
parsed = A.parse("debug.getproto( require(game.ReplicatedStorage.Util).tick , 1 , true )[2]")
check("parse a running copy path", parsed ~= nil and A.code(parsed) == A.code(c2), parsed and A.code(parsed))
parsed = A.parse("debug.getupvalues(debug.getproto(require(game.ReplicatedStorage.Util).tick, 1, true)[1])[1]")
check("parse an upvalue of a running copy", parsed ~= nil and A.code(parsed) == A.code(up))
parsed = A.parse("debug.getproto(debug.getproto(require(game.ReplicatedStorage.Util).tick, 1), 1)")
check("parse nested in nested", parsed ~= nil and A.code(parsed) == A.code(deep))
parsed, whyParse = A.parse("debug.getproto(require(game.ReplicatedStorage.Util).tick, 1, true)")
check("running copies need [k]", parsed == nil and whyParse:find("[1]", 1, true) ~= nil, whyParse)
parsed, whyParse = A.parse("debug.getproto(require(game.ReplicatedStorage.Util).tick)")
check("an index is needed", parsed == nil and whyParse:find("takes a function, a number", 1, true) ~= nil, whyParse)
parsed, whyParse = A.parse("debug.getproto(require(game.ReplicatedStorage.Util).tick, x)")
check("the index is a number", parsed == nil, whyParse)

-- the path bar and /load take them
okGo = P.go("debug.getproto(require(game.ReplicatedStorage.Util).tick, 1)")
check("typed in the path bar: loaded", okGo and Loaded.value() == proto1 and Loaded.get().Access ~= nil)
check("…its crumb shows", (function()
	for _, c in P.Crumbs:GetDescendants() do
		if c:IsA("TextLabel") and c.Text == "nested 1" then
			return true
		end
	end
	return false
end)())
C.run("/load debug.getproto(require(game.ReplicatedStorage.Util).tick, 1, true)[1]")
check("/load takes a running copy path", Loaded.value() == copyA, Loaded.value())
P.menuItems()
check("Copy gives the code", (function()
	for _, item in T.Menus.build("pathbar", { Access = Loaded.get().Access }) do
		if item.Id == "copy" then
			item.Callback()
		end
	end
	return H.CLIPBOARD == "debug.getproto(require(game.ReplicatedStorage.Util).tick, 1, true)[1]"
end)(), H.CLIPBOARD)
-- reload re-reads a running copy (a copy that went away keeps the old one)
H.FN[tick].Protos[1].Closures = { copyB }
okReload = P.reload()
check("reload re-reads the running copy", okReload and Loaded.value() == copyB)

check("integrity counts getproto", C.Lines[3] and C.Lines[3].Plain:find("51/51 executor functions", 1, true) ~= nil, C.Lines[3] and C.Lines[3].Plain)

print(("pathreload: %d passed, %d failed, 0 runtime errors"):format(passed, failed))
