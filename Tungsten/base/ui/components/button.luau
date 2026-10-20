--[[
	Tungsten · base/ui/components/button
	Push button with optional icon.

		local button = Button.new({
			Parent = row, Text = "Run", Icon = "console",
			Style = "accent",          -- "default" | "accent" | "ghost" | "danger"
			OnClick = function() end,
		})
		button:SetText("Stop") ; button:SetEnabled(false)
		button.Clicked:Connect(...)

	Width fits the text unless Size is given.
]]

local T = ...
local signal = T.import("base/signal")
local Theme = T.import("base/theme")
local Create = T.import("base/ui/create")
local UI = T.import("base/ui/ui")
local Animate = T.import("base/ui/animate")
local Icons = T.import("base/data/icons")

local new = Create.new
local Sizes = Theme.Sizes

local STYLES = {
	default = { Back = "Surface", Hover = "SurfaceHover", Press = "SurfaceActive", Text = "Text", Stroke = "Border", BackAlpha = 0 },
	accent = { Back = "Accent", Hover = "AccentHover", Press = "Accent", Text = "OnAccent", Stroke = nil, BackAlpha = 0 },
	ghost = { Back = "SurfaceHover", Hover = "SurfaceHover", Press = "SurfaceActive", Text = "TextDim", Stroke = nil, BackAlpha = 1 },
	danger = { Back = "Surface", Hover = "SurfaceHover", Press = "SurfaceActive", Text = "Danger", Stroke = "Border", BackAlpha = 0 },
}

local Button = {}
Button.__index = Button

function Button.new(props: { [string]: any })
	local self = setmetatable({}, Button)
	self.Bin = signal.bin()
	self.Clicked = signal.new()
	self.Enabled = true
	self.Hovered = false
	self.Style = STYLES[props.Style or "default"] or STYLES.default
	self.Origin = props.Origin or "core"

	local style = self.Style
	local button = new("TextButton", {
		Name = props.Name or "Button",
		Size = props.Size or UDim2.fromOffset(0, Sizes.Control),
		AutomaticSize = if props.Size then Enum.AutomaticSize.None else Enum.AutomaticSize.X,
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		LayoutOrder = props.LayoutOrder or 0,
		BackgroundTransparency = style.BackAlpha,
		Theme = { BackgroundColor3 = style.Back },
	})
	self.Instance = button
	self.Bin:Add(button)
	Create.corner(button, Sizes.RadiusSmall)
	if style.Stroke then
		self.Stroke = Create.stroke(button, style.Stroke, 1, 0)
	end
	Create.padding(button, 0, 10, 0, 10)
	Create.list(button, Enum.FillDirection.Horizontal, 6, {
		VerticalAlignment = Enum.VerticalAlignment.Center,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
	})

	if props.Icon then
		self.Icon = Icons.new(props.Icon, 14, style.Text)
		self.Icon.LayoutOrder = 1
		self.Icon.Parent = button
	end
	self.Label = new("TextLabel", {
		Name = "Label",
		Text = props.Text or "",
		FontFace = Theme.Fonts.Medium,
		Size = UDim2.fromScale(0, 1),
		AutomaticSize = Enum.AutomaticSize.X,
		Visible = (props.Text or "") ~= "",
		LayoutOrder = 2,
		Theme = { TextColor3 = style.Text },
		Parent = button,
	})

	Animate.pressable(button, self.Bin)
	Animate.hover(button, self.Bin, function(hovered)
		self.Hovered = hovered
		self:_restyle(Animate.Fast)
	end)
	self.Bin:Add(button.Activated:Connect(function()
		if not self.Enabled then
			return
		end
		if props.OnClick then
			local ok, err = pcall(props.OnClick, self)
			if not ok then
				T.Log.error("ui", "button callback failed: " .. tostring(err))
			end
		end
		self.Clicked:Fire()
		UI.fire("Button", "Clicked", self.Origin, self)
	end))

	self.Bin:Add(Create.cleanupWith(button, self))
	if props.Parent then
		button.Parent = props.Parent
	end
	UI.fire("Button", "Created", self.Origin, self, props)
	return self
end

function Button:_restyle(duration: number?)
	local style = self.Style
	local hovered = self.Hovered and self.Enabled
	Theme.bind(self.Instance, "BackgroundColor3", if hovered then style.Hover else style.Back, duration)
	Animate.set(self.Instance, {
		BackgroundTransparency = if hovered then 0 else style.BackAlpha,
	}, duration)
	local textKey = if self.Enabled then style.Text else "TextMuted"
	if style == STYLES.ghost and hovered then
		textKey = "Text"
	end
	Theme.bind(self.Label, "TextColor3", textKey, duration)
	if self.Icon then
		Icons.tint(self.Icon, textKey, duration)
	end
end

function Button:SetText(text: string)
	self.Label.Text = text
	self.Label.Visible = text ~= ""
end

function Button:SetEnabled(enabled: boolean)
	self.Enabled = enabled
	self.Instance.AutoButtonColor = false
	self:_restyle(Animate.Fast)
end

function Button:Destroy()
	self.Bin:Clean()
	self.Clicked:DisconnectAll()
end

return UI.register("Button", Button, {
	Description = "push buttons with an optional icon",
	Events = {
		Created = "button, props",
		Clicked = "button",
	},
})
