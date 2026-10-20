--[[
	Tungsten · console/commands/errors
	errors, trace, retry, try. See console/errors for the records.
]]

local T = ...
local Settings = T.import("base/settings")
local Errors = T.import("console/errors")

local KIND_COLORS = {
	syntax = "Warning",
	runtime = "Danger",
	command = "Danger",
	unknown = "TextDim",
	internal = "Danger",
	game = "TextMuted",
	plugin = "Accent",
	explorer = "Info",
}

local function pad(text: string, width: number): string
	return if #text >= width then text .. " " else text .. string.rep(" ", width - #text)
end

-- "#3", "3" or nothing (the newest).
local function pick(ctx, word: string?)
	if word == nil or word == "" then
		local record = Errors.get()
		if not record then
			ctx.fail("no errors yet")
		end
		return record
	end
	local id = tonumber((word:gsub("^#", "")))
	if not id then
		ctx.usage()
	end
	local record = Errors.get(id)
	if not record then
		ctx.fail(("no error #%d · /errors lists them"):format(id))
	end
	return record
end

local function show(ctx, record)
	local Console = ctx.Console
	Console.write("hint", {
		{ Text = ("error #%d"):format(record.Id), Color = "Accent" },
		{ Text = (" · %s · %s"):format(record.Kind, record.Time), Color = "TextDim" },
	})
	ctx.detail({ { Text = "message  ", Color = "TextMuted" }, { Text = record.Message, Color = "Text" } })
	if record.Label then
		ctx.detail({ { Text = "from     ", Color = "TextMuted" }, { Text = record.Label, Color = "Text" } })
	end
	if record.Input then
		ctx.detail({ { Text = "input    ", Color = "TextMuted" }, { Text = record.Input, Color = "TextDim" } })
	end
	if record.Command then
		ctx.detail({ { Text = "command  ", Color = "TextMuted" }, { Text = record.Command, Color = "TextDim" } })
	end
	if record.Code and record.Code ~= record.Input then
		ctx.detail({ { Text = "code     ", Color = "TextMuted" }, { Text = record.Code, Color = "TextDim" } })
	end
	if record.Caret then
		ctx.detail({ { Text = "         " .. record.Caret[1], Color = "TextDim" } })
		ctx.detail({ { Text = "         " .. record.Caret[2], Color = "Danger" } })
	end
	for _, hint in record.Hints do
		ctx.detail({ { Text = "hint     ", Color = "TextMuted" }, { Text = hint, Color = "Text" } })
	end
	if #record.Trace > 0 then
		ctx.detail({ { Text = "trace", Color = "TextMuted" } })
		for _, frame in record.Trace do
			ctx.detail({ { Text = "    " .. frame, Color = if frame:find("console:", 1, true) then "Text" else "TextMuted" } })
		end
	elseif record.Kind == "runtime" or record.Kind == "internal" then
		ctx.detail({ { Text = "trace    ", Color = "TextMuted" }, { Text = "only Tungsten's own frames (hidden)", Color = "TextMuted" } })
	end
	if record.Input then
		ctx.detail({ { Text = ("/retry %d runs it again · $err holds the newest error"):format(record.Id), Color = "TextMuted" } })
	end
end

return {
	{
		Name = "errors",
		Group = "Errors",
		Usage = "/errors [count | kind | clear]",
		Description = "list recent errors (kinds: syntax runtime command unknown internal game plugin explorer)",
		Run = function(ctx)
			local arg = ctx.Args[1] and ctx.Args[1]:lower()
			if arg == "clear" then
				Errors.clear()
				ctx.success("errors cleared")
				return
			end
			local list = Errors.list()
			local limit = tonumber(arg) or 20
			local kind = if arg and not tonumber(arg) then arg else nil
			local shown = {}
			for index = #list, 1, -1 do
				local record = list[index]
				if kind == nil or record.Kind == kind then
					table.insert(shown, 1, record)
					if #shown >= limit then
						break
					end
				end
			end
			if #shown == 0 then
				ctx.info(if kind then ("no %s errors"):format(kind) else "no errors this session")
				return
			end
			ctx.Console.write("hint", ("%d of %d errors · /trace <number> for details"):format(#shown, #list))
			for _, record in shown do
				local line = ctx.detail({
					{ Text = pad("#" .. record.Id, 5), Color = "Accent" },
					{ Text = record.Time .. "  ", Color = "TextMuted" },
					{ Text = pad(record.Kind, 9), Color = KIND_COLORS[record.Kind] or "TextDim" },
					{ Text = (if record.Label then record.Label .. ": " else "") .. record.Message, Color = "Text" },
					{ Text = if record.Input then "  · " .. record.Input else "", Color = "TextMuted" },
				})
				if line then
					line.Error = record
				end
			end
			return #shown
		end,
		Complete = function(_, argIndex)
			return if argIndex == 1 then { "clear", "syntax", "runtime", "command", "unknown", "internal", "game" } else {}
		end,
	},
	{
		Name = "trace",
		Aliases = { "why", "error" },
		Group = "Errors",
		Usage = "/trace [number]",
		Description = "everything about an error: input, code, where, hints, traceback",
		Run = function(ctx)
			local record = pick(ctx, ctx.Args[1])
			show(ctx, record)
			return record
		end,
	},
	{
		Name = "retry",
		Group = "Errors",
		Usage = "/retry [number]",
		Description = "run the input of an error again (the newest by default)",
		Run = function(ctx)
			local record = pick(ctx, ctx.Args[1])
			if not record.Input then
				ctx.fail(("error #%d has no input to run again"):format(record.Id))
			end
			if record.Input:match("^/retry") then
				ctx.fail("that input was itself a /retry")
			end
			ctx.Console.echo(record.Input)
			if not ctx.Console.guarded(record.Input) then
				ctx.stop() -- the input reported its own error
			end
		end,
	},
	{
		Name = "try",
		Group = "Errors",
		Usage = "/try <input>",
		Description = "run an input; on failure only a warning, so a && chain goes on",
		Run = function(ctx)
			if ctx.Raw == "" then
				ctx.usage()
			end
			local ok = ctx.Console.guarded(ctx.Raw)
			if not ok then
				ctx.warn("failed · carrying on (/trace shows the error)")
			end
			return ok
		end,
	},
	{
		Name = "traceback",
		Group = "Errors",
		Usage = "/traceback [on | off]",
		Description = "print the traceback under code errors",
		Run = function(ctx)
			local word = ctx.Args[1] and ctx.Args[1]:lower()
			local value
			if word == "on" then
				value = true
			elseif word == "off" then
				value = false
			elseif word == nil then
				value = not Settings.get("ConsoleTraceback")
			else
				ctx.usage()
			end
			Settings.set("ConsoleTraceback", value)
			ctx.success(("tracebacks %s"):format(if value then "on · shown under code errors" else "off · /trace still shows them"))
		end,
		Complete = function(_, argIndex)
			return if argIndex == 1 then { "on", "off" } else {}
		end,
	},
}
