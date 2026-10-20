-- test fixture: stands in for the prime plugin "scriptviewer" (P0 tests)
return {
	Id = "scriptviewer",
	Name = "Script Viewer",
	Prime = true,
	Tab = {
		Title = "Script Viewer",
		Build = function(page, api)
			getgenv().ViewerBuilt = (getgenv().ViewerBuilt or 0) + 1
		end,
		OnLoad = function(values, api, items)
			getgenv().ViewerLoads = (getgenv().ViewerLoads or 0) + 1
			getgenv().ViewerGot = values
			getgenv().ViewerItems = items
			getgenv().ViewerOpenWhenLoaded = api.tab.isOpen()
			return true
		end,
	},
	Exports = function(api)
		return {
			reveal = function(focus)
				if type(focus) == "table" and focus.Fail then
					error("can't reveal that")
				end
				getgenv().ViewerRevealed = focus
				getgenv().ViewerOpenOnReveal = api.tab.isOpen()
			end,
		}
	end,
}
