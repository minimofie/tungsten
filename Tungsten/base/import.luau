--[[
	Tungsten · base/import
	Loads modules from the local Tungsten folder exactly once.

	Every module file receives the shared context table `T` as `...`
	and returns its module value:

		local T = ...
		local Theme = T.import("base/theme")
		return MyModule
]]

return function(root: string, T)
	local cache = {}
	local loading = {}

	local function import(path: string)
		local cached = cache[path]
		if cached ~= nil then
			return cached
		end

		if loading[path] then
			error(("circular import of '%s'"):format(path), 2)
		end

		local file = ("%s/%s.luau"):format(root, path)
		if not isfile(file) then
			error(("module not found: %s"):format(file), 2)
		end

		local chunk, compileError = loadfile(file)
		if not chunk then
			error(("compile error in %s: %s"):format(file, tostring(compileError)), 2)
		end

		loading[path] = true
		local ok, result = xpcall(chunk, debug.traceback, T)
		loading[path] = nil

		if not ok then
			error(("error while loading %s:\n%s"):format(file, tostring(result)), 2)
		end

		if result == nil then
			result = true
		end
		cache[path] = result

		if T.Log then
			T.Log.debug("import", "loaded " .. path)
		end
		return result
	end

	return import
end
