--[[
	Tungsten · console/errors
	What the console knows about things that went wrong.

	Every [x] line the console writes for a failed input is backed by an
	error record:
		{
			Id, Time,
			Kind     = "syntax" | "runtime" | "command" | "unknown" | "internal" | "game"
			           | "plugin" | "explorer" (reports from console/reporter),
			Source, Label = who reported it (reporters only: id and shown name),
			Message  = the error text,
			Input    = what was typed (rerun with /retry),
			Code     = the Luau that failed (code errors),
			Command  = "/name" (command errors),
			Trace    = { frame lines } (runtime and internal errors, cleaned),
			Hints    = { "plain-language explanations" },
			Caret    = { line, marker } (syntax errors: where it went wrong),
		}
	The newest record is the reserved variable $err; /errors lists them,
	/trace shows one in full, /retry runs its input again.

		Errors.record(info)   -> record (no output)
		Errors.report(info)   -> record + [x] line (+ caret, hints, trace)
		Errors.get(id?)       -> a record (newest when id is nil)
		Errors.list()
		Errors.Added:Connect(function(record) end)
]]

local T = ...
local signal = T.import("base/signal")
local Settings = T.import("base/settings")
local Types = T.import("base/types")
local Variables = T.import("base/variables")
local Parser = T.import("console/parser")

local Errors = {}
Errors.Max = 50
Errors.Added = signal.new() -- (record)
Errors.Cleared = signal.new()

local list: { any } = {}
local nextId = 0

local function clock(): string
	local ok, t = pcall(function()
		return DateTime.now():ToLocalTime()
	end)
	return if ok and t then ("%02d:%02d:%02d"):format(t.Hour, t.Minute, t.Second) else "--:--:--"
end

----------------------------------------------------------------------
-- Tracebacks
----------------------------------------------------------------------

-- Keeps the frames that belong to the user's code; drops Tungsten's own
-- and the engine's plumbing.
function Errors.cleanTrace(trace: string?): { string }
	local frames = {}
	if type(trace) ~= "string" then
		return frames
	end
	for line in (trace .. "\n"):gmatch("(.-)\n") do
		local text = line:gsub("^%s+", ""):gsub("%s+$", "")
		if text ~= "" and text ~= "stack traceback:" and text ~= "Stack Begin" and text ~= "Stack End" then
			local internal = text:find(T.Root .. "/", 1, true) ~= nil
				or text:find("[C]", 1, true) ~= nil
				or text:find("^function <") ~= nil
			if not internal then
				table.insert(frames, text)
			end
		end
	end
	-- The first line is usually the message itself; drop it if repeated.
	return frames
end

----------------------------------------------------------------------
-- Syntax errors: where it went wrong
----------------------------------------------------------------------

-- Returns the code line and a "    ^" marker under the problem, or nil.
function Errors.caret(code: string?, message: string): { string }?
	if type(code) ~= "string" or code == "" then
		return nil
	end
	local firstLine = code:match("^[^\n]*") or code
	local got = message:match("got '(.-)'") or message:match("got (%b<>)")
	local column = nil
	if got == "<eof>" or message:find("<eof>", 1, true) then
		column = #firstLine + 1
	elseif got and got ~= "" then
		column = firstLine:find(got, 1, true)
	elseif message:find("Malformed string", 1, true) then
		column = firstLine:find("[\"'`]")
	elseif message:find("Expected 'end'", 1, true) or message:find("Expected 'until'", 1, true) then
		column = #firstLine + 1
	end
	if not column then
		return nil
	end
	return { firstLine, string.rep(" ", column - 1) .. "^" }
end

----------------------------------------------------------------------
-- Explanations
----------------------------------------------------------------------

local function closest(name: string, candidates: { string }, limit: number?): { string }
	local scored = {}
	local lower = name:lower()
	for _, candidate in candidates do
		local distance = Parser.distance(lower, candidate:lower())
		local allowed = if #name >= 4 then math.max(2, math.floor(#name / 4)) else 1
		if distance <= allowed or candidate:lower():find(lower, 1, true) == 1 then
			table.insert(scored, { candidate, distance })
		end
	end
	table.sort(scored, function(a, b)
		return a[2] < b[2]
	end)
	local out = {}
	for index = 1, math.min(#scored, limit or 3) do
		table.insert(out, scored[index][1])
	end
	return out
end

local function memberNames(value: any): { string }
	local names = {}
	if typeof(value) == "Instance" then
		local ok, children = pcall(function()
			return value:GetChildren()
		end)
		if ok then
			for _, child in children do
				local okName, name = pcall(function()
					return child.Name
				end)
				if okName then
					table.insert(names, name)
				end
			end
		end
	elseif type(value) == "table" then
		for key in value do
			if type(key) == "string" then
				table.insert(names, key)
			end
		end
	end
	return names
end

local function quoteList(names: { string }): string
	local parts = {}
	for _, name in names do
		table.insert(parts, '"' .. name .. '"')
	end
	return table.concat(parts, " or ")
end

--[[
	Walks the dotted paths in the code (a.b.c, $x.y, workspace.Part.Size)
	without running anything else, and finds the first part that is
	missing. Only plain indexing is done: no calls.
	lookup(name) -> value, found   (variables, then globals)
]]
function Errors.findMissing(code: string, lookup: (string) -> (any, boolean)): string?
	local source = code:gsub("%-%-[^\n]*", ""):gsub('"[^"]*"', '""'):gsub("'[^']*'", "''")
	-- Names the code declares itself (locals, parameters, loop variables)
	-- only exist while it runs, so they can't be checked from outside.
	local declared = {}
	local function declare(list: string)
		for name in list:gmatch("[%a_][%w_]*") do
			declared[name] = true
		end
	end
	for list in source:gmatch("local%s+function%s+([%a_][%w_]*)") do
		declare(list)
	end
	for list in source:gmatch("local%s+([%a_][%w_%s,]*)") do
		declare(list)
	end
	for list in source:gmatch("function[^%(]*%(([^%)]*)%)") do
		declare(list)
	end
	for list in source:gmatch("for%s+([%a_][%w_%s,]*)%s+in%s") do
		declare(list)
	end
	for name in source:gmatch("for%s+([%a_][%w_]*)%s*=") do
		declared[name] = true
	end
	for chain in source:gmatch("%$?[%a_][%w_]*[%.:][%a_][%w_%.:]*") do
		local parts = {}
		local isVariable = chain:sub(1, 1) == "$"
		for piece in chain:gsub("^%$", ""):gmatch("[^%.:]+") do
			table.insert(parts, piece)
		end
		local root = parts[1]
		if declared[root] and not isVariable then
			continue
		end
		local current, found = lookup(root)
		if not found or current == nil then
			if not Types.isIdentifier(root) then
				continue
			end
			local suggestions = closest(root, Variables.names())
			return ("%s is nil · no variable or global named %s%s"):format(
				root, root, if #suggestions > 0 then " · did you mean " .. quoteList(suggestions) .. "?" else ""
			)
		end
		local walked = root
		for index = 2, #parts do
			local key = parts[index]
			-- A call after this part (a:b()) means it's a method: stop here.
			local ok, nextValue = pcall(function()
				return current[key]
			end)
			if not ok or nextValue == nil then
				local suggestions = closest(key, memberNames(current))
				local what = if typeof(current) == "Instance"
					then ("%s (%s) has no child or property \"%s\""):format(walked, Types.tag(current), key)
					else ("%s has no \"%s\""):format(walked, key)
				return what .. (if #suggestions > 0 then " · did you mean " .. quoteList(suggestions) .. "?" else "")
			end
			walked ..= "." .. key
			current = nextValue
			if type(current) ~= "table" and typeof(current) ~= "Instance" and type(current) ~= "userdata" then
				break
			end
		end
	end
	return nil
end

-- Plain-language hints for a record. lookup is used for code errors.
function Errors.explain(record, lookup: ((string) -> (any, boolean))?): { string }
	local hints = {}
	local message = tostring(record.Message or "")
	local code = record.Code

	local function add(text: string?)
		if text and not table.find(hints, text) then
			table.insert(hints, text)
		end
	end

	-- Where a path breaks.
	-- Any error about a nil value (indexing, calling, arithmetic, joining) or
	-- a missing Roblox member may come from a path with a missing part.
	if code and lookup and (message:find("nil", 1, true) or message:find("is not a valid member", 1, true)) then
		local ok, missing = pcall(Errors.findMissing, code, lookup)
		if ok and missing then
			add(missing)
		end
	end

	local variable = message:match("unknown variable %$([%a_][%w_]*)")
	if variable then
		local suggestions = closest(variable, Variables.names())
		add(if #suggestions > 0
			then ("did you mean $%s? · /vars lists every variable"):format(suggestions[1])
			else "/vars lists every variable · /set " .. variable .. " = … makes one")
	end

	local key = message:match("attempt to index nil with '([^']+)'")
	if key then
		add(("the value before .%s is nil · check each part with = (for example = workspace)"):format(key))
	elseif message:find("attempt to call a nil value", 1, true) then
		add("a function name is misspelled, or the object has no such method")
	end
	local op, side = message:match("attempt to perform arithmetic %((%a+)%) on (%a+)")
	if op then
		add(("one side of the %s is %s, not a number · /type $name shows a variable's type"):format(op, side))
	end
	local concat = message:match("attempt to concatenate (%a+)")
	if concat then
		add(("a %s can't be joined with .. · wrap it in tostring(…)"):format(concat))
	end
	if message:find("attempt to compare", 1, true) then
		add("< and > need two numbers (or two strings) · check both sides with =")
	end
	if message:find("Malformed string", 1, true) then
		add("a quote is not closed")
	elseif message:find("<eof>", 1, true) then
		add("the code ends too early: a bracket, quote, then, do or end is missing")
	elseif message:find("Expected identifier when parsing expression", 1, true) then
		add("something is missing where a value should be (two operators in a row, or a stray symbol)")
	elseif message:find("Incomplete statement", 1, true) then
		add("a value on its own isn't a statement · use > or = to show it")
	end
	if message:find("is not a valid member", 1, true) then
		add("Roblox names are case-sensitive · = parent shows what is there")
	end
	if message:find("^usage:") and record.Command then
		add(("/help %s explains it"):format(record.Command:gsub("^[/:]", "")))
	end
	if record.Kind == "internal" then
		add("this is a fault in Tungsten · the log file has the details (/logs)")
	end
	return hints
end

----------------------------------------------------------------------
-- Records
----------------------------------------------------------------------

function Errors.record(info: { [string]: any })
	nextId += 1
	local record = {
		Id = nextId,
		Time = clock(),
		Kind = info.Kind or "runtime",
		Message = tostring(info.Message or "error"),
		Input = info.Input,
		Code = info.Code,
		Command = info.Command,
		Source = info.Source,
		Label = info.Label,
		Trace = if type(info.Trace) == "table" then info.Trace else Errors.cleanTrace(info.Trace),
		Hints = info.Hints or {},
	}
	if record.Kind == "syntax" then
		record.Caret = Errors.caret(record.Code, record.Message)
	end
	if #record.Hints == 0 and not info.NoExplain then
		local ok, hints = pcall(Errors.explain, record, info.Lookup)
		if ok then
			record.Hints = hints
		else
			T.Log.warn("errors", "explaining failed: " .. tostring(hints))
		end
	end
	table.insert(list, record)
	if #list > Errors.Max then
		table.remove(list, 1)
	end
	pcall(Variables.setReserved, "err", record, "console")
	T.Log.debug("errors", ("#%d %s: %s"):format(record.Id, record.Kind, record.Message))
	Errors.Added:Fire(record)
	return record
end

function Errors.get(id: number?)
	if id == nil then
		return list[#list]
	end
	for _, record in list do
		if record.Id == id then
			return record
		end
	end
	return nil
end

function Errors.list(): { any }
	return table.clone(list)
end

function Errors.clear()
	table.clear(list)
	pcall(Variables.setReserved, "err", nil)
	Errors.Cleared:Fire()
end

-- Writes the [x] line for a record, then its caret, hints and (when the
-- ConsoleTraceback setting is on) its traceback.
function Errors.write(Console, record)
	local content = if record.Label
		then { { Text = record.Label .. ": ", Color = "TextDim" }, { Text = record.Message, Color = "Text" } }
		else record.Message
	local line = Console.write("error", content)
	if line then
		line.Error = record
		line.Source = record.Source
	end
	if record.Caret then
		Console.detail({ { Text = record.Caret[1], Color = "TextDim" } })
		Console.detail({ { Text = record.Caret[2], Color = "Danger" } })
	end
	for _, hint in record.Hints do
		Console.write("hint", hint)
	end
	if Settings.get("ConsoleTraceback") == true and #record.Trace > 0 then
		for index, frame in record.Trace do
			if index > 8 then
				Console.detail({ { Text = ("… %d more · /trace %d"):format(#record.Trace - 8, record.Id), Color = "TextMuted" } })
				break
			end
			Console.detail({ { Text = frame, Color = "TextMuted" } })
		end
	end
	return line
end

-- record + write.
function Errors.report(Console, info: { [string]: any })
	local record = Errors.record(info)
	Errors.write(Console, record)
	return record
end

-- Readable summary for lists and copying.
function Errors.describe(record): { string }
	local lines = {
		("error #%d · %s · %s"):format(record.Id, record.Kind, record.Time),
		"message  " .. record.Message,
	}
	if record.Label then
		table.insert(lines, "from     " .. record.Label)
	end
	if record.Input then
		table.insert(lines, "input    " .. record.Input)
	end
	if record.Code and record.Code ~= record.Input then
		table.insert(lines, "code     " .. record.Code)
	end
	if record.Caret then
		table.insert(lines, "         " .. record.Caret[1])
		table.insert(lines, "         " .. record.Caret[2])
	end
	for _, hint in record.Hints do
		table.insert(lines, "hint     " .. hint)
	end
	if #record.Trace > 0 then
		table.insert(lines, "trace")
		for _, frame in record.Trace do
			table.insert(lines, "    " .. frame)
		end
	end
	return lines
end

T.Bin:Add(function()
	table.clear(list)
	Errors.Added:DisconnectAll()
	Errors.Cleared:DisconnectAll()
end)

return Errors
