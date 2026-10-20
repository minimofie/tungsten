--[[
	Tungsten · console/console
	The Console tab: output above, input line below.

	Input keys (while the input has focus)
		Enter        run
		Up / Down    history (or move through the suggestion list)
		Tab          complete commands, $variables and command arguments
		Escape       close the suggestion list
	Suggestions appear while typing a /command, :plugin.command or $name.

	The console's logic (lines, commands, variables in code) lives in
	console/core so it works before this tab is first opened.
]]

local T = ...
local signal = T.import("base/signal")
local Services = T.import("base/services")
local Theme = T.import("base/theme")
local Create = T.import("base/ui/create")
local Animate = T.import("base/ui/animate")
local Icons = T.import("base/data/icons")
local Console = T.import("console/core")
local Output = T.import("console/output")
local Completion = T.import("console/completion")
local InputAssist = T.import("console/inputassist")

local UserInputService = Services.UserInputService
local new = Create.new
local Sizes = Theme.Sizes

local INPUT_HEIGHT = 30
local GAP = 8
local PAGE_PAD = 10

local ConsoleTab = {}
ConsoleTab.__index = ConsoleTab

function ConsoleTab.new(page: Frame)
	local self = setmetatable({}, ConsoleTab)
	self.Bin = signal.bin()
	self.HistoryIndex = nil :: number?
	self.Draft = ""
	self.Focused = false
	self._programmatic = false
	self._tabAt = -1

	local holder = new("Frame", {
		Name = "Console",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = page,
	})
	Create.padding(holder, PAGE_PAD)
	self.Instance = holder
	self.Bin:Add(holder)

	------------------------------------------------------------------
	-- Input line
	------------------------------------------------------------------
	local bar = new("Frame", {
		Name = "InputBar",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, INPUT_HEIGHT),
		Theme = { BackgroundColor3 = "Chrome" },
		Parent = holder,
	})
	Create.corner(bar, Sizes.Radius)
	local stroke = Create.stroke(bar, "Border", 1, 0)
	self.Bar = bar

	bar.Size = UDim2.new(1, 0, 0, INPUT_HEIGHT)

	local prompt = Icons.new("chevron_right", 14, "Accent")
	prompt.AnchorPoint = Vector2.new(0, 0.5)
	prompt.Position = UDim2.new(0, 9, 0.5, 0)
	prompt.Parent = bar

	-- No hint text on the input: Up/Down history is in the Console docs.

	local box = new("TextBox", {
		Name = "Box",
		Position = UDim2.fromOffset(30, 0),
		Size = UDim2.new(1, -40, 1, 0),
		BackgroundTransparency = 1,
		Text = "",
		PlaceholderText = "/help · > code · $name",
		FontFace = Theme.Fonts.Mono,
		TextSize = Sizes.CodeText,
		TextXAlignment = Enum.TextXAlignment.Left,
		ClearTextOnFocus = false,
		ClipsDescendants = true,
		ZIndex = 2,
		Parent = bar,
	})
	Theme.bind(box, "PlaceholderColor3", "TextMuted")
	self.Box = box
	self.CharWidth = Create.textWidth("0000000000", Sizes.CodeText, "Mono") / 10

	local function restyle()
		Theme.bind(stroke, "Color", if self.Focused then "Accent" else "Border", Animate.Fast)
	end

	------------------------------------------------------------------
	-- Output
	------------------------------------------------------------------
	self.Output = Output.new({
		Parent = holder,
		Console = Console,
		Size = UDim2.new(1, 0, 1, -(INPUT_HEIGHT + GAP)),
		OnEmptyClick = function()
			self:Focus()
		end,
		OnRecall = function(text)
			self:SetText(text)
			self:Focus()
		end,
	})
	self.Bin:Add(self.Output)

	------------------------------------------------------------------
	-- Suggestions
	------------------------------------------------------------------
	self.Completion = Completion.new({
		Anchor = bar,
		OnPick = function(item)
			self:_apply(item)
			self:Focus()
		end,
	})
	self.Bin:Add(self.Completion)

	------------------------------------------------------------------
	-- Input events
	------------------------------------------------------------------
	self.Bin:Add(box.Focused:Connect(function()
		self.Focused = true
		restyle()
	end))
	self.Bin:Add(box.FocusLost:Connect(function(enterPressed)
		self.Focused = false
		restyle()
		if enterPressed then
			self:Submit()
		end
	end))
	self.Bin:Add(box:GetPropertyChangedSignal("Text"):Connect(function()
		self:_onText()
	end))
	self.Bin:Add(UserInputService.InputBegan:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.Keyboard then
			return
		end
		if not (self.Focused or UserInputService:GetFocusedTextBox() == box) then
			return
		end
		self:_onKey(input.KeyCode)
	end))

	self.Bin:Add(bar:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		self:_updateHint()
	end))
	self:_updateHint()
	self.Bin:Add(Create.cleanupWith(holder, self))
	return self
end

----------------------------------------------------------------------
-- Text helpers
----------------------------------------------------------------------
-- Cursor and text helpers, suggestions, Tab, Up/Down and history are
-- shared with the command bar: console/inputassist.

-- The hint gives way when the typed text would reach it.
function ConsoleTab:_updateHint()
	if not self.Hint then
		return
	end
	local text = self.Box.Text
	if text == "" then
		self.Hint.Visible = true
		return
	end
	local room = Create.layoutSize(self.Bar).X - 40 - Create.layoutSize(self.Hint).X - 12
	self.Hint.Visible = room > 0 and #text * self.CharWidth < room
end

function ConsoleTab:Focus()
	task.defer(function()
		if self.Box.Parent then
			self.Box:CaptureFocus()
		end
	end)
end

function ConsoleTab:Submit()
	local text = self.Box.Text
	self.Completion:Close()
	self.HistoryIndex = nil
	self.Draft = ""
	self:SetText("")
	if Console.Parser.trim(text) ~= "" then
		self.Output:ScrollToEnd()
		Console.run(text)
	end
	self:Focus()
end

function ConsoleTab:Destroy()
	self.Bin:Clean()
end

InputAssist.mixin(ConsoleTab)

----------------------------------------------------------------------
-- Tab definition
----------------------------------------------------------------------

return {
	Id = "console",
	Title = "Console",
	Icon = "console",
	Order = 1,
	Builtin = true,
	-- A load (base/loaded, from any tab): $loaded holds the object, or the
	-- value of a loaded target (a table for several), and the console
	-- shows it.
	OnLoad = function(instances)
		local value = if #instances == 1 then instances[1] else instances
		T.Variables.set("loaded", value, { Source = "explorer", Undo = false })
		Console.value("success", "loaded = ", value)
		return true
	end,
	Build = function(page)
		local view = ConsoleTab.new(page)
		Console.View = view
		T.Bin:Add(function()
			if Console.View == view then
				Console.View = nil
			end
		end)
	end,
}
