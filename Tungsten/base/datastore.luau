--[[
	Tungsten · base/datastore
	The one place Tungsten keeps data between runs: a JSON file of named
	values, written shortly after a change (so a burst of changes is one
	write) and on shutdown. Tungsten's own settings (base/settings) and
	every plugin's settings (api.settings) are stored through it.

		local store = DataStore.open("Tungsten/base/settings.json", {
			Name = "settings",      -- log tag
			Backup = true,          -- keep a copy of a file that can't be read
		})
		local values, problem = store:read()  -- table | nil (no file / unreadable)
		store:queue(function() return values end) -- save soon (snapshot taken then)
		store:flush()                         -- save now if a save is waiting
		store:write(values)                   -- save now -> ok, err

	It only reads and writes; checking what the values mean is the job of
	whoever owns the file.
]]

local T = ...
local HttpService = T.import("base/services").HttpService

local DataStore = {}
DataStore.Delay = 0.4 -- seconds between a change and the write

local Store = {}
Store.__index = Store

function DataStore.open(path: string, opts: { [string]: any }?)
	opts = opts or {}
	return setmetatable({
		Path = path,
		Name = opts.Name or "data",
		Backup = opts.Backup == true,
		_queued = false,
		_snapshot = nil,
	}, Store)
end

-- The decoded file. nil, nil when there is no file; nil and a reason
-- when it can't be read (a Backup store copies it to <path>.bak first).
function Store:read(): ({ [string]: any }?, string?)
	if not isfile(self.Path) then
		return nil, nil
	end
	local ok, decoded = pcall(function()
		return HttpService:JSONDecode(readfile(self.Path))
	end)
	if ok and type(decoded) == "table" then
		return decoded, nil
	end
	if self.Backup then
		pcall(function()
			writefile(self.Path .. ".bak", readfile(self.Path))
		end)
	end
	return nil, "could not be read"
end

function Store:write(values: { [string]: any }): (boolean, string?)
	local ok, err = pcall(function()
		writefile(self.Path, HttpService:JSONEncode(values))
	end)
	if not ok then
		T.Log.error(self.Name, ("could not save %s: %s"):format(self.Path, tostring(err)))
		return false, tostring(err)
	end
	return true, nil
end

-- Save soon. snapshot() is called when the write happens, so the newest
-- values are written.
function Store:queue(snapshot: () -> { [string]: any })
	self._snapshot = snapshot
	if self._queued then
		return
	end
	self._queued = true
	task.delay(DataStore.Delay, function()
		self:flush()
	end)
end

function Store:pending(): boolean
	return self._queued
end

-- Write now if a save is waiting.
function Store:flush(): boolean
	if not self._queued then
		return false
	end
	self._queued = false
	local snapshot = self._snapshot
	self._snapshot = nil
	if snapshot then
		self:write(snapshot())
	end
	return true
end

return DataStore
