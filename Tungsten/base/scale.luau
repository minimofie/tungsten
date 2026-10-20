--[[
	Tungsten · base/scale
	How big the window is, like resizing it: the window (and the explorer
	joined to it, a share of its width) is BaseSize × the scale. Text,
	icons, buttons, rows and popups stay their normal size; layouts that
	stretch (lists, panes, the path bar, the console) get more room.

		Scale.get() / Scale.size()  -> the stored scale (the window's multiplier)
		Scale.windowSize()          -> BaseSize × the scale

	Drawing is always 1:1 now: Scale.factor() is 1, so code that turns
	on-screen measurements into layout offsets (Scale.toLayout /
	toScreen, Create.layoutSize / toLocal, Overlay.toLayout) keeps
	working and changes nothing.

	The scale only changes when you change it (Plugins › tungsten, /scale,
	/setting Scale). A new value is capped to what fits the screen at that
	moment (window and explorer together); a screen that gets smaller
	later never changes it.
]]

local T = ...
local signal = T.import("base/signal")
local Settings = T.import("base/settings")

local Scale = {}
Scale.Min = 0.75
Scale.Max = 1.75
Scale.Step = 0.05
Scale.KeyStep = 0.1
Scale.BaseSize = Vector2.new(760, 460) -- the window's layout size (its size at scale 1)
Scale.Margin = 8 -- gap kept from screen edges
Scale.SideShare = 200 / 760 -- explorer width as a share of the window's width (200 px at scale 1)
Scale.SideGap = 0 -- pixels between the window and the explorer (none: they join)
Scale.Changed = signal.new() -- (factor)

-- Largest scale whose window fits the current screen.
local fitLimit = Scale.Max

local function round2(value: number): number
	return math.floor(value * 100 + 0.5) / 100
end

local function normalize(value: number): number
	value = math.clamp(value, Scale.Min, Scale.Max)
	value = math.floor(value / Scale.Step + 0.5) * Scale.Step
	return round2(value)
end

-- The stored scale.
function Scale.get(): number
	return normalize(Settings.get("Scale"))
end

-- The window's size multiplier (the stored scale).
function Scale.size(): number
	return Scale.get()
end

-- What the UI is drawn at: always 1 (scale makes the window bigger, not
-- its contents).
function Scale.factor(): number
	return 1
end

-- Older name, kept for callers that read the scale in use.
Scale.effective = Scale.get -- the scale shown to you (percent in settings, /scale)

-- Largest scale that fits the screen right now (what + and /scale stop at).
function Scale.limit(): number
	return fitLimit
end

function Scale.set(value: number): number
	assert(type(value) == "number" and value == value, "Scale.set expects a number")
	local before = Scale.get()
	value = math.min(normalize(value), fitLimit)
	Settings.set("Scale", value)
	local after = Scale.get()
	if after ~= before then
		T.Log.info("scale", ("scale %.2f -> %.2f"):format(before, after))
		Scale.Changed:Fire(after)
	end
	return after
end

-- Step from the scale in use.
function Scale.step(delta: number): number
	return Scale.set(Scale.get() + delta)
end

-- On-screen pixels <-> layout pixels (numbers, Vector2s or UDim2-free math).
function Scale.toLayout(value: any): any
	return value / Scale.factor()
end

function Scale.toScreen(value: any): any
	return value * Scale.factor()
end

-- Explorer width for a window width.
function Scale.sideWidth(windowWidth: number): number
	return math.floor(windowWidth * Scale.SideShare + 0.5)
end

-- Window + gap + explorer.
function Scale.footprint(size: Vector2): Vector2
	return Vector2.new(size.X + Scale.SideGap + Scale.sideWidth(size.X), size.Y)
end

-- Called by the window whenever the screen size is known or changes. Only
-- the limit for the next change moves; the scale in use never does.
function Scale.setViewport(viewport: Vector2)
	local usableX = viewport.X - Scale.Margin * 2 - Scale.SideGap
	local usableY = viewport.Y - Scale.Margin * 2
	local raw = math.min(usableX / (Scale.BaseSize.X * (1 + Scale.SideShare)), usableY / Scale.BaseSize.Y)
	-- Round down to a whole step so the limit itself always fits.
	local limit = math.floor(raw / Scale.Step + 1e-6) * Scale.Step
	fitLimit = round2(math.clamp(limit, Scale.Min, Scale.Max))
end

-- The window's size at the scale in use (BaseSize × the scale).
function Scale.windowSize(): Vector2
	local scale = Scale.get()
	return Vector2.new(math.floor(Scale.BaseSize.X * scale + 0.5), math.floor(Scale.BaseSize.Y * scale + 0.5))
end

-- Store the normalized value in case settings.json held an odd number.
Settings.set("Scale", Scale.get())

return Scale
