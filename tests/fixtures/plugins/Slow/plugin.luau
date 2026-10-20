-- test fixture: Load never finishes in time
return {
	Id = "slow",
	Name = "Slow",
	Load = function(api)
		task.wait(30)
		getgenv().SlowFinished = true
		api.variables.set("slowvar", 1)
	end,
}
