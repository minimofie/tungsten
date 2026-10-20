--[[
	Script Viewer · lib/inspect
	Works out what a loaded item is and the facts the Overview shows.
	Nothing here runs game code: a ModuleScript is only "required" when
	the game already did (it is in getloadedmodules), and then require
	hands back the cached value.

		local subject = Inspect.subject(item, count)   -- item: Instance or a loaded target
		subject.Kind     "script" | "module" | "function" | "proto" | "table" | "value" | "none"
		subject.Title    what it is called      subject.Icon   an icon name
		subject.Fn       the function to inspect (a script's main function)
		subject.Table    the table to inspect (a module's returned table)
		subject.Facts    { { Id, Text, Value, Hint? } } in Overview order
		subject.Notes    { text } things the Overview says under the facts
		subject.Proto    (a nested function) where it came from: { Owner, Index,
		                 FromCopy, Script } (FromCopy: from a script's bytecode
		                 copy, so its running copies are found by matching)

	A nested function (a ProtoProxy, from debug.getproto / getprotos) is
	the "proto" kind: its Fn is the proxy (constants and nested functions
	read and written through it); its running copies hold upvalues.

	Every Volt call is guarded: a missing or failing function leaves its
	fact out (the Notes say which one).
]]

local P = ...

local Inspect = {}

-- Volt functions this file uses (each documented at docs.voltbz.net).
Inspect.Uses = {
	"getscriptclosure", "getsenv", "getrunningscripts", "getscripthash",
	"getloadedmodules", "getfunctionhash", "iscclosure", "isexecutorclosure",
	"isreadonly", "getrawmetatable", "debug.getinfo", "debug.getconstants",
	"debug.getupvalues", "debug.getprotos", "debug.getproto",
}

-- A Volt function by name ("debug.getinfo" too), or nil.
local function volt(name: string): any
	local env = getfenv(1)
	local head, rest = name:match("^(%w+)%.(%w+)$")
	if head then
		local lib = (env :: any)[head]
		local fn = if type(lib) == "table" then lib[rest] else nil
		return if type(fn) == "function" then fn else nil
	end
	local fn = (env :: any)[name]
	return if type(fn) == "function" then fn else nil
end
Inspect.volt = volt

-- Calls a Volt function; ok, result (false when missing or it failed).
local function call(name: string, ...: any): (boolean, any)
	local fn = volt(name)
	if not fn then
		return false, name .. " is missing"
	end
	return pcall(fn, ...)
end
Inspect.call = call

local function count(t: any): number
	local n = 0
	if type(t) == "table" then
		for _ in next, t do
			n += 1
		end
	end
	return n
end

local function short(hash: any): string?
	if type(hash) ~= "string" or hash == "" then
		return nil
	end
	return hash:sub(1, 12) .. "…"
end

local function same(a: Instance, b: Instance): boolean
	if a == b then
		return true
	end
	local ok, yes = pcall(compareinstances, a, b)
	return ok and yes == true
end

Inspect.same = same

local function listed(list: any, obj: Instance): boolean
	if type(list) ~= "table" then
		return false
	end
	for _, item in list do
		if typeof(item) == "Instance" and same(item, obj) then
			return true
		end
	end
	return false
end

local function pathOf(obj: Instance): string
	local ok, path = pcall(function()
		return obj:GetFullName()
	end)
	return if ok then path else "?"
end

local function isA(obj: Instance, class: string): boolean
	local ok, yes = pcall(function()
		return obj:IsA(class)
	end)
	return ok and yes == true
end

----------------------------------------------------------------------
-- Functions
----------------------------------------------------------------------

-- What Luau itself says about a function (name, source, line defined).
local function luauInfo(fn: any): (string?, string?, number?)
	local ok, source, line, name = pcall(debug.info, fn, "sln")
	if not ok then
		return nil, nil, nil
	end
	return (if type(name) == "string" and name ~= "" then name else nil), source, (if type(line) == "number" and line > 0 then line else nil)
end

function Inspect.isC(fn: any): boolean
	local ok, yes = call("iscclosure", fn)
	return ok and yes == true
end

function Inspect.functionName(fn: any): string
	local name = luauInfo(fn)
	if not name then
		local ok, info = call("debug.getinfo", fn)
		if ok and type(info) == "table" and type(info.name) == "string" and info.name ~= "" then
			name = info.name
		end
	end
	return name or "(anonymous)"
end

local function addFunctionFacts(subject, fn: any, notes: { string })
	local facts = subject.Facts
	local isC = Inspect.isC(fn)
	local _, source, line = luauInfo(fn)
	table.insert(facts, { Id = "kind", Text = "Kind", Value = if isC then "C function" else "Luau function" })
	local okExec, byExecutor = call("isexecutorclosure", fn)
	if okExec then
		table.insert(facts, { Id = "made", Text = "Made by", Value = if byExecutor then "the executor" else "the game" })
	end
	if not isC then
		if source then
			table.insert(facts, { Id = "source", Text = "Source", Value = source })
		end
		if line then
			table.insert(facts, { Id = "line", Text = "Defined at", Value = "line " .. line })
		end
	end
	local okInfo, info = call("debug.getinfo", fn)
	if okInfo and type(info) == "table" then
		if type(info.numparams) == "number" then
			local vararg = info.is_vararg == 1 or info.is_vararg == true
			table.insert(facts, { Id = "params", Text = "Parameters", Value = tostring(info.numparams) .. (if vararg then " + ..." else "") })
		end
		if type(info.nups) == "number" then
			table.insert(facts, { Id = "upvalues", Text = "Upvalues", Value = tostring(info.nups) })
		end
	else
		table.insert(notes, "debug.getinfo didn't answer: parameters and upvalues aren't shown")
	end
	if isC then
		table.insert(notes, "a C function has no constants, upvalues or nested functions to show")
		return
	end
	local okConst, constants = call("debug.getconstants", fn)
	if okConst and type(constants) == "table" then
		table.insert(facts, { Id = "constants", Text = "Constants", Value = tostring(count(constants)) })
	end
	local okProtos, protos = call("debug.getprotos", fn)
	if okProtos and type(protos) == "table" then
		table.insert(facts, { Id = "functions", Text = "Nested functions", Value = tostring(#protos) })
	end
	local okHash, hash = call("getfunctionhash", fn)
	if okHash and short(hash) then
		table.insert(facts, { Id = "hash", Text = "Hash", Value = short(hash), Full = hash, Hint = "SHA-384 of its bytecode" })
	end
end

----------------------------------------------------------------------
-- Nested functions (ProtoProxy)
----------------------------------------------------------------------

function Inspect.isProto(value: any): boolean
	return typeof(value) == "ProtoProxy"
end

-- Name, source and line of a nested function (debug.info takes a ProtoProxy).
function Inspect.protoInfo(proto: any): { [string]: any }
	local out = { Name = "(anonymous)" }
	local okInfo, info = call("debug.getinfo", proto)
	if okInfo and type(info) == "table" then
		if type(info.name) == "string" and info.name ~= "" then
			out.Name = info.name
		end
		out.Params = if type(info.numparams) == "number" then info.numparams else nil
		out.Vararg = info.is_vararg == 1 or info.is_vararg == true
		out.Upvalues = if type(info.nups) == "number" then info.nups else nil
		out.Source = if type(info.short_src) == "string" then info.short_src elseif type(info.source) == "string" then info.source else nil
	end
	local ok, source, line = pcall(debug.info, proto, "sl")
	if ok then
		out.Source = out.Source or (if type(source) == "string" then source else nil)
		out.Line = if type(line) == "number" and line > 0 then line else nil
	end
	local okConst, constants = call("debug.getconstants", proto)
	out.Constants = if okConst and type(constants) == "table" then count(constants) else nil
	local okProtos, protos = call("debug.getprotos", proto)
	out.Nested = if okProtos and type(protos) == "table" then #protos else nil
	local okHash, hash = pcall(function()
		return proto.CodeHash
	end)
	out.CodeHash = if okHash and type(hash) == "number" then hash else nil
	return out
end

local function addProtoFacts(subject, proto: any, notes: { string })
	local facts = subject.Facts
	local info = Inspect.protoInfo(proto)
	subject.Title = info.Name
	table.insert(facts, { Id = "kind", Text = "Kind", Value = "nested function prototype" })
	if info.Source then
		table.insert(facts, { Id = "source", Text = "Source", Value = info.Source })
	end
	if info.Line then
		table.insert(facts, { Id = "line", Text = "Defined at", Value = "line " .. info.Line })
	end
	if info.Params then
		table.insert(facts, { Id = "params", Text = "Parameters", Value = tostring(info.Params) .. (if info.Vararg then " + ..." else "") })
	end
	if info.Upvalues then
		table.insert(facts, { Id = "upvalues", Text = "Upvalues", Value = tostring(info.Upvalues) })
	end
	if info.Constants then
		table.insert(facts, { Id = "constants", Text = "Constants", Value = tostring(info.Constants) })
	end
	if info.Nested then
		table.insert(facts, { Id = "functions", Text = "Nested functions", Value = tostring(info.Nested) })
	end
	if info.CodeHash then
		table.insert(facts, { Id = "hash", Text = "Code hash", Value = tostring(info.CodeHash), Hint = "a 32-bit hash of its instructions" })
	end
	table.insert(notes, "a nested function's prototype: its constants and nested functions are read and changed here (every copy shares them); its running copies hold the upvalues (Upvalues)")
	if subject.Proto and subject.Proto.FromCopy then
		table.insert(notes, "it comes from the script's bytecode copy: changes go to the running copies that match it")
	end
end

----------------------------------------------------------------------
-- Tables
----------------------------------------------------------------------

local function addTableFacts(subject, t: { [any]: any })
	local facts = subject.Facts
	local array = rawlen(t)
	local total = count(t)
	table.insert(facts, { Id = "entries", Text = "Entries", Value = ("%d (%d in order, %d by key)"):format(total, array, math.max(0, total - array)) })
	local okMeta, meta = call("getrawmetatable", t)
	if not okMeta then
		okMeta, meta = pcall(getmetatable, t)
	end
	table.insert(facts, { Id = "metatable", Text = "Metatable", Value = if okMeta and meta ~= nil then "yes" else "no" })
	local okRead, readonly = call("isreadonly", t)
	local frozen = table.isfrozen(t)
	table.insert(facts, { Id = "readonly", Text = "Read-only", Value = if frozen or (okRead and readonly) then "yes" else "no" })
end

----------------------------------------------------------------------
-- Scripts
----------------------------------------------------------------------

local function mainFunction(script: Instance, notes: { string }): any
	local ok, result = call("getscriptclosure", script)
	if ok and type(result) == "function" then
		return result
	end
	if ok and type(result) == "string" then
		table.insert(notes, "its bytecode didn't compile: " .. result)
	elseif not ok then
		table.insert(notes, "its main function couldn't be read: " .. tostring(result))
	end
	return nil
end

local function addScriptFacts(subject, script: Instance, notes: { string })
	local facts = subject.Facts
	table.insert(facts, { Id = "class", Text = "Class", Value = script.ClassName })
	table.insert(facts, { Id = "path", Text = "Path", Value = pathOf(script) })
	local okHash, hash = call("getscripthash", script)
	if okHash and short(hash) then
		table.insert(facts, { Id = "hash", Text = "Hash", Value = short(hash), Full = hash, Hint = "SHA-384 of its bytecode" })
	elseif okHash then
		table.insert(notes, "it has no bytecode (nothing to decompile or inspect)")
	end
	if subject.Kind == "module" then
		local okList, modules = call("getloadedmodules")
		local required = okList and listed(modules, script)
		table.insert(facts, { Id = "required", Text = "Required by the game", Value = if required then "yes" else "no" })
		if required then
			local okRequire, value = pcall(require, script)
			if okRequire then
				subject.Returned = value
				table.insert(facts, { Id = "returns", Text = "Returns", Value = typeof(value) .. (if type(value) == "table" then (" (%d entries)"):format(count(value)) else "") })
				if type(value) == "table" then
					subject.Table = value
				end

			else
				table.insert(notes, "require failed: " .. tostring(value))
			end
		else
			table.insert(notes, "not required yet: its returned value isn't shown (requiring it would run it)")
		end
		-- its environment finds its running functions (Upvalues)
		local okEnv, env = call("getsenv", script)
		if okEnv and type(env) == "table" then
			subject.Env = env
		end
	else
		local okRunning, running = call("getrunningscripts")
		local isRunning = okRunning and listed(running, script)
		table.insert(facts, { Id = "running", Text = "Running", Value = if isRunning then "yes" else "no" })
		-- asked even when not listed as running: getsenv returns nil when
		-- the environment isn't there
		local okEnv, env = call("getsenv", script)
		if okEnv and type(env) == "table" then
			subject.Env = env
			table.insert(facts, { Id = "globals", Text = "Globals", Value = tostring(count(env)) })
		end
	end
	local main = mainFunction(script, notes)
	if main then
		subject.Fn = main
		local okConst, constants = call("debug.getconstants", main)
		if okConst and type(constants) == "table" then
			table.insert(facts, { Id = "constants", Text = "Constants (main function)", Value = tostring(count(constants)) })
		end
		local okProtos, protos = call("debug.getprotos", main)
		if okProtos and type(protos) == "table" then
			table.insert(facts, { Id = "functions", Text = "Nested functions", Value = tostring(#protos) })
		end
		table.insert(notes, "the main function is compiled again from the script's bytecode: its constants and nested functions are the script's; the running upvalues are in the script's running functions (Upvalues)")
	end
end

----------------------------------------------------------------------
-- The subject
----------------------------------------------------------------------

local function valueOf(item: any): any
	if type(item) == "table" and type(item.Kind) == "string" and item.Value ~= nil and item.Label ~= nil then
		return item.Value
	end
	return item
end

-- Where a loaded nested function came from: the target's Info, or the
-- last step of its path (debug.getproto(owner, i)).
local function protoOrigin(item: any, access: any): { [string]: any }?
	if type(item) ~= "table" then
		return nil
	end
	local info = rawget(item, "Info")
	if type(info) == "table" and info.Owner ~= nil and type(info.Index) == "number" then
		return { Owner = info.Owner, Index = info.Index, FromCopy = info.FromCopy == true, Script = info.Script, ScriptSubject = info.ScriptSubject }
	end
	local path = rawget(item, "Access")
	if access and type(path) == "table" and type(path.Steps) == "table" then
		local last = path.Steps[#path.Steps]
		if last and last.Kind == "proto" then
			local okPrefix, prefix = pcall(function()
				local steps = {}
				for index = 1, #path.Steps - 1 do
					steps[index] = path.Steps[index]
				end
				local root = access.root(path.Script)
				local a = root
				for _, step in steps do
					a = access.extend(a, step)
				end
				return a
			end)
			if okPrefix and prefix then
				local ok, owner = access.resolve(prefix)
				if ok and owner ~= nil then
					return { Owner = owner, Index = last.Index }
				end
			end
		end
	end
	return nil
end

function Inspect.subject(item: any, total: number?, access: any?)
	local subject = { Kind = "none", Title = "Nothing loaded", Icon = "type_function", Facts = {}, Notes = {}, Item = item, Count = total or (if item ~= nil then 1 else 0) }
	if item == nil then
		return subject
	end
	local notes = subject.Notes
	local value = valueOf(item)
	local kind = typeof(value)
	if kind == "Instance" then
		subject.Instance = value
		local okName, name = pcall(function()
			return value.Name
		end)
		subject.Title = if okName then tostring(name) else "?"
		if isA(value, "ModuleScript") then
			subject.Kind = "module"
			subject.Icon = "class_modulescript"
			addScriptFacts(subject, value, notes)
		elseif isA(value, "LocalScript") or isA(value, "Script") then
			subject.Kind = "script"
			subject.Icon = if isA(value, "LocalScript") then "class_localscript" else "class_script"
			addScriptFacts(subject, value, notes)
		else
			subject.Kind = "value"
			subject.Icon = "object"
			table.insert(subject.Facts, { Id = "class", Text = "Class", Value = value.ClassName })
			table.insert(notes, "load a script, a ModuleScript, a function or a table to inspect it")
		end
	elseif kind == "ProtoProxy" then
		subject.Kind = "proto"
		subject.Icon = "type_function"
		subject.Fn = value
		subject.Proto = protoOrigin(item, access)
		addProtoFacts(subject, value, notes)
		if type(item) == "table" and item ~= value and type(item.Label) == "string" and subject.Title == "(anonymous)" then
			subject.Title = item.Label
		end
	elseif kind == "function" then
		subject.Kind = "function"
		subject.Icon = "type_function"
		subject.Fn = value
		subject.Title = Inspect.functionName(value)
		addFunctionFacts(subject, value, notes)
	elseif kind == "table" then
		subject.Kind = "table"
		subject.Icon = "type_table"
		subject.Table = value
		subject.Title = if type(item) == "table" and item ~= value and type(item.Label) == "string" then item.Label else "table"
		addTableFacts(subject, value)
	else
		subject.Kind = "value"
		subject.Icon = "type_misc"
		subject.Title = kind
		local ok, text = pcall(tostring, value)
		table.insert(subject.Facts, { Id = "type", Text = "Type", Value = kind })
		table.insert(subject.Facts, { Id = "value", Text = "Value", Value = if ok then text else "?" })
		table.insert(notes, "load a script, a ModuleScript, a function or a table to inspect it")
	end
	if subject.Count > 1 then
		table.insert(notes, 1, ("%d things are loaded; this shows the first"):format(subject.Count))
	end
	return subject
end

return Inspect
