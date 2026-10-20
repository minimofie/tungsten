-- test fixture: owns $shared and watches it
return {
	Id = "alpha",
	Name = "Alpha",
	Order = 1,
	Load = function(api)
		local g = getgenv()
		g.AlphaSeen = {}
		g.AlphaChanges = 0
		api.variables.set("shared", "alpha")
		api.variables.watch("shared", function(value, old, removed, by)
			table.insert(g.AlphaSeen, { Value = value, Removed = removed, By = by })
		end)
		api.variables.Changed:Connect(function()
			g.AlphaChanges += 1
		end)
	end,
}
