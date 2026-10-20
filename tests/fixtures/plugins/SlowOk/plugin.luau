-- test fixture: Load waits a moment, within the limit
return {
	Id = "slowok",
	Name = "Slow but fine",
	Load = function(api)
		task.wait(1)
		getgenv().SlowOkDone = true
	end,
}
