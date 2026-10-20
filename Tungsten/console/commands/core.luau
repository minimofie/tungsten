--[[
	Tungsten · console/commands/core
	General console commands: help, clear, echo, scale, settings, logs,
	game, history, copy, type, exit.

	Each command file returns a list of command definitions (see
	console/commands.luau). Explorer commands are in
	console/commands/explorer.luau.
]]

local T = ...
local Settings = T.import("base/settings")
local Scale = T.import("base/scale")
local Types = T.import("base/types")
local Commands = T.import("console/commands")

local function pad(text: string, width: number): string
	if #text >= width then
		return text .. "  "
	end
	return text .. string.rep(" ", width - #text)
end

local function settingText(value: any): string
	if type(value) == "table" then
		local parts = {}
		for _, item in value do
			table.insert(parts, tostring(item))
		end
		return "{" .. table.concat(parts, ", ") .. "}"
	end
	return Types.short(value)
end

local function onOff(word: string?): boolean?
	word = word and word:lower()
	if word == "on" or word == "true" or word == "yes" or word == "1" then
		return true
	elseif word == "off" or word == "false" or word == "no" or word == "0" then
		return false
	end
	return nil
end

return {
	{
		Name = "help",
		Aliases = { "?", "commands" },
		Group = "Console",
		Usage = "/help [command]",
		Description = "list commands, or explain one",
		Run = function(ctx)
			local Console = ctx.Console
			local wanted = ctx.Args[1]
			if wanted and (wanted:lower() == "prefixes" or wanted:lower() == "prefix") then
				Console.write("hint", "input prefixes · what you type first")
				for _, entry in Console.InputPrefixes do
					Console.detail({
						{ Text = pad(entry.Prefix, 4), Color = "Accent" },
						{ Text = pad(entry.Example, 24), Color = "Text" },
						{ Text = entry.Meaning, Color = "TextDim" },
					})
				end
				Console.write("hint", "output prefixes · what the console prints")
				for _, kind in Console.OutputOrder do
					local style = Console.Kinds[kind]
					Console.detail({
						{ Text = pad(style.Tag, 10), Color = style.TagColor },
						{ Text = Console.OutputMeaning[kind], Color = "TextDim" },
					})
				end
				return
			end
			if wanted then
				wanted = wanted:gsub("^[/:?]", "")
				local owner, name = wanted:match("^([%a_][%w_%-]*)%.([%a_][%w_%-]*)$")
				local command = if owner then Commands.get(owner, name) else Commands.resolve(wanted)
				if not command then
					ctx.fail(("no command \"%s\" · /help lists them all"):format(wanted))
				end
				Console.write("hint", {
					{ Text = Commands.invocation(command), Color = "Accent" },
					{ Text = "  " .. command.Description, Color = "Text" },
				})
				Console.detail({ { Text = "usage  ", Color = "TextMuted" }, { Text = command.Usage, Color = "Text" } })
				if #command.Aliases > 0 then
					local names = {}
					for _, alias in command.Aliases do
						table.insert(names, "/" .. alias)
					end
					Console.detail({ { Text = "also   ", Color = "TextMuted" }, { Text = table.concat(names, "  "), Color = "TextDim" } })
				end
				return
			end

			local list = {}
			local width = 0
			for _, command in Commands.list() do
				if not command.Hidden then
					table.insert(list, command)
					width = math.max(width, #command.Usage)
				end
			end
			width = math.min(width + 2, 34)
			Console.write("hint", ("%d commands · /help <command> for details · /help prefixes · /docs for the manual"):format(#list))
			-- Groups in a fixed order; plugins after.
			local order = { Console = 1, Variables = 2, Errors = 3, Tools = 4, Explorer = 5, Game = 6, Window = 7 }
			table.sort(list, function(a, b)
				local ga = if a.Owner == "core" then (order[a.Group] or 50) else 100
				local gb = if b.Owner == "core" then (order[b.Group] or 50) else 100
				if ga ~= gb then
					return ga < gb
				end
				if a.Owner ~= b.Owner then
					return a.Owner < b.Owner
				end
				return a.Name < b.Name
			end)
			local group = nil
			for _, command in list do
				local heading = if command.Owner == "core" then command.Group else command.Owner
				if heading ~= group then
					group = heading
					Console.detail({ { Text = heading:upper(), Color = "TextMuted" } })
				end
				Console.detail({
					{ Text = "  " .. pad(command.Usage, width), Color = "Accent" },
					{ Text = command.Description, Color = "TextDim" },
				})
			end
			Console.detail({
				{ Text = "Prefixes: ", Color = "TextMuted" },
				{ Text = "/ : > = $ ? ! # && ||", Color = "Accent" },
				{ Text = " · /help prefixes explains them", Color = "TextDim" },
			})
		end,
		Complete = function(_, argIndex)
			if argIndex ~= 1 then
				return {}
			end
			local names = { "prefixes" }
			for _, command in Commands.list() do
				if not command.Hidden then
					table.insert(names, if command.Owner == "core" then command.Name else command.Owner .. "." .. command.Name)
				end
			end
			return names
		end,
	},
	{
		Name = "clear",
		Aliases = { "cls" },
		Group = "Console",
		Usage = "/clear",
		Description = "clear the console",
		Run = function(ctx)
			ctx.Console.clear()
		end,
	},
	{
		Name = "echo",
		Group = "Console",
		Usage = "/echo <text>",
		Description = "print text ($name is replaced)",
		Run = function(ctx)
			local raw = ctx.Raw
			-- /echo "text" prints the text without the quotes.
			local quoted = raw:match('^"(.*)"$') or raw:match("^'(.*)'$")
			local text = ctx.interpolate(quoted or raw)
			ctx.Console.info(text)
			return text
		end,
	},
	{
		Name = "history",
		Group = "Console",
		Usage = "/history [clear]",
		Description = "show or clear the input history",
		Run = function(ctx)
			local history = ctx.Console.History
			if (ctx.Args[1] or ""):lower() == "clear" then
				table.clear(history)
				ctx.success("history cleared")
				return
			end
			-- The /history entry itself is the newest one; skip it.
			local count = #history - 1
			if count <= 0 then
				ctx.info("no history yet")
				return
			end
			local from = math.max(1, count - 29)
			ctx.info(("last %d of %d entries · Up/Down in the input goes through them"):format(count - from + 1, count))
			for index = from, count do
				ctx.detail({ { Text = pad(tostring(index), 5), Color = "TextMuted" }, { Text = history[index], Color = "Text" } })
			end
		end,
		Complete = function(_, argIndex)
			return if argIndex == 1 then { "clear" } else {}
		end,
	},
	{
		Name = "game",
		Group = "Console",
		Usage = "/game [on | off]",
		Description = "show the game's print and warn as [game] lines",
		Run = function(ctx)
			local Console = ctx.Console
			local wanted = onOff(ctx.Args[1])
			if ctx.Args[1] and wanted == nil then
				ctx.usage()
			end
			if wanted == nil then
				wanted = not Console.gameOutput()
			end
			Console.setGameOutput(wanted)
			ctx.success(("game output %s"):format(if wanted then "on · print and warn from the game appear as [game]" else "off"))
		end,
		Complete = function(_, argIndex)
			return if argIndex == 1 then { "on", "off" } else {}
		end,
	},
	{
		Name = "copy",
		Group = "Console",
		Usage = "/copy <value | $name | > code>",
		Description = "copy text or a value to the clipboard",
		Run = function(ctx)
			local raw = ctx.Raw
			if raw == "" then
				ctx.usage()
			end
			local value
			if raw:sub(1, 1) == ">" then
				value = ctx.eval(raw:sub(2))
			elseif raw:match("^%$[%a_][%w_]*$") then
				value = ctx.resolve(raw)
			else
				value = ctx.interpolate(raw)
			end
			local text = if type(value) == "string"
				then value
				elseif typeof(value) == "Instance" then Types.path(value)
				else Types.short(value, 100000)
			local ok, err = pcall(setclipboard, text)
			if not ok then
				ctx.fail("could not copy: " .. tostring(err))
			end
			ctx.success(("copied %d characters"):format(#text))
		end,
	},
	{
		Name = "type",
		Aliases = { "typeof" },
		Group = "Variables",
		Usage = "/type <$name | > code>",
		Description = "describe a value's type and class",
		Run = function(ctx)
			local raw = ctx.Raw
			if raw == "" then
				ctx.usage()
			end
			local value = if raw:sub(1, 1) == ">" then ctx.eval(raw:sub(2)) else ctx.eval(raw)
			ctx.value("success", nil, value)
			local info = Types.describe(value)
			ctx.detail({ { Text = "type   ", Color = "TextMuted" }, { Text = info.Type, Color = "Text" } })
			if info.Class then
				ctx.detail({ { Text = "class  ", Color = "TextMuted" }, { Text = info.Class, Color = "Text" } })
				ctx.detail({ { Text = "base   ", Color = "TextMuted" }, { Text = info.Base or "-", Color = "Text" } })
				ctx.detail({ { Text = "path   ", Color = "TextMuted" }, { Text = Types.path(value), Color = "TextDim" } })
			elseif type(value) == "table" then
				local count = 0
				for _ in value do
					count += 1
				end
				ctx.detail({ { Text = "size   ", Color = "TextMuted" }, { Text = ("%d entries (%d in the array part)"):format(count, #value), Color = "Text" } })
			elseif type(value) == "string" then
				ctx.detail({ { Text = "length ", Color = "TextMuted" }, { Text = tostring(#value), Color = "Text" } })
			elseif info.Function then
				local fn = info.Function
				ctx.detail({ { Text = "shape  ", Color = "TextMuted" }, { Text = fn.Signature, Color = "Text" } })
				ctx.detail({ { Text = "kind   ", Color = "TextMuted" }, { Text = if fn.Kind == "C" then "built in (C)" else "Luau", Color = "Text" } })
				if fn.Line then
					ctx.detail({ { Text = "from   ", Color = "TextMuted" }, { Text = ("%s line %d"):format(tostring(fn.Source), fn.Line), Color = "TextDim" } })
				end
			end
			if typeof(value) ~= "Instance" and value ~= nil then
				ctx.detail({ { Text = "edit   ", Color = "TextMuted" }, { Text = Types.editText(value), Color = "TextDim" } })
			end
			return value
		end,
	},
	{
		Name = "scale",
		Aliases = { "zoom" },
		Group = "Window",
		Usage = "/scale [value | + | - | reset]",
		Description = "show or change the window size (like resizing it; contents keep their size)",
		Run = function(ctx)
			local arg = ctx.Args[1]
			local before = Scale.effective()
			if arg == nil then
				ctx.info(("scale %.2f · range %.2f to %.2f · this screen fits up to %.2f"):format(before, Scale.Min, Scale.Max, Scale.limit()))
				return before
			end
			local after
			if arg == "+" then
				after = Scale.step(Scale.KeyStep)
			elseif arg == "-" then
				after = Scale.step(-Scale.KeyStep)
			elseif arg:lower() == "reset" then
				after = Scale.set(1)
			else
				local number = tonumber(ctx.resolve(arg))
				if not number or number ~= number then
					ctx.usage()
				end
				after = Scale.set(number :: number)
				if math.abs(after - number) > 0.001 then
					local reason = if number > Scale.limit() and Scale.limit() < Scale.Max
						then "the most this screen fits"
						elseif number > Scale.Max then "the maximum"
						elseif number < Scale.Min then "the minimum"
						else "the nearest step"
					ctx.warn(("scale %.2f · %.2f was adjusted to %s"):format(after, number, reason))
					return after
				end
			end
			ctx.success(("scale %.2f"):format(after))
			return after
		end,
		Complete = function(_, argIndex)
			return if argIndex == 1 then { "+", "-", "reset", "1", "1.25", "1.5" } else {}
		end,
	},
	{
		Name = "settings",
		Group = "Window",
		Usage = "/settings [name [value | reset]]",
		Description = "show or change Tungsten settings",
		Run = function(ctx)
			local key, valueWord = ctx.Args[1], ctx.Args[2]
			local defaults = Settings.defaults()
			if key == nil then
				local keys = {}
				local width = 0
				for name in defaults do
					table.insert(keys, name)
					width = math.max(width, #name)
				end
				table.sort(keys)
				ctx.info(("settings · saved in %s"):format(Settings.Path))
				for _, name in keys do
					ctx.detail({
						{ Text = pad(name, width + 2), Color = "Text" },
						{ Text = settingText(Settings.get(name)), Color = "Accent" },
						{ Text = "  default " .. settingText(defaults[name]), Color = "TextMuted" },
					})
				end
				return
			end
			-- Case-insensitive key match.
			local match = nil
			for name in defaults do
				if name:lower() == key:lower() then
					match = name
				end
			end
			if not match then
				ctx.fail(("no setting \"%s\" · /settings lists them"):format(key))
			end
			if valueWord == nil then
				ctx.info(("%s = %s"):format(match, settingText(Settings.get(match))))
				return Settings.get(match)
			end
			local value
			if valueWord:lower() == "reset" then
				value = defaults[match]
			else
				local rest = ctx.Raw:match("^%S+%s+(.+)$") or valueWord
				local default = defaults[match]
				if type(default) == "boolean" then
					value = onOff(rest)
				elseif type(default) == "number" then
					value = tonumber(rest)
				elseif type(default) == "string" then
					value = rest
				else
					value = ctx.eval(rest)
				end
			end
			if match == "Scale" and type(value) == "number" then
				local applied = Scale.set(value)
				ctx.success(("Scale = %.2f"):format(applied))
				return applied
			end
			if not Settings.set(match, value) then
				ctx.fail(("%s can't be %s"):format(match, settingText(value)))
			end
			ctx.success(("%s = %s"):format(match, settingText(Settings.get(match))))
			return Settings.get(match)
		end,
		Complete = function(_, argIndex)
			if argIndex ~= 1 then
				return {}
			end
			local keys = {}
			for name in Settings.defaults() do
				table.insert(keys, name)
			end
			return keys
		end,
	},
	{
		Name = "logs",
		Group = "Window",
		Usage = "/logs [list | <count>]",
		Description = "show the newest log entries or the log files",
		Run = function(ctx)
			local Log = T.Log
			Log.flush()
			local arg = ctx.Args[1]
			if arg and arg:lower() == "list" then
				local ok, files = pcall(listfiles, T.Root .. "/logs")
				if not ok or type(files) ~= "table" then
					ctx.fail("could not list the logs folder")
				end
				local names = {}
				for _, file in files do
					local name = tostring(file):match("[^/\\]+$")
					if name and name:match("%.log$") then
						table.insert(names, name)
					end
				end
				table.sort(names, function(a, b)
					return a > b
				end)
				ctx.info(("%d log files in %s/logs (newest first)"):format(#names, T.Root))
				for _, name in names do
					local current = Log.File and Log.File:match("[^/\\]+$") == name
					ctx.detail({ { Text = name, Color = if current then "Accent" else "Text" }, { Text = if current then "  this session" else "", Color = "TextMuted" } })
				end
				return
			end
			local count = math.clamp(tonumber(arg) or 15, 1, 200)
			if not Log.File then
				ctx.fail("no log file this session")
			end
			local ok, content = pcall(readfile, Log.File)
			if not ok then
				ctx.fail("could not read " .. tostring(Log.File))
			end
			local lines = {}
			for line in (content .. "\n"):gmatch("(.-)\n") do
				if line:match("^%[") then
					table.insert(lines, line)
				end
			end
			ctx.info(("%s · last %d entries"):format(Log.File, math.min(count, #lines)))
			for index = math.max(1, #lines - count + 1), #lines do
				local line = lines[index]
				local color = if line:find("%[ERROR%]") then "Danger" elseif line:find("%[WARN %]") then "Warning" else "TextDim"
				ctx.detail({ { Text = line, Color = color } })
			end
		end,
		Complete = function(_, argIndex)
			return if argIndex == 1 then { "list", "50" } else {}
		end,
	},
	{
		Name = "exit",
		Aliases = { "quit" },
		Group = "Window",
		Usage = "/exit",
		Description = "close Tungsten (run Tungsten.luau to start it again)",
		Run = function(ctx)
			ctx.info("closing Tungsten")
			task.delay(0.15, function()
				if T.Shutdown then
					T.Shutdown("closed from the console")
				end
			end)
		end,
	},
}
