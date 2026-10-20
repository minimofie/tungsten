--[[
	Tungsten · base/ui/commandbar
	A command bar of its own, apart from the main window: press ' (the
	CommandBarKey setting) anywhere in the game — window open or
	minimized — type a console input and press Enter. It runs in the
	console exactly as if typed there (commands, > Luau, $variables, …)
	without opening the window; the newest output lines show under the
	bar.

	Typing works like the console input (console/inputassist): the same
	live suggestion list with the same labels and hints, Tab completes,
	Up/Down move through the suggestions or the history. Enter runs (the
	bar stays open), Escape closes the suggestions or else the bar, the
	key on an empty bar or a click anywhere else closes it. Closing forgets the
	text and the output: it always opens empty.

		CommandBar.open() ; CommandBar.close() ; CommandBar.toggle()
		CommandBar.run("/select remotes")
		CommandBar.Opened / Closed / Ran (signals)
]]

local T = ...
local signal = T.import("base/signal")
local Services = T.import("base/services")
local Settings = T.import("base/settings")
local Theme = T.import("base/theme")
local Create = T.import("base/ui/create")
local Animate = T.import("base/ui/animate")
local Icons = T.import("base/data/icons")
local Overlay = T.import("base/ui/overlay")
local UI = T.import("base/ui/ui")
local Completion = T.import("console/completion")
local InputAssist = T.import("console/inputassist")

local UserInputService = Services.UserInputService
local new = Create.new
local Sizes = Theme.Sizes

local WIDTH = 560
local BAR = 40
local LINE = 18
local GAP = 6
local MAX_LINES = 8
local TOP = 0.22 -- of the screen height
local SEE_THROUGH = 0.14 -- background transparency of the bar, its output and its suggestions

local CommandBar = {}
CommandBar.Opened = signal.new()
CommandBar.Closed = signal.new()
CommandBar.Ran = signal.new() -- (text)
CommandBar.IsOpen = false
CommandBar.Transparency = SEE_THROUGH

local gui, frame, barFrame, box, results = nil, nil, nil, nil, nil
local holderFrame = nil
local setInputLive -- (defined below)
local resultLines = {}
local bin = signal.bin()
local capturing = false
local completionClosedAt = -1
local letGo -- defined below

-- The typing help host (same methods as the console input).
local Host = {}
Host.__index = Host
InputAssist.mixin(Host)
local host = nil

local function console()
	return T.Console
end

-- Output lines under the bar.
local function drawResults()
	if not results then
		return
	end
	for _, child in results:GetChildren() do
		if child:IsA("TextLabel") then
			child:Destroy()
		end
	end
	local Console = console()
	local styles = if Console then Console.Styles or Console.Kinds else nil
	for index, line in resultLines do
		local style = styles and styles[line.Kind]
		local tag = if style and style.Tag then style.Tag .. " " else "    "
		new("TextLabel", {
			Name = "Line" .. index,
			Size = UDim2.new(1, 0, 0, LINE),
			LayoutOrder = index,
			Text = tag .. line.Plain,
			FontFace = Theme.Fonts.Mono,
			TextSize = Sizes.CodeText - 1,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Theme = { TextColor3 = if style then style.TagColor or "Text" else "Text" },
			Parent = results,
		})
	end
	-- The suggestion list may open over the output; the output steps
	-- aside while it is open.
	local suggesting = host ~= nil and host.Completion:IsOpen()
	results.Visible = #resultLines > 0 and not suggesting
	frame.Size = UDim2.fromOffset(WIDTH, BAR + (if #resultLines > 0 then GAP + #resultLines * LINE + 12 else 0))
end

local function build()
	if gui then
		return
	end
	gui = new("ScreenGui", {
		Name = T.import("base/ui/window").randomName(),
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 2000,
		Enabled = false,
	})
	gui.Parent = gethui()
	bin:Add(gui)
	-- Centred in a holder. The bar keeps its size at every UI scale (it
	-- is not part of the window), and so do its suggestions.
	holderFrame = new("Frame", {
		Name = "CommandBarHolder",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, TOP, 0),
		Size = UDim2.fromOffset(WIDTH, BAR),
		BackgroundTransparency = 1,
		Parent = gui,
	})
	frame = new("Frame", {
		Name = "CommandBar",
		Size = UDim2.fromOffset(WIDTH, BAR),
		BackgroundTransparency = 1,
		Parent = holderFrame,
	})
	barFrame = new("Frame", {
		Name = "Bar",
		Size = UDim2.new(1, 0, 0, BAR),
		BackgroundTransparency = SEE_THROUGH,
		Theme = { BackgroundColor3 = "Surface" },
		Parent = frame,
	})
	Create.corner(barFrame, Sizes.Radius)
	Create.stroke(barFrame, "Accent", 1, 0.2)
	local mark = Icons.new(Icons.Brand, 20, "Accent")
	mark.AnchorPoint = Vector2.new(0, 0.5)
	mark.Position = UDim2.new(0, 12, 0.5, 0)
	mark.Parent = barFrame
	box = new("TextBox", {
		Name = "Input",
		Position = UDim2.fromOffset(42, 0),
		Size = UDim2.new(1, -54, 1, 0),
		BackgroundTransparency = 1,
		ClearTextOnFocus = false,
		Text = "",
		PlaceholderText = "",
		Selectable = false, -- never the selected UI object (that would take game input)
		TextEditable = false, -- only while the bar is open
		TextXAlignment = Enum.TextXAlignment.Left,
		FontFace = Theme.Fonts.Mono,
		TextSize = Sizes.CodeText + 1,
		ClipsDescendants = true,
		Parent = barFrame,
	})
	results = new("Frame", {
		Name = "Results",
		Position = UDim2.fromOffset(0, BAR + GAP),
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Visible = false,
		BackgroundTransparency = SEE_THROUGH,
		Theme = { BackgroundColor3 = "Chrome" },
		Parent = frame,
	})
	Create.corner(results, Sizes.RadiusSmall)
	Create.padding(results, 6, 10, 6, 10)
	Create.list(results, Enum.FillDirection.Vertical, 0)

	-- Suggestions: the console's own list, anchored to the bar and as
	-- see-through as the bar.
	host = setmetatable({
		Box = box,
		HistoryIndex = nil,
		Draft = "",
		_programmatic = false,
		_completion = nil,
	}, Host)
	host.Completion = Completion.new({
		Anchor = barFrame,
		Transparency = SEE_THROUGH,
		Fixed = true, -- the command bar keeps its size, and so do its suggestions
		OnPick = function(item)
			host:_apply(item)
			CommandBar.focus()
		end,
	})
	bin:Add(host.Completion)
	bin:Add(host.Completion.Closed:Connect(function()
		completionClosedAt = os.clock()
		drawResults()
	end))

	bin:Add(box.FocusLost:Connect(function(enter)
		if not CommandBar.IsOpen or not enter then
			return
		end
		local text = box.Text
		host.Completion:Close()
		host.HistoryIndex = nil
		host.Draft = ""
		host:SetText("")
		if text:match("^%s*$") then
			CommandBar.close()
			return
		end
		CommandBar.run(text)
		CommandBar.focus()
	end))
	bin:Add(box:GetPropertyChangedSignal("Text"):Connect(function()
		-- The key that opened the bar must not end up in it.
		if CommandBar._justOpened and box.Text:sub(1, 1) == CommandBar.keyText() then
			CommandBar._justOpened = false
			host:SetText(box.Text:sub(2))
			return
		end
		CommandBar._justOpened = false
		host:_onText()
		drawResults()
	end))
end

local function keyName(): string
	local name = Settings.get("CommandBarKey")
	return if type(name) == "string" and name ~= "" then name else "Quote"
end

-- The character the bar's key types (what the welcome line and docs show).
local KEY_TEXT = {
	Quote = "'", BackSlash = "\\", Semicolon = ";", Backquote = "`", Slash = "/", Comma = ",",
	Period = ".", LeftBracket = "[", RightBracket = "]", Minus = "-", Equals = "=",
}
function CommandBar.keyText(): string
	local name = keyName()
	return KEY_TEXT[name] or name
end

-- Is this KeyCode the one that opens the bar (CommandBarKey)?
function CommandBar.isKey(key: EnumItem): boolean
	local name = keyName()
	if key.Name == name then
		return true
	end
	local ok, wanted = pcall(function()
		return (Enum.KeyCode :: any)[name]
	end)
	return ok and wanted == key
end

function CommandBar.focus()
	task.defer(function()
		if CommandBar.IsOpen and box and box.Parent then
			box:CaptureFocus()
		end
	end)
end

-- Empty input and output (the bar never keeps what was in it).
local function clear()
	resultLines = {}
	capturing = false
	if host then
		host.Completion:Close()
		host.HistoryIndex = nil
		host.Draft = ""
		host:SetText("")
	end
	drawResults()
end

-- Whether the input box can take the keyboard.
setInputLive = function(live: boolean)
	if not box then
		return
	end
	pcall(function()
		box.TextEditable = live
		box.Interactable = live
	end)
	box.Visible = live
end

function CommandBar.open()
	build()
	if CommandBar.IsOpen then
		CommandBar.focus()
		return
	end
	CommandBar.IsOpen = true
	box.TextEditable = true
	clear()
	CommandBar._justOpened = true
	-- the key press that opened it may still type its character a moment later
	task.delay(0.15, function()
		CommandBar._justOpened = false
	end)
	gui.Enabled = true
	setInputLive(true)
	holderFrame.Position = UDim2.new(0.5, 0, TOP, -8)
	Animate.tween(holderFrame, { Position = UDim2.new(0.5, 0, TOP, 0) }, Animate.Fast)
	Animate.fade(frame, "in", Animate.Fast)
	CommandBar.focus()
	CommandBar.Opened:Fire()
	UI.fire("CommandBar", "Opened", "core")
end

-- The bar's box lets go of the keyboard, and nothing of the bar stays the
-- selected UI object.
function letGo()
	if not box then
		return
	end
	pcall(function()
		box:ReleaseFocus()
	end)
	if CommandBar.IsOpen then
		return
	end
	pcall(function()
		box.TextEditable = false
	end)
	pcall(function()
		local GuiService = Services.GuiService
		local selected = GuiService.SelectedObject
		if selected and gui and selected:IsDescendantOf(gui) then
			GuiService.SelectedObject = nil
		end
	end)
end

function CommandBar.close()
	if not CommandBar.IsOpen then
		return
	end
	CommandBar.IsOpen = false
	CommandBar._justOpened = false
	-- Give the keyboard and mouse back to the game at once: a box that
	-- stays focused (or selected) after closing would take the next
	-- key press or click.
	letGo()
	task.defer(letGo)
	if host then
		host.Completion:Close()
	end
	Animate.fade(frame, "out", Animate.Fast, function()
		release()
		if not CommandBar.IsOpen and gui then
			gui.Enabled = false
			clear()
			letGo()
		end
	end)
	CommandBar.Closed:Fire()
	UI.fire("CommandBar", "Closed", "core")
end

function CommandBar.toggle()
	if CommandBar.IsOpen then
		CommandBar.close()
	else
		CommandBar.open()
	end
end

-- Runs an input in the console and shows its output under the bar.
function CommandBar.run(text: string)
	local Console = console()
	if not Console then
		return false
	end
	text = tostring(UI.apply("CommandBar", "Input", "core", tostring(text)))
	resultLines = {}
	capturing = true
	CommandBar.Ran:Fire(text)
	UI.fire("CommandBar", "Ran", "core", text)
	Console.run(text)
	-- Output keeps arriving for a moment (commands that yield).
	task.delay(2, function()
		capturing = false
	end)
	drawResults()
	return true
end

function CommandBar.lines(): { any }
	return resultLines
end

-- The suggestion list (tests, plugins).
function CommandBar.completion()
	return host and host.Completion
end

-- Is a screen point on the bar, its output or its suggestions?
local function onBar(point: Vector2): boolean
	if frame and Overlay.inside(barFrame, point) then
		return true
	end
	if results and results.Visible and Overlay.inside(results, point) then
		return true
	end
	local list = host and host.Completion
	return list ~= nil and list:IsOpen() and list.Panel ~= nil and Overlay.inside(list.Panel, point)
end

function CommandBar.start()
	build()
	if T.Console then
		bin:Add(T.Console.LineAdded:Connect(function(line)
			if capturing and CommandBar.IsOpen then
				table.insert(resultLines, line)
				while #resultLines > MAX_LINES do
					table.remove(resultLines, 1)
				end
				drawResults()
			end
		end))
	end
	bin:Add(UserInputService.InputBegan:Connect(function(input, processed)
		local kind = input.UserInputType
		-- A click anywhere else closes the bar.
		if kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.MouseButton2 or kind == Enum.UserInputType.Touch then
			if CommandBar.IsOpen and not onBar(Overlay.pointOf(input)) then
				CommandBar.close()
			end
			return
		end
		if kind ~= Enum.UserInputType.Keyboard then
			return
		end
		local key = input.KeyCode
		local focused = UserInputService:GetFocusedTextBox()
		if CommandBar.IsOpen and focused == box then
			if key == Enum.KeyCode.Escape then
				-- The first Escape closes the suggestions (the overlay
				-- already did, this same moment); the next one the bar.
				if host.Completion:IsOpen() or os.clock() - completionClosedAt < 0.05 then
					host.Completion:Close()
				else
					CommandBar.close()
				end
			elseif CommandBar.isKey(key) and box.Text == "" and not CommandBar._justOpened then
				-- the bar's key on an empty bar closes it (typed inside text it's
				-- just a character, e.g. a ' in a string)
				CommandBar.close()
			else
				host:_onKey(key)
				drawResults()
			end
			return
		end
		-- Only a focused text box blocks the key. The game often marks
		-- keys as processed (its own binds, the chat), so that flag is not
		-- a reason to ignore the bar's key. The bar's own box still
		-- focused while the bar is closed doesn't count.
		if focused == box and not CommandBar.IsOpen then
			pcall(function()
				box:ReleaseFocus()
			end)
			focused = nil
		end
		if focused then
			return
		end
		if CommandBar.isKey(key) then
			CommandBar.toggle()
		elseif processed then
			return
		elseif key == Enum.KeyCode.Escape and CommandBar.IsOpen then
			CommandBar.close()
		end
	end))
	bin:Add(function()
		CommandBar.IsOpen = false
		gui, frame, barFrame, box, results, host = nil, nil, nil, nil, nil, nil
		holderFrame = nil
		resultLines = {}
		for _, sig in { CommandBar.Opened, CommandBar.Closed, CommandBar.Ran } do
			sig:DisconnectAll()
		end
	end)
	T.Bin:Add(bin)
end

CommandBar.gui = function()
	build()
	return gui
end
CommandBar.box = function()
	return box
end
CommandBar.frame = function()
	return frame
end

UI.register("CommandBar", CommandBar, {
	Description = "the ' command bar (runs console input without the window)",
	Constructor = function()
		CommandBar.open()
		return CommandBar
	end,
	Events = {
		Opened = "(nothing)",
		Closed = "(nothing)",
		Ran = "text · an input was run",
	},
	Filters = {
		Input = "text · the input about to run",
	},
})

return CommandBar
