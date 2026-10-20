--[[
	Script Viewer · lib/serialize
	Writes a value as a Luau table literal for the Table view. Values that
	can't be written as text (functions, Instances, threads, userdata,
	shared or cyclic tables, tables nested too deep) become KEEP with a
	comment saying what they are, so the same text can later be read back
	and only the changed values written (editing, part 1.6).

		Serialize.write(value, opts?) -> text
			opts.MaxDepth  (default 8)   opts.MaxEntries per table (default 500)
		Serialize.KEEP  -- the placeholder value
]]

local P = ...

local Serialize = {}
Serialize.MaxDepth = 8
Serialize.MaxEntries = 500

Serialize.KEEP = table.freeze(setmetatable({}, {
	__tostring = function()
		return "KEEP"
	end,
}))

local RESERVED = {
	["and"] = true, ["break"] = true, ["do"] = true, ["else"] = true, ["elseif"] = true,
	["end"] = true, ["false"] = true, ["for"] = true, ["function"] = true, ["if"] = true,
	["in"] = true, ["local"] = true, ["nil"] = true, ["not"] = true, ["or"] = true,
	["repeat"] = true, ["return"] = true, ["then"] = true, ["true"] = true, ["until"] = true,
	["while"] = true, ["continue"] = true,
}

local ESCAPES = { ["\\"] = "\\\\", ['"'] = '\\"', ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t" }

local function quote(text: string): string
	return '"' .. text:gsub('[%c\\"]', function(char)
		return ESCAPES[char] or string.format("\\%03d", char:byte())
	end) .. '"'
end
Serialize.quote = quote

local function comment(text: string): string
	return "--[[ " .. text:gsub("[%c%]]", " ") .. " ]]"
end

local function number(n: number): string
	if n ~= n then
		return "0/0"
	elseif n == math.huge then
		return "math.huge"
	elseif n == -math.huge then
		return "-math.huge"
	elseif n == 0 and 1 / n < 0 then
		return "-0"
	elseif n == math.floor(n) and math.abs(n) < 2 ^ 53 then
		return string.format("%d", n)
	end
	for precision = 15, 17 do
		local text = string.format("%." .. precision .. "g", n)
		if tonumber(text) == n then
			return text
		end
	end
	return string.format("%.17g", n)
end
Serialize.number = number

local function numbers(...: number): string
	local parts = {}
	for index = 1, select("#", ...) do
		parts[index] = number((select(index, ...)))
	end
	return table.concat(parts, ", ")
end

-- Roblox values written as the constructor that makes them again.
local DATATYPES: { [string]: (any) -> string } = {
	Vector3 = function(v) return `Vector3.new({numbers(v.X, v.Y, v.Z)})` end,
	Vector2 = function(v) return `Vector2.new({numbers(v.X, v.Y)})` end,
	Color3 = function(v) return `Color3.new({numbers(v.R, v.G, v.B)})` end,
	UDim = function(v) return `UDim.new({numbers(v.Scale, v.Offset)})` end,
	UDim2 = function(v) return `UDim2.new({numbers(v.X.Scale, v.X.Offset, v.Y.Scale, v.Y.Offset)})` end,
	CFrame = function(v) return `CFrame.new({numbers(v:GetComponents())})` end,
	BrickColor = function(v) return `BrickColor.new({number(v.Number)})` end,
	EnumItem = function(v) return tostring(v) end,
	NumberRange = function(v) return `NumberRange.new({numbers(v.Min, v.Max)})` end,
	vector = function(v) return `vector.create({numbers(v.x, v.y, v.z)})` end,
}

local function describe(value: any): string
	local kind = typeof(value)
	if kind == "function" then
		local ok, name = pcall(debug.info, value, "n")
		return "function " .. (if ok and type(name) == "string" and name ~= "" then name else "(anonymous)")
	elseif kind == "Instance" then
		local ok, path = pcall(function()
			return value:GetFullName()
		end)
		return "Instance " .. (if ok then path else "?")
	end
	return kind
end
Serialize.describe = describe

local function keyText(key: any): string?
	local kind = type(key)
	if kind == "string" then
		return if key:match("^[%a_][%w_]*$") and not RESERVED[key] then key else "[" .. quote(key) .. "]"
	elseif kind == "number" then
		return "[" .. number(key) .. "]"
	elseif kind == "boolean" then
		return "[" .. tostring(key) .. "]"
	end
	return nil
end

local ORDER = { number = 1, string = 2, boolean = 3 }
local function before(a: any, b: any): boolean
	local ra, rb = ORDER[type(a)] or 4, ORDER[type(b)] or 4
	if ra ~= rb then
		return ra < rb
	elseif ra == 1 or ra == 2 then
		return a < b
	elseif ra == 3 then
		return not a and b
	end
	return tostring(a) < tostring(b)
end

function Serialize.write(root: any, opts: { [string]: any }?): string
	local o = opts or {}
	local maxDepth = o.MaxDepth or Serialize.MaxDepth
	local maxEntries = o.MaxEntries or Serialize.MaxEntries
	local out = {}
	local seen = {}
	local writeValue

	local function writeTable(t: { [any]: any }, depth: number, indent: string)
		seen[t] = true
		local length = rawlen(t)
		local keys = {}
		for key in next, t do
			if not (type(key) == "number" and key >= 1 and key <= length and key % 1 == 0) then
				table.insert(keys, key)
			end
		end
		table.sort(keys, before)
		if length == 0 and #keys == 0 then
			table.insert(out, "{}")
			return
		end
		local inner = indent .. "\t"
		table.insert(out, "{\n")
		local written = 0
		for index = 1, length do
			if written >= maxEntries then
				break
			end
			written += 1
			table.insert(out, inner)
			writeValue(rawget(t, index), depth + 1, inner)
			table.insert(out, ",\n")
		end
		for _, key in keys do
			local text = keyText(key)
			if written < maxEntries and text then
				written += 1
				table.insert(out, inner .. text .. " = ")
				writeValue(rawget(t, key), depth + 1, inner)
				table.insert(out, ",\n")
			end
		end
		local total = length + #keys
		if total > written then
			table.insert(out, inner .. comment(("%d more entries not shown (other keys or past %d)"):format(total - written, maxEntries)) .. "\n")
		end
		table.insert(out, indent .. "}")
	end

	function writeValue(value: any, depth: number, indent: string)
		local kind = typeof(value)
		if kind == "nil" or kind == "boolean" then
			table.insert(out, tostring(value))
		elseif kind == "number" then
			table.insert(out, number(value))
		elseif kind == "string" then
			table.insert(out, quote(value))
		elseif kind == "table" then
			if value == Serialize.KEEP then
				table.insert(out, "KEEP")
			elseif seen[value] then
				table.insert(out, "KEEP " .. comment("a table shown earlier (shared or cyclic)"))
			elseif depth >= maxDepth then
				table.insert(out, "KEEP " .. comment("nested too deep to show"))
			else
				writeTable(value, depth, indent)
			end
		elseif DATATYPES[kind] then
			local ok, text = pcall(DATATYPES[kind], value)
			table.insert(out, if ok then text else "KEEP " .. comment(kind))
		else
			table.insert(out, "KEEP " .. comment(describe(value)))
		end
	end

	writeValue(root, 0, "")
	return table.concat(out)
end

return Serialize
