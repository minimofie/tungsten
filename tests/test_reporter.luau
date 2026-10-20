-- Reporters (console/reporter): plugins and the explorer print info,
-- warnings and errors; faults caught by the frameworks are reported.
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
local new = H.env.Instance.new
local crate = new("Part")
crate.Name = "Crate"
crate.Parent = H.env.workspace
local locked = new("Part")
locked.Name = "Locked"
locked.Parent = H.env.workspace
rawset(locked, "_lockedParent", true)

local ok, err = H.run("Tungsten/Tungsten.luau")
check("loader runs", ok, err)
H.advance(1)
local T = H.genv.Tungsten.Context
local C, UI, Menus, E = T.Console, T.UI, T.Menus, T.Explorer
local imp = T.import
local Overlay = T.Overlay

local function mark() return #C.Lines + 1 end
local function since(at)
	local out = {}
	for i = at, #C.Lines do table.insert(out, C.Lines[i].Plain) end
	return table.concat(out, "\n")
end
local function has(at, text) return since(at):find(text, 1, true) ~= nil end

----------------------------------------------------------------------
-- 1. Plugin reporter
----------------------------------------------------------------------
local out = C.reporter("myplugin", { Label = "My Plugin" })
check("one reporter per id", C.reporter("myplugin") == out and out.Label == "My Plugin")
local at = mark()
out:info("loaded 12 items")
out:success("saved")
out:warn("3 skipped")
check("info", has(at, "[plugin] My Plugin: loaded 12 items"), since(at))
check("success", has(at, "[plugin] My Plugin: saved"))
check("warn uses [!]", has(at, "[!] My Plugin: 3 skipped"))
check("lines carry their source", C.Lines[at].Source == "myplugin")
local errorsBefore = #C.Errors.list()
local record = out:error("could not read the file", { Hints = { "check the name" } })
check("error is an [x] line with the name", has(at, "[x] My Plugin: could not read the file"), since(at))
check("its hints follow", has(at, "[?] check the name"))
check("error record kind plugin, source and label", record and record.Kind == "plugin" and record.Source == "myplugin" and record.Label == "My Plugin")
check("$err holds it", T.Variables.get("err") == record)
check("/errors has it", #C.Errors.list() == errorsBefore + 1)
at = mark()
C.run("/errors plugin")
H.advance(0.2)
check("/errors plugin lists it with the name", has(at, "My Plugin: could not read the file"), since(at))
at = mark()
C.run("/trace " .. record.Id)
H.advance(0.2)
check("/trace shows who reported it", has(at, "from     My Plugin"), since(at))
-- value
at = mark()
out:value("found ", crate)
check("value line", has(at, "[plugin] My Plugin: found") and has(at, "Crate Part <BasePart>"), since(at))
check("value icon after the name", C.Lines[at].Icon == "class_part" and C.Lines[at].IconAt == #"[plugin] " + #"My Plugin: " + #"found ", C.Lines[at].IconAt)
-- detail
at = mark()
out:detail("more")
check("detail is indented", C.Lines[at].Plain == "    more")
-- try / wrap
local okTry, value = out:try(function(a, b) return a + b end, 2, 3)
check("try returns results", okTry == true and value == 5)
at = mark()
local okFail, failRecord = out:try(function() error("boom") end)
check("try reports failures", okFail == false and has(at, "[x] My Plugin:") and has(at, "boom"), since(at))
check("try keeps the traceback", failRecord and #failRecord.Trace >= 0)
at = mark()
local safe = out:wrap(function(x) if x then error("disk full") end return "fine" end, "Saving")
check("wrap passes results", safe(false) == "fine")
safe(true)
check("wrap names what failed", has(at, "[x] My Plugin: Saving failed: ") and has(at, "disk full"), since(at))
-- folding
at = mark()
for _ = 1, 5 do out:warn("same thing") end
local count = select(2, since(at):gsub("same thing", ""))
check("repeated warnings fold", count == 1, count)
H.advance(1.3)
check("then say how often", has(at, "repeated 4 more times"), since(at))
at = mark()
for _ = 1, 3 do out:error("same error") end
H.advance(1.3)
check("repeated errors fold and are counted", select(2, since(at):gsub("same error", "")) == 1 and has(at, "repeated 2 more times"), since(at))
local rec = out:error("attempt to index nil with 'x'")
check("plugin errors don't get console-code hints", #rec.Hints == 0)
at = mark()
out:info("again")
out:info("again")
check("info is never folded", select(2, since(at):gsub("again", "")) == 2)
-- Console.plugin still works the old way
at = mark()
C.plugin("oldplug", "hello")
check("Console.plugin format kept", has(at, "[plugin] oldplug: hello"))
-- muted
out.Muted = true
at = mark()
out:info("quiet")
out:error("quiet error")
check("a muted reporter prints nothing", since(at) == "")
out.Muted = false

----------------------------------------------------------------------
-- 2. Explorer messages
----------------------------------------------------------------------
check("explorer reporter is a core source", C.reporter("explorer").Plugin == false and C.reporter("explorer").Label == "Explorer")
E.select({ crate, locked })
H.advance(0.2)
at = mark()
E.deleteNodes(E.getSelectedNodes())
H.advance(0.2)
check("explorer success line", has(at, "[+] Explorer: deleted Crate"), since(at))
check("explorer error line for the locked one", has(at, "[x] Explorer: couldn't delete Locked:") and has(at, "locked"), since(at))
check("explorer error kind", C.Errors.get().Kind == "explorer" and C.Errors.get().Label == "Explorer")
check("with a hint", has(at, "[?] locked or protected objects"))
at = mark()
H.NIL = { new("Folder") }
E.refreshNil()
check("refresh nil reports the count", has(at, "[*] Explorer: 1 object without a parent"), since(at))
at = mark()
E.select({ locked })
H.advance(0.2)
local menuMod = imp("base/explorer/menu")
local ctx = menuMod.context(E, E.getSelectedNodes(), E.getSelectedNodes()[1], V2(300, 300))
for _, item in Menus.build("explorer.object", ctx) do
	if item.Text == "Copy Path" then item.Callback(item) end
end
check("copy path reports", has(at, "[+] Explorer: copied the path of 1 object"), since(at))
T.PathBar.show(T.Explorer.getPrimary(), T.Tabs.Selected) -- what Load would show
at = mark()
for _, item in T.PathBar.menuItems() do
	if item.Text == "Copy" then item.Callback(item) end
end
check("path bar copy reports as the explorer", has(at, "[+] Explorer: copied game.Workspace.Locked"), since(at))
-- a failing entry in an explorer menu reports as the explorer
Menus.add("explorer.object", { Id = "broken", Text = "Broken", Callback = function() error("explorer action exploded") end })
at = mark()
for _, item in Menus.build("explorer.object", ctx) do
	if item.Text == "Broken" then item.Callback(item) end
end
check("explorer menu faults print as Explorer", has(at, "[x] Explorer: 'Broken' failed:") and has(at, "explorer action exploded"), since(at))
Menus.remove("explorer.object", "broken")

----------------------------------------------------------------------
-- 3. Faults caught for plugins are reported under their name
----------------------------------------------------------------------
-- menu entry callback
Menus.add("console.output", { Id = "bad", Section = "console", Text = "Bad entry", Callback = function() error("entry broke") end }, "p2")
C.reporter("p2", { Label = "Plugin Two" })
at = mark()
for _, item in Menus.build("console.output", { Output = {}, Console = C, Selected = {} }) do
	if item.Text == "Bad entry" then item.Callback(item) end
end
check("plugin menu entry fault", has(at, "[x] Plugin Two: 'Bad entry' failed: ") and has(at, "entry broke"), since(at))
-- a field that errors
Menus.add("console.output", { Id = "badtext", Section = "console", Text = function() error("text broke") end }, "p2")
at = mark()
Menus.build("console.output", { Output = {}, Console = C, Selected = {} })
check("plugin menu field fault", has(at, "[x] Plugin Two: a menu entry failed:") and has(at, "text broke"), since(at))
-- explorer function: Run and AppliesTo
E.select({ H.env.workspace })
H.advance(0.2)
E.addFunction({ Id = "explode", Text = "Explode", Owner = "p2", Run = function() error("run broke") end })
E.addFunction({ Id = "picky", Text = "Picky", Owner = "p2", AppliesTo = function() error("applies broke") end })
ctx = menuMod.context(E, E.getSelectedNodes(), E.getSelectedNodes()[1], V2(300, 300))
at = mark()
local fnItems = Menus.build("explorer.function", ctx)
local explodeItem, pickyShown = nil, false
for _, item in fnItems do
	if item.Text == "Explode" then
		explodeItem = item
	elseif item.Text == "Picky" then
		pickyShown = true
	end
end
check("AppliesTo fault reported, entry hidden", has(at, "[x] Plugin Two: AppliesTo of 'picky' failed:") and explodeItem ~= nil and not pickyShown, since(at))
explodeItem.Callback(explodeItem)
check("Run fault reported", has(at, "[x] Plugin Two: 'Explode' failed:") and has(at, "run broke"), since(at))
-- UI hooks and filters
local page = new("Frame")
page.Size = H.env.UDim2.fromOffset(300, 200)
page.Parent = T.Window.Content
UI.on("Toggle", "Changed", function() error("hook broke") end, { Owner = "p2" })
local toggle = UI.new("Toggle", { Parent = page, Origin = "p2" })
at = mark()
toggle:Set(true)
check("UI hook fault", has(at, "[x] Plugin Two: Toggle.Changed handler failed:") and has(at, "hook broke"), since(at))
UI.filter("ContextMenu", "Items", function() return "nope" end, { Owner = "p2" })
at = mark()
UI.new("ContextMenu", { Origin = "p2", Items = { { Text = "x" } }, Position = V2(300, 300) })
check("UI filter type fault", has(at, "[x] Plugin Two: ContextMenu.Items filter failed: it returned a string instead of a table"), since(at))
Overlay.closeAll()
-- picker kind and row kind
local TypePicker = imp("base/ui/components/typepicker")
TypePicker.registerKind("broken", { Owner = "p2", Options = function() error("options broke") end })
at = mark()
TypePicker.options("broken")
check("picker kind fault", has(at, "[x] Plugin Two: picker kind 'broken' failed:") and has(at, "options broke"), since(at))
local ContextMenu = imp("base/ui/components/contextmenu")
ContextMenu.addKind("brokenrow", { Owner = "p2", Build = function() error("row broke") end })
at = mark()
ContextMenu.open({ { Kind = "brokenrow", Text = "Row" } }, { Position = V2(300, 300) })
check("row kind fault", has(at, "[x] Plugin Two: menu row kind 'brokenrow' failed:") and has(at, "row broke"), since(at))
Overlay.closeAll()
-- Tungsten's own faults don't print as a plugin
UI.on("Button", "Clicked", function() error("core hook") end)
local button = UI.new("Button", { Parent = page, Text = "b" })
at = mark()
H.clickObject(button.Instance)
check("core hook faults go to the log, not the console", not has(at, "core hook"), since(at))
-- cleanup removes the reporter
UI.removeOwner("p2")
check("removeOwner drops the reporter", not imp("console/reporter").exists("p2"))
check("no runtime errors escaped", #H.ERRORS == 0, H.ERRORS[1])

for _, e in H.ERRORS do print("ERR: " .. e) end
print(("reporter: %d passed, %d failed, %d runtime errors"):format(passed, failed, #H.ERRORS))
