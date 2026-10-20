--[[
	Tungsten · console/commands/tools
	Working with the console and the window: about, time, bench, repeat,
	wait, alias, unalias, run, files, log, savelog, tab, minimize,
	accent, docs.
]]

local T = ...
local Settings = T.import("base/settings")
local Types = T.import("base/types")
local Registry = T.import("base/registry")
local Commands = T.import("console/commands")

local started = os.clock()

local function duration(seconds: number): string
	if seconds < 0.001 then
		return ("%.1f µs"):format(seconds * 1e6)
	elseif seconds < 1 then
		return ("%.2f ms"):format(seconds * 1000)
	elseif seconds < 120 then
		return ("%.2f s"):format(seconds)
	end
	local minutes = math.floor(seconds / 60)
	if minutes < 120 then
		return ("%d min %d s"):format(minutes, math.floor(seconds % 60))
	end
	return ("%d h %d min"):format(math.floor(minutes / 60), minutes % 60)
end

local function stamp(): string
	local t = DateTime.now():ToLocalTime()
	return ("%04d-%02d-%02d_%02d-%02d-%02d"):format(t.Year, t.Month, t.Day, t.Hour, t.Minute, t.Second)
end

-- Rejects paths that leave the workspace or use odd characters.
local function cleanPath(path: string?): string?
	if not path or path == "" then
		return nil
	end
	path = path:gsub("\\", "/"):gsub("^/+", "")
	if path:find("%.%.") or path:find("[:*?\"<>|]") then
		return nil
	end
	return path
end

return {
	{
		Name = "about",
		Aliases = { "version" },
		Group = "Console",
		Usage = "/about",
		Description = "version, executor, place and uptime",
		Run = function(ctx)
			local Console = ctx.Console
			local name, version = Console.executor()
			ctx.info({ { Text = "tungsten (unified) ", Color = "Text" }, { Text = "v" .. T.Version, Color = "Accent" } })
			ctx.detail({ { Text = "executor  ", Color = "TextMuted" }, { Text = name .. " " .. version, Color = "Text" } })
			ctx.detail({ { Text = "place     ", Color = "TextMuted" }, { Text = tostring(game.PlaceId), Color = "Text" } })
			ctx.detail({ { Text = "plugins   ", Color = "TextMuted" }, { Text = tostring(Console.pluginCount()), Color = "Text" } })
			ctx.detail({ { Text = "commands  ", Color = "TextMuted" }, { Text = tostring(#Commands.list()), Color = "Text" } })
			ctx.detail({ { Text = "running   ", Color = "TextMuted" }, { Text = duration(os.clock() - started), Color = "Text" } })
			ctx.detail({ { Text = "log       ", Color = "TextMuted" }, { Text = tostring(T.Log.File), Color = "TextDim" } })
			if T.LoadTime then
				ctx.detail({ { Text = "load      ", Color = "TextMuted" }, { Text = ("%d ms"):format(math.floor(T.LoadTime * 1000 + 0.5)), Color = "Text" } })
			end
		end,
	},
	{
		Name = "time",
		Aliases = { "date" },
		Group = "Console",
		Usage = "/time",
		Description = "local time, date and how long Tungsten has run",
		Run = function(ctx)
			local now = DateTime.now()
			local t = now:ToLocalTime()
			ctx.Console.write("time", {
				{ Text = ("%02d:%02d:%02d"):format(t.Hour, t.Minute, t.Second), Color = "Text" },
				{ Text = ("  %04d-%02d-%02d"):format(t.Year, t.Month, t.Day), Color = "TextDim" },
				{ Text = "  · running " .. duration(os.clock() - started), Color = "TextMuted" },
			})
			return os.clock() - started
		end,
	},
	{
		Name = "bench",
		Group = "Tools",
		Usage = "/bench [runs] <code>",
		Description = "time Luau code (default 1000 runs)",
		Run = function(ctx)
			local runs, code = ctx.Raw:match("^(%d+)%s+(.+)$")
			runs = tonumber(runs) or 1000
			code = code or ctx.Raw
			code = code:gsub("^>%s*", "")
			if code == "" then
				ctx.usage()
			end
			runs = math.clamp(runs :: number, 1, 1000000)
			local chunk, err = ctx.Console.compile(code)
			if not chunk then
				ctx.fail(err)
			end
			local okFirst, firstError = pcall(chunk)
			if not okFirst then
				ctx.fail(tostring(firstError))
			end
			local begin = os.clock()
			for index = 1, runs do
				chunk()
				if index % 20000 == 0 then
					task.wait() -- keep the game responsive on long runs
				end
			end
			local total = os.clock() - begin
			ctx.Console.write("time", {
				{ Text = ("%d runs · %s total · "):format(runs, duration(total)), Color = "Text" },
				{ Text = duration(total / runs) .. " each", Color = "Accent" },
			})
			return total / runs
		end,
	},
	{
		Name = "repeat",
		Group = "Tools",
		Usage = "/repeat <count> <input>",
		Description = "run an input several times (up to 1000)",
		Run = function(ctx)
			local count, input = ctx.Raw:match("^(%d+)%s+(.+)$")
			count = tonumber(count)
			if not count or not input then
				ctx.usage()
			end
			count = math.clamp(count :: number, 1, 1000)
			for index = 1, count do
				if not ctx.Console.execute(input, 1) then
					ctx.fail(("stopped at run %d of %d"):format(index, count))
				end
				if index % 50 == 0 then
					task.wait()
				end
			end
		end,
	},
	{
		Name = "wait",
		Aliases = { "sleep" },
		Group = "Tools",
		Usage = "/wait <seconds>",
		Description = "pause (useful between && parts)",
		Run = function(ctx)
			local seconds = tonumber(ctx.resolve(ctx.Args[1]))
			if not seconds then
				ctx.usage()
			end
			seconds = math.clamp(seconds :: number, 0, 300)
			task.wait(seconds)
			return seconds
		end,
	},
	{
		Name = "alias",
		Group = "Tools",
		Usage = "/alias [name = input]",
		Description = "make a short name for an input (this session)",
		Run = function(ctx)
			local Console = ctx.Console
			if ctx.Raw == "" then
				local names = {}
				for name in Console.Aliases do
					table.insert(names, name)
				end
				table.sort(names)
				if #names == 0 then
					ctx.info("no aliases · /alias hi = /echo hello")
					return
				end
				for _, name in names do
					ctx.detail({ { Text = "/" .. name, Color = "Accent" }, { Text = "  →  " .. Console.Aliases[name], Color = "TextDim" } })
				end
				return
			end
			local name, input = ctx.Raw:match("^/?([%a_][%w_%-]*)%s*=%s*(.+)$")
			if not name then
				ctx.usage()
			end
			if Commands.get("core", name) then
				ctx.fail(("/%s is a command · pick another name"):format(name))
			end
			Console.setAlias(name, input)
			ctx.success(("/%s now runs %s"):format(name:lower(), input))
		end,
	},
	{
		Name = "unalias",
		Group = "Tools",
		Usage = "/unalias <name | *>",
		Description = "remove an alias",
		Run = function(ctx)
			local Console = ctx.Console
			local name = (ctx.Args[1] or ""):gsub("^/", ""):lower()
			if name == "" then
				ctx.usage()
			end
			if name == "*" then
				table.clear(Console.Aliases)
				ctx.success("all aliases removed")
				return
			end
			if not Console.Aliases[name] then
				ctx.fail(("no alias /%s"):format(name))
			end
			Console.setAlias(name, nil)
			ctx.success(("alias /%s removed"):format(name))
		end,
		Complete = function(ctx, argIndex)
			local names = {}
			if argIndex == 1 then
				for name in ctx.Console.Aliases do
					table.insert(names, name)
				end
			end
			return names
		end,
	},
	{
		Name = "run",
		Group = "Tools",
		Usage = "/run <file>",
		Description = "run a Luau file from Volt's workspace folder",
		Run = function(ctx)
			local path = cleanPath(ctx.Raw)
			if not path then
				ctx.usage()
			end
			if not isfile(path :: string) then
				ctx.fail(("no file %s in the workspace folder"):format(path))
			end
			local chunk, err = loadfile(path :: string)
			if not chunk then
				ctx.fail(tostring(err))
			end
			if setfenv then
				pcall(setfenv, chunk, ctx.Console.makeEnv())
			end
			local results = table.pack(pcall(chunk))
			if not results[1] then
				ctx.fail(tostring(results[2]))
			end
			ctx.success(("ran %s"):format(path))
			if results.n > 1 then
				ctx.value("success", "returned ", results[2])
			end
			return results[2]
		end,
	},
	{
		Name = "files",
		Aliases = { "ls" },
		Group = "Tools",
		Usage = "/files [folder]",
		Description = "list files in Volt's workspace folder",
		Run = function(ctx)
			local folder = cleanPath(ctx.Raw) or ""
			local ok, entries = pcall(listfiles, folder)
			if not ok or type(entries) ~= "table" then
				ctx.fail(("can't list \"%s\""):format(folder))
			end
			local items = {}
			for _, entry in entries do
				local path = tostring(entry):gsub("\\", "/")
				local name = path:match("[^/]+$") or path
				local isFolder = false
				pcall(function()
					isFolder = isfolder(path)
				end)
				table.insert(items, { Name = name, Folder = isFolder })
			end
			table.sort(items, function(a, b)
				if a.Folder ~= b.Folder then
					return a.Folder
				end
				return a.Name:lower() < b.Name:lower()
			end)
			ctx.info(("%s · %d entries"):format(if folder == "" then "workspace" else folder, #items))
			for _, item in items do
				ctx.detail({ { Text = item.Name .. (if item.Folder then "/" else ""), Color = if item.Folder then "Accent" else "Text" } })
			end
		end,
	},
	{
		Name = "log",
		Group = "Tools",
		Usage = "/log <text>",
		Description = "write a line into this session's log file",
		Run = function(ctx)
			if ctx.Raw == "" then
				ctx.usage()
			end
			local text = ctx.interpolate(ctx.Raw)
			T.Log.info("user", text)
			T.Log.flush()
			ctx.success("written to " .. tostring(T.Log.File))
		end,
	},
	{
		Name = "savelog",
		Aliases = { "dump" },
		Group = "Tools",
		Usage = "/savelog [file]",
		Description = "save the console's text to a file",
		Run = function(ctx)
			local path = cleanPath(ctx.Raw) or (T.Root .. "/logs/console_" .. stamp() .. ".txt")
			local lines = {}
			for _, line in ctx.Console.Lines do
				table.insert(lines, (line.Time or "") .. " " .. line.Plain)
			end
			local ok, err = pcall(writefile, path, table.concat(lines, "\n") .. "\n")
			if not ok then
				ctx.fail("could not write: " .. tostring(err))
			end
			ctx.success(("saved %d lines to %s"):format(#lines, path))
			return path
		end,
	},
	{
		Name = "tab",
		Group = "Window",
		Usage = "/tab <name>",
		Description = "open a Tungsten tab",
		Run = function(ctx)
			local wanted = (ctx.Raw or ""):lower()
			if wanted == "" then
				local names = {}
				for _, tab in Registry.listTabs() do
					table.insert(names, tab.Id)
				end
				ctx.info("tabs: " .. table.concat(names, ", "))
				return
			end
			for _, tab in Registry.listTabs() do
				if tab.Id:lower() == wanted or tab.Title:lower() == wanted then
					T.Tabs:Select(tab.Id)
					return
				end
			end
			for _, tab in Registry.listTabs() do
				if tab.Id:lower():sub(1, #wanted) == wanted or tab.Title:lower():sub(1, #wanted) == wanted then
					T.Tabs:Select(tab.Id)
					return
				end
			end
			ctx.fail(("no tab \"%s\""):format(wanted))
		end,
		Complete = function(_, argIndex)
			local names = {}
			if argIndex == 1 then
				for _, tab in Registry.listTabs() do
					table.insert(names, tab.Id)
				end
			end
			return names
		end,
	},
	{
		Name = "docs",
		Aliases = { "doc", "manual" },
		Group = "Window",
		Usage = "/docs [topic]",
		Description = "open the documentation (optionally at a topic)",
		Run = function(ctx)
			T.Tabs:Select("documentation")
			local topic = ctx.Raw
			if topic ~= "" then
				local Docs = T.import("documentation/docs")
				if not Docs.open(topic) then
					ctx.warn(("no topic \"%s\" · the topic list shows them all"):format(topic))
				end
			end
		end,
		Complete = function(_, argIndex)
			local names = {}
			if argIndex == 1 then
				local ok, Docs = pcall(T.import, "documentation/docs")
				if ok then
					for _, topic in Docs.topics() do
						table.insert(names, topic.Id)
					end
				end
			end
			return names
		end,
	},
	{
		Name = "undo",
		Group = "Tools",
		Usage = "/undo [count | list | clear]",
		Description = "take back the last change (property and attribute edits, renames, moves, inserts, variables)",
		Run = function(ctx)
			local Undo = T.import("base/undo")
			local arg = (ctx.Args[1] or ""):lower()
			if arg == "list" then
				local entries = Undo.list()
				if #entries == 0 then
					ctx.info("nothing to undo")
					return {}
				end
				ctx.info(("%d step%s to undo (newest first)"):format(#entries, if #entries == 1 then "" else "s"))
				local texts = {}
				for index, entry in entries do
					if index > 30 then
						ctx.detail({ { Text = ("  … %d more"):format(#entries - 30), Color = "TextMuted" } })
						break
					end
					ctx.detail({
						{ Text = ("  %2d  "):format(index), Color = "TextMuted" },
						{ Text = entry.Text, Color = if entry.CanUndo then "Text" else "TextMuted" },
						{ Text = if entry.CanUndo then "" else "  (can't be undone)", Color = "TextMuted" },
					})
					table.insert(texts, entry.Text)
				end
				return texts
			elseif arg == "clear" then
				Undo.clear()
				ctx.success("cleared the undo list")
				return nil
			end
			local count = 1
			if arg ~= "" then
				count = tonumber(arg) :: number
				if not count or count < 1 or count ~= math.floor(count) then
					ctx.usage()
				end
			end
			local undone = {}
			for _ = 1, count do
				local ok, text = Undo.undo()
				if ok then
					table.insert(undone, text)
				else
					if #undone == 0 and text == "nothing to undo" then
						ctx.warn("nothing to undo")
					elseif text ~= "nothing to undo" then
						ctx.warn(text :: string)
					end
					break
				end
			end
			if #undone == 1 then
				ctx.success("undid " .. undone[1])
			elseif #undone > 1 then
				ctx.success(("undid %d steps: %s"):format(#undone, table.concat(undone, "; ")))
			end
			if T.Explorer and T.Explorer.View then
				T.Explorer.View:Refresh()
			end
			return undone
		end,
		Complete = function(_, argIndex)
			return if argIndex == 1 then { "list", "clear", "2", "5" } else {}
		end,
	},
	{
		Name = "integrity",
		Aliases = { "check" },
		Group = "Console",
		Usage = "/integrity",
		Description = "check Tungsten's files, executor functions, settings and data",
		Run = function(ctx)
			local report = T.import("base/integrity").run()
			if report.Clean then
				ctx.success("integrity ok · " .. report.Summary)
			elseif report.Ok then
				ctx.warn("integrity ok, with notes · " .. report.Summary)
			else
				ctx.error("integrity problems · " .. report.Summary)
			end
			for _, check in report.Checks do
				ctx.detail({
					{ Text = ("%-10s"):format(check.Name), Color = "TextMuted" },
					{ Text = if check.Ok and #check.Problems == 0 then "ok  " else "!!  ", Color = if check.Ok and #check.Problems == 0 then "Success" else "Warning" },
					{ Text = check.Text, Color = "Text" },
				})
				for _, text in check.Problems do
					ctx.detail({ { Text = "            " .. text, Color = "Warning" } })
				end
			end
			return report.Ok
		end,
	},
	{
		Name = "bar",
		Aliases = { "commandbar" },
		Group = "Window",
		Usage = "/bar [key <KeyCode>]",
		Description = "open the ' command bar, or change the key that opens it",
		Run = function(ctx)
			if (ctx.Args[1] or ""):lower() == "key" then
				local name = ctx.Args[2]
				local ok, key = pcall(function()
					return (Enum.KeyCode :: any)[name]
				end)
				if not name or not ok or typeof(key) ~= "EnumItem" then
					ctx.fail("say a key name, e.g. /bar key Quote (or F8, Semicolon, BackSlash …)")
				end
				T.Settings.set("CommandBarKey", key.Name)
				ctx.success(("the command bar opens with %s"):format(key.Name))
				return key.Name
			end
			task.defer(function()
				T.CommandBar.open()
			end)
			return nil
		end,
		Complete = function(_, argIndex)
			return if argIndex == 1 then { "key" } elseif argIndex == 2 then { "Quote", "BackSlash", "F8", "Semicolon", "Backquote" } else {}
		end,
	},
	{
		Name = "minimize",
		Aliases = { "hide" },
		Group = "Window",
		Usage = "/minimize",
		Description = "minimize the window to the button at the top",
		Run = function()
			task.defer(function()
				T.Window:Minimize()
			end)
		end,
	},
	{
		Name = "accent",
		Aliases = { "color" },
		Group = "Window",
		Usage = "/accent [r g b | #hex | reset]",
		Description = "show or change the accent color",
		Run = function(ctx)
			local args = ctx.Args
			local value
			if #args == 0 then
				local current = Settings.get("Accent")
				ctx.info(("accent %d %d %d"):format(current[1], current[2], current[3]))
				return current
			elseif args[1]:lower() == "reset" then
				value = Settings.defaults().Accent
			elseif args[1]:match("^#?%x%x%x%x%x%x$") then
				local hex = args[1]:gsub("#", "")
				value = { tonumber(hex:sub(1, 2), 16), tonumber(hex:sub(3, 4), 16), tonumber(hex:sub(5, 6), 16) }
			else
				local r, g, b = tonumber(args[1]), tonumber(args[2]), tonumber(args[3])
				if not (r and g and b) then
					ctx.usage()
				end
				value = { math.floor(r :: number), math.floor(g :: number), math.floor(b :: number) }
			end
			if not Settings.set("Accent", value) then
				ctx.fail("each channel must be 0 to 255")
			end
			ctx.success(("accent %d %d %d"):format(value[1], value[2], value[3]))
			return value
		end,
		Complete = function(_, argIndex)
			return if argIndex == 1 then { "reset", "#F0963C" } else {}
		end,
	},
	{
		Name = "menus",
		Group = "Window",
		Usage = "/menus [menu id]",
		Description = "list the named menus, or one menu's entries and who added them",
		Run = function(ctx)
			local Menus = T.import("base/ui/menus")
			local id = ctx.Args[1]
			if not id then
				local ids = Menus.list()
				ctx.info(("%d menus · /menus <id> lists one menu's entries"):format(#ids))
				for _, menuId in ids do
					local menu = Menus.get(menuId)
					ctx.detail({
						{ Text = menuId, Color = "Accent" },
						{ Text = ("  %s · %d entr%s"):format(menu.Title, #menu.Entries, if #menu.Entries == 1 then "y" else "ies"), Color = "TextDim" },
						{ Text = if menu.Locked then "  · fixed" elseif menu.Owner ~= "core" then "  · from " .. menu.Owner else "", Color = "TextMuted" },
					})
				end
				return ids
			end
			local menu = Menus.get(id)
			if not menu then
				ctx.fail(("no menu \"%s\" · /menus lists them"):format(id))
			end
			ctx.info(("%s · %s%s"):format(id, menu.Title, if menu.Locked then " · fixed (plugins can't add to it)" else ""))
			local sectionNames = {}
			for _, section in menu.Sections do
				table.insert(sectionNames, section.Id)
			end
			ctx.detail({ { Text = "sections  ", Color = "TextMuted" }, { Text = table.concat(sectionNames, ", "), Color = "Text" } })
			for _, entry in Menus.entries(id) do
				local text = if type(entry.Text) == "string" then entry.Text
					elseif entry.Menu then "› " .. entry.Menu
					elseif entry.Include then "+ " .. entry.Include
					elseif entry.Provide then "(several, built when opened)"
					else "(text built when opened)"
				ctx.detail({
					{ Text = ("%-10s"):format(tostring(entry.Section or "-")), Color = "TextMuted" },
					{ Text = ("%-26s"):format(tostring(entry.Id)), Color = "Text" },
					{ Text = text, Color = "TextDim" },
					{ Text = if entry.Owner ~= "core" then "  · " .. entry.Owner else "", Color = "Accent" },
				})
			end
			return id
		end,
		Complete = function(_, argIndex)
			if argIndex ~= 1 then
				return {}
			end
			return T.import("base/ui/menus").list()
		end,
	},
	{
		Name = "ui",
		Group = "Window",
		Usage = "/ui [component]",
		Description = "list the UI components, or one component's events and filters and who hooks them",
		Run = function(ctx)
			local UI = T.import("base/ui/ui")
			local name = ctx.Args[1]
			if not name then
				local names = UI.list()
				ctx.info(("%d components · /ui <name> lists its events and filters"):format(#names))
				for _, componentName in names do
					local info = UI.describe(componentName)
					ctx.detail({
						{ Text = ("%-16s"):format(componentName), Color = "Accent" },
						{ Text = info.Description, Color = "TextDim" },
					})
				end
				return names
			end
			local match
			for _, componentName in UI.list() do
				if componentName:lower() == name:lower() then
					match = componentName
				end
			end
			if not match then
				ctx.fail(("no component \"%s\" · /ui lists them"):format(name))
			end
			local info = UI.describe(match)
			ctx.info(("%s · %s"):format(match, info.Description))
			for _, group in { { "event", info.Events }, { "filter", info.Filters } } do
				for _, entry in group[2] do
					ctx.detail({
						{ Text = ("%-7s"):format(group[1]), Color = "TextMuted" },
						{ Text = ("%-18s"):format(entry.Name), Color = "Text" },
						{ Text = entry.Info, Color = "TextDim" },
						{ Text = if #entry.Hooks > 0 then "  · " .. table.concat(entry.Hooks, ", ") else "", Color = "Accent" },
					})
				end
			end
			return match
		end,
		Complete = function(_, argIndex)
			return if argIndex == 1 then T.import("base/ui/ui").list() else {}
		end,
	},
}
