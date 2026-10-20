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
		A heading's Chain: base/access steps from fn to its function; the rows
	under it have the same steps as OwnerChain.
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
		child.Up = node -- the row it is under (its path)
		child.Deep = node.Deep
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
		child.Up = node
		child.Deep = node.Deep
		table.insert(out, child)
	end
	return out
end

local deepFunctionChildren

-- One value as a node. ancestors: the tables / functions above it (cycles).
-- A node with Deep set (the Contents sub-tab's Deep view) opens a function
-- into its constants, upvalues and nested functions instead of only its
-- upvalues.
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
				elseif node.Deep then
					return deepFunctionChildren(node, value, mine, false)
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
		return {}, "nothing to inspect"
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
		return {}, "nothing to inspect"
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
-- Owner / Index: the function it is nested in and its place there (its
-- running copies: debug.getproto(Owner, Index, true)). Chain: base/access
-- steps from the root function. Root: that function, when it isn't the
-- loaded one (a script's running function). FromCopy: from a script's
-- bytecode copy (no path reaches it; its running copies are matched).
local function protoNode(proto: any, id: string, path: string, depth: number, seen, origin)
	local info = Inspect.protoInfo(proto)
	local okProtos, protos = call("debug.getprotos", proto)
	local nested = if okProtos and type(protos) == "table" then protos else {}
	local node = {
		Id = id,
		Key = info.Name,
		Path = path,
		Value = proto,
		Type = "function",
		Depth = depth,
		Kind = "proto",
		Expandable = #nested > 0 and not seen[proto],
		Line = info.Line,
		Params = info.Params,
		Upvalues = info.Upvalues,
		Constants = info.Constants or 0,
		Nested = #nested,
		Owner = origin.Owner,
		Index = origin.Index,
		Chain = origin.Chain,
		Root = origin.Root,
		FromCopy = origin.FromCopy,
	}
	if node.Expandable then
		local mine = table.clone(seen)
		mine[proto] = true
		node.Children = function()
			local out = {}
			for index, child in nested do
				local chain = table.clone(origin.Chain)
				table.insert(chain, { Kind = "proto", Index = index })
				table.insert(out, protoNode(child, id .. "/" .. index, path .. "." .. index, depth + 1, mine, {
					Owner = proto, Index = index, Chain = chain, Root = origin.Root, FromCopy = origin.FromCopy,
				}))
			end
			return out
		end
	end
	return node
end

-- The nested functions of fn (a function or a ProtoProxy), as a tree.
-- opts.Root / opts.FromCopy are passed on to the rows (see protoNode).
function Rows.functions(fn: any, opts: { [string]: any }?): ({ any }, string?)
	local o = opts or {}
	if fn == nil then
		return {}, "nothing to inspect"
	end
	if not Inspect.isProto(fn) and Inspect.isC(fn) then
		return {}, "a C function has no nested functions"
	end
	local ok, protos = call("debug.getprotos", fn)
	if not ok or type(protos) ~= "table" then
		return {}, "debug.getprotos didn't answer: " .. tostring(protos)
	end
	local out = {}
	for index, proto in protos do
		table.insert(out, protoNode(proto, (o.IdPrefix or "p") .. index, tostring(index), o.Depth or 0, { [fn] = true }, {
			Owner = fn, Index = index, Chain = { { Kind = "proto", Index = index } }, Root = o.Root, FromCopy = o.FromCopy,
		}))
	end
	return out, nil
end

-- A running function as a row of the Functions sub-tab; it opens into its
-- nested functions.
local function liveNode(fn: any, id: string, depth: number)
	local name = Inspect.functionName(fn)
	local okLine, line = pcall(debug.info, fn, "l")
	local okInfo, info = call("debug.getinfo", fn)
	local okConst, constants = call("debug.getconstants", fn)
	local okProtos, protos = call("debug.getprotos", fn)
	local constantCount = 0
	if okConst and type(constants) == "table" then
		for _ in next, constants do
			constantCount += 1
		end
	end
	local nested = if okProtos and type(protos) == "table" then #protos else 0
	local node = {
		Id = id,
		Key = name,
		Path = name,
		Value = fn,
		Type = "function",
		Depth = depth,
		Kind = "function",
		Expandable = nested > 0,
		Line = if okLine and type(line) == "number" and line > 0 then line else nil,
		Params = if okInfo and type(info) == "table" and type(info.numparams) == "number" then info.numparams else nil,
		Upvalues = if okInfo and type(info) == "table" and type(info.nups) == "number" then info.nups else nil,
		Constants = constantCount,
		Nested = nested,
	}
	if node.Expandable then
		node.Children = function()
			return (Rows.functions(fn, { IdPrefix = id .. "/p", Depth = depth + 1, Root = fn }))
		end
	end
	return node
end

-- A group heading in the Functions sub-tab ("Running", "In the bytecode").
local function group(id: string, title: string, children: { any }, why: string?)
	return {
		Id = id,
		Key = title,
		Path = title,
		Type = "",
		Depth = 0,
		Kind = "heading",
		Expandable = #children > 0,
		Children = function()
			return children
		end,
		Count = #children,
		Note = why,
	}
end

-- The Functions sub-tab's rows. A script or ModuleScript: its running
-- functions, then the nested functions in its bytecode (from the copy).
-- A function or nested function: its nested functions.
function Rows.functionsOf(subject): ({ any }, string?)
	if subject == nil or subject.Kind == "none" then
		return {}, "nothing loaded"
	end
	if subject.Kind == "table" then
		-- the functions inside the table, by key path
		local out = {}
		for index, entry in Rows.functionsInTable(subject.Table) do
			local node = liveNode(entry.Fn, "f" .. index, 0)
			node.Key, node.Path = entry.Path, entry.Path
			local chain = {}
			for _, key in entry.Keys do
				table.insert(chain, { Kind = "key", Key = key })
			end
			node.Chain, node.ChainFrom = chain, "table"
			table.insert(out, node)
		end
		if #out == 0 then
			return {}, "no Luau functions in this table"
		end
		return out, nil
	end
	if subject.Kind == "script" or subject.Kind == "module" then
		local running = {}
		local live, why = Rows.liveFunctions(subject)
		for index, fn in live or {} do
			table.insert(running, liveNode(fn, "r" .. index, 1))
		end
		local copied = {}
		if subject.Fn ~= nil then
			copied = Rows.functions(subject.Fn, { IdPrefix = "b", Depth = 1, FromCopy = true })
		end
		return {
			group("running", "Running", running, if live then nil else why),
			group("bytecode", "In the bytecode", copied, if subject.Fn == nil then "its bytecode couldn't be read" else nil),
		}, nil
	end
	if subject.Fn == nil then
		return {}, if subject.Kind == "table" then "a table has no functions (its entries are in the Contents sub-tab)" else "this has no function to inspect"
	end
	return Rows.functions(subject.Fn)
end

-- Same constants, slot for slot?
local function sameConstants(a: any, b: any): boolean
	local okA, ca = call("debug.getconstants", a)
	local okB, cb = call("debug.getconstants", b)
	if not okA or not okB or type(ca) ~= "table" or type(cb) ~= "table" then
		return false
	end
	for index, value in next, ca do
		if not rawequal(cb[index], value) and not (value ~= value and cb[index] ~= cb[index]) then
			return false
		end
	end
	for index in next, cb do
		if ca[index] == nil then
			return false
		end
	end
	return true
end
Rows.sameConstants = sameConstants

-- The running copies of a nested function: debug.getproto(owner, index,
-- true), or for one from a script's bytecode copy, the script's running
-- functions with the same constants (and line, when known).
-- origin: { Owner, Index, FromCopy, ScriptSubject } (a subject's Proto, or a row)
function Rows.runningCopies(proto: any, origin: any): ({ any }?, string?)
	if type(origin) ~= "table" then
		return nil, "where it came from isn't known (inspect it from its function to see its running copies)"
	end
	if origin.FromCopy then
		local scriptSubject = origin.ScriptSubject
		if type(scriptSubject) ~= "table" then
			return nil, "it comes from a script's bytecode and the script isn't known"
		end
		local live, why = Rows.liveFunctions(scriptSubject)
		if not live then
			return nil, why
		end
		local okLine, line = pcall(debug.info, proto, "l")
		local wantLine = if okLine and type(line) == "number" and line > 0 then line else nil
		local out = {}
		for _, fn in live do
			local okFnLine, fnLine = pcall(debug.info, fn, "l")
			local sameLine = wantLine == nil or not okFnLine or fnLine == wantLine
			if sameLine and sameConstants(proto, fn) then
				table.insert(out, fn)
			end
		end
		return out, nil
	end
	if origin.Owner == nil or type(origin.Index) ~= "number" then
		return nil, "where it came from isn't known (inspect it from its function to see its running copies)"
	end
	local ok, copies = call("debug.getproto", origin.Owner, origin.Index, true)
	if not ok or type(copies) ~= "table" then
		return nil, "debug.getproto didn't list its running copies: " .. tostring(copies)
	end
	local out = {}
	for _, fn in copies do
		if type(fn) == "function" then
			table.insert(out, fn)
		end
	end
	return out, nil
end


-- A table's entries as root rows (the Table sub-tab).
-- opts.Deep: the Deep view (functions open into constants, upvalues and
-- nested functions).
function Rows.entries(t: any, opts: { [string]: any }?): ({ any }, string?)
	if type(t) ~= "table" then
		return {}, "not a table"
	end
	local top = { Id = if opts and opts.Deep then "d" else "t", Path = "", Depth = -1, Deep = opts ~= nil and opts.Deep == true }
	return tableChildren(top, t, { [t] = true }), nil
end

-- The Deep view's groups under a function (or a nested function, isProto):
-- Constants (editable), Upvalues (editable; not for a prototype, which
-- has none) and Nested functions (each opening the same way). Empty
-- groups are left out.
function deepFunctionChildren(node, fn: any, ancestors, isProto: boolean)
	local out = {}
	local function group(suffix: string, noun: string, build)
		local g = { Id = node.Id .. "/" .. suffix, Key = noun, Path = node.Path, Type = "", Depth = node.Depth + 1, Kind = "group", Deep = true, Up = node }
		local ok, list = pcall(build, g)
		list = if ok and type(list) == "table" then list else {}
		if #list == 0 then
			return
		end
		g.Count = #list
		g.Summary = ("%d %s"):format(#list, noun:lower())
		g.Expandable = true
		g.Children = function()
			return list
		end
		table.insert(out, g)
	end
	group("c", "Constants", function(g)
		local rows = {}
		local okConst, constants = call("debug.getconstants", fn)
		if okConst and type(constants) == "table" then
			local highest = 0
			for index in next, constants do
				if type(index) == "number" and index > highest then
					highest = index
				end
			end
			for index = 1, highest do
				local value = constants[index]
				if value ~= nil then
					local row = valueNode(g.Id .. "/" .. index, tostring(index), node.Path .. " · constant " .. index, value, g.Depth + 1, ancestors, "constant")
					row.Index, row.Owner = index, fn
					table.insert(rows, row)
				end
			end
		end
		return rows
	end)
	if not isProto then
		group("u", "Upvalues", function(g)
			return functionChildren(g, fn, ancestors)
		end)
	end
	group("n", "Nested functions", function(g)
		local rows = Rows.functions(fn, { IdPrefix = g.Id .. "/p", Depth = g.Depth + 1 })
		for _, row in rows do
			row.Up = g
			row.Deep = true
			local proto = row.Value
			row.Expandable = true
			row._children = nil
			row.Children = function()
				return deepFunctionChildren(row, proto, ancestors, true)
			end
		end
		return rows
	end)
	return out
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

-- A nested function's running copies with their upvalues, a heading each.
function Rows.upvaluesOfCopies(copies: { any }): ({ any }, string?)
	local out = {}
	for index, fn in copies do
		local rows = Rows.upvalues(fn)
		local title = "running " .. index
		prefix(rows, "c" .. index, title)
		local node = heading("c" .. index, fn, title, rows)
		node.CopyIndex = index
		for _, row in rows do
			row.CopyIndex = index
		end
		table.insert(out, node)
	end
	if #out == 0 then
		return {}, "no running copies of it exist now (none was made, or they are gone)"
	end
	return out, nil
end

-- Constants: the function's own, then every nested function's (depth first).
function Rows.constantsByFunction(fn: any, opts): ({ any }, string?)
	if fn == nil then
		return {}, "nothing to inspect"
	end
	if Inspect.isC(fn) then
		return {}, "a C function has no constants"
	end
	local out = {}
	local function add(target, id: string, path: string, chain, seen, owner, index)
		if #out >= Rows.MaxHeadings then
			return
		end
		local rows = Rows.constants(target, opts)
		prefix(rows, id, path)
		local node = heading(id, target, path, rows)
		node.Chain = chain
		node.Owner, node.Index = owner, index -- a nested function: where it is (running copies)
		for _, row in rows do
			row.OwnerChain = chain
		end
		table.insert(out, node)
		local ok, protos = call("debug.getprotos", target)
		if ok and type(protos) == "table" then
			for index, proto in protos do
				if not seen[proto] then
					local mine = table.clone(seen)
					mine[proto] = true
					local nextChain = table.clone(chain)
					table.insert(nextChain, { Kind = "proto", Index = index })
					add(proto, id .. "." .. index, (if path == "main" then "" else path .. ".") .. index, nextChain, mine, target, index)
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
		return {}, "nothing to inspect"
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
		for _, row in own do
			row.OwnerChain = first.Chain
		end
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
						for _, row in rows do
							row.OwnerChain = myChain
						end
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
-- upvalues are. Found four ways, the first that finds any wins:
--   1. filtergc Environment = the script's environment (getsenv)
--   2. getgc: every Luau function whose environment's `script` is it
--      (works for scripts that were cloned and moved, whose source name
--      is where they were made)
--   3. filtergc Source = the script's full name, re-checked
--   4. getgc: every Luau function whose source is the script's full name
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
	-- 2. every function the collector knows whose environment's script is it
	if #found == 0 and typeof(script) == "Instance" and Inspect.volt("getgc") then
		local ok, list = call("getgc", false)
		if ok then
			take(list, function(fn)
				local okEnv, fnEnv = pcall(getfenv, fn)
				if not okEnv or type(fnEnv) ~= "table" then
					return false
				end
				local okScript, owner = pcall(rawget, fnEnv, "script")
				return okScript and typeof(owner) == "Instance" and (owner == script or Inspect.same(owner, script))
			end)
			how = if #found > 0 then "script" else how
		end
	end
	-- 3. by source name, re-checked (how filtergc compares Source isn't documented)
	if #found == 0 and fullName and hasFilter then
		local ok, list = call("filtergc", "function", { Source = fullName, IgnoreExecutor = true })
		if ok then
			take(list, function(fn)
				return sourceOf(fn) == fullName
			end)
			how = "source"
		end
	end
	-- 4. every function the collector knows, by source name
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

-- Upvalues of several functions with one left out list: exclude[fn] = true.
function Rows.upvaluesOfOthers(list: { any }, exclude: { [any]: boolean }): ({ any }, string?)
	local rest = {}
	for _, fn in list do
		if not exclude[fn] then
			table.insert(rest, fn)
		end
	end
	return Rows.upvaluesOfFunctions(rest)
end

----------------------------------------------------------------------
-- Functions inside a table (a loaded table, a module's returned table)
----------------------------------------------------------------------

Rows.TableDepth = 4 -- how deep a table is walked for its functions
Rows.TableBudget = 20000 -- entries the walk looks at most
Rows.MaxTableFunctions = 300

-- Every Luau function in a table and the tables inside it (shared and
-- cyclic tables once), with the keys that reach it.
-- -> { { Fn, Keys = { k1, k2, … }, Path = "a.b" } }
function Rows.functionsInTable(t: any): { any }
	local out = {}
	if type(t) ~= "table" then
		return out
	end
	local seenTables, seenFns = { [t] = true }, {}
	local budget = Rows.TableBudget
	local function walk(tbl, keys, path: string, depth: number)
		local list = {}
		for key in next, tbl do
			budget -= 1
			if budget <= 0 then
				break
			end
			table.insert(list, key)
		end
		sortKeys(list)
		for _, key in list do
			if #out >= Rows.MaxTableFunctions then
				return
			end
			local value = rawget(tbl, key)
			local writable = type(key) == "string" or type(key) == "number" or type(key) == "boolean"
			if writable then
				local here = joinPath(path, key)
				local mine = table.clone(keys)
				table.insert(mine, key)
				if usable(value) and not seenFns[value] then
					seenFns[value] = true
					table.insert(out, { Fn = value, Keys = mine, Path = here })
				elseif type(value) == "table" and not seenTables[value] and depth < Rows.TableDepth then
					seenTables[value] = true
					walk(value, mine, here, depth + 1)
				end
			end
		end
	end
	walk(t, {}, "", 1)
	return out
end

-- The upvalues of every Luau function in a table, a heading per function
-- named by its key path. A heading's Chain is the key steps from the
-- table (ChainFrom = "table"), so its path can be shown and copied.
function Rows.upvaluesOfTable(t: any): ({ any }, string?, { [any]: boolean })
	local found = Rows.functionsInTable(t)
	local out, shown = {}, {}
	for index, entry in found do
		shown[entry.Fn] = true
		local id = "t" .. index
		local rows = Rows.upvalues(entry.Fn)
		local chain = {}
		for _, key in entry.Keys do
			table.insert(chain, { Kind = "key", Key = key })
		end
		prefix(rows, id, entry.Path)
		local node = heading(id, entry.Fn, entry.Path, rows)
		node.Chain, node.ChainFrom = chain, "table"
		for _, row in rows do
			row.OwnerChain, row.OwnerChainFrom = chain, "table"
		end
		table.insert(out, node)
	end
	if #out == 0 then
		return {}, "no Luau functions in this table, so no upvalues (its entries are in the Contents sub-tab)", shown
	end
	return out, nil, shown
end

-- The constants of every Luau function in a table, a heading per function
-- named by its key path (like Rows.upvaluesOfTable).
function Rows.constantsOfTable(t: any, opts: { [string]: any }?): ({ any }, string?)
	local out = {}
	for index, entry in Rows.functionsInTable(t) do
		local id = "t" .. index
		local rows = Rows.constants(entry.Fn, opts)
		local chain = {}
		for _, key in entry.Keys do
			table.insert(chain, { Kind = "key", Key = key })
		end
		prefix(rows, id, entry.Path)
		local node = heading(id, entry.Fn, entry.Path, rows)
		node.Chain, node.ChainFrom = chain, "table"
		for _, row in rows do
			row.OwnerChain, row.OwnerChainFrom = chain, "table"
		end
		table.insert(out, node)
	end
	if #out == 0 then
		return {}, "no Luau functions in this table, so no constants (its entries are in the Contents sub-tab)"
	end
	return out, nil
end

----------------------------------------------------------------------
-- Searching every function's upvalues (the scope "Search all functions")
----------------------------------------------------------------------

Rows.ScanLimit = 200 -- functions a search lists at most
Rows.ScanEntries = 50 -- matching entries a table upvalue lists at most

-- Does a value match the search text? Text: contains it (any case); a
-- number: equal, or its text starts with it; a boolean: "true" / "false";
-- a function: its name contains it; an Instance: its name contains it.
function Rows.matches(value: any, query: string): boolean
	local q = query:lower()
	if q == "" then
		return false
	end
	local kind = typeof(value)
	if kind == "string" then
		return value:lower():find(q, 1, true) ~= nil
	elseif kind == "number" then
		local n = tonumber(query)
		return (n ~= nil and n == value) or tostring(value):lower():sub(1, #q) == q
	elseif kind == "boolean" then
		return tostring(value) == q
	elseif kind == "function" then
		return Inspect.functionName(value):lower():find(q, 1, true) ~= nil
	elseif kind == "Instance" then
		local ok, name = pcall(function()
			return value.Name
		end)
		return ok and type(name) == "string" and name:lower():find(q, 1, true) ~= nil
	elseif kind == "table" then
		return false
	end
	local ok, text = pcall(tostring, value)
	return ok and type(text) == "string" and text:lower():find(q, 1, true) ~= nil
end

-- Every game function (getgc; the executor's own left out) with an upvalue
-- that matches. opts.Tables: also look inside table upvalues (keys and
-- values); the table's row then opens into the entries that matched.
-- opts.Yield(): called now and then so a long search doesn't freeze.
-- -> headings, why, { Functions = looked at, Capped = boolean }
function Rows.scanUpvalues(query: string, opts: { [string]: any }?): ({ any }, string?, { [string]: any })
	local o = opts or {}
	local stats = { Functions = 0, Capped = false }
	query = (query or ""):match("^%s*(.-)%s*$")
	if #query < 2 and not tonumber(query) then
		return {}, "type at least two characters (or a number) to search", stats
	end
	if not Inspect.volt("getgc") then
		return {}, "getgc is missing: functions can't be searched", stats
	end
	local ok, list = call("getgc", false)
	if not ok or type(list) ~= "table" then
		return {}, "getgc failed: " .. tostring(list), stats
	end
	local out = {}
	for count, fn in list do
		if count % 2000 == 0 and o.Yield then
			o.Yield()
		end
		if usable(fn) then
			stats.Functions += 1
			local okUp, upvalues = call("debug.getupvalues", fn)
			if okUp and type(upvalues) == "table" then
				local rows = {}
				local indexes = {}
				for index in next, upvalues do
					table.insert(indexes, index)
				end
				sortKeys(indexes)
				for _, index in indexes do
					local value = upvalues[index]
					local root = { [fn] = true }
					if type(value) == "table" and o.Tables then
						local matched = {}
						for key, entry in next, value do
							if not rawequal(entry, value) and (Rows.matches(key, query) or Rows.matches(entry, query)) then
								table.insert(matched, key)
								if #matched >= Rows.ScanEntries then
									break
								end
							end
						end
						if #matched > 0 then
							local node = valueNode("s" .. #out + 1 .. "/u" .. tostring(index), tostring(index), "upvalue " .. tostring(index), value, 0, root, "upvalue")
							node.Index, node.Owner = index, fn
							node.Note = ("%d matching %s"):format(#matched, if #matched == 1 then "entry" else "entries")
							node.Expandable = true
							sortKeys(matched)
							node.Children = function()
								local children = {}
								for _, key in matched do
									local child = valueNode(node.Id .. "/" .. keyText(key), keyText(key), joinPath(node.Path, key), rawget(value, key), node.Depth + 1, { [value] = true, [fn] = true }, "entry")
									child.Parent, child.RawKey, child.Up = value, key, node
									table.insert(children, child)
								end
								return children
							end
							table.insert(rows, node)
						end
					elseif type(value) ~= "table" and Rows.matches(value, query) then
						local node = valueNode("s" .. #out + 1 .. "/u" .. tostring(index), tostring(index), "upvalue " .. tostring(index), value, 0, root, "upvalue")
						node.Index, node.Owner = index, fn
						table.insert(rows, node)
					end
				end
				if #rows > 0 then
					local id = "s" .. #out + 1
					local okInfo, source, line = pcall(debug.info, fn, "sl")
					local where = if okInfo and type(source) == "string" then source:gsub("^[=@]", "") .. (if type(line) == "number" and line > 0 then ":" .. line else "") else "?"
					prefix(rows, id, Inspect.functionName(fn))
					local node = heading(id, fn, where, rows)
					table.insert(out, node)
					if #out >= Rows.ScanLimit then
						stats.Capped = true
						break
					end
				end
			end
		end
	end
	if #out == 0 then
		return {}, ("no upvalue of the %d functions looked at matches %q%s"):format(stats.Functions, query, if o.Tables then "" else " (turn on Search inside tables to look in tables too)"), stats
	end
	return out, nil, stats
end

-- A search's rows read again after a change (values, and a table's
-- entries when it is opened again).
function Rows.refreshScan(headings: { any })
	for _, headingNode in headings do
		for _, node in Rows.childrenOf(headingNode) do
			if node.Kind == "upvalue" and node.Owner ~= nil then
				local ok, upvalues = call("debug.getupvalues", node.Owner)
				if ok and type(upvalues) == "table" then
					node.Value = upvalues[node.Index]
					node.Type = typeof(node.Value)
					node._children = nil
				end
			end
		end
	end
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
		return nil, "nothing to inspect"
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
