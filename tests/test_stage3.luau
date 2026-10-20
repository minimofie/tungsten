-- Stage 3: console, variables, types, prefixes, commands, documentation tab.
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

-- A part named Baseplate in the mock workspace.
local workspaceObj = H.env.workspace
local baseplate = H.env.Instance.new("Part")
baseplate.Name = "Baseplate"
baseplate.Parent = workspaceObj

local ok, err = H.run("Tungsten/Tungsten.luau")
check("loader runs", ok, err)
H.advance(1)
local T = H.genv.Tungsten.Context
local C = T.Console
local Variables = T.Variables
local Types = T.Types
local imp = T.import

local function lines(from)
	local out = {}
	for index = from or 1, #C.Lines do
		table.insert(out, C.Lines[index].Plain)
	end
	return out
end
local function mark()
	return #C.Lines + 1
end
local function since(from)
	return table.concat(lines(from), "\n")
end
local function has(from, text)
	return since(from):find(text, 1, true) ~= nil
end
local function run(text)
	local at = mark()
	C.run(text)
	H.step()
	return at
end

----------------------------------------------------------------------
-- 1. Welcome + /help
----------------------------------------------------------------------
check("version 0.4.0", T.Version == "0.4.0")
check("welcome line 1", C.Lines[1] and C.Lines[1].Plain:find("tungsten (unified) v0.4.0", 1, true) and C.Lines[1].Plain:find("MockVolt 1.3", 1, true), C.Lines[1] and C.Lines[1].Plain)
check("welcome: load time and plugins", C.Lines[2] and C.Lines[2].Plain:find("loaded in %d+ ms") and C.Lines[2].Plain:find("0 plugins loaded", 1, true), C.Lines[2] and C.Lines[2].Plain)
check("welcome: integrity line", C.Lines[3] and C.Lines[3].Plain:find("integrity", 1, true) and C.Lines[3].Plain:find("files", 1, true), C.Lines[3] and C.Lines[3].Plain)
local helpLine
for i = 3, math.min(#C.Lines, 12) do
	if C.Lines[i].Plain:find("/help", 1, true) and C.Lines[i].Plain:sub(1, 3) == "[*]" then
		helpLine = C.Lines[i]
	end
end
check("welcome: how to start", helpLine ~= nil and helpLine.Plain:find("command bar", 1, true))
local view = C.View
check("console tab built at start", view ~= nil)
check("output rows exist for welcome", view and view.Output.Rows[1] and view.Output.Rows[1].Row.Visible)
check("input has no hint text (Up/Down history is in the docs)", view.Hint == nil and view.Bar:FindFirstChild("Hint") == nil)
check("docs note Up/Down history", T.Docs.search("history")[1] ~= nil)

local at = run("/help")
check("/help echoes", C.Lines[at].Plain == "[>] /help")
for _, name in { "/set", "/get", "/vars", "/unset", "/scale", "/logs", "/settings", "/exit", "/clear", "/echo", "/rename", "/watch", "/bench", "/alias", "/fps", "/docs" } do
	check("/help lists " .. name, has(at, name .. " ") or has(at, name .. "\n"))
end
check("/help header is [?]", C.Lines[at + 1].Plain:sub(1, 3) == "[?]", C.Lines[at + 1].Plain)

----------------------------------------------------------------------
-- 2. Variables and code
----------------------------------------------------------------------
at = run("/set a = 5")
check("/set a = 5", has(at, "[+] a = 5 <number>"), since(at))
at = run("/get a")
check("/get a gives 5 <number>", has(at, "5 <number>"), since(at))
at = run("> $a * 2")
check("> $a * 2 gives 10", has(at, "[+] 10 <number>"), since(at))
check("$last holds 10", Variables.get("last") == 10)
at = run("$a + 1")
check("$ prefix runs code", has(at, "6 <number>"), since(at))
at = run("> a + 100")
check("plain name works in code", has(at, "105 <number>"), since(at))

----------------------------------------------------------------------
-- 3. Instances in variables
----------------------------------------------------------------------
at = run("> x = workspace.Baseplate")
check("assignment makes a variable", Variables.get("x") == baseplate)
check("assignment reports", has(at, "x = ") and has(at, "Baseplate Part <BasePart>"), since(at))
at = run("/vars")
check("/vars shows x Part <BasePart>", has(at, "Baseplate Part <BasePart>"), since(at))
local xLine
for index = at, #C.Lines do
	if C.Lines[index].Plain:find("Baseplate", 1, true) then
		xLine = C.Lines[index]
	end
end
check("/vars row has the class icon", xLine and xLine.Icon == "class_part", xLine and xLine.Icon)
check("Types.tag", Types.tag(5) == "<number>" and Types.tag(baseplate) == "Part <BasePart>", Types.tag(baseplate))
check("Types.short string", Types.short("hi") == '"hi"')
at = run("/vars number")
check("/vars filters by type", has(at, "a ") and not has(at, "Baseplate"), since(at))

----------------------------------------------------------------------
-- 4. Errors don't break the console
----------------------------------------------------------------------
at = run("/frobnicate")
check("unknown command [x]", has(at, '[x] unknown command "frobnicate"'), since(at))
at = run("/hlep")
check("did you mean", has(at, "did you mean /help"), since(at))
at = run("> error('boom')")
check("Luau error [x]", has(at, "[x] console:1: boom"), since(at))
at = run("> 1 +")
check("compile error [x]", has(at, "[x] console:"), since(at))
at = run("> nosuchthing.field")
check("runtime error [x]", has(at, "[x]"), since(at))
at = run("> $nope")
check("unknown $var [x]", has(at, "unknown variable $nope"), since(at))
at = run("/get a")
check("console works after errors", has(at, "5 <number>"))
check("no runtime errors so far", #H.ERRORS == 0, H.ERRORS[1])

----------------------------------------------------------------------
-- 5. Input: history, Tab, live suggestions
----------------------------------------------------------------------
local box = view.Box
local function typeText(text)
	H.focusBox(box)
	box.CursorPosition = #text + 1
	box.Text = text
	H.step()
end
local function enter(text)
	if text then
		typeText(text)
	end
	H.focused = nil
	box.FocusLost:Fire(true)
	H.step()
	H.step()
end

at = mark()
enter("/echo first")
check("Enter runs the input", has(at, "[*] first"), since(at))
check("input cleared after Enter", box.Text == "")
check("input refocused after Enter", H.focused == box)
enter("/echo second")
H.key("Up")
check("Up recalls newest", box.Text == "/echo second", box.Text)
H.key("Up")
check("Up again goes older", box.Text == "/echo first", box.Text)
H.key("Down")
check("Down goes newer", box.Text == "/echo second", box.Text)
H.key("Down")
check("Down past newest restores the draft", box.Text == "", box.Text)

typeText("/he")
H.key("Tab")
check("Tab completes a command", box.Text == "/help ", box.Text)
typeText("/get $l")
H.key("Tab")
check("Tab completes $variables", box.Text == "/get $last", box.Text)
typeText("/get $")
check("several matches open the list while typing", view.Completion:IsOpen())
check("list is on the overlay", view.Completion.Panel and view.Completion.Panel:IsDescendantOf(T.Overlay.layer()))
H.key("Down")
local highlighted = view.Completion:Current()
H.key("Tab")
check("Tab takes the highlighted match", highlighted and box.Text == "/get " .. highlighted.Text and highlighted.Text ~= "$a", box.Text)
check("list closed after taking", not view.Completion:IsOpen())
typeText("/s")
check("typing /s shows suggestions live", view.Completion:IsOpen())
local labels = {}
for _, item in view.Completion.Items do
	table.insert(labels, item.Label)
end
check("suggestions include /set and /scale", table.find(labels, "/set") and table.find(labels, "/scale"), table.concat(labels, ","))
local panelPos = view.Completion.Panel.AbsolutePosition
check("list sits above the input", panelPos.Y + view.Completion.Panel.AbsoluteSize.Y <= view.Bar.AbsolutePosition.Y, tostring(panelPos))
H.key("Escape")
check("Escape closes suggestions", not view.Completion:IsOpen())
view:SetText("/get $")
H.key("Tab")
check("Tab with no list open fills the shared part and opens it", view.Completion:IsOpen() and box.Text == "/get $", box.Text)
T.Overlay.closeAll()
typeText("/unset ")
H.key("Tab")
check("argument completion lists variables", view.Completion:IsOpen() or box.Text:find("/unset a", 1, true), box.Text)
T.Overlay.closeAll()
typeText("x\ty")
check("tab characters are removed", box.Text == "xy", box.Text)
view:SetText("")

----------------------------------------------------------------------
-- 6. [game] output, escaping
----------------------------------------------------------------------
local LogService = H.services.LogService
check("game output off by default", T.Settings.get("ConsoleGameOutput") == false)
at = mark()
LogService.MessageOut:Fire("hidden message", H.env.Enum.MessageType.MessageOutput)
H.step()
check("off: game prints not shown", not has(at, "hidden message"))
run("/game on")
check("/game on saves", T.Settings.get("ConsoleGameOutput") == true)
at = mark()
LogService.MessageOut:Fire("Round 3 starting <b>now</b>", H.env.Enum.MessageType.MessageOutput)
LogService.MessageOut:Fire("careful", H.env.Enum.MessageType.MessageWarning)
H.step()
H.step()
check("[game] line shows the text literally", has(at, "[game] Round 3 starting <b>now</b>"), since(at))
local gameLine = C.Lines[at]
check("warn tinted", C.Lines[at + 1] and C.Lines[at + 1].Segments[2].Color == "Warning")
local shownEscaped = false
for _, entry in view.Output.Rows do
	if entry.Line == gameLine and entry.Row.Visible then
		shownEscaped = entry.Label.RichText == true and entry.Label.Text:find("&lt;b&gt;now&lt;/b&gt;", 1, true) ~= nil and not entry.Label.Text:find("<b>", 1, true)
	end
end
check("drawn escaped (shows <b> literally)", shownEscaped)
run("/game off")
at = mark()
LogService.MessageOut:Fire("after off", H.env.Enum.MessageType.MessageOutput)
H.step()
check("/game off stops mirroring", not has(at, "after off"))
check("one MessageOut connection at most", LogService.MessageOut:Count() == 0, LogService.MessageOut:Count())
at = run("> print('from code', 1)")
check("print in code writes [*]", has(at, "[*] from code  1"), since(at))

----------------------------------------------------------------------
-- 7. /scale
----------------------------------------------------------------------
local before = T.Window.Size
at = run("/scale 1.2")
H.advance(0.5)
check("/scale 1.2 applies", T.Scale.effective() == 1.2 and has(at, "scale 1.20"), since(at))
check("window resized", T.Window.Size.X > before.X, tostring(T.Window.Size))
at = run("/scale 9")
check("/scale too big warns and stops at the screen limit", has(at, "[!]") and T.Scale.effective() == T.Scale.limit(), since(at))
run("/scale 1.2")

----------------------------------------------------------------------
-- 8. Prefixes
----------------------------------------------------------------------
at = run("= {1, 2, {3}}")
check("= shows [=] and expands", has(at, "[=] ") and has(at, "[1] = 1"), since(at))
at = run("= workspace.Baseplate")
check("= shows an Instance's path", has(at, "path") and has(at, "Baseplate"), since(at))
at = run("?set")
check("?set is help for /set", has(at, "[?] /set") and has(at, "usage"), since(at))
at = run("?")
check("? alone lists commands", has(at, "commands ·"), since(at))
run("/echo again")
at = run("!!")
check("!! reruns the last input", has(at, "[>] /echo again") and has(at, "[*] again"), since(at))
at = run("!/set")
check("!/set recalls by prefix", has(at, "[>] /set a = 5"), since(at))
at = run("!999")
check("!999 is an error", has(at, "[x] no history entry"), since(at))
at = run("# looking at the spawn")
check("# writes a note", has(at, "[#] looking at the spawn"), since(at))
at = run("/set n = 1 && /inc n && /get n")
check("&& runs in order", Variables.get("n") == 2 and has(at, "2 <number>"), since(at))
at = run("/nope && /echo never")
check("&& stops at a failure", not has(at, "[*] never") and has(at, "[?] stopped"), since(at))
at = run('/echo "a && b"')
check("&& inside quotes is text", has(at, "[*] a && b"), since(at))
at = run("/help prefixes")
check("/help prefixes lists input prefixes", has(at, "?set") and has(at, "!!") and has(at, "&&"), since(at))
check("/help prefixes lists output prefixes", has(at, "[=]") and has(at, "[$]") and has(at, "[~]") and has(at, "[game]"), since(at))
at = run("help")
check("bare command word still runs", has(at, "commands ·"))
at = run("blah blah")
check("bare text explains prefixes", has(at, "[x] commands start with /"), since(at))

----------------------------------------------------------------------
-- 9. Variable commands
----------------------------------------------------------------------
at = run("/text greet hello $a there")
check("/text", Variables.get("greet") == "hello 5 there", Variables.get("greet"))
run("/rename greet hi")
check("/rename", Variables.get("hi") == "hello 5 there" and not Variables.has("greet"))
run("/set t = {1, {2}}")
run("/dup t t2")
local t, t2 = Variables.get("t"), Variables.get("t2")
check("/dup copies tables", t ~= t2 and t2[2] == t[2])
run("/dup t t3 deep")
check("/dup deep", Variables.get("t3")[2] ~= t[2] and Variables.get("t3")[2][1] == 2)
run("/set p = 1")
run("/set q = 2")
run("/swap p q")
check("/swap", Variables.get("p") == 2 and Variables.get("q") == 1)
run("/inc k")
run("/inc k 4")
run("/dec k 2")
check("/inc /dec", Variables.get("k") == 3, Variables.get("k"))
at = run("/inc greetx")
at = run("/inc hi")
check("/inc on text fails", has(at, "not a number"), since(at))
run("/push list 10")
run('/push list "b"')
check("/push makes and fills a table", type(Variables.get("list")) == "table" and #Variables.get("list") == 2)
at = run("/pop list")
check("/pop", #Variables.get("list") == 1 and has(at, '"b"'), since(at))
at = run("/len t")
check("/len table", has(at, "2 entries"), since(at))
at = run("/keys t")
check("/keys", has(at, "1 ") and has(at, "{2}"), since(at))
at = run("/isa x BasePart")
check("/isa yes", has(at, "[+] $x is a BasePart"), since(at))
at = run("/isa a string")
check("/isa no", has(at, "[!] $a is not a string"), since(at))
run("/set v = 5")
run("/export v t")
check("/export copies Luau", H.CLIPBOARD and H.CLIPBOARD:find("local v = 5", 1, true) and H.CLIPBOARD:find("local t = {", 1, true), H.CLIPBOARD)
check("a plugin can't change a variable you made", Variables.set("v", 6, { Source = "testplugin" }) == false and Variables.get("v") == 5)
Variables.set("pv", 1, { Source = "testplugin" })
run("/watch pv")
at = mark()
Variables.set("pv", 6, { Source = "testplugin" })
H.step()
check("/watch prints [$] on change", has(at, "[$] $pv = 6 <number>") and has(at, "testplugin"), since(at))
run("/unwatch pv")
Variables.unset("pv")
run("/watch v")
run("/unwatch v")
at = mark()
Variables.set("v", 7)
H.step()
check("/unwatch stops", not has(at, "[$]"))
at = run("/set last = 1")
check("reserved $last can't be set", has(at, "reserved"), since(at))
at = run("/unset nonexist")
check("/unset missing warns", has(at, "[!] no variable $nonexist"), since(at))
run("/unset p q")
check("/unset several", not Variables.has("p") and not Variables.has("q"))
at = run("/type $x")
check("/type describes", has(at, "class  Part") and has(at, "base   BasePart"), since(at))
check("Types.literal", Types.literal({ 1, a = "x" }):find('a = "x"', 1, true) ~= nil)

----------------------------------------------------------------------
-- 10. Tool, game and window commands
----------------------------------------------------------------------
run("/alias hey = /echo hey there")
at = run("/hey")
check("/alias runs", has(at, "[*] hey there"), since(at))
run("/unalias hey")
at = run("/hey")
check("/unalias removes", has(at, "unknown command"), since(at))
run("/set rc = 0")
run("/repeat 3 /inc rc")
check("/repeat", Variables.get("rc") == 3, Variables.get("rc"))
at = run("/echo go && /wait 1 && /echo done")
check("/wait pauses a chain", has(at, "[*] go") and not has(at, "[*] done"))
H.advance(1.2)
check("chain resumes after /wait", has(at, "[*] done"), since(at))
at = run("/bench 50 > 1 + 1")
check("/bench prints [~]", has(at, "[~] 50 runs"), since(at))
at = run("/time")
check("/time prints [~]", has(at, "[~] "), since(at))
at = run("/about")
check("/about", has(at, "tungsten (unified) v0.4.0") and has(at, "executor"), since(at))
at = run("/log hello log")
H.advance(1)
check("/log writes the log", T.Log.File and H.FILES[T.Log.File]:find("hello log", 1, true) ~= nil)
at = run("/savelog Tungsten/logs/test_dump.txt")
check("/savelog writes a file", H.FILES["Tungsten/logs/test_dump.txt"] and H.FILES["Tungsten/logs/test_dump.txt"]:find("/savelog", 1, true) ~= nil)
at = run("/files Tungsten/console")
check("/files lists", has(at, "commands.luau"), since(at))
at = run("/run ../escape.luau")
check("/run rejects escaping paths", has(at, "[x]"), since(at))
H.FILES["myscript.luau"] = "return a * 3"
at = run("/run myscript.luau")
check("/run runs with variables", has(at, "15 <number>"), since(at))
at = run("/accent #FF0000")
check("/accent hex", T.Settings.get("Accent")[1] == 255 and T.Settings.get("Accent")[2] == 0)
run("/accent reset")
check("/accent reset", T.Settings.get("Accent")[1] == 240)
run("/settings ConsoleTimestamps on")
check("/settings sets a boolean", T.Settings.get("ConsoleTimestamps") == true)
H.step()
local stampShown = false
for _, entry in view.Output.Rows do
	if entry.Row.Visible and entry.Label.Text:find("12:00:", 1, true) then
		stampShown = true
	end
end
check("timestamps drawn", stampShown)
run("/settings ConsoleTimestamps off")
at = run("/settings")
check("/settings lists", has(at, "ConsoleGameOutput") and has(at, "Scale"), since(at))
at = run("/fps")
H.advance(1)
check("/fps measures", has(at, "fps"), since(at))
at = run("/ping")
check("/ping fails gracefully here", has(at, "[x]"), since(at))
at = run("/players")
check("/players fails gracefully here", has(at, "[x]"), since(at))
at = run("/mem")
check("/mem", has(at, "luau"), since(at))
at = run("/place")
check("/place", has(at, "123"), since(at))
at = run("/logs")
check("/logs shows entries", has(at, "] [DEBUG] [console]") or has(at, "] [INFO "), since(at))
at = run("/history")
check("/history lists", has(at, "/logs") and has(at, "last 30 of"), since(at))
run("/tab documentation")
H.advance(0.5)
check("/tab switches", T.Tabs.Selected == "documentation")
run("/tab console")
H.advance(0.3)

-- Plugin-owned command routing.
local Commands = C.Commands
Commands.register({
	Name = "greet",
	Owner = "testplug",
	Description = "test plugin command",
	Usage = ":testplug.greet",
	Run = function(ctx)
		ctx.Console.plugin("testplug", "hello from plugin")
		return 42
	end,
})
at = run(":testplug.greet")
check(":plugin.cmd runs", has(at, "[plugin] testplug: hello from plugin"), since(at))
check("plugin result to $last", Variables.get("last") == 42)
at = run("/greet")
check("/cmd reaches a unique plugin command", has(at, "hello from plugin"))
local comp = C.complete(":test", 6)
check(": completion lists plugin commands", comp.Items[1] and comp.Items[1].Label == ":testplug.greet")
at = run(":testplug.nothing")
check("unknown plugin command", has(at, "[x] unknown command"), since(at))

----------------------------------------------------------------------
-- 11. Output: selection, copy, menu, long sessions
----------------------------------------------------------------------
local out = view.Output
run("/clear")
H.step()
check("/clear empties", #C.Lines == 0)
for index = 1, 5 do
	C.info("row " .. index)
end
H.step()
H.step()
local function rowFor(text)
	for _, entry in out.Rows do
		if entry.Line and entry.Line.Plain:find(text, 1, true) and entry.Row.Visible then
			return entry.Row
		end
	end
	return nil
end
local r2 = rowFor("row 2")
check("row drawn", r2 ~= nil)
H.clickObject(r2)
H.keys.LeftControl = true
H.clickObject(rowFor("row 4"))
H.keys.LeftControl = nil
check("Ctrl+click adds", #out:GetSelected() == 2)
H.keys.LeftShift = true
H.clickObject(rowFor("row 5"))
H.keys.LeftShift = nil
check("Shift+click range", #out:GetSelected() == 2 or #out:GetSelected() == 4, #out:GetSelected())
H.clickObject(rowFor("row 1"))
H.keys.LeftShift = true
H.clickObject(rowFor("row 3"))
H.keys.LeftShift = nil
check("Shift range from anchor", #out:GetSelected() == 3, #out:GetSelected())
out:CopySelected(true)
check("copy selected lines", H.CLIPBOARD == "[*] row 1\n[*] row 2\n[*] row 3", H.CLIPBOARD)
out:CopySelected(false)
check("copy without prefixes", H.CLIPBOARD == "row 1\nrow 2\nrow 3", H.CLIPBOARD)
H.clickObject(rowFor("row 2"), "MouseButton2")
local menu = T.Overlay.top()
check("right-click opens the output menu", menu ~= nil and menu.Frame:IsDescendantOf(T.Overlay.layer()))
local menuText = {}
if menu then
	for _, d in menu.Frame:GetDescendants() do
		if d.ClassName == "TextLabel" then
			table.insert(menuText, d.Text)
		end
	end
end
local joined = table.concat(menuText, "|")
check("menu has copy, game output, clear", joined:find("Copy", 1, true) and joined:find("Show game output", 1, true) and joined:find("Clear console", 1, true), joined)
T.Overlay.closeAll()
-- double-click an echo line recalls it
run("/echo recall me")
H.step()
H.step()
local echoRow = rowFor("[>] /echo recall me")
H.clickObject(echoRow)
H.clickObject(echoRow)
check("double-click [>] recalls into input", box.Text == "/echo recall me", box.Text)
view:SetText("")

for index = 1, 6000 do
	C.info("bulk " .. index)
end
H.step()
H.step()
check("line cap keeps the newest", #C.Lines <= C.MaxLines and C.Lines[#C.Lines].Plain == "[*] bulk 6000", #C.Lines)
local visible = 0
for _, entry in out.Rows do
	if entry.Row.Visible then
		visible += 1
	end
end
check("virtual output: few rows exist", #out.Rows < 60 and visible > 5, #out.Rows .. " rows")
check("follows the newest line", out.Stick == true)
check("no runtime errors", #H.ERRORS == 0, H.ERRORS[1])

----------------------------------------------------------------------
-- 12. Documentation tab
----------------------------------------------------------------------
T.Tabs:Select("documentation")
H.advance(0.5)
local Docs = imp("documentation/docs")
local topics = Docs.topics()
check("9 topics", #topics == 9, #topics)
check("topic order", topics[1].Id == "console" and topics[2].Id == "prefixes" and topics[3].Id == "commands" and topics[4].Id == "variables" and topics[5].Id == "errors" and topics[6].Id == "explorer" and topics[7].Id == "menus" and topics[8].Id == "ui", topics[1] and topics[1].Id)
local dview = Docs.View
check("docs view built", dview ~= nil and dview.Current and dview.Current.Id == "console")
check("no placeholder in docs", H.find(T.Tabs.Pages.documentation, "Placeholder") == nil)
run("/docs prefixes")
H.step()
check("/docs opens a topic", dview.Current.Id == "prefixes", dview.Current and dview.Current.Id)
local content = dview.Scroll.Content
local tables, codes = 0, 0
for _, d in content:GetChildren() do
	if d.Name == "Table" then
		tables += 1
	elseif d.Name == "Code" then
		codes += 1
	end
end
check("prefix topic renders tables", tables >= 3, tables)
check("prefix topic renders code", codes >= 1, codes)
-- Every input prefix and output prefix is documented.
local prefixText = Docs.get("prefixes").Text
for _, entry in C.InputPrefixes do
	check("documented input prefix " .. entry.Prefix, prefixText:find(entry.Prefix, 1, true) ~= nil)
end
for _, kind in C.OutputOrder do
	check("documented output prefix " .. C.Kinds[kind].Tag, prefixText:find(C.Kinds[kind].Tag, 1, true) ~= nil)
end
-- Every built-in command is documented.
local commandText = Docs.get("commands").Text:gsub("``", "`")
commandText = Docs.get("commands").Source .. "\n" .. table.concat((function()
	local out = {}
	for _, block in Docs.get("commands").Blocks do
		if block.Rows then
			for _, row in block.Rows do
				table.insert(out, row[1])
			end
		end
	end
	return out
end)(), "\n")
for _, command in Commands.list() do
	if command.Owner == "core" then
		check("documented /" .. command.Name, commandText:find("`/" .. command.Name, 1, true) ~= nil)
	end
end
-- Search filters the list.
dview.Search.Box.Text = "alias"
H.step()
check("search filters topics", #dview.List:GetItems() >= 1 and #dview.List:GetItems() < 8, #dview.List:GetItems())
dview.Search.Box.Text = ""
H.step()
check("clearing search shows all", #dview.List:GetItems() == 9)
-- Code block menu runs examples.
Docs.open("commands")
H.step()
local codeBlock
for _, d in dview.Scroll.Content:GetChildren() do
	if d.Name == "Code" and not codeBlock then
		codeBlock = d
	end
end
check("commands topic has examples", codeBlock ~= nil)
check("plugin command appears in the docs", H.find(dview.Scroll.Content, "Table") ~= nil and (function()
	for _, d in dview.Scroll.Content:GetDescendants() do
		if d.ClassName == "TextLabel" and d.Text:find("testplug.greet", 1, true) then
			return true
		end
	end
	return false
end)())
check("rich text is escaped", dview.rich("`<b>`"):find("&lt;b&gt;", 1, true) ~= nil and not dview.rich("`<b>`"):find("<b>", 1, true))
dview:_codeMenu("/set fromdocs = 7", V2(300, 300))
H.step()
local codeMenu = T.Overlay.top()
local runItem
for _, d in codeMenu.Frame:GetDescendants() do
	if d.ClassName == "TextLabel" and d.Text == "Run in the console" then
		runItem = d.Parent
	end
end
check("code menu offers Run", runItem ~= nil)
if runItem then
	H.clickObject(runItem)
	H.advance(0.5)
end
check("Run in the console works", Variables.get("fromdocs") == 7 and T.Tabs.Selected == "console")
T.Tabs:Select("console")
H.advance(0.3)

----------------------------------------------------------------------
-- 13. Parser details
----------------------------------------------------------------------
local Parser = C.Parser
check("$ in strings untouched", Parser.code('"$a" .. $a') == '"$a" .. __tungsten_vars.a', Parser.code('"$a" .. $a'))
check("$ in comments untouched", Parser.code("$a -- $b") == "__tungsten_vars.a -- $b")
check("split keeps quotes", table.concat(Parser.split('a "b c" d'), "|") == "a|b c|d")
check("chain splits", #Parser.chain("/a && /b && > x && y") == 4)
check("chain ignores brackets", #Parser.chain("> f(a && b)") == 1)

----------------------------------------------------------------------
-- 15. Types outside the console: parsing, text, conversion
----------------------------------------------------------------------
local E = H.env
local typeof = H.env.typeof -- the mock's datatypes
local okV, vec = Types.parse("1, 2, 3", "Vector3")
check("parse Vector3", okV and vec.X == 1 and vec.Y == 2 and vec.Z == 3)
local okV2, vec2 = Types.parse("Vector3.new(4, 5, 6)", "Vector3")
check("parse Vector3.new(...)", okV2 and vec2.Z == 6)
local badV, reasonV = Types.parse("1, 2", "Vector3")
check("bad Vector3 says why", badV == false and tostring(reasonV):find("x, y, z", 1, true) ~= nil, reasonV)
local okC, col = Types.parse("#ff8800", "Color3")
check("parse #hex Color3", okC and col.R == 1 and math.abs(col.G - 136 / 255) < 1e-6)
local okC2, col2 = Types.parse("255, 136, 0", "Color3")
check("parse rgb Color3", okC2 and col2 == col)
check("Color3 out of range fails", Types.parse("300, 0, 0", "Color3") == false)
check("parse number", select(2, Types.parse(" 42 ", "number")) == 42)
check("bad number fails", Types.parse("abc", "number") == false)
check("parse boolean words", select(2, Types.parse("yes", "boolean")) == true and select(2, Types.parse("off", "boolean")) == false)
local okI, inst = Types.parse("workspace.Baseplate", "Instance")
check("parse Instance path", okI and inst == baseplate, tostring(inst))
local okI2, inst2 = Types.parse('workspace["Baseplate"]', "Instance")
check("parse Instance [\"name\"]", okI2 and inst2 == baseplate)
local badI, reasonI = Types.parse("workspace.Nothing", "Instance")
check("missing child says why", badI == false and tostring(reasonI):find("Nothing", 1, true) ~= nil, reasonI)
check("paths never run code", Types.parse("workspace:Destroy()", "Instance") == false)
local okE, item = Types.parse("Plastic", "EnumItem", { Enum = "Material" })
check("parse EnumItem by name", okE and item == E.Enum.Material.Plastic)
local okE2, item2 = Types.parse("Material.Wood", "EnumItem")
check("parse Enum.Name.Item form", okE2 and item2 == E.Enum.Material.Wood)
run("/set a = 5")
check("parse $variable", select(2, Types.parse("$a", "number")) == 5)
check("$variable of the wrong type fails", Types.parse("$a", "string") == false)
local okT, tbl = Types.parse("{1, 2, x = Vector3.new(1, 1, 1)}", "table")
check("parse table literal", okT and tbl[2] == 2 and tbl.x.X == 1)
check("table literal can't reach game", Types.parse("{game}", "table") == true and #select(2, Types.parse("{game}", "table")) == 0)
check("guess number", select(2, Types.parse("4")) == 4)
check("guess quoted text", select(2, Types.parse('"hi"')) == "hi")
check("guess Vector3", typeof(select(2, Types.parse("1, 2, 3"))) == "Vector3")
check("guess hex Color3", typeof(select(2, Types.parse("#ffffff"))) == "Color3")
check("guess plain text", select(2, Types.parse("hello there")) == "hello there")
check("editText Vector3", Types.editText(E.Vector3.new(1, 2.5, 3)) == "1, 2.5, 3", Types.editText(E.Vector3.new(1, 2.5, 3)))
check("editText Color3", Types.editText(col) == "255, 136, 0", Types.editText(col))
check("editText Enum", Types.editText(E.Enum.Material.Wood) == "Wood")
check("editText round-trips", select(2, Types.parse(Types.editText(vec), "Vector3")) == vec)
check("convert text to number", select(2, Types.convert("7", "number")) == 7)
check("convert number to text", select(2, Types.convert(7, "string")) == "7")
check("convert Vector3 to text", select(2, Types.convert(vec, "string")) == "1, 2, 3")
check("default Vector3", typeof(Types.default("Vector3")) == "Vector3")
check("signature", Types.signature(function(x, y, ...) end) == "function(a1, a2, ...)", Types.signature(function(x, y, ...) end))
check("signature of a C function", Types.signature(print):find("%(%.%.%.%)") ~= nil, Types.signature(print))
check("isA class", Types.isA(baseplate, "BasePart") and not Types.isA(baseplate, "GuiObject"))
check("isA type", Types.isA(5, "number") and Types.isA(baseplate, "Instance") and not Types.isA("5", "number"))
check("classInfo", Types.classInfo("Part").Category == "part" and Types.classInfo("Part").Creatable == true)
local opt = Types.option(baseplate)
check("option for a value", opt.Icon == "class_part" and opt.Hint == "Part <BasePart>" and opt.Text == "Baseplate")
local TypePicker = imp("base/ui/components/typepicker")
check("iconFor value: Vector3", (TypePicker.iconFor("value", vec)) == "type_vector")
check("iconFor value: Instance", (TypePicker.iconFor("value", baseplate)) == "class_part")
check("isPickerKind", TypePicker.isPickerKind("class") and TypePicker.isPickerKind("enum:Material") and not TypePicker.isPickerKind("value"))

----------------------------------------------------------------------
-- 16. Lists: value columns and editing entries
----------------------------------------------------------------------
local ListC = imp("base/ui/components/list")
local Overlay = T.Overlay
local rows = {
	{ Name = "num", Class = "Part", Kind = "number", Value = 5 },
	{ Name = "vec", Class = "Model", Kind = "Vector3", Value = E.Vector3.new(1, 2, 3) },
	{ Name = "flag", Class = "Folder", Kind = "boolean", Value = true },
	{ Name = "mat", Class = "Part", Kind = "EnumItem", Value = E.Enum.Material.Plastic },
	{ Name = "obj", Class = "Part", Kind = "Instance", Value = baseplate },
}
local edits = {}
local tlist = ListC.new({
	Parent = T.Window.Content,
	Position = UDim2 and nil,
	Size = E.UDim2.fromOffset(560, 200),
	Columns = {
		{ Key = "Name", Title = "Name", Width = 120, Editable = true },
		{ Key = "Class", Title = "Class", Width = 140, Type = "class", Editable = true },
		{ Key = "Kind", Title = "Type", Width = 120, Type = "valueType", Editable = true },
		{ Key = "Value", Title = "Value", Width = 160, Type = "value", Editable = true },
	},
	OnEdit = function(row, key, value, old)
		if key == "Name" and value == "bad" then
			return false, "that name is not allowed"
		end
		table.insert(edits, { row, key, value, old })
		return true
	end,
	Items = rows,
})
tlist.Instance.ZIndex = 60
H.advance(0.2)
local function cell(rowIndex, columnIndex)
	for _, entry in tlist.Rows do
		if entry.Index == rowIndex then
			return entry.Cells[columnIndex]
		end
	end
end
check("value column shows Vector3 text", cell(2, 4).Label.Text == "1, 2, 3", cell(2, 4).Label.Text)
check("value column shows the vector icon", cell(2, 4).Icon.Visible and cell(2, 4).Icon.Image:find("type_vector", 1, true) ~= nil)
check("value column shows Instance by name with class icon", cell(5, 4).Label.Text == "Baseplate" and cell(5, 4).Icon.Image:find("class_part", 1, true) ~= nil)
check("value column shows enum item name", cell(4, 4).Label.Text == "Plastic")

local function editorBox()
	local top = Overlay.top()
	return top and top.Box, top
end
local function commit(text)
	local box = editorBox()
	box.Text = text
	H.step()
	H.focused = nil
	box.FocusLost:Fire(true)
	H.step()
	H.step()
end

tlist:BeginEdit(rows[1], "Value")
H.step()
local box1, top1 = editorBox()
check("number cell opens a text editor on the overlay", box1 ~= nil and top1.Frame:IsDescendantOf(Overlay.layer()))
check("editor starts with the value's text", box1 and box1.Text == "5", box1 and box1.Text)
local cellPos = cell(1, 4).Label.AbsolutePosition
check("editor sits over the cell", top1 and math.abs(top1.Frame.AbsolutePosition.Y - (cellPos.Y - 0)) <= 1 and top1.Frame.AbsolutePosition.X <= cellPos.X, top1 and tostring(top1.Frame.AbsolutePosition) .. " vs " .. tostring(cellPos))
commit("12")
check("number edit saved as a number", rows[1].Value == 12 and type(rows[1].Value) == "number")
check("OnEdit saw the change", edits[#edits] and edits[#edits][2] == "Value" and edits[#edits][4] == 5)
tlist:BeginEdit(rows[1], "Value")
H.step()
commit("abc")
local _, stillOpen = editorBox()
check("bad text keeps the editor open", stillOpen and not stillOpen.Closed and stillOpen.Box ~= nil)
check("and says why", stillOpen and stillOpen.Frame.Hint.Text:find("number", 1, true) ~= nil, stillOpen and stillOpen.Frame.Hint.Text)
check("value unchanged", rows[1].Value == 12)
Overlay.closeAll()

tlist:BeginEdit(rows[2], "Value")
H.step()
commit("4, 5, 6")
check("Vector3 cell parses as Vector3", typeof(rows[2].Value) == "Vector3" and rows[2].Value.X == 4)
tlist:BeginEdit(rows[5], "Value")
H.step()
commit("workspace")
check("Instance cell takes a path", rows[5].Value == workspaceObj)

local function pickOption(text)
	local top = Overlay.top()
	if not top then
		return false
	end
	for _, d in top.Frame:GetDescendants() do
		if d.ClassName == "TextLabel" and d.Name == "Text" and d.Text == text and d.Parent.Visible ~= false then
			H.clickObject(d.Parent)
			H.step()
			return true
		end
	end
	return false
end
tlist:BeginEdit(rows[3], "Value")
H.step()
check("boolean cell offers a choice", Overlay.top() ~= nil and Overlay.top().Box == nil)
check("pick false", pickOption("false") and rows[3].Value == false)
tlist:BeginEdit(rows[4], "Value")
H.step()
check("enum cell offers its items", pickOption("Wood") and rows[4].Value == E.Enum.Material.Wood)

tlist:BeginEdit(rows[1], "Class")
H.step()
local classPopup = Overlay.top()
local search = classPopup and H.find(classPopup.Frame, "Box")
check("class cell opens a searchable class picker", search ~= nil and search.ClassName == "TextBox")
if search then
	search.Text = "WedgePart"
	H.step()
	H.focused = nil
	search.FocusLost:Fire(true)
	H.step()
end
check("picked class saved", rows[1].Class == "WedgePart", rows[1].Class)

tlist:SetSelected({ rows[1], rows[2] })
tlist:BeginEdit(rows[1], "Kind")
H.step()
local editedCount = 0
local conn = tlist.Edited:Connect(function(items)
	editedCount = #items
end)
check("type picker lists types", pickOption("string"))
check("multi-selection edits every selected row", rows[1].Kind == "string" and rows[2].Kind == "string" and rows[3].Kind == "boolean")
check("Edited fires with all rows", editedCount == 2, editedCount)
conn:Disconnect()
tlist:ClearSelection()

tlist:BeginEdit(rows[1], "Name")
H.step()
commit("bad")
local _, rejected = editorBox()
check("OnEdit can reject with a reason", rejected and not rejected.Closed and rejected.Frame.Hint.Text:find("not allowed", 1, true) ~= nil)
check("rejected value not written", rows[1].Name == "num")
Overlay.closeAll()

-- double-click an editable cell; F2; menu entries
local valueCell = cell(1, 4).Label
local spot = H.toScreen(valueCell.AbsolutePosition + E.Vector2.new(10, 8))
H.click(spot)
H.advance(0.05)
H.click(spot)
check("double-click an editable cell edits it", editorBox() ~= nil)
Overlay.closeAll()
H.advance(0.5)
H.click(H.toScreen(cell(2, 1).Label.AbsolutePosition + E.Vector2.new(5, 8)))
H.advance(0.5)
H.focused = nil -- clicking the list takes focus away from the console input in Roblox
H.key("F2")
local f2box, f2top = editorBox()
check("F2 edits the first editable column of the clicked row", f2box ~= nil and f2box.Text == "vec", f2box and f2box.Text)
Overlay.closeAll()
local menuEntries = tlist:EditMenuItems(rows[1])
check("EditMenuItems gives one entry per editable column", #menuEntries == 4 and menuEntries[1].Text == "Edit name" and menuEntries[1].Shortcut == "F2")
tlist.Instance:Destroy()
H.step()

----------------------------------------------------------------------
-- 17. Console, variables and functions together
----------------------------------------------------------------------
at = run("> double = function(n) return n * 2 end")
check("functions become variables", type(Variables.get("double")) == "function")
at = run("/vars double")
check("/vars shows a function's shape", has(at, "function") and has(at, "(a1)") and has(at, "<function>"), since(at))
at = run("/call double 21")
check("/call calls a function variable", has(at, "42 <number>") and Variables.get("last") == 42, since(at))
at = run("/call a")
check("/call on a non-function fails", has(at, "not a function"), since(at))
at = run("> getA = function() return a end")
run("/set a = 9")
at = run("/call getA")
check("a console function sees variables later", has(at, "9 <number>"), since(at))
check("and when called from outside the console", Variables.get("getA")() == 9)
at = run("/type $double")
check("/type shows function details", has(at, "shape") and has(at, "Luau"), since(at))
at = run("> game = 5")
check("hiding a global warns", has(at, "[!] $game now hides the global game"), since(at))
run("/unset game")
at = run("> game ~= nil")
check("/unset brings the global back", has(at, "true <boolean>"), since(at))
at = run("> print = 1")
check("console names can't be replaced", has(at, "[x]") and has(at, "belongs to the console"), since(at))
at = run("> local q = 1")
check("local gets a hint", has(at, "[?] local q ends with this input"), since(at))
check("local didn't make a variable", not Variables.has("q"))
at = run("> tungsten.Types.tag(5)")
check("tungsten reaches Tungsten's modules", has(at, '"<number>"'), since(at))
at = run("/echo twice is ${$a * 2}")
check("${code} in text", has(at, "[*] twice is 18"), since(at))
run("/set cfg = {s = 1.1}")
at = run("/scale $cfg.s")
H.advance(0.3)
check("$var.field as a command argument", T.Scale.effective() == 1.1, since(at))
run("/scale 1.2")
H.advance(0.3)
at = run("/setas v3 Vector3 1, 2, 3")
check("/setas Vector3", typeof(Variables.get("v3")) == "Vector3" and has(at, "v3 = 1, 2, 3 <Vector3>"), since(at))
run("/setas m Material Wood")
check("/setas enum by enum name", Variables.get("m") == E.Enum.Material.Wood)
run("/setas c Color3 #ff0000")
check("/setas Color3", typeof(Variables.get("c")) == "Color3")
run("/setas bp Instance workspace.Baseplate")
check("/setas Instance", Variables.get("bp") == baseplate)
at = run("/setas bad Vector3 1, 2")
check("/setas explains bad text", has(at, "[x] type x, y, z"), since(at))
run("/text ns 7")
run("/cast ns number")
check("/cast text to number", Variables.get("ns") == 7)
run("/cast v3 string")
check("/cast Vector3 to text", Variables.get("v3") == "1, 2, 3")
local comp2 = C.complete("/call ", 7)
local hasDouble = false
for _, it in comp2.Items do
	if it.Text == "double" then
		hasDouble = true
	end
end
check("/call completes function variables", hasDouble)
check("plugins see console variables", Variables.source("double") == "console")
Variables.set("fromPlugin", 3, { Source = "myplugin" })
at = run("> fromPlugin + 1")
check("console sees plugin variables", has(at, "4 <number>"), since(at))
at = run("/vars fromPlugin")
check("/vars shows the variable's source", has(at, "myplugin"), since(at))
check("no runtime errors after integration", #H.ERRORS == 0, H.ERRORS[1])


----------------------------------------------------------------------
-- 18. Errors: records, explanations, guards, commands
----------------------------------------------------------------------
local Errors = C.Errors
Errors.clear()
-- = never fails silently: a display problem falls back to one line.
local realPretty = Types.pretty
Types.pretty = function()
	error("display broke")
end
at = run("= {1, 2}")
Types.pretty = realPretty
check("= falls back when showing in full fails", has(at, "[=] {1, 2}") or has(at, "{1, 2} <table>"), since(at))
-- A fault anywhere while running an input is reported, not lost.
local realExecute = C.execute
C.execute = function()
	error("simulated fault")
end
at = run("= 1 + 1")
C.execute = realExecute
check("an internal fault shows an [x] line", has(at, "[x] Tungsten failed while running this") and has(at, "simulated fault"), since(at))
check("internal fault is recorded", Errors.get() and Errors.get().Kind == "internal" and Errors.get().Input == "= 1 + 1")
check("internal fault gets the log hint", has(at, "[?] this is a fault in Tungsten"), since(at))
at = run("= 1 + 1")
check("= works again afterwards", has(at, "[=] 2 <number>"), since(at))

-- Records and $err
at = run("> error('kaboom')")
local rec = Errors.get()
check("runtime error recorded", rec and rec.Kind == "runtime" and rec.Message:find("kaboom", 1, true) and rec.Input == "> error('kaboom')" and rec.Code == "error('kaboom')")
check("$err is the newest record", Variables.get("err") == rec)
local errLine
for index = at, #C.Lines do
	if C.Lines[index].Kind == "error" and not errLine then
		errLine = C.Lines[index]
	end
end
check("the [x] line carries its record", errLine and errLine.Error == rec)
check("runtime errors keep a traceback", rec and type(rec.Trace) == "table")
at = run("> $err.Message")
check("$err readable in code", has(at, "kaboom"), since(at))
check("$err can't be set", has(run("/set err = 1"), "reserved"))

-- Syntax caret
at = run("> 1 +")
rec = Errors.get()
check("syntax error kind", rec.Kind == "syntax")
check("syntax error shows the code and a caret", has(at, "    1 +\n") and has(at, "^"), since(at))
check("caret record", rec.Caret and rec.Caret[1] == "1 +" and rec.Caret[2]:find("%^") ~= nil)
check("syntax hint", has(at, "[?] the code ends too early"), since(at))
at = run("> print('abc)")
check("unclosed quote hint", has(at, "[?] a quote is not closed"), since(at))

-- Missing parts of paths
at = run("> workspace.Basepalte.Size")
check("missing child found with did-you-mean", has(at, 'has no child or property "Basepalte"') and has(at, 'did you mean "Baseplate"'), since(at))
run("/set cfg = {speed = 16}")
at = run("> $cfg.speeed * 2")
check("missing table key found", has(at, 'cfg has no "speeed"') and has(at, '"speed"'), since(at))
at = run("> nosuchroot.child.x")
check("missing root named", has(at, "nosuchroot is nil"), since(at))
at = run("> local p = workspace.Nope p.x = 1")
check("locals in the code aren't blamed", not has(at, "p is nil"), since(at))
at = run("> $speeed")
check("unknown variable did-you-mean", has(at, "unknown variable $speeed") or has(at, "[x]"), since(at))
at = run("> 'a' .. nil")
check("concatenate hint", has(at, "can't be joined"), since(at))
at = run("> 1 + {}")
check("arithmetic hint", has(at, "not a number"), since(at))

-- Command, unknown and usage errors
at = run("/frobnicate")
check("unknown command recorded", Errors.get().Kind == "unknown")
at = run("/scale abc")
rec = Errors.get()
check("usage error recorded with its command", rec.Kind == "command" and rec.Command == "/scale" and has(at, "[?] /help scale explains it"), since(at))
at = run("/set q = nosuch.thing")
rec = Errors.get()
check("bad code inside a command keeps code + hints", rec.Code == "nosuch.thing" and has(at, "nosuch is nil"), since(at))
Commands.register({ Name = "crashy", Owner = "testplug", Run = function() local t = nil; return t.x end })
at = run(":testplug.crashy")
rec = Errors.get()
check("a plugin's crashing command is reported under the plugin's name", has(at, "[x] testplug: :testplug.crashy failed: ") and has(at, "attempt to index nil") and rec.Source == "testplug" and rec.Trace ~= nil, since(at))
at = run("x = 1")
check("bare Luau gets no \"looks like Luau\" line", not has(at, "looks like Luau") and has(at, "commands start with /"), since(at))
run("/set double2 = function(n) return n end")
at = run("/double2")
check("command named like a variable hints /call", has(at, "/call double2"), since(at))

-- || and /try
at = run("/nope || /echo fallback ran")
check("|| runs after a failure", has(at, "[*] fallback ran"), since(at))
at = run("/echo fine || /echo not this")
check("|| skipped after success", has(at, "[*] fine") and not has(at, "[*] not this"), since(at))
at = run("/nope && /echo no || /echo rescue")
check("&& then || mix", not has(at, "[*] no") and has(at, "[*] rescue"), since(at))
at = run("/try /nope && /echo carried on")
check("/try lets a chain carry on", has(at, "[!] failed · carrying on") and has(at, "[*] carried on"), since(at))
check("chain parts keep their operators", Parser.chain("a && b || c")[2].Op == "&&" and Parser.chain("a && b || c")[3].Op == "||")

-- /errors, /trace, /retry, /traceback
at = run("/errors")
check("/errors lists records", has(at, "errors · /trace") and has(at, "runtime") and has(at, "syntax"), since(at))
at = run("/errors syntax")
check("/errors filters by kind", has(at, "syntax") and not has(at, "kaboom"), since(at))
local someId = Errors.list()[1].Id
at = run("/trace " .. someId)
check("/trace shows a record", has(at, "error #" .. someId) and has(at, "message"), since(at))
at = run("/trace 9999")
check("/trace unknown number", has(at, "no error #9999"), since(at))
run("/set fixme = 1")
run("> fixme + nothere")
local failing = Errors.get()
run("/set nothere = 2")
at = run("/retry")
check("/retry reruns the newest error's input", has(at, "[+] 3 <number>"), since(at))
run("/unset nothere")
local before = #Errors.list()
at = run("/retry " .. failing.Id)
check("/retry of a still-failing input reports once", #Errors.list() == before + 1, #Errors.list() - before)
run("/traceback on")
check("/traceback saves the setting", T.Settings.get("ConsoleTraceback") == true)
at = run("> (function() error('deep') end)()")
check("traceback printed under the error when on", has(at, "console:1"), since(at))
run("/traceback off")

-- Output: tint, menu, double-click, copy without prefixes
H.step()
H.step()
local errRow
for _, entry in view.Output.Rows do
	if entry.Row.Visible and entry.Line and entry.Line.Kind == "error" and entry.Line.Error then
		errRow = entry
	end
end
check("error rows are tinted", errRow and errRow.Tint == "Danger" and errRow.Row.BackgroundTransparency < 1)
if errRow then
	H.clickObjectLeft(errRow.Row, "MouseButton2")
	local menu2 = T.Overlay.top()
	local labels2 = {}
	for _, d in menu2.Frame:GetDescendants() do
		if d.ClassName == "TextLabel" then
			table.insert(labels2, d.Text)
		end
	end
	local joined2 = table.concat(labels2, "|")
	check("error menu offers explain / copy / run again", joined2:find("Explain this error", 1, true) and joined2:find("Copy error with details", 1, true) and joined2:find("Run it again", 1, true), joined2)
	T.Overlay.closeAll()
	local mark2 = mark()
	local clickedId = errRow.Line.Error.Id -- rows are reused once new lines arrive
	H.clickObjectLeft(errRow.Row)
	H.clickObjectLeft(errRow.Row)
	H.step()
	check("double-click an error explains it", has(mark2, "error #" .. clickedId), since(mark2))
end
local hintLine
for index = #C.Lines, 1, -1 do
	if C.Lines[index].Kind == "hint" then
		hintLine = C.Lines[index]
		break
	end
end
view.Output:_selectOnly(hintLine)
view.Output:CopySelected(false)
check("copy without prefixes strips [?] too", H.CLIPBOARD and H.CLIPBOARD:sub(1, 3) ~= "[?]", H.CLIPBOARD)
check("Errors.describe gives copyable text", table.concat(Errors.describe(Errors.get()), "\n"):find("message", 1, true) ~= nil)
-- game errors are recorded while mirroring
run("/game on")
LogService.MessageOut:Fire("Script error in game", H.env.Enum.MessageType.MessageError)
H.step()
check("game errors land in /errors", Errors.get().Kind == "game" and Errors.get().Message == "Script error in game")
run("/game off")
run("/errors clear")
check("/errors clear", #Errors.list() == 0 and not Variables.has("err"))
check("no runtime errors after error tests", #H.ERRORS == 0, H.ERRORS[1])

----------------------------------------------------------------------
-- 14. Re-run: variables gone, settings kept, no extra listeners
----------------------------------------------------------------------
run("/game on")
local counts = { H.UIS.InputBegan:Count(), H.UIS.InputChanged:Count(), H.UIS.InputEnded:Count() }
H.run("Tungsten/Tungsten.luau")
H.advance(1)
local T2 = H.genv.Tungsten.Context
check("re-run ok", T2 ~= T)
check("variables are gone after a new session", T2.Variables.count() == 0, T2.Variables.count())
check("settings kept (scale)", T2.Settings.get("Scale") == 1.2 and T2.Scale.effective() == 1.2, T2.Settings.get("Scale"))
check("settings kept (game output)", T2.Settings.get("ConsoleGameOutput") == true)
check("one MessageOut connection after re-run", LogService.MessageOut:Count() == 1, LogService.MessageOut:Count())
H.run("Tungsten/Tungsten.luau")
H.advance(1)
local counts2 = { H.UIS.InputBegan:Count(), H.UIS.InputChanged:Count(), H.UIS.InputEnded:Count() }
H.run("Tungsten/Tungsten.luau")
H.advance(1)
local counts3 = { H.UIS.InputBegan:Count(), H.UIS.InputChanged:Count(), H.UIS.InputEnded:Count() }
check("re-running adds no listeners", table.concat(counts2, ",") == table.concat(counts3, ","), table.concat(counts2, ",") .. " -> " .. table.concat(counts3, ","))
check("still one MessageOut connection", LogService.MessageOut:Count() == 1)
local T3 = H.genv.Tungsten.Context
T3.Console.run("/exit")
H.advance(1)
check("/exit shuts down", H.genv.Tungsten == nil and #H.HUI:GetChildren() == 0, #H.HUI:GetChildren())
check("/exit drops the game output listener", LogService.MessageOut:Count() == 0)

for _, e in H.ERRORS do
	print("ERR: " .. e)
end
print(("stage3: %d passed, %d failed, %d runtime errors"):format(passed, failed, #H.ERRORS))
