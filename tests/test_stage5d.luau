-- Stage 5 Round A, part 4: variables across plugins. Every variable has
-- an owner; a plugin changes only its own, you change any; names someone
-- has are refused, not overwritten; watches say who changed a variable;
-- a plugin's watches, variables and undo steps go when it stops.
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
local V2 = E_.Vector2.new
H.ABS_SHIFT = SHIFT or 0
local genv = H.genv

local ROOT = "Tungsten/plugins/"
for _, folder in { "Alpha", "Beta" } do
	local prefix = "fixtures/plugins/" .. folder .. "/"
	for path, content in H.FILES do
		if path:sub(1, #prefix) == prefix then
			H.FILES[ROOT .. folder .. "/" .. path:sub(#prefix + 1)] = content
		end
	end
end
H.FILES["Tungsten/base/plugins.json"] = '{"On":["alpha","beta"]}'
local part = H.part("Door", E_.workspace)

local ok, err = H.run("Tungsten/Tungsten.luau")
check("loader runs", ok, err)
H.advance(5)
local T = genv.Tungsten.Context
local Variables = T.Variables
local Plugins = T.Plugins
local C = T.Console
check("both plugins on", Plugins.get("alpha").State == "on" and Plugins.get("beta").State == "on")

local function run(input)
	local before = #C.Lines
	C.run(input)
	H.advance(0.1)
	local out = {}
	for index = before + 1, #C.Lines do
		table.insert(out, C.Lines[index].Plain)
	end
	return table.concat(out, "\n")
end
local function has(text, piece)
	return text:find(piece, 1, true) ~= nil
end

----------------------------------------------------------------------
-- 1. owners and the rules between plugins
----------------------------------------------------------------------
do
	check("Alpha owns $shared", Variables.owner("shared") == "alpha" and Variables.get("shared") == "alpha")
	check("Beta can't overwrite it", genv.BetaSet[1] == false and genv.BetaSet[2] == "$shared belongs to alpha", genv.BetaSet[2])
	check("Beta can't unset it", genv.BetaUnset[1] == false and genv.BetaUnset[2] == "$shared belongs to alpha")
	check("Beta can read it, and see whose it is", genv.BetaRead == "alpha" and genv.BetaOwner == "alpha")
	check("Beta owns its own", Variables.owner("betavar") == "beta")
	local beta = Plugins.get("beta").Api
	check("a plugin may change its own", beta.variables.set("betavar", 2) and Variables.get("betavar") == 2)
	check("Variables.canWrite says why", select(2, Variables.canWrite("shared", "beta")) == "$shared belongs to alpha")
	check("info carries the owner", Variables.info("shared").Owner == "alpha")
end

----------------------------------------------------------------------
-- 2. you and plugins
----------------------------------------------------------------------
do
	run("/set door = 1")
	check("your variable is yours", Variables.owner("door") == "you")
	local alpha = Plugins.get("alpha").Api
	local okSet, why = alpha.variables.set("door", 2)
	check("a plugin can't take a name you have", okSet == false and why == "$door belongs to you" and Variables.get("door") == 1, why)
	check("…or unset it", alpha.variables.unset("door") == false and Variables.has("door"))

	local seen = #genv.AlphaSeen
	local at = run('/set shared = "mine"')
	check("you may change a plugin's variable", Variables.get("shared") == "mine", at)
	check("…it stays the plugin's", Variables.owner("shared") == "alpha")
	local last = genv.AlphaSeen[#genv.AlphaSeen]
	check("…and its watch is told you changed it (by = console)", #genv.AlphaSeen == seen + 1 and last.Value == "mine" and last.By == "console", last and last.By)
	check("the plugin may still change it after you did", alpha.variables.set("shared", "alpha again") and Variables.get("shared") == "alpha again")
	last = genv.AlphaSeen[#genv.AlphaSeen]
	check("…its own change says by = alpha", last.By == "alpha")

	at = run("/vars")
	check("/vars names a plugin's variables' owner", has(at, "owned by alpha") and has(at, "owned by beta"), at)

	-- the explorer's Variable menu names the owner too
	alpha.variables.set("thing", part)
	H.advance(0.1) -- the explorer's variable badges update on the next frame
	local E = T.Explorer
	local node = E.Tree:NodeFor(part)
	local ctx = T.import("base/explorer/menu").context(E, { node }, node, V2(10, 10))
	local unsetText
	for _, item in T.Menus.build("explorer.variable", ctx) do
		if type(item.Text) == "string" and item.Text:sub(1, 5) == "Unset" then
			unsetText = item.Text
		end
	end
	check("explorer › Variable › Unset says whose it is", unsetText == "Unset $thing (alpha)", unsetText)

	at = run("/unset betavar")
	check("you may unset a plugin's variable", not Variables.has("betavar"), at)
end

----------------------------------------------------------------------
-- 3. a plugin stopping takes its variables, watches and undo steps
----------------------------------------------------------------------
do
	local Undo = T.Undo
	local alphaSteps = 0
	for _, entry in Undo.list() do
		if entry.Owner == "alpha" then
			alphaSteps += 1
		end
	end
	check("a plugin's own variable changes are its undo steps", alphaSteps > 0, alphaSteps)

	-- one of your steps that will bring back an Alpha variable
	run('/set shared = "yours for a moment"')
	local changesBefore = genv.AlphaChanges
	Plugins._disable(Plugins.get("alpha"))
	check("Alpha off: its variables are gone", not Variables.has("shared") and not Variables.has("thing"))
	local leftover = 0
	for _, entry in Undo.list() do
		if entry.Owner == "alpha" then
			leftover += 1
		end
	end
	check("Alpha off: its undo steps are gone", leftover == 0, leftover)
	local seenBefore = #genv.AlphaSeen
	run("/set door = 5")
	run("/set something = 1")
	check("Alpha off: its watch and Changed listener don't run any more", #genv.AlphaSeen == seenBefore and genv.AlphaChanges == changesBefore, genv.AlphaChanges - changesBefore)
	check("Beta is untouched", Plugins.get("beta").State == "on" and Variables.owner("door") == "you")

	-- undo your /set door = 5 and /set something, then the /set shared one
	run("/undo")
	run("/undo")
	local at = run("/undo")
	check("undoing your step brings $shared back", Variables.get("shared") == "alpha again", Variables.get("shared"))
	check("…as yours, since Alpha isn't running", Variables.owner("shared") == "you")
	check("…and the console says so", has(at, "$shared came back as yours (alpha isn't running)"), at)
end

----------------------------------------------------------------------
-- 4. reload: the old copy's listeners don't stack
----------------------------------------------------------------------
do
	local beta = Plugins.get("beta")
	local co = coroutine.create(function()
		Plugins.reload("beta")
	end)
	coroutine.resume(co)
	H.advance(0.2)
	check("reload: Beta on again", Plugins.get("beta").State == "on")
	check("reload: its variable is back and its own", Variables.owner("betavar") == "beta")
	check("reload: $shared is yours now, so Beta still can't take it", genv.BetaSet[1] == false and genv.BetaSet[2] == "$shared belongs to you", genv.BetaSet[2])
	check("no runtime errors", #H.ERRORS == 0, H.ERRORS[1])
end

print(("stage5d: %d passed, %d failed, %d runtime errors"):format(passed, failed, #H.ERRORS))
