-- test fixture: tries to take Alpha's variable, reads it instead
return {
	Id = "beta",
	Name = "Beta",
	Order = 2,
	Load = function(api)
		local g = getgenv()
		g.BetaSet = table.pack(api.variables.set("shared", "beta"))
		g.BetaUnset = table.pack(api.variables.unset("shared"))
		g.BetaRead = api.variables.get("shared")
		g.BetaOwner = api.variables.owner("shared")
		api.variables.set("betavar", 1)
	end,
}
