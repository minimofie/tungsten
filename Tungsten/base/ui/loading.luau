--[[
	Tungsten · base/ui/loading
	The splash screen shown when Tungsten starts, before the window or
	anything else appears: the brand icon, the name and a progress bar.
	It fades in (0.5 s), the bar fills over Loading.Duration seconds (3),
	stays full a moment (0.4 s), then the card fades out (0.6 s) and only
	then does the window open. Tungsten loads behind it.

		local splash = Loading.show()           -- the bar starts filling
		splash:Wait()                           -- until the full duration has passed
		splash:Finish()                         -- fades out (waits for it), removes itself
		splash:Step(0.4)                        -- (moves the bar by hand, for tests)
]]

local T = ...
local Theme = T.import("base/theme")
local Create = T.import("base/ui/create")
local Animate = T.import("base/ui/animate")
local Icons = T.import("base/data/icons")

local new = Create.new
local Sizes = Theme.Sizes

local WIDTH = 280
local HEIGHT = 132
local BAR_WIDTH = 200
local BAR_HEIGHT = 4

local Loading = {}
Loading.__index = Loading
Loading.Duration = 3 -- seconds the progress bar takes to fill
Loading.FadeInTime = 0.5 -- the card fading in (the bar starts after it)
Loading.HoldTime = 0.4 -- full bar shown a moment before fading out
Loading.FadeOutTime = 0.6

function Loading.show(opts: { [string]: any }?)
	local self = setmetatable({}, Loading)
	self.Progress = 0
	self.Duration = (opts and tonumber(opts.Duration)) or Loading.Duration
	self.FadeIn = (opts and tonumber(opts.FadeIn)) or Loading.FadeInTime
	self.Hold = (opts and tonumber(opts.Hold)) or Loading.HoldTime
	self.FadeOut = (opts and tonumber(opts.FadeOut)) or Loading.FadeOutTime
	self.Yield = not (opts and opts.Yield == false)
	self.Started = os.clock()
	local gui = new("ScreenGui", {
		Name = T.import("base/ui/window").randomName(),
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 3000,
	})
	self.Gui = gui
	local card = new("Frame", {
		Name = "Loading",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(WIDTH, HEIGHT),
		Theme = { BackgroundColor3 = "Background" },
		Parent = gui,
	})
	self.Card = card
	-- The splash keeps one size at every UI scale.
	self.BaseScale = 1
	self.Scale = new("UIScale", { Scale = self.BaseScale * 0.96, Parent = card })
	Create.corner(card, Sizes.Radius + 2)
	Create.stroke(card, "Accent", 1, 0.6)

	local icon = Icons.new(Icons.Brand, 44, "Accent")
	icon.Name = "Brand"
	icon.AnchorPoint = Vector2.new(0.5, 0)
	icon.Position = UDim2.new(0.5, 0, 0, 20)
	icon.Parent = card

	local nameRow = new("Frame", {
		Name = "Name",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 68),
		Size = UDim2.fromOffset(0, 26),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		Parent = card,
	})
	local layout = Create.list(nameRow, Enum.FillDirection.Horizontal, 6, { VerticalAlignment = Enum.VerticalAlignment.Bottom })
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	new("TextLabel", {
		Name = "Title",
		Text = "tungsten",
		Size = UDim2.fromOffset(0, 26),
		AutomaticSize = Enum.AutomaticSize.X,
		FontFace = Theme.Fonts.Bold,
		TextSize = Sizes.Title + 6,
		LayoutOrder = 1,
		Theme = { TextColor3 = "Accent" },
		Parent = nameRow,
	})
	new("TextLabel", {
		Name = "Unified",
		Text = "(unified)",
		Size = UDim2.fromOffset(0, 22),
		AutomaticSize = Enum.AutomaticSize.X,
		FontFace = Theme.Fonts.Medium,
		TextSize = Sizes.TextSmall + 1,
		LayoutOrder = 2,
		Theme = { TextColor3 = "Text" },
		Parent = nameRow,
	})

	local track = new("Frame", {
		Name = "Track",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 108),
		Size = UDim2.fromOffset(BAR_WIDTH, BAR_HEIGHT),
		Theme = { BackgroundColor3 = "Border" },
		Parent = card,
	})
	Create.corner(track, BAR_HEIGHT / 2)
	local fill = new("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(0, 1),
		Theme = { BackgroundColor3 = "Accent" },
		Parent = track,
	})
	Create.corner(fill, BAR_HEIGHT / 2)
	self.Fill = fill

	gui.Parent = gethui()
	-- Fades in (growing slightly), then the bar fills evenly over the
	-- duration.
	Animate.fade(card, "in", self.FadeIn)
	Animate.tween(self.Scale, { Scale = self.BaseScale }, self.FadeIn, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	task.delay(self.FadeIn, function()
		if fill.Parent and self.Progress < 1 then
			Animate.tween(fill, { Size = UDim2.fromScale(1, 1) }, self.Duration, Enum.EasingStyle.Linear, Enum.EasingDirection.Out)
		end
	end)
	T.Bin:Add(function()
		if gui.Parent then
			gui:Destroy()
		end
	end)
	return self
end

-- Moves the bar to `fraction` (0..1) by hand.
function Loading:Step(fraction: number)
	fraction = math.clamp(fraction, self.Progress, 1)
	self.Progress = fraction
	if self.Fill and self.Fill.Parent then
		self.Fill.Size = UDim2.fromScale(fraction, 1)
	end
end

-- How far the bar is (0..1), by time.
function Loading:Fraction(): number
	return math.clamp((os.clock() - self.Started) / math.max(self.Duration, 0.001), 0, 1)
end

-- Waits until the splash has been up for its full duration (plus a short
-- hold with the bar full). Counts real frame time, so it can't be cut
-- short.
function Loading:Wait()
	local target = self.FadeIn + self.Duration + self.Hold
	local waited = os.clock() - self.Started
	while waited < target do
		local step = task.wait(math.min(target - waited, 0.25))
		waited += math.max(tonumber(step) or 0, 1 / 240)
	end
end

-- Fades the splash out; returns once it is gone, so the window can fade
-- in after it.
function Loading:Finish()
	self.Progress = 1
	local gui, card = self.Gui, self.Card
	if not (gui and gui.Parent) then
		return
	end
	if self.Fill and self.Fill.Parent then
		self.Fill.Size = UDim2.fromScale(1, 1)
	end
	local done = false
	Animate.tween(self.Scale, { Scale = self.BaseScale * 0.96 }, self.FadeOut, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	Animate.fade(card, "out", self.FadeOut, function()
		done = true
		if gui.Parent then
			gui:Destroy()
		end
	end)
	if self.Yield ~= false then
		local waited = 0
		while not done and waited < self.FadeOut + 1 do
			waited += tonumber(task.wait()) or 1 / 60
		end
	end
end

return Loading
