--[[
	Tungsten · base/ui/components/texteditor
	Code editor with Luau syntax colors, line numbers, mouse and keyboard
	selection, copy/cut/paste, undo, Tab indenting, read-only mode, and
	scrolling both ways. Only the lines on screen are drawn, so long
	scripts stay fast.

		local editor = TextEditor.new({
			Parent = page, Text = source, ReadOnly = false,
			OnChanged = function(text) end,   -- after edits (batched per frame)
		})
		editor:SetText(s) ; editor:GetText() ; editor:SetReadOnly(true)
		editor:GetSelectedText() ; editor:SelectAll() ; editor:Focus()

	Keys: arrows (+Shift select, +Ctrl by word), Home/End, PageUp/Down,
	Ctrl+Home/End, Backspace/Delete (+Ctrl by word), Tab / Shift+Tab
	(indent / outdent; whole lines when several are selected), Enter keeps
	the indent, Ctrl+A/C/X/V/Z/Y. Paste uses the normal Ctrl+V (Volt
	can't read the clipboard directly); copy uses setclipboard.
]]

local T = ...
local signal = T.import("base/signal")
local Services = T.import("base/services")
local Theme = T.import("base/theme")
local Create = T.import("base/ui/create")
local Overlay = T.import("base/ui/overlay")
local Scroll = T.import("base/ui/components/scroll")
local Lexer = T.import("base/ui/components/luaulexer")
local Menus = T.import("base/ui/menus")
local UI = T.import("base/ui/ui")

local UserInputService = Services.UserInputService
local RunService = Services.RunService
local new = Create.new
local Sizes = Theme.Sizes

local TAB = 4 -- columns per tab stop
local TEXT_PAD = 8 -- left padding inside the code area
local UNDO_LIMIT = 200
local REPEAT_DELAY = 0.4
local REPEAT_RATE = 0.033
local DOUBLE_CLICK = 0.35
local BLINK = 0.53

local COLOR_KEYS = {
	Text = "SyntaxText",
	Space = "SyntaxText",
	Keyword = "SyntaxKeyword",
	Builtin = "SyntaxBuiltin",
	String = "SyntaxString",
	Number = "SyntaxNumber",
	Comment = "SyntaxComment",
	Operator = "SyntaxOperator",
	Function = "SyntaxFunction",
	Property = "SyntaxProperty",
	Literal = "SyntaxLiteral",
	Self = "SyntaxSelf",
}

local ESCAPES = { ["&"] = "&amp;", ["<"] = "&lt;", [">"] = "&gt;", ['"'] = "&quot;", ["'"] = "&apos;" }

local function escape(text: string): string
	return (string.gsub(text, "[&<>\"']", ESCAPES))
end

local byte, sub = string.byte, string.sub

local function isContinuation(b: number?): boolean
	return b ~= nil and b >= 0x80 and b < 0xC0
end

local function plain(text: string): boolean
	return not string.find(text, "[\t\128-\255]")
end

-- Visual column (0-based) of the byte position `pos` (0 = line start).
local function visualCol(text: string, pos: number): number
	if plain(text) then
		return math.min(pos, #text)
	end
	local col = 0
	for i = 1, math.min(pos, #text) do
		local b = byte(text, i)
		if b == 9 then
			col = (col // TAB + 1) * TAB
		elseif not isContinuation(b) then
			col += 1
		end
	end
	return col
end

local function visualLength(text: string): number
	return visualCol(text, #text)
end

-- Byte position closest to visual column `col`.
local function posFromVisual(text: string, col: number): number
	if col <= 0 then
		return 0
	end
	if plain(text) then
		return math.min(col, #text)
	end
	local current = 0
	local i = 1
	local length = #text
	while i <= length do
		local b = byte(text, i)
		local width, size
		if b == 9 then
			width = (current // TAB + 1) * TAB - current
			size = 1
		else
			width = 1
			size = 1
			while isContinuation(byte(text, i + size)) do
				size += 1
			end
		end
		if col < current + width / 2 then
			return i - 1
		end
		current += width
		i += size
		if col <= current then
			return i - 1
		end
	end
	return length
end

local function nextPos(text: string, pos: number): number
	if pos >= #text then
		return #text
	end
	pos += 1
	while pos < #text and isContinuation(byte(text, pos + 1)) do
		pos += 1
	end
	return pos
end

local function prevPos(text: string, pos: number): number
	if pos <= 0 then
		return 0
	end
	pos -= 1
	while pos > 0 and isContinuation(byte(text, pos + 1)) do
		pos -= 1
	end
	return pos
end

local function charClass(c: string): number
	if c == "" then
		return 0
	elseif string.find(c, "[%w_\128-\255]") then
		return 2
	elseif string.find(c, "%s") then
		return 1
	end
	return 3
end

-- Expand tabs and cut a line to the visual columns [first, last).
-- Returns rich text built from tokens.
local function richSlice(tokens, first: number, last: number, colors): string
	local out = {}
	local col = 0
	for _, token in tokens do
		local text = token.Text
		local hex = colors[token.Kind] or colors.Text
		local pieces = {}
		if plain(text) then
			local startCol, endCol = col, col + #text
			if endCol > first and startCol < last then
				local from = math.max(first, startCol) - startCol + 1
				local to = math.min(last, endCol) - startCol
				pieces[1] = sub(text, from, to)
			end
			col = endCol
		else
			local i, length = 1, #text
			while i <= length do
				local b = byte(text, i)
				if b == 9 then
					local stop = (col // TAB + 1) * TAB
					for c = col, stop - 1 do
						if c >= first and c < last then
							table.insert(pieces, " ")
						end
					end
					col = stop
					i += 1
				else
					local size = 1
					while isContinuation(byte(text, i + size)) do
						size += 1
					end
					if col >= first and col < last then
						table.insert(pieces, sub(text, i, i + size - 1))
					end
					col += 1
					i += size
				end
			end
		end
		local piece = table.concat(pieces)
		if piece ~= "" then
			if token.Kind == "Space" then
				table.insert(out, piece)
			else
				table.insert(out, ('<font color="%s">%s</font>'):format(hex, escape(piece)))
			end
		end
		if col >= last then
			break
		end
	end
	return table.concat(out)
end

local TextEditor = {}
TextEditor.__index = TextEditor

----------------------------------------------------------------------
-- Construction
----------------------------------------------------------------------

function TextEditor.new(props: { [string]: any })
	local self = setmetatable({}, TextEditor)
	self.Bin = signal.bin()
	self.Changed = signal.new() -- (text)
	self.ReadOnly = props.ReadOnly == true
	self.MenuId = props.Menu -- a named menu for the right-click (default "editor")
	self.Origin = props.Origin or "core"
	self.ShowNumbers = props.LineNumbers ~= false
	self._onChanged = props.OnChanged

	self.Lines = { "" }
	self.Tokens = {} -- line -> tokens
	self.States = { [1] = nil } -- line -> lexer state at the start of the line
	self.ValidStates = 1 -- States[1..ValidStates] are correct
	self.MaxCols = 0
	self.CursorLine, self.CursorCol = 1, 0
	self.AnchorLine, self.AnchorCol = nil, nil
	self.PreferredCol = 0
	self.Focused = false
	self.Undo, self.Redo = {}, {}
	self._lastEdit = { Kind = "", Time = 0 }
	self._repeatToken = 0
	self._blinkToken = 0
	self._changeQueued = false
	self._lastClick = { Time = 0, Line = 0, Col = 0 }

	self.FontSize = Sizes.CodeText
	self.LineHeight = Sizes.CodeLine
	self.CharWidth = math.max(1, Create.textWidth(string.rep("0", 100), self.FontSize, "Mono") / 100)

	local root = new("Frame", {
		Name = props.Name or "Editor",
		Size = props.Size or UDim2.fromScale(1, 1),
		Position = props.Position or UDim2.new(),
		LayoutOrder = props.LayoutOrder or 0,
		ClipsDescendants = true,
		Theme = { BackgroundColor3 = "Chrome" },
	})
	self.Instance = root
	self.Bin:Add(root)
	Create.corner(root, Sizes.RadiusSmall)
	self.Stroke = Create.stroke(root, "Border", 1, 0)

	self.Gutter = new("Frame", {
		Name = "Gutter",
		Size = UDim2.new(0, 40, 1, 0),
		ClipsDescendants = true,
		Visible = self.ShowNumbers,
		Theme = { BackgroundColor3 = "EditorGutter" },
		Parent = root,
	})
	self.NumberLabels = {}

	local scroll = Scroll.new({ Mode = "virtual", Direction = "XY", Parent = root })
	self.Scroll = scroll
	self.Bin:Add(scroll)
	self.View = scroll.Instance

	self.LineHighlight = new("Frame", {
		Name = "CurrentLine",
		Size = UDim2.new(1, 0, 0, self.LineHeight),
		Visible = false,
		ZIndex = 1,
		Theme = { BackgroundColor3 = "EditorLine" },
		Parent = self.View,
	})
	self.Cursor = new("Frame", {
		Name = "Cursor",
		Size = UDim2.fromOffset(2, self.LineHeight - 2),
		Visible = false,
		ZIndex = 6,
		Theme = { BackgroundColor3 = "Accent" },
		Parent = self.View,
	})
	self.RowPool = {}

	-- Clicks and drags land on this transparent layer above the text
	-- (scroll bars sit above it).
	local hit = new("TextButton", {
		Name = "Hit",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Selectable = false,
		ZIndex = 30,
		Parent = self.View,
	})
	self.Hit = hit

	-- Receives typing and pastes; never shown.
	local box = new("TextBox", {
		Name = "Input",
		Size = UDim2.fromOffset(2, 2),
		BackgroundTransparency = 1,
		TextTransparency = 1,
		Text = "",
		MultiLine = true,
		ClearTextOnFocus = false,
		TextEditable = not self.ReadOnly,
		ShowNativeInput = true,
		Parent = root,
	})
	self.Box = box

	self:_wireInput()
	self.Bin:Add(scroll.Changed:Connect(function()
		self:_render()
	end))
	self.Bin:Add(self.View:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		self:_render()
	end))
	self.Bin:Add(Theme.Changed:Connect(function()
		self:_render()
	end))

	self.Bin:Add(Create.cleanupWith(root, self))
	if props.Parent then
		root.Parent = props.Parent
	end
	self:SetText(props.Text or "", true)
	UI.fire("TextEditor", "Created", self.Origin, self, props)
	return self
end

----------------------------------------------------------------------
-- Text model
----------------------------------------------------------------------

function TextEditor:GetText(): string
	return table.concat(self.Lines, "\n")
end

function TextEditor:_recomputeMax()
	local max = 0
	for _, line in self.Lines do
		local length = if plain(line) then #line else visualLength(line)
		if length > max then
			max = length
		end
	end
	self.MaxCols = max
end

function TextEditor:_invalidate(fromLine: number)
	for line in self.Tokens do
		if line >= fromLine then
			self.Tokens[line] = nil
		end
	end
	if self.ValidStates > fromLine then
		self.ValidStates = fromLine
	end
end

function TextEditor:SetText(text: string, silent: boolean?)
	text = string.gsub(tostring(text), "\r\n?", "\n")
	self.Lines = string.split(text, "\n")
	if #self.Lines == 0 then
		self.Lines = { "" }
	end
	self.Tokens = {}
	self.States = {}
	self.ValidStates = 1
	self.CursorLine, self.CursorCol = 1, 0
	self.AnchorLine, self.AnchorCol = nil, nil
	self.PreferredCol = 0
	self.Undo, self.Redo = {}, {}
	self:_recomputeMax()
	self:_updateGutter()
	self:_updateCanvas()
	self.Scroll:ScrollTo(Vector2.zero)
	self:_render()
	if not silent then
		self:_queueChanged()
	end
end

function TextEditor:_queueChanged()
	if self._changeQueued then
		return
	end
	self._changeQueued = true
	task.defer(function()
		self._changeQueued = false
		if not self.Instance.Parent then
			return
		end
		local text = self:GetText()
		if self._onChanged then
			local ok, err = pcall(self._onChanged, text)
			if not ok then
				T.Log.error("editor", "change callback failed: " .. tostring(err))
			end
		end
		self.Changed:Fire(text)
		if UI.has("TextEditor", "Changed") then
			UI.fire("TextEditor", "Changed", self.Origin, self, text)
		end
	end)
end

-- Tokens for a line, lexing (and caching) everything above it as needed.
function TextEditor:_tokens(line: number)
	local cached = self.Tokens[line]
	if cached then
		return cached
	end
	local states = self.States
	for index = self.ValidStates, line do
		local tokens, nextState = Lexer.line(self.Lines[index] or "", states[index])
		self.Tokens[index] = tokens
		states[index + 1] = nextState
		self.ValidStates = index + 1
	end
	if self.Tokens[line] == nil then
		local tokens, nextState = Lexer.line(self.Lines[line] or "", states[line])
		self.Tokens[line] = tokens
		states[line + 1] = nextState
	end
	return self.Tokens[line]
end

----------------------------------------------------------------------
-- Selection helpers
----------------------------------------------------------------------

function TextEditor:HasSelection(): boolean
	return self.AnchorLine ~= nil and (self.AnchorLine ~= self.CursorLine or self.AnchorCol ~= self.CursorCol)
end

-- Ordered selection: line1, col1, line2, col2.
function TextEditor:_range(): (number, number, number, number)
	local l1, c1, l2, c2 = self.AnchorLine or self.CursorLine, self.AnchorCol or self.CursorCol, self.CursorLine, self.CursorCol
	if l1 > l2 or (l1 == l2 and c1 > c2) then
		l1, c1, l2, c2 = l2, c2, l1, c1
	end
	return l1, c1, l2, c2
end

function TextEditor:_textBetween(l1: number, c1: number, l2: number, c2: number): string
	local lines = self.Lines
	if l1 == l2 then
		return sub(lines[l1], c1 + 1, c2)
	end
	local parts = { sub(lines[l1], c1 + 1) }
	for index = l1 + 1, l2 - 1 do
		table.insert(parts, lines[index])
	end
	table.insert(parts, sub(lines[l2], 1, c2))
	return table.concat(parts, "\n")
end

function TextEditor:GetSelectedText(): string
	if not self:HasSelection() then
		return ""
	end
	return self:_textBetween(self:_range())
end

function TextEditor:SelectAll()
	self.AnchorLine, self.AnchorCol = 1, 0
	self.CursorLine = #self.Lines
	self.CursorCol = #self.Lines[#self.Lines]
	self:_afterMove(false)
end

function TextEditor:_clearSelection()
	self.AnchorLine, self.AnchorCol = nil, nil
end

----------------------------------------------------------------------
-- Editing
----------------------------------------------------------------------

function TextEditor:_snapshot()
	return {
		Lines = table.clone(self.Lines),
		CursorLine = self.CursorLine,
		CursorCol = self.CursorCol,
	}
end

-- Save an undo point. Runs of typing (or deleting) within a second share one.
function TextEditor:_pushUndo(kind: string)
	local now = os.clock()
	local last = self._lastEdit
	local merge = (kind == "type" or kind == "delete") and last.Kind == kind and now - last.Time < 1
	last.Kind, last.Time = kind, now
	table.clear(self.Redo)
	if merge then
		return
	end
	table.insert(self.Undo, self:_snapshot())
	if #self.Undo > UNDO_LIMIT then
		table.remove(self.Undo, 1)
	end
end

function TextEditor:_restore(snapshot)
	self.Lines = snapshot.Lines
	self.CursorLine = math.clamp(snapshot.CursorLine, 1, #self.Lines)
	self.CursorCol = math.clamp(snapshot.CursorCol, 0, #self.Lines[self.CursorLine])
	self:_clearSelection()
	self.Tokens = {}
	self.ValidStates = 1
	self:_recomputeMax()
	self:_edited(1)
end

function TextEditor:UndoStep()
	local snapshot = table.remove(self.Undo)
	if snapshot then
		table.insert(self.Redo, self:_snapshot())
		self._lastEdit.Kind = ""
		self:_restore(snapshot)
	end
end

function TextEditor:RedoStep()
	local snapshot = table.remove(self.Redo)
	if snapshot then
		table.insert(self.Undo, self:_snapshot())
		self._lastEdit.Kind = ""
		self:_restore(snapshot)
	end
end

-- After any change to Lines from `fromLine` down.
function TextEditor:_edited(fromLine: number)
	self:_invalidate(fromLine)
	local length = visualLength(self.Lines[self.CursorLine] or "")
	if length > self.MaxCols then
		self.MaxCols = length
	end
	self:_updateGutter()
	self:_updateCanvas()
	self.PreferredCol = visualCol(self.Lines[self.CursorLine], self.CursorCol)
	self:_reveal()
	self:_render()
	self:_queueChanged()
	-- Shrinking lines may lower the widest line; check once per frame.
	if not self._maxQueued then
		self._maxQueued = true
		task.defer(function()
			self._maxQueued = false
			local before = self.MaxCols
			self:_recomputeMax()
			if self.MaxCols ~= before then
				self:_updateCanvas()
			end
		end)
	end
end

function TextEditor:_deleteRange(l1: number, c1: number, l2: number, c2: number)
	local lines = self.Lines
	local head = sub(lines[l1], 1, c1)
	local tail = sub(lines[l2], c2 + 1)
	lines[l1] = head .. tail
	for _ = l1 + 1, l2 do
		table.remove(lines, l1 + 1)
	end
	self.CursorLine, self.CursorCol = l1, c1
	self:_clearSelection()
end

function TextEditor:_deleteSelection(): boolean
	if not self:HasSelection() then
		self:_clearSelection()
		return false
	end
	local l1, c1, l2, c2 = self:_range()
	self:_deleteRange(l1, c1, l2, c2)
	return true
end

-- Insert text at the cursor (replacing the selection).
function TextEditor:Insert(text: string, kind: string?)
	if self.ReadOnly then
		return
	end
	text = string.gsub(text, "\r\n?", "\n")
	if text == "" then
		return
	end
	self:_pushUndo(kind or (if #text == 1 and text ~= "\n" then "type" else "insert"))
	self:_deleteSelection()

	local lines = self.Lines
	local line, col = self.CursorLine, self.CursorCol
	local current = lines[line]
	local head, tail = sub(current, 1, col), sub(current, col + 1)
	local pieces = string.split(text, "\n")
	if #pieces == 1 then
		lines[line] = head .. text .. tail
		self.CursorCol = col + #text
	else
		lines[line] = head .. pieces[1]
		for index = 2, #pieces do
			table.insert(lines, line + index - 1, pieces[index])
		end
		local last = line + #pieces - 1
		self.CursorLine = last
		self.CursorCol = #lines[last]
		lines[last] ..= tail
		for index = line, last do
			local length = visualLength(lines[index])
			if length > self.MaxCols then
				self.MaxCols = length
			end
		end
	end
	self:_edited(line)
end

function TextEditor:_newline()
	local current = self.Lines[self.CursorLine]
	local indent = string.match(current, "^[ \t]*") or ""
	-- Don't carry indent past the cursor (pressing Enter inside the indent).
	indent = sub(indent, 1, self.CursorCol)
	self:Insert("\n" .. indent, "insert")
end

function TextEditor:_backspace(word: boolean)
	if self.ReadOnly then
		return
	end
	if self:HasSelection() then
		self:_pushUndo("delete")
		self:_deleteSelection()
		self:_edited(self.CursorLine)
		return
	end
	local line, col = self.CursorLine, self.CursorCol
	if col == 0 and line == 1 then
		return
	end
	self:_pushUndo("delete")
	if col == 0 then
		local previous = self.Lines[line - 1]
		self:_deleteRange(line - 1, #previous, line, 0)
	else
		local target = if word then self:_wordLeft(line, col) else prevPos(self.Lines[line], col)
		self:_deleteRange(line, target, line, col)
	end
	self:_edited(self.CursorLine)
end

function TextEditor:_delete(word: boolean)
	if self.ReadOnly then
		return
	end
	if self:HasSelection() then
		self:_pushUndo("delete")
		self:_deleteSelection()
		self:_edited(self.CursorLine)
		return
	end
	local line, col = self.CursorLine, self.CursorCol
	local text = self.Lines[line]
	if col >= #text and line == #self.Lines then
		return
	end
	self:_pushUndo("delete")
	if col >= #text then
		self:_deleteRange(line, col, line + 1, 0)
	else
		local target = if word then self:_wordRight(line, col) else nextPos(text, col)
		self:_deleteRange(line, col, line, target)
	end
	self:_edited(line)
end

-- Tab / Shift+Tab: indent or outdent. With a multi-line selection every
-- selected line moves; otherwise Tab inserts a tab at the cursor.
function TextEditor:_indent(outdent: boolean)
	if self.ReadOnly then
		return
	end
	local l1, c1, l2, c2 = self:_range()
	local multi = self:HasSelection() and l1 ~= l2
	if not multi and not outdent then
		self:Insert("\t", "insert")
		return
	end
	if multi and c2 == 0 and l2 > l1 then
		l2 -= 1 -- a selection ending at column 0 doesn't include that line
	end
	self:_pushUndo("indent")
	local lines = self.Lines
	local shiftAnchor, shiftCursor = 0, 0
	for index = l1, l2 do
		local text = lines[index]
		local change = 0
		if outdent then
			local lead = string.match(text, "^\t") or string.match(text, "^ ? ? ? ?") or ""
			lines[index] = sub(text, #lead + 1)
			change = -#lead
		else
			lines[index] = "\t" .. text
			change = 1
		end
		if index == self.CursorLine then
			shiftCursor = change
		end
		if index == self.AnchorLine then
			shiftAnchor = change
		end
	end
	self.CursorCol = math.max(0, self.CursorCol + shiftCursor)
	if self.AnchorLine then
		self.AnchorCol = math.max(0, self.AnchorCol + shiftAnchor)
	end
	self:_edited(l1)
end

----------------------------------------------------------------------
-- Cursor movement
----------------------------------------------------------------------

function TextEditor:_wordLeft(line: number, col: number): number
	local text = self.Lines[line]
	local pos = col
	-- skip spaces, then a run of one class
	while pos > 0 and charClass(sub(text, pos, pos)) == 1 do
		pos -= 1
	end
	local class = charClass(sub(text, pos, pos))
	while pos > 0 and charClass(sub(text, pos, pos)) == class do
		pos -= 1
	end
	return pos
end

function TextEditor:_wordRight(line: number, col: number): number
	local text = self.Lines[line]
	local pos = col
	local length = #text
	local class = charClass(sub(text, pos + 1, pos + 1))
	while pos < length and charClass(sub(text, pos + 1, pos + 1)) == class do
		pos += 1
	end
	while pos < length and charClass(sub(text, pos + 1, pos + 1)) == 1 do
		pos += 1
	end
	return pos
end

-- Begin a move: keep or start a selection (extend) or drop it.
function TextEditor:_beginMove(extend: boolean)
	if extend then
		if not self.AnchorLine then
			self.AnchorLine, self.AnchorCol = self.CursorLine, self.CursorCol
		end
	else
		self:_clearSelection()
	end
end

function TextEditor:_afterMove(keepPreferred: boolean)
	if not keepPreferred then
		self.PreferredCol = visualCol(self.Lines[self.CursorLine], self.CursorCol)
	end
	self:_reveal()
	self:_render()
	self:_blink()
end

function TextEditor:_move(key: Enum.KeyCode, shift: boolean, ctrl: boolean)
	local lines = self.Lines
	local line, col = self.CursorLine, self.CursorCol
	local text = lines[line]
	local keepPreferred = false

	-- Without Shift, Left/Right first collapse a selection to its edge.
	if not shift and self:HasSelection() and (key == Enum.KeyCode.Left or key == Enum.KeyCode.Right) then
		local l1, c1, l2, c2 = self:_range()
		self:_clearSelection()
		if key == Enum.KeyCode.Left then
			self.CursorLine, self.CursorCol = l1, c1
		else
			self.CursorLine, self.CursorCol = l2, c2
		end
		self:_afterMove(false)
		return
	end
	self:_beginMove(shift)

	if key == Enum.KeyCode.Left then
		if col > 0 then
			col = if ctrl then self:_wordLeft(line, col) else prevPos(text, col)
		elseif line > 1 then
			line -= 1
			col = #lines[line]
		end
	elseif key == Enum.KeyCode.Right then
		if col < #text then
			col = if ctrl then self:_wordRight(line, col) else nextPos(text, col)
		elseif line < #lines then
			line += 1
			col = 0
		end
	elseif key == Enum.KeyCode.Up or key == Enum.KeyCode.Down or key == Enum.KeyCode.PageUp or key == Enum.KeyCode.PageDown then
		local page = math.max(1, math.floor(self.Scroll:ViewSize().Y / self.LineHeight) - 1)
		local step = if key == Enum.KeyCode.Up then -1 elseif key == Enum.KeyCode.Down then 1 elseif key == Enum.KeyCode.PageUp then -page else page
		local target = math.clamp(line + step, 1, #lines)
		if target == line then
			col = if step < 0 then 0 else #text
		else
			line = target
			col = posFromVisual(lines[line], self.PreferredCol)
			keepPreferred = true
		end
	elseif key == Enum.KeyCode.Home then
		if ctrl then
			line, col = 1, 0
		else
			-- Toggle between the first non-blank character and column 0.
			local indent = #(string.match(text, "^[ \t]*") or "")
			col = if col == indent then 0 else indent
		end
	elseif key == Enum.KeyCode.End then
		if ctrl then
			line = #lines
		end
		col = #lines[line]
	end

	self.CursorLine, self.CursorCol = line, col
	self:_afterMove(keepPreferred)
end

----------------------------------------------------------------------
-- Clipboard
----------------------------------------------------------------------

function TextEditor:Copy(): boolean
	local text = self:GetSelectedText()
	if text == "" then
		return false
	end
	local ok, err = pcall(setclipboard, text)
	if not ok then
		T.Log.warn("editor", "copy failed: " .. tostring(err))
	end
	return ok
end

function TextEditor:Cut()
	if self.ReadOnly or not self:HasSelection() then
		return
	end
	if self:Copy() then
		self:_pushUndo("cut")
		self:_deleteSelection()
		self:_edited(self.CursorLine)
	end
end

----------------------------------------------------------------------
-- Geometry
----------------------------------------------------------------------

function TextEditor:_gutterWidth(): number
	if not self.ShowNumbers then
		return 0
	end
	local digits = math.max(2, #tostring(#self.Lines))
	return math.ceil(digits * self.CharWidth) + 22
end

function TextEditor:_updateGutter()
	local width = self:_gutterWidth()
	if width ~= self._gutterW then
		self._gutterW = width
		self.Gutter.Size = UDim2.new(0, width, 1, 0)
		self.View.Position = UDim2.fromOffset(width, 0)
		self.View.Size = UDim2.new(1, -width, 1, 0)
	end
end

function TextEditor:_updateCanvas()
	local width = math.ceil(self.MaxCols * self.CharWidth) + TEXT_PAD * 2 + self.CharWidth * 2
	-- Leave some room under the last line so it isn't hidden by the bar.
	local height = #self.Lines * self.LineHeight + self.LineHeight
	self.Scroll:SetCanvasSize(Vector2.new(width, height))
end

-- Screen point -> text position.
function TextEditor:_positionAt(point: Vector2): (number, number)
	local at = Create.toLocal(point, self.View) -- layout pixels inside the view
	local offset = self.Scroll.Offset
	local y = at.Y + offset.Y
	local line = math.clamp(math.floor(y / self.LineHeight) + 1, 1, #self.Lines)
	local x = at.X + offset.X - TEXT_PAD
	local col = math.max(0, math.floor(x / self.CharWidth + 0.5))
	return line, posFromVisual(self.Lines[line], col)
end

-- Scroll so the cursor is visible.
function TextEditor:_reveal()
	local top = (self.CursorLine - 1) * self.LineHeight
	self.Scroll:Reveal("Y", top, top + self.LineHeight, self.LineHeight, false)
	local x = TEXT_PAD + visualCol(self.Lines[self.CursorLine], self.CursorCol) * self.CharWidth
	self.Scroll:Reveal("X", x - TEXT_PAD, x + self.CharWidth * 2, self.CharWidth * 4, false)
end

----------------------------------------------------------------------
-- Drawing
----------------------------------------------------------------------

function TextEditor:_row(slot: number)
	local row = self.RowPool[slot]
	if row then
		return row
	end
	local selection = new("Frame", {
		Name = "Selection",
		Visible = false,
		ZIndex = 2,
		Theme = { BackgroundColor3 = "Selection" },
		Parent = self.View,
	})
	local label = new("TextLabel", {
		Name = "Line" .. slot,
		FontFace = Theme.Fonts.Mono,
		TextSize = self.FontSize,
		RichText = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		Size = UDim2.new(0, 10, 0, self.LineHeight),
		ZIndex = 3,
		Parent = self.View,
	})
	local number = new("TextLabel", {
		Name = "Number" .. slot,
		FontFace = Theme.Fonts.Mono,
		TextSize = Sizes.TextSmall + 1,
		TextXAlignment = Enum.TextXAlignment.Right,
		Size = UDim2.new(1, -12, 0, self.LineHeight),
		Theme = { TextColor3 = "TextMuted" },
		Parent = self.Gutter,
	})
	row = { Selection = selection, Label = label, Number = number }
	self.RowPool[slot] = row
	return row
end

function TextEditor:_render()
	local scroll = self.Scroll
	local offset = scroll.Offset
	local view = scroll:ViewSize()
	local lineHeight, charWidth = self.LineHeight, self.CharWidth
	local lines = self.Lines
	local first = math.max(1, math.floor(offset.Y / lineHeight) + 1)
	local count = math.ceil(math.max(view.Y, lineHeight) / lineHeight) + 1
	local firstCol = math.max(0, math.floor((offset.X - TEXT_PAD) / charWidth))
	local lastCol = firstCol + math.ceil(math.max(view.X, 1) / charWidth) + 2
	local textX = TEXT_PAD + firstCol * charWidth - offset.X

	local colors = {}
	for kind, key in COLOR_KEYS do
		colors[kind] = Theme.hex(key)
	end

	local hasSelection = self:HasSelection()
	local l1, c1, l2, c2 = self:_range()

	for slot = 1, math.max(count, #self.RowPool) do
		local index = first + slot - 1
		local text = lines[index]
		if slot > count or text == nil then
			local row = self.RowPool[slot]
			if row then
				row.Label.Visible = false
				row.Selection.Visible = false
				row.Number.Visible = false
			end
		else
			local row = self:_row(slot)
			local y = (index - 1) * lineHeight - offset.Y
			local label = row.Label
			label.Visible = true
			label.Position = UDim2.fromOffset(math.floor(textX + 0.5), math.floor(y + 0.5))
			label.Size = UDim2.new(0, math.ceil((lastCol - firstCol) * charWidth), 0, lineHeight)
			label.Text = richSlice(self:_tokens(index), firstCol, lastCol, colors)

			local number = row.Number
			number.Visible = self.ShowNumbers
			number.Position = UDim2.fromOffset(0, math.floor(y + 0.5))
			number.Text = tostring(index)
			Theme.bind(number, "TextColor3", if index == self.CursorLine and self.Focused then "TextDim" else "TextMuted")

			-- Selection band for this line.
			local selection = row.Selection
			if hasSelection and index >= l1 and index <= l2 then
				local fromCol = if index == l1 then visualCol(text, c1) else 0
				local toCol = if index == l2 then visualCol(text, c2) else visualLength(text) + 1
				local x1 = TEXT_PAD + fromCol * charWidth - offset.X
				local width = math.max(0, (toCol - fromCol) * charWidth)
				selection.Visible = width > 0
				selection.Position = UDim2.fromOffset(math.floor(x1 + 0.5), math.floor(y + 0.5))
				selection.Size = UDim2.fromOffset(math.ceil(width), lineHeight)
			else
				selection.Visible = false
			end
		end
	end

	-- Current line + cursor.
	local cursorY = (self.CursorLine - 1) * lineHeight - offset.Y
	self.LineHighlight.Visible = self.Focused and not hasSelection
	self.LineHighlight.Position = UDim2.fromOffset(0, math.floor(cursorY + 0.5))
	local cursorX = TEXT_PAD + visualCol(lines[self.CursorLine], self.CursorCol) * charWidth - offset.X
	self.Cursor.Position = UDim2.fromOffset(math.floor(cursorX), math.floor(cursorY + 1.5))
	if not self.Focused then
		self.Cursor.Visible = false
	end
	-- Keep the input box near the cursor (helps IME popups appear in place).
	local area = Create.layoutSize(self.Instance)
	self.Box.Position = UDim2.fromOffset(
		math.clamp(cursorX + (self._gutterW or 0), 0, math.max(0, area.X - 4)),
		math.clamp(cursorY, 0, math.max(0, area.Y - 4))
	)
end

function TextEditor:_blink()
	self._blinkToken += 1
	local token = self._blinkToken
	if not self.Focused then
		self.Cursor.Visible = false
		return
	end
	self.Cursor.Visible = true
	task.spawn(function()
		while self._blinkToken == token and self.Focused do
			task.wait(BLINK)
			if self._blinkToken ~= token or not self.Focused then
				break
			end
			self.Cursor.Visible = not self.Cursor.Visible
		end
	end)
end

----------------------------------------------------------------------
-- Input
----------------------------------------------------------------------

local function isDown(...): boolean
	for _, key in { ... } do
		if UserInputService:IsKeyDown(key) then
			return true
		end
	end
	return false
end

local function ctrlDown(): boolean
	return isDown(Enum.KeyCode.LeftControl, Enum.KeyCode.RightControl, Enum.KeyCode.LeftSuper, Enum.KeyCode.RightSuper)
end

local function shiftDown(): boolean
	return isDown(Enum.KeyCode.LeftShift, Enum.KeyCode.RightShift)
end

-- Run `action` now and keep repeating while the key is held.
function TextEditor:_repeat(key: Enum.KeyCode, action: () -> ())
	self._repeatToken += 1
	local token = self._repeatToken
	action()
	task.spawn(function()
		task.wait(REPEAT_DELAY)
		while self._repeatToken == token and self.Focused and UserInputService:IsKeyDown(key) do
			action()
			task.wait(REPEAT_RATE)
		end
	end)
end

local REPEATING = {
	[Enum.KeyCode.Left] = true,
	[Enum.KeyCode.Right] = true,
	[Enum.KeyCode.Up] = true,
	[Enum.KeyCode.Down] = true,
	[Enum.KeyCode.PageUp] = true,
	[Enum.KeyCode.PageDown] = true,
	[Enum.KeyCode.Backspace] = true,
	[Enum.KeyCode.Delete] = true,
}

function TextEditor:_onKey(key: Enum.KeyCode)
	local ctrl, shift = ctrlDown(), shiftDown()

	if ctrl and not REPEATING[key] and key ~= Enum.KeyCode.Home and key ~= Enum.KeyCode.End then
		if key == Enum.KeyCode.A then
			self:SelectAll()
		elseif key == Enum.KeyCode.C then
			self:Copy()
		elseif key == Enum.KeyCode.X then
			self:Cut()
		elseif key == Enum.KeyCode.Z then
			if shift then
				self:RedoStep()
			else
				self:UndoStep()
			end
		elseif key == Enum.KeyCode.Y then
			self:RedoStep()
		end
		return
	end

	if key == Enum.KeyCode.Tab then
		self._tabAt = os.clock()
		self:_indent(shift)
	elseif key == Enum.KeyCode.Backspace then
		self:_repeat(key, function()
			self:_backspace(ctrlDown())
		end)
	elseif key == Enum.KeyCode.Delete then
		self:_repeat(key, function()
			self:_delete(ctrlDown())
		end)
	elseif REPEATING[key] then
		self:_repeat(key, function()
			self:_move(key, shiftDown(), ctrlDown())
		end)
	elseif key == Enum.KeyCode.Home or key == Enum.KeyCode.End then
		self:_move(key, shift, ctrl)
	end
end

function TextEditor:_wireInput()
	local box = self.Box
	local bin = self.Bin

	bin:Add(box.Focused:Connect(function()
		self.Focused = true
		Theme.bind(self.Stroke, "Color", "BorderStrong")
		self:_render()
		self:_blink()
	end))
	bin:Add(box.FocusLost:Connect(function()
		self.Focused = false
		self._repeatToken += 1
		Theme.bind(self.Stroke, "Color", "Border")
		self:_render()
		self:_blink()
	end))

	-- Typed characters, Enter and Ctrl+V all arrive as box text.
	bin:Add(box:GetPropertyChangedSignal("Text"):Connect(function()
		local text = box.Text
		if text == "" then
			return
		end
		box.Text = ""
		if self.ReadOnly then
			return
		end
		-- Tab is handled by the key handler; drop the box's own copy.
		if self._tabAt and os.clock() - self._tabAt < 0.25 then
			text = string.gsub(text, "\t", "")
			if text == "" then
				return
			end
		end
		if text == "\n" or text == "\r" then
			self:_newline()
		else
			self:Insert(text)
		end
	end))

	bin:Add(UserInputService.InputBegan:Connect(function(input)
		if not self.Focused or input.UserInputType ~= Enum.UserInputType.Keyboard then
			return
		end
		self:_onKey(input.KeyCode)
	end))

	-- Mouse: click to place, drag to select, Shift+click to extend,
	-- double-click selects a word, right-click opens the edit menu.
	local hit = self.Hit
	bin:Add(hit.InputBegan:Connect(function(input)
		local kind = input.UserInputType
		if kind == Enum.UserInputType.MouseButton2 then
			self:_contextMenu(Overlay.pointOf(input))
			return
		end
		if kind ~= Enum.UserInputType.MouseButton1 and kind ~= Enum.UserInputType.Touch then
			return
		end
		local point = Overlay.pointOf(input)
		local line, col = self:_positionAt(point)
		-- The click may also make Roblox drop the box's focus; take it back
		-- after this input has been processed.
		task.defer(function()
			if self.Instance.Parent then
				box:CaptureFocus()
			end
		end)

		local now = os.clock()
		local last = self._lastClick
		if now - last.Time < DOUBLE_CLICK and last.Line == line and math.abs(last.Col - col) <= 1 then
			-- Select the word under the pointer.
			last.Time = 0
			local text = self.Lines[line]
			local class = charClass(sub(text, col + 1, col + 1))
			local from, to = col, col
			while from > 0 and charClass(sub(text, from, from)) == class do
				from -= 1
			end
			while to < #text and charClass(sub(text, to + 1, to + 1)) == class do
				to += 1
			end
			self.AnchorLine, self.AnchorCol = line, from
			self.CursorLine, self.CursorCol = line, to
			self:_afterMove(false)
			return
		end
		last.Time, last.Line, last.Col = now, line, col

		if shiftDown() then
			self:_beginMove(true)
		else
			self.AnchorLine, self.AnchorCol = line, col
		end
		self.CursorLine, self.CursorCol = line, col
		self:_afterMove(false)

		-- Drag selection with auto-scroll past the edges.
		local pointer = point
		local moveConn, endConn, stepConn
		local function update()
			local l, c = self:_positionAt(pointer)
			if l ~= self.CursorLine or c ~= self.CursorCol then
				self.CursorLine, self.CursorCol = l, c
				self:_afterMove(false)
			end
		end
		moveConn = UserInputService.InputChanged:Connect(function(move)
			if move.UserInputType == Enum.UserInputType.MouseMovement or move.UserInputType == Enum.UserInputType.Touch then
				pointer = Overlay.pointOf(move)
				update()
			end
		end)
		stepConn = RunService.RenderStepped:Connect(function()
			local origin, size = self.View.AbsolutePosition, self.View.AbsoluteSize
			local dy = if pointer.Y < origin.Y then pointer.Y - origin.Y elseif pointer.Y > origin.Y + size.Y then pointer.Y - origin.Y - size.Y else 0
			local dx = if pointer.X < origin.X then pointer.X - origin.X elseif pointer.X > origin.X + size.X then pointer.X - origin.X - size.X else 0
			if dx ~= 0 or dy ~= 0 then
				-- how far past the edge, on screen -> layout pixels
				local factor = Create.scaleOf(self.View)
				self.Scroll:ScrollBy(Vector2.new(dx, dy) * (0.4 / factor), false)
				update()
			end
		end)
		endConn = UserInputService.InputEnded:Connect(function(ended)
			if ended.UserInputType == Enum.UserInputType.MouseButton1 or ended.UserInputType == Enum.UserInputType.Touch then
				moveConn:Disconnect()
				endConn:Disconnect()
				stepConn:Disconnect()
				if not self:HasSelection() then
					self:_clearSelection()
					self:_render()
				end
			end
		end)
		bin:Add(moveConn)
		bin:Add(endConn)
		bin:Add(stepConn)
	end))
end

-- "editor" (open to plugins): ctx.Editor is the editor.
Menus.define("editor", {
	Title = "Code editor",
	Sections = { "clipboard", "edit" },
})
Menus.addMany("editor", {
	{
		Id = "copy",
		Section = "clipboard",
		Order = 10,
		Text = "Copy",
		Icon = "copy",
		Shortcut = "Ctrl+C",
		Disabled = function(ctx)
			return not ctx.Editor:HasSelection()
		end,
		Callback = function(ctx)
			ctx.Editor:Copy()
		end,
	},
	{
		Id = "cut",
		Section = "clipboard",
		Order = 20,
		Text = "Cut",
		Icon = "cut",
		Shortcut = "Ctrl+X",
		Disabled = function(ctx)
			return ctx.Editor.ReadOnly or not ctx.Editor:HasSelection()
		end,
		Callback = function(ctx)
			ctx.Editor:Cut()
		end,
	},
	{
		Id = "select_all",
		Section = "edit",
		Order = 10,
		Text = "Select all",
		Shortcut = "Ctrl+A",
		Callback = function(ctx)
			ctx.Editor:SelectAll()
			ctx.Editor.Box:CaptureFocus()
		end,
	},
	{
		Id = "undo",
		Section = "edit",
		Order = 20,
		Text = "Undo",
		Shortcut = "Ctrl+Z",
		Disabled = function(ctx)
			return ctx.Editor.ReadOnly or #ctx.Editor.Undo == 0
		end,
		Callback = function(ctx)
			ctx.Editor:UndoStep()
		end,
	},
	{
		Id = "redo",
		Section = "edit",
		Order = 30,
		Text = "Redo",
		Shortcut = "Ctrl+Y",
		Disabled = function(ctx)
			return ctx.Editor.ReadOnly or #ctx.Editor.Redo == 0
		end,
		Callback = function(ctx)
			ctx.Editor:RedoStep()
		end,
	},
})

-- An editor may use its own menu id (props.Menu) for its own entries.
function TextEditor:_contextMenu(point: Vector2)
	return Menus.open(self.MenuId or "editor", { Editor = self }, { Position = point, Origin = self.Origin })
end

----------------------------------------------------------------------
-- Public
----------------------------------------------------------------------

function TextEditor:SetReadOnly(readOnly: boolean)
	self.ReadOnly = readOnly == true
	self.Box.TextEditable = not self.ReadOnly
end

function TextEditor:Focus()
	self.Box:CaptureFocus()
end

function TextEditor:Blur()
	self.Box:ReleaseFocus()
end

function TextEditor:Destroy()
	self._repeatToken += 1
	self._blinkToken += 1
	self.Bin:Clean()
	self.Changed:DisconnectAll()
end

return UI.register("TextEditor", TextEditor, {
	Description = "multi-line code editor with Luau highlighting",
	Events = {
		Created = "editor, props",
		Changed = "editor, text",
	},
})
