--[[
	Tungsten · console/parser
	Reads console input.

		Parser.classify(text)   -> kind, body
			"/help set"     -> "command", "help set"
			":viewer.open"  -> "plugin",  "viewer.open"
			"> 1 + 1"       -> "code",    "1 + 1"
			"$a * 2"        -> "code",    "$a * 2"
			"= workspace"   -> "pretty",  "workspace"
			"?set"          -> "help",    "set"
			"!!"            -> "recall",  "!"
			"# note"        -> "note",    "note"
			"help"          -> "bare",    "help"
		Parser.split(text)      -> { "set", "a", "=", "5" } with quotes kept together
		Parser.code(source)     -> Luau with every $name outside strings and
		                           comments turned into a variable lookup
		Parser.interpolate(text, lookup) -> text with $name replaced
		Parser.tokenAt(text, cursor)     -> start, token (for completion)
]]

local Parser = {}

-- The name code uses to reach variables (put into the console's code env).
Parser.VarTable = "__tungsten_vars"

function Parser.trim(text: string): string
	return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

function Parser.classify(text: string): (string, string)
	local trimmed = Parser.trim(text)
	local first = trimmed:sub(1, 1)
	if first == "/" then
		return "command", Parser.trim(trimmed:sub(2))
	elseif first == ":" then
		return "plugin", Parser.trim(trimmed:sub(2))
	elseif first == ">" then
		return "code", Parser.trim(trimmed:sub(2))
	elseif first == "=" then
		return "pretty", Parser.trim(trimmed:sub(2))
	elseif first == "$" then
		return "code", trimmed
	elseif first == "?" then
		return "help", Parser.trim(trimmed:sub(2))
	elseif first == "!" then
		return "recall", Parser.trim(trimmed:sub(2))
	elseif first == "#" then
		return "note", Parser.trim(trimmed:sub(2))
	end
	return "bare", trimmed
end

-- Words separated by spaces; "double" or 'single' quotes group words
-- (quotes removed, \" kept as "). Returns the words and, for each, the
-- character position where it started in `text`.
function Parser.split(text: string): ({ string }, { number })
	local words, starts = {}, {}
	local index = 1
	local length = #text
	while index <= length do
		local char = text:sub(index, index)
		if char:match("%s") then
			index += 1
		else
			local start = index
			local parts = {}
			while index <= length and not text:sub(index, index):match("%s") do
				local c = text:sub(index, index)
				if c == '"' or c == "'" then
					local quoteChar = c
					index += 1
					while index <= length do
						local q = text:sub(index, index)
						if q == "\\" and index < length then
							table.insert(parts, text:sub(index + 1, index + 1))
							index += 2
						elseif q == quoteChar then
							index += 1
							break
						else
							table.insert(parts, q)
							index += 1
						end
					end
				else
					table.insert(parts, c)
					index += 1
				end
			end
			table.insert(words, table.concat(parts))
			table.insert(starts, start)
		end
	end
	return words, starts
end

-- Everything after the first word (the raw argument text).
function Parser.rest(text: string): (string, string)
	local name, rest = text:match("^(%S+)%s*(.-)%s*$")
	return name or "", rest or ""
end

----------------------------------------------------------------------
-- $name in Luau code
----------------------------------------------------------------------

-- Length of a long bracket opener at `index` ("[[", "[==["), or nil.
local function longOpen(source: string, index: number): (number?, number?)
	local equals = source:match("^%[(=*)%[", index)
	if equals then
		return #equals, 2 + #equals
	end
	return nil, nil
end

-- Converts $name to __tungsten_vars.name, skipping strings and comments.
-- Returns the converted code and the names it referenced.
function Parser.code(source: string): (string, { string })
	local out = {}
	local names = {}
	local index = 1
	local length = #source
	local function emit(piece: string)
		table.insert(out, piece)
	end
	while index <= length do
		local char = source:sub(index, index)
		if char == "-" and source:sub(index + 1, index + 1) == "-" then
			-- Comment: long or to end of line.
			local level, openLength = longOpen(source, index + 2)
			local stop
			if level then
				local close = "]" .. string.rep("=", level) .. "]"
				local found = source:find(close, index + 2 + (openLength :: number), true)
				stop = if found then found + #close - 1 else length
			else
				local found = source:find("\n", index, true)
				stop = if found then found - 1 else length
			end
			emit(source:sub(index, stop))
			index = stop + 1
		elseif char == '"' or char == "'" or char == "`" then
			local stop = index + 1
			while stop <= length do
				local c = source:sub(stop, stop)
				if c == "\\" then
					stop += 2
				elseif c == char or c == "\n" then
					break
				else
					stop += 1
				end
			end
			emit(source:sub(index, math.min(stop, length)))
			index = stop + 1
		elseif char == "[" and longOpen(source, index) then
			local level, openLength = longOpen(source, index)
			local close = "]" .. string.rep("=", level :: number) .. "]"
			local found = source:find(close, index + (openLength :: number), true)
			local stop = if found then found + #close - 1 else length
			emit(source:sub(index, stop))
			index = stop + 1
		elseif char == "$" then
			local name = source:match("^[%a_][%w_]*", index + 1)
			if name then
				emit(Parser.VarTable .. "." .. name)
				table.insert(names, name)
				index += 1 + #name
			else
				emit(char)
				index += 1
			end
		else
			-- Copy a run of ordinary characters in one go.
			local stop = source:find("[%-\"'`%[%$]", index + 1) or (length + 1)
			emit(source:sub(index, stop - 1))
			index = stop
		end
	end
	return table.concat(out), names
end

-- Replaces $name in plain text using lookup(name) -> text or nil.
-- "$$" gives a literal "$". Unknown names make it return nil + the name.
function Parser.interpolate(text: string, lookup: (string) -> string?): (string?, string?)
	local missing = nil
	local result = text:gsub("%$(%$?)([%a_]?[%w_]*)", function(dollar, name)
		if dollar == "$" then
			return "$" .. name
		end
		if name == "" or not name:match("^[%a_]") then
			return nil
		end
		local value = lookup(name)
		if value == nil then
			missing = missing or name
			return nil
		end
		return value
	end)
	if missing then
		return nil, missing
	end
	return result, nil
end

-- The token being typed at `cursor` (1-based position of the caret,
-- i.e. the next character to be typed goes there).
function Parser.tokenAt(text: string, cursor: number): (number, string)
	local start = cursor
	while start > 1 and not text:sub(start - 1, start - 1):match("%s") do
		start -= 1
	end
	return start, text:sub(start, cursor - 1)
end

-- Whether code reads as a statement (assignment, local, loop, ...)
-- rather than an expression; used to pick the clearer compile error.
local STATEMENT_WORDS = {
	["local"] = true, ["for"] = true, ["if"] = true, ["while"] = true, ["repeat"] = true,
	["do"] = true, ["return"] = true, ["function"] = true, ["break"] = true, ["continue"] = true,
}
function Parser.looksLikeStatement(source: string): boolean
	local first = source:match("^%s*([%a_][%w_]*)")
	if first and STATEMENT_WORDS[first] then
		return true
	end
	-- A lone "=" (not ==, ~=, <=, >=) outside strings is an assignment.
	local stripped = Parser.code(source):gsub('"[^"]*"', ""):gsub("'[^']*'", "")
	return stripped:find("[^=~<>]=[^=]") ~= nil or stripped:find("^=[^=]") ~= nil or stripped:find("[%+%-%*/%%%^]=") ~= nil
end

-- Splits input at && and || outside quotes and brackets. Each part is
-- { Text = "...", Op = "&&" | "||" | nil } where Op joins it to the part
-- before it (nil for the first).
function Parser.chain(text: string): { { Text: string, Op: string? } }
	local parts = {}
	local depth = 0
	local quote = nil
	local start = 1
	local op = nil
	local index = 1
	local length = #text
	local function push(stop: number, nextOp: string?)
		local piece = Parser.trim(text:sub(start, stop))
		if piece ~= "" then
			table.insert(parts, { Text = piece, Op = if #parts == 0 then nil else op })
		end
		op = nextOp
	end
	while index <= length do
		local c = text:sub(index, index)
		if quote then
			if c == "\\" then
				index += 1
			elseif c == quote then
				quote = nil
			end
		elseif c == '"' or c == "'" or c == "`" then
			quote = c
		elseif c == "(" or c == "{" or c == "[" then
			depth += 1
		elseif c == ")" or c == "}" or c == "]" then
			depth = math.max(0, depth - 1)
		elseif depth == 0 then
			local pair = text:sub(index, index + 1)
			if pair == "&&" or pair == "||" then
				push(index - 1, pair)
				index += 1
				start = index + 1
			end
		end
		index += 1
	end
	push(length, nil)
	return parts
end

-- Levenshtein distance, for "did you mean".
function Parser.distance(a: string, b: string): number
	if a == b then
		return 0
	end
	local la, lb = #a, #b
	if la == 0 then
		return lb
	end
	if lb == 0 then
		return la
	end
	local previous = {}
	for j = 0, lb do
		previous[j] = j
	end
	for i = 1, la do
		local current = { [0] = i }
		local ca = a:sub(i, i)
		for j = 1, lb do
			local cost = if ca == b:sub(j, j) then 0 else 1
			current[j] = math.min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
		end
		previous = current
	end
	return previous[lb]
end

return Parser
