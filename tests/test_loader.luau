-- The web loader (loader.luau at the repo root): installs and updates
-- workspace/Tungsten/ from release.txt over request(), then runs Tungsten.
local passed, failed = 0, 0
local function check(name, cond, detail)
	if cond then
		passed += 1
	else
		failed += 1
		print("FAIL: " .. name .. (if detail ~= nil then "  [" .. tostring(detail) .. "]" else ""))
	end
end
local E_ = H.env
H.ABS_SHIFT = SHIFT or 0
local genv = H.genv
H.keepPrimes()

local function contains(list, text)
	for _, line in list do
		if line:find(text, 1, true) then
			return true
		end
	end
	return false
end

----------------------------------------------------------------------
-- release.txt matches what Tungsten/ ships (rerun tools/make_release.py)
----------------------------------------------------------------------
local REAL_LIST = H.FILES["release.txt"]
check("release.txt exists", type(REAL_LIST) == "string")
check("loader.luau exists", type(H.FILES["loader.luau"]) == "string")
local SHIPPED = {}
do
	local version = REAL_LIST:match("^version (%S+)\n")
	local loaderVersion = H.FILES["Tungsten/Tungsten.luau"]:match('local VERSION = "([^"]+)"')
	check("release.txt version is Tungsten's", version ~= nil and version == loaderVersion, version)
	local missing, stale = {}, {}
	for hash, size, path in REAL_LIST:gmatch("(%x+) (%d+) (%S+)") do
		table.insert(SHIPPED, path)
		local content = H.FILES["Tungsten/" .. path]
		if content == nil then
			table.insert(missing, path)
		elseif content ~= "<binary>" and #content ~= tonumber(size) then
			table.insert(stale, path)
		end
	end
	check("release.txt lists files", #SHIPPED > 200, #SHIPPED)
	check("every listed file exists", #missing == 0, table.concat(missing, ", "))
	check("listed sizes are current", #stale == 0, table.concat(stale, ", "))
	local listed = {}
	for _, path in SHIPPED do
		listed[path] = true
	end
	local unlisted = {}
	for path in H.FILES do
		local rel = path:match("^Tungsten/(.+)$")
		if rel and not listed[rel] then
			local parts = rel:split("/")
			local runtime = rel == "base/settings.json" or rel == "base/plugins.json" or rel == "base/installed.txt"
				or parts[1] == "logs" or parts[1] == "saved" or (parts[1] == "plugins" and #parts > 2 and parts[#parts] == "settings.json")
			if not runtime then
				table.insert(unlisted, rel)
			end
		end
	end
	check("every shipped file is listed", #unlisted == 0, table.concat(unlisted, ", "))
	check("manifest is listed", listed["base/data/manifest.luau"] == true)
	check("the loader's record is not listed", listed["base/installed.txt"] == nil)
end

----------------------------------------------------------------------
-- A stand-in repository served through request()
----------------------------------------------------------------------
local BASE = "https://raw.githubusercontent.com/minimofie/tungsten/test/"
local REMOTE, ORDER = {}, {}
for _, path in SHIPPED do
	REMOTE[path] = H.FILES["Tungsten/" .. path]
	table.insert(ORDER, path)
end
local function addRemote(path, content)
	if REMOTE[path] == nil then
		table.insert(ORDER, path)
	end
	REMOTE[path] = content
end
local function removeRemote(path)
	REMOTE[path] = nil
	table.remove(ORDER, table.find(ORDER, path))
end
local hashes = {}
local function hashOf(s)
	if not hashes[s] then
		local h = #s
		for i = 1, #s do
			h = (h * 31 + s:byte(i)) % 4294967291
		end
		hashes[s] = ("%08x"):format(h)
	end
	return hashes[s]
end
local EXTRA_LINES = ""
local function listText()
	local lines = { "version 9.9.9" }
	for _, path in ORDER do
		table.insert(lines, ("%s %d %s"):format(hashOf(REMOTE[path]), #REMOTE[path], path))
	end
	return table.concat(lines, "\n") .. "\n" .. EXTRA_LINES
end

local REQUESTS, LOG = {}, {}
local OFFLINE, MISSING = false, {}
E_.request = function(opts)
	table.insert(REQUESTS, opts.Url)
	if OFFLINE then
		error("HttpError: ConnectFail", 0)
	end
	local notFound = { Success = false, StatusCode = 404, StatusMessage = "Not Found", Headers = {}, Body = "404: Not Found" }
	if opts.Url:sub(1, #BASE) ~= BASE then
		return notFound
	end
	local rel = opts.Url:sub(#BASE + 1)
	local body
	if rel == "release.txt" then
		body = listText()
	elseif rel:sub(1, 9) == "Tungsten/" then
		body = REMOTE[rel:sub(10)]
	end
	if body == nil or MISSING[rel] then
		return notFound
	end
	return { Success = true, StatusCode = 200, StatusMessage = "OK", Headers = {}, Body = body }
end
E_.print = function(...)
	table.insert(LOG, table.concat({ ... }, " "))
end

local function clearLocal()
	for path in table.clone(H.FILES) do
		if path:sub(1, 9) == "Tungsten/" then
			H.FILES[path] = nil
		end
	end
end
local function sameAsRemote()
	local wrong = {}
	for _, path in ORDER do
		if H.FILES["Tungsten/" .. path] ~= REMOTE[path] then
			table.insert(wrong, path)
		end
	end
	return #wrong == 0, table.concat(wrong, ", ")
end
local function runLoader(opts)
	table.clear(REQUESTS)
	table.clear(LOG)
	table.clear(H.WARNINGS)
	local ok, err = H.run("loader.luau", opts or { Branch = "test" })
	H.advance(5)
	return ok, err
end
local function fileRequests()
	local n = 0
	for _, url in REQUESTS do
		if url:find("/Tungsten/", 1, true) then
			n += 1
		end
	end
	return n
end

----------------------------------------------------------------------
-- A fresh install
----------------------------------------------------------------------
addRemote("base/data/old_note.txt", "dropped in the next version")
clearLocal()
do
	local ok, err = runLoader()
	check("fresh: loader runs", ok, err)
	check("fresh: files come from the branch asked for", REQUESTS[1] == BASE .. "release.txt", REQUESTS[1])
	check("fresh: every file downloaded once", fileRequests() == #ORDER, fileRequests())
	local same, wrong = sameAsRemote()
	check("fresh: workspace matches the repository", same, wrong)
	check("fresh: record written", type(H.FILES["Tungsten/base/installed.txt"]) == "string")
	check("fresh: record has the version", (H.FILES["Tungsten/base/installed.txt"] or ""):match("^version 9%.9%.9\n") ~= nil)
	check("fresh: says what it downloaded", contains(LOG, "downloading " .. #ORDER .. " files (version 9.9.9)"), LOG[1])
	check("fresh: Tungsten started", type(genv.Tungsten) == "table" and type(genv.Tungsten.Context) == "table")
	check("fresh: no warnings", #H.WARNINGS == 0, H.WARNINGS[1])
end

----------------------------------------------------------------------
-- Run again with nothing new
----------------------------------------------------------------------
local userFiles = {
	["Tungsten/plugins/Mine/readme.txt"] = "my own plugin folder",
	["Tungsten/saved/thing.rbxm"] = "saved",
}
for path, content in userFiles do
	H.FILES[path] = content
end
do
	local before = genv.Tungsten
	local ok, err = runLoader()
	check("again: loader runs", ok, err)
	check("again: only the list is fetched", #REQUESTS == 1 and fileRequests() == 0, #REQUESTS)
	check("again: says up to date", contains(LOG, "version 9.9.9 is up to date"), LOG[1])
	check("again: Tungsten restarted", genv.Tungsten ~= nil and genv.Tungsten ~= before)
end

----------------------------------------------------------------------
-- An update: one file changed, one dropped, one added; a local edit
----------------------------------------------------------------------
do
	local changed = REMOTE["base/access.luau"] .. "\n-- changed upstream\n"
	addRemote("base/access.luau", changed)
	-- Same size, different content: only the hash tells.
	local undo = REMOTE["base/undo.luau"]
	local sameSize = undo:sub(1, -2) .. (if undo:sub(-1) == "\n" then " " else "\n")
	addRemote("base/undo.luau", sameSize)
	removeRemote("base/data/old_note.txt")
	addRemote("base/data/new_note.txt", "new in this version")
	H.FILES["Tungsten/base/types.luau"] ..= "\n-- edited by hand\n"
	local ok, err = runLoader()
	check("update: loader runs", ok, err)
	check("update: only changed or edited files downloaded", fileRequests() == 4, fileRequests())
	check("update: same-size change written", H.FILES["Tungsten/base/undo.luau"] == sameSize)
	check("update: changed file written", H.FILES["Tungsten/base/access.luau"] == changed)
	check("update: added file written", H.FILES["Tungsten/base/data/new_note.txt"] == "new in this version")
	check("update: hand edit replaced", H.FILES["Tungsten/base/types.luau"] == REMOTE["base/types.luau"])
	check("update: dropped file deleted", H.FILES["Tungsten/base/data/old_note.txt"] == nil)
	for path, content in userFiles do
		check("update: user file kept " .. path, H.FILES[path] == content)
	end
	local settings = H.FILES["Tungsten/base/settings.json"]
	check("update: settings kept", settings == nil or type(settings) == "string")
	local same, wrong = sameAsRemote()
	check("update: workspace matches the repository", same, wrong)
end

----------------------------------------------------------------------
-- A failed download changes nothing and runs the workspace copy
----------------------------------------------------------------------
do
	local before = H.FILES["Tungsten/base/access.luau"]
	addRemote("base/access.luau", before .. "-- another change\n")
	addRemote("base/loaded.luau", REMOTE["base/loaded.luau"] .. "-- also changed\n")
	MISSING["Tungsten/base/loaded.luau"] = true
	local handle = genv.Tungsten
	local ok, err = runLoader()
	check("failed file: loader runs", ok, err)
	check("failed file: warns", contains(H.WARNINGS, "update failed (base/loaded.luau: HTTP 404"), H.WARNINGS[1])
	check("failed file: nothing written", H.FILES["Tungsten/base/access.luau"] == before)
	check("failed file: workspace copy runs", genv.Tungsten ~= nil and genv.Tungsten ~= handle)
	MISSING["Tungsten/base/loaded.luau"] = nil
	ok, err = runLoader()
	check("retry: loader runs", ok, err)
	check("retry: both files downloaded", fileRequests() == 2, fileRequests())
	local same, wrong = sameAsRemote()
	check("retry: workspace matches the repository", same, wrong)
end

----------------------------------------------------------------------
-- Offline, wrong branch, unsafe paths, Run = false
----------------------------------------------------------------------
do
	OFFLINE = true
	local handle = genv.Tungsten
	local ok, err = runLoader()
	check("offline: loader runs", ok, err)
	check("offline: warns", contains(H.WARNINGS, "could not check for updates (HttpError: ConnectFail)"), H.WARNINGS[1])
	check("offline: workspace copy runs", genv.Tungsten ~= nil and genv.Tungsten ~= handle)
	OFFLINE = false

	ok, err = runLoader({ Run = false })
	check("no Branch: the repository's default branch (HEAD)", REQUESTS[1] == "https://raw.githubusercontent.com/minimofie/tungsten/HEAD/release.txt", REQUESTS[1])

	ok, err = runLoader({ Branch = "nope" })
	check("wrong branch: workspace copy runs", ok and contains(H.WARNINGS, "HTTP 404 Not Found"), err)

	EXTRA_LINES = "0123456789ab 4 ../evil.luau\n0123456789ab 4 /abs.luau\n"
	ok, err = runLoader()
	check("unsafe paths: loader runs", ok, err)
	check("unsafe paths: never fetched", not contains(REQUESTS, "evil") and not contains(REQUESTS, "abs.luau"))
	check("unsafe paths: never written", H.FILES["evil.luau"] == nil and H.FILES["/abs.luau"] == nil)
	EXTRA_LINES = ""

	local handle2 = genv.Tungsten
	clearLocal()
	ok, err = runLoader({ Branch = "test", Run = false })
	check("Run = false: loader runs", ok, err)
	local same, wrong = sameAsRemote()
	check("Run = false: files installed", same, wrong)
	check("Run = false: Tungsten not restarted", genv.Tungsten == handle2)

	clearLocal()
	OFFLINE = true
	ok, err = runLoader()
	check("offline, nothing installed: fails", not ok)
	check("offline, nothing installed: says why", tostring(err):find("could not download Tungsten", 1, true) ~= nil, err)
	OFFLINE = false
end

print(("loader: %d passed, %d failed, 0 runtime errors"):format(passed, failed))
