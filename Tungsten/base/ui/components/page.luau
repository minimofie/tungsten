--[[
	Tungsten · base/ui/components/page
	Layout pieces so a plugin's tab looks like Tungsten's own pages, built
	only from Tungsten's components (no new look, nothing a plugin can
	restyle, nothing resizable by the mouse).

		local page = Page.new({ Parent = tabPage, Toolbar = true, Scroll = true })
		page.Toolbar    -- a row along the top for buttons, inputs, dropdowns
		page.Body       -- the content (a scrolling list when Scroll = true)
		Page.section(page.Body, "Results")              -- a heading like the Plugins tab's
		local row = Page.row(page.Body, { Text = "Speed", Hint = "studs a second" })
		row.Control     -- put one control in it (Toggle, Input, Dropdown, Button…)
		Page.field(page.Body, { Id = "speed", Kind = "number", Text = "Speed",
			Default = 16, Min = 0, Max = 100 }, api.settings)
		                -- a settings row (the same kinds as plugin Settings),
		                -- read from and written to any store with get / set
		Page.placeholder(page.Body, "Nothing yet", { "Run a scan to fill this." })
		local left, right = Page.panes(page.Body, { Split = 0.4 })  -- two fixed panes

	Rows and sections stack in the order they are made (or LayoutOrder).
]]

local T = ...
local Theme = T.import("base/theme")
local Create = T.import("base/ui/create")
local UI = T.import("base/ui/ui")
local Scroll = T.import("base/ui/components/scroll")

local new = Create.new
local Sizes = Theme.Sizes

local PAD = 12
local ROW = 40

local Page = {}

local orders = setmetatable({}, { __mode = "k" }) -- parent -> next LayoutOrder

local function nextOrder(parent: Instance, given: number?): number
	if given then
		orders[parent] = math.max(orders[parent] or 0, given)
		return given
	end
	local order = (orders[parent] or 0) + 1
	orders[parent] = order
	return order
end

-- A list layout for a body, once.
local function stacked(body: Instance)
	if not body:FindFirstChildOfClass("UIListLayout") then
		local layout = Create.list(body, Enum.FillDirection.Vertical, 4)
		layout.SortOrder = Enum.SortOrder.LayoutOrder
	end
end

function Page.new(props: { [string]: any })
	local holder = new("Frame", {
		Name = props.Name or "Page",
		Size = props.Size or UDim2.fromScale(1, 1),
		Position = props.Position or UDim2.new(),
		BackgroundTransparency = 1,
		Parent = props.Parent,
	})
	local page = { Instance = holder, Origin = props.Origin or "core" }
	local top = 0
	if props.Toolbar then
		local toolbar = new("Frame", {
			Name = "Toolbar",
			Position = UDim2.fromOffset(PAD, 10),
			Size = UDim2.new(1, -PAD * 2, 0, Sizes.Control),
			BackgroundTransparency = 1,
			Parent = holder,
		})
		local layout = Create.list(toolbar, Enum.FillDirection.Horizontal, 6, { VerticalAlignment = Enum.VerticalAlignment.Center })
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		page.Toolbar = toolbar
		top = 10 + Sizes.Control + 8
		new("Frame", {
			Name = "Line",
			Position = UDim2.fromOffset(0, top - 1),
			Size = UDim2.new(1, 0, 0, 1),
			Theme = { BackgroundColor3 = "Border" },
			Parent = holder,
		})
	end
	if props.Scroll then
		local scroll = Scroll.new({
			Name = "Body",
			Direction = "Y",
			Position = UDim2.fromOffset(0, top),
			Size = UDim2.new(1, 0, 1, -top),
			Parent = holder,
		})
		page.Scroll = scroll
		page.Body = scroll.Content
		Create.padding(page.Body, 8, PAD + 4, 16, PAD)
		stacked(page.Body)
	else
		page.Body = new("Frame", {
			Name = "Body",
			Position = UDim2.fromOffset(0, top),
			Size = UDim2.new(1, 0, 1, -top),
			BackgroundTransparency = 1,
			Parent = holder,
		})
	end
	UI.fire("Page", "Created", page.Origin, page, props)
	return page
end

function Page.section(parent: Instance, text: string, order: number?): TextLabel
	stacked(parent)
	return new("TextLabel", {
		Name = "Section_" .. tostring(text),
		Size = UDim2.new(1, 0, 0, 26),
		LayoutOrder = nextOrder(parent, order),
		Text = string.upper(tostring(text)),
		FontFace = Theme.Fonts.Bold,
		TextSize = Sizes.TextSmall,
		TextYAlignment = Enum.TextYAlignment.Bottom,
		Theme = { TextColor3 = "Accent" },
		Parent = parent,
	})
end

-- A labelled row; its Control frame (right side) holds one control.
function Page.row(parent: Instance, props: { [string]: any })
	stacked(parent)
	local row = new("Frame", {
		Name = props.Name or ("Row_" .. tostring(props.Text)),
		Size = UDim2.new(1, 0, 0, props.Height or ROW),
		LayoutOrder = nextOrder(parent, props.Order),
		BackgroundTransparency = 1,
		Parent = parent,
	})
	new("TextLabel", {
		Name = "Label",
		Position = UDim2.fromOffset(0, if props.Hint then 3 else 0),
		Size = UDim2.new(1, -220, 0, if props.Hint then 20 else props.Height or ROW),
		Text = tostring(props.Text or ""),
		TextTruncate = Enum.TextTruncate.AtEnd,
		Theme = { TextColor3 = if props.Danger then "Danger" else "Text" },
		Parent = row,
	})
	if props.Hint then
		new("TextLabel", {
			Name = "Hint",
			Position = UDim2.fromOffset(0, 21),
			Size = UDim2.new(1, -220, 0, 16),
			Text = tostring(props.Hint),
			TextSize = Sizes.TextSmall,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Theme = { TextColor3 = "TextMuted" },
			Parent = row,
		})
	end
	local control = new("Frame", {
		Name = "Control",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.new(0, 210, 1, 0),
		BackgroundTransparency = 1,
		Parent = row,
	})
	local controlLayout = Create.list(control, Enum.FillDirection.Horizontal, 6, {
		VerticalAlignment = Enum.VerticalAlignment.Center,
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
	})
	controlLayout.SortOrder = Enum.SortOrder.LayoutOrder
	return { Instance = row, Control = control }
end

-- A settings row bound to a store (the rows the Plugins tab uses).
function Page.field(parent: Instance, item: { [string]: any }, store: any, order: number?)
	stacked(parent)
	assert(type(item) == "table" and type(item.Id) == "string", "a field needs an Id")
	assert(type(store) == "table" and type(store.get) == "function", "a field needs a store with get / set")
	local Manager = T.Manager
	assert(Manager and Manager.settingRow, "the Plugins tab isn't loaded")
	local row, control = Manager.settingRow(parent, nextOrder(parent, order), item, store)
	-- a value changed elsewhere (the plugin, its page) shows here too
	if store.Changed and control and control.Update then
		local connection
		connection = store.Changed:Connect(function(key)
			if key == item.Id and row.Parent then
				control.Update(store.get(key))
			end
		end)
		row.Destroying:Connect(function()
			connection:Disconnect()
		end)
	end
	return { Instance = row, Control = control }
end

function Page.placeholder(parent: Instance, title: string, lines: { string }?): Frame
	return Create.placeholder(parent, title, lines)
end

-- Two panes side by side with a line between (fixed; the explorer's
-- splitter stays the only thing the mouse resizes).
function Page.panes(parent: Instance, props: { [string]: any }?): (Frame, Frame)
	local options = props or {}
	local split = math.clamp(tonumber(options.Split) or 0.5, 0.1, 0.9)
	local holder = new("Frame", {
		Name = options.Name or "Panes",
		Size = options.Size or UDim2.fromScale(1, 1),
		LayoutOrder = nextOrder(parent, options.Order),
		BackgroundTransparency = 1,
		Parent = parent,
	})
	local left = new("Frame", {
		Name = "Left",
		Size = UDim2.new(split, -1, 1, 0),
		BackgroundTransparency = 1,
		Parent = holder,
	})
	new("Frame", {
		Name = "Divider",
		Position = UDim2.new(split, 0, 0, 8),
		Size = UDim2.new(0, 1, 1, -16),
		Theme = { BackgroundColor3 = "Border" },
		Parent = holder,
	})
	local right = new("Frame", {
		Name = "Right",
		Position = UDim2.new(split, 1, 0, 0),
		Size = UDim2.new(1 - split, -1, 1, 0),
		BackgroundTransparency = 1,
		Parent = holder,
	})
	return left, right
end

return UI.register("Page", Page, {
	Description = "page layout for plugin tabs: toolbar + body, sections, rows, settings fields, placeholder, two panes",
	Events = {
		Created = "page, props",
	},
})
