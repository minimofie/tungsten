-- test fixture: links to the prime plugins it Uses (soft: starts without them)
return {
	Id = "linker",
	Name = "Linker",
	Uses = { "scriptviewer", "instanceviewer" },
	Tab = {
		Title = "Linker",
		Build = function() end,
		OnLoad = function(values, api)
			getgenv().LinkerGot = values
			if getgenv().LinkerFail then
				error("linker OnLoad broke")
			end
			if getgenv().LinkerReload then
				getgenv().LinkerReload = getgenv().LinkerReload - 1
				api.loaded.set(getgenv().LinkerReloadWith)
			end
		end,
	},
	Load = function(api)
		getgenv().LinkerApi = api
	end,
}
