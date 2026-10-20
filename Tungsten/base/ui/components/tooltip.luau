--[[
	Tungsten · base/ui/components/tooltip
	Small hover labels on the overlay (they never take clicks).

		local handle = Tooltip.attach(button, "Open the console", { Side = "right" })
		Tooltip.attach(row, function() return "computed " .. os.clock() end)
		handle:Remove()
		Tooltip.show("text", anchorPos, anchorSize, "below") ; Tooltip.hide()

	opts.Side "right" (default) | "below" | "above"; opts.Delay seconds
	(default 0.45); opts.Origin for UI hooks. The "ShowTooltips" setting
	turns them all off.
]]

local T = ...
local signal = T.import("base/signal")
local Theme = T.import("base/theme")
local Create = T.import("base/ui/create")
local Animate = T.import("base/ui/animate")
local Overlay = T.import("base/ui/overlay")
local UI = T.import("base/ui/ui")

local new = Create.new
local Sizes = Theme.Sizes

local Tooltip = {}
Tooltip.Delay = 0.45

local current: Frame? = nil
local showToken = 0

function Tooltip.hide()
	showToken += 1
	if current then
		current:Destroy()
		current = nil
	end
end

-- No tooltips while the window is minimized (only the pill is on screen).
local function minimized(): boolean
	local window = T.Window
	return window ~= nil and window.Minimized == true
end

function Tooltip.show(text: string, anchorPos: Vector2, anchorSize: Vector2?, side: string?, origin: string?)
	Tooltip.hide()
	if minimized() then
		return nil
	end
	text = tostring(UI.apply("Tooltip", "Text", origin or "core", tostring(text or ""), anchorPos))
	if text == "" then
		return nil
	end
	local okLayer, layer = pcall(Overlay.layer)
	if not okLayer then
		return nil
	end
	local width = math.min(math.ceil(Create.textWidth(text, Sizes.TextSmall)) + 16, 320)
	local lines = math.max(1, math.ceil((Create.textWidth(text, Sizes.TextSmall) + 16) / 320))
	local size = Vector2.new(width, 8 + lines * 14)
	side = side or "right"
	local position = Overlay.place(size, anchorPos, anchorSize or Vector2.zero, {
		Side = if side == "right" then "right" else "below",
		Gap = 6,
	})
	if side == "above" then
		local local_ = Overlay.toLayout(anchorPos)
		position = Vector2.new(position.X, math.max(Overlay.Margin, local_.Y - size.Y - 6))
	elseif side == "right" and anchorSize then
		-- centred on the anchor's height (anchor size in layout pixels)
		local local_ = Overlay.toLayout(anchorPos)
		local anchorHeight = anchorSize.Y / Overlay.factor()
		position = Vector2.new(position.X, math.max(Overlay.Margin, local_.Y + (anchorHeight - size.Y) / 2))
	end
	local frame = new("Frame", {
		Name = "Tooltip",
		Position = UDim2.fromOffset(position.X, position.Y),
		Size = UDim2.fromOffset(size.X, size.Y),
		Active = false,
		ZIndex = 900,
		BackgroundTransparency = 1,
		Theme = { BackgroundColor3 = "SurfaceActive" },
		Parent = layer,
	})
	Create.corner(frame, 5)
	local stroke = Create.stroke(frame, "BorderStrong", 1, 1)
	local label = new("TextLabel", {
		Name = "Text",
		Position = UDim2.fromOffset(8, 4),
		Size = UDim2.new(1, -16, 1, -8),
		Text = text,
		TextSize = Sizes.TextSmall,
		TextWrapped = true,
		TextTransparency = 1,
		ZIndex = 901,
		Theme = { TextColor3 = "Text" },
		Parent = frame,
	})
	Animate.tween(frame, { BackgroundTransparency = 0 }, Animate.Fast)
	Animate.tween(stroke, { Transparency = 0 }, Animate.Fast)
	Animate.tween(label, { TextTransparency = 0 }, Animate.Fast)
	current = frame
	UI.fire("Tooltip", "Shown", origin or "core", text, frame)
	return frame
end

function Tooltip.current(): Frame?
	return current
end

local Handle = {}
Handle.__index = Handle
function Handle:Remove()
	self.Bin:Clean()
	if self.Showing then
		Tooltip.hide()
	end
end

function Tooltip.attach(target: GuiObject, text: string | () -> string?, opts: { [string]: any }?)
	opts = opts or {}
	local handle = setmetatable({ Bin = signal.bin(), Showing = false }, Handle)
	local delay = (opts :: any).Delay or Tooltip.Delay
	handle.Bin:Add(target.MouseEnter:Connect(function()
		local ok, Settings = pcall(T.import, "base/settings")
		if ok and Settings.get("ShowTooltips") == false then
			return
		end
		showToken += 1
		local token = showToken
		task.delay(delay, function()
			if token ~= showToken or not target.Parent or not Overlay.shown(target) or minimized() then
				return
			end
			-- Nothing while the window is minimized (the pill has no tooltip).
			if T.Window and T.Window.Minimized then
				return
			end
			local value = text
			if type(text) == "function" then
				local okText, result = pcall(text)
				value = if okText then result else nil
			end
			if value == nil or value == "" then
				return
			end
			if Tooltip.show(tostring(value), target.AbsolutePosition, target.AbsoluteSize, (opts :: any).Side, (opts :: any).Origin) then
				handle.Showing = true
				-- Gone as soon as its object is hidden (a tab switch, minimize…).
				task.spawn(function()
					while handle.Showing and token == showToken do
						task.wait(0.2)
						if handle.Showing and token == showToken and (not target.Parent or not Overlay.shown(target) or minimized()) then
							handle.Showing = false
							Tooltip.hide()
						end
					end
				end)
			end
		end)
	end))
	local function leave()
		if handle.Showing then
			handle.Showing = false
			Tooltip.hide()
		else
			showToken += 1
		end
	end
	handle.Bin:Add(target.MouseLeave:Connect(leave))
	handle.Bin:Add(target.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.MouseButton2 then
			leave()
		end
	end))
	handle.Bin:Add(target.AncestryChanged:Connect(function()
		if not target.Parent then
			leave()
		end
	end))
	return handle
end

-- Minimizing hides any tooltip at once (they live on the overlay, which
-- stays on screen with the pill).
local hooked = false
function Tooltip.watchWindow(window)
	if hooked or not window then
		return
	end
	hooked = true
	T.Bin:Add(window.MinimizedChanged:Connect(function()
		Tooltip.hide()
	end))
end

T.Bin:Add(Tooltip.hide)

return UI.register("Tooltip", Tooltip, {
	Description = "hover labels for any GUI object",
	Constructor = function(props)
		return Tooltip.attach(props.Target, props.Text, props)
	end,
	Events = {
		Shown = "text, frame · a tooltip appeared",
	},
	Filters = {
		Text = "text, anchorPos · the text about to show",
	},
})
