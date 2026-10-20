-- test fixture: every callback it hands Tungsten throws
return {
	Id = "faulty",
	Name = "Faulty",
	Settings = { { Id = "go", Kind = "action", Text = "Go", Run = function() error("action broke") end } },
	Commands = {
		{
			Name = "faultcmd",
			Run = function() local t = nil; return t.x end,
			Complete = function() error("complete broke") end,
		},
	},
	Functions = {
		{ Id = "faultfn", Text = "Fault", AppliesTo = function() error("applies broke") end, Run = function() error("run broke") end },
	},
	Tab = { Title = "Faulty", Build = function() error("build broke") end },
	Load = function(api)
		api.ui.on("Button", "Clicked", function() error("hook broke") end, { Owner = api.Id })
	end,
	Unload = function() error("unload broke") end,
}
