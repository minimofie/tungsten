local P = ...
getgenv().GoodUtilRuns = (getgenv().GoodUtilRuns or 0) + 1
return {
	answer = 42,
	folder = P.Folder,
	greet = function(who) return "hello " .. who end,
}
