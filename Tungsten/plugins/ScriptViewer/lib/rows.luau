--[[
	Script Viewer · lib/rows
	The rows of the Constants, Upvalues, Functions and Contents sub-tabs,
	read-only (editing is part 1.6).

		Rows.constants(fn, opts)  -> root nodes   (debug.getconstants)
		Rows.upvalues(fn, opts)   -> root nodes   (debug.getupvalues)
		Rows.functions(fn, opts)  -> root nodes   (debug.getprotos, nested)
		Rows.entries(t)           -> root nodes   (a table's entries: the Contents sub-tab)
		Rows.constantsByFunction(fn, opts) -> headings: fn's constants, then every
		                          nested function's (scope "With nested functions")
		Rows.upvaluesWithNested(fn) -> headings: fn's upvalues, then those of the
		                          running copies of its nested functions
		Rows.upvaluesOfFunctions(list) -> headings: a script's running functions
		A heading's Chain: base/access steps from fn to its function.
		Rows.plain(kind, source)  -> the plain value the Table view writes
		Rows.tree(roots, expanded)   -> visible rows, children of expanded nodes
		Rows.flat(roots, opts)       -> every row down to opts.Depth (List view)

	A node: { Id (its path, stable across refreshes), Key (shown), Path,
	Value, Type, Depth, Expandable, Children() -> nodes, Kind, Note? }.
	Tables open into their entries, functions into their upvalues, nested
	functions into their own nested functions. A table or function already
	open higher up the same branch isn't opened again (marked "cycle").
]]

local P = ...

local Inspect = P.import("lib/inspect")
local call = Inspect.call

local Rows = {}
Rows.MaxEntries = 500 -- entries shown when a table opens (the rest: a "more" row)
Rows.MaxRows = 3000 -- rows the List view builds at most
Rows.ListDepth = 3 -- how deep the List view opens things
Rows.MaxHeadings = 200 -- function headings a scope lists at most

local KEY_ORDER = { number = 1, string = 2, boolean = 3 }

-- tostring that never errors (a key's __tostring may)
local function safeText(value: any): string
	local ok, text = pcall(tostring, value)
	return if ok and type(text) == "string" then text else typeof(value)
end

local function sortKeys(keys: { any })
	local texts = {}
	table.sort(keys, function(a, b)
		local ra, rb = KEY_ORDER[type(a)] or 4, KEY_ORDER[type(b)] or 4
		if ra ~= rb then
			return ra < rb
		elseif ra == 1 then
			if a ~= a or b ~= b then -- NaN keys last
				return b ~= b and a == a
			end
			return a < b
		elseif ra == 2 then
			return a < b
		elseif ra == 3 then
			return not a and b
		end
		texts[a] = texts[a] or safeText(a)
		texts[b] = texts[b] or safeText(b)
		return texts[a] < texts[b]
	end)
end

local function keyText(key: any): string
	if type(key) == "string" then
		return if key:match("^[%a_][%w_]*$") then key else ("[%q]"):format(key)
	elseif type(key) == "number" then
		return ("[%s]"):format(tostring(key))
	end
	return "[" .. safeText(key) .. "]"
end
Rows.keyText = keyText

local function joinPath(base: string, key: any): string
	local text = keyText(key)
	if base == "" then
		return text
	end
	return if text:sub(1, 1) == "[" then base .. text else base .. "." .. text
end

local valueNode

-- Children of a table: its entries, sorted.
local function tableChildren(node, t: { [any]: any }, ancestors)
	local keys = {}
	for key in next, t do
		table.insert(keys, key)
	end
	sortKeys(keys)
	local out = {}
	for index, key in keys do
		if index > Rows.MaxEntries then
			table.insert(out, {
				Id = node.Id .. "/more",
				Key = ("… %d more"):format(#keys - Rows.MaxEntries),
				Path = node.Path,
				Depth = node.Depth + 1,
				Type = "",
				Expandable = false,
				Kind = "more",
			})
			break
		end
		local child = valueNode(node.Id .. "/" .. keyText(key), keyText(key), joinPath(node.Path, key), rawget(t, key), node.Depth + 1, ancestors, "entry")
		child.Parent = t -- the table it is in, and its key (editing)
		child.RawKey = key
		table.insert(out, child)
	end
	return out
end

-- Children of a function: its upvalues.
local function functionChildren(node, fn: any, ancestors)
	if Inspect.isC(fn) then
		return {}
	end
	local ok, upvalues = call("debug.getupvalues", fn)
	local out = {}
	if not ok or type(upvalues) ~= "table" then
		return out
	end
	local indexes = {}
	for index in next, upvalues do
		table.insert(indexes, index)
	end
	sortKeys(indexes)
	for _, index in indexes do
		local key = "upvalue " .. tostring(index)
		local child = valueNode(node.Id .. "/u" .. tostring(index), key, node.Path .. "↑" .. tostring(index), upvalues[index], node.Depth + 1, ancestors, "upvalue")
		child.Index = index
		child.Owner = fn -- the function this is an upvalue of (references)
		table.insert(out, child)
	end
	return out
end

-- One value as a node. ancestors: the tables / functions above it (cycles).
function valueNode(id: string, key: string, path: string, value: any, depth: number, ancestors, kind: string)
	local valueType = typeof(value)
	local node = {
		Id = id,
		Key = key,
		Path = path,
		Value = value,
		Type = valueType,
		Depth = depth,
		Kind = kind,
		Expandable = false,
	}
	local opens = valueType == "table" or (valueType == "function" and not Inspect.isC(value))
	if opens then
		if ancestors[value] then
			node.Note = "cycle"
		else
			node.Expandable = true
			local mine = table.clone(ancestors)
			mine[value] = true
			node.Children = function()
				if valueType == "table" then
					return tableChildren(node, value, mine)
				end
				return functionChildren(node, value, mine)
			end
		end
	end
	return node
end

----------------------------------------------------------------------
-- The three lists
----------------------------------------------------------------------

function Rows.constants(fn: any, opts: { [string]: any }?): ({ any }, string?)
	local o = opts or {}
	if fn == nil then
		return {}, "nothing to look into"
	end
	if Inspect.isC(fn) then
		return {}, "a C function has no constants"
	end
	local ok, constants = call("debug.getconstants", fn)
	if not ok or type(constants) ~= "table" then
		return {}, "debug.getconstants didn't answer: " .. tostring(constants)
	end
	local highest = 0
	for index in next, constants do
		if type(index) == "number" and index > highest then
			highest = index
		end
	end
	local out = {}
	local root = { [fn] = true }
	for index = 1, highest do
		local value = constants[index]
		if value ~= nil or o.ShowEmpty then
			local node = valueNode("c" .. index, tostring(index), "constant " .. index, value, 0, root, "constant")
			node.Index = index
			node.Owner = fn
			if value == nil then
				node.Type = "empty"
				node.Note = "empty slot"
			end
			table.insert(out, node)
		end
	end
	return out, nil
end

function Rows.upvalues(fn: any, opts: { [string]: any }?): ({ any }, string?)
	if fn == nil then
		return {}, "nothing to look into"
	end
	if Inspect.isC(fn) then
		return {}, "a C function's upvalues can't be read"
	end
	local ok, upvalues = call("debug.getupvalues", fn)
	if not ok or type(upvalues) ~= "table" then
		return {}, "debug.getupvalues didn't answer: " .. tostring(upvalues)
	end
	local indexes = {}
	for index in next, upvalues do
		table.insert(indexes, index)
	end
	sortKeys(indexes)
	local out = {}
	local root = { [fn] = true }
	for _, index in indexes do
		local node = valueNode("u" .. tostring(index), tostring(index), "upvalue " .. tostring(index), upvalues[index], 0, root, "upvalue")
		node.Index = index
		node.Owner = fn
		table.insert(out, node)
	end
	return out, nil
end

-- A nested function (ProtoProxy) as a node; its children are its own.
local function protoNode(proto: any, id: string, path: string, depth: number, seen)
	local okInfo, info = call("debug.getinfo", proto)
	local name = if okInfo and type(info) == "table" and type(info.name) == "string" and info.name ~= "" then info.name else "(anonymous)"
	local okConst, constants = call("debug.getconstants", proto)
	local okProtos, protos = call("debug.getprotos", proto)
	local constantCount = 0
	if okConst and type(constants) == "table" then
		for _ in next, constants do
			constantCount += 1
		end
	end
	local nested = if okProtos and type(protos) == "table" then protos else {}
	local node = {
		Id = id,
		Key = name,
		Path = path,
		Value = proto,
		Type = "function",
		Depth = depth,
		Kind = "proto",
		Expandable = #nested > 0 and not seen[proto],
		Params = if okInfo and type(info) == "table" and type(info.numparams) == "number" then info.numparams else nil,
		Upvalues = if okInfo and type(info) == "table" and type(info.nups) == "number" then info.nups else nil,
		Constants = constantCount,
		Nested = #nested,
	}
	if node.Expandable then
		local mine = table.clone(seen)
		mine[proto] = true
		node.Children = function()
			local out = {}
			for index, child in nested do
				table.insert(out, protoNode(child, id .. "/" .. index, path .. "." .. index, depth + 1, mine))
			end
			return out
		end
	end
	return node
end

function Rows.functions(fn: any, opts: { [string]: any }?): ({ any }, string?)
	if fn == nil then
		return {}, "nothing to look into"
	end
	if Inspect.isC(fn) then
		return {}, "a C function has no nested functions"
	end
	local ok, protos = call("debug.getprotos", fn)
	if not ok or type(protos) ~= "table" then
		return {}, "debug.getprotos didn't answer: " .. tostring(protos)
	end
	local out = {}
	for index, proto in protos do
		table.insert(out, protoNode(proto, "p" .. index, tostring(index), 0, { [fn] = true }))
	end
	return out, nil
end

-- A table's entries as root rows (the Table sub-tab).
function Rows.entries(t: any): ({ any }, string?)
	if type(t) ~= "table" then
		return {}, "not a table"
	end
	local top = { Id = "t", Path = "", Depth = -1 }
	return tableChildren(top, t, { [t] = true }), nil
end

----------------------------------------------------------------------
-- Scope "With nested functions": rows under the function that owns them
----------------------------------------------------------------------

local function functionTitle(fn: any, path: string): string
	local name
	local ok, info = call("debug.getinfo", fn)
	if ok and type(info) == "table" and type(info.name) == "string" and info.name ~= "" then
		name = info.name
	end
	if not name and type(fn) == "function" then
		name = Inspect.functionName(fn)
	end
	return (name or "(anonymous)") .. "   " .. path
end

-- Puts rows under a heading: ids and paths start with the heading's.
local function prefix(rows: { any }, id: string, path: string)
	for _, node in rows do
		node.Id = id .. "/" .. node.Id
		node.Path = path .. " · " .. node.Path
	end
end

local function heading(id: string, fn: any, path: string, children: { any }, why: string?)
	for _, child in children do
		child.Depth += 1
	end
	return {
		Id = id,
		Key = functionTitle(fn, path),
		Path = path,
		Value = fn,
		Type = "function",
		Depth = 0,
		Kind = "heading",
		Expandable = #children > 0,
		Children = function()
			return children
		end,
		Note = why,
		Count = #children,
	}
end

-- Constants: the function's own, then every nested function's (depth first).
function Rows.constantsByFunction(fn: any, opts): ({ any }, string?)
	if fn == nil then
		return {}, "nothing to look into"
	end
	if Inspect.isC(fn) then
		return {}, "a C function has no constants"
	end
	local out = {}
	local function add(target, id: string, path: string, chain, seen)
		if #out >= Rows.MaxHeadings then
			return
		end
		local rows = Rows.constants(target, opts)
		prefix(rows, id, path)
		local node = heading(id, target, path, rows)
		node.Chain = chain
		table.insert(out, node)
		local ok, protos = call("debug.getprotos", target)
		if ok and type(protos) == "table" then
			for index, proto in protos do
				if not seen[proto] then
					local mine = table.clone(seen)
					mine[proto] = true
					local nextChain = table.clone(chain)
					table.insert(nextChain, { Kind = "proto", Index = index })
					add(proto, id .. "." .. index, (if path == "main" then "" else path .. ".") .. index, nextChain, mine)
				end
			end
		end
	end
	add(fn, "f", "main", {}, { [fn] = true })
	return out, nil
end

-- Upvalues of a function and of the running copies of its nested
-- functions (debug.getproto(f, i, true): the live closures of a nested
-- function, which have real upvalues), each under a heading. Nested
-- functions of nested functions are followed too (six levels at most).
-- A heading's Chain is how its function is reached from fn (base/access
-- steps), so its path can be shown and copied.
function Rows.upvaluesWithNested(fn: any): ({ any }, string?)
	if fn == nil then
		return {}, "nothing to look into"
	end
	if typeof(fn) ~= "ProtoProxy" and Inspect.isC(fn) then
		return {}, "a C function's upvalues can't be read"
	end
	local out = {}
	if typeof(fn) ~= "ProtoProxy" then
		local own = Rows.upvalues(fn)
		prefix(own, "f", "main")
		local first = heading("f", fn, "main", own)
		first.Chain = {}
		table.insert(out, first)
	end
	local seen = { [fn] = true }
	local function walk(owner, id: string, path: string, chain, depth: number)
		local ok, protos = call("debug.getprotos", owner)
		if not ok or type(protos) ~= "table" then
			return
		end
		for index, proto in protos do
			if #out >= Rows.MaxHeadings then
				return
			end
			local here = if path == "main" then tostring(index) else path .. "." .. index
			local okCopies, copies = call("debug.getproto", owner, index, true)
			if okCopies and type(copies) == "table" then
				for copyIndex, copy in copies do
					if type(copy) == "function" and not seen[copy] and #out < Rows.MaxHeadings then
						seen[copy] = true
						local rowId = ("%s.%dr%d"):format(id, index, copyIndex)
						local title = ("nested %s · running %d"):format(here, copyIndex)
						local rows = Rows.upvalues(copy)
						prefix(rows, rowId, title)
						local node = heading(rowId, copy, title, rows)
						local myChain = table.clone(chain)
						table.insert(myChain, { Kind = "closure", Index = index, Copy = copyIndex })
						node.Chain = myChain
						table.insert(out, node)
					end
				end
			end
			if depth < 6 and not seen[proto] then
				seen[proto] = true
				local protoChain = table.clone(chain)
				table.insert(protoChain, { Kind = "proto", Index = index })
				walk(proto, id .. "." .. index, here, protoChain, depth + 1)
			end
		end
	end
	walk(fn, "f", "main", {}, 1)
	if #out == 0 then
		return {}, "it has no running copies of nested functions"
	end
	return out, nil
end

-- A script's running functions. A script's main function as the viewer
-- has it is a fresh copy (getscriptclosure), so these are where its
-- upvalues are. Found three ways, the first that finds any wins:
--   1. filtergc Environment = the script's environment (getsenv)
--   2. filtergc Source = the script's full name, re-checked
--   3. getgc: every Luau function whose source is the script's full name
-- Returns the list (by line) and how they were found, or nil and why.
Rows.MaxLive = 300

local function sourceOf(fn: any): string?
	local ok, source = pcall(debug.info, fn, "s")
	if ok and type(source) == "string" then
		return (source:gsub("^[=@]", ""))
	end
	return nil
end

local function usable(fn: any): boolean
	if type(fn) ~= "function" or Inspect.isC(fn) then
		return false
	end
	local okExec, isExec = call("isexecutorclosure", fn)
	return not (okExec and isExec == true)
end

local function fullNameOf(script: any): string?
	if typeof(script) ~= "Instance" then
		return nil
	end
	local ok, name = pcall(function()
		return script:GetFullName()
	end)
	return if ok and type(name) == "string" then name else nil
end

function Rows.liveFunctions(subject): ({ any }?, string?, string?)
	local env, script = subject.Env, subject.Instance
	local fullName = fullNameOf(script)
	local found, how = {}, nil
	local notes = {}
	local function take(list: any, check: ((fn: any) -> boolean)?)
		for _, fn in (if type(list) == "table" then list else {}) do
			if usable(fn) and (check == nil or check(fn)) then
				table.insert(found, fn)
				if #found >= Rows.MaxLive then
					break
				end
			end
		end
	end
	local hasFilter = Inspect.volt("filtergc") ~= nil
	-- 1. by environment
	if type(env) == "table" and hasFilter then
		local ok, list = call("filtergc", "function", { Environment = env, IgnoreExecutor = true })
		if ok then
			take(list)
			how = "environment"
		else
			table.insert(notes, "filtergc (Environment) failed: " .. tostring(list))
		end
	end
	-- 2. by source name, re-checked (how filtergc compares Source isn't documented)
	if #found == 0 and fullName and hasFilter then
		local ok, list = call("filtergc", "function", { Source = fullName, IgnoreExecutor = true })
		if ok then
			take(list, function(fn)
				return sourceOf(fn) == fullName
			end)
			how = "source"
		end
	end
	-- 3. every function the collector knows, by source name
	if #found == 0 and fullName and Inspect.volt("getgc") then
		local ok, list = call("getgc", false)
		if ok then
			take(list, function(fn)
				return sourceOf(fn) == fullName
			end)
			how = "getgc"
		else
			table.insert(notes, "getgc failed: " .. tostring(list))
		end
	end
	if #found == 0 then
		local what = if subject.Kind == "module" then "ModuleScript" else "script"
		local why
		if not hasFilter and not Inspect.volt("getgc") then
			why = "filtergc and getgc are missing: a script's running functions can't be found"
		elseif subject.Kind == "module" and subject.Returned == nil and env == nil then
			why = "the game hasn't required it yet, so it has no running functions"
		else
			why = ("no running functions of this %s were found (it may have finished, or not started)"):format(what)
		end
		if #notes > 0 then
			why ..= " · " .. table.concat(notes, " · ")
		end
		return nil, why, nil
	end
	local lines = {}
	for _, fn in found do
		local okLine, line = pcall(debug.info, fn, "l")
		lines[fn] = if okLine and type(line) == "number" then line else math.huge
	end
	table.sort(found, function(x, y)
		return lines[x] < lines[y]
	end)
	return found, nil, how
end

-- Upvalues of several functions: a heading per function (by its line)
-- with its upvalues under it. Functions without upvalues are left out.
function Rows.upvaluesOfFunctions(list: { any }): ({ any }, string?)
	local out = {}
	for index, fn in list do
		local rows = Rows.upvalues(fn)
		if #rows > 0 then
			local okLine, line = pcall(debug.info, fn, "l")
			local path = if okLine and type(line) == "number" and line > 0 then "line " .. line else "#" .. index
			for _, node in rows do
				node.Id = "l" .. index .. "/" .. node.Id
				node.Path = path .. " · " .. node.Path
			end
			table.insert(out, heading("l" .. index, fn, path, rows))
		end
	end
	if #out == 0 then
		return {}, ("none of its %d running functions has upvalues"):format(#list)
	end
	return out, nil
end

----------------------------------------------------------------------
-- Table view: the value written as a Luau table
----------------------------------------------------------------------

-- What the Table view writes for a panel (a plain Luau value).
function Rows.plain(kind: string, source: any): (any, string?)
	if kind == "contents" then
		if type(source) ~= "table" then
			return nil, "not a table"
		end
		return source, nil
	end
	if source == nil then
		return nil, "nothing to look into"
	end
	if Inspect.isC(source) then
		return nil, "a C function has nothing to write here"
	end
	if kind == "constants" then
		local ok, constants = call("debug.getconstants", source)
		return if ok and type(constants) == "table" then constants else nil, if ok then nil else tostring(constants)
	elseif kind == "upvalues" then
		local ok, upvalues = call("debug.getupvalues", source)
		return if ok and type(upvalues) == "table" then upvalues else nil, if ok then nil else tostring(upvalues)
	end
	-- functions: name, counts and nested functions, as data
	local function describeProto(proto, depth: number)
		local okInfo, info = call("debug.getinfo", proto)
		local okConst, constants = call("debug.getconstants", proto)
		local okProtos, protos = call("debug.getprotos", proto)
		local entry = {
			name = if okInfo and type(info) == "table" and info.name ~= "" then info.name else "(anonymous)",
			params = if okInfo and type(info) == "table" then info.numparams else nil,
			upvalues = if okInfo and type(info) == "table" then info.nups else nil,
			constants = if okConst and type(constants) == "table" then constants else nil,
		}
		if okProtos and type(protos) == "table" and #protos > 0 and depth < 6 then
			entry.functions = {}
			for index, child in protos do
				entry.functions[index] = describeProto(child, depth + 1)
			end
		end
		return entry
	end
	local ok, protos = call("debug.getprotos", source)
	if not ok or type(protos) ~= "table" then
		return nil, tostring(protos)
	end
	local out = {}
	for index, proto in protos do
		out[index] = describeProto(proto, 1)
	end
	return out, nil
end

----------------------------------------------------------------------
-- Views
----------------------------------------------------------------------

local function childrenOf(node): { any }
	if not node.Expandable or not node.Children then
		return {}
	end
	if node._children == nil then
		local ok, children = pcall(node.Children)
		node._children = if ok and type(children) == "table" then children else {}
	end
	return node._children
end
Rows.childrenOf = childrenOf

-- Tree view: roots, and the children of every expanded node (by Id).
-- expanded may be a function(node) -> boolean (function headings start
-- open unless you closed them).
function Rows.tree(roots: { any }, expanded: any): { any }
	local out = {}
	local isOpen = if type(expanded) == "function" then expanded else function(node)
		return expanded[node.Id] == true
	end
	local function walk(list)
		for _, node in list do
			if #out >= Rows.MaxRows then
				return
			end
			table.insert(out, node)
			node.Expanded = isOpen(node) == true
			if node.Expanded then
				walk(childrenOf(node))
			end
		end
	end
	walk(roots)
	return out
end

-- List view: everything down to Rows.ListDepth, flat, with paths.
function Rows.flat(roots: { any }, opts: { [string]: any }?): ({ any }, boolean)
	local depthLimit = (opts and opts.Depth) or Rows.ListDepth
	local out = {}
	local capped = false
	local function walk(list)
		for _, node in list do
			if #out >= Rows.MaxRows then
				capped = true
				return
			end
			table.insert(out, node)
			if node.Depth + 1 < depthLimit then
				walk(childrenOf(node))
			end
		end
	end
	walk(roots)
	return out, capped
end

return Rows
