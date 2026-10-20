--[[
	Tungsten · documentation/documentation
	The Documentation tab: a searchable topic list on the left, the
	topic on the right. Topics come from documentation/topics/ and from
	plugins (documentation/docs.luau explains both). The search takes the
	shared filter words (several words, !not, "exact", group:Name).
	Explorer › Load into this tab shows the loaded object's class page.

	Right-click
		topic list    open, copy titles, reload topics
		code block    copy, put in the console input, run in the console
		page          copy the topic's text, open the console
]]

local T = ...
local signal = T.import("base/signal")
local Theme = T.import("base/theme")
local Create = T.import("base/ui/create")
local Overlay = T.import("base/ui/overlay")
local Scroll = T.import("base/ui/components/scroll")
local List = T.import("base/ui/components/list")
local Input = T.import("base/ui/components/input")
local Menus = T.import("base/ui/menus")
local Docs = T.import("documentation/docs")

local new = Create.new
local Sizes = Theme.Sizes

local PAD = 10
local SIDE = 190
local CONTENT_PAD = 16

local DocsTab = {}
DocsTab.__index = DocsTab

----------------------------------------------------------------------
-- Inline formatting -> escaped rich text
----------------------------------------------------------------------

local function rich(text: string): string
	local escaped = Create.escape(text)
	local codeColor = Theme.hex("Accent")
	escaped = escaped:gsub("`([^`]+)`", function(code)
		return ('<font face="RobotoMono" color="%s">%s</font>'):format(codeColor, code)
	end)
	escaped = escaped:gsub("%*%*(.-)%*%*", "<b>%1</b>")
	return escaped
end
DocsTab.rich = rich

-- Inputs a code block may run: each line starts with a console prefix.
local function runnableLines(text: string): { string }?
	local lines = {}
	for line in (text .. "\n"):gmatch("(.-)\n") do
		local trimmed = line:gsub("^%s+", ""):gsub("%s+$", "")
		if trimmed ~= "" then
			if not trimmed:match("^[/:>=%$%?!#]") then
				return nil
			end
			table.insert(lines, trimmed)
		end
	end
	return if #lines > 0 then lines else nil
end

local function toConsole(text: string?, run: boolean)
	T.Tabs:Select("console")
	local Console = T.Console
	task.defer(function()
		if run then
			for _, line in runnableLines(text or "") or {} do
				Console.run(line)
			end
		elseif Console.View and text then
			Console.View:SetText(text)
			Console.View:Focus()
		end
	end)
end

----------------------------------------------------------------------
-- Building
----------------------------------------------------------------------

function DocsTab.new(page: Frame)
	local self = setmetatable({}, DocsTab)
	self.Bin = signal.bin()
	self.Current = nil
	self.Filter = ""

	local holder = new("Frame", {
		Name = "Documentation",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = page,
	})
	Create.padding(holder, PAD)
	self.Instance = holder
	self.Bin:Add(holder)

	-- Left: search + topics.
	local side = new("Frame", {
		Name = "Side",
		Size = UDim2.new(0, SIDE, 1, 0),
		BackgroundTransparency = 1,
		Parent = holder,
	})
	self.Search = Input.new({
		Name = "Search",
		Parent = side,
		Size = UDim2.new(1, 0, 0, Sizes.Control),
		Icon = "search",
		Placeholder = "Search topics…",
		OnTyping = function(text)
			self.Filter = text
			self:_refreshList()
		end,
	})
	self.Bin:Add(self.Search)

	self.List = List.new({
		Name = "Topics",
		Parent = side,
		Position = UDim2.fromOffset(0, Sizes.Control + 8),
		Size = UDim2.new(1, 0, 1, -(Sizes.Control + 8)),
		Columns = { {
			Key = "Title",
			Flex = true,
			Get = function(topic)
				if topic.Group and topic.Group ~= Docs.CoreGroup then
					return ("%s  · %s"):format(topic.Title, topic.Group)
				end
				return topic.Title
			end,
		} },
		Header = false,
		MultiSelect = true,
		EmptyText = "No topics match",
		Menu = "docs.topics",
		MenuContext = function(ctx)
			ctx.View = self
		end,
		OnActivate = function(item)
			self:Show(item)
		end,
	})
	self.Bin:Add(self.List)
	self.Bin:Add(self.List.SelectionChanged:Connect(function(selected)
		if #selected == 1 and selected[1] ~= self.Current then
			self:Show(selected[1])
		end
	end))

	-- Right: the topic.
	local body = new("Frame", {
		Name = "Body",
		Position = UDim2.fromOffset(SIDE + PAD, 0),
		Size = UDim2.new(1, -(SIDE + PAD), 1, 0),
		Theme = { BackgroundColor3 = "Chrome" },
		Parent = holder,
	})
	Create.corner(body, Sizes.Radius)
	Create.stroke(body, "Border", 1, 0)
	self.Body = body

	-- Right-clicks on empty page space.
	local backdrop = new("TextButton", {
		Name = "Backdrop",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 1,
		Parent = body,
	})
	self.Bin:Add(backdrop.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			self:_pageMenu(Overlay.pointOf(input))
		end
	end))

	local scroll = Scroll.new({ Name = "Page", Direction = "Y", Parent = body })
	scroll.Instance.ZIndex = 2
	Create.list(scroll.Content, Enum.FillDirection.Vertical, 8)
	Create.padding(scroll.Content, CONTENT_PAD, CONTENT_PAD + 6, CONTENT_PAD, CONTENT_PAD)
	self.Scroll = scroll
	self.Bin:Add(scroll)

	self.Bin:Add(Docs.Changed:Connect(function()
		local id = self.Current and self.Current.Id
		self:_refreshList()
		local topic = id and Docs.get(id)
		if topic then
			self:Show(topic)
		end
	end))
	self.Bin:Add(Docs.OpenRequested:Connect(function(topic)
		self:Show(topic)
	end))
	self.Bin:Add(Theme.Changed:Connect(function()
		if self.Current then
			self:_render(self.Current)
		end
	end))

	self:_refreshList()
	local first = Docs.Pending or self.List:GetItems()[1]
	Docs.Pending = nil
	if first then
		self:Show(first)
	end
	self.Bin:Add(Create.cleanupWith(holder, self))
	return self
end

function DocsTab:_refreshList()
	local items = if self.Filter:match("^%s*$") then Docs.topics() else Docs.search(self.Filter)
	if self.Current and self.Current.Hidden then
		-- A class page opened by Load stays listed while it is shown.
		table.insert(items, 1, self.Current)
	end
	self.List:SetItems(items)
	if self.Current then
		for _, item in items do
			if item.Id == self.Current.Id then
				self.List:SetSelected({ item }, true)
			end
		end
	end
end

function DocsTab:Show(topic)
	if not topic then
		return
	end
	-- The list holds fresh copies after a reload; match by id.
	for _, item in self.List:GetItems() do
		if item.Id == topic.Id then
			topic = item
			break
		end
	end
	self.Current = topic
	if topic.Hidden and not self.List.Index[topic] then
		self:_refreshList()
	end
	self.List:SetSelected({ topic }, true)
	self.List:ScrollToItem(topic, false)
	self:_render(topic)
	self.Scroll:ScrollTo(Vector2.zero, false)
end

----------------------------------------------------------------------
-- Blocks
----------------------------------------------------------------------

local function textLabel(props)
	local label = new("TextLabel", {
		Name = props.Name or "Text",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextWrapped = true,
		RichText = true,
		Text = props.Text,
		FontFace = props.Font or Theme.Fonts.Regular,
		TextSize = props.TextSize or Sizes.Text,
		LineHeight = props.LineHeight or 1.15,
		LayoutOrder = props.LayoutOrder or 0,
		Theme = { TextColor3 = props.Color or "Text" },
		Parent = props.Parent,
	})
	return label
end

function DocsTab:_codeBlock(text: string, order: number)
	local box = new("Frame", {
		Name = "Code",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Active = true,
		LayoutOrder = order,
		Theme = { BackgroundColor3 = "EditorGutter" },
		Parent = self.Scroll.Content,
	})
	Create.corner(box, Sizes.RadiusSmall)
	Create.stroke(box, "Border", 1, 0)
	Create.padding(box, 8, 10, 8, 10)
	new("TextLabel", {
		Name = "Text",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextWrapped = true,
		Text = text,
		FontFace = Theme.Fonts.Mono,
		TextSize = Sizes.CodeText,
		LineHeight = 1.1,
		Parent = box,
	})
	box.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			self:_codeMenu(text, Overlay.pointOf(input))
		end
	end)
	return box
end

local function columnWeights(block): { number }
	local weights = {}
	local rows = { block.Header }
	for _, row in block.Rows do
		table.insert(rows, row)
	end
	for column = 1, #block.Header do
		local total, count = 0, 0
		for _, row in rows do
			if row[column] then
				total += #row[column]
				count += 1
			end
		end
		weights[column] = math.clamp(if count > 0 then total / count else 8, 6, 46)
	end
	return weights
end

function DocsTab:_table(block, order: number)
	local frame = new("Frame", {
		Name = "Table",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = order,
		Theme = { BackgroundColor3 = "Background" },
		Parent = self.Scroll.Content,
	})
	Create.corner(frame, Sizes.RadiusSmall)
	Create.stroke(frame, "Border", 1, 0)
	Create.list(frame, Enum.FillDirection.Vertical, 0)

	local weights = columnWeights(block)
	local sum = 0
	for _, weight in weights do
		sum += weight
	end

	local function row(cells, index: number, header: boolean)
		local line = new("Frame", {
			Name = if header then "Header" else "Row" .. index,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = if header or index % 2 == 0 then 0 else 1,
			LayoutOrder = index,
			Theme = { BackgroundColor3 = if header then "Surface" else "Chrome" },
			Parent = frame,
		})
		Create.list(line, Enum.FillDirection.Horizontal, 0)
		for column = 1, #block.Header do
			local cell = new("Frame", {
				Name = "Cell" .. column,
				Size = UDim2.new(weights[column] / sum, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundTransparency = 1,
				LayoutOrder = column,
				Parent = line,
			})
			Create.padding(cell, 5, 8, 5, 8)
			textLabel({
				Parent = cell,
				Text = rich(cells[column] or ""),
				Font = if header then Theme.Fonts.Medium else nil,
				TextSize = if header then Sizes.TextSmall else Sizes.Text,
				Color = if header then "TextMuted" else "Text",
			})
		end
	end

	row(block.Header, 0, true)
	for index, cells in block.Rows do
		row(cells, index, false)
	end
	return frame
end

-- {{plugin-commands}}: the commands plugins added, read live.
function DocsTab:_directive(block, order: number)
	if block.Name ~= "plugin-commands" then
		return textLabel({ Parent = self.Scroll.Content, Text = rich("(unknown block " .. block.Name .. ")"), Color = "TextMuted", LayoutOrder = order })
	end
	local Commands = T.Console and T.Console.Commands
	local rows = {}
	for _, command in (if Commands then Commands.list() else {}) do
		if command.Owner ~= "core" and not command.Hidden then
			table.insert(rows, { "`" .. Commands.invocation(command) .. "`", command.Description, "`" .. command.Usage .. "`" })
		end
	end
	if #rows == 0 then
		return textLabel({
			Parent = self.Scroll.Content,
			Text = rich("No plugin commands yet. Commands that plugins add show up here."),
			Color = "TextMuted",
			LayoutOrder = order,
		})
	end
	return self:_table({ Header = { "Command", "What it does", "Usage" }, Rows = rows }, order)
end

local HEADING_SIZE = { 20, 16, 14 }

function DocsTab:_render(topic)
	local content = self.Scroll.Content
	for _, child in content:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	if type(topic.Build) == "function" then
		-- A page of the topic's own UI (plugins).
		local ok, err = pcall(topic.Build, content, self)
		if not ok then
			T.Log.error("docs", ("topic '%s' failed to build: %s"):format(topic.Id, tostring(err)))
			if topic.Owner ~= "core" then
				T.import("console/reporter").ownerFault(topic.Owner, ("documentation topic '%s'"):format(topic.Id), err)
			end
			textLabel({ Parent = content, Text = rich("This topic failed to load."), Color = "TextMuted" })
		end
		if #topic.Blocks == 0 then
			return
		end
	end
	for order, block in topic.Blocks do
		local kind = block.Kind
		if kind == "heading" then
			local label = textLabel({
				Parent = content,
				Name = "Heading",
				Text = rich(block.Text),
				Font = Theme.Fonts.Bold,
				TextSize = HEADING_SIZE[block.Level] or 14,
				Color = if block.Level == 3 then "TextDim" else "Text",
				LayoutOrder = order,
			})
			if block.Level == 2 and order > 1 then
				Create.padding(label, 8, 0, 0, 0)
			end
		elseif kind == "paragraph" then
			textLabel({ Parent = content, Name = "Paragraph", Text = rich(block.Text), Color = "TextDim", LayoutOrder = order })
		elseif kind == "list" then
			local holder = new("Frame", {
				Name = "List",
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundTransparency = 1,
				LayoutOrder = order,
				Parent = content,
			})
			Create.list(holder, Enum.FillDirection.Vertical, 4)
			for index, item in block.Items do
				local line = new("Frame", {
					Name = "Item" .. index,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					BackgroundTransparency = 1,
					LayoutOrder = index,
					Parent = holder,
				})
				new("TextLabel", {
					Name = "Dot",
					Size = UDim2.fromOffset(14, Sizes.Text + 2),
					Text = "•",
					Theme = { TextColor3 = "Accent" },
					Parent = line,
				})
				local text = new("Frame", {
					Name = "Body",
					Position = UDim2.fromOffset(14, 0),
					Size = UDim2.new(1, -14, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					BackgroundTransparency = 1,
					Parent = line,
				})
				textLabel({ Parent = text, Text = rich(item), Color = "TextDim" })
			end
		elseif kind == "tip" then
			local box = new("Frame", {
				Name = "Tip",
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				LayoutOrder = order,
				Theme = { BackgroundColor3 = "AccentSoft" },
				Parent = content,
			})
			Create.corner(box, Sizes.RadiusSmall)
			Create.padding(box, 8, 12, 8, 12)
			textLabel({ Parent = box, Text = rich(block.Text), Color = "Text" })
		elseif kind == "code" then
			self:_codeBlock(block.Text, order)
		elseif kind == "table" then
			self:_table(block, order)
		elseif kind == "rule" then
			new("Frame", {
				Name = "Rule",
				Size = UDim2.new(1, 0, 0, 1),
				LayoutOrder = order,
				Theme = { BackgroundColor3 = "Border" },
				Parent = content,
			})
		elseif kind == "directive" then
			self:_directive(block, order)
		end
	end
end

----------------------------------------------------------------------
-- Menus
----------------------------------------------------------------------

-- "docs.code": right-click a code block. ctx.Text, ctx.Runnable (lines
-- that would run, or nil), ctx.Single (one line), ctx.View.
Menus.define("docs.code", {
	Title = "Documentation code block",
	Header = "Code",
	Sections = { "main" },
})
Menus.addMany("docs.code", {
	{
		Id = "copy",
		Order = 10,
		Text = "Copy",
		Icon = "copy",
		Callback = function(ctx)
			pcall(setclipboard, ctx.Text)
		end,
	},
	{
		Id = "to_input",
		Order = 20,
		Text = "Put in the console input",
		Icon = "edit",
		Disabled = function(ctx)
			return not ctx.Single
		end,
		Callback = function(ctx)
			toConsole(ctx.Text, false)
		end,
	},
	{
		Id = "run",
		Order = 30,
		Text = function(ctx)
			local runnable = ctx.Runnable
			return if runnable and #runnable > 1 then ("Run %d lines in the console"):format(#runnable) else "Run in the console"
		end,
		Icon = "console",
		Disabled = function(ctx)
			return ctx.Runnable == nil
		end,
		Callback = function(ctx)
			toConsole(ctx.Text, true)
		end,
	},
})

-- "docs.page": right-click the topic page. ctx.Topic, ctx.View.
Menus.define("docs.page", {
	Title = "Documentation page",
	Header = function(ctx)
		return if ctx.Topic then ctx.Topic.Title else "Documentation"
	end,
	Sections = { "main", "reload" },
})
Menus.addMany("docs.page", {
	{
		Id = "copy_text",
		Order = 10,
		Text = "Copy topic text",
		Icon = "copy",
		Disabled = function(ctx)
			return ctx.Topic == nil
		end,
		Callback = function(ctx)
			pcall(setclipboard, ctx.Topic.Text)
		end,
	},
	{
		Id = "console",
		Order = 20,
		Text = "Open the console",
		Icon = "console",
		Callback = function()
			T.Tabs:Select("console")
		end,
	},
	{
		Id = "reload",
		Section = "reload",
		Order = 10,
		Text = "Reload topics",
		Callback = function()
			Docs.reload()
		end,
	},
})

-- "docs.topics": right-click the topic list (List context: ctx.Selected,
-- ctx.Item, ctx.List, ctx.Point; plus ctx.View).
Menus.define("docs.topics", {
	Title = "Documentation topic list",
	Header = function(ctx)
		if #ctx.Selected > 1 then
			return ("%d topics"):format(#ctx.Selected)
		end
		return if ctx.Item then ctx.Item.Title else "Topics"
	end,
	Sections = { "main", "reload" },
})
Menus.addMany("docs.topics", {
	{
		Id = "open",
		Order = 10,
		Text = "Open",
		Disabled = function(ctx)
			return ctx.Item == nil
		end,
		Callback = function(ctx)
			ctx.View:Show(ctx.Item)
		end,
	},
	{
		Id = "copy_titles",
		Order = 20,
		Text = function(ctx)
			return if #ctx.Selected > 1 then "Copy titles" else "Copy title"
		end,
		Icon = "copy",
		Disabled = function(ctx)
			return #ctx.Selected == 0
		end,
		Callback = function(ctx)
			local titles = {}
			for _, topic in ctx.Selected do
				table.insert(titles, topic.Title)
			end
			pcall(setclipboard, table.concat(titles, "\n"))
		end,
	},
	{
		Id = "copy_text",
		Order = 30,
		Text = "Copy text",
		Disabled = function(ctx)
			return #ctx.Selected == 0
		end,
		Callback = function(ctx)
			local parts = {}
			for _, topic in ctx.Selected do
				table.insert(parts, topic.Text)
			end
			pcall(setclipboard, table.concat(parts, "\n\n"))
		end,
	},
	{
		Id = "reload",
		Section = "reload",
		Order = 10,
		Text = "Reload topics",
		Callback = function()
			Docs.reload()
		end,
	},
})

function DocsTab:_codeMenu(text: string, point: Vector2)
	return Menus.open("docs.code", {
		View = self,
		Text = text,
		Runnable = runnableLines(text),
		Single = not text:find("\n"),
	}, { Position = point })
end

function DocsTab:_pageMenu(point: Vector2)
	return Menus.open("docs.page", { View = self, Topic = self.Current }, { Position = point })
end

function DocsTab:Destroy()
	self.Bin:Clean()
end

return {
	Id = "documentation",
	Title = "Documentation",
	Icon = "documentation",
	Order = 3,
	Builtin = true,
	Build = function(page)
		local view = DocsTab.new(page)
		Docs.View = view
	end,
	-- A load (base/loaded): the class page of the first loaded object. The
	-- page changes in the background; the tab isn't opened. Values that
	-- aren't Instances leave the page as it is.
	OnLoad = function(instances)
		if typeof(instances[1]) ~= "Instance" then
			return false
		end
		local Api = T.import("base/explorer/api")
		local className = Api.knownClass(instances[1])
		local topic = Docs.classTopic(className)
		if topic then
			Docs.open(topic)
			return true
		end
		return false
	end,
}
