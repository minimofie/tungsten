--[[
	Tungsten · console/commands
	The console's command registry.

		Commands.register({
			Name = "scale",
			Aliases = { "zoom" },              -- optional
			Group = "Window",                  -- heading in /help
			Usage = "/scale [value | + | -]",
			Description = "show or change the window scale",
			Owner = "core",                    -- plugins pass their id
			Run = function(ctx) ... end,       -- may return a value for $last
			Complete = function(ctx, argIndex, partial) return { "+", "-" } end,
		})

	Core commands run as /name. A plugin's commands run as :plugin.name,
	and also as /name when no core command has that name.

	Command files: every .luau file in console/commands/ returns a list of
	definitions and is loaded at start-up, so dropping a file there adds
	commands.
]]

local T = ...
local signal = T.import("base/signal")

local DIR = T.Root .. "/console/commands"
local BUILTIN_FILES = { "core", "variables", "errors", "tools", "explorer", "session", "plugins" } -- loaded first, in this order

local Commands = {}
Commands.Added = signal.new() -- (command)
Commands.Removed = signal.new() -- (command)

local byKey: { [string]: any } = {} -- "owner\0name" -> command
local aliases: { [string]: any } = {} -- "owner\0alias" -> command

local function key(owner: string, name: string): string
	return owner .. "\0" .. name:lower()
end

function Commands.register(definition)
	assert(type(definition) == "table", "command definition must be a table")
	local name = definition.Name
	assert(type(name) == "string" and name:match("^[%a_][%w_%-]*$"), "command needs a Name of letters, digits, _ or -")
	assert(type(definition.Run) == "function", ("command '%s' needs a Run function"):format(name))
	local owner = definition.Owner or "core"
	assert(type(owner) == "string" and owner:match("^[%a_][%w_%-]*$"), "command Owner must be a plain id")

	local command = {
		Name = name:lower(),
		Aliases = {},
		Group = definition.Group or (if owner == "core" then "Console" else owner),
		Usage = definition.Usage or ("/" .. name:lower()),
		Description = definition.Description or "",
		Owner = owner,
		Run = definition.Run,
		Complete = definition.Complete,
		Hidden = definition.Hidden == true,
	}
	local k = key(owner, command.Name)
	if byKey[k] then
		error(("command '%s' already exists for %s"):format(command.Name, owner), 2)
	end
	byKey[k] = command
	for _, alias in definition.Aliases or {} do
		alias = tostring(alias):lower()
		table.insert(command.Aliases, alias)
		aliases[key(owner, alias)] = command
	end
	Commands.Added:Fire(command)
	return command
end

function Commands.unregister(owner: string, name: string): boolean
	local k = key(owner, name)
	local command = byKey[k]
	if not command then
		return false
	end
	byKey[k] = nil
	for _, alias in command.Aliases do
		aliases[key(owner, alias)] = nil
	end
	Commands.Removed:Fire(command)
	return true
end

-- All commands of one owner (a plugin being disabled).
function Commands.unregisterOwner(owner: string): number
	local removed = 0
	for _, command in Commands.list() do
		if command.Owner == owner then
			Commands.unregister(owner, command.Name)
			removed += 1
		end
	end
	return removed
end

function Commands.get(owner: string, name: string)
	local k = key(owner, name)
	return byKey[k] or aliases[k]
end

-- "/name": core first, then a plugin command when only one plugin has it.
function Commands.resolve(name: string)
	local command = Commands.get("core", name)
	if command then
		return command, nil
	end
	local found = {}
	for _, other in Commands.list() do
		if other.Owner ~= "core" and (other.Name == name:lower() or table.find(other.Aliases, name:lower())) then
			table.insert(found, other)
		end
	end
	if #found == 1 then
		return found[1], nil
	elseif #found > 1 then
		return nil, "ambiguous"
	end
	return nil, nil
end

-- Sorted by group (Console first), then name.
function Commands.list(): { any }
	local list = {}
	for _, command in byKey do
		table.insert(list, command)
	end
	table.sort(list, function(a, b)
		if a.Owner ~= b.Owner then
			if a.Owner == "core" or b.Owner == "core" then
				return a.Owner == "core"
			end
			return a.Owner < b.Owner
		end
		if a.Group ~= b.Group then
			return a.Group < b.Group
		end
		return a.Name < b.Name
	end)
	return list
end

-- Text a user types to run the command.
function Commands.invocation(command): string
	if command.Owner == "core" then
		return "/" .. command.Name
	end
	return ":" .. command.Owner .. "." .. command.Name
end

----------------------------------------------------------------------
-- Loading command files
----------------------------------------------------------------------

local function loadFile(name: string)
	local ok, result = pcall(T.import, "console/commands/" .. name)
	if not ok then
		T.Log.error("commands", ("could not load console/commands/%s: %s"):format(name, tostring(result)))
		return 0
	end
	if type(result) ~= "table" then
		T.Log.warn("commands", ("console/commands/%s returned no command list"):format(name))
		return 0
	end
	local count = 0
	for _, definition in result do
		local okRegister, err = pcall(Commands.register, definition)
		if okRegister then
			count += 1
		else
			T.Log.error("commands", ("console/commands/%s: %s"):format(name, tostring(err)))
		end
	end
	return count
end

function Commands.loadAll(): number
	local names = table.clone(BUILTIN_FILES)
	local ok, entries = pcall(listfiles, DIR)
	if ok and type(entries) == "table" then
		local extra = {}
		for _, entry in entries do
			local file = tostring(entry):match("[^/\\]+$")
			local base = file and file:match("^(.+)%.luau$")
			if base and not table.find(names, base) then
				table.insert(extra, base)
			end
		end
		table.sort(extra)
		for _, base in extra do
			table.insert(names, base)
		end
	end
	local total = 0
	for _, name in names do
		total += loadFile(name)
	end
	T.Log.info("commands", ("%d commands loaded"):format(total))
	return total
end

T.Bin:Add(function()
	table.clear(byKey)
	table.clear(aliases)
	Commands.Added:DisconnectAll()
	Commands.Removed:DisconnectAll()
end)

return Commands
