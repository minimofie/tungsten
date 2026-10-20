-- test fixture: a plugin that works and uses every part of the definition
local P = ...
local util = P.import("lib/util")
return {
	Id = "good",
	Name = "Good",
	Version = "1.2",
	Author = "tests",
	Description = "does everything right",
	Settings = {
		{ Id = "speed", Kind = "number", Text = "Speed", Default = 16, Min = 0, Max = 100 },
	},
	Commands = {
		{ Name = "goodhello", Usage = "/goodhello", Description = "say hello", Run = function(ctx) ctx.success(util.greet("tests")) end },
	},
	Functions = {
		{ Id = "goodname", Text = "Good: name", Run = function(list) return list[1] and list[1].Name end },
	},
	Tab = {
		Title = "Good",
		Build = function(page, api)
			local label = Instance.new("TextLabel")
			label.Name = "GoodLabel"
			label.Text = P.read("data.txt")
			label.Parent = page
			api.console.print("tab built")
		end,
	},
	Docs = "docs.md",
	Load = function(api)
		getgenv().GoodLoaded = (getgenv().GoodLoaded or 0) + 1
		api.variables.set("goodvar", util.answer)
	end,
	Unload = function(api)
		getgenv().GoodUnloaded = (getgenv().GoodUnloaded or 0) + 1
	end,
}
