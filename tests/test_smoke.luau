local passed, failed = 0, 0
local function check(name, cond, detail)
	if cond then
		passed += 1
	else
		failed += 1
		print("FAIL: " .. name .. (if detail ~= nil then "  [" .. tostring(detail) .. "]" else ""))
	end
end
H.CHECK = check

local ok, err = H.run("Tungsten/Tungsten.luau")
check("loader runs", ok, err)
H.advance(1)
local G = H.genv.Tungsten
check("global handle", G ~= nil)
local T = G and G.Context
check("no errors at start", #H.ERRORS == 0, H.ERRORS[1])

local guis = H.HUI:GetChildren()
check("three screen guis (window, overlay, command bar)", #guis == 3, #guis)

check("no component test tab", T.Registry.getTab("componenttest") == nil)
check("no test keys module", H.FILES["Tungsten/base/testkeys.luau"] == nil and H.FILES["Tungsten/base/testtab.luau"] == nil)
check("explorer started", T.Explorer ~= nil and T.Explorer.Tree ~= nil)
check("path bar started", T.PathBar ~= nil and T.PathBar.Instance ~= nil)
check("explorer panel on the window", H.find(T.Window.Root, "Explorer") ~= nil)
for _, id in { "console", "documentation", "plugins" } do
	check("tab " .. id, T.Tabs:Select(id))
	H.advance(0.4)
	check("page built " .. id, T.Tabs.Pages[id] ~= nil and T.Tabs.Pages[id].Visible)
end
check("no errors after opening tabs", #H.ERRORS == 0, H.ERRORS[1])

for _, e in H.ERRORS do print("ERR: " .. e) end
print(("smoke: %d passed, %d failed"):format(passed, failed))
return T
