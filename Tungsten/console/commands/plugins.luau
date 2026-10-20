--[[
	Tungsten · console/commands/plugins
	The plugins in Tungsten/plugins (base/plugins):
		/plugins                 every plugin: id, name, version, state
		/plugins rescan          pick up new or changed folders
		/plugin on <id>          start it at the next start
		/plugin off <id>         stop it at the next start (it keeps running now)
		/plugin reload <id>      read its files again and start it again
		/plugin info <id>        everything about one plugin
]]

local T = ...

local STATE_COLOR = { on = "Success", off = "TextMuted", failed = "Danger", problem = "Danger" }

local function host(ctx)
	local plugins = T.Plugins
	if type(plugins) ~= "table" or type(plugins.list) ~= "function" then
		ctx.fail("the plugin host isn't running")
	end
	return plugins
end

local function pad(text: string, width: number): string
	return if #text >= width then text .. " " else text .. string.rep(" ", width - #text)
end

-- A record by id or folder name (problems without an id have only a folder).
local function find(plugins, key: string?)
	if not key or key == "" then
		return nil
	end
	local record = plugins.get(key) or plugins.byFolder(key)
	if record then
		return record
	end
	local lower = key:lower()
	for _, other in plugins.list() do
		if (other.Id and other.Id:lower() == lower) or other.Folder:lower() == lower then
			return other
		end
	end
	return nil
end

local function require(ctx, plugins, key: string?)
	local record = find(plugins, key)
	if not record then
		ctx.fail(("no plugin '%s' · /plugins lists them"):format(tostring(key)))
	end
	return record
end

local function pendingText(plugins, record): string
	local pending = record.Id and plugins.pending(record.Id)
	return if pending then (" · %s at the next start"):format(pending) else ""
end

local function idChoices()
	local out = {}
	local plugins = T.Plugins
	if type(plugins) == "table" and type(plugins.list) == "function" then
		for _, record in plugins.list() do
			table.insert(out, { Text = record.Id or record.Folder, Hint = record.State })
		end
	end
	return out
end

-- What a running plugin has registered, counted by kind.
local function adds(id: string): string
	local parts = {}
	local okCommands, Commands = pcall(T.import, "console/commands")
	if okCommands then
		local count = 0
		for _, command in Commands.list() do
			if command.Owner == id then
				count += 1
			end
		end
		if count > 0 then
			table.insert(parts, ("%d command%s"):format(count, if count == 1 then "" else "s"))
		end
	end
	local tabs = 0
	for _, tab in T.Registry.allTabs() do
		if tab.Owner == id then
			tabs += 1
		end
	end
	if tabs > 0 then
		table.insert(parts, ("%d tab%s"):format(tabs, if tabs == 1 then "" else "s"))
	end
	local functions = 0
	for _, entry in T.Menus.entries("explorer.function") do
		if entry.Owner == id then
			functions += 1
		end
	end
	if functions > 0 then
		table.insert(parts, ("%d explorer function%s"):format(functions, if functions == 1 then "" else "s"))
	end
	local variables = 0
	for _, entry in T.Variables.list() do
		if entry.Source == id then
			variables += 1
		end
	end
	if variables > 0 then
		table.insert(parts, ("%d variable%s"):format(variables, if variables == 1 then "" else "s"))
	end
	return if #parts > 0 then table.concat(parts, " · ") else "nothing yet"
end

return {
	{
		Name = "plugins",
		Group = "Plugins",
		Usage = "/plugins [rescan]",
		Description = "list the plugins in Tungsten/plugins (rescan: find new ones)",
		Complete = function(_, argIndex)
			return if argIndex <= 2 then { "rescan" } else {}
		end,
		Run = function(ctx)
			local plugins = host(ctx)
			local arg = ctx.Args[1]
			if arg and arg:lower() == "rescan" then
				local before = #plugins.list()
				local list = plugins.rescan()
				ctx.success(("%d plugin%s found (%+d)"):format(#list, if #list == 1 then "" else "s", #list - before))
				return #list
			elseif arg then
				ctx.usage()
			end
			local list = plugins.list()
			if #list == 0 then
				ctx.info("no plugins · put a plugin's folder in Tungsten/plugins, then /plugins rescan")
				return 0
			end
			for _, record in list do
				local id = record.Id or ("(" .. record.Folder .. ")")
				ctx.Console.write("info", {
					{ Text = pad(id, 16), Color = "Text" },
					{ Text = pad(tostring(record.Name or record.Folder), 20), Color = "TextDim" },
					{ Text = pad(if record.Version then "v" .. record.Version else "", 8), Color = "TextMuted" },
					{ Text = record.State, Color = STATE_COLOR[record.State] or "Text" },
					{ Text = pendingText(plugins, record), Color = "Warning" },
					{ Text = if record.Problem then " · " .. record.Problem else "", Color = "TextMuted" },
				})
			end
			ctx.detail(("%d on · /plugin info <id> for one"):format(plugins.count()))
			return #list
		end,
	},
	{
		Name = "plugin",
		Group = "Plugins",
		Usage = "/plugin <on | off | reload | info> <id>",
		Description = "turn a plugin on or off (from the next start), reload it, or show it",
		Complete = function(_, argIndex)
			if argIndex <= 2 then
				return { "on", "off", "reload", "info" }
			end
			return idChoices()
		end,
		Run = function(ctx)
			local plugins = host(ctx)
			local action = (ctx.Args[1] or ""):lower()
			local key = ctx.Args[2]
			if action == "" or not key then
				ctx.usage()
			end
			local record = require(ctx, plugins, key)
			local id = record.Id
			if action == "on" or action == "off" then
				if not id then
					ctx.fail(("%s can't run: %s"):format(record.Folder, tostring(record.Problem)))
				end
				local on = action == "on"
				local ok, why = plugins.setWanted(id, on)
				if not ok then
					ctx.fail(why or "could not change it")
				end
				local running = record.State == "on"
				if on == running then
					ctx.success(("%s stays %s"):format(id, action))
				else
					ctx.success(("%s will be %s at the next start%s"):format(id, action, if running then " (it keeps running until then)" else ""))
				end
				return on
			elseif action == "reload" then
				local function report(ok, why)
					local now = find(plugins, key) or record
					if ok then
						ctx.Console.success(("%s reloaded · %s"):format(now.Id or now.Folder, now.State))
					else
						ctx.Console.write("warn", ("%s: %s"):format(now.Id or now.Folder, tostring(why)))
					end
				end
				if coroutine.isyieldable() then
					local ok, why = plugins.reload(id or record.Folder)
					report(ok, why)
					return ok
				end
				-- Load may wait; do it where Tungsten can wait for it.
				task.spawn(function()
					report(plugins.reload(id or record.Folder))
				end)
				ctx.info(("reloading %s…"):format(id or record.Folder))
				return nil
			elseif action == "info" then
				local Console = ctx.Console
				Console.write("info", {
					{ Text = tostring(record.Name or record.Folder), Color = "Accent" },
					{ Text = if record.Version then " v" .. record.Version else "", Color = "TextDim" },
					{ Text = if record.Author then " · by " .. record.Author else "", Color = "TextDim" },
				})
				if record.Description then
					ctx.detail(record.Description)
				end
				ctx.detail(("id %s · folder plugins/%s"):format(tostring(id or "—"), record.Folder))
				ctx.detail({
					{ Text = "state ", Color = "TextMuted" },
					{ Text = record.State, Color = STATE_COLOR[record.State] or "Text" },
					{ Text = pendingText(plugins, record), Color = "Warning" },
				})
				if record.Problem then
					ctx.detail({ { Text = record.Problem, Color = "Danger" } })
				end
				if record.State == "on" and record.LoadTime then
					ctx.detail(("loaded in %d ms · adds %s"):format(math.floor(record.LoadTime * 1000 + 0.5), adds(id :: string)))
				end
				local definition = record.Definition
				if definition and definition.Requires and #definition.Requires > 0 then
					ctx.detail("needs " .. table.concat(definition.Requires, ", "))
				end
				if definition and definition.Uses and #definition.Uses > 0 then
					ctx.detail("uses (when on) " .. table.concat(definition.Uses, ", "))
				end
				if (record.Faults or 0) > 0 then
					local last = record.LastFault
					ctx.detail({
						{ Text = ("%d fault%s"):format(record.Faults, if record.Faults == 1 then "" else "s"), Color = "Warning" },
						{ Text = if last then (" · last: %s failed: %s"):format(last.What, last.Message) else "", Color = "TextMuted" },
					})
				end
				for _, warning in record.Warnings or {} do
					ctx.detail({ { Text = warning, Color = "Warning" } })
				end
				if record.Hooks and #record.Hooks > 0 then
					ctx.detail(("its code mentions %s (it runs with the executor's rights)"):format(table.concat(record.Hooks, ", ")))
				end
				return record.State
			end
			ctx.usage()
		end,
	},
}
