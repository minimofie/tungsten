-- test fixture: builds its tab from the layout pieces and sub-tabs (Round C)
return {
	Id = "builder",
	Name = "Builder",
	Settings = {
		{ Id = "depth", Kind = "number", Text = "Depth", Hint = "how far to look", Default = 3, Min = 1, Max = 10 },
		{ Id = "loud", Kind = "toggle", Text = "Loud", Default = false },
	},
	Tab = {
		Title = "Builder",
		Build = function(page, api)
			local g = getgenv()
			local view = api.ui.page({ Parent = page, Toolbar = true })
			g.BuilderPage = view
			api.ui.new("Button", { Parent = view.Toolbar, Name = "Run", Text = "Run" })
			g.BuilderTabs = api.ui.subtabs({
				Parent = view.Body,
				Tabs = {
					{
						Id = "values",
						Title = "Values",
						Icon = "variable",
						Build = function(holder)
							g.BuilderValuesBuilt = (g.BuilderValuesBuilt or 0) + 1
							local left, right = api.ui.panes(holder, { Split = 0.4 })
							g.BuilderLeft, g.BuilderRight = left, right
							api.ui.section(right, "Options")
							g.BuilderDepth = api.ui.field(right, api.settings.item("depth"), api.settings)
							local row = api.ui.row(right, { Text = "Custom", Hint = "a row of its own" })
							api.ui.new("Toggle", { Parent = row.Control, Name = "Custom" })
							g.BuilderRow = row
							api.pathbar.show(workspace:FindFirstChild("ValuesThing"), nil, "values")
						end,
					},
					{
						Id = "remotes",
						Title = "Remotes",
						Build = function(holder)
							g.BuilderRemotesBuilt = (g.BuilderRemotesBuilt or 0) + 1
							api.ui.placeholder(holder, "Nothing yet", { "Run a scan to fill this." })
							api.pathbar.show(workspace:FindFirstChild("RemotesThing"), nil, "remotes")
						end,
					},
					{
						Id = "broken",
						Title = "Broken",
						Build = function()
							error("sub-tab broke")
						end,
					},
				},
			})
		end,
	},
}
