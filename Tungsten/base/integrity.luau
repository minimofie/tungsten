--[[
	Tungsten · base/integrity
	Start-up checks, shown under the console's welcome line and by
	/integrity:

	- files: every file in base/data/manifest is there, and Luau / text
	  files still have the size they shipped with. Only Tungsten's own
	  files are listed: plugin folders (plugins/<Folder>/), saved/, logs/
	  and the files Tungsten writes (settings.json, plugins.json) are never
	  checked (tools/make_manifest.py leaves them out)
	- executor: the Volt functions Tungsten uses exist (each missing one
	  names what stops working)
	- settings: settings.json loaded without dropping anything
	- data: the bundled class / property list is readable
	Plugins report their own state in the welcome line and /plugins.

		local report = Integrity.run()
		report.Ok, report.Problems ({ text }), report.Summary ("228 files · …")
		report.Checks = { { Name, Ok, Text, Problems } }
]]

local T = ...

local Integrity = {}

-- Volt functions Tungsten uses, and what needs each.
Integrity.Functions = {
	{ "gethui", "the window (it is hidden from the game)" },
	{ "cloneref", "safe references to services" },
	{ "getcustomasset", "icons" },
	{ "readfile", "settings, documentation, modules" },
	{ "writefile", "settings and logs" },
	{ "appendfile", "plugin files (api.files.append)" },
	{ "delfile", "plugin files (api.files.delete)" },
	{ "delfolder", "plugin folders (api.files.delete)" },
	{ "isfile", "loading files" },
	{ "listfiles", "console command files, documentation topics and plugins" },
	{ "isfolder", "the logs folder and plugin folders" },
	{ "makefolder", "the logs folder" },
	{ "loadfile", "loading modules and plugins" },
	{ "setclipboard", "Copy entries" },
	{ "getnilinstances", "Nil Instances in the explorer" },
	{ "getloadedmodules", "the loadedmodules search" },
	{ "gethiddenproperty", "hidden properties" },
	{ "sethiddenproperty", "editing hidden properties" },
	{ "getproperties", "properties newer than the bundled list" },
	{ "identifyexecutor", "the executor name in the welcome line" },
	{ "getgenv", "replacing an earlier run, the shared remote-block hook" },
	{ "compareinstances", "matching objects behind cloned references" },
	{ "saveinstance", "Save to File and /save" },
	{ "decompile", "Save Script, /decompile and the script viewer's Source" },
	{ "getscriptbytecode", "Save Bytecode" },
	{ "getscriptclosure", "Dump Functions and the script viewer" },
	{ "fireclickdetector", "Fire ClickDetector" },
	{ "fireproximityprompt", "Fire ProximityPrompt" },
	{ "firetouchinterest", "Fire TouchInterest" },
	{ "hookmetamethod", "Block remote" },
	{ "getnamecallmethod", "Block remote" },
	{ "checkcaller", "Block remote (your own calls still go through)" },
	{ "newcclosure", "Block remote" },
	-- the prime plugins (Plugins stage); dotted names are library functions
	{ "getsenv", "script viewer: a running script's globals" },
	{ "getrunningscripts", "script viewer: is a script running" },
	{ "getscripthash", "script viewer: a script's hash" },
	{ "getfunctionhash", "script viewer: a function's hash" },
	{ "iscclosure", "script viewer: C or Luau function" },
	{ "isexecutorclosure", "script viewer: made by the game or the executor" },
	{ "isreadonly", "script viewer: read-only tables" },
	{ "getrawmetatable", "script viewer: a table's metatable" },
	{ "debug.getinfo", "script viewer: a function's parameters and upvalue count" },
	{ "debug.getconstants", "script viewer: constants" },
	{ "debug.getupvalues", "script viewer: upvalues" },
	{ "debug.getprotos", "script viewer: nested functions" },
	{ "filtergc", "script viewer: references of constants and upvalues, a script's running functions" },
	{ "getgc", "script viewer: a script's running functions (when filtergc finds none)" },
	{ "debug.setconstant", "script viewer: changing constants" },
	{ "debug.setupvalue", "script viewer: changing upvalues" },
	{ "setreadonly", "script viewer: changing read-only tables (asked first)" },
}

local TEXT = { luau = true, md = true, json = true, txt = true }

local function checkFiles()
	local check = { Name = "files", Ok = true, Problems = {} }
	local ok, manifest = pcall(T.import, "base/data/manifest")
	if not ok or type(manifest) ~= "table" then
		check.Ok = false
		check.Text = "no file list (base/data/manifest.luau)"
		table.insert(check.Problems, check.Text)
		return check
	end
	local total, missing, changed = 0, {}, {}
	for rel, size in manifest do
		total += 1
		local path = T.Root .. "/" .. rel
		local present = false
		pcall(function()
			present = isfile(path)
		end)
		if not present then
			table.insert(missing, rel)
		else
			local extension = rel:match("%.(%w+)$")
			if extension and TEXT[extension] then
				local okRead, content = pcall(readfile, path)
				if okRead and type(content) == "string" and #content ~= size then
					-- Windows line endings add a byte per line; allow for them.
					local _, newlines = content:gsub("\r\n", "")
					if #content - newlines ~= size then
						table.insert(changed, rel)
					end
				end
			end
		end
	end
	table.sort(missing)
	table.sort(changed)
	check.Total = total
	check.Missing = missing
	check.Changed = changed
	for _, rel in missing do
		table.insert(check.Problems, "missing " .. rel)
	end
	for _, rel in changed do
		table.insert(check.Problems, "changed " .. rel)
	end
	check.Ok = #missing == 0
	check.Text = ("%d files%s%s"):format(
		total - #missing,
		if #missing > 0 then (" · %d missing"):format(#missing) else "",
		if #changed > 0 then (" · %d changed"):format(#changed) else ""
	)
	return check
end

local function checkFunctions()
	local check = { Name = "executor", Ok = true, Problems = {} }
	local env = getfenv(1)
	local have = 0
	for _, entry in Integrity.Functions do
		local name = entry[1]
		local head, rest = name:match("^(%w+)%.(%w+)$")
		local fn
		if head then
			-- a library function, e.g. debug.getconstants
			local lib = (env :: any)[head]
			fn = if type(lib) == "table" then lib[rest] else nil
		else
			fn = (env :: any)[name]
			if fn == nil and type(getgenv) == "function" then
				local okGenv, genv = pcall(getgenv)
				fn = if okGenv and type(genv) == "table" then genv[name] else nil
			end
		end
		if type(fn) == "function" then
			have += 1
		else
			table.insert(check.Problems, ("%s is missing · %s won't work"):format(entry[1], entry[2]))
		end
	end
	check.Ok = #check.Problems == 0
	check.Text = ("%d/%d executor functions"):format(have, #Integrity.Functions)
	return check
end

local function checkSettings()
	local check = { Name = "settings", Ok = true, Problems = {} }
	local ok, Settings = pcall(T.import, "base/settings")
	local problems = if ok and type(Settings.Problems) == "table" then Settings.Problems else {}
	for _, text in problems do
		table.insert(check.Problems, text)
	end
	check.Ok = #problems == 0
	check.Text = if check.Ok then "settings ok" else ("settings: %d fixed"):format(#problems)
	return check
end

local function checkData()
	local check = { Name = "data", Ok = true, Problems = {} }
	local ok, Api = pcall(T.import, "base/explorer/api")
	if not ok or type(Api) ~= "table" or not Api.class("Part") then
		check.Ok = false
		check.Text = "class data unreadable"
		table.insert(check.Problems, "base/data/api.luau couldn't be read: " .. tostring(if ok then "no Part class" else Api))
		return check
	end
	check.Text = "class data " .. tostring(Api.Version)
	return check
end

function Integrity.run()
	local checks = { checkFiles(), checkFunctions(), checkSettings(), checkData() }
	local problems, parts = {}, {}
	local ok = true
	for _, check in checks do
		table.insert(parts, check.Text)
		for _, text in check.Problems do
			table.insert(problems, text)
		end
		-- Missing optional executor functions are warnings, not failures.
		if not check.Ok and check.Name ~= "executor" then
			ok = false
		end
	end
	local report = {
		Ok = ok,
		Clean = #problems == 0,
		Checks = checks,
		Problems = problems,
		Summary = table.concat(parts, " · "),
	}
	Integrity.Last = report
	return report
end

return Integrity
