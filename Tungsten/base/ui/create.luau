--[[
	Tungsten · base/ui/create
	Instance construction helpers with Tungsten defaults.

		Create.new("Frame", {
			Size = UDim2.fromScale(1, 1),
			Theme = { BackgroundColor3 = "Surface" },
			Parent = page,
		})
]]

local T = ...
local Theme = T.import("base/theme")

local Create = {}

local TEXT_CLASSES = { TextLabel = true, TextButton = true, TextBox = true }

local DEFAULTS = {
	Frame = { BorderSizePixel = 0 },
	ScrollingFrame = { BorderSizePixel = 0 },
	ImageLabel = { BorderSizePixel = 0, BackgroundTransparency = 1 },
	ImageButton = { BorderSizePixel = 0, BackgroundTransparency = 1, AutoButtonColor = false },
	TextLabel = {
		BorderSizePixel = 0,
		BackgroundTransparency = 1,
		FontFace = Theme.Fonts.Regular,
		TextSize = Theme.Sizes.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "", -- Roblox starts a TextLabel with "Label"
		RichText = false,
	},
	TextButton = {
		BorderSizePixel = 0,
		AutoButtonColor = false,
		FontFace = Theme.Fonts.Regular,
		TextSize = Theme.Sizes.Text,
		Text = "",
		RichText = false,
	},
	TextBox = {
		BorderSizePixel = 0,
		FontFace = Theme.Fonts.Regular,
		TextSize = Theme.Sizes.Text,
		ClearTextOnFocus = false,
		Text = "", -- Roblox starts a TextBox with "TextBox"; placeholders show only when empty
		RichText = false,
	},
}

function Create.new(className: string, props: { [string]: any }?, children: { Instance }?): any
	local instance = Instance.new(className)
	local defaults = DEFAULTS[className]
	if defaults then
		for key, value in defaults do
			(instance :: any)[key] = value
		end
	end

	local parent = nil
	local themed = {}
	if props then
		for key, value in props do
			if key == "Parent" then
				parent = value
			elseif key == "Theme" then
				themed = value
			else
				(instance :: any)[key] = value
			end
		end
	end

	if TEXT_CLASSES[className] and themed.TextColor3 == nil and (props == nil or props.TextColor3 == nil) then
		Theme.bind(instance, "TextColor3", "Text")
	end
	for property, colorKey in themed do
		Theme.bind(instance, property, colorKey)
	end

	if children then
		for _, child in children do
			child.Parent = instance
		end
	end
	if parent then
		instance.Parent = parent
	end
	return instance
end

function Create.corner(parent: Instance, radius: (number | UDim)?): UICorner
	local value = if typeof(radius) == "UDim" then radius else UDim.new(0, (radius :: number?) or Theme.Sizes.Radius)
	return Create.new("UICorner", { CornerRadius = value, Parent = parent })
end

function Create.stroke(parent: Instance, colorKey: string?, thickness: number?, transparency: number?): UIStroke
	return Create.new("UIStroke", {
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Thickness = thickness or 1,
		Transparency = transparency or 0,
		Theme = { Color = colorKey or "Border" },
		Parent = parent,
	})
end

function Create.padding(parent: Instance, top: number, right: number?, bottom: number?, left: number?): UIPadding
	right = right or top
	bottom = bottom or top
	left = left or right
	return Create.new("UIPadding", {
		PaddingTop = UDim.new(0, top),
		PaddingRight = UDim.new(0, right :: number),
		PaddingBottom = UDim.new(0, bottom :: number),
		PaddingLeft = UDim.new(0, left :: number),
		Parent = parent,
	})
end

function Create.list(parent: Instance, direction: Enum.FillDirection, padding: number?, props: { [string]: any }?): UIListLayout
	local layout = Create.new("UIListLayout", {
		FillDirection = direction,
		Padding = UDim.new(0, padding or 0),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = parent,
	})
	if props then
		for key, value in props do
			(layout :: any)[key] = value
		end
	end
	return layout
end

-- Run object:Destroy() once `instance` is destroyed (directly or with an
-- ancestor), so listeners on shared services don't outlive their UI.
function Create.cleanupWith(instance: Instance, object: any)
	local connection
	connection = instance.Destroying:Connect(function()
		connection:Disconnect()
		task.defer(function()
			object:Destroy()
		end)
	end)
	return connection
end

-- Pixel width of plain text (for sizing menus and popups up front).
local TextService = T.import("base/services").TextService
local MEASURE_FONTS = {
	Regular = Enum.Font.BuilderSans,
	Medium = Enum.Font.BuilderSansMedium,
	Bold = Enum.Font.BuilderSansBold,
	Mono = Enum.Font.RobotoMono,
}
local widthCache = {}

function Create.textWidth(text: string, size: number?, font: string?): number
	size = size or Theme.Sizes.Text
	font = font or "Regular"
	local key = (font :: string) .. "\0" .. tostring(size) .. "\0" .. text
	local cached = widthCache[key]
	if cached then
		return cached
	end
	local ok, bounds = pcall(function()
		return TextService:GetTextSize(text, size, MEASURE_FONTS[font] or Enum.Font.BuilderSans, Vector2.new(100000, 1000))
	end)
	local width = if ok and bounds then bounds.X else #text * (size :: number) * 0.55
	widthCache[key] = width
	return width
end

----------------------------------------------------------------------
-- Layout pixels vs on-screen pixels
--
-- Tungsten's UI is laid out in layout pixels (sizes at scale 1) and
-- drawn bigger or smaller by UIScales (base/scale). Create.textWidth
-- above measures in layout pixels. AbsolutePosition, AbsoluteSize and
-- the mouse are on-screen pixels; turn them into layout pixels with
-- these before using them as Size / Position offsets:
--
--   Create.scaleOf(obj)          -> how big obj is drawn (every UIScale
--                                   on it and above it, multiplied)
--   Create.layoutSize(obj)       -> obj's size in layout pixels
--   Create.toLocal(point, frame) -> an on-screen point as an offset
--                                   from frame's top-left corner
----------------------------------------------------------------------

function Create.scaleOf(object: Instance?): number
	local factor = 1
	local current = object
	while current do
		if current:IsA("GuiObject") then
			local uiScale = current:FindFirstChildOfClass("UIScale")
			if uiScale then
				factor *= (uiScale :: UIScale).Scale
			end
		elseif current:IsA("LayerCollector") then
			break
		end
		current = current.Parent
	end
	return if factor > 0 then factor else 1
end

function Create.layoutSize(object: GuiObject): Vector2
	return object.AbsoluteSize / Create.scaleOf(object)
end

function Create.toLocal(point: Vector2, frame: GuiObject): Vector2
	return (point - frame.AbsolutePosition) / Create.scaleOf(frame)
end

-- Text made safe for a RichText label: shows "<b>" literally.
local ESCAPES = { ["&"] = "&amp;", ["<"] = "&lt;", [">"] = "&gt;", ['"'] = "&quot;", ["'"] = "&apos;" }
function Create.escape(text: string): string
	return (string.gsub(tostring(text), "[&<>\"']", ESCAPES))
end

-- Centered title + muted lines; used by tabs that have no content yet.
function Create.placeholder(page: Instance, title: string, lines: { string }?): Frame
	local holder = Create.new("Frame", {
		Name = "Placeholder",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -32, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Parent = page,
	})
	Create.list(holder, Enum.FillDirection.Vertical, 6, { HorizontalAlignment = Enum.HorizontalAlignment.Center })

	Create.new("TextLabel", {
		Name = "Title",
		Text = title,
		FontFace = Theme.Fonts.Bold,
		TextSize = 16,
		AutomaticSize = Enum.AutomaticSize.XY,
		TextXAlignment = Enum.TextXAlignment.Center,
		LayoutOrder = 1,
		Parent = holder,
	})

	for index, line in lines or {} do
		Create.new("TextLabel", {
			Name = "Line",
			Text = line,
			AutomaticSize = Enum.AutomaticSize.XY,
			TextXAlignment = Enum.TextXAlignment.Center,
			Theme = { TextColor3 = if index == 1 then "TextDim" else "TextMuted" },
			LayoutOrder = index + 1,
			Parent = holder,
		})
	end
	return holder
end

return Create
