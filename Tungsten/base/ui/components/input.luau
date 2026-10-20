--[[
	Tungsten · base/ui/components/input
	Single-line text or number box.

		local box = Input.new({
			Parent = row, Placeholder = "Name", Text = "",
			Width = 180,                       -- or Size = UDim2...
			OnCommit = function(text) end,     -- Enter or focus lost
			OnTyping = function(text) end,     -- every change
		})

		local num = Input.new({
			Parent = row, Numeric = true, Value = 1, Min = 0.75, Max = 1.75,
			Step = 0.05, Decimals = 2,
			OnCommit = function(number) end,
		})

	Number boxes accept only numbers; an invalid entry reverts. While a
	number box is focused, Up/Down change it by Step.
]]

local T = ...
local signal = T.import("base/signal")
local Services = T.import("base/services")
local Theme = T.import("base/theme")
local Create = T.import("base/ui/create")
local UI = T.import("base/ui/ui")
local Animate = T.import("base/ui/animate")
local Icons = T.import("base/data/icons")

local UserInputService = Services.UserInputService
local new = Create.new
local Sizes = Theme.Sizes

local Input = {}
Input.__index = Input

local function formatNumber(value: number, decimals: number?): string
	if decimals then
		local text = ("%." .. decimals .. "f"):format(value)
		-- Trim trailing zeros ("1.50" -> "1.5", "2.00" -> "2").
		if text:find("%.") then
			text = text:gsub("0+$", ""):gsub("%.$", "")
		end
		return text
	end
	return tostring(value)
end

function Input.new(props: { [string]: any })
	local self = setmetatable({}, Input)
	self.Bin = signal.bin()
	self.Committed = signal.new() -- (text or number)
	self.Typing = signal.new() -- (text)
	self.Numeric = props.Numeric == true
	self.Min = props.Min
	self.Max = props.Max
	self.Step = props.Step or 1
	self.Decimals = props.Decimals
	self.Focused = false
	self.Hovered = false
	self._onCommit = props.OnCommit
	self._onTyping = props.OnTyping
	self.Origin = props.Origin or "core"

	local root = new("Frame", {
		Name = props.Name or "Input",
		Size = props.Size or UDim2.fromOffset(props.Width or 180, Sizes.Control),
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		LayoutOrder = props.LayoutOrder or 0,
		Theme = { BackgroundColor3 = "Chrome" },
	})
	self.Instance = root
	self.Bin:Add(root)
	Create.corner(root, Sizes.RadiusSmall)
	self.Stroke = Create.stroke(root, "Border", 1, 0)

	local leftPad = 8
	if props.Icon then
		local icon = Icons.new(props.Icon, 14, "TextMuted")
		icon.AnchorPoint = Vector2.new(0, 0.5)
		icon.Position = UDim2.new(0, 7, 0.5, 0)
		icon.Parent = root
		self.Icon = icon
		leftPad = 26
	end

	local box = new("TextBox", {
		Name = "Box",
		Position = UDim2.fromOffset(leftPad, 0),
		Size = UDim2.new(1, -leftPad - 8, 1, 0),
		BackgroundTransparency = 1,
		Text = "",
		PlaceholderText = props.Placeholder or "",
		TextXAlignment = Enum.TextXAlignment.Left,
		ClearTextOnFocus = false,
		ClipsDescendants = true,
		FontFace = if props.Mono or self.Numeric then Theme.Fonts.Mono else Theme.Fonts.Regular,
		Parent = root,
	})
	Theme.bind(box, "PlaceholderColor3", "TextMuted")
	self.Box = box

	if self.Numeric then
		self.Value = tonumber(props.Value) or 0
		box.Text = formatNumber(self.Value, self.Decimals)
	else
		box.Text = props.Text or ""
	end
	self._committedText = box.Text

	local function restyle()
		local key = if self.Focused then "Accent" elseif self.Hovered then "BorderStrong" else "Border"
		Theme.bind(self.Stroke, "Color", key, Animate.Fast)
		if self.Icon then
			Icons.tint(self.Icon, if self.Focused then "Accent" else "TextMuted", Animate.Fast)
		end
	end
	Animate.hover(root, self.Bin, function(hovered)
		self.Hovered = hovered
		restyle()
	end)
	self.Bin:Add(box.Focused:Connect(function()
		self.Focused = true
		restyle()
	end))
	self.Bin:Add(box.FocusLost:Connect(function()
		self.Focused = false
		restyle()
		self:_commit()
	end))
	self.Bin:Add(box:GetPropertyChangedSignal("Text"):Connect(function()
		local text = box.Text
		if self._onTyping then
			local ok, err = pcall(self._onTyping, text)
			if not ok then
				T.Log.error("ui", "input callback failed: " .. tostring(err))
			end
		end
		self.Typing:Fire(text)
		if UI.has("Input", "Typing") then
			UI.fire("Input", "Typing", self.Origin, self, text)
		end
	end))

	if self.Numeric then
		self.Bin:Add(UserInputService.InputBegan:Connect(function(input)
			if not self.Focused or input.UserInputType ~= Enum.UserInputType.Keyboard then
				return
			end
			local direction = if input.KeyCode == Enum.KeyCode.Up then 1 elseif input.KeyCode == Enum.KeyCode.Down then -1 else 0
			if direction ~= 0 then
				local current = tonumber(box.Text) or self.Value
				self:SetValue(current + direction * self.Step)
				self:_fire(self.Value)
			end
		end))
	end

	self.Bin:Add(Create.cleanupWith(root, self))
	if props.Parent then
		root.Parent = props.Parent
	end
	UI.fire("Input", "Created", self.Origin, self, props)
	return self
end

function Input:_fire(value: any)
	if self._onCommit then
		local ok, err = pcall(self._onCommit, value)
		if not ok then
			T.Log.error("ui", "input callback failed: " .. tostring(err))
		end
	end
	self.Committed:Fire(value)
	UI.fire("Input", "Committed", self.Origin, self, value)
end

function Input:_clampNumber(value: number): number
	if self.Min then
		value = math.max(self.Min, value)
	end
	if self.Max then
		value = math.min(self.Max, value)
	end
	return value
end

function Input:_commit()
	local box = self.Box
	if self.Numeric then
		local number = tonumber(box.Text)
		if number == nil or number ~= number then
			box.Text = formatNumber(self.Value, self.Decimals) -- revert
			return
		end
		number = self:_clampNumber(number)
		box.Text = formatNumber(number, self.Decimals)
		if number ~= self.Value then
			self.Value = number
			self:_fire(number)
		end
	else
		if box.Text ~= self._committedText then
			self._committedText = box.Text
			self:_fire(box.Text)
		end
	end
end

function Input:SetValue(value: number)
	self.Value = self:_clampNumber(value)
	self.Box.Text = formatNumber(self.Value, self.Decimals)
end

function Input:SetText(text: string)
	self.Box.Text = text
	self._committedText = text
end

function Input:GetText(): string
	return self.Box.Text
end

function Input:Focus()
	self.Box:CaptureFocus()
end

function Input:Destroy()
	self.Bin:Clean()
	self.Committed:DisconnectAll()
	self.Typing:DisconnectAll()
end

return UI.register("Input", Input, {
	Description = "single-line text and number boxes",
	Events = {
		Created = "input, props",
		Committed = "input, value · Enter or focus lost with a new value",
		Typing = "input, text",
	},
})
