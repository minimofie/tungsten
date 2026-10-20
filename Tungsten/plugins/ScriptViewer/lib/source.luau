--[[
	Script Viewer · lib/source
	Decompiled source for the Source sub-tab. decompile (Volt) yields until
	it finishes and errors when it can't, so it runs in a thread of its
	own; each script is decompiled once per session (kept by its hash, so
	a changed script is decompiled again).

		Source.scriptFor(subject) -> Instance?, note?   the script whose source to show
		Source.get(script) -> ok, text      -- yields; cached
		Source.cached(script) -> text?      -- without decompiling
		Source.forget()                     -- clears the cache
]]

local P = ...

local Inspect = P.import("lib/inspect")
local call = Inspect.call

local Source = {}

local cache = setmetatable({}, { __mode = "k" }) -- script -> { Hash, Text }

local function hashOf(script: Instance): string?
	local ok, hash = call("getscripthash", script)
	return if ok and type(hash) == "string" then hash else nil
end

-- The script a subject's source comes from, and a note saying how.
function Source.scriptFor(subject): (Instance?, string?)
	if subject == nil or subject.Kind == "none" then
		return nil, "nothing loaded"
	end
	if subject.Kind == "script" or subject.Kind == "module" then
		return subject.Instance, nil
	end
	local item = subject.Item
	local origin = if type(item) == "table" and typeof(item.Origin) == "Instance" then item.Origin else nil
	if origin == nil and subject.Kind == "proto" and subject.Proto and type(subject.Proto.ScriptSubject) == "table" then
		origin = subject.Proto.ScriptSubject.Instance -- a nested function of a script's bytecode
	end
	if subject.Kind == "function" or subject.Kind == "proto" then
		if origin then
			local note = if subject.Kind == "proto" then "the script this nested function came from" else "the script this function came from"
			local line = nil
			pcall(function()
				local defined = debug.info(subject.Fn, "l")
				if type(defined) == "number" and defined > 0 then
					line = defined
				end
			end)
			if line then
				note ..= (" · it is defined at line %d"):format(line)
			end
			return origin, note
		end
		return nil, "a function on its own has no source to decompile · load the script it is in"
	end
	if subject.Kind == "table" then
		return nil, "a table has no source · its entries are in the Contents sub-tab"
	end
	return nil, "only scripts and ModuleScripts have source"
end

function Source.cached(script: Instance): string?
	local entry = cache[script]
	if entry and entry.Hash == hashOf(script) then
		return entry.Text
	end
	return nil
end

-- Decompiles (yields). ok, text or ok = false, why.
function Source.get(script: Instance): (boolean, string)
	local known = Source.cached(script)
	if known then
		return true, known
	end
	local ok, text = call("decompile", script)
	if not ok then
		return false, "decompile failed: " .. tostring(text)
	end
	if type(text) ~= "string" then
		return false, "decompile gave no text"
	end
	cache[script] = { Hash = hashOf(script), Text = text }
	return true, text
end

function Source.forget()
	table.clear(cache)
end

return Source
