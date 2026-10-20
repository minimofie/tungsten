--[[
	Tungsten · base/textfilter
	The filter syntax every text search in Tungsten shares (dropdown and
	picker searches, the documentation search, the console's /search
	words…). Words are combined: each must match.

		door        contains "door" (any case)
		"Door"      is exactly Door
		!door       does not contain "door"
		key:value   a field: hint:Part, type:number (fields the search offers)

		local test = TextFilter.compile('part !wedge')
		test({ "PartName", "hint text" }) -> true / false
		TextFilter.isPlain(text) -> true for one plain word (callers may rank)
]]

local TextFilter = {}

local function words(text: string): { string }
	local list = {}
	local position = 1
	while position <= #text do
		local start = text:find("%S", position)
		if not start then
			break
		end
		local negate = text:sub(start, start) == "!"
		local body = if negate then start + 1 else start
		local c = text:sub(body, body)
		if c == '"' or c == "'" then
			local close = text:find(c, body + 1, true)
			local finish = close or #text + 1
			table.insert(list, (if negate then "!" else "") .. text:sub(body, finish))
			position = finish + 1
		else
			local finish = (text:find("%s", start) or #text + 1) - 1
			table.insert(list, text:sub(start, finish))
			position = finish + 1
		end
	end
	return list
end
TextFilter.words = words

function TextFilter.isPlain(text: string): boolean
	local list = words(text)
	if #list ~= 1 then
		return #list == 0
	end
	local word = list[1]
	return not (word:sub(1, 1) == "!" or word:sub(1, 1) == '"' or word:sub(1, 1) == "'" or word:find(":", 1, true))
end

--[[
	TextFilter.compile(text) -> test(texts, fields) -> boolean
	texts: the strings a word may be found in ({ name, hint, … })
	fields: { hint = "Part", type = "number" } for key:value words
]]
function TextFilter.compile(text: string)
	local tests = {}
	for _, word in words(tostring(text or "")) do
		local negate = word:sub(1, 1) == "!" and #word > 1
		if negate then
			word = word:sub(2)
		end
		local test
		local quote = word:sub(1, 1)
		if (quote == '"' or quote == "'") and #word >= 2 then
			local exact = word:sub(2):gsub(quote .. "$", "")
			test = function(texts)
				for _, item in texts do
					if item == exact then
						return true
					end
				end
				return false
			end
		else
			local key, value = word:match("^([%a_]+):(.*)$")
			if key and value ~= "" then
				key, value = key:lower(), value:lower()
				test = function(texts, fields)
					local field = fields and fields[key]
					if field == nil then
						return false
					end
					return tostring(field):lower():find(value, 1, true) ~= nil
				end
			else
				local lower = word:lower()
				test = function(texts)
					for _, item in texts do
						if tostring(item):lower():find(lower, 1, true) then
							return true
						end
					end
					return false
				end
			end
		end
		table.insert(tests, if negate then function(texts, fields) return not test(texts, fields) end else test)
	end
	return function(texts: { string }, fields: { [string]: any }?): boolean
		for _, test in tests do
			if not test(texts, fields) then
				return false
			end
		end
		return true
	end
end

return TextFilter
