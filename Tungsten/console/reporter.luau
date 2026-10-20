--[[
	Tungsten · console/reporter
	A reporter prints messages for one source (a plugin, the explorer) to
	the console, with that source's name in front:

		local out = Console.reporter("myplugin", { Label = "My Plugin" })
		out:info("loaded 12 items")          [plugin] My Plugin: loaded 12 items
		out:success("saved")                 [plugin] My Plugin: saved
		out:warn("3 items skipped")          [!] My Plugin: 3 items skipped
		out:error("could not read the file") [x] My Plugin: could not read the file
		out:detail("more about it")              more about it
		out:value("result = ", value)        [plugin] My Plugin: result = 5 <number>

		local ok, result = out:try(fn, ...)   -- runs fn; a failure becomes an [x] line
		local safe = out:wrap(fn, "Refresh")  -- fn guarded the same way

	Core sources (Plugin = false, e.g. the explorer) use the normal
	prefixes instead of [plugin]: [*] Explorer: …, [+] Explorer: ….

	Errors are error records (kind "plugin", or the reporter's Kind), so
	/errors, /trace and $err work for them; a traceback given (or caught
	by try / wrap) is kept. The same warning or error repeated within a
	second (a failing hook on every frame, say) is written once, then
	"repeated N times". Info and success lines are always written.

	Every message also goes to the log file.
]]

local T = ...
local Types = T.import("base/types")
local signal = T.import("base/signal")

local Reporter = {}
Reporter.__index = Reporter
Reporter.RepeatWindow = 1 -- seconds in which an identical warning / error is folded

local reporters: { [string]: any } = {}

local function console()
	return T.Console
end

local function textOf(content): string
	if type(content) == "table" then
		local parts = {}
		for _, segment in content do
			table.insert(parts, tostring(segment.Text or ""))
		end
		return table.concat(parts)
	end
	return tostring(content)
end

--[[
	Reporter.get(id, opts) -> reporter (one per id; later opts update it)
	opts.Label   name shown in front (default: the id)
	opts.Plugin  true (default unless id is "explorer" or "core"): [plugin] lines
	opts.Kind    error record kind (default "plugin" for plugins, else the id)
]]
function Reporter.get(id: string, opts: { [string]: any }?)
	assert(type(id) == "string" and id ~= "", "a reporter needs an id")
	opts = opts or {}
	local self = reporters[id]
	if not self then
		self = setmetatable({
			Id = id,
			Label = id,
			Plugin = not (id == "explorer" or id == "core" or id == "tungsten"),
			Kind = nil,
			Muted = false,
			_last = nil,
			_lastAt = 0,
			_repeats = 0,
			_token = 0,
		}, Reporter)
		reporters[id] = self
	end
	if (opts :: any).Label then
		self.Label = tostring((opts :: any).Label)
	end
	if (opts :: any).Plugin ~= nil then
		self.Plugin = (opts :: any).Plugin == true
	end
	if (opts :: any).Kind then
		self.Kind = tostring((opts :: any).Kind)
	end
	return self
end

function Reporter.exists(id: string): boolean
	return reporters[id] ~= nil
end

-- Forgets a source's reporter (a plugin being turned off).
function Reporter.remove(id: string)
	reporters[id] = nil
end

function Reporter:_kind(): string
	return self.Kind or (if self.Plugin then "plugin" else self.Id)
end

-- Folds identical messages that arrive close together. true: skip it.
function Reporter:_fold(level: string, text: string): boolean
	local key = level .. "\0" .. text
	local now = os.clock()
	if self._last == key and now - self._lastAt < Reporter.RepeatWindow then
		self._repeats += 1
		self._lastAt = now
		return true
	end
	self:_flushRepeats()
	self._last = key
	self._lastAt = now
	return false
end

function Reporter:_flushRepeats()
	if self._repeats > 0 then
		local count = self._repeats
		self._repeats = 0
		self:_write("warn", ("the last message was repeated %d more time%s"):format(count, if count == 1 then "" else "s"), true)
	end
end

local LEVEL = {
	info = { Core = "info", Plugin = "plugin", Color = "Text" },
	success = { Core = "success", Plugin = "plugin", Color = "Success" },
	warn = { Core = "warn", Plugin = "warn", Color = "Text" },
}

function Reporter:_segments(content, color: string): { any }
	local segments = { { Text = self.Label .. ": ", Color = "TextDim" } }
	if type(content) == "table" then
		for _, segment in content do
			table.insert(segments, { Text = tostring(segment.Text or ""), Color = segment.Color or color })
		end
	else
		table.insert(segments, { Text = tostring(content), Color = color })
	end
	return segments
end

function Reporter:_write(level: string, content, skipFold: boolean?)
	if self.Muted then
		return nil
	end
	local Console = console()
	local text = textOf(content)
	T.Log.info("report", ("[%s] %s: %s"):format(self.Id, level, text))
	if not Console then
		return nil
	end
	if not skipFold and level == "warn" and self:_fold(level, text) then
		return nil
	end
	local style = LEVEL[level]
	local kind = if self.Plugin then style.Plugin else style.Core
	local line = Console.write(kind, self:_segments(content, style.Color))
	if line then
		line.Source = self.Id
	end
	self:_scheduleFlush()
	return line
end

-- Writes "repeated N times" a moment after the last repeat.
function Reporter:_scheduleFlush()
	self._token += 1
	local token = self._token
	task.delay(Reporter.RepeatWindow + 0.1, function()
		if self._token == token then
			self:_flushRepeats()
		end
	end)
end

function Reporter:info(content)
	return self:_write("info", content)
end

function Reporter:success(content)
	return self:_write("success", content)
end

function Reporter:warn(content)
	return self:_write("warn", content)
end

-- An indented line under the previous one (no name, never folded).
function Reporter:detail(content, opts)
	if self.Muted or not console() then
		return nil
	end
	return console().detail(content, opts)
end

-- "label value <type>", with the value's icon.
function Reporter:value(label: string?, value: any)
	if self.Muted or not console() then
		return nil
	end
	local Console = console()
	local segments, opts = Console.valueSegments(label, value)
	local all = self:_segments(segments, "Text")
	if opts.IconAt then
		opts.IconAt += #self.Label + 2
	end
	local line = Console.write(if self.Plugin then "plugin" else "info", all, opts)
	if line then
		line.Source = self.Id
	end
	return line
end

--[[
	reporter:error(message, details) -> the error record (or nil when muted
	or folded)
	message: text, or an error value (tables with .Message work too)
	details: Trace (traceback text), Hints { … }, Code, Input
]]
function Reporter:error(message, details: { [string]: any }?)
	details = details or {}
	local text = if type(message) == "table" and message.Message then tostring(message.Message) else tostring(message)
	T.Log.error("report", ("[%s] %s%s"):format(self.Id, text, if (details :: any).Trace then "\n" .. tostring((details :: any).Trace) else ""))
	local Console = console()
	if self.Muted or not Console then
		return nil
	end
	if self:_fold("error", text) then
		self:_scheduleFlush()
		return nil
	end
	local record = Console.Errors.record({
		Kind = self:_kind(),
		Message = text,
		Source = self.Id,
		Label = self.Label,
		Trace = (details :: any).Trace,
		Hints = (details :: any).Hints,
		Code = (details :: any).Code,
		Input = (details :: any).Input,
		NoExplain = true, -- the console's code hints don't fit a plugin's errors
	})
	Console.Errors.write(Console, record)
	self:_scheduleFlush()
	return record
end
Reporter.fail = Reporter.error

-- Runs fn(...) guarded: returns true + results, or false + the record.
function Reporter:try(fn: (...any) -> ...any, ...)
	local trace = nil
	local results = table.pack(xpcall(fn, function(message)
		trace = debug.traceback(tostring(message), 2)
		return message
	end, ...))
	if results[1] then
		return table.unpack(results, 1, results.n)
	end
	local message = results[2]
	if type(message) == "table" and message.Message then
		message = message.Message
	end
	local record = self:error(tostring(message), { Trace = trace })
	return false, record
end

-- fn guarded the same way; `what` names it in the message. The wrapped
-- function returns fn's results, or nothing when fn failed (reported).
function Reporter:wrap(fn: (...any) -> ...any, what: string?)
	return function(...)
		local results = table.pack(self:try(function(...)
			local inner = table.pack(xpcall(fn, function(message)
				if what then
					local text = if type(message) == "table" and message.Message then message.Message else message
					return ("%s failed: %s"):format(what, tostring(text))
				end
				return message
			end, ...))
			if not inner[1] then
				error(inner[2], 0)
			end
			return table.unpack(inner, 2, inner.n)
		end, ...))
		if results[1] then
			return table.unpack(results, 2, results.n)
		end
		return nil
	end
end

-- Reports a fault from framework code run on behalf of an owner (menu
-- entries, UI hooks, picker kinds, row kinds). Plugin owners get a
-- console line; Tungsten's own faults go to the log only (they also have
-- the in-console [x] path for commands).
-- Reporter.Faulted (owner, what, message) fires for every plugin fault, so
-- the plugin host can count them.
Reporter.Faulted = signal.new()

function Reporter.ownerFault(owner: string?, what: string, err: any)
	local text = if type(err) == "table" and err.Message then tostring(err.Message) else tostring(err)
	local message, trace = text:match("^(.-)\n(.*)$")
	message = message or text
	if owner == nil or owner == "core" then
		T.Log.error("report", ("%s failed: %s"):format(what, text))
		return nil
	end
	local record = Reporter.get(owner):error(("%s failed: %s"):format(what, message), { Trace = trace })
	Reporter.Faulted:Fire(owner, what, message)
	return record
end

T.Bin:Add(function()
	table.clear(reporters)
end)

return Reporter
