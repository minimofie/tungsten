--[[
	Tungsten · console/commands/session
	Facts about the running game: fps, ping, players, place, mem,
	services. Read-only; nothing here changes the game.
]]

local T = ...
local Services = T.import("base/services")
local Types = T.import("base/types")

local function localPlayer()
	local ok, player = pcall(function()
		return Services.Players.LocalPlayer
	end)
	return if ok then player else nil
end

local function pad(text: string, width: number): string
	return if #text >= width then text .. " " else text .. string.rep(" ", width - #text)
end

return {
	{
		Name = "fps",
		Group = "Game",
		Usage = "/fps",
		Description = "measure frames per second for half a second",
		Run = function(ctx)
			local frames, elapsed = 0, 0
			local slowest = 0
			local connection
			connection = Services.RunService.RenderStepped:Connect(function(dt)
				frames += 1
				elapsed += dt
				slowest = math.max(slowest, dt)
			end)
			local begin = os.clock()
			while elapsed < 0.5 and os.clock() - begin < 3 do
				task.wait()
			end
			connection:Disconnect()
			if frames == 0 or elapsed <= 0 then
				ctx.fail("no frames were drawn")
			end
			local fps = frames / elapsed
			ctx.Console.write("time", {
				{ Text = ("%.0f fps"):format(fps), Color = "Accent" },
				{ Text = ("  · %.1f ms a frame · slowest %.1f ms"):format(elapsed / frames * 1000, slowest * 1000), Color = "TextDim" },
			})
			return fps
		end,
	},
	{
		Name = "ping",
		Group = "Game",
		Usage = "/ping",
		Description = "your connection's round trip to the server",
		Run = function(ctx)
			local player = localPlayer()
			if not player then
				ctx.fail("no local player")
			end
			local ok, seconds = pcall(function()
				return player:GetNetworkPing()
			end)
			if not ok or type(seconds) ~= "number" then
				ctx.fail("ping is not available here")
			end
			-- GetNetworkPing is one way; the round trip is twice that.
			local ms = seconds * 2000
			ctx.Console.write("time", { { Text = ("%.0f ms"):format(ms), Color = "Accent" }, { Text = " round trip", Color = "TextDim" } })
			return ms
		end,
	},
	{
		Name = "players",
		Aliases = { "who" },
		Group = "Game",
		Usage = "/players [filter]",
		Description = "list players in the server",
		Run = function(ctx)
			local ok, list = pcall(function()
				return Services.Players:GetPlayers()
			end)
			if not ok or type(list) ~= "table" then
				ctx.fail("can't read the player list")
			end
			local filter = ctx.Args[1] and ctx.Args[1]:lower()
			local me = localPlayer()
			local shown = 0
			ctx.info(("%d player%s"):format(#list, if #list == 1 then "" else "s"))
			for _, player in list do
				local name, display, id, team = "?", "?", 0, nil
				pcall(function()
					name, display, id = player.Name, player.DisplayName, player.UserId
					team = player.Team
				end)
				if filter == nil or name:lower():find(filter, 1, true) or display:lower():find(filter, 1, true) then
					shown += 1
					local segments, opts = ctx.Console.valueSegments(nil, player)
					segments = {
						{ Text = "  ", Color = "Text" },
						{ Text = pad(display, 20), Color = if player == me then "Accent" else "Text" },
						{ Text = pad("@" .. name, 22), Color = "TextDim" },
						{ Text = pad(tostring(id), 12), Color = "TextMuted" },
						{ Text = if team then tostring(team) else "", Color = "TextMuted" },
					}
					opts.IconAt = 0
					ctx.detail(segments, opts)
				end
			end
			if filter and shown == 0 then
				ctx.info(("nobody matches \"%s\""):format(filter))
			end
			return list
		end,
	},
	{
		Name = "place",
		Aliases = { "server" },
		Group = "Game",
		Usage = "/place",
		Description = "place, game and server ids",
		Run = function(ctx)
			local facts = {
				{ "place id", function() return game.PlaceId end },
				{ "game id", function() return game.GameId end },
				{ "version", function() return game.PlaceVersion end },
				{ "server", function() return game.JobId end },
				{ "players", function() return ("%d / %d"):format(#Services.Players:GetPlayers(), Services.Players.MaxPlayers) end },
				{ "uptime", function() return ("%.0f s"):format(workspace.DistributedGameTime) end },
			}
			ctx.info("this place")
			for _, fact in facts do
				local ok, value = pcall(fact[2])
				ctx.detail({ { Text = pad(fact[1], 10), Color = "TextMuted" }, { Text = if ok then tostring(value) else "-", Color = "Text" } })
			end
			return game.PlaceId
		end,
	},
	{
		Name = "mem",
		Aliases = { "memory" },
		Group = "Game",
		Usage = "/mem",
		Description = "Luau and game memory use",
		Run = function(ctx)
			local luaKb = gcinfo()
			ctx.info("memory")
			ctx.detail({ { Text = pad("luau", 10), Color = "TextMuted" }, { Text = ("%.1f MB"):format(luaKb / 1024), Color = "Text" } })
			local ok, total = pcall(function()
				return Services.Stats:GetTotalMemoryUsageMb()
			end)
			if ok and type(total) == "number" then
				ctx.detail({ { Text = pad("game", 10), Color = "TextMuted" }, { Text = ("%.0f MB"):format(total), Color = "Text" } })
			end
			return luaKb
		end,
	},
	{
		Name = "services",
		Group = "Game",
		Usage = "/services [filter]",
		Description = "list the game's services",
		Run = function(ctx)
			local ok, children = pcall(function()
				return game:GetChildren()
			end)
			if not ok or type(children) ~= "table" then
				ctx.fail("can't list services")
			end
			local filter = ctx.Args[1] and ctx.Args[1]:lower()
			local list = {}
			for _, child in children do
				local class = Types.classOf(child) or "?"
				if filter == nil or class:lower():find(filter, 1, true) then
					table.insert(list, child)
				end
			end
			table.sort(list, function(a, b)
				return (Types.classOf(a) or "") < (Types.classOf(b) or "")
			end)
			ctx.info(("%d services"):format(#list))
			for _, child in list do
				local icon, color = Types.icon(child)
				ctx.detail({ { Text = "  ", Color = "Text" }, { Text = Types.classOf(child) or "?", Color = "Text" } }, { Icon = icon, IconColor = color, IconAt = 0 })
			end
			return list
		end,
	},
}
