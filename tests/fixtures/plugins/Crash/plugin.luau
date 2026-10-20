-- test fixture: Load throws after registering a command
return {
	Id = "crash",
	Name = "Crash",
	Commands = { { Name = "crashcmd", Run = function(ctx) end } },
	Load = function(api)
		api.variables.set("crashvar", 1)
		error("boom in Load")
	end,
}
