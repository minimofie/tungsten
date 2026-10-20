-- test fixture: stands in for the prime plugin "scanner"
return {
	Id = "scanner",
	Name = "Scanner",
	Prime = true,
	Order = 500, -- primes load first anyway
	Exports = function(api)
		return { ping = function() return "pong" end, owner = api.Id }
	end,
}
