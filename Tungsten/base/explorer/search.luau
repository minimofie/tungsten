--[[
	Tungsten · base/explorer/search
	The explorer's search: a query becomes a test for instances.

		local query, problem = Search.parse('isa:BasePart door rad:50')
		query.Test(instance) -> boolean
		Search.run(query, onMatch, onDone) -> handle (handle:Cancel())

	Terms (separated by spaces, all must match)
		door            name contains "door" (any case)
		"Door"          name is exactly Door (case matters)
		isa:BasePart    the class is or inherits from BasePart
		class:Part      the class is exactly Part
		remotes         RemoteEvent, RemoteFunction, UnreliableRemoteEvent
		bindables       BindableEvent, BindableFunction
		scripts         LocalScript, ModuleScript, Script
		players         Player objects
		loadedmodules   ModuleScripts that have been required
		nil             objects outside the game (parent is nil)
		rad:50          parts within 50 studs of your character
		!term           anything that does not match the term
	Filter words may also be written with a / (/remotes).
]]

local T = ...
local Classes = T.import("base/data/classes")

local Search = {}
Search.MaxResults = 3000
Search.ChunkSize = 2500 -- instances checked before yielding a frame

local FILTER_WORDS = {
	remotes = true,
	bindables = true,
	scripts = true,
	players = true,
	loadedmodules = true,
	["nil"] = true,
}
Search.FilterWords = { "remotes", "bindables", "scripts", "players", "loadedmodules", "nil", "isa:", "class:", "rad:" }

local function isA(obj: Instance, class: string): boolean
	local ok, result = pcall(function()
		return obj:IsA(class)
	end)
	return ok and result == true
end

local function nameOf(obj: Instance): string
	local ok, name = pcall(function()
		return obj.Name
	end)
	return if ok then tostring(name) else ""
end

local function classOf(obj: Instance): string
	local ok, class = pcall(function()
		return obj.ClassName
	end)
	return if ok then tostring(class) else ""
end

-- "basepart" -> "BasePart" when Tungsten knows the class.
local knownClasses = nil
local function properClass(text: string): string
	if not knownClasses then
		knownClasses = {}
		for _, name in Classes.list() do
			knownClasses[name:lower()] = name
		end
	end
	return knownClasses[text:lower()] or text
end

-- Splits on spaces, keeping "quoted text" (with its quotes) together.
local function words(text: string): { string }
	local list = {}
	local position = 1
	local length = #text
	while position <= length do
		local start = text:find("%S", position)
		if not start then
			break
		end
		local stop
		local negate = text:sub(start, start) == "!" and 1 or 0
		if text:sub(start + negate, start + negate) == '"' then
			local close = text:find('"', start + negate + 1, true)
			stop = if close then close else length
		else
			stop = (text:find("%s", start) or (length + 1)) - 1
		end
		table.insert(list, text:sub(start, stop))
		position = stop + 1
	end
	return list
end
Search.words = words

local function characterRoot(): BasePart?
	local ok, root = pcall(function()
		local players = game:GetService("Players")
		local character = players.LocalPlayer and players.LocalPlayer.Character
		if not character then
			return nil
		end
		return character:FindFirstChild("HumanoidRootPart") or character.PrimaryPart
	end)
	return if ok then root else nil
end

-- Set of objects outside the game (nil roots and everything under them).
local function nilSet(): { [Instance]: boolean }
	local set = {}
	if getnilinstances == nil then
		return set
	end
	local ok, list = pcall(getnilinstances)
	if not ok or type(list) ~= "table" then
		return set
	end
	for _, obj in list do
		if typeof(obj) == "Instance" then
			set[obj] = true
		end
	end
	return set
end

local function isNilParented(obj: Instance, roots: { [Instance]: boolean }): boolean
	local current: Instance? = obj
	local guard = 0
	while current and guard < 400 do
		guard += 1
		if roots[current] then
			return true
		end
		local ok, parent = pcall(function()
			return (current :: Instance).Parent
		end)
		if not ok then
			return false
		end
		if parent == nil then
			return current ~= game
		end
		current = parent
	end
	return false
end

-- One term -> test function, or nil + problem.
local function term(word: string, context): (((Instance) -> boolean)?, string?)
	local lower = word:lower()
	local bare = lower:gsub("^/", "")
	local quoted = word:match('^"(.*)"$') or word:match('^"(.*)$')
	if quoted then
		return function(obj)
			return nameOf(obj) == quoted
		end
	end
	local key, value = word:match("^/?(%a+):(.*)$")
	if key then
		key = key:lower()
		if key == "isa" then
			if value == "" then
				return nil, "isa: needs a class, e.g. isa:BasePart"
			end
			local class = properClass(value)
			return function(obj)
				return isA(obj, class)
			end
		elseif key == "class" then
			if value == "" then
				return nil, "class: needs a class, e.g. class:Part"
			end
			local wanted = value:lower()
			return function(obj)
				return classOf(obj):lower() == wanted
			end
		elseif key == "rad" then
			local radius = tonumber(value)
			if not radius then
				return nil, "rad: needs a number of studs, e.g. rad:50"
			end
			local root = characterRoot()
			if not root then
				return nil, "rad: needs your character in the game"
			end
			local ok, center = pcall(function()
				return root.Position
			end)
			if not ok then
				return nil, "rad: can't read your character's position"
			end
			return function(obj)
				if not isA(obj, "BasePart") then
					return false
				end
				local okPos, position = pcall(function()
					return (obj :: BasePart).Position
				end)
				return okPos and (position - center).Magnitude <= radius
			end
		end
		-- Not a filter: plain text containing a colon.
	end
	if FILTER_WORDS[bare] then
		if bare == "remotes" then
			return function(obj)
				return isA(obj, "RemoteEvent") or isA(obj, "RemoteFunction") or isA(obj, "UnreliableRemoteEvent")
			end
		elseif bare == "bindables" then
			return function(obj)
				return isA(obj, "BindableEvent") or isA(obj, "BindableFunction")
			end
		elseif bare == "scripts" then
			return function(obj)
				return isA(obj, "LuaSourceContainer")
			end
		elseif bare == "players" then
			return function(obj)
				return isA(obj, "Player")
			end
		elseif bare == "loadedmodules" then
			if getloadedmodules == nil then
				return nil, "loadedmodules isn't available here"
			end
			local set = {}
			local ok, list = pcall(getloadedmodules)
			if ok and type(list) == "table" then
				for _, module in list do
					set[module] = true
				end
			end
			return function(obj)
				return set[obj] == true
			end
		elseif bare == "nil" then
			context.WantsNil = true
			local roots = context.NilRoots
			return function(obj)
				return isNilParented(obj, roots)
			end
		end
	end
	local needle = lower
	return function(obj)
		return nameOf(obj):lower():find(needle, 1, true) ~= nil
	end
end

--[[
	Search.parse(text) -> query | nil, problem
	query = { Text, Test(obj), Terms, IncludesNil }
	An empty text gives nil and no problem.
]]
function Search.parse(text: string)
	text = tostring(text or "")
	local list = words(text)
	if #list == 0 then
		return nil, nil
	end
	local context = { NilRoots = nilSet(), WantsNil = false }
	local tests = {}
	for _, word in list do
		local negate = word:sub(1, 1) == "!" and #word > 1
		local body = if negate then word:sub(2) else word
		local test, problem = term(body, context)
		if not test then
			return nil, problem
		end
		table.insert(tests, if negate then function(obj) return not test(obj) end else test)
	end
	local query = {
		Text = text,
		Terms = list,
		NilRoots = context.NilRoots,
		Test = function(obj: Instance): boolean
			for _, test in tests do
				local ok, result = pcall(test, obj)
				if not ok or not result then
					return false
				end
			end
			return true
		end,
	}
	return query, nil
end

-- A query every object matches (the start for a filter without search words).
function Search.everything()
	return {
		Text = "",
		Terms = {},
		NilRoots = nilSet(),
		Test = function()
			return true
		end,
	}
end

-- The query with one more test that must also pass (the explorer filter).
function Search.combine(query, test: ((Instance) -> boolean)?)
	if test == nil then
		return query
	end
	local combined = table.clone(query)
	local base = query.Test
	combined.Test = function(obj: Instance): boolean
		if not base(obj) then
			return false
		end
		local ok, result = pcall(test, obj)
		return ok and result == true
	end
	return combined
end

--[[
	Search.run(query, opts) -> handle
	opts.OnMatch(obj)      for each match (stops at MaxResults)
	opts.OnDone(count, capped)
	opts.Skip(obj)         true to leave out an object and its descendants
	Checks the game and the nil instances a chunk at a time, so big games
	don't freeze. handle:Cancel() stops it.
]]
function Search.run(query, opts)
	local handle = { Cancelled = false, Done = false, Count = 0, Capped = false }
	function handle:Cancel()
		self.Cancelled = true
	end
	task.spawn(function()
		local sources = {}
		local ok, all = pcall(function()
			return game:GetDescendants()
		end)
		if ok then
			table.insert(sources, all)
		end
		local nilList = {}
		for root in query.NilRoots do
			table.insert(nilList, root)
			local okDesc, descendants = pcall(function()
				return root:GetDescendants()
			end)
			if okDesc then
				for _, item in descendants do
					table.insert(nilList, item)
				end
			end
		end
		table.insert(sources, nilList)

		local checked = 0
		for _, list in sources do
			for _, obj in list do
				if handle.Cancelled then
					return
				end
				checked += 1
				if checked % Search.ChunkSize == 0 then
					task.wait()
					if handle.Cancelled then
						return
					end
				end
				if query.Test(obj) and (opts.Skip == nil or not opts.Skip(obj)) then
					handle.Count += 1
					local okMatch, err = pcall(opts.OnMatch, obj)
					if not okMatch then
						T.Log.warn("explorer", "search match failed: " .. tostring(err))
					end
					if handle.Count >= Search.MaxResults then
						handle.Capped = true
						break
					end
				end
			end
			if handle.Capped then
				break
			end
		end
		handle.Done = true
		if opts.OnDone and not handle.Cancelled then
			pcall(opts.OnDone, handle.Count, handle.Capped)
		end
	end)
	return handle
end

-- Matches right away (no yielding), for /find and plugins. Returns the
-- list and whether it stopped at the limit.
function Search.collect(query, limit: number?, skip: ((Instance) -> boolean)?): ({ Instance }, boolean)
	limit = limit or Search.MaxResults
	local results = {}
	local ok, all = pcall(function()
		return game:GetDescendants()
	end)
	local function scan(list)
		for _, obj in list do
			if query.Test(obj) and (skip == nil or not skip(obj)) then
				table.insert(results, obj)
				if #results >= (limit :: number) then
					return true
				end
			end
		end
		return false
	end
	if ok and scan(all) then
		return results, true
	end
	for root in query.NilRoots do
		if scan({ root }) then
			return results, true
		end
		local okDesc, descendants = pcall(function()
			return root:GetDescendants()
		end)
		if okDesc and scan(descendants) then
			return results, true
		end
	end
	return results, false
end

return Search
