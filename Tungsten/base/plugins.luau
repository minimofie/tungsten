--[[
	Tungsten · base/plugins
	The plugin host. Every folder in Tungsten/plugins with a plugin.luau
	in it is a plugin (folders whose names start with _ are skipped, so a
	template can sit there). plugins/manager.luau is the Plugins tab, not
	a plugin.

	plugin.luau is loaded with loadfile and called with a context P:
		P.Folder   the folder's name          P.Path   "Tungsten/plugins/<Folder>"
		P.Version  Tungsten's version
		P.import("lib/util")  runs plugins/<Folder>/lib/util.luau once (it gets P too)
		P.read("data.txt")    readfile inside the folder
		P.file("icon.png")    the full path of a file in the folder
	and returns its definition (see base/api, Api.checkDefinition). Its top
	level only builds that table; the plugin's work starts in Load(api).

	States
		off      found and fine, not running
		on       running (its Load finished)
		failed   it was turned on but registering or Load threw (or Load
		         took longer than LoadTimeout); the error is kept
		problem  it can't run: plugin.luau doesn't compile or fails, a bad
		         definition, an id another folder already uses, a reserved
		         id, or a Requires it can't meet
	Turning a plugin on or off takes effect the next time Tungsten starts
	(Plugins.setWanted); new plugins start off. Which plugins are on is kept
	in Tungsten/base/plugins.json (Reset all settings doesn't touch it).

	Prime plugins
		scriptviewer, instanceviewer and scanner are the prime plugins (in
		that load order). Their ids are reserved (a folder only gets one
		with Prime = true), they load first, and they are the only plugins
		another plugin may list in Requires or Uses. Requires: it can't
		start without them. Uses: it starts anyway; links to them work while
		they are on. A plugin reaches what a prime plugin shares (its
		Exports) with api.plugins.get(id), and opens its tab at something
		with api.plugins.open(id, focus) (its Exports.reveal(focus)).

		Plugins.start()  ; Plugins.stop()       -- the loader calls these
		Plugins.list()   -> records in load order ; Plugins.get(id)
		Plugins.count()  -> plugins running
		Plugins.setWanted(id, on) ; Plugins.wanted(id) ; Plugins.pending(id)
		Plugins.reload(id)    -- read its files again and start it again if
		                      -- it was on or failed (for one that ran into a problem)
		Plugins.rescan()      -- pick up new folders without restarting
		Plugins.exportsFor(caller, id) ; Plugins.open(caller, id, focus)
		Plugins.Changed       -- (id or folder, record)
]]

local T = ...
local signal = T.import("base/signal")
local Api = T.import("base/api")
local DataStore = T.import("base/datastore")

local Plugins = {}
Plugins.Folder = T.Root .. "/plugins"
Plugins.Prime = { "scriptviewer", "instanceviewer", "scanner" }
Plugins.LoadTimeout = 5 -- seconds a Load may take before the plugin counts as failed
Plugins.DefaultOrder = 100
-- Ids no plugin may use: Tungsten's own, and its built-in tabs.
Plugins.Reserved = { core = true, tungsten = true, console = true, plugins = true, documentation = true }
Plugins.Changed = signal.new() -- (key, record)

local PRIME: { [string]: number } = {}
for index, id in Plugins.Prime do
	PRIME[id] = index
end

local store = DataStore.open(T.Root .. "/base/plugins.json", { Name = "plugins" })
local wanted: { [string]: boolean } = {} -- ids to start at the next start
local wantedAtStart: { [string]: boolean } = {} -- what was on when this run started
local records: { [string]: any } = {} -- id -> record (the folder that owns the id)
local ordered: { any } = {} -- every record (problems too), load order
local started = false
local faultConnection = nil

-- Every fault reported under a plugin's name is counted on its record
-- (shown on its page). Nothing else happens: no automatic turning off.
local function noteFault(owner: string, what: string, message: string)
	local record = records[owner]
	if not record then
		return
	end
	record.Faults += 1
	record.LastFault = { What = what, Message = message, Time = os.clock() }
	changed(record)
end
Plugins._noteFault = noteFault

local function log(level: string, text: string)
	local logger = T.Log
	if logger and logger[level] then
		logger[level]("plugins", text)
	end
end

local function nameOf(path: string): string
	return path:match("([^/\\]+)[/\\]*$") or path
end

local function changed(record)
	Plugins.Changed:Fire(record.Id or record.Folder, record)
end

----------------------------------------------------------------------
-- Which plugins are on (kept between runs)
----------------------------------------------------------------------

local function loadWanted()
	table.clear(wanted)
	local decoded = store:read()
	if decoded and type(decoded.On) == "table" then
		for _, id in decoded.On do
			if type(id) == "string" then
				wanted[id] = true
			end
		end
	end
end

local function saveWanted()
	store:queue(function()
		local on = {}
		for id in wanted do
			table.insert(on, id)
		end
		table.sort(on)
		return { On = on }
	end)
end

function Plugins.wanted(id: string): boolean
	return wanted[id] == true
end

-- Turn a plugin on or off for the next start. Nothing starts or stops now.
function Plugins.setWanted(id: string, on: boolean): (boolean, string?)
	if type(id) ~= "string" or (records[id] == nil and not wanted[id]) then
		return false, ("no plugin '%s'"):format(tostring(id))
	end
	if (wanted[id] == true) == (on == true) then
		return true, nil
	end
	wanted[id] = if on then true else nil
	saveWanted()
	log("info", ("%s will be %s at the next start"):format(id, if on then "on" else "off"))
	local record = records[id]
	if record then
		changed(record)
	end
	return true, nil
end

-- "on" / "off" when the next start will change it, nil otherwise.
function Plugins.pending(id: string): string?
	local record = records[id]
	local running = record ~= nil and record.State == "on"
	if wanted[id] and not running then
		-- failed / problem: it was meant to run and didn't; nothing is pending
		return if record and (record.State == "problem" or record.State == "failed") then nil else "on"
	elseif not wanted[id] and running then
		return "off"
	end
	return nil
end

----------------------------------------------------------------------
-- Reading a plugin folder
----------------------------------------------------------------------

local function makeContext(folder: string, path: string)
	local P = { Folder = folder, Path = path, Version = T.Version }
	local cache, loading = {}, {}
	function P.file(rel: string): string
		return path .. "/" .. tostring(rel)
	end
	function P.read(rel: string): string
		return readfile(P.file(rel))
	end
	function P.import(rel: string)
		rel = tostring(rel):gsub("%.luau$", "")
		local cached = cache[rel]
		if cached ~= nil then
			return cached
		end
		if loading[rel] then
			error(("circular import of '%s'"):format(rel), 2)
		end
		local file = path .. "/" .. rel .. ".luau"
		if not isfile(file) then
			error(("%s has no %s.luau"):format(folder, rel), 2)
		end
		local chunk, compileError = loadfile(file)
		if not chunk then
			error(("%s.luau doesn't compile: %s"):format(rel, tostring(compileError)), 2)
		end
		loading[rel] = true
		local ok, result = pcall(chunk, P)
		loading[rel] = nil
		if not ok then
			error(result, 0)
		end
		if result == nil then
			result = true
		end
		cache[rel] = result
		return result
	end
	return P
end

local function problem(record, text: string, trace: string?)
	record.State = "problem"
	record.Problem = text
	record.Trace = trace
	return record
end

-- A record for one folder: its definition, or the problem with it.
local function readFolder(folder: string)
	local path = Plugins.Folder .. "/" .. folder
	local file = path .. "/plugin.luau"
	local record = {
		Folder = folder,
		Path = path,
		State = "off",
		Warnings = {},
		Hooks = {},
		Faults = 0,
	}
	local okSource, source = pcall(readfile, file)
	if okSource and type(source) == "string" then
		for _, word in { "hookmetamethod", "hookfunction" } do
			if source:find(word, 1, true) then
				table.insert(record.Hooks, word)
			end
		end
	end
	local okLoad, chunk, compileError = pcall(loadfile, file)
	if not okLoad then
		return problem(record, "plugin.luau can't be read: " .. tostring(chunk))
	end
	if not chunk then
		record.CompileError = true
		return problem(record, "plugin.luau doesn't compile: " .. tostring(compileError))
	end
	local trace
	local okRun, definition = xpcall(chunk, function(message)
		trace = debug.traceback(tostring(message), 2)
		return message
	end, makeContext(folder, path))
	if not okRun then
		return problem(record, "plugin.luau failed: " .. tostring(definition), trace)
	end
	local bad = Api.checkDefinition(definition, folder)
	if bad then
		return problem(record, bad)
	end
	local id = Api.idFor(definition, folder) :: string
	record.Id = id
	record.Definition = definition
	record.Name = definition.Name
	record.Version = definition.Version
	record.Author = definition.Author
	record.Description = definition.Description
	record.Order = definition.Order or Plugins.DefaultOrder
	if Plugins.Reserved[id] then
		return problem(record, ("'%s' is one of Tungsten's own names; set another Id"):format(id))
	end
	if PRIME[id] and definition.Prime ~= true then
		return problem(record, ("'%s' is reserved for a prime plugin"):format(id))
	end
	if definition.Prime == true and not PRIME[id] then
		return problem(record, ("only the prime plugins (%s) set Prime"):format(table.concat(Plugins.Prime, ", ")))
	end
	for _, key in { "Requires", "Uses" } do
		for _, other in definition[key] or {} do
			if other == id then
				return problem(record, ("it lists itself in %s"):format(key))
			elseif not PRIME[other] then
				return problem(record, ("%s can only name the prime plugins (%s), not '%s'"):format(key, table.concat(Plugins.Prime, ", "), other))
			end
		end
	end
	if definition.Id == nil then
		table.insert(record.Warnings, ("no Id: it goes by '%s' (the folder name); set Id so renaming the folder keeps it on"):format(id))
	end
	return record
end

-- Folders in Tungsten/plugins that hold a plugin.luau, A–Z.
local function folders(): { string }
	local found = {}
	local okFolder, exists = pcall(isfolder, Plugins.Folder)
	if not (okFolder and exists) then
		return found
	end
	local ok, entries = pcall(listfiles, Plugins.Folder)
	if not ok or type(entries) ~= "table" then
		log("warn", "could not list " .. Plugins.Folder .. ": " .. tostring(entries))
		return found
	end
	for _, entry in entries do
		local name = nameOf(tostring(entry))
		local okIs, isDir = pcall(isfolder, Plugins.Folder .. "/" .. name)
		if okIs and isDir and name:sub(1, 1) ~= "_" then
			local okHas, has = pcall(isfile, Plugins.Folder .. "/" .. name .. "/plugin.luau")
			if okHas and has then
				table.insert(found, name)
			end
		end
	end
	table.sort(found, function(a, b)
		local la, lb = a:lower(), b:lower()
		if la ~= lb then
			return la < lb
		end
		return a < b
	end)
	return found
end

-- Load order: prime plugins first (in their order), then Order, then name.
local function sortRecords(list: { any })
	table.sort(list, function(a, b)
		-- only a real prime plugin (not a folder refused for taking its id)
		local pa = (a.Id and a.State ~= "problem" and PRIME[a.Id]) or math.huge
		local pb = (b.Id and b.State ~= "problem" and PRIME[b.Id]) or math.huge
		if pa ~= pb then
			return pa < pb
		end
		local oa, ob = a.Order or Plugins.DefaultOrder, b.Order or Plugins.DefaultOrder
		if oa ~= ob then
			return oa < ob
		end
		local na, nb = tostring(a.Name or a.Folder):lower(), tostring(b.Name or b.Folder):lower()
		if na ~= nb then
			return na < nb
		end
		return a.Folder < b.Folder
	end)
end

----------------------------------------------------------------------
-- Starting and stopping one plugin
----------------------------------------------------------------------

local function iconSource(record, icon: any): any
	if icon == nil then
		local default = record.Path .. "/icon.png"
		local ok, has = pcall(isfile, default)
		return if ok and has then default else nil
	end
	if type(icon) == "string" then
		local inFolder = record.Path .. "/" .. icon
		local ok, has = pcall(isfile, inFolder)
		if ok and has then
			return inFolder
		end
	end
	return icon
end

local function docsTopic(record)
	local docs = record.Definition.Docs
	local topic
	if type(docs) == "string" then
		topic = { File = record.Path .. "/" .. docs }
	else
		topic = table.clone(docs)
		if type(topic.File) == "string" and topic.File:sub(1, #T.Root + 1) ~= T.Root .. "/" then
			topic.File = record.Path .. "/" .. topic.File
		end
	end
	topic.Id = topic.Id or record.Id
	topic.Title = topic.Title or record.Name
	topic.Group = topic.Group or record.Name
	return topic
end

-- Runs Load(api) in a thread of its own and waits for it, at most
-- LoadTimeout seconds. Returns ok, message?, trace?
local function runLoad(load, api): (boolean, string?, string?)
	local done, ok, message, trace = false, false, nil, nil
	local thread = task.spawn(function()
		ok = xpcall(load, function(err)
			message = if type(err) == "table" and err.Message then tostring(err.Message) else tostring(err)
			trace = debug.traceback(tostring(message), 2)
			return err
		end, api)
		done = true
	end)
	if done then
		return ok, if ok then nil else "Load failed: " .. tostring(message), trace
	end
	if not coroutine.isyieldable() then
		-- Nothing here can wait for it; a Load must not yield outside the host.
		pcall(task.cancel, thread)
		return false, "Load waited, and the plugin was started where Tungsten can't wait for it", nil
	end
	local since = os.clock()
	while not done do
		if os.clock() - since >= Plugins.LoadTimeout then
			pcall(task.cancel, thread)
			return false, ("Load took longer than %d s"):format(Plugins.LoadTimeout), nil
		end
		task.wait()
	end
	return ok, if ok then nil else "Load failed: " .. tostring(message), trace
end

-- Puts a plugin into the failed state: the error goes to the console under
-- its name, then everything it registered is taken away.
local function fail(record, api, message: string, trace: string?)
	record.State = "failed"
	record.Problem = message
	record.Trace = trace
	record.Faults += 1
	local reporter = api and api.console and api.console.reporter
	if not reporter and T.Console and record.Id then
		local okGet, made = pcall(T.Console.reporter, record.Id, { Label = record.Name or record.Id })
		reporter = if okGet then made else nil
	end
	if reporter then
		local okReport, entry = pcall(function()
			return reporter:error(message, { Trace = trace })
		end)
		record.Error = if okReport then entry else nil
	end
	if api then
		pcall(api.remove, api)
	end
	record.Api = nil
	record.Exports = nil
	log("error", ("%s failed: %s%s"):format(record.Id, message, if trace then "\n" .. trace else ""))
	changed(record)
	return false, message
end

local function enable(record): (boolean, string?)
	if record.State == "on" then
		return true, nil
	end
	if record.State == "problem" or not record.Definition then
		return false, record.Problem or "it can't run"
	end
	local definition = record.Definition
	local id = record.Id
	for _, other in definition.Requires or {} do
		local needed = records[other]
		if not needed then
			problem(record, ("needs the prime plugin '%s', which isn't installed"):format(other))
			changed(record)
			return false, record.Problem
		elseif needed.State ~= "on" then
			problem(record, ("needs the prime plugin '%s', which isn't on"):format(other))
			changed(record)
			return false, record.Problem
		end
	end

	local startedAt = os.clock()
	local key = Api.lock(id, record.Folder)
	local okApi, api = pcall(Api.new, id, {
		Name = definition.Name,
		Settings = definition.Settings,
		SettingsPath = record.Path .. "/settings.json",
		Folder = record.Folder,
		Key = key,
	})
	if not okApi then
		return fail(record, nil, "its api could not be made: " .. tostring(api))
	end
	api.Version = definition.Version
	api.Path = record.Path
	record.Api = api

	-- What the definition declares.
	local registerTrace
	local okRegister, registerError = xpcall(function()
		for _, command in definition.Commands or {} do
			api.console.register(command)
		end
		for _, fn in definition.Functions or {} do
			api.explorer.addFunction(fn)
		end
		local tab = definition.Tab
		if tab then
			api.tabs.add({
				Id = id,
				Title = tab.Title,
				Icon = iconSource(record, tab.Icon or definition.Icon),
				Tooltip = tab.Tooltip or definition.Description,
				Closable = true,
				-- built the first time it opens; the tab bar reports a fault
				-- under the plugin's name
				Build = function(page)
					tab.Build(page, api)
				end,
				-- every load (base/loaded), whichever tab is open
				OnLoad = if type(tab.OnLoad) == "function"
					then function(values, _, items)
						return tab.OnLoad(values, api, items)
					end
					else nil,
				-- each time the tab opens / another opens
				OnSelect = if type(tab.OnSelect) == "function"
					then function()
						return tab.OnSelect(api)
					end
					else nil,
				OnDeselect = if type(tab.OnDeselect) == "function"
					then function()
						return tab.OnDeselect(api)
					end
					else nil,
			})
		end
		if definition.Docs then
			api.docs.add(docsTopic(record))
		end
	end, function(err)
		registerTrace = debug.traceback(tostring(err), 2)
		return err
	end)
	if not okRegister then
		return fail(record, api, "registering failed: " .. tostring(registerError), registerTrace)
	end

	if definition.Load then
		local okLoad, message, trace = runLoad(definition.Load, api)
		if not okLoad then
			return fail(record, api, message :: string, trace)
		end
		if not Api.isAlive(api) then
			return fail(record, nil, "Load removed the plugin's api")
		end
	end

	local exports = definition.Exports
	if type(exports) == "function" then
		local okExports, value = pcall(exports, api)
		if not okExports then
			return fail(record, api, "Exports failed: " .. tostring(value))
		end
		exports = value
	end
	record.Exports = if type(exports) == "table" then exports else nil

	record.State = "on"
	record.Problem, record.Trace, record.Error = nil, nil, nil
	record.LoadTime = os.clock() - startedAt
	log("info", ("%s on (%.0f ms)"):format(id, record.LoadTime * 1000))
	changed(record)
	return true, nil
end

local function disable(record)
	if record.State ~= "on" then
		return false
	end
	local api = record.Api
	local definition = record.Definition
	if api and definition.Unload then
		local okUnload, err = xpcall(definition.Unload, function(message)
			return tostring(message) .. "\n" .. debug.traceback(tostring(message), 2)
		end, api)
		if not okUnload then
			T.import("console/reporter").ownerFault(record.Id, "Unload", err)
		end
	end
	if api then
		pcall(api.remove, api)
	end
	record.Api = nil
	record.Exports = nil
	record.State = "off"
	log("info", record.Id .. " off")
	changed(record)
	return true
end

----------------------------------------------------------------------
-- The plugin list
----------------------------------------------------------------------

--[[
	Reads Tungsten/plugins again. Running and failed plugins are kept as
	they are (a failed one keeps its error until it is reloaded); the rest
	are read fresh (a fixed plugin.luau shows its new state). New folders
	arrive off; folders that are gone leave (a running plugin stays until
	the next start). `reread` names folders to read fresh regardless.
]]
function Plugins.rescan(reread: { [string]: boolean }?): { any }
	local before = {}
	for _, record in ordered do
		before[record.Folder] = record
	end
	local next = {}
	local seen = {}
	for _, folder in folders() do
		seen[folder] = true
		local old = before[folder]
		if old and (old.State == "on" or old.State == "failed") and not (reread and reread[folder]) then
			table.insert(next, old)
		else
			local fresh = readFolder(folder)
			fresh.Faults = if old then old.Faults else 0
			table.insert(next, fresh)
		end
	end
	-- a running plugin whose folder is gone keeps going until the next start
	for _, record in ordered do
		if not seen[record.Folder] and record.State == "on" and not table.find(next, record) then
			table.insert(record.Warnings, "its folder is gone; it stops at the next start")
			table.insert(next, record)
		end
	end

	-- Ids: running plugins keep theirs; otherwise the first folder (A–Z) wins.
	local owners = {}
	for _, record in next do
		if record.State == "on" or record.State == "failed" then
			owners[record.Id] = record
		end
	end
	-- (a folder with a problem never claims an id)
	for _, record in next do
		if record.Id and record.State == "off" and record.Definition then
			local owner = owners[record.Id]
			if owner and owner ~= record then
				problem(record, ("its id '%s' is already used by plugins/%s"):format(record.Id, owner.Folder))
			elseif not owner then
				owners[record.Id] = record
			end
		end
	end

	-- Locks follow the owners.
	for id, record in records do
		if owners[id] == nil then
			local entry = Api.lockedBy(id)
			if entry == record.Folder then
				Api.unlock(id, Api.lock(id, record.Folder))
			end
		end
	end
	table.clear(records)
	for id, record in owners do
		records[id] = record
		Api.lock(id, record.Folder)
	end

	sortRecords(next)
	ordered = next
	for _, record in ordered do
		changed(record)
	end
	return Plugins.list()
end

function Plugins.list(): { any }
	return table.clone(ordered)
end

function Plugins.get(id: string)
	return records[id]
end

-- The record for a folder (problems without an id included).
function Plugins.byFolder(folder: string)
	for _, record in ordered do
		if record.Folder == folder then
			return record
		end
	end
	return nil
end

function Plugins.isPrime(id: string): boolean
	return PRIME[id] ~= nil
end

-- How many plugins are running.
function Plugins.count(): number
	local count = 0
	for _, record in ordered do
		if record.State == "on" then
			count += 1
		end
	end
	return count
end

-- Does `caller` list `other` in Requires or Uses?
local function lists(caller: string, other: string): boolean
	local record = records[caller]
	if not (record and record.Definition) then
		return false
	end
	for _, key in { "Requires", "Uses" } do
		for _, id in record.Definition[key] or {} do
			if id == other then
				return true
			end
		end
	end
	return false
end

-- Why `other` can't be reached right now (nil when it is on).
local function unreachable(other: string): string?
	local needed = records[other]
	if not needed then
		return ("'%s' isn't installed"):format(other)
	elseif needed.State ~= "on" then
		local name = needed.Name or other
		return ("%s isn't on (turn it on in the Plugins tab)"):format(name)
	end
	return nil
end

-- What a prime plugin shares, for a plugin that lists it in Requires or Uses.
function Plugins.exportsFor(caller: string, other: string): (any, string?)
	if not lists(caller, other) then
		return nil, ("%s doesn't list '%s' in Requires or Uses"):format(caller, tostring(other))
	end
	local why = unreachable(other)
	if why then
		return nil, why
	end
	return records[other].Exports or {}, nil
end

--[[
	Opens a prime plugin's tab at something: selects its tab and calls its
	Exports.reveal(focus) (if it has one). A plugin may open the primes it
	lists (Requires / Uses); a prime may open itself; caller "you" (the
	user, the console) may open any prime. Returns ok, why.
]]
function Plugins.open(caller: string, other: string, focus: any?): (boolean, string?)
	if caller ~= "you" and caller ~= other and not lists(caller, other) then
		return false, ("%s doesn't list '%s' in Requires or Uses"):format(caller, tostring(other))
	end
	local why = unreachable(other)
	if why then
		return false, why
	end
	local record = records[other]
	if T.Tabs and T.Registry and T.Registry.getTab(other) then
		T.Tabs:Select(other)
	end
	local reveal = type(record.Exports) == "table" and record.Exports.reveal
	if focus ~= nil and type(reveal) == "function" then
		local ok, err = pcall(reveal, focus)
		if not ok then
			local okR, Reporter = pcall(T.import, "console/reporter")
			if okR and Reporter.ownerFault then
				Reporter.ownerFault(other, "Exports.reveal", err)
			end
			return false, ("%s couldn't show it: %s"):format(record.Name or other, tostring(err))
		end
	end
	return true, nil
end

----------------------------------------------------------------------
-- Start-up, shutdown, reload
----------------------------------------------------------------------

-- Finds every plugin and starts the ones that are on. Each Load may take
-- up to LoadTimeout seconds; call it where Tungsten can wait (the loader).
function Plugins.start()
	if started then
		return Plugins.count()
	end
	started = true
	loadWanted()
	wantedAtStart = table.clone(wanted)
	if not faultConnection then
		local okReporter, Reporter = pcall(T.import, "console/reporter")
		if okReporter and Reporter.Faulted then
			faultConnection = Reporter.Faulted:Connect(noteFault)
		end
	end
	Plugins.rescan()
	for _, record in table.clone(ordered) do
		if not started then
			break -- stopped while starting (Tungsten was run again)
		end
		if record.Id and wanted[record.Id] and record.State == "off" then
			enable(record)
		end
	end
	log("info", ("%d of %d plugins on"):format(Plugins.count(), #ordered))
	return Plugins.count()
end

-- Stops every running plugin, newest first.
function Plugins.stop()
	for index = #ordered, 1, -1 do
		local record = ordered[index]
		if record.State == "on" then
			pcall(disable, record)
		end
	end
	store:flush()
	if faultConnection then
		faultConnection:Disconnect()
		faultConnection = nil
	end
	for id, record in records do
		local key = Api.lock(id, record.Folder)
		Api.unlock(id, key)
	end
	table.clear(records)
	table.clear(ordered)
	started = false
end

function Plugins.started(): boolean
	return started
end

-- Plugins that list `id` in Requires and are running.
local function dependents(id: string): { any }
	local out = {}
	for _, record in ordered do
		if record.State == "on" and record.Definition then
			for _, other in record.Definition.Requires or {} do
				if other == id then
					table.insert(out, record)
					break
				end
			end
		end
	end
	return out
end

--[[
	Reads a plugin's files again and, if it was on or failed, starts it
	again (settings are kept; its variables go with the old copy). Plugins
	that need it are stopped first and started again after. Waits for Load
	like start(); returns ok, message.
]]
function Plugins.reload(id: string): (boolean, string?)
	local record = records[id]
	if not record then
		for _, other in ordered do
			if other.Id == id or other.Folder == id then
				record = other
				break
			end
		end
	end
	if not record then
		return false, ("no plugin '%s'"):format(tostring(id))
	end
	-- It starts again if it is running, or was on when Tungsten started
	-- and then failed or hit a problem (turning it off since doesn't stop
	-- that: off waits for the next start, like on).
	local wasRunning = record.State == "on"
		or ((record.State == "failed" or record.State == "problem") and record.Id ~= nil and wantedAtStart[record.Id] == true)
	local needing = if record.Id then dependents(record.Id) else {}
	for index = #needing, 1, -1 do
		disable(needing[index])
	end
	disable(record)

	local folder = record.Folder
	Plugins.rescan({ [folder] = true }) -- reads its files fresh
	local now = Plugins.byFolder(folder)
	local ok, message = true, nil
	if now and now.State == "off" and wasRunning then
		ok, message = enable(now)
	elseif now and now.State == "problem" then
		ok, message = false, now.Problem
	end
	for _, other in needing do
		local again = Plugins.get(other.Id)
		if again and again.State == "off" then
			enable(again)
		end
	end
	return ok, message
end

-- For tests and the host's own use: start / stop one plugin now.
Plugins._enable = enable
Plugins._disable = disable

return Plugins
