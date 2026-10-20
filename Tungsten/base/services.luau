--[[
	Tungsten · base/services
	Cloned service references, fetched on first use:

		local Services = T.import("base/services")
		Services.TweenService:Create(...)
]]

local cache = {}

return setmetatable({}, {
	__index = function(_, name: string)
		local service = cache[name]
		if service == nil then
			service = cloneref(game:GetService(name))
			cache[name] = service
		end
		return service
	end,
})
