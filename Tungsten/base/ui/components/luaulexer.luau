--[[
	Tungsten · base/ui/components/luaulexer
	Splits one line of Luau into colored tokens. Long strings and long
	comments that span lines are carried in a state value from one line
	to the next.

		local tokens, nextState = Lexer.line(text, state)
		-- tokens: { { Kind = "Keyword", Text = "local" }, ... }

	Kinds: Text, Space, Keyword, Builtin, String, Number, Comment,
	Operator, Function, Property, Literal, Self.
]]

local Lexer = {}

local KEYWORDS = {}
for _, word in {
	"and", "break", "do", "else", "elseif", "end", "for", "function", "if", "in", "local", "not", "or",
	"repeat", "return", "then", "until", "while", "continue", "export", "type", "typeof",
} do
	KEYWORDS[word] = "Keyword"
end
KEYWORDS["true"] = "Literal"
KEYWORDS["false"] = "Literal"
KEYWORDS["nil"] = "Literal"
KEYWORDS["self"] = "Self"
-- `continue`, `export`, `type` are contextual in Luau; coloring them as
-- keywords is what most editors do and reads fine.
KEYWORDS["typeof"] = "Builtin"

local BUILTINS = {}
for _, word in {
	-- Luau
	"assert", "error", "getmetatable", "setmetatable", "ipairs", "pairs", "next", "pcall", "xpcall",
	"print", "warn", "rawequal", "rawget", "rawset", "rawlen", "select", "tonumber", "tostring", "type",
	"unpack", "require", "gcinfo", "newproxy", "loadstring", "getfenv", "setfenv", "_G", "_VERSION",
	"math", "string", "table", "coroutine", "debug", "utf8", "bit32", "buffer", "os", "task", "vector",
	-- Roblox
	"game", "workspace", "script", "shared", "plugin", "tick", "time", "wait", "spawn", "delay",
	"elapsedTime", "settings", "UserSettings", "Enum", "Instance", "Vector2", "Vector3", "Vector2int16",
	"Vector3int16", "CFrame", "Color3", "BrickColor", "UDim", "UDim2", "Rect", "Ray", "Region3",
	"Region3int16", "NumberRange", "NumberSequence", "NumberSequenceKeypoint", "ColorSequence",
	"ColorSequenceKeypoint", "TweenInfo", "PhysicalProperties", "Random", "DateTime", "Font", "Axes",
	"Faces", "PathWaypoint", "OverlapParams", "RaycastParams", "SharedTable", "Content",
	-- Volt
	"getgenv", "getrenv", "getsenv", "getgc", "filtergc", "getreg", "gethui", "cloneref", "hookfunction",
	"hookmetamethod", "newcclosure", "restorefunction", "checkcaller", "getnamecallmethod",
	"setnamecallmethod", "getrawmetatable", "setrawmetatable", "setreadonly", "isreadonly",
	"getconnections", "firesignal", "decompile", "saveinstance", "getproperties", "gethiddenproperty",
	"sethiddenproperty", "getcustomasset", "readfile", "writefile", "appendfile", "isfile", "isfolder",
	"makefolder", "listfiles", "delfile", "delfolder", "loadfile", "dofile", "setclipboard", "request",
	"identifyexecutor", "getscriptclosure", "getcallingscript", "getupvalues", "getupvalue",
	"setupvalue", "getconstants", "getconstant", "setconstant", "getprotos", "getproto", "getstack",
	"setstack", "iscclosure", "islclosure", "isexecutorclosure", "clonefunction", "fireclickdetector",
	"fireproximityprompt", "firetouchinterest", "getnilinstances", "getinstances", "Drawing", "crypt",
} do
	BUILTINS[word] = true
end

Lexer.Keywords = KEYWORDS
Lexer.Builtins = BUILTINS

local find, sub, match = string.find, string.sub, string.match

local function push(tokens, kind: string, text: string)
	if text == "" then
		return
	end
	local last = tokens[#tokens]
	if last and last.Kind == kind and (kind == "Operator" or kind == "Space" or kind == "Comment" or kind == "String") then
		last.Text ..= text
	else
		table.insert(tokens, { Kind = kind, Text = text })
	end
end

-- Closing bracket of a long string/comment of `level`.
local function closer(level: number): string
	return "]" .. string.rep("=", level) .. "]"
end

--[[
	state: nil, or { Kind = "Comment" | "String", Level = n } when the
	line starts inside a long bracket.
]]
function Lexer.line(text: string, state)
	local tokens = {}
	local length = #text
	local i = 1
	local prevDot = false -- last significant token was "." or ":"

	if state then
		local close = closer(state.Level)
		local _, stop = find(text, close, 1, true)
		if not stop then
			push(tokens, state.Kind, text)
			return tokens, state
		end
		push(tokens, state.Kind, sub(text, 1, stop))
		i = stop + 1
		state = nil
	end

	while i <= length do
		local c = sub(text, i, i)

		if c == " " or c == "\t" then
			local _, stop = find(text, "^[ \t]+", i)
			push(tokens, "Space", sub(text, i, stop))
			i = stop + 1
		elseif c == "-" and sub(text, i + 1, i + 1) == "-" then
			local equals = match(text, "^%[(=*)%[", i + 2)
			if equals then
				local level = #equals
				local _, stop = find(text, closer(level), i + 4 + level, true)
				if stop then
					push(tokens, "Comment", sub(text, i, stop))
					i = stop + 1
				else
					push(tokens, "Comment", sub(text, i))
					return tokens, { Kind = "Comment", Level = level }
				end
			else
				push(tokens, "Comment", sub(text, i))
				return tokens, nil
			end
		elseif c == "[" and match(text, "^%[=*%[", i) then
			local equals = match(text, "^%[(=*)%[", i)
			local level = #equals
			local _, stop = find(text, closer(level), i + 2 + level, true)
			prevDot = false
			if stop then
				push(tokens, "String", sub(text, i, stop))
				i = stop + 1
			else
				push(tokens, "String", sub(text, i))
				return tokens, { Kind = "String", Level = level }
			end
		elseif c == '"' or c == "'" or c == "`" then
			local j = i + 1
			while j <= length do
				local d = sub(text, j, j)
				if d == "\\" then
					j += 2
				elseif d == c then
					break
				else
					j += 1
				end
			end
			push(tokens, "String", sub(text, i, math.min(j, length)))
			i = j + 1
			prevDot = false
		elseif find(c, "%d") or (c == "." and find(sub(text, i + 1, i + 1), "%d")) then
			local stop = select(2, find(text, "^0[xX][%x_]+", i))
				or select(2, find(text, "^0[bB][01_]+", i))
				or select(2, find(text, "^%d*%.?[%d_]*[eE][%+%-]?%d+", i))
				or select(2, find(text, "^%d*%.?[%d_]+", i))
				or select(2, find(text, "^%d+%.?", i))
				or i
			push(tokens, "Number", sub(text, i, stop))
			i = stop + 1
			prevDot = false
		elseif find(c, "[%a_]") then
			local _, stop = find(text, "^[%w_]+", i)
			local word = sub(text, i, stop)
			local kind = KEYWORDS[word]
			if not kind then
				local after = match(text, "^[ \t]*(.)", stop + 1)
				if after == "(" or after == "{" or after == '"' or after == "'" or after == "`" then
					kind = "Function"
				elseif prevDot then
					kind = "Property"
				elseif BUILTINS[word] then
					kind = "Builtin"
				else
					kind = "Text"
				end
			elseif prevDot and kind ~= "Literal" then
				kind = "Property" -- e.g. Enum.KeyCode.End
			end
			push(tokens, kind, word)
			i = stop + 1
			prevDot = false
		else
			-- Punctuation, one character at a time (".." and "..." count as operators).
			local run = match(text, "^%.%.%.?", i)
			if run then
				push(tokens, "Operator", run)
				i += #run
				prevDot = false
			else
				push(tokens, "Operator", c)
				i += 1
				prevDot = c == "." or c == ":"
			end
		end
	end
	return tokens, state
end

return Lexer
