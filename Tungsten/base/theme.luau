--[[
	Tungsten · base/theme
	Colors, fonts and sizes. Colors are bound to instances by key so a
	later accent change recolors everything already on screen:

		Theme.bind(frame, "BackgroundColor3", "Surface")
		Theme.bind(icon, "ImageColor3", "Accent", 0.15) -- tweened
]]

local T = ...
local signal = T.import("base/signal")
local Settings = T.import("base/settings")
local TweenService = T.import("base/services").TweenService

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local Theme = {}
Theme.Changed = signal.new() -- (key, color)

Theme.Colors = {
	Background = rgb(27, 27, 30),
	Chrome = rgb(21, 21, 24), -- title bar, side bar, pill
	Surface = rgb(35, 35, 39),
	SurfaceHover = rgb(44, 44, 49),
	SurfaceActive = rgb(53, 53, 59),
	Border = rgb(43, 43, 49),
	BorderStrong = rgb(64, 64, 72),
	Text = rgb(232, 232, 236),
	TextDim = rgb(160, 160, 169),
	TextMuted = rgb(106, 106, 115),
	Accent = rgb(240, 150, 60),
	AccentSoft = rgb(0, 0, 0), -- derived
	AccentHover = rgb(0, 0, 0), -- derived
	OnAccent = rgb(24, 22, 20),
	Danger = rgb(232, 92, 92),
	Success = rgb(96, 200, 128),
	Warning = rgb(236, 196, 84),
	Info = rgb(110, 168, 240),
	DangerSoft = rgb(240, 160, 160), -- light red: inside something deleted (frozen explorer)
	Moved = rgb(130, 190, 250), -- light blue: moved somewhere else (frozen explorer)
	Selection = rgb(0, 0, 0), -- derived (selected rows, text selection)

	-- Code editor
	SyntaxText = rgb(220, 220, 226),
	SyntaxKeyword = rgb(242, 116, 132),
	SyntaxBuiltin = rgb(110, 196, 240),
	SyntaxString = rgb(166, 222, 128),
	SyntaxNumber = rgb(246, 190, 96),
	SyntaxComment = rgb(112, 112, 122),
	SyntaxOperator = rgb(186, 186, 196),
	SyntaxFunction = rgb(240, 216, 128),
	SyntaxProperty = rgb(132, 168, 238),
	SyntaxLiteral = rgb(246, 150, 96),
	SyntaxSelf = rgb(214, 140, 230),
	EditorGutter = rgb(24, 24, 27),
	EditorLine = rgb(31, 31, 35),
}

Theme.Fonts = {
	Regular = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Regular),
	Medium = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Medium),
	Bold = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Bold),
	Mono = Font.new("rbxasset://fonts/families/RobotoMono.json", Enum.FontWeight.Regular),
}

-- Pixel sizes. These never change with the window scale setting.
Theme.Sizes = {
	Text = 13,
	TextSmall = 11,
	Title = 14,
	TitleBar = 34,
	PathBar = 38, -- strip under the title bar (path bar + its padding)
	Sidebar = 44,
	TabButton = 34,
	Icon = 16,
	Radius = 8,
	RadiusSmall = 6,
	Row = 24, -- list rows
	Control = 26, -- buttons, inputs, dropdowns
	MenuItem = 26,
	MenuHeader = 22,
	ScrollBar = 4,
	CodeText = 13,
	CodeLine = 18,
}

local function deriveAccent(accent: Color3)
	local colors = Theme.Colors
	colors.Accent = accent
	colors.AccentSoft = colors.Background:Lerp(accent, 0.18)
	colors.AccentHover = accent:Lerp(Color3.new(1, 1, 1), 0.14)
	colors.Selection = colors.Background:Lerp(accent, 0.3)
end

-- instance -> { [property] = colorKey }
-- Weak keys: destroyed popups and rows drop out on their own.
local bindings: { [Instance]: { [string]: string } } = setmetatable({}, { __mode = "k" }) :: any

function Theme.color(key: string): Color3
	local color = Theme.Colors[key]
	if not color then
		error(("unknown theme color '%s'"):format(tostring(key)), 2)
	end
	return color
end

function Theme.bind(instance: Instance, property: string, key: string, duration: number?)
	local color = Theme.color(key)
	local map = bindings[instance]
	if not map then
		map = {}
		bindings[instance] = map
	end
	map[property] = key

	if duration and duration > 0 then
		TweenService:Create(
			instance,
			TweenInfo.new(duration, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
			{ [property] = color }
		):Play()
	else
		(instance :: any)[property] = color
	end
end

function Theme.unbind(instance: Instance, property: string?)
	if property then
		local map = bindings[instance]
		if map then
			map[property] = nil
		end
	else
		bindings[instance] = nil
	end
end

-- Like bind, but also accepts a fixed Color3 (which is not re-themed).
function Theme.apply(instance: Instance, property: string, value: string | Color3, duration: number?)
	if typeof(value) == "Color3" then
		Theme.unbind(instance, property)
		if duration and duration > 0 then
			TweenService:Create(
				instance,
				TweenInfo.new(duration, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
				{ [property] = value }
			):Play()
		else
			(instance :: any)[property] = value
		end
	else
		Theme.bind(instance, property, value :: string, duration)
	end
end

-- Rich-text hex for a color key, e.g. "#F0963C".
function Theme.hex(key: string): string
	return "#" .. Theme.color(key):ToHex()
end

local function refresh()
	for instance, map in bindings do
		if instance.Parent == nil then
			bindings[instance] = nil
			continue
		end
		for property, key in map do
			pcall(function()
				(instance :: any)[property] = Theme.Colors[key]
			end)
		end
	end
end

function Theme.setColor(key: string, color: Color3)
	Theme.color(key)
	if key == "Accent" then
		deriveAccent(color)
	else
		Theme.Colors[key] = color
	end
	refresh()
	Theme.Changed:Fire(key, color)
end

local function accentFromSetting(value): Color3
	return rgb(value[1], value[2], value[3])
end

deriveAccent(accentFromSetting(Settings.get("Accent")))

T.Bin:Add(Settings.Changed:Connect(function(key, value)
	if key == "Accent" then
		Theme.setColor("Accent", accentFromSetting(value))
	end
end))

T.Bin:Add(function()
	table.clear(bindings)
end)

return Theme
