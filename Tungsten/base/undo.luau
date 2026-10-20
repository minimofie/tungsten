--[[
	Tungsten · base/undo
	The list of actions /undo can take back (newest last). Tungsten records
	what it changes in the game and in your variables:

		property and attribute edits (the properties panel, its popups,
		/setprop), renames, moving objects (dragging, /move), inserting
		objects (Insert, /insert), and variable changes made by /set,
		/unset, /clearvars, /rename and the explorer's Variable menu.

	Deleting is recorded too: the explorer takes deleted objects out of
	the game (Parent = nil) instead of destroying them, so they can come
	back. Code you run with > or = isn't
	recorded: Tungsten can't know what it changed.

		Undo.record({
			Text = "set Transparency on Door",   -- what /undo says it undid
			Undo = function() ... end,            -- puts things back (errors are reported)
			Merge = "prop:Transparency:…",        -- optional, see groups
			CanUndo = false,                      -- optional: listed but can't be undone
			Owner = "myplugin",                   -- optional
		})
		Undo.undo()        -> ok, text      (the newest entry)
		Undo.list()        -> entries, newest first
		Undo.clear() ; Undo.removeOwner(owner)
		Undo.Changed       signal

	Groups: while Undo.beginGroup(key) is open, entries recorded with
	Merge == key fold into one (the first one's Undo is kept), so dragging
	in a color picker becomes a single step. Undo.endGroup(key) closes it.
	Undo.quiet(fn) runs fn without recording (undo itself uses it).
]]

local T = ...
local signal = T.import("base/signal")

local Undo = {}
Undo.MaxSteps = 100
Undo.Changed = signal.new()

local stack: { any } = {}
local openGroups: { [string]: boolean } = {}
local quietDepth = 0

function Undo.record(entry: { [string]: any })
	assert(type(entry) == "table" and type(entry.Text) == "string", "an undo entry needs Text")
	assert(entry.CanUndo == false or type(entry.Undo) == "function", "an undo entry needs Undo()")
	if quietDepth > 0 then
		return nil
	end
	local top = stack[#stack]
	if entry.Merge and top and top.Merge == entry.Merge and openGroups[entry.Merge] then
		-- same group: keep the oldest way back, show the newest text
		top.Text = entry.Text
		top.Time = os.clock()
		Undo.Changed:Fire()
		return top
	end
	local stored = {
		Text = entry.Text,
		Undo = entry.Undo,
		Merge = entry.Merge,
		CanUndo = entry.CanUndo ~= false,
		Owner = entry.Owner or "core",
		Time = os.clock(),
	}
	table.insert(stack, stored)
	while #stack > Undo.MaxSteps do
		table.remove(stack, 1)
	end
	Undo.Changed:Fire()
	return stored
end

function Undo.beginGroup(key: string)
	openGroups[key] = true
end

function Undo.endGroup(key: string)
	openGroups[key] = nil
end

function Undo.quiet(fn: () -> ...any): ...any
	quietDepth += 1
	local results = table.pack(pcall(fn))
	quietDepth -= 1
	if not results[1] then
		error(results[2], 0)
	end
	return table.unpack(results, 2, results.n)
end

function Undo.isRecording(): boolean
	return quietDepth == 0
end

-- Takes back the newest entry. Returns ok, text (or the reason it couldn't).
function Undo.undo(): (boolean, string?)
	local entry = table.remove(stack)
	if not entry then
		return false, "nothing to undo"
	end
	if entry.Merge then
		openGroups[entry.Merge] = nil
	end
	Undo.Changed:Fire()
	if not entry.CanUndo then
		return false, ("%s can't be undone"):format(entry.Text)
	end
	local ok, err = pcall(Undo.quiet, entry.Undo)
	if not ok then
		return false, ("couldn't undo %s: %s"):format(entry.Text, (tostring(err):gsub("^.-:%d+: ", "")))
	end
	return true, entry.Text
end

function Undo.peek()
	return stack[#stack]
end

function Undo.count(): number
	return #stack
end

-- Entries, newest first (copies).
function Undo.list(): { any }
	local out = {}
	for index = #stack, 1, -1 do
		local entry = stack[index]
		table.insert(out, { Text = entry.Text, CanUndo = entry.CanUndo, Owner = entry.Owner, Time = entry.Time })
	end
	return out
end

function Undo.clear()
	table.clear(stack)
	table.clear(openGroups)
	Undo.Changed:Fire()
end

function Undo.removeOwner(owner: string): number
	local count = 0
	for index = #stack, 1, -1 do
		if stack[index].Owner == owner then
			table.remove(stack, index)
			count += 1
		end
	end
	if count > 0 then
		Undo.Changed:Fire()
	end
	return count
end

----------------------------------------------------------------------
-- Helpers for common kinds of change
----------------------------------------------------------------------

local function nameOf(obj: Instance): string
	local ok, name = pcall(function()
		return obj.Name
	end)
	return if ok then tostring(name) else "?"
end

-- "Door" or "3 objects"
function Undo.describe(instances: { Instance }): string
	if #instances == 1 then
		return nameOf(instances[1])
	end
	return ("%d objects"):format(#instances)
end

-- Remembers variables (by name); returns a function that puts them back
-- the way they were (set again, or removed if they didn't exist).
function Undo.rememberVariables(names: { string }): () -> ()
	local Variables = T.import("base/variables")
	local saved = {}
	for _, name in names do
		local value, exists = Variables.get(name)
		saved[name] = if exists then { Value = value, Source = Variables.source(name) } else false
	end
	return function()
		for name, entry in saved do
			if entry then
				-- Undo acts for you, and gives the variable back to whoever had
				-- it; a plugin that is gone can't have it back, so it is yours.
				local owner = entry.Source or "console"
				if not Variables.isUser(owner) and not T.import("base/api").get(owner) then
					owner = "console"
					local Console = T.Console
					if Console and Console.detail then
						pcall(Console.detail, ("$%s came back as yours (%s isn't running)"):format(name, entry.Source))
					end
				end
				Variables.set(name, entry.Value, { Source = "console", Owner = owner })
			elseif Variables.has(name) then
				Variables.unset(name)
			end
		end
	end
end

T.Bin:Add(function()
	table.clear(stack)
	table.clear(openGroups)
	Undo.Changed:DisconnectAll()
end)

return Undo
