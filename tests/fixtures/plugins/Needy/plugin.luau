-- test fixture: needs the scanner
return {
	Id = "needy",
	Name = "Needy",
	Order = 1,
	Requires = { "scanner" },
	Load = function(api)
		local scanner, why = api.plugins.get("scanner")
		getgenv().NeedyGot = if scanner then scanner.ping() else why
		local _, notListed = api.plugins.get("good")
		getgenv().NeedyNotListed = notListed
	end,
}
