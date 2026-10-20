--[[
	Tungsten loader

	Run it in Volt:

		loadstring(request({ Url = "https://raw.githubusercontent.com/minimofie/tungsten/main/loader.luau" }).Body)()

	It brings the Tungsten folder in Volt's workspace up to date from GitHub,
	then runs Tungsten.luau from that folder. Only files that changed since
	the last run are downloaded; Tungsten itself still runs from local files.
	Settings, logs, saved files and plugins you added are never touched. When
	GitHub can't be reached, the copy already in the workspace runs.

	Options (all optional), passed to the loaded chunk:

		loadstring(...)({ Branch = "dev", Owner = "name", Repo = "tungsten", Run = false })

	Branch / Owner / Repo pick where files come from (default main,
	minimofie, tungsten). Run = false updates the folder without starting
	Tungsten.
]]

local options = ...
if type(options) ~= "table" then
	options = {}
end

local OWNER = options.Owner or "minimofie"
local REPO = options.Repo or "tungsten"
local BRANCH = options.Branch or "main"
local ROOT = "Tungsten"
-- What the loader installed last time ("<hash> <size> <path>" lines), so a
-- file is downloaded again only when its hash changes or it was edited.
local RECORD = ROOT .. "/base/installed.txt"
local BASE = ("https://raw.githubusercontent.com/%s/%s/%s/"):format(OWNER, REPO, BRANCH)
local WORKERS = 8

local function say(text: string)
	print("[Tungsten] " .. text)
end

local function fetch(path: string): (string?, string?)
	local ok, response = pcall(request, { Url = BASE .. path, Method = "GET" })
	if not ok then
		return nil, tostring(response)
	end
	if type(response) ~= "table" then
		return nil, "no response"
	end
	if not response.Success or response.StatusCode ~= 200 or type(response.Body) ~= "string" then
		return nil, ("HTTP %s %s"):format(tostring(response.StatusCode), tostring(response.StatusMessage or ""))
	end
	return response.Body
end

-- A path from a list must stay inside the Tungsten folder.
local function safePath(path: string): boolean
	return path:sub(1, 1) ~= "/" and not path:find("\\", 1, true) and not path:find("..", 1, true)
end

-- "version <x>" plus "<hash> <size> <path>" lines -> version, { [path] = entry }, ordered paths
local function parse(text: string)
	local version, files, order = nil, {}, {}
	for line in text:gmatch("[^\n]+") do
		line = line:gsub("\r$", "")
		local v = line:match("^version%s+(%S+)$")
		if v then
			version = v
		else
			local hash, size, path = line:match("^(%x+) (%d+) (%S+)$")
			if hash and safePath(path) and not files[path] then
				files[path] = { Hash = hash, Size = tonumber(size) }
				table.insert(order, path)
			end
		end
	end
	return version, files, order
end

local function readLocal(path: string): string?
	local ok, exists = pcall(isfile, path)
	if not ok or not exists then
		return nil
	end
	local read, data = pcall(readfile, path)
	return if read and type(data) == "string" then data else nil
end

local function runTungsten()
	if options.Run == false then
		return
	end
	local chunk, err = loadfile(ROOT .. "/Tungsten.luau")
	if not chunk then
		error("[Tungsten] could not compile Tungsten.luau: " .. tostring(err), 0)
	end
	return chunk()
end

local function installed(): boolean
	local ok, exists = pcall(isfile, ROOT .. "/Tungsten.luau")
	return ok and exists
end

----------------------------------------------------------------------
-- What the repository ships
----------------------------------------------------------------------
local listText, listError = fetch("release.txt")
local version, list, order
if listText then
	version, list, order = parse(listText)
end
if not listText or not version or #order == 0 then
	local why = listError or "release.txt is not a file list"
	if installed() then
		warn(("[Tungsten] could not check for updates (%s); running the copy in the workspace"):format(why))
		return runTungsten()
	end
	error(("[Tungsten] could not download Tungsten from %s (%s)"):format(BASE, why), 0)
end

----------------------------------------------------------------------
-- What needs downloading
----------------------------------------------------------------------
local recorded = {}
do
	local text = readLocal(RECORD)
	if text then
		local _, files = parse(text)
		recorded = files
	end
end

local need, stale = {}, {}
for _, path in order do
	local entry, old = list[path], recorded[path]
	local data = if old and old.Hash == entry.Hash then readLocal(ROOT .. "/" .. path) else nil
	if not data or #data ~= entry.Size then
		table.insert(need, path)
		stale[path] = true
	end
end

----------------------------------------------------------------------
-- Download everything first; write only when all of it arrived, so a
-- failed update leaves the workspace copy as it was.
----------------------------------------------------------------------
if #need > 0 then
	say(("downloading %d file%s (version %s)"):format(#need, if #need == 1 then "" else "s", version))
	local got, failure = {}, nil
	local nextIndex, running = 0, 0
	local function worker()
		while not failure do
			nextIndex += 1
			local path = need[nextIndex]
			if not path then
				break
			end
			local body, err = fetch(ROOT .. "/" .. path)
			if not body then
				failure = path .. ": " .. tostring(err)
			elseif #body ~= list[path].Size then
				failure = ("%s: expected %d bytes, got %d"):format(path, list[path].Size, #body)
			else
				got[path] = body
			end
		end
		running -= 1
	end
	for _ = 1, math.min(WORKERS, #need) do
		running += 1
		task.spawn(worker)
	end
	while running > 0 do
		task.wait()
	end

	if failure then
		if installed() then
			warn(("[Tungsten] update failed (%s); running the copy in the workspace"):format(failure))
			return runTungsten()
		end
		error("[Tungsten] download failed: " .. failure, 0)
	end

	local writeFailures = 0
	for _, path in need do
		local ok, err = pcall(writefile, ROOT .. "/" .. path, got[path])
		if ok then
			stale[path] = nil
		else
			writeFailures += 1
			warn(("[Tungsten] could not write %s: %s"):format(path, tostring(err)))
		end
	end
	if writeFailures > 0 then
		warn(("[Tungsten] %d file%s could not be written; they are tried again next run"):format(writeFailures, if writeFailures == 1 then "" else "s"))
	end
end

-- Files an earlier version installed that this one no longer ships.
for path in recorded do
	if not list[path] then
		local full = ROOT .. "/" .. path
		local ok, exists = pcall(isfile, full)
		if ok and exists then
			pcall(delfile, full)
		end
	end
end

-- Record what is now installed (a file that couldn't be written is left
-- out, so the next run downloads it again).
do
	local lines = { "version " .. version }
	for _, path in order do
		if not stale[path] then
			table.insert(lines, ("%s %d %s"):format(list[path].Hash, list[path].Size, path))
		end
	end
	local ok, err = pcall(writefile, RECORD, table.concat(lines, "\n") .. "\n")
	if not ok then
		warn("[Tungsten] could not write " .. RECORD .. ": " .. tostring(err))
	end
end

say(if #need > 0 then ("updated to version %s"):format(version) else ("version %s is up to date"):format(version))
return runTungsten()
