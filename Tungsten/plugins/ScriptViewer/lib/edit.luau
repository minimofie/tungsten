--[[
	Script Viewer · lib/edit
	Changing what the viewer shows, in the game's memory (nothing is
	written to a script's source, nothing replicates, a rejoin resets it).

		Edit.kindOf(node)            -> "constant" | "upvalue" | "entry" | nil
		Edit.write(node, value, opts) -> ok, why, undo    -- one value
		Edit.remove(node, opts)       -> ok, why, undo    -- an entry or upvalue to nil
		Edit.add(t, key, value, opts) -> ok, why, undo    -- a new entry in a table
		Edit.rename(node, newKey, opts) -> ok, why, undo  -- move an entry to another key
		Edit.applyText(kind, target, text, opts) -> ok, why, count, undo
			kind "constants" | "upvalues" | "contents"; the Table view's text,
			read back (KEEP keeps a value as it is) and only differences written
		Edit.readOnly(t) -> boolean
	opts.Unlock = true: a read-only table may be made writable for the write
	and read-only again after (asked for first: Q10). opts.AnyType = true: a
	constant may change type (Volt's caution: the bytecode may expect it).

	undo() puts the old value(s) back the same way. Volt functions:
	debug.setconstant (1-based; function or ProtoProxy), debug.setupvalue,
	isreadonly / setreadonly, getfunctionhash, filtergc.

	A script's or ModuleScript's constants are read from a copy compiled
	again from its bytecode (getscriptclosure: "not the closure currently
	running"). opts.Subject set: a constant of that copy is written to the
	script's running functions that are the same function (same constants,
	and the same getfunctionhash for a function), and to the copy so the
	view shows it. None running: nothing is written (it would change
	nothing in the game).
]]

local P = ...

local Inspect = P.import("lib/inspect")
local Serialize = P.import("lib/serialize")
local Rows = P.import("lib/rows")
local call = Inspect.call

local Edit = {}

local CONSTANT_TYPES = { string = true, number = true, boolean = true, vector = true }

function Edit.kindOf(node): string?
	if type(node) ~= "table" then
		return nil
	end
	if node.Kind == "constant" and node.Owner ~= nil and type(node.Index) == "number" then
		return "constant"
	elseif node.Kind == "upvalue" and node.Owner ~= nil and node.Index ~= nil then
		return "upvalue"
	elseif node.Kind == "entry" and type(node.Parent) == "table" then
		return "entry"
	end
	return nil
end

function Edit.readOnly(t: any): boolean
	if type(t) ~= "table" then
		return false
	end
	if table.isfrozen(t) then
		return true
	end
	local ok, yes = call("isreadonly", t)
	return ok and yes == true
end

-- Writes t[key] = value, unlocking a read-only table when allowed.
local function setEntry(t: { [any]: any }, key: any, value: any, opts): (boolean, string?)
	if key == nil or key ~= key then
		return false, "that key can't be used"
	end
	local locked = Edit.readOnly(t)
	if locked and not (opts and opts.Unlock) then
		return false, "read-only"
	end
	if locked then
		local okUnlock, err = call("setreadonly", t, false)
		if not okUnlock or Edit.readOnly(t) then
			return false, "the table couldn't be made writable" .. (if not okUnlock then ": " .. tostring(err) else " (it is frozen)")
		end
	end
	local ok, err = pcall(rawset, t, key, value)
	if locked then
		call("setreadonly", t, true) -- read-only again, as it was
	end
	if not ok then
		return false, "the write failed: " .. tostring(err)
	end
	return true, nil
end
Edit.setEntry = setEntry

local function setConstant(owner: any, index: number, value: any): (boolean, string?)
	local ok, err = call("debug.setconstant", owner, index, value)
	if not ok then
		return false, "debug.setconstant failed: " .. tostring(err)
	end
	return true, nil
end

local function setUpvalue(owner: any, index: any, value: any): (boolean, string?)
	local ok, err = call("debug.setupvalue", owner, index, value)
	if not ok then
		return false, "debug.setupvalue failed: " .. tostring(err)
	end
	return true, nil
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

local function hashOf(fn: any): string?
	if type(fn) ~= "function" then
		return nil
	end
	local ok, hash = call("getfunctionhash", fn)
	return if ok and type(hash) == "string" then hash else nil
end

-- What a constant write goes to: the owner itself, or (for a script's
-- compiled copy) the running functions that are that function.
-- -> { targets } | nil, why
function Edit.constantTargets(owner: any, subject: any): ({ any }?, string?)
	if type(subject) ~= "table" or (subject.Kind ~= "script" and subject.Kind ~= "module") then
		return { owner }, nil
	end
	local live, why = Rows.liveFunctions(subject)
	if live then
		for _, fn in live do
			if rawequal(fn, owner) then
				return { owner }, nil -- already a running function
			end
		end
	end
	local what = if subject.Kind == "module" then "ModuleScript" else "script"
	if not live then
		return nil, ("this is the %s's bytecode, not running code, and %s: changing it would change nothing in the game"):format(what, tostring(why))
	end
	local ownerHash = hashOf(owner)
	local twins, hashes, distinct = {}, {}, 0
	for _, fn in live do
		local fnHash = hashOf(fn)
		if (ownerHash == nil or fnHash == ownerHash) and sameConstants(owner, fn) then
			table.insert(twins, fn)
			local key = fnHash or tostring(fn)
			if not hashes[key] then
				hashes[key] = true
				distinct += 1
			end
		end
	end
	if #twins == 0 then
		return nil, ("none of the %s's running functions is this one (a main chunk runs once and is gone): changing it would change nothing in the game. Its running functions are under Upvalues; right-click one › Inspect"):format(what)
	end
	if ownerHash == nil and distinct > 1 then
		return nil, ("%d running functions of the %s look the same; right-click the one you mean under Upvalues › Inspect, and change it there"):format(distinct, what)
	end
	table.insert(twins, owner) -- the copy too, so the view shows the change
	return twins, nil
end

-- Writes a constant to every target, all or none.
local function setConstantAll(targets: { any }, index: number, value: any): (boolean, string?, (() -> ())?)
	local olds = {}
	for i, target in targets do
		local okRead, current = call("debug.getconstants", target)
		olds[i] = if okRead and type(current) == "table" then current[index] else nil
		local ok, err = setConstant(target, index, value)
		if not ok then
			for back = i - 1, 1, -1 do
				setConstant(targets[back], index, olds[back])
			end
			return false, err, nil
		end
	end
	return true, nil, function()
		for i = #targets, 1, -1 do
			setConstant(targets[i], index, olds[i])
		end
	end
end
Edit.setConstantAll = setConstantAll

-- Can this constant take a value of that type?
function Edit.constantAllows(node, value: any, opts): (boolean, string?)
	local kind = typeof(value)
	if value == nil then
		return false, "a constant can't be set to nil"
	end
	if not CONSTANT_TYPES[kind] then
		return false, ("a constant can only be a string, number, boolean or vector, not %s"):format(kind)
	end
	if not (opts and opts.AnyType) and node.Value ~= nil and typeof(node.Value) ~= kind then
		return false, ("this constant is a %s; changing its type is off (Plugins › Script Viewer › Constants may change type)"):format(typeof(node.Value))
	end
	return true, nil
end

function Edit.write(node, value: any, opts): (boolean, string?, (() -> ())?)
	local kind = Edit.kindOf(node)
	if not kind then
		return false, "only constants, upvalues and table entries can be changed", nil
	end
	local old = node.Value
	if kind == "constant" then
		local allowed, why = Edit.constantAllows(node, value, opts)
		if not allowed then
			return false, why, nil
		end
		local targets, whyNot = Edit.constantTargets(node.Owner, opts and opts.Subject)
		if not targets then
			return false, whyNot, nil
		end
		return setConstantAll(targets, node.Index, value)
	elseif kind == "upvalue" then
		if Inspect.isC(node.Owner) then
			return false, "a C function's upvalues can't be changed", nil
		end
		local ok, err = setUpvalue(node.Owner, node.Index, value)
		if not ok then
			return false, err, nil
		end
		return true, nil, function()
			setUpvalue(node.Owner, node.Index, old)
		end
	end
	local parent, key = node.Parent, node.RawKey
	local ok, err = setEntry(parent, key, value, opts)
	if not ok then
		return false, err, nil
	end
	return true, nil, function()
		setEntry(parent, key, old, { Unlock = true })
	end
end

function Edit.remove(node, opts): (boolean, string?, (() -> ())?)
	local kind = Edit.kindOf(node)
	if kind == "constant" then
		return false, "a constant can't be removed", nil
	elseif kind == nil then
		return false, "only upvalues and table entries can be set to nil", nil
	end
	return Edit.write(node, nil, opts)
end

function Edit.add(t: any, key: any, value: any, opts): (boolean, string?, (() -> ())?)
	if type(t) ~= "table" then
		return false, "entries are added to tables", nil
	end
	if key == nil then
		return false, "a new entry needs a key", nil
	end
	if rawget(t, key) ~= nil then
		return false, ("there is already an entry at %s"):format(tostring(key)), nil
	end
	local ok, err = setEntry(t, key, value, opts)
	if not ok then
		return false, err, nil
	end
	return true, nil, function()
		setEntry(t, key, nil, { Unlock = true })
	end
end

function Edit.rename(node, newKey: any, opts): (boolean, string?, (() -> ())?)
	if Edit.kindOf(node) ~= "entry" then
		return false, "only table entries have keys to rename", nil
	end
	local t, oldKey, value = node.Parent, node.RawKey, node.Value
	if newKey == nil then
		return false, "the new key is missing", nil
	end
	if rawequal(newKey, oldKey) then
		return false, "that is already its key", nil
	end
	if rawget(t, newKey) ~= nil then
		return false, ("there is already an entry at %s"):format(tostring(newKey)), nil
	end
	local ok, err = setEntry(t, newKey, value, opts)
	if not ok then
		return false, err, nil
	end
	setEntry(t, oldKey, nil, { Unlock = true })
	return true, nil, function()
		setEntry(t, oldKey, value, { Unlock = true })
		setEntry(t, newKey, nil, { Unlock = true })
	end
end

----------------------------------------------------------------------
-- The Table view's text, read back
----------------------------------------------------------------------

-- What the text may use: the values Serialize writes, nothing else (the
-- text runs in an empty environment: no game, no functions to call).
local function sandbox()
	return {
		KEEP = Serialize.KEEP,
		math = { huge = math.huge },
		Vector3 = { new = Vector3.new },
		Vector2 = { new = Vector2.new },
		Color3 = { new = Color3.new, fromRGB = Color3.fromRGB },
		UDim = { new = UDim.new },
		UDim2 = { new = UDim2.new, fromOffset = UDim2.fromOffset, fromScale = UDim2.fromScale },
		CFrame = { new = CFrame.new },
		BrickColor = { new = BrickColor.new },
		NumberRange = { new = NumberRange.new },
		Enum = Enum,
		vector = if vector then { create = vector.create } else nil,
	}
end

function Edit.parseText(text: string): (boolean, any)
	local chunk, err = loadstring("return " .. text, "=table")
	if not chunk then
		return false, tostring(err)
	end
	pcall(setfenv, chunk, sandbox())
	local ok, value = pcall(chunk)
	if not ok then
		return false, tostring(value)
	end
	if type(value) ~= "table" then
		return false, "the text must be one table"
	end
	return true, value
end

-- New tables typed in must not keep KEEP.
local function stripKeep(t: { [any]: any }, seen)
	if seen[t] then
		return t
	end
	seen[t] = true
	for key, value in next, t do
		if value == Serialize.KEEP then
			rawset(t, key, nil)
		elseif type(value) == "table" then
			stripKeep(value, seen)
		end
	end
	return t
end

local function isTextKey(key: any): boolean
	local kind = type(key)
	return kind == "string" or kind == "number" or kind == "boolean"
end

-- Every write that makes target match incoming (nested tables kept by
-- identity), as { Table, Key, Value }.
local function plan(target, incoming, changes, seen)
	if seen[target] then
		return
	end
	seen[target] = true
	for key in next, target do
		if isTextKey(key) and rawget(incoming, key) == nil then
			table.insert(changes, { Table = target, Key = key, Value = nil })
		end
	end
	for key, value in next, incoming do
		if value ~= Serialize.KEEP then
			local current = rawget(target, key)
			if type(value) == "table" and type(current) == "table" then
				plan(current, value, changes, seen)
			elseif current ~= value then
				if type(value) == "table" then
					value = stripKeep(value, {})
				end
				table.insert(changes, { Table = target, Key = key, Value = value })
			end
		end
	end
end
Edit.plan = plan

-- Writes planned table changes (all or none if a table can't be written).
local function applyPlan(changes, opts): (boolean, string?, (() -> ())?)
	for _, change in changes do
		if Edit.readOnly(change.Table) and not (opts and opts.Unlock) then
			return false, "read-only", nil
		end
	end
	local done = {}
	for _, change in changes do
		local old = rawget(change.Table, change.Key)
		local ok, err = setEntry(change.Table, change.Key, change.Value, opts)
		if not ok then
			for index = #done, 1, -1 do
				setEntry(done[index].Table, done[index].Key, done[index].Old, { Unlock = true })
			end
			return false, err, nil
		end
		table.insert(done, { Table = change.Table, Key = change.Key, Old = old })
	end
	return true, nil, function()
		for index = #done, 1, -1 do
			setEntry(done[index].Table, done[index].Key, done[index].Old, { Unlock = true })
		end
	end
end

-- Reads the Table view's text back and writes only what differs.
-- target: the function (constants / upvalues) or the table (contents).
function Edit.applyText(kind: string, target: any, text: string, opts): (boolean, string?, number, (() -> ())?)
	local ok, parsed = Edit.parseText(text)
	if not ok then
		return false, "the text isn't a Luau table: " .. tostring(parsed), 0, nil
	end
	if kind == "contents" then
		if type(target) ~= "table" then
			return false, "there is no table to write to", 0, nil
		end
		local changes = {}
		plan(target, parsed, changes, {})
		if #changes == 0 then
			return true, nil, 0, nil
		end
		local applied, why, undo = applyPlan(changes, opts)
		return applied, why, if applied then #changes else 0, undo
	end
	if kind ~= "constants" and kind ~= "upvalues" then
		return false, "this view can't be written back", 0, nil
	end
	local getter = if kind == "constants" then "debug.getconstants" else "debug.getupvalues"
	local okRead, current = call(getter, target)
	if not okRead or type(current) ~= "table" then
		return false, getter .. " didn't answer", 0, nil
	end
	-- what changes, checked before anything is written
	local writes, tableChanges = {}, {}
	for index, value in next, parsed do
		if value ~= Serialize.KEEP then
			local old = current[index]
			if type(index) ~= "number" then
				return false, ("%s are numbered: %s isn't a number"):format(kind, tostring(index)), 0, nil
			end
			if kind == "upvalues" and type(value) == "table" and type(old) == "table" then
				plan(old, value, tableChanges, {})
			elseif old ~= value then
				if kind == "constants" then
					local allowed, why = Edit.constantAllows({ Value = old }, value, opts)
					if not allowed then
						return false, ("constant %d: %s"):format(index, why), 0, nil
					end
				end
				table.insert(writes, { Index = index, Old = old, Value = if type(value) == "table" then stripKeep(value, {}) else value })
			end
		end
	end
	-- a script's constants go to its running functions (Edit.constantTargets)
	local targets = { target }
	if kind == "constants" and #writes > 0 then
		local found, whyNot = Edit.constantTargets(target, opts and opts.Subject)
		if not found then
			return false, whyNot, 0, nil
		end
		targets = found
	end
	local undos = {}
	local function rollback()
		for index = #undos, 1, -1 do
			undos[index]()
		end
	end
	for _, write in writes do
		local okWrite, err, undo
		if kind == "constants" then
			okWrite, err, undo = setConstantAll(targets, write.Index, write.Value)
		else
			okWrite, err = setUpvalue(target, write.Index, write.Value)
			local index, old = write.Index, write.Old
			undo = function()
				setUpvalue(target, index, old)
			end
		end
		if not okWrite then
			rollback()
			return false, err, 0, nil
		end
		table.insert(undos, undo)
	end
	if #tableChanges > 0 then
		local applied, why, undo = applyPlan(tableChanges, opts)
		if not applied then
			rollback()
			return false, why, 0, nil
		end
		table.insert(undos, undo)
	end
	local count = #writes + #tableChanges
	if count == 0 then
		return true, nil, 0, nil
	end
	return true, nil, count, rollback
end

-- Does any table a text apply would write to need unlocking?
function Edit.needsUnlock(kind: string, target: any, text: string): boolean
	local ok, parsed = Edit.parseText(text)
	if not ok then
		return false
	end
	local changes = {}
	if kind == "contents" and type(target) == "table" then
		plan(target, parsed, changes, {})
	elseif kind == "upvalues" then
		local okRead, current = call("debug.getupvalues", target)
		if okRead and type(current) == "table" then
			for index, value in next, parsed do
				if type(value) == "table" and type(current[index]) == "table" and value ~= Serialize.KEEP then
					plan(current[index], value, changes, {})
				end
			end
		end
	end
	for _, change in changes do
		if Edit.readOnly(change.Table) then
			return true
		end
	end
	return false
end

return Edit
