--[[
	Tungsten · base/settings
	Persistent Tungsten settings, stored in Tungsten/base/settings.json
	through base/datastore (the same store plugins' settings use).
	Unknown keys and values of the wrong type are dropped on load.

	Only preferences are saved. Session keys (which tab is open, whether
	the explorer is collapsed, folded property categories, the explorer
	filter) work like any other setting while Tungsten runs but are never
	written to the file and start from their defaults every time, so the
	UI always opens as a clean slate.
]]

local T = ...
local signal = T.import("base/signal")
local DataStore = T.import("base/datastore")

local PATH = T.Root .. "/base/settings.json"
local store = DataStore.open(PATH, { Name = "settings", Backup = true })

local DEFAULTS = {
	Scale = 1,
	Accent = { 240, 150, 60 },
	LastTab = "console", -- session only
	ConsoleGameOutput = false, -- mirror the game's print/warn as [game] lines
	ConsoleTimestamps = false, -- show the time before each console line
	ConsoleTraceback = false, -- print the traceback under code errors
	ExplorerOpen = true, -- explorer panel shown beside the window (session only)
	ExplorerSort = true, -- services first, then names A-Z (off: game order)
	ExplorerSplit = 0.5, -- the tree's share of the explorer's height (the rest: properties)
	PropertyDecimals = 3, -- decimals shown for numbers in the properties panel
	PropertiesDeprecated = false, -- show deprecated properties
	PropertiesHidden = false, -- show hidden / not scriptable properties
	PropertiesCollapsed = {}, -- names of closed property categories (session only)
	ExplorerFilter = {}, -- { Only = { group ids }, Classes = { … }, Hide = { … } } (session only)
	TabOrder = {}, -- tab ids in the user's order (Move up / down)
	HiddenTabs = {}, -- tabs the user hid
	CommandBarKey = "Quote", -- KeyCode name that opens the command bar (' by default)
	ShowTooltips = true, -- hover tooltips
}

-- Kept in memory only: never saved, back to the default at every start.
local SESSION = {
	LastTab = true,
	ExplorerOpen = true,
	PropertiesCollapsed = true,
	ExplorerFilter = true,
}

-- Extra validation beyond "same type as the default".
local VALIDATORS = {
	ExplorerSplit = function(value)
		return value == value and value >= 0.05 and value <= 0.95
	end,
	PropertyDecimals = function(value)
		return value == math.floor(value) and value >= 0 and value <= 8
	end,
	ExplorerFilter = function(value)
		for key, list in value do
			if (key ~= "Only" and key ~= "Classes" and key ~= "Hide") or type(list) ~= "table" then
				return false
			end
			for _, item in list do
				if type(item) ~= "string" then
					return false
				end
			end
		end
		return true
	end,
	TabOrder = function(value)
		for key, id in value do
			if type(key) ~= "number" or type(id) ~= "string" then
				return false
			end
		end
		return true
	end,
	HiddenTabs = function(value)
		for key, id in value do
			if type(key) ~= "number" or type(id) ~= "string" then
				return false
			end
		end
		return true
	end,
	CommandBarKey = function(value)
		return value:match("^[%a%d]+$") ~= nil
	end,
	PropertiesCollapsed = function(value)
		for key, name in value do
			if type(key) ~= "number" or type(name) ~= "string" then
				return false
			end
		end
		return #value <= 200
	end,
	Scale = function(value)
		return value == value and value > 0 and value < 10
	end,
	Accent = function(value)
		if #value ~= 3 then
			return false
		end
		for _, channel in value do
			if type(channel) ~= "number" or channel < 0 or channel > 255 then
				return false
			end
		end
		return true
	end,
}

local Settings = {}
Settings.Path = PATH
Settings.Problems = {} -- what load() had to drop or reset (integrity check)
Settings.Changed = signal.new() -- (key, value)

local data = {}

local function copy(value)
	if type(value) == "table" then
		return table.clone(value)
	end
	return value
end

local function isValid(key: string, value: any): boolean
	local default = DEFAULTS[key]
	if default == nil or type(value) ~= type(default) then
		return false
	end
	local validator = VALIDATORS[key]
	return validator == nil or validator(value)
end

-- The values that are written: everything but the session keys.
local function saved(): { [string]: any }
	local out = {}
	for key, value in data do
		if not SESSION[key] then
			out[key] = value
		end
	end
	return out
end

local function queueSave()
	store:queue(saved)
end

-- Write now if a change is waiting.
function Settings.flush()
	store:flush()
end

function Settings.load()
	data = {}
	for key, value in DEFAULTS do
		data[key] = copy(value)
	end

	local decoded, problem = store:read()
	if decoded then
		for key, value in decoded do
			if SESSION[key] then
				continue -- an older file saved it; it starts fresh now
			elseif key == "CommandBarKey" and value == "BackSlash" then
				continue -- the old default; the bar opens with ' now
			elseif isValid(key, value) then
				data[key] = value
			else
				T.Log.warn("settings", ("ignored invalid setting '%s'"):format(tostring(key)))
				table.insert(Settings.Problems, ("ignored invalid setting '%s'"):format(tostring(key)))
			end
		end
	elseif problem then
		T.Log.warn("settings", "settings.json could not be read; defaults used (old file kept as settings.json.bak)")
		table.insert(Settings.Problems, "settings.json could not be read; defaults used")
	end

	-- Write the checked values back at once (drops what was ignored).
	store:write(saved())
	T.Bin:Add(Settings.flush)
	T.Log.info("settings", "loaded")
end

function Settings.get(key: string): any
	return copy(data[key])
end

function Settings.set(key: string, value: any): boolean
	if not isValid(key, value) then
		T.Log.warn("settings", ("rejected value for '%s': %s"):format(key, tostring(value)))
		return false
	end
	local current = data[key]
	if type(value) ~= "table" and current == value then
		return true
	end
	data[key] = copy(value)
	if not SESSION[key] then
		queueSave()
	end
	Settings.Changed:Fire(key, copy(value))
	return true
end

-- Is this key kept for the session only (never saved)?
function Settings.isSession(key: string): boolean
	return SESSION[key] == true
end

function Settings.defaults(): { [string]: any }
	local result = {}
	for key, value in DEFAULTS do
		result[key] = copy(value)
	end
	return result
end

return Settings
