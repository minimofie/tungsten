--[[
	Tungsten · base/logger
	Writes one file per run to Tungsten/logs/session_<time>.log
	(the logs folder is made when missing)
	and keeps only the newest few.

		T.Log.info("scope", "message", ...)
		T.Log.warn / T.Log.error / T.Log.debug
]]

local T = ...

local LOG_DIR = T.Root .. "/logs"
local KEEP = 8
local FLUSH_DELAY = 0.5

local LEVEL_TAGS = {
	debug = "DEBUG",
	info = "INFO ",
	warn = "WARN ",
	error = "ERROR",
}

local Logger = {}
Logger.File = nil :: string?

local buffer = {}
local flushQueued = false
local closed = false

local function clock(): string
	local t = DateTime.now():ToLocalTime()
	return ("%02d:%02d:%02d.%03d"):format(t.Hour, t.Minute, t.Second, t.Millisecond)
end

local function fileStamp(): string
	local t = DateTime.now():ToLocalTime()
	return ("%04d-%02d-%02d_%02d-%02d-%02d"):format(t.Year, t.Month, t.Day, t.Hour, t.Minute, t.Second)
end

function Logger.flush()
	if #buffer == 0 or not Logger.File then
		return
	end
	local data = table.concat(buffer)
	table.clear(buffer)
	local ok, err = pcall(appendfile, Logger.File, data)
	if not ok then
		warn("[Tungsten] could not write log file: " .. tostring(err))
	end
end

local function queueFlush()
	if flushQueued then
		return
	end
	flushQueued = true
	task.delay(FLUSH_DELAY, function()
		flushQueued = false
		Logger.flush()
	end)
end

local function write(level: string, scope: string, ...)
	if closed then
		return
	end
	local parts = table.pack(...)
	for i = 1, parts.n do
		parts[i] = tostring(parts[i])
	end
	local message = table.concat(parts, " ", 1, parts.n)
	-- Indent continuation lines (tracebacks) so entries stay readable.
	message = message:gsub("\n", "\n    ")

	table.insert(buffer, ("[%s] [%s] [%s] %s\n"):format(clock(), LEVEL_TAGS[level], scope, message))

	if level == "error" then
		Logger.flush()
	else
		queueFlush()
	end
end

function Logger.debug(scope: string, ...)
	write("debug", scope, ...)
end

function Logger.info(scope: string, ...)
	write("info", scope, ...)
end

function Logger.warn(scope: string, ...)
	write("warn", scope, ...)
end

function Logger.error(scope: string, ...)
	write("error", scope, ...)
end

local function prune()
	local ok, entries = pcall(listfiles, LOG_DIR)
	if not ok or type(entries) ~= "table" then
		return
	end

	local sessions = {}
	for _, entry in entries do
		local name = tostring(entry):match("[^/\\]+$")
		if name and name:match("^session_.+%.log$") then
			table.insert(sessions, name)
		end
	end

	-- Timestamped names sort chronologically; newest first.
	table.sort(sessions, function(a, b)
		return a > b
	end)

	for index = KEEP + 1, #sessions do
		pcall(delfile, LOG_DIR .. "/" .. sessions[index])
	end
end

function Logger.start()
	if not isfolder(LOG_DIR) then
		makefolder(LOG_DIR)
	end

	local base = "session_" .. fileStamp()
	local path = ("%s/%s.log"):format(LOG_DIR, base)
	local suffix = 2
	while isfile(path) do
		path = ("%s/%s_%d.log"):format(LOG_DIR, base, suffix)
		suffix += 1
	end

	local executorName, executorVersion = "unknown", ""
	pcall(function()
		executorName, executorVersion = identifyexecutor()
	end)

	local header = table.concat({
		("Tungsten %s session log"):format(T.Version),
		("Started   %s"):format(DateTime.now():FormatLocalTime("LLL", "en-us")),
		("Executor  %s %s"):format(tostring(executorName), tostring(executorVersion or "")),
		("Place     %s"):format(tostring(game.PlaceId)),
		string.rep("-", 60),
		"",
	}, "\n")

	writefile(path, header)
	Logger.File = path
	prune()
end

function Logger.close()
	if closed then
		return
	end
	write("info", "core", "session closed")
	Logger.flush()
	closed = true
end

return Logger
