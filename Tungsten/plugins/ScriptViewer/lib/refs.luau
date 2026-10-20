--[[
	Script Viewer · lib/refs
	References of a constant or an upvalue: the other functions in memory
	that use the same constant, or hold the same value as an upvalue.

		Refs.canSearch(node) -> ok, why       -- is this row something to search for
		Refs.find(node, opts) -> ok, results | why, capped   (may yield)
			opts.Limit (default 200), opts.Self (the function being looked at)
		result = { Fn, Name, Source, Line, Match = "constant 3" | "upvalue 2", Self }

	Uses Volt's filtergc (functions only; it leaves out executor-made
	functions by default). Its docs don't say how a list of values is
	matched, so one value is asked for at a time and every function it
	returns is checked again here (debug.getconstants / getupvalues,
	compared with rawequal) before it is listed.
]]

local P = ...

local Inspect = P.import("lib/inspect")
local call = Inspect.call

local Refs = {}
Refs.Limit = 200

-- Values worth searching for. A constant is a string, number, boolean or
-- vector; an upvalue may be anything but nil (booleans and small numbers
-- match far too much to mean anything, but they are allowed: you asked).
function Refs.canSearch(node): (boolean, string?)
	if type(node) ~= "table" then
		return false, "select a constant or an upvalue"
	end
	if node.Kind ~= "constant" and node.Kind ~= "upvalue" then
		return false, "references are found for constants and upvalues"
	end
	if node.Value == nil then
		return false, "an empty slot has nothing to look for"
	end
	if node.Kind == "constant" then
		local kind = typeof(node.Value)
		if kind ~= "string" and kind ~= "number" and kind ~= "boolean" and kind ~= "vector" then
			return false, "a " .. kind .. " constant can't be searched for"
		end
	end
	return true, nil
end

local function indexOf(list: any, value: any): number?
	if type(list) ~= "table" then
		return nil
	end
	for index, item in next, list do
		if rawequal(item, value) then
			return index
		end
	end
	return nil
end

local function describe(fn: any)
	local name = Inspect.functionName(fn)
	local source, line
	pcall(function()
		local s, l = debug.info(fn, "sl")
		source = s
		line = if type(l) == "number" and l > 0 then l else nil
	end)
	return name, source, line
end

function Refs.find(node, opts: { [string]: any }?): (boolean, any, boolean?)
	local o = opts or {}
	local okSearch, why = Refs.canSearch(node)
	if not okSearch then
		return false, why
	end
	if not Inspect.volt("filtergc") then
		return false, "filtergc is missing: references can't be found"
	end
	local limit = o.Limit or Refs.Limit
	local field = if node.Kind == "constant" then "Constants" else "Upvalues"
	local ok, found = call("filtergc", "function", { [field] = { node.Value }, IgnoreExecutor = true })
	if not ok then
		return false, "filtergc failed: " .. tostring(found)
	end
	if type(found) ~= "table" then
		found = {}
	end
	local results = {}
	local capped = false
	for _, fn in found do
		if type(fn) == "function" and not Inspect.isC(fn) then
			local list
			if field == "Constants" then
				local okList, constants = call("debug.getconstants", fn)
				list = if okList then constants else nil
			else
				local okList, upvalues = call("debug.getupvalues", fn)
				list = if okList then upvalues else nil
			end
			local index = indexOf(list, node.Value)
			if index then
				if #results >= limit then
					capped = true
					break
				end
				local name, source, line = describe(fn)
				table.insert(results, {
					Fn = fn,
					Name = name,
					Source = source or "",
					Line = line,
					Match = (if field == "Constants" then "constant " else "upvalue ") .. tostring(index),
					Self = rawequal(fn, o.Self),
				})
			end
		end
	end
	-- the function being looked at first, then by source and line
	table.sort(results, function(a, b)
		if a.Self ~= b.Self then
			return a.Self
		end
		if a.Source ~= b.Source then
			return a.Source < b.Source
		end
		return (a.Line or 0) < (b.Line or 0)
	end)
	return true, results, capped
end

return Refs
