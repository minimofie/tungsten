--[[
	Tungsten · base/ui/components/label
	Text labels and section headers.

		Label.new({ Parent = page, Text = "Hello", Style = "dim" })
		Label.section({ Parent = page, Text = "Inputs" })

	Styles: "body" (default), "dim", "muted", "mono", "title".
	Text is plain (never rich text), so values from the game can't break it.
]]

local T = ...
local Theme = T.import("base/theme")
local Create = T.import("base/ui/create")
local UI = T.import("base/ui/ui")

local new = Create.new

local STYLES = {
	body = { Color = "Text", Font = "Regular", Size = Theme.Sizes.Text },
	dim = { Color = "TextDim", Font = "Regular", Size = Theme.Sizes.Text },
	muted = { Color = "TextMuted", Font = "Regular", Size = Theme.Sizes.TextSmall },
	mono = { Color = "Text", Font = "Mono", Size = Theme.Sizes.Text },
	title = { Color = "Text", Font = "Bold", Size = 16 },
}

local Label = {}

function Label.new(props: { [string]: any }): TextLabel
	local style = STYLES[props.Style or "body"] or STYLES.body
	local label = new("TextLabel", {
		Name = props.Name or "Label",
		Text = props.Text or "",
		FontFace = Theme.Fonts[style.Font],
		TextSize = style.Size,
		Size = props.Size or UDim2.new(1, 0, 0, 0),
		AutomaticSize = if props.Size then Enum.AutomaticSize.None else Enum.AutomaticSize.Y,
		Position = props.Position or UDim2.new(),
		TextWrapped = props.Wrap ~= false,
		TextXAlignment = props.Align or Enum.TextXAlignment.Left,
		LayoutOrder = props.LayoutOrder or 0,
		Theme = { TextColor3 = style.Color },
		Parent = props.Parent,
	})
	UI.fire("Label", "Created", props.Origin or "core", label, props)
	return label
end

-- Small uppercase heading with a hairline to its right.
function Label.section(props: { [string]: any }): Frame
	local holder = new("Frame", {
		Name = props.Name or "Section",
		Size = UDim2.new(1, 0, 0, 22),
		BackgroundTransparency = 1,
		LayoutOrder = props.LayoutOrder or 0,
	})
	local text = new("TextLabel", {
		Name = "Title",
		Text = string.upper(props.Text or ""),
		FontFace = Theme.Fonts.Bold,
		TextSize = Theme.Sizes.TextSmall,
		Size = UDim2.fromScale(0, 1),
		AutomaticSize = Enum.AutomaticSize.X,
		Theme = { TextColor3 = "TextMuted" },
		Parent = holder,
	})
	local line = new("Frame", {
		Name = "Line",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 0, 0.5, 0),
		Size = UDim2.new(1, 0, 0, 1),
		Theme = { BackgroundColor3 = "Border" },
		Parent = holder,
	})
	-- Start the line after the text once its width is known.
	local function place()
		local width = Create.layoutSize(text).X
		line.Position = UDim2.new(0, width + 8, 0.5, 0)
		line.Size = UDim2.new(1, -(width + 8), 0, 1)
	end
	text:GetPropertyChangedSignal("AbsoluteSize"):Connect(place)
	place()
	holder.Parent = props.Parent
	UI.fire("Label", "Created", props.Origin or "core", holder, props)
	return holder
end

return UI.register("Label", Label, {
	Description = "text labels (Label.new) and section headers (Label.section)",
	Events = {
		Created = "instance, props · a label or section header",
	},
})
