--[[
	Tungsten · console/inputassist
	The typing help shared by the console input and the command bar, so
	both behave the same: live suggestions while typing a /command,
	:plugin.command or $name, Tab completes (or accepts the highlighted
	suggestion), Up/Down move through the suggestions or the history.

	A host is a table with
		Box          the TextBox
		Completion   a console/completion list anchored to its input
		HistoryIndex, Draft, _programmatic, _completion   (state; start nil / "" / false)
		_updateHint  optional
	and gets these methods with InputAssist.mixin(Host).
]]

local T = ...
local Console = T.import("console/core")

local Assist = {}

function Assist:_cursor(): number
	local text = self.Box.Text
	local ok, position = pcall(function()
		return self.Box.CursorPosition
	end)
	if not ok or type(position) ~= "number" or position < 1 or position > #text + 1 then
		return #text + 1
	end
	return position
end

function Assist:_setCursor(position: number)
	pcall(function()
		self.Box.CursorPosition = position
	end)
end

-- Sets the text without opening suggestions.
function Assist:SetText(text: string, cursor: number?)
	self._programmatic = true
	self.Box.Text = text
	self._programmatic = false
	self:_setCursor(cursor or (#text + 1))
	self.Completion:Close()
	if self._updateHint then
		self:_updateHint()
	end
end

function Assist:GetText(): string
	return self.Box.Text
end

function Assist:_onText()
	local box = self.Box
	local text = box.Text
	-- Tab is handled as a key; drop the tab character the box inserts.
	local tabAt = text:find("\t", 1, true)
	if tabAt then
		self:SetText((text:gsub("\t", "")), tabAt)
		return
	end
	if self._updateHint then
		self:_updateHint()
	end
	if self._programmatic then
		return
	end
	self.HistoryIndex = nil
	self:_suggest(false)
end

----------------------------------------------------------------------
-- Completion
----------------------------------------------------------------------

-- Live (while typing) or forced (Tab).
function Assist:_suggest(forced: boolean)
	local text = self.Box.Text
	local cursor = self:_cursor()
	local result = Console.complete(text, cursor)
	self._completion = result
	local items = result.Items
	if not forced then
		local exact = #items == 1 and Console.Parser.trim(items[1].Text):lower() == result.Token:lower()
		if result.Live and #items > 0 and not exact and #result.Token > 0 then
			self.Completion:Show(items)
		else
			self.Completion:Close()
		end
		return result
	end
	if #items == 0 then
		self.Completion:Close()
	elseif #items == 1 then
		self:_apply(items[1])
	else
		local common = Console.commonPrefix(items)
		if #common > #result.Token then
			self:_replaceToken(result, common)
			result = Console.complete(self.Box.Text, self:_cursor())
			self._completion = result
		end
		self.Completion:Show(result.Items)
	end
	return result
end

function Assist:_replaceToken(result, replacement: string)
	local text = self.Box.Text
	local start = result.Start
	local stop = start + #result.Token -- first character after the token
	local after = text:sub(stop)
	-- Don't double the space after a completed command.
	if replacement:sub(-1) == " " and after:sub(1, 1) == " " then
		replacement = replacement:sub(1, -2)
	end
	local newText = text:sub(1, start - 1) .. replacement .. after
	self:SetText(newText, start + #replacement)
end

function Assist:_apply(item)
	local result = self._completion or Console.complete(self.Box.Text, self:_cursor())
	self:_replaceToken(result, item.Text)
	self._completion = nil
end

----------------------------------------------------------------------
-- Keys, history, running
----------------------------------------------------------------------

function Assist:_onKey(key: Enum.KeyCode)
	local completion = self.Completion
	if key == Enum.KeyCode.Tab then
		self._tabAt = os.clock()
		if completion:IsOpen() then
			local item = completion:Current()
			completion:Close()
			if item then
				self:_apply(item)
			end
		else
			self:_suggest(true)
		end
	elseif key == Enum.KeyCode.Up then
		if completion:IsOpen() then
			completion:Move(-1)
		else
			self:_history(-1)
		end
	elseif key == Enum.KeyCode.Down then
		if completion:IsOpen() then
			completion:Move(1)
		else
			self:_history(1)
		end
	end
end

function Assist:_history(step: number)
	local history = Console.History
	if #history == 0 then
		return
	end
	local index = self.HistoryIndex
	if index == nil then
		if step > 0 then
			return
		end
		self.Draft = self.Box.Text
		index = #history
	else
		index += step
	end
	if index > #history then
		self.HistoryIndex = nil
		self:SetText(self.Draft)
		return
	end
	index = math.max(1, index)
	self.HistoryIndex = index
	self:SetText(history[index])
end


-- Copies the methods into a host class.
local InputAssist = {}
function InputAssist.mixin(class)
	for name, fn in Assist do
		if class[name] == nil then
			class[name] = fn
		end
	end
	return class
end
InputAssist.Methods = Assist

return InputAssist
