-- Stage 5 Round C, part 3: the authoring guide (Documentation › Plugins).
-- Its template and its tab example are taken out of the topic and run as
-- real plugins, so the guide can't drift from what Tungsten does.
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

local topic = H.FILES["Tungsten/documentation/topics/09_plugins.md"]
check("the guide exists", type(topic) == "string")

-- the code block after a heading
local function codeAfter(heading)
	local at = topic:find(heading, 1, true)
	if not at then
		return nil
	end
	local open = topic:find("```\n", at, true)
	local close = open and topic:find("\n```", open + 4, true)
	return open and close and topic:sub(open + 4, close)
end

local template = codeAfter("## Template")
check("the template is in the guide", template and template:find("return {", 1, true) ~= nil)
local tabExample = codeAfter("## Building its tab")
check("the tab example is in the guide", tabExample and tabExample:find("api.ui.subtabs", 1, true) ~= nil)

H.FILES["Tungsten/plugins/MyPlugin/plugin.luau"] = template
H.FILES["Tungsten/plugins/Spawner/plugin.luau"] = "return { Id = 'spawner', Name = 'Spawner', Settings = { { Id = 'speed', Kind = 'number', Text = 'Speed', Default = 16 } },\n"
	.. tabExample .. "\n}"
H.FILES["Tungsten/base/plugins.json"] = '{"On":["myplugin","spawner"]}'
H.part("Thing", E_.workspace)

local ok, err = H.run("Tungsten/Tungsten.luau")
check("loader runs", ok, err)
H.advance(5)
local T = genv.Tungsten.Context
local Plugins = T.Plugins
local C = T.Console
local function run(input)
	local before = #C.Lines
	C.run(input)
	H.advance(0.2)
	local out = {}
	for index = before + 1, #C.Lines do
		table.insert(out, C.Lines[index].Plain)
	end
	return table.concat(out, "\n")
end

----------------------------------------------------------------------
-- 1. the template works as it is
----------------------------------------------------------------------
do
	local record = Plugins.get("myplugin")
	check("template: on", record and record.State == "on", record and record.Problem)
	check("template: no warnings (it sets Id)", record and #record.Warnings == 0)
	local welcome = {}
	for index = 1, #C.Lines do
		table.insert(welcome, C.Lines[index].Plain)
	end
	check("template: Load printed under its name", table.concat(welcome, "\n"):find("[plugin] My Plugin: loaded from Tungsten/plugins/MyPlugin", 1, true) ~= nil)
	check("template: /greet", run("/greet you"):find("hello you", 1, true) ~= nil)
	local found = false
	for _, entry in T.Menus.entries("explorer.function") do
		if entry.Owner == "myplugin" then
			found = true
		end
	end
	check("template: its explorer function", found)
	T.Tabs:Select("myplugin")
	H.advance(0.3)
	local page = T.Tabs.Pages.myplugin
	check("template: its tab builds with a settings field", page and H.find(page, "Pref_count") ~= nil)
	local at = #C.Lines
	record.Api.settings.set("count", 5)
	H.advance(0.1)
	local out = {}
	for index = at + 1, #C.Lines do
		table.insert(out, C.Lines[index].Plain)
	end
	check("template: its owned listener hears setting changes", table.concat(out, "\n"):find("count is now 5", 1, true) ~= nil, table.concat(out, "\n"))
end

----------------------------------------------------------------------
-- 2. the tab example works as it is
----------------------------------------------------------------------
do
	local record = Plugins.get("spawner")
	check("tab example: on", record and record.State == "on", record and record.Problem)
	T.Tabs:Select("spawner")
	H.advance(0.3)
	local page = T.Tabs.Pages.spawner
	check("tab example: toolbar, sub-tabs, panes, section, field, row", page and H.find(page, "Toolbar") and H.find(page, "Tab_make") and H.find(page, "Tab_list")
		and H.find(page, "Section_Options") and H.find(page, "Pref_speed") and H.find(page, "Row_Anchored"))
	check("no faults from the examples", record.Faults == 0 and Plugins.get("myplugin").Faults == 0)
end

----------------------------------------------------------------------
-- 3. the guide reads well in the Documentation tab
----------------------------------------------------------------------
do
	local doc = T.Docs.get("plugins")
	check("the topic loads", doc ~= nil)
	local headings = {}
	for _, block in doc.Blocks do
		if block.Kind == "heading" or block.Kind == "h2" or block.Level == 2 then
			table.insert(headings, block.Text)
		end
	end
	local text = table.concat(headings, "|")
	for _, want in { "Installing and turning on", "The Plugins tab", "Writing a plugin", "The definition", "Lifecycle", "Settings", "The api", "Building its tab", "Console commands", "Explorer actions", "Variables", "Listeners and threads", "Files", "Prime plugins", "Rules", "Template" } do
		check("section: " .. want, text:find(want, 1, true) ~= nil, text)
	end
	-- every string in the expanded blocks (live blocks are filled in)
	local seen = {}
	local function strings(value, out, depth)
		if depth > 6 or seen[value] then
			return
		end
		if type(value) == "string" then
			table.insert(out, value)
		elseif type(value) == "table" then
			seen[value] = true
			for _, item in value do
				strings(item, out, depth + 1)
			end
		end
	end
	local all = {}
	strings(doc.Blocks, all, 0)
	local joined = table.concat(all, "\n")
	check("the live list of plugin commands shows the template's command", joined:find("greet", 1, true) ~= nil and joined:find("{{plugin-commands}}", 1, true) == nil)
	check("no preview wording left", not topic:find("This is a preview", 1, true) and not topic:find("manager will", 1, true) and not topic:find("will be listed", 1, true))
end

check("no runtime errors", #H.ERRORS == 0, H.ERRORS[1])
print(("stage5i: %d passed, %d failed, %d runtime errors"):format(passed, failed, #H.ERRORS))
