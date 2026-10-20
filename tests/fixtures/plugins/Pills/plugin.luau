-- test fixture (in-game P0b checklist): a tab with sub-tabs, a badge and
-- enough sub-tabs to scroll
return {
	Id = "pills",
	Name = "Pills",
	Tab = {
		Title = "Pills",
		Icon = "object",
		Build = function(page, api)
			local list = {
				{ Id = "constants", Title = "Constants", Icon = "type_number", Build = function(view)
					api.ui.placeholder(view, "Constants view")
				end },
				{ Id = "upvalues", Title = "Upvalues", Icon = "variable", Badge = 3, Build = function(view)
					api.ui.placeholder(view, "Upvalues view")
				end },
				{ Id = "source", Title = "Source", Build = function(view)
					api.ui.placeholder(view, "Source view")
				end },
			}
			for index = 1, 10 do
				table.insert(list, { Id = "extra" .. index, Title = "Extra view " .. index, Icon = "object" })
			end
			getgenv().PillsTabs = api.ui.subtabs({ Parent = page, Tabs = list })
		end,
	},
}
