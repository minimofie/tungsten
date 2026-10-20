-- Stage 5 Round C, part 2: building a plugin's tab: page (toolbar + body),
-- sections, rows, settings fields bound to a store, placeholder, two
-- fixed panes, sub-tabs inside the one tab (built when first shown,
-- faults under the plugin's name), the path bar per sub-tab, api.tab.
local passed, failed = 0, 0
local function check(name, cond, detail)
	if cond then
		passed += 1
	else
		failed += 1
		print("FAIL: " .. name .. (if detail ~= nil then "  [" .. tostring(detail) .. "]" else ""))
	end
end
local E_ = H.env
H.ABS_SHIFT = SHIFT or 0
local genv = H.genv

local ROOT = "Tungsten/plugins/"
local prefix = "fixtures/plugins/Builder/"
for path, content in H.FILES do
	if path:sub(1, #prefix) == prefix then
		H.FILES[ROOT .. "Builder/" .. path:sub(#prefix + 1)] = content
	end
end
H.FILES["Tungsten/base/plugins.json"] = '{"On":["builder"]}'
local valuesThing = H.part("ValuesThing", E_.workspace)
local remotesThing = H.part("RemotesThing", E_.workspace)

local ok, err = H.run("Tungsten/Tungsten.luau")
check("loader runs", ok, err)
H.advance(5)
local T = genv.Tungsten.Context
local Plugins = T.Plugins
local C = T.Console
local api = Plugins.get("builder").Api
check("builder is on", Plugins.get("builder").State == "on")
check("its tab isn't built until it opens", genv.BuilderPage == nil)

----------------------------------------------------------------------
-- 1. page, sub-tabs, path bar
----------------------------------------------------------------------
local before = #C.Lines
api.tab.select()
H.advance(0.4)
local tabs = genv.BuilderTabs
do
	check("api.tab.select opens its tab", T.Tabs.Selected == "builder" and api.tab.isOpen())
	local page = genv.BuilderPage
	check("page: toolbar and body", page and page.Toolbar and page.Body and H.find(page.Toolbar, "Run") ~= nil)
	check("sub-tabs: one strip with a tab per view", tabs and H.find(tabs.Instance, "Tab_values") and H.find(tabs.Instance, "Tab_remotes") and H.find(tabs.Instance, "Tab_broken"))
	check("the first opens by itself", tabs.Selected == "values" and genv.BuilderValuesBuilt == 1 and tabs:View("values").Visible)
	check("the others aren't built yet", genv.BuilderRemotesBuilt == nil and not tabs:View("remotes").Visible)
	check("the open one has the accent fill", H.find(tabs.Instance, "Tab_values").BackgroundColor3 == T.Theme.Colors.AccentSoft and H.find(tabs.Instance, "Tab_values").BackgroundTransparency == 0 and H.find(tabs.Instance, "Tab_remotes").BackgroundTransparency == 1)

	-- switch by clicking
	local remotesLabel = H.find(H.find(tabs.Instance, "Tab_remotes"), "Text")
	H.clickObject(remotesLabel)
	H.advance(0.2)
	check("clicking a sub-tab opens it and builds it once", tabs.Selected == "remotes" and genv.BuilderRemotesBuilt == 1 and tabs:View("remotes").Visible and not tabs:View("values").Visible)
	tabs:Select("values")
	tabs:Select("remotes")
	check("…built only once", genv.BuilderRemotesBuilt == 1 and genv.BuilderValuesBuilt == 1)
	check("placeholder in it", H.find(tabs:View("remotes"), "Placeholder") ~= nil)

	-- a sub-tab whose Build throws
	local faultsBefore = Plugins.get("builder").Faults
	before = #C.Lines
	tabs:Select("broken")
	H.advance(0.1)
	local out = {}
	for index = before + 1, #C.Lines do
		table.insert(out, C.Lines[index].Plain)
	end
	check("a failing sub-tab Build is reported under the plugin's name", table.concat(out, "\n"):find("[x] Builder: building sub-tab 'broken' failed: ", 1, true) ~= nil, table.concat(out, "\n"))
	check("…and counted", Plugins.get("builder").Faults == faultsBefore + 1)
	check("…the others still work", tabs:Select("values") and tabs.Selected == "values")
end

----------------------------------------------------------------------
-- 2. one path bar for every tab and sub-tab
----------------------------------------------------------------------
do
	local bar = T.import("base/ui/pathbar")
	local function crumbText()
		local strip = H.find(T.Window.Root, "Crumbs") or H.find(T.Window.Root, "PathBar")
		local texts = {}
		if strip then
			for _, d in strip:GetDescendants() do
				if d.ClassName == "TextLabel" or d.ClassName == "TextButton" then
					table.insert(texts, d.Text)
				end
			end
		end
		return table.concat(texts, " ")
	end
	-- the sub-tab Builds called api.pathbar.show: that loads for every tab
	check("api.pathbar.show loaded it for every tab (the last one shown)", T.Loaded.get() == remotesThing and crumbText():find("RemotesThing", 1, true) ~= nil, crumbText())
	tabs:Select("values")
	H.advance(0.2)
	check("switching sub-tabs doesn't change what is loaded", crumbText():find("RemotesThing", 1, true) ~= nil and crumbText():find("ValuesThing", 1, true) == nil, crumbText())
	T.Tabs:Select("console")
	H.advance(0.2)
	check("another tab shows the same", crumbText():find("RemotesThing", 1, true) ~= nil, crumbText())
	local by
	local conn = T.Loaded.Changed:Connect(function(_, who) by = who end)
	api.pathbar.show(valuesThing)
	H.advance(0.2)
	conn:Disconnect()
	check("a plugin's show loads as that plugin", by == "builder", by)
	check("…and every tab follows", crumbText():find("ValuesThing", 1, true) ~= nil, crumbText())
	api.tab.select()
	tabs:Select("broken")
	H.advance(0.2)
	check("…its own tab too", crumbText():find("ValuesThing", 1, true) ~= nil, crumbText())
	tabs:Select("values")
	H.advance(0.2)
end

----------------------------------------------------------------------
-- 3. sections, rows, fields, panes
----------------------------------------------------------------------
do
	local right = genv.BuilderRight
	check("panes: two, side by side, fixed split", genv.BuilderLeft and right and math.abs(genv.BuilderLeft.Size.X.Scale - 0.4) < 1e-6 and math.abs(right.Position.X.Scale - 0.4) < 1e-6)
	check("section heading", H.find(right, "Section_Options") ~= nil and H.find(right, "Section_Options").Text == "OPTIONS")
	check("row with its own control", genv.BuilderRow and H.find(genv.BuilderRow.Control, "Custom") ~= nil)
	local field = genv.BuilderDepth
	check("field: a settings row bound to the store", field and field.Control and field.Control.Widget ~= nil)
	field.Control.Widget:SetValue(7)
	local box = field.Control.Widget
	if box._commit then
		box:_commit()
	end
	api.settings.set("depth", 7)
	H.advance(0.1)
	check("field: writes the store", api.settings.get("depth") == 7)
	api.settings.set("depth", 2)
	H.advance(0.1)
	check("field: follows a change made elsewhere", field.Control.Widget.Value == 2, field.Control.Widget.Value)
	check("layout order follows the order they were made", H.find(right, "Section_Options").LayoutOrder < field.Instance.LayoutOrder and field.Instance.LayoutOrder < genv.BuilderRow.Instance.LayoutOrder)
end

----------------------------------------------------------------------
-- 4. api.tab badge, scale, and stopping
----------------------------------------------------------------------
do
	api.tab.badge(3)
	check("api.tab.badge", T.Registry.getTab("builder").Badge == 3)
	api.tab.badge(0)
	T.Scale.set(1.3)
	H.advance(0.4)
	local strip = tabs.Strip
	check("sub-tabs keep their size at scale 1.3 (drawn 1:1)", math.abs(T.import("base/ui/create").scaleOf(strip) - 1) < 0.001)
	local valuesButton = H.find(tabs.Instance, "Tab_values")
	local labels = H.find(H.find(tabs.Instance, "Tab_remotes"), "Text")
	H.clickObject(labels)
	H.advance(0.2)
	check("…and clicks still land on the right one at 130%", tabs.Selected == "remotes")
	T.Scale.set(1)
	H.advance(0.3)
	Plugins._disable(Plugins.get("builder"))
	H.advance(0.2)
	check("stopping the plugin removes its tab and sub-tabs", T.Registry.getTab("builder") == nil and (tabs.Instance.Parent == nil or tabs.Destroyed))
end

check("no runtime errors", #H.ERRORS == 0, H.ERRORS[1])
print(("stage5h: %d passed, %d failed, %d runtime errors"):format(passed, failed, #H.ERRORS))
