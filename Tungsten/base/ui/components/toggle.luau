--[[
	Tungsten · base/ui/components/toggle
	On/off switch with an optional label (clicking the label toggles too).

		local toggle = Toggle.new({ Parent = row, Text = "Read-only", Value = false,
			OnChanged = function(on) end })
		toggle:Set(true) ; toggle.Value ; toggle.Changed:Connect(...)
]]

local T = ...
local signal = T.import("base/signal")
local Theme = T.import("base/theme")
local Create = T.import("base/ui/create")
local UI = T.import("base/ui/ui")
local Animate = T.import("base/ui/animate")

local new = Create.new
local TRACK = Vector2.new(30, 16)
local KNOB = 10

local Toggle = {}
Toggle.__index = Toggle

function Toggle.new(props: { [string]: any })
	local self = setmetatable({}, Toggle)
	self.Bin = signal.bin()
	self.Changed = signal.new() -- (value)
	self.Value = props.Value == true
	self.Hovered = false
	self._onChanged = props.OnChanged
	self.Origin = props.Origin or "core"

	local root = new("TextButton", {
		Name = props.Name or "Toggle",
		Size = UDim2.fromOffset(0, Theme.Sizes.Control),
		AutomaticSize = Enum.AutomaticSize.X,
		Position = props.Position or UDim2.new(),
		LayoutOrder = props.LayoutOrder or 0,
		BackgroundTransparency = 1,
	})
	self.Instance = root
	self.Bin:Add(root)
	Create.list(root, Enum.FillDirection.Horizontal, 8, { VerticalAlignment = Enum.VerticalAlignment.Center })

	local track = new("Frame", {
		Name = "Track",
		Size = UDim2.fromOffset(TRACK.X, TRACK.Y),
		LayoutOrder = 1,
		Theme = { BackgroundColor3 = "SurfaceActive" },
		Parent = root,
	})
	Create.corner(track, UDim.new(1, 0))
	self.TrackStroke = Create.stroke(track, "BorderStrong", 1, 0)
	local knob = new("Frame", {
		Name = "Knob",
		AnchorPoint = Vector2.new(0, 0.5),
		Size = UDim2.fromOffset(KNOB, KNOB),
		Theme = { BackgroundColor3 = "TextDim" },
		Parent = track,
	})
	Create.corner(knob, UDim.new(1, 0))
	self.Track, self.Knob = track, knob

	if props.Text then
		self.Label = new("TextLabel", {
			Name = "Label",
			Text = props.Text,
			Size = UDim2.fromScale(0, 1),
			AutomaticSize = Enum.AutomaticSize.X,
			LayoutOrder = 2,
			Theme = { TextColor3 = "TextDim" },
			Parent = root,
		})
	end

	Animate.hover(root, self.Bin, function(hovered)
		self.Hovered = hovered
		self:_render(Animate.Fast)
	end)
	self.Bin:Add(root.Activated:Connect(function()
		self:Set(not self.Value)
	end))

	self.Bin:Add(Create.cleanupWith(root, self))
	self:_render(nil)
	if props.Parent then
		root.Parent = props.Parent
	end
	UI.fire("Toggle", "Created", self.Origin, self, props)
	return self
end

function Toggle:_render(duration: number?)
	local on = self.Value
	Theme.bind(self.Track, "BackgroundColor3", if on then "Accent" else "SurfaceActive", duration)
	Theme.bind(self.TrackStroke, "Color", if on then "Accent" else (if self.Hovered then "TextMuted" else "BorderStrong"), duration)
	Theme.bind(self.Knob, "BackgroundColor3", if on then "OnAccent" else (if self.Hovered then "Text" else "TextDim"), duration)
	Animate.set(self.Knob, {
		Position = UDim2.new(0, if on then TRACK.X - KNOB - 3 else 3, 0.5, 0),
	}, duration)
	if self.Label then
		Theme.bind(self.Label, "TextColor3", if self.Hovered then "Text" else "TextDim", duration)
	end
end

function Toggle:Set(value: boolean, silent: boolean?)
	value = value == true
	if value == self.Value then
		return
	end
	self.Value = value
	self:_render(Animate.Normal)
	if silent then
		return
	end
	if self._onChanged then
		local ok, err = pcall(self._onChanged, value)
		if not ok then
			T.Log.error("ui", "toggle callback failed: " .. tostring(err))
		end
	end
	self.Changed:Fire(value)
	UI.fire("Toggle", "Changed", self.Origin, self, value)
end

function Toggle:Destroy()
	self.Bin:Clean()
	self.Changed:DisconnectAll()
end

return UI.register("Toggle", Toggle, {
	Description = "on/off switches",
	Events = {
		Created = "toggle, props",
		Changed = "toggle, value",
	},
})
