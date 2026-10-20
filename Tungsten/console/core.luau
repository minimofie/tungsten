--[[
	Tungsten · console/core
	The console itself, independent of the tab's UI: the line buffer,
	output prefixes, running input, history, completion data and the
	[game] output mirror. Lines written before the tab is opened are kept
	and shown when it is.

	Output (plain text; it is escaped when drawn, so "<b>" shows as typed)
		Console.info(text)      [*]
		Console.success(text)   [+]
		Console.warn(text)      [!]
		Console.error(text)     [x]
		Console.echo(text)      [>]  (input as typed)
		Console.plugin(owner, text)   [plugin] owner: text
		Console.reporter(id, opts)    a source's own printer: info, success,
		                              warn, error (an error record), detail,
		                              value, try, wrap (console/reporter)
		Console.game(text, messageType)  [game]
		Console.detail(text or segments)  indented line without a prefix
		Console.value(kind, label, value) e.g. "a = 5 <number>"

	Input
		Console.run("/set a = 5")   echo + run (what pressing Enter does)
		Console.eval("1 + 1")       -> true, { n = 1, 2 }  or false, message
]]

local T = ...
local signal = T.import("base/signal")
local Services = T.import("base/services")
local Settings = T.import("base/settings")
local Types = T.import("base/types")
local Variables = T.import("base/variables")
local Parser = T.import("console/parser")
local Commands = T.import("console/commands")
local Errors = T.import("console/errors")

-- This module's own environment: the executor's globals (game, workspace,
-- every Volt function). Console code falls back to it.
local BASE_ENV = if getfenv then getfenv() else nil

local Console = {}
Console.MaxLines = 5000
Console.TrimChunk = 500
Console.MaxLineLength = 2000
Console.MaxHistory = 200
Console.Lines = {} :: { any }
Console.History = {} :: { string }
Console.LineAdded = signal.new() -- (line)
Console.LinesTrimmed = signal.new() -- (count removed from the top)
Console.Cleared = signal.new()
Console.Commands = Commands
Console.Parser = Parser
Console.Errors = Errors

-- Prefix, prefix color and text color for each kind of line.
Console.Kinds = {
	info = { Tag = "[*]", TagColor = "Info", TextColor = "Text" },
	success = { Tag = "[+]", TagColor = "Success", TextColor = "Text" },
	warn = { Tag = "[!]", TagColor = "Warning", TextColor = "Text" },
	error = { Tag = "[x]", TagColor = "Danger", TextColor = "Text" },
	echo = { Tag = "[>]", TagColor = "TextMuted", TextColor = "TextDim" },
	result = { Tag = "[=]", TagColor = "Success", TextColor = "Text" },
	hint = { Tag = "[?]", TagColor = "Accent", TextColor = "Text" },
	note = { Tag = "[#]", TagColor = "Warning", TextColor = "TextDim" },
	var = { Tag = "[$]", TagColor = "SyntaxSelf", TextColor = "Text" },
	time = { Tag = "[~]", TagColor = "SyntaxBuiltin", TextColor = "Text" },
	plugin = { Tag = "[plugin]", TagColor = "Accent", TextColor = "Text" },
	game = { Tag = "[game]", TagColor = "TextMuted", TextColor = "TextDim" },
	detail = { Tag = nil, TagColor = "TextMuted", TextColor = "Text" },
}

-- Input prefixes, for /help and the documentation.
Console.InputPrefixes = {
	{ Prefix = "/", Example = "/help", Meaning = "run a command" },
	{ Prefix = ":", Example = ":plugin.command", Meaning = "run a plugin's command" },
	{ Prefix = ">", Example = "> 1 + 1", Meaning = "run Luau and show the result" },
	{ Prefix = "=", Example = "= workspace", Meaning = "run Luau and show the result in full (tables expanded)" },
	{ Prefix = "$", Example = "$a * 2", Meaning = "Luau that starts with a variable" },
	{ Prefix = "?", Example = "?set", Meaning = "help for a command (? alone lists them)" },
	{ Prefix = "!", Example = "!!  !3  !/set", Meaning = "run again from history: last, number, or last starting with" },
	{ Prefix = "#", Example = "# note", Meaning = "write a note line; nothing runs" },
	{ Prefix = "&&", Example = "/set a = 1 && /get a", Meaning = "run the next input only if this one worked" },
	{ Prefix = "||", Example = "> risky() || /echo it failed", Meaning = "run the next input only if this one failed" },
}

-- Output prefixes, in the order the documentation lists them.
Console.OutputOrder = { "info", "success", "warn", "error", "echo", "result", "hint", "note", "var", "time", "plugin", "game" }
Console.OutputMeaning = {
	info = "information",
	success = "a command or code worked; results",
	warn = "a warning; something was adjusted or skipped",
	error = "something failed (unknown command, Luau error); the console keeps working",
	echo = "the input you ran",
	result = "a result shown in full by =",
	hint = "help text",
	note = "a note written with #",
	var = "a watched variable changed (/watch)",
	time = "timings (/bench, /time, /fps, /ping)",
	plugin = "output from a plugin",
	game = "the game's own print, warn and errors (/game on)",
}
Console.Indent = "    " -- width of "[*] ", used for detail and continuation lines

local nextId = 0

local function clock(): string
	local ok, t = pcall(function()
		return DateTime.now():ToLocalTime()
	end)
	if ok and t then
		return ("%02d:%02d:%02d"):format(t.Hour, t.Minute, t.Second)
	end
	return "--:--:--"
end

local function clean(text: string): string
	text = tostring(text):gsub("\r\n", "\n"):gsub("\r", "\n"):gsub("\t", "    ")
	-- Other control characters would draw as boxes.
	text = text:gsub("[%z\1-\8\11-\31\127]", "")
	return text
end

----------------------------------------------------------------------
-- Writing lines
----------------------------------------------------------------------

--[[
	A line: {
		Id, Kind, Time,
		Segments = { { Text = "...", Color = "ThemeKey" | Color3 }, ... },
		Icon, IconColor, IconAt,   -- optional icon drawn over 2 spaces at character IconAt
		Plain,                     -- the text without colors (copying, searching)
		Length,                    -- characters
		Input,                     -- for echo lines: the input that was run
	}
]]
local function addLine(line)
	nextId += 1
	line.Id = nextId
	line.Time = clock()
	local parts = {}
	for _, segment in line.Segments do
		table.insert(parts, segment.Text)
	end
	line.Plain = table.concat(parts)
	local ok, length = pcall(utf8.len, line.Plain)
	line.Length = if ok and length then length else #line.Plain
	table.insert(Console.Lines, line)

	local lines = Console.Lines
	if #lines > Console.MaxLines then
		local remove = math.min(Console.TrimChunk, #lines - 1)
		table.move(lines, remove + 1, #lines, 1)
		for index = #lines - remove + 1, #lines do
			lines[index] = nil
		end
		Console.LinesTrimmed:Fire(remove)
	end
	Console.LineAdded:Fire(line)
	return line
end

local function toSegments(content, color): { any }
	if type(content) == "table" then
		return content
	end
	return { { Text = tostring(content), Color = color } }
end

-- Splits segments at newlines into one segment list per line.
local function splitLines(segments): { { any } }
	local result = { {} }
	for _, segment in segments do
		local text = clean(segment.Text)
		local first = true
		for piece in (text .. "\n"):gmatch("(.-)\n") do
			if not first then
				table.insert(result, {})
			end
			first = false
			if piece ~= "" then
				if #piece > Console.MaxLineLength then
					piece = piece:sub(1, Console.MaxLineLength) .. "…"
				end
				table.insert(result[#result], { Text = piece, Color = segment.Color })
			end
		end
	end
	return result
end

--[[
	Console.write(kind, content, opts)
	content: text, or a list of { Text, Color } segments.
	opts: Icon, IconColor, IconAt (character index inside the content where
	two spaces were left for the icon), Input (echo lines).
	Returns the first line written.
]]
function Console.write(kind: string, content, opts: { [string]: any }?)
	local style = Console.Kinds[kind] or Console.Kinds.info
	opts = opts or {}
	local rows = splitLines(toSegments(content, style.TextColor))
	local first
	for index, row in rows do
		local segments = {}
		local lead
		if style.Tag then
			lead = if index == 1 then style.Tag .. " " else string.rep(" ", #style.Tag + 1)
			table.insert(segments, { Text = lead, Color = style.TagColor })
		elseif kind == "detail" then
			lead = Console.Indent
			table.insert(segments, { Text = lead, Color = style.TagColor })
		end
		for _, segment in row do
			table.insert(segments, { Text = segment.Text, Color = segment.Color or style.TextColor })
		end
		local line = { Kind = kind, Segments = segments, Continuation = index > 1 }
		if index == 1 then
			if opts.Icon and opts.IconAt then
				line.Icon = opts.Icon
				line.IconColor = opts.IconColor
				line.IconAt = opts.IconAt + (if lead then #lead else 0)
			end
			line.Input = opts.Input
			first = addLine(line)
		else
			addLine(line)
		end
	end
	return first
end

function Console.info(text)
	return Console.write("info", text)
end
function Console.success(text)
	return Console.write("success", text)
end
function Console.warn(text)
	return Console.write("warn", text)
end
function Console.error(text)
	return Console.write("error", text)
end
function Console.echo(text)
	return Console.write("echo", text, { Input = text })
end
function Console.detail(content, opts)
	return Console.write("detail", content, opts)
end

-- Plugin output: "[plugin] Owner: text" (see Console.reporter).
function Console.plugin(owner: string, text, color: string?)
	local reporter = Console.reporter(owner)
	if color and color ~= "Text" then
		return reporter:info({ { Text = tostring(text), Color = color } })
	end
	return reporter:info(text)
end

-- A reporter for a source (plugin id, "explorer"): info / success / warn /
-- error / detail / value / try / wrap. See console/reporter.
function Console.reporter(id: string, opts: { [string]: any }?)
	return T.import("console/reporter").get(id, opts)
end

local GAME_COLORS = {
	MessageWarning = "Warning",
	MessageError = "Danger",
	MessageInfo = "Info",
}
function Console.game(text, messageType)
	local name = if typeof(messageType) == "EnumItem" then messageType.Name else tostring(messageType or "")
	return Console.write("game", { { Text = tostring(text), Color = GAME_COLORS[name] or "TextDim" } })
end

-- Segments for "label value <tag>", with room for an Instance's icon.
-- Returns segments plus icon options for Console.write.
function Console.valueSegments(label: string?, value: any): ({ any }, { [string]: any })
	local segments = {}
	local opts = {}
	local at = 0
	if label and label ~= "" then
		table.insert(segments, { Text = label, Color = "Text" })
		at += #label
	end
	if typeof(value) == "Instance" then
		local icon, color = Types.icon(value)
		opts.Icon, opts.IconColor, opts.IconAt = icon, color, at
		table.insert(segments, { Text = "  ", Color = "Text" })
	end
	table.insert(segments, { Text = Types.short(value), Color = "Text" })
	table.insert(segments, { Text = " " .. Types.tag(value), Color = "TextMuted" })
	return segments, opts
end

function Console.value(kind: string, label: string?, value: any)
	local segments, opts = Console.valueSegments(label, value)
	return Console.write(kind, segments, opts)
end

function Console.clear()
	table.clear(Console.Lines)
	Console.Cleared:Fire()
end

----------------------------------------------------------------------
-- Luau code
----------------------------------------------------------------------

-- A planned stop (ctx.fail, bad code inside a command): the message plus
-- optional error details (Kind, Code, Trace).
local function failure(message, details: { [string]: any }?)
	local object = { Message = message }
	for key, value in details or {} do
		object[key] = value
	end
	return setmetatable(object, { __tostring = function(self) return self.Message end })
end

-- Names console code gets from the console itself (not variables).
local OWN_NAMES = { print = true, warn = true, tungsten = true, var = true, [Parser.VarTable] = true }

-- Whether a name is one of the executor's globals (game, workspace, ...).
function Console.isGlobal(name: string): boolean
	if OWN_NAMES[name] then
		return true
	end
	if not BASE_ENV then
		return false
	end
	local ok, value = pcall(function()
		return BASE_ENV[name]
	end)
	return ok and value ~= nil
end

-- A [!] line when a new variable hides a global in console code.
function Console.shadowWarning(name: string)
	if Console.isGlobal(name) and not OWN_NAMES[name] then
		Console.warn(("$%s now hides the global %s in console code · /unset %s brings it back"):format(name, name, name))
	end
end

local function assignVariable(name: string, value: any)
	if OWN_NAMES[name] then
		error(("%s belongs to the console and can't be replaced"):format(name), 3)
	end
	if value == nil then
		if Variables.has(name) then
			Variables.unset(name)
			Console.success("removed $" .. name)
		end
		return
	end
	local isNew = not Variables.has(name)
	local ok, reason = Variables.set(name, value, { Source = "console" })
	if not ok then
		error(reason, 3)
	end
	Console.value("success", name .. " = ", value)
	if isNew then
		Console.shadowWarning(name)
	end
end

local function consolePrint(kind: string)
	return function(...)
		local parts = table.pack(...)
		for index = 1, parts.n do
			local item = parts[index]
			parts[index] = if type(item) == "string" then item else Types.short(item)
		end
		Console.write(kind, table.concat(parts, "  ", 1, parts.n))
	end
end

--[[
	The environment console code runs in. Lookup order for a name:
		1. the console's own: print, warn (write to the console),
		   var("name") (a variable by name; lists of objects as a group),
		   tungsten (Tungsten's modules: tungsten.Variables, .Types, .Console,
		   .Scale, .Settings, .Theme, ...)
		2. variables (plain name or $name)
		3. the executor's globals (game, workspace, Volt functions)
	Assigning a new global creates a variable; assigning nil removes it.
	Functions made here keep this environment, so a function stored in a
	variable still sees variables when it is called later (also from
	/call or a plugin).
]]
function Console.makeEnv()
	local vars = setmetatable({}, {
		__index = function(_, name)
			local value, exists = Variables.get(name)
			if not exists then
				if name == "sel" then
					error("$sel is empty · select something in the explorer first", 2)
				end
				error(("unknown variable $%s"):format(tostring(name)), 2)
			end
			return value
		end,
		__newindex = function(_, name, value)
			assignVariable(name, value)
		end,
	})
	local own = {
		[Parser.VarTable] = vars,
		print = consolePrint("info"),
		warn = consolePrint("warn"),
		tungsten = T,
		-- var("name"): a variable by name; a list of objects comes back as
		-- a group (var("list1"):Destroy() destroys them all).
		var = function(name)
			return Variables.ref(name)
		end,
	}
	return setmetatable({}, {
		__index = function(_, name)
			local mine = own[name]
			if mine ~= nil then
				return mine
			end
			local value, exists = Variables.get(name)
			if exists then
				return value
			end
			return if BASE_ENV then BASE_ENV[name] else nil
		end,
		__newindex = function(_, name, value)
			if type(name) == "string" and Types.isIdentifier(name) then
				assignVariable(name, value)
			else
				rawset(own, name, value)
			end
		end,
	})
end

local function cleanError(message: any): string
	local text = tostring(message)
	text = text:gsub('^%[string "console"%]:', "console:")
	return text
end

-- Compiles console code. Expressions are tried first so "1 + 1" returns 2.
function Console.compile(source: string): (any, string?)
	local converted = Parser.code(source)
	local chunk, expressionError = loadstring("return " .. converted, "=console")
	local err = expressionError
	if not chunk then
		local statementError
		chunk, statementError = loadstring(converted, "=console")
		-- Report the error for what the input looks like it was meant to be.
		if Parser.looksLikeStatement(source) then
			err = statementError
		end
	end
	if not chunk then
		return nil, cleanError(err)
	end
	if setfenv then
		local ok, setError = pcall(setfenv, chunk, Console.makeEnv())
		if not ok then
			T.Log.warn("console", "could not set the code environment: " .. tostring(setError))
		end
	end
	return chunk, nil
end

-- Runs code and returns true + packed results, or
-- false + message + kind ("syntax" or "runtime") + traceback.
-- Yields if the code yields.
function Console.eval(source: string): (boolean, any, string?, string?)
	local chunk, err = Console.compile(source)
	if not chunk then
		return false, err, "syntax", nil
	end
	local trace = nil
	local results = table.pack(xpcall(chunk, function(message)
		if type(message) == "table" and getmetatable(message) and message.Message then
			return message.Message
		end
		trace = debug.traceback(tostring(message), 2)
		T.Log.debug("console", "code error:\n" .. trace)
		return cleanError(message)
	end))
	if not results[1] then
		return false, results[2], "runtime", trace
	end
	local values = table.pack(table.unpack(results, 2, results.n))
	return true, values
end

-- Looks a name up the way console code does (variables, then globals).
function Console.lookup(name: string): (any, boolean)
	local value, exists = Variables.get(name)
	if exists then
		return value, true
	end
	if BASE_ENV then
		local ok, global = pcall(function()
			return BASE_ENV[name]
		end)
		if ok and global ~= nil then
			return global, true
		end
	end
	return nil, false
end

-- The input being run right now (error records keep it for /retry).
Console.CurrentInput = nil :: string?

-- An [x] line backed by an error record (see console/errors).
function Console.fail(info: { [string]: any })
	info.Input = info.Input or Console.CurrentInput
	info.Lookup = info.Lookup or Console.lookup
	return Errors.report(Console, info)
end

local function setLast(value: any)
	if value ~= nil then
		Variables.setReserved("last", value, "console")
	end
end
Console.setLast = setLast

-- Runs console code in the current thread. Returns true when it worked.
-- pretty = true shows the result in full (the = prefix).
local function runCode(source: string, pretty: boolean?): boolean
	if source == "" then
		Console.fail({
			Kind = "syntax",
			Message = if pretty then "nothing to show · type Luau after =, e.g. = workspace" else "nothing to run · type Luau after >, e.g. > 1 + 1",
			Hints = { "= shows a value in full, > runs code and shows its result" },
		})
		return false
	end
	local ok, result, kind, trace = Console.eval(source)
	if not ok then
		Console.fail({ Kind = kind or "runtime", Message = result, Code = source, Trace = trace })
		return false
	end
	if result.n == 0 then
		if pretty then
			Console.write("result", { { Text = "no value", Color = "TextMuted" } })
		end
		-- "local x = 1" ends with the input; say how to keep it.
		local localName = source:match("^%s*local%s+([%a_][%w_]*)")
		if localName and not source:find("[;\n]") and not source:match("^%s*local%s+function") then
			Console.write("hint", ("local %s ends with this input · write %s = … to keep it as a variable"):format(localName, localName))
		end
		return true
	end
	if pretty then
		for index = 1, result.n do
			-- Showing a value must never lose the result: fall back to one line.
			local shown, problem = pcall(Console.showFull, result[index])
			if not shown then
				T.Log.error("console", "showing a result in full failed: " .. tostring(problem))
				pcall(Console.value, "result", nil, result[index])
			end
		end
	elseif result.n == 1 then
		Console.value("success", nil, result[1])
	else
		local segments = {}
		for index = 1, result.n do
			if index > 1 then
				table.insert(segments, { Text = "   ·   ", Color = "TextMuted" })
			end
			table.insert(segments, { Text = Types.short(result[index], 60), Color = "Text" })
			table.insert(segments, { Text = " " .. Types.tag(result[index]), Color = "TextMuted" })
		end
		Console.write("success", segments)
	end
	setLast(result[1])
	return true
end
Console.runCode = runCode

-- Variables (reserved ones too) whose value is the object or a list
-- holding it.
function Console.variablesHolding(obj: Instance): { string }
	local names = {}
	for _, entry in Variables.list() do
		local value = entry.Value
		if value == obj or (type(value) == "table" and typeof(value) ~= "Instance" and table.find(value, obj)) then
			table.insert(names, "$" .. entry.Name)
		end
	end
	return names
end

local function infoRow(label: string, segments: { any })
	local row = { { Text = ("%-10s"):format(label), Color = "TextMuted" } }
	for _, segment in segments do
		table.insert(row, segment)
	end
	Console.detail(row)
end

--[[
	An object in full (= on an Instance, Explorer › Function › View in
	console): the object, its class and base classes, path, parent,
	children and descendants, and the variables that hold it.
]]
function Console.describeInstance(obj: Instance)
	Console.value("result", nil, obj)
	local okClass, className = pcall(function()
		return obj.ClassName
	end)
	if okClass then
		local okApi, Api = pcall(T.import, "base/explorer/api")
		local chain = if okApi then Api.superclasses(className) else {}
		infoRow("class", {
			{ Text = className, Color = "Accent" },
			{ Text = if #chain > 0 then "  ‹ " .. table.concat(chain, " ‹ ") else "", Color = "TextMuted" },
		})
	end
	infoRow("path", { { Text = Types.path(obj), Color = "TextDim" } })
	local okParent, parent = pcall(function()
		return obj.Parent
	end)
	if okParent then
		infoRow("parent", { { Text = if parent then Types.path(parent) else "nil (not in the game)", Color = "TextDim" } })
	end
	local okKids, children = pcall(function()
		return #obj:GetChildren()
	end)
	local okAll, descendants = pcall(function()
		return #obj:GetDescendants()
	end)
	if okKids then
		infoRow("children", {
			{ Text = tostring(children), Color = "Text" },
			{ Text = if okAll and descendants ~= children then ("  · %d descendants"):format(descendants) else "", Color = "TextMuted" },
		})
	end
	local held = Console.variablesHolding(obj)
	infoRow("variables", { { Text = if #held > 0 then table.concat(held, ", ") else "none", Color = if #held > 0 then "Accent" else "TextMuted" } })
	-- explorer frozen: what the tree shows for it
	local Explorer = T.Explorer
	local state = if Explorer and Explorer.frozenState then Explorer.frozenState(obj) else nil
	if state then
		local words = { { Text = Explorer.FrozenWords[state] .. " while the explorer is frozen", Color = Explorer.FrozenColors[state] } }
		if (state == "moved" or state == "inside_moved") and okParent and parent then
			table.insert(words, { Text = " · now in " .. Types.path(parent), Color = "TextMuted" })
		end
		infoRow("explorer", words)
	end
end

-- Objects in full, one after another (a list gets a count first).
function Console.inspect(value: any)
	local list = {}
	if typeof(value) == "Instance" then
		list = { value }
	elseif type(value) == "table" then
		for _, item in value do
			if typeof(item) == "Instance" then
				table.insert(list, item)
			end
		end
	end
	if #list == 0 then
		Console.showFull(value)
		return
	end
	if #list > 1 then
		Console.info(("%d objects"):format(#list))
	end
	for index, obj in list do
		if index > 25 then
			Console.detail({ { Text = ("… and %d more"):format(#list - 25), Color = "TextMuted" } })
			break
		end
		Console.describeInstance(obj)
	end
end

-- A value in full: tables expanded, Instances with their path.
function Console.showFull(value: any)
	local kind = typeof(value)
	if kind == "table" and next(value) ~= nil then
		Console.write("result", { { Text = Types.short(value, 80), Color = "Text" }, { Text = " " .. Types.tag(value), Color = "TextMuted" } })
		for _, line in Types.pretty(value, 3, 200) do
			Console.detail(line)
		end
	elseif kind == "Instance" then
		Console.describeInstance(value)
	elseif type(value) == "string" and (#value > 100 or value:find("\n")) then
		Console.write("result", { { Text = ("%d characters"):format(#value), Color = "TextDim" }, { Text = " <string>", Color = "TextMuted" } })
		Console.detail(value)
	else
		Console.value("result", nil, value)
	end
end

----------------------------------------------------------------------
-- Commands
----------------------------------------------------------------------

local function makeContext(command, rest: string)
	local words = Parser.split(rest)
	local ctx = {
		Command = command,
		Raw = rest,
		Args = words,
		Console = Console,
		Variables = Variables,
		Types = Types,
		T = T,
	}
	-- Stops the command with an error line (no traceback).
	function ctx.fail(message: string)
		error(failure(message), 0)
	end
	-- Stops the command as failed without another [x] line (the problem
	-- was already reported, e.g. by an input the command ran).
	function ctx.stop()
		error(failure("stopped", { Silent = true }), 0)
	end
	function ctx.usage()
		error(failure("usage: " .. command.Usage), 0)
	end
	-- A word as a value: "$a" gives the variable, anything else stays text.
	-- "$a.Name", "$t[1]" and "$f()" are evaluated as code.
	function ctx.resolve(word: string?): any
		if word == nil then
			return nil
		end
		local name = word:match("^%$([%a_][%w_]*)$")
		if name then
			local value, exists = Variables.get(name)
			if not exists then
				ctx.fail(("unknown variable $%s"):format(name))
			end
			return value
		end
		if word:match("^%$[%a_][%w_]*[%.%[:(]") then
			return (ctx.eval(word))
		end
		return word
	end
	-- Evaluates Luau (with $names); fails the command on errors.
	function ctx.eval(source: string): any
		local ok, result, kind, trace = Console.eval(source)
		if not ok then
			error(failure(result, { Kind = kind, Code = source, Trace = trace }), 0)
		end
		return result[1], result
	end
	-- Replaces $name in text with the variable's display text.
	-- Also replaces ${code} with the code's result: /echo ${$a * 2}.
	function ctx.interpolate(text: string): string
		text = text:gsub("%${(.-)}", function(code)
			local value = ctx.eval(code)
			return if type(value) == "string" then value else Types.short(value)
		end)
		local result, missing = Parser.interpolate(text, function(name)
			local value, exists = Variables.get(name)
			if not exists then
				return nil
			end
			return if type(value) == "string" then value else Types.short(value)
		end)
		if not result then
			ctx.fail(("unknown variable $%s"):format(tostring(missing)))
		end
		return result :: string
	end
	ctx.info, ctx.success, ctx.warn, ctx.error = Console.info, Console.success, Console.warn, Console.error
	ctx.detail, ctx.value = Console.detail, Console.value
	return ctx
end

-- Runs a command in the current thread. Returns true when it worked.
function Console.runCommand(command, rest: string): boolean
	local ctx = makeContext(command, rest or "")
	T.Log.debug("console", ("command %s %s"):format(Commands.invocation(command), rest or ""))
	local ok, result = xpcall(command.Run, function(message)
		if type(message) == "table" and getmetatable(message) and message.Message then
			return message
		end
		return { Crash = tostring(message), Trace = debug.traceback(tostring(message), 2) }
	end, ctx)
	if ok then
		setLast(result)
		return true
	end
	local invocation = Commands.invocation(command)
	if type(result) == "table" and result.Crash and command.Owner ~= "core" then
		-- A plugin's command broke: reported under the plugin's name.
		T.Log.error("console", ("%s failed:\n%s"):format(invocation, result.Trace))
		T.import("console/reporter").ownerFault(command.Owner, invocation, cleanError(result.Crash) .. "\n" .. tostring(result.Trace))
	elseif type(result) == "table" and result.Crash then
		-- The command itself broke (a bug in it, not a mistake in the input).
		T.Log.error("console", ("%s failed:\n%s"):format(invocation, result.Trace))
		Console.fail({
			Kind = "command",
			Message = ("%s failed: %s"):format(invocation, cleanError(result.Crash)),
			Command = invocation,
			Trace = result.Trace,
			Hints = {
				("the command %s hit an error inside itself · /trace shows where"):format(invocation),
				if command.Owner == "core" then "this is a fault in Tungsten · the log has the details (/logs)"
					else ("this comes from the plugin %s"):format(command.Owner),
			},
		})
	else
		if type(result) == "table" and result.Silent then
			return false
		end
		-- ctx.fail / ctx.usage, or bad code given to the command.
		local message = tostring(if type(result) == "table" then result.Message else result)
		Console.fail({
			Kind = if type(result) == "table" and result.Kind then result.Kind else "command",
			Message = message,
			Command = invocation,
			Code = if type(result) == "table" then result.Code else nil,
			Trace = if type(result) == "table" then result.Trace else nil,
		})
	end
	return false
end

local function suggest(name: string, owner: string?): string?
	local best, bestDistance = nil, math.huge
	for _, command in Commands.list() do
		if (owner == nil or command.Owner == owner) and not command.Hidden then
			local distance = Parser.distance(name:lower(), command.Name)
			if distance < bestDistance then
				best, bestDistance = command, distance
			end
		end
	end
	-- Short names allow one slip, longer ones two (a swapped pair), very long ones more.
	local allowed = if #name >= 4 then math.max(2, math.floor(#name / 4)) else 1
	if best and bestDistance <= allowed then
		return Commands.invocation(best)
	end
	return nil
end

local function unknownCommand(display: string, name: string, owner: string?)
	local hint = suggest(name, owner)
	local hints = {}
	if Variables.has(name) then
		table.insert(hints, ("$%s is a variable · = $%s shows it, /call %s calls it"):format(name, name, name))
	end
	Console.fail({
		Kind = "unknown",
		Message = ("unknown command \"%s\" · %s"):format(display, if hint then "did you mean " .. hint .. "?" else "try /help"),
		Hints = hints,
	})
end

----------------------------------------------------------------------
-- Aliases (session only): /alias hi = /echo hello
----------------------------------------------------------------------

Console.Aliases = {} :: { [string]: string }

function Console.setAlias(name: string, input: string?)
	name = name:lower()
	Console.Aliases[name] = input
end

----------------------------------------------------------------------
-- Running input
----------------------------------------------------------------------

function Console.pushHistory(text: string)
	local history = Console.History
	if history[#history] ~= text then
		table.insert(history, text)
		if #history > Console.MaxHistory then
			table.remove(history, 1)
		end
	end
end

-- "!!" last input, "!3" history entry 3, "!-2" two back, "!/se" newest
-- starting with "/se". Returns the input or nil + reason.
function Console.recall(spec: string): (string?, string?)
	local history = Console.History
	if #history == 0 then
		return nil, "the history is empty"
	end
	if spec == "!" or spec == "" then
		return history[#history], nil
	end
	local number = tonumber(spec)
	if number then
		local index = if number < 0 then #history + 1 + number else number
		local entry = history[index]
		if not entry then
			return nil, ("no history entry %s · /history lists them"):format(spec)
		end
		return entry, nil
	end
	for index = #history, 1, -1 do
		if history[index]:sub(1, #spec):lower() == spec:lower() then
			return history[index], nil
		end
	end
	return nil, ("nothing in the history starts with \"%s\""):format(spec)
end

local MAX_ALIAS_DEPTH = 8

-- Runs one input (no echo, no history) in the current thread.
-- Returns true when it worked. Used by Console.run, /repeat and aliases.
function Console.execute(text: string, depth: number?): boolean
	depth = depth or 0
	if (depth :: number) > MAX_ALIAS_DEPTH then
		Console.error("aliases call each other too deeply")
		return false
	end
	text = Parser.trim(text)
	if text == "" then
		return true
	end
	local kind, body = Parser.classify(text)
	if kind == "command" or kind == "bare" then
		local name, rest = Parser.rest(body)
		if name == "" then
			Console.fail({ Kind = "unknown", Message = "type a command after / · try /help", Hints = { "/help lists every command" } })
			return false
		end
		local alias = Console.Aliases[name:lower()]
		if alias then
			return Console.execute(alias .. (if rest ~= "" then " " .. rest else ""), (depth :: number) + 1)
		end
		local command, problem = Commands.resolve(name)
		if command then
			return Console.runCommand(command, rest)
		elseif kind == "bare" then
			local hints = { "/help prefixes explains every prefix" }
			Console.fail({ Kind = "unknown", Message = "commands start with / · Luau with > or = · variables with $ · ? for help", Hints = hints })
		elseif problem == "ambiguous" then
			Console.fail({ Kind = "unknown", Message = ("several plugins have \"%s\" · use :plugin.%s"):format(name, name) })
		else
			unknownCommand(name, name, nil)
		end
		return false
	elseif kind == "plugin" then
		local target, rest = Parser.rest(body)
		local owner, name = target:match("^([%a_][%w_%-]*)%.([%a_][%w_%-]*)$")
		if not owner then
			Console.fail({ Kind = "unknown", Message = "plugin commands look like :plugin.command", Hints = { "the Commands topic in the documentation lists plugin commands" } })
			return false
		end
		local command = Commands.get(owner, name)
		if command then
			return Console.runCommand(command, rest)
		end
		unknownCommand(target, name, owner)
		return false
	elseif kind == "code" then
		return runCode(body, false)
	elseif kind == "pretty" then
		return runCode(body, true)
	elseif kind == "help" then
		local help = Commands.get("core", "help")
		return help ~= nil and Console.runCommand(help, body)
	elseif kind == "note" then
		if body ~= "" then
			Console.write("note", body)
		end
		return true
	elseif kind == "recall" then
		Console.fail({ Kind = "unknown", Message = "! only works at the start of an input" })
		return false
	end
	return false
end

-- What pressing Enter does: history, echo, then each && part in order
-- (stopping at the first that fails). Runs on its own thread so commands
-- may wait (/wait, code that yields).
function Console.run(input: string)
	local text = Parser.trim(tostring(input or ""))
	if text == "" then
		return
	end
	local kind, body = Parser.classify(text)
	if kind == "recall" then
		local recalled, reason = Console.recall(body)
		if not recalled then
			Console.echo(text)
			Console.fail({ Kind = "unknown", Message = reason, Input = text, Hints = { "/history lists what can be recalled" } })
			return
		end
		text = recalled
	end
	Console.pushHistory(text)
	Console.echo(text)

	local parts = Parser.chain(text)
	task.spawn(function()
		local ok = true
		local skipped = 0
		for index, part in parts do
			-- a && b: b only if a worked.  a || b: b only if a failed.
			if index > 1 and ((part.Op == "&&" and not ok) or (part.Op == "||" and ok)) then
				if part.Op == "&&" then
					skipped += 1
				end
				continue
			end
			ok = Console.guarded(part.Text)
		end
		if skipped > 0 then
			Console.write("hint", ("stopped · %d more part%s not run"):format(skipped, if skipped == 1 then "" else "s"))
		end
	end)
end

-- Console.execute with a safety net: whatever goes wrong inside Tungsten
-- while running an input ends in an [x] line, never in silence.
function Console.guarded(text: string): boolean
	local previous = Console.CurrentInput
	Console.CurrentInput = text
	local trace = nil
	local ok, result = xpcall(Console.execute, function(message)
		trace = debug.traceback(tostring(message), 2)
		return message
	end, text)
	Console.CurrentInput = previous
	if ok then
		return result == true
	end
	T.Log.error("console", ("running \"%s\" failed inside Tungsten:\n%s"):format(text, tostring(trace)))
	pcall(Console.fail, {
		Kind = "internal",
		Message = "Tungsten failed while running this: " .. cleanError(result),
		Input = text,
		Trace = trace,
	})
	return false
end

----------------------------------------------------------------------
-- Completion data (the tab's UI shows it)
----------------------------------------------------------------------

local function startsWith(text: string, prefix: string): boolean
	return text:sub(1, #prefix):lower() == prefix:lower()
end

--[[
	Console.complete(text, cursor) -> {
		Start = position of the token, Token = the token so far,
		Items = { { Text = replacement, Label = shown, Hint = muted } },
		Live = true when the list may be shown while typing ($, / and :)
	}
]]
function Console.complete(text: string, cursor: number?)
	cursor = cursor or (#text + 1)
	local start, token = Parser.tokenAt(text, cursor :: number)
	local before = text:sub(1, start - 1)
	local first = before:match("^%s*$") ~= nil
	local items = {}
	local live = false

	if token:sub(1, 1) == "$" then
		live = true
		local partial = token:sub(2)
		for _, entry in Variables.list() do
			if startsWith(entry.Name, partial) then
				table.insert(items, { Text = "$" .. entry.Name, Label = "$" .. entry.Name, Hint = Types.tag(entry.Value) })
			end
		end
	elseif first and token:sub(1, 1) == "/" then
		live = true
		local partial = token:sub(2)
		local seen = {}
		for _, command in Commands.list() do
			if not command.Hidden and not seen[command.Name] and startsWith(command.Name, partial) then
				local resolved = Commands.resolve(command.Name)
				if resolved == command then
					seen[command.Name] = true
					table.insert(items, { Text = "/" .. command.Name .. " ", Label = "/" .. command.Name, Hint = command.Description })
				end
			end
		end
		for name, target in Console.Aliases do
			if not seen[name] and startsWith(name, partial) then
				table.insert(items, { Text = "/" .. name .. " ", Label = "/" .. name, Hint = "alias · " .. target })
			end
		end
	elseif first and token:sub(1, 1) == "?" then
		live = true
		local partial = token:sub(2)
		for _, command in Commands.list() do
			if not command.Hidden and command.Owner == "core" and startsWith(command.Name, partial) then
				table.insert(items, { Text = "?" .. command.Name, Label = "?" .. command.Name, Hint = command.Description })
			end
		end
	elseif first and token:sub(1, 1) == ":" then
		live = true
		local partial = token:sub(2)
		for _, command in Commands.list() do
			local full = command.Owner .. "." .. command.Name
			if command.Owner ~= "core" and not command.Hidden and startsWith(full, partial) then
				table.insert(items, { Text = ":" .. full .. " ", Label = ":" .. full, Hint = command.Description })
			end
		end
	elseif not first then
		-- Arguments: ask the command.
		local words = Parser.split(before)
		local head = words[1] or ""
		local command
		if head:sub(1, 1) == "/" then
			command = Commands.resolve(head:sub(2))
		elseif head:sub(1, 1) == ":" then
			local owner, name = head:sub(2):match("^([%a_][%w_%-]*)%.([%a_][%w_%-]*)$")
			command = owner and Commands.get(owner, name)
		end
		if command and command.Complete then
			local ok, list = pcall(command.Complete, { Console = Console, Variables = Variables, T = T }, #words, token)
			if not ok and command.Owner ~= "core" then
				T.import("console/reporter").ownerFault(command.Owner, ("completing %s"):format(Commands.invocation(command)), list)
			end
			if ok and type(list) == "table" then
				for _, entry in list do
					local value = if type(entry) == "table" then entry.Text else tostring(entry)
					if startsWith(value, token) then
						table.insert(items, {
							Text = value,
							Label = if type(entry) == "table" then entry.Label or value else value,
							Hint = if type(entry) == "table" then entry.Hint else nil,
						})
					end
				end
			end
		end
	end

	table.sort(items, function(a, b)
		return a.Label:lower() < b.Label:lower()
	end)
	return { Start = start, Token = token, Items = items, Live = live }
end

-- Longest shared start of the items' texts (case-insensitive match).
function Console.commonPrefix(items): string
	if #items == 0 then
		return ""
	end
	local prefix = items[1].Text
	for index = 2, #items do
		local other = items[index].Text
		local length = 0
		for position = 1, math.min(#prefix, #other) do
			if prefix:sub(position, position):lower() ~= other:sub(position, position):lower() then
				break
			end
			length = position
		end
		prefix = prefix:sub(1, length)
	end
	return prefix
end

----------------------------------------------------------------------
-- [game] output
----------------------------------------------------------------------

local gameConnection: RBXScriptConnection? = nil

function Console.gameOutput(): boolean
	return Settings.get("ConsoleGameOutput") == true
end

local function applyGameOutput()
	local wanted = Console.gameOutput()
	if wanted and not gameConnection then
		local ok, result = pcall(function()
			return Services.LogService.MessageOut:Connect(function(message, messageType)
				local line = Console.game(message, messageType)
				local kind = if typeof(messageType) == "EnumItem" then messageType.Name else tostring(messageType)
				if kind == "MessageError" and line then
					-- Kept in /errors too (no extra output).
					line.Error = Errors.record({ Kind = "game", Message = tostring(message) })
				end
			end)
		end)
		if ok then
			gameConnection = result
		else
			T.Log.warn("console", "game output unavailable: " .. tostring(result))
		end
	elseif not wanted and gameConnection then
		gameConnection:Disconnect()
		gameConnection = nil
	end
end

function Console.setGameOutput(on: boolean)
	Settings.set("ConsoleGameOutput", on == true)
	applyGameOutput()
end

----------------------------------------------------------------------
-- Start-up
----------------------------------------------------------------------

function Console.executor(): (string, string)
	local name, version = "unknown executor", ""
	pcall(function()
		local n, v = identifyexecutor()
		name, version = tostring(n or name), tostring(v or "")
	end)
	return name, version
end

function Console.pluginCount(): number
	local plugins = T.Plugins
	if type(plugins) == "table" and type(plugins.count) == "function" then
		local ok, count = pcall(plugins.count)
		if ok and type(count) == "number" then
			return count
		end
	end
	return 0
end

--[[
	The start-up lines: name, version, executor, load time and plugins,
	then the integrity checks (base/integrity), then how to start.
	info.LoadTime (seconds) comes from the loader.
]]
function Console.welcome(info: { [string]: any }?)
	info = info or {}
	local name, version = Console.executor()
	local count = Console.pluginCount()
	local loadTime = tonumber((info :: any).LoadTime)
	local pluginTime = tonumber((info :: any).PluginLoadTime)
	local troubled = 0 -- plugins that failed or have a problem
	local host = T.Plugins
	if type(host) == "table" and type(host.list) == "function" then
		pcall(function()
			for _, record in host.list() do
				if record.State == "failed" or (record.State == "problem" and record.Id and host.wanted(record.Id)) then
					troubled += 1
				end
			end
		end)
	end
	Console.write("info", {
		{ Text = "tungsten", Color = "Accent" },
		{ Text = " (unified) ", Color = "Text" },
		{ Text = "v" .. T.Version, Color = "Accent" },
		{ Text = (" · %s%s"):format(name, if version ~= "" then " " .. version else ""), Color = "TextDim" },
	})
	Console.detail({
		{ Text = "loaded in ", Color = "TextMuted" },
		{ Text = if loadTime then ("%d ms"):format(math.floor(loadTime * 1000 + 0.5)) else "?", Color = "Text" },
		{ Text = " · ", Color = "TextMuted" },
		{ Text = ("%d plugin%s"):format(count, if count == 1 then "" else "s"), Color = "Text" },
		{ Text = " loaded", Color = "TextMuted" },
		-- plugin load time is counted apart from Tungsten's own
		{ Text = if count > 0 and pluginTime then (" in %d ms"):format(math.floor(pluginTime * 1000 + 0.5)) else "", Color = "TextMuted" },
		{ Text = if troubled > 0 then (" · %d didn't start (/plugins)"):format(troubled) else "", Color = "Warning" },
	})
	local okCheck, report = pcall(function()
		return T.import("base/integrity").run()
	end)
	if not okCheck then
		Console.write("warn", "integrity check failed to run: " .. tostring(report))
	else
		Console.detail({
			{ Text = "integrity ", Color = "TextMuted" },
			{ Text = if report.Clean then "ok" elseif report.Ok then "ok, with notes" else "problems", Color = if report.Clean then "Success" elseif report.Ok then "Warning" else "Danger" },
			{ Text = " · " .. report.Summary, Color = "TextMuted" },
		})
		for index, text in report.Problems do
			if index > 6 then
				Console.detail({ { Text = ("  … and %d more · /integrity lists them"):format(#report.Problems - 6), Color = "TextMuted" } })
				break
			end
			Console.detail({ { Text = "  " .. text, Color = "Warning" } })
		end
	end
	Console.write("info", {
		{ Text = "Type ", Color = "TextDim" },
		{ Text = "/help", Color = "Accent" },
		{ Text = " for commands · ", Color = "TextDim" },
		{ Text = ">", Color = "Accent" },
		{ Text = " runs Luau · ", Color = "TextDim" },
		{ Text = "$name", Color = "Accent" },
		{ Text = " uses a variable · ", Color = "TextDim" },
		{ Text = if T.CommandBar then T.CommandBar.keyText() else "'", Color = "Accent" },
		{ Text = " opens the command bar", Color = "TextDim" },
	})
end

function Console.start()
	Commands.loadAll()
	applyGameOutput()
	T.Bin:Add(Settings.Changed:Connect(function(key)
		if key == "ConsoleGameOutput" then
			applyGameOutput()
		end
	end))
	T.Bin:Add(function()
		if gameConnection then
			gameConnection:Disconnect()
			gameConnection = nil
		end
		table.clear(Console.Lines)
		for _, sig in { Console.LineAdded, Console.LinesTrimmed, Console.Cleared } do
			sig:DisconnectAll()
		end
	end)
end

return Console
