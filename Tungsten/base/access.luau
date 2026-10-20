--[[
	Tungsten · base/access
	How a value inside a script is reached: from a ModuleScript's returned
	value (require), or a running script's globals (getsenv), then keys
	and upvalues. The path bar shows it as crumbs, Copy gives it as code:

		require(game.ReplicatedStorage.Combat).Weapons.Sword.swing
		getsenv(game.Players.LocalPlayer.PlayerScripts.Main).update
		debug.getupvalues(require(game.ReplicatedStorage.Util).tick)[2]

	An access is a table:
		{ Root = "require" | "getsenv", Script = Instance,
		  Steps = { { Kind = "key", Key = k } | { Kind = "upvalue", Index = n } } }

		Access.root(script)             -> an access with no steps (nil if not a script)
		Access.extend(access, step)     -> a new access one step further
		Access.key(access, key)         -> extend by a key (nil if the key can't be written)
		Access.upvalue(access, index)   -> extend by an upvalue
		Access.code(access)             -> the code text
		Access.crumbs(access)           -> { { Text, Step? } } root first
		Access.resolve(access, upTo?)   -> ok, value | why   (upTo: steps to walk)
		Access.parse(text)              -> access | nil, why  (never runs the text)
		Access.find(value)              -> access | nil       (searched, cached)
		Access.findFrom(access, value)  -> access | nil       (searched from a known place)
		Access.is(x)                    -> boolean

	Nothing here requires a ModuleScript the game hasn't required: require
	is only used on modules getloadedmodules lists (they return what the
	game already got). Text is only walked: paths with Types.resolvePath,
	keys and upvalue numbers read as literals.
]]

local T = ...
local Types = T.import("base/types")

local Access = {}

Access.MaxDepth = 5 -- keys deep a search goes
Access.Budget = 20000 -- entries a search may look at
Access.CacheTime = 10 -- seconds a "not found" is remembered

local ACCESS = {} -- metatable marking accesses
ACCESS.__index = ACCESS

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

local function call(name: string, ...: any): (boolean, any)
	local fn = volt(name)
	if not fn then
		return false, name .. " is missing"
	end
	return pcall(fn, ...)
end

function Access.is(x: any): boolean
	return type(x) == "table" and getmetatable(x) == ACCESS
end

local function make(root: string, script: Instance, steps: { any })
	return table.freeze(setmetatable({ Root = root, Script = script, Steps = table.freeze(steps) }, ACCESS))
end

local function isA(obj: any, className: string): boolean
	local ok, yes = pcall(function()
		return obj:IsA(className)
	end)
	return ok and yes == true
end

-- A script's root: require for a ModuleScript, getsenv for the others.
function Access.root(script: any)
	if typeof(script) ~= "Instance" then
		return nil
	end
	if isA(script, "ModuleScript") then
		return make("require", script, {})
	elseif isA(script, "LocalScript") or isA(script, "Script") then
		return make("getsenv", script, {})
	end
	return nil
end

local function writableKey(key: any): boolean
	local kind = type(key)
	if kind == "string" then
		return true
	elseif kind == "number" then
		return key == key and key ~= math.huge and key ~= -math.huge
	end
	return kind == "boolean"
end

function Access.extend(access, step)
	assert(Access.is(access), "not an access")
	local steps = table.clone(access.Steps)
	table.insert(steps, table.freeze(table.clone(step)))
	return make(access.Root, access.Script, steps)
end

function Access.key(access, key: any)
	if not Access.is(access) or not writableKey(key) then
		return nil
	end
	return Access.extend(access, { Kind = "key", Key = key })
end

function Access.upvalue(access, index: number)
	if not Access.is(access) or type(index) ~= "number" then
		return nil
	end
	return Access.extend(access, { Kind = "upvalue", Index = index })
end

----------------------------------------------------------------------
-- Text
----------------------------------------------------------------------

local function keyCode(key: any): string
	if type(key) == "string" then
		if key:match("^[%a_][%w_]*$") then
			return "." .. key
		end
		return "[" .. Types.literal(key) .. "]"
	elseif type(key) == "number" then
		return ("[%s]"):format(if key == math.floor(key) and math.abs(key) < 2 ^ 53 then ("%d"):format(key) else ("%.17g"):format(key))
	end
	return "[" .. tostring(key) .. "]"
end

local function stepText(step): string
	if step.Kind == "upvalue" then
		return "upvalue " .. tostring(step.Index)
	end
	local key = step.Key
	if type(key) == "string" then
		return key
	end
	return "[" .. tostring(key) .. "]"
end
Access.stepText = stepText

function Access.code(access): string
	local code = ("%s(%s)"):format(access.Root, Types.path(access.Script))
	for _, step in access.Steps do
		if step.Kind == "upvalue" then
			code = ("debug.getupvalues(%s)[%d]"):format(code, step.Index)
		else
			code ..= keyCode(step.Key)
		end
	end
	return code
end

function Access.crumbs(access): { any }
	local out = { { Text = access.Root .. "()", Depth = 0 } }
	for index, step in access.Steps do
		table.insert(out, { Text = stepText(step), Step = step, Depth = index })
	end
	return out
end

-- The access with only its first n steps.
function Access.prefix(access, n: number)
	local steps = {}
	for index = 1, math.min(n, #access.Steps) do
		steps[index] = access.Steps[index]
	end
	return make(access.Root, access.Script, steps)
end

----------------------------------------------------------------------
-- Walking
----------------------------------------------------------------------

local function listed(list: any, item: any): boolean
	if type(list) ~= "table" then
		return false
	end
	for _, x in list do
		if rawequal(x, item) then
			return true
		end
	end
	return false
end

-- The root value: a required module's value, or a script's globals.
local function rootValue(access): (boolean, any)
	local script = access.Script
	if access.Root == "require" then
		local okList, modules = call("getloadedmodules")
		if not okList then
			return false, "getloadedmodules failed: " .. tostring(modules)
		end
		if not listed(modules, script) then
			return false, ("%s hasn't been required by the game (requiring it would run it)"):format(Types.path(script))
		end
		local ok, value = pcall(require, script)
		if not ok then
			return false, "require failed: " .. tostring(value)
		end
		return true, value
	end
	local ok, env = call("getsenv", script)
	if not ok then
		return false, "getsenv failed: " .. tostring(env)
	end
	if type(env) ~= "table" then
		return false, ("%s isn't running (getsenv has no environment for it)"):format(Types.path(script))
	end
	return true, env
end

function Access.resolve(access, upTo: number?): (boolean, any)
	if not Access.is(access) then
		return false, "not an access"
	end
	local ok, value = rootValue(access)
	if not ok then
		return false, value
	end
	local last = math.min(upTo or #access.Steps, #access.Steps)
	for index = 1, last do
		local step = access.Steps[index]
		if step.Kind == "upvalue" then
			if type(value) ~= "function" then
				return false, ("%s isn't a function (it has no upvalues)"):format(stepText(access.Steps[index - 1] or { Kind = "key", Key = access.Root .. "()" }))
			end
			local okUp, upvalues = call("debug.getupvalues", value)
			if not okUp or type(upvalues) ~= "table" then
				return false, "debug.getupvalues failed: " .. tostring(upvalues)
			end
			value = upvalues[step.Index]
		else
			if type(value) ~= "table" then
				return false, ("can't index a %s with %s"):format(typeof(value), stepText(step))
			end
			value = rawget(value, step.Key)
		end
		if value == nil and index < last then
			return false, stepText(step) .. " is nil"
		end
	end
	return true, value
end

----------------------------------------------------------------------
-- Parsing (never runs the text)
----------------------------------------------------------------------

-- Index of the ")" closing the "(" at open, skipping quoted text.
local function closing(text: string, open: number): number?
	local depth, i, quote = 0, open, nil
	while i <= #text do
		local c = text:sub(i, i)
		if quote then
			if c == "\\" then
				i += 1
			elseif c == quote then
				quote = nil
			end
		elseif c == "\"" or c == "'" then
			quote = c
		elseif c == "(" then
			depth += 1
		elseif c == ")" then
			depth -= 1
			if depth == 0 then
				return i
			end
		end
		i += 1
	end
	return nil
end

local ESCAPES = { n = "\n", t = "\t", r = "\r", ["\\"] = "\\", ["\""] = "\"", ["'"] = "'", ["0"] = "\0" }

-- The text inside quotes, its escapes read (\n \t \" \\ \ddd).
local function unquote(inner: string): string
	return (inner:gsub("\\(%d%d?%d?)", function(digits)
		return string.char(math.clamp(tonumber(digits) :: number, 0, 255))
	end):gsub("\\(.)", function(c)
		return ESCAPES[c] or c
	end))
end

-- Reads key steps: .name ["text"] ['text'] [number] [true]
local function readSteps(rest: string, steps: { any }): (boolean, string?)
	local position = 1
	while position <= #rest do
		local spaces = rest:match("^%s+", position)
		if spaces then
			position += #spaces
			continue
		end
		local name, after = rest:match("^%.%s*([%a_][%w_]*)()", position)
		if name then
			table.insert(steps, { Kind = "key", Key = name })
			position = after
			continue
		end
		local inside = rest:match("^%[(.-)%]", position)
		if inside == nil then
			return false, ("can't read %q (keys are .name or [\"text\"] or [number])"):format(rest:sub(position))
		end
		local trimmed = inside:match("^%s*(.-)%s*$")
		local key
		local q = trimmed:sub(1, 1)
		if (q == "\"" or q == "'") and trimmed:sub(-1) == q and #trimmed >= 2 then
			key = unquote(trimmed:sub(2, -2))
		elseif trimmed == "true" or trimmed == "false" then
			key = trimmed == "true"
		else
			key = tonumber(trimmed)
			if key == nil then
				return false, ("[%s] isn't a key (text in quotes, a number or true / false)"):format(inside)
			end
		end
		table.insert(steps, { Kind = "key", Key = key })
		position += #inside + 2
	end
	return true, nil
end

function Access.parse(text: string)
	local source = (tostring(text or "")):match("^%s*(.-)%s*$")
	local head = source:match("^([%a_][%w_%.]*)%s*%(")
	if head == "debug.getupvalues" then
		local open = (source:find("(", 1, true) :: number)
		local close = closing(source, open)
		if not close then
			return nil, "a ( isn't closed"
		end
		local inner, why = Access.parse(source:sub(open + 1, close - 1))
		if not inner then
			return nil, why
		end
		local index, rest = source:sub(close + 1):match("^%s*%[%s*(%d+)%s*%](.*)$")
		if not index then
			return nil, "debug.getupvalues(...) needs an upvalue number: [1]"
		end
		local steps = table.clone(inner.Steps)
		table.insert(steps, { Kind = "upvalue", Index = tonumber(index) })
		local ok, why2 = readSteps(rest, steps)
		if not ok then
			return nil, why2
		end
		return make(inner.Root, inner.Script, steps)
	end
	if head ~= "require" and head ~= "getsenv" then
		return nil, "not a require(...) or getsenv(...) path"
	end
	local open = (source:find("(", 1, true) :: number)
	local close = closing(source, open)
	if not close then
		return nil, "a ( isn't closed"
	end
	local script, reason = Types.resolvePath(source:sub(open + 1, close - 1))
	if not script then
		return nil, reason or "not a path"
	end
	local root = Access.root(script)
	if not root then
		return nil, ("%s isn't a script"):format(Types.path(script))
	end
	if head == "require" and root.Root ~= "require" then
		return nil, "require takes a ModuleScript; use getsenv(...) for a script"
	elseif head == "getsenv" and root.Root ~= "getsenv" then
		return nil, "getsenv takes a script; use require(...) for a ModuleScript"
	end
	local steps = {}
	local ok, why = readSteps(source:sub(close + 1), steps)
	if not ok then
		return nil, why
	end
	return make(root.Root, root.Script, steps)
end

----------------------------------------------------------------------
-- Finding (breadth first, raw reads, a budget)
----------------------------------------------------------------------

local found = setmetatable({}, { __mode = "k" }) -- value -> access
local missed = setmetatable({}, { __mode = "k" }) -- value -> os.clock() of the miss

-- Breadth-first from a root value: the shortest key path to value.
local function search(access, rootVal: any, value: any, budget: { n: number }): any
	if rawequal(rootVal, value) then
		return access
	end
	if type(rootVal) ~= "table" then
		return nil
	end
	local seen = { [rootVal] = true }
	local queue = { { Table = rootVal, Access = access, Depth = 0 } }
	local head = 1
	while head <= #queue do
		local entry = queue[head]
		head += 1
		for key, child in next, entry.Table do
			budget.n -= 1
			if budget.n <= 0 then
				return nil
			end
			if rawequal(child, value) then
				return Access.key(entry.Access, key)
			end
			if type(child) == "table" and not seen[child] and entry.Depth + 1 < Access.MaxDepth and writableKey(key) then
				seen[child] = true
				local nextAccess = Access.key(entry.Access, key)
				if nextAccess then
					table.insert(queue, { Table = child, Access = nextAccess, Depth = entry.Depth + 1 })
				end
			end
		end
	end
	return nil
end

local function byName(list: { any }): { any }
	local named = {}
	for _, script in list do
		local ok, name = pcall(function()
			return script:GetFullName()
		end)
		table.insert(named, { Script = script, Name = if ok then name else "" })
	end
	table.sort(named, function(a, b)
		return a.Name < b.Name
	end)
	local out = {}
	for index, entry in named do
		out[index] = entry.Script
	end
	return out
end

-- Where a function or table is reached from: required modules first, then
-- running scripts' globals. The shortest path wins; results are cached.
function Access.find(value: any)
	local kind = type(value)
	if kind ~= "function" and kind ~= "table" then
		return nil
	end
	local cached = found[value]
	if cached then
		local ok, now = Access.resolve(cached)
		if ok and rawequal(now, value) then
			return cached
		end
		found[value] = nil
	end
	local miss = missed[value]
	if miss and os.clock() - miss < Access.CacheTime then
		return nil
	end
	local budget = { n = Access.Budget }
	local best = nil
	local roots = {}
	local okModules, modules = call("getloadedmodules")
	if okModules and type(modules) == "table" then
		for _, module in byName(modules) do
			table.insert(roots, module)
		end
	end
	local okRunning, running = call("getrunningscripts")
	if okRunning and type(running) == "table" then
		for _, script in byName(running) do
			if not isA(script, "ModuleScript") then
				table.insert(roots, script)
			end
		end
	end
	for _, script in roots do
		local root = Access.root(script)
		if root then
			local okRoot, rootVal = rootValue(root)
			if okRoot then
				local hit = search(root, rootVal, value, budget)
				if hit and (best == nil or #hit.Steps < #best.Steps) then
					best = hit
					if #best.Steps <= 1 then
						break
					end
				end
			end
		end
		if budget.n <= 0 then
			break
		end
	end
	if best then
		found[value] = best
		missed[value] = nil
	else
		missed[value] = os.clock()
	end
	return best
end

-- From a known place (the script viewer's loaded table): where value is
-- inside it.
function Access.findFrom(access, value: any)
	if not Access.is(access) then
		return nil
	end
	local ok, rootVal = Access.resolve(access)
	if not ok then
		return nil
	end
	return search(access, rootVal, value, { n = Access.Budget })
end

-- Forgets what was found (tests; a rejoin).
function Access.forget()
	table.clear(found)
	table.clear(missed)
end

return Access
