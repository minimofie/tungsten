--[[
	Tungsten · base/ui/components/notify
	Toasts: short messages stacked in the bottom-right corner of the
	screen. They show even while the window is minimized (the command bar
	uses them for its results).

		Notify.show({
			Title = "Saved", Text = "3 objects written to the file",
			Kind = "success",          -- "info" (default), "success", "warn", "error", or a kind of your own
			Duration = 4,              -- seconds; 0 keeps it until closed
			Icon = "check",            -- default: the kind's icon
			Actions = { { Text = "Open", Callback = function(toast) end } },
			OnClick = function(toast) end,
			Origin = "myplugin",
		}) -> toast (toast:Close())
		Notify.info("text") ; Notify.success("text") ; Notify.warn("text") ; Notify.error("text")
		Notify.clear()

	Kinds of your own:
		Notify.registerKind("remote", { Icon = "class_remote", Color = "Info", Owner = "myplugin" })
]]

local T = ...
local signal = T.import("base/signal")
local Theme = T.import("base/theme")
local Create = T.import("base/ui/create")
local Animate = T.import("base/ui/animate")
local Icons = T.import("base/data/icons")
local Overlay = T.import("base/ui/overlay")
local UI = T.import("base/ui/ui")

local new = Create.new
local Sizes = Theme.Sizes

local WIDTH = 300
local GAP = 8
local MARGIN = 16
local MAX_SHOWN = 5

local Notify = {}
Notify.Shown = {} -- open toasts, oldest first

local kinds: { [string]: any } = {
	info = { Icon = "console", Color = "Info", Owner = "core" },
	success = { Icon = "check", Color = "Success", Owner = "core" },
	warn = { Icon = "hide", Color = "Warning", Owner = "core" },
	error = { Icon = "close", Color = "Danger", Owner = "core" },
}
local BUILTIN = { info = true, success = true, warn = true, error = true }

function Notify.registerKind(name: string, definition: { [string]: any })
	assert(type(name) == "string" and name:match("^[%a_][%w_]*$"), "a toast kind needs a plain name")
	assert(not BUILTIN[name], ("'%s' is a built-in kind"):format(name))
	kinds[name] = { Icon = definition.Icon or "console", Color = definition.Color or "Accent", Owner = definition.Owner or "core" }
end

function Notify.removeOwner(owner: string): number
	local count = 0
	for name, kind in table.clone(kinds) do
		if kind.Owner == owner and not BUILTIN[name] then
			kinds[name] = nil
			count += 1
		end
	end
	return count
end

local holder: Frame? = nil

local function container(): Frame?
	if holder and holder.Parent then
		return holder
	end
	local ok, layer = pcall(Overlay.layer)
	if not ok then
		return nil
	end
	holder = new("Frame", {
		Name = "Toasts",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -MARGIN, 1, -MARGIN),
		Size = UDim2.new(0, WIDTH, 1, -MARGIN * 2),
		BackgroundTransparency = 1,
		ZIndex = 800,
		Parent = layer,
	})
	local layout = Create.list(holder, Enum.FillDirection.Vertical, GAP)
	layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	return holder
end

local order = 0

function Notify.show(opts: { [string]: any } | string)
	if type(opts) == "string" then
		opts = { Text = opts }
	end
	local options = opts :: { [string]: any }
	local origin = options.Origin or "core"
	if UI.has("Notify", "Toast") then
		options = UI.apply("Notify", "Toast", origin, table.clone(options))
	end
	local parent = container()
	if not parent then
		return nil
	end
	local kind = kinds[options.Kind or "info"] or kinds.info
	local text = tostring(options.Text or "")
	local title = options.Title and tostring(options.Title)
	local actions = options.Actions or {}

	local lines = math.max(1, math.ceil(Create.textWidth(text, Sizes.Text) / (WIDTH - 60)))
	local height = 12 + (if title then 18 else 0) + (if text ~= "" then lines * 17 else 0) + (if #actions > 0 then 30 else 0) + 10
	order += 1
	local toast = { Closed = false, Kind = options.Kind or "info", Bin = signal.bin(), Closing = signal.new() }
	local card = new("TextButton", {
		Name = "Toast" .. order,
		Size = UDim2.fromOffset(WIDTH, height),
		LayoutOrder = order,
		BackgroundTransparency = 1,
		Theme = { BackgroundColor3 = "Surface" },
		Parent = parent,
	})
	Create.corner(card, Sizes.Radius)
	local stroke = Create.stroke(card, kind.Color, 1, 1)
	local stripe = new("Frame", {
		Name = "Stripe",
		Position = UDim2.fromOffset(0, 8),
		Size = UDim2.new(0, 3, 1, -16),
		BackgroundTransparency = 1,
		Theme = { BackgroundColor3 = kind.Color },
		Parent = card,
	})
	Create.corner(stripe, 2)
	local icon = Icons.new(options.Icon or kind.Icon, 16, kind.Color)
	icon.Position = UDim2.fromOffset(14, 12)
	icon.ImageTransparency = 1
	icon.Parent = card
	local y = 10
	local labels = {}
	if title then
		local label = new("TextLabel", {
			Name = "Title",
			Position = UDim2.fromOffset(40, y),
			Size = UDim2.new(1, -70, 0, 18),
			Text = title,
			FontFace = Theme.Fonts.Medium,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextTransparency = 1,
			Theme = { TextColor3 = "Text" },
			Parent = card,
		})
		table.insert(labels, label)
		y += 18
	end
	if text ~= "" then
		local label = new("TextLabel", {
			Name = "Text",
			Position = UDim2.fromOffset(40, y),
			Size = UDim2.new(1, -60, 0, lines * 17),
			Text = text,
			TextWrapped = true,
			TextYAlignment = Enum.TextYAlignment.Top,
			TextTransparency = 1,
			Theme = { TextColor3 = if title then "TextDim" else "Text" },
			Parent = card,
		})
		table.insert(labels, label)
		y += lines * 17
	end
	local close = new("TextButton", {
		Name = "Close",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -6, 0, 6),
		Size = UDim2.fromOffset(20, 20),
		BackgroundTransparency = 1,
		ZIndex = 3,
		Theme = { BackgroundColor3 = "SurfaceHover" },
		Parent = card,
	})
	Create.corner(close, 5)
	local closeIcon = Icons.new("close", 11, "TextMuted")
	closeIcon.AnchorPoint = Vector2.new(0.5, 0.5)
	closeIcon.Position = UDim2.fromScale(0.5, 0.5)
	closeIcon.Parent = close

	function toast:Close(reason: string?)
		if self.Closed then
			return
		end
		self.Closed = true
		local index = table.find(Notify.Shown, self)
		if index then
			table.remove(Notify.Shown, index)
		end
		self.Closing:Fire(reason)
		self.Bin:Clean()
		Animate.tween(card, { BackgroundTransparency = 1 }, Animate.Fast)
		Animate.tween(stroke, { Transparency = 1 }, Animate.Fast)
		for _, label in labels do
			Animate.tween(label, { TextTransparency = 1 }, Animate.Fast)
		end
		task.delay(Animate.Fast, function()
			card:Destroy()
		end)
		UI.fire("Notify", "Closed", origin, self, reason)
	end

	toast.Buttons = {}
	if #actions > 0 then
		local x = 40
		for index, action in actions do
			local width = math.ceil(Create.textWidth(tostring(action.Text), Sizes.TextSmall)) + 18
			local button = new("TextButton", {
				Name = "Action" .. index,
				Position = UDim2.new(0, x, 1, -32),
				Size = UDim2.fromOffset(width, 22),
				ZIndex = 3,
				Theme = { BackgroundColor3 = "SurfaceHover" },
				Parent = card,
			})
			Create.corner(button, 5)
			new("TextLabel", {
				Name = "Text",
				Size = UDim2.fromScale(1, 1),
				Text = tostring(action.Text),
				TextSize = Sizes.TextSmall,
				TextXAlignment = Enum.TextXAlignment.Center,
				ZIndex = 4,
				Theme = { TextColor3 = "Accent" },
				Parent = button,
			})
			toast.Bin:Add(button.Activated:Connect(function()
				if action.Callback then
					local ok, err = pcall(action.Callback, toast)
					if not ok then
						T.Log.error("ui", "toast action failed: " .. tostring(err))
					end
				end
				if action.Keep ~= true then
					toast:Close("action")
				end
			end))
			toast.Buttons[action.Text] = button
			x += width + 6
		end
	end
	toast.Bin:Add(close.Activated:Connect(function()
		toast:Close("closed")
	end))
	toast.Bin:Add(card.Activated:Connect(function()
		if options.OnClick then
			local ok, err = pcall(options.OnClick, toast)
			if not ok then
				T.Log.error("ui", "toast click failed: " .. tostring(err))
			end
		end
	end))
	-- Hovering pauses the countdown.
	local hovered = false
	Animate.hover(card, toast.Bin, function(on)
		hovered = on
	end)

	Animate.tween(card, { BackgroundTransparency = 0 }, Animate.Fast)
	Animate.tween(stroke, { Transparency = 0.4 }, Animate.Fast)
	Animate.tween(stripe, { BackgroundTransparency = 0 }, Animate.Fast)
	Animate.tween(icon, { ImageTransparency = 0 }, Animate.Fast)
	for _, label in labels do
		Animate.tween(label, { TextTransparency = 0 }, Animate.Fast)
	end

	toast.Frame = card
	table.insert(Notify.Shown, toast)
	while #Notify.Shown > MAX_SHOWN do
		Notify.Shown[1]:Close("overflow")
	end
	local duration = if options.Duration == nil then 4 else tonumber(options.Duration) or 4
	if duration > 0 then
		task.spawn(function()
			local left = duration
			while left > 0 and not toast.Closed do
				local dt = task.wait(0.1)
				if not hovered then
					left -= dt or 0.1
				end
			end
			toast:Close("timeout")
		end)
	end
	UI.fire("Notify", "Created", origin, toast, options)
	return toast
end

for _, kind in { "info", "success", "warn", "error" } do
	(Notify :: any)[kind] = function(text: string, title: string?, opts: { [string]: any }?)
		local options = table.clone(opts or {})
		options.Kind, options.Text, options.Title = kind, text, title
		return Notify.show(options)
	end
end

function Notify.clear()
	for _, toast in table.clone(Notify.Shown) do
		toast:Close("cleared")
	end
end

T.Bin:Add(function()
	Notify.clear()
	holder = nil
end)

return UI.register("Notify", Notify, {
	Description = "toasts in the corner of the screen (info, success, warn, error, your own kinds)",
	Constructor = "show",
	Events = {
		Created = "toast, opts",
		Closed = "toast, reason",
	},
	Filters = {
		Toast = "opts · the options of a toast about to show",
	},
})
