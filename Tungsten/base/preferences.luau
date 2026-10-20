--[[
	Tungsten · base/preferences
	Every setting a person can change, in one place: the "tungsten" entry
	of the Plugins tab shows these (it isn't a plugin, just where the
	program's own settings live). Each item reads and writes through the
	same code the commands use, so a change here and a change from a
	command are the same thing.

		Preferences.groups()          -> { { Title, Items = { item } } }
		Preferences.get(id) ; Preferences.set(id, value) ; Preferences.reset(id)
		Preferences.resetAll()
		Preferences.Changed           -- (id, value) when any of them changes

	An item: Id, Kind ("toggle" | "number" | "stepper" | "color" | "choice"
	| "action"), Text, Hint, and per kind Min / Max / Step / Decimals
	(number), Step(direction) / CanStep / Format (stepper), Options
	(choice), Run (action), Setting (the settings key it stores in).

	The page keeps to a few: window size, tooltips, the command bar key,
	the explorer's sort order and Reset all. The rest have their own
	place (accent: /accent; console options: the output's right-click
	menu and /traceback; explorer properties: the ⋯ menu; the split: drag
	the line; tabs: the side bar's right-click menu). Reset all still puts
	every one of them back.
]]

local T = ...
local signal = T.import("base/signal")
local Settings = T.import("base/settings")
local Scale = T.import("base/scale")

local Preferences = {}
Preferences.Changed = signal.new() -- (id, value)

local KEY_OPTIONS = {
	{ Value = "Quote", Text = "'  (apostrophe)" },
	{ Value = "BackSlash", Text = "\\  (backslash)" },
	{ Value = "Semicolon", Text = ";  (semicolon)" },
	{ Value = "Backquote", Text = "`  (backquote)" },
	{ Value = "RightAlt", Text = "Right Alt" },
	{ Value = "F6", Text = "F6" },
	{ Value = "F7", Text = "F7" },
	{ Value = "F8", Text = "F8" },
	{ Value = "F9", Text = "F9" },
}

local function setting(key: string)
	return function()
		return Settings.get(key)
	end, function(value)
		return Settings.set(key, value)
	end
end

local function item(spec)
	if spec.Setting and not spec.Get then
		spec.Get, spec.Set = setting(spec.Setting)
	end
	return spec
end

local GROUPS = {
	{
		Title = "Window",
		Items = {
			item({
				Id = "scale", Kind = "stepper", Text = "Window size", Hint = "smaller / bigger · also /scale",
				Setting = "Scale",
				Get = function()
					return Scale.effective()
				end,
				Set = function(value)
					Scale.set(value)
					return true
				end,
				Step = function(direction: number)
					return Scale.step(direction * Scale.KeyStep)
				end,
				CanStep = function(direction: number)
					if direction < 0 then
						return Scale.effective() > Scale.Min + 1e-6
					end
					return Scale.effective() < math.min(Scale.Max, Scale.limit()) - 1e-6
				end,
				Format = function(value: number)
					return ("%d%%"):format(math.floor(value * 100 + 0.5))
				end,
			}),
			item({ Id = "tooltips", Kind = "toggle", Text = "Tooltips", Hint = "labels when you hover tab icons and buttons", Setting = "ShowTooltips" }),
		},
	},
	{
		Title = "Command bar",
		Items = {
			item({ Id = "barKey", Kind = "choice", Text = "Key that opens it", Hint = "works anywhere in the game · also /bar key", Options = KEY_OPTIONS, Setting = "CommandBarKey" }),
		},
	},
	{
		Title = "Explorer",
		Items = {
			item({ Id = "sort", Kind = "toggle", Text = "Services first, then A–Z", Hint = "off: the game's own order · also /explorer sort", Setting = "ExplorerSort" }),
		},
	},
	{
		Title = "Everything",
		Items = {
			item({
				Id = "resetAll", Kind = "action", Text = "Reset all settings", Hint = "every setting back to how Tungsten ships, also the ones changed elsewhere", Button = "Reset…", Danger = true,
				Run = function()
					T.Prompt.confirm({
						Title = "Reset all settings?",
						Text = "Every setting goes back to how Tungsten ships.",
						ConfirmText = "Reset",
						Danger = true,
						OnConfirm = function()
							Preferences.resetAll()
						end,
					})
				end,
			}),
		},
	},
}

local byId = {}
for _, group in GROUPS do
	for _, entry in group.Items do
		byId[entry.Id] = entry
	end
end

function Preferences.groups(): { any }
	return GROUPS
end

function Preferences.item(id: string)
	return byId[id]
end

function Preferences.get(id: string): any
	local entry = byId[id]
	return if entry and entry.Get then entry.Get() else nil
end

function Preferences.set(id: string, value: any): boolean
	local entry = byId[id]
	if not entry or not entry.Set then
		return false
	end
	local ok, result = pcall(entry.Set, value)
	return ok and result ~= false
end

function Preferences.reset(id: string): boolean
	local entry = byId[id]
	if not entry or not entry.Setting then
		return false
	end
	return Preferences.set(id, Settings.defaults()[entry.Setting])
end

-- Every saved setting back to how Tungsten ships, the ones without a row
-- here included (accent color, console and explorer options, the split,
-- tab order and hidden tabs).
function Preferences.resetAll(): number
	local defaults = Settings.defaults()
	local count = 0
	for key, value in defaults do
		if not Settings.isSession(key) then
			local ok = pcall(function()
				if key == "Scale" then
					Scale.set(value)
				elseif key == "ConsoleGameOutput" and T.Console then
					T.Console.setGameOutput(value)
				elseif key == "ExplorerSplit" and T.Explorer then
					T.Explorer.setSplit(value)
				elseif key == "HiddenTabs" then
					for _, id in table.clone(Settings.get("HiddenTabs") or {}) do
						T.Registry.setHidden(id, false)
					end
					Settings.set("HiddenTabs", {})
				else
					Settings.set(key, value)
				end
			end)
			if ok then
				count += 1
			end
		end
	end
	if T.Tabs then
		T.Tabs:Rebuild()
	end
	return count
end

-- The item an changed settings key belongs to.
local bySetting = {}
for _, entry in byId do
	if entry.Setting then
		bySetting[entry.Setting] = entry
	end
end

T.Bin:Add(Settings.Changed:Connect(function(key, value)
	local entry = bySetting[key]
	if entry then
		Preferences.Changed:Fire(entry.Id, value)
	end
end))
T.Bin:Add(function()
	Preferences.Changed:DisconnectAll()
end)

return Preferences
