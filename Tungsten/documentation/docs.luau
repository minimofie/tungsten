--[[
	Tungsten · documentation/docs
	The documentation is modular: topics come from files and from code
	(plugins), any topic can get extra sections from elsewhere, and live
	blocks ("directives") are filled in each time a page is shown.

	Topic files: documentation/topics/NN_id.md ("01_console.md": the number
	sets the order, the rest is the id). The first "# " line is the title.

	Supported formatting (one block per line or group of lines)
		# Title / ## Section / ### Small heading
		plain lines           paragraph (lines next to each other join up)
		- item                bullet list
		> text                tip box
		| a | b |             table (first row is the header; |---| rows are skipped)
		```  ...  ```         code block
		---                   divider
		{{name}} / {{name:arg}}  a live block (see Directives)
	Inline: `code` and **bold**.

	Reading
		Docs.topics()          -> { topic } sorted by group, then Order
		Docs.get(id) ; Docs.find("prefix") ; Docs.search("text")
		Docs.open("commands")  shows a topic in the Documentation tab
		Docs.reload()
	A topic: { Id, Title, Order, Group, Owner, Blocks (expanded), Text,
	Source, Build? }.

	Topics of your own (plugins)
		Docs.addTopic({
			Id = "remotespy", Title = "Remote Spy", Order = 10,
			Group = "Remote Spy",          -- groups sort after Tungsten's own
			Source = "# Remote Spy\n…",    -- the same formatting as the files
			-- or File = "Tungsten/plugins/RemoteSpy/docs.md"
			-- or Build = function(content, view) end  (a page of your own UI)
			Keywords = { "remote", "hook" },
			Owner = "remotespy",
		})
		Docs.addSection("commands", {    -- extra section in any topic
			Id = "remotespy", Title = "Remote Spy", Order = 50,
			Source = "| Command | … |", Owner = "remotespy",
		})
		Docs.addDirective("remotes", {   -- a live block: {{remotes}} / {{remotes:arg}}
			Source = function(arg, topic) return "markdown text" end,   -- or
			Blocks = function(arg, topic) return { blocks } end,
			Owner = "remotespy",
		})
		Docs.addGroup("Remote Spy", { Order = 10 })
		Docs.removeOwner("remotespy")

	Built-in directives: {{commands:Group}} (that group's commands, live),
	{{commands-other}} (groups no topic lists), {{plugin-commands}},
	{{menus}}, {{components}}, {{filter-groups}}, {{groups}}.
]]

local T = ...
local signal = T.import("base/signal")

local DIR = T.Root .. "/documentation/topics"

local Docs = {}
Docs.Changed = signal.new() -- topics reloaded or added
Docs.OpenRequested = signal.new() -- (topic)
Docs.Pending = nil -- topic asked for before the tab was built

local fileTopics: { any }? = nil -- from documentation/topics
local codeTopics: { any } = {} -- Docs.addTopic
local sections: { [string]: { any } } = {} -- topic id -> extra sections
local directives: { [string]: any } = {}
local groups: { [string]: any } = {
	Tungsten = { Order = 0, Title = "Tungsten", Owner = "core" },
	Classes = { Order = 900, Title = "Classes", Owner = "core" },
}
Docs.CoreGroup = "Tungsten"

----------------------------------------------------------------------
-- Parsing
----------------------------------------------------------------------

local function trim(text: string): string
	return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function splitRow(line: string): { string }
	local cells = {}
	local inner = trim(line):gsub("^|", ""):gsub("|$", "")
	-- Allow \| inside cells.
	inner = inner:gsub("\\|", "\0")
	for cell in (inner .. "|"):gmatch("(.-)|") do
		table.insert(cells, (trim(cell):gsub("%z", "|")))
	end
	return cells
end

function Docs.parse(source: string): { any }
	local blocks = {}
	local paragraph = nil
	local list = nil
	local tableBlock = nil
	local code = nil

	local function flush()
		if paragraph then
			table.insert(blocks, { Kind = "paragraph", Text = table.concat(paragraph, " ") })
			paragraph = nil
		end
		if list then
			table.insert(blocks, { Kind = "list", Items = list })
			list = nil
		end
		if tableBlock then
			table.insert(blocks, tableBlock)
			tableBlock = nil
		end
	end

	source = source:gsub("\r\n", "\n"):gsub("\t", "    ")
	for line in (source .. "\n"):gmatch("(.-)\n") do
		if code then
			if trim(line):sub(1, 3) == "```" then
				table.insert(blocks, { Kind = "code", Text = table.concat(code, "\n") })
				code = nil
			else
				table.insert(code, line)
			end
			continue
		end
		local stripped = trim(line)
		if stripped:sub(1, 3) == "```" then
			flush()
			code = {}
		elseif stripped == "" then
			flush()
		elseif stripped:match("^#+%s") then
			flush()
			local hashes, text = stripped:match("^(#+)%s+(.*)$")
			table.insert(blocks, { Kind = "heading", Level = math.min(#hashes, 3), Text = text })
		elseif stripped:match("^%-%-%-+$") then
			flush()
			table.insert(blocks, { Kind = "rule" })
		elseif stripped:match("^{{[%w%-]+:?[^}]*}}$") then
			flush()
			table.insert(blocks, { Kind = "directive", Name = stripped:match("^{{(.-)}}$") })
		elseif stripped:sub(1, 1) == "|" then
			if paragraph or list then
				flush()
			end
			local cells = splitRow(stripped)
			local separator = true
			for _, cell in cells do
				if not cell:match("^:?%-+:?$") then
					separator = false
				end
			end
			if not separator then
				if not tableBlock then
					tableBlock = { Kind = "table", Header = cells, Rows = {} }
				else
					table.insert(tableBlock.Rows, cells)
				end
			end
		elseif stripped:match("^[%-%*]%s") then
			if paragraph or tableBlock then
				flush()
			end
			list = list or {}
			table.insert(list, stripped:sub(3))
		elseif stripped:sub(1, 1) == ">" then
			flush()
			local text = trim(stripped:sub(2))
			local last = blocks[#blocks]
			if last and last.Kind == "tip" then
				last.Text ..= " " .. text
			else
				table.insert(blocks, { Kind = "tip", Text = text })
			end
		else
			if list and line:match("^%s+") then
				-- Indented line continues the last bullet.
				list[#list] ..= " " .. stripped
			else
				if list or tableBlock then
					flush()
				end
				paragraph = paragraph or {}
				table.insert(paragraph, stripped)
			end
		end
	end
	if code then
		table.insert(blocks, { Kind = "code", Text = table.concat(code, "\n") })
	end
	flush()
	return blocks
end

-- Plain text of blocks (for search and "copy").
local function plainText(blocks): string
	local parts = {}
	for _, block in blocks do
		if block.Text then
			table.insert(parts, block.Text)
		elseif block.Items then
			for _, item in block.Items do
				table.insert(parts, "- " .. item)
			end
		elseif block.Header then
			table.insert(parts, table.concat(block.Header, " | "))
			for _, row in block.Rows do
				table.insert(parts, table.concat(row, " | "))
			end
		end
	end
	return (table.concat(parts, "\n"):gsub("`", ""):gsub("%*%*", ""))
end
Docs.plainText = plainText

local function changed()
	Docs.Changed:Fire()
end

local function titleOf(blocks, fallback: string): string
	if blocks[1] and blocks[1].Kind == "heading" and blocks[1].Level == 1 then
		return blocks[1].Text
	end
	return fallback
end

----------------------------------------------------------------------
-- Directives
----------------------------------------------------------------------

function Docs.addDirective(name: string, definition: { [string]: any })
	assert(type(name) == "string" and name:match("^[%w%-]+$"), "a directive needs a plain name")
	assert(type(definition) == "table" and (type(definition.Source) == "function" or type(definition.Blocks) == "function"), "a directive needs Source(arg, topic) or Blocks(arg, topic)")
	directives[name] = { Source = definition.Source, Blocks = definition.Blocks, Owner = definition.Owner or "core" }
	changed()
end

function Docs.removeDirective(name: string): boolean
	if directives[name] then
		directives[name] = nil
		changed()
		return true
	end
	return false
end

-- The blocks a directive stands for (or a note when it fails / is unknown).
local function expandDirective(block, topic): { any }
	local name, arg = block.Name:match("^([%w%-]+):(.*)$")
	name = name or block.Name
	local definition = directives[name]
	if not definition then
		return { { Kind = "tip", Text = ("(unknown block {{%s}})"):format(block.Name) } }
	end
	local ok, result
	if definition.Blocks then
		ok, result = pcall(definition.Blocks, arg, topic)
	else
		ok, result = pcall(definition.Source, arg, topic)
		if ok and type(result) == "string" then
			result = Docs.parse(result)
		end
	end
	if not ok or type(result) ~= "table" then
		local problem = if ok then "it returned no blocks" else tostring(result)
		T.Log.warn("docs", ("block {{%s}} failed: %s"):format(block.Name, problem))
		if definition.Owner ~= "core" then
			T.import("console/reporter").ownerFault(definition.Owner, ("documentation block {{%s}}"):format(block.Name), problem)
		end
		return { { Kind = "tip", Text = ("(the block {{%s}} could not be shown)"):format(block.Name) } }
	end
	return result
end

local function expand(blocks, topic): { any }
	local out = {}
	for _, block in blocks do
		if block.Kind == "directive" then
			for _, inner in expandDirective(block, topic) do
				if inner.Kind ~= "directive" then
					table.insert(out, inner)
				end
			end
		else
			table.insert(out, block)
		end
	end
	return out
end

----------------------------------------------------------------------
-- Topics
----------------------------------------------------------------------

local function sourceOf(definition): (string?, string?)
	if type(definition.Source) == "string" then
		return definition.Source, nil
	end
	if type(definition.File) == "string" then
		local ok, text = pcall(readfile, definition.File)
		if ok and type(text) == "string" then
			return text, nil
		end
		return nil, "could not read " .. definition.File
	end
	return nil, nil
end

local function makeTopic(definition)
	local source, problem = sourceOf(definition)
	local blocks = if source then Docs.parse(source) else {}
	if problem then
		blocks = { { Kind = "tip", Text = problem } }
	end
	local id = tostring(definition.Id):lower()
	return {
		Id = id,
		Title = definition.Title or titleOf(blocks, id),
		Order = tonumber(definition.Order) or 600,
		Group = definition.Group or Docs.CoreGroup,
		Owner = definition.Owner or "core",
		Icon = definition.Icon,
		Keywords = definition.Keywords,
		Build = definition.Build,
		Hidden = definition.Hidden == true,
		Source = source or "",
		RawBlocks = blocks,
	}
end

local function loadFiles()
	local list = {}
	local ok, entries = pcall(listfiles, DIR)
	if not ok or type(entries) ~= "table" then
		T.Log.warn("docs", "could not list " .. DIR)
		entries = {}
	end
	for _, entry in entries do
		local path = tostring(entry):gsub("\\", "/")
		local file = path:match("[^/]+$") or ""
		local number, id = file:match("^(%d+)_(.+)%.md$")
		if not id then
			id = file:match("^(.+)%.md$")
		end
		if id then
			local readOk, source = pcall(readfile, DIR .. "/" .. file)
			if readOk and type(source) == "string" then
				table.insert(list, makeTopic({ Id = id, Order = tonumber(number) or 500, Source = source }))
			else
				T.Log.warn("docs", "could not read " .. file)
			end
		end
	end
	fileTopics = list
	T.Log.info("docs", ("%d documentation topics from files"):format(#list))
end

-- A topic with its sections added and its directives filled in.
local function finish(raw)
	local topic = table.clone(raw)
	local blocks = table.clone(raw.RawBlocks)
	local extra = sections[raw.Id]
	local sources = { raw.Source }
	if extra then
		local list = table.clone(extra)
		table.sort(list, function(a, b)
			if a.Order ~= b.Order then
				return a.Order < b.Order
			end
			return a.Seq < b.Seq
		end)
		for _, section in list do
			if section.Title then
				table.insert(blocks, { Kind = "heading", Level = 2, Text = section.Title })
			end
			for _, block in section.Blocks do
				table.insert(blocks, block)
			end
			table.insert(sources, section.Source or "")
		end
	end
	topic.Blocks = expand(blocks, topic)
	topic.Text = plainText(topic.Blocks)
	topic.Source = table.concat(sources, "\n")
	topic.Sections = if extra then #extra else 0
	return topic
end

local function groupOrder(name: string): number
	local group = groups[name]
	return if group then group.Order else 100
end

function Docs.topics(includeHidden: boolean?): { any }
	if not fileTopics then
		loadFiles()
	end
	local list = {}
	for _, raw in fileTopics :: { any } do
		table.insert(list, finish(raw))
	end
	for _, raw in codeTopics do
		if includeHidden or not raw.Hidden then
			table.insert(list, finish(raw))
		end
	end
	table.sort(list, function(a, b)
		if a.Group ~= b.Group then
			local ga, gb = groupOrder(a.Group), groupOrder(b.Group)
			if ga ~= gb then
				return ga < gb
			end
			return a.Group < b.Group
		end
		if a.Order ~= b.Order then
			return a.Order < b.Order
		end
		return a.Title:lower() < b.Title:lower()
	end)
	return list
end

function Docs.reload()
	fileTopics = nil
	loadFiles()
	changed()
end

function Docs.get(id: string)
	id = tostring(id):lower()
	for _, topic in Docs.topics(true) do
		if topic.Id == id then
			return topic
		end
	end
	return nil
end

function Docs.find(name: string)
	name = trim(name):lower()
	if name == "" then
		return nil
	end
	local list = Docs.topics()
	for _, topic in list do
		if topic.Id == name or topic.Title:lower() == name then
			return topic
		end
	end
	for _, topic in list do
		if topic.Id:sub(1, #name) == name or topic.Title:lower():sub(1, #name) == name then
			return topic
		end
	end
	return nil
end

-- Topics matching search words (base/textfilter: several words, !not,
-- "exact", group:Explorer, id:commands).
function Docs.search(text: string): { any }
	local TextFilter = T.import("base/textfilter")
	local test = TextFilter.compile(text)
	local out = {}
	for _, topic in Docs.topics() do
		local keywords = if type(topic.Keywords) == "table" then table.concat(topic.Keywords, " ") else ""
		if test({ topic.Title, topic.Text, keywords }, { group = topic.Group, id = topic.Id, owner = topic.Owner }) then
			table.insert(out, topic)
		end
	end
	return out
end

function Docs.open(name: string | any): boolean
	local topic = if type(name) == "table" then name else Docs.find(name) or Docs.get(name)
	if not topic then
		return false
	end
	Docs.Pending = topic
	Docs.OpenRequested:Fire(topic)
	return true
end

function Docs.addTopic(definition: { [string]: any })
	assert(type(definition) == "table" and type(definition.Id) == "string" and definition.Id ~= "", "a topic needs an Id")
	assert(definition.Source ~= nil or definition.File ~= nil or definition.Build ~= nil, "a topic needs Source, File or Build")
	local id = definition.Id:lower()
	for index, topic in codeTopics do
		if topic.Id == id then
			table.remove(codeTopics, index)
			break
		end
	end
	local topic = makeTopic(definition)
	table.insert(codeTopics, topic)
	if topic.Group ~= Docs.CoreGroup and not groups[topic.Group] then
		groups[topic.Group] = { Order = 100, Title = topic.Group, Owner = topic.Owner }
	end
	changed()
	return topic
end
Docs.add = Docs.addTopic -- the earlier name

function Docs.removeTopic(id: string): boolean
	id = id:lower()
	for index, topic in codeTopics do
		if topic.Id == id then
			table.remove(codeTopics, index)
			changed()
			return true
		end
	end
	return false
end
Docs.remove = Docs.removeTopic

local sectionSeq = 0
function Docs.addSection(topicId: string, definition: { [string]: any })
	assert(type(topicId) == "string", "addSection needs a topic id")
	assert(type(definition) == "table", "a section needs a definition")
	local source, problem = sourceOf(definition)
	local blocks = if type(definition.Blocks) == "table" then definition.Blocks elseif source then Docs.parse(source) else {}
	if problem then
		blocks = { { Kind = "tip", Text = problem } }
	end
	local key = topicId:lower()
	sections[key] = sections[key] or {}
	local id = definition.Id or definition.Title or tostring(#sections[key] + 1)
	for index, section in sections[key] do
		if section.Id == id then
			table.remove(sections[key], index)
			break
		end
	end
	sectionSeq += 1
	table.insert(sections[key], {
		Id = id,
		Title = definition.Title,
		Order = tonumber(definition.Order) or 100,
		Owner = definition.Owner or "core",
		Blocks = blocks,
		Source = source,
		Seq = sectionSeq,
	})
	changed()
	return id
end

function Docs.removeSection(topicId: string, id: string): boolean
	local list = sections[topicId:lower()]
	if not list then
		return false
	end
	for index, section in list do
		if section.Id == id then
			table.remove(list, index)
			changed()
			return true
		end
	end
	return false
end

function Docs.addGroup(name: string, definition: { [string]: any }?)
	assert(type(name) == "string" and name ~= "", "a group needs a name")
	definition = definition or {}
	groups[name] = { Order = tonumber((definition :: any).Order) or 100, Title = (definition :: any).Title or name, Owner = (definition :: any).Owner or "core" }
	changed()
end

function Docs.groups(): { any }
	local list = {}
	for name, group in groups do
		table.insert(list, { Name = name, Order = group.Order, Title = group.Title, Owner = group.Owner })
	end
	table.sort(list, function(a, b)
		if a.Order ~= b.Order then
			return a.Order < b.Order
		end
		return a.Name < b.Name
	end)
	return list
end

function Docs.removeOwner(owner: string): number
	local count = 0
	for index = #codeTopics, 1, -1 do
		if codeTopics[index].Owner == owner then
			table.remove(codeTopics, index)
			count += 1
		end
	end
	for _, list in sections do
		for index = #list, 1, -1 do
			if list[index].Owner == owner then
				table.remove(list, index)
				count += 1
			end
		end
	end
	for name, definition in table.clone(directives) do
		if definition.Owner == owner then
			directives[name] = nil
			count += 1
		end
	end
	for name, group in table.clone(groups) do
		if group.Owner == owner and name ~= Docs.CoreGroup then
			groups[name] = nil
			count += 1
		end
	end
	if count > 0 then
		changed()
	end
	return count
end

----------------------------------------------------------------------
-- Built-in directives
----------------------------------------------------------------------

local function commandsModule()
	return T.Console and T.Console.Commands
end

local function aliasText(command): string
	if command.Aliases and #command.Aliases > 0 then
		local list = {}
		for _, alias in command.Aliases do
			table.insert(list, "`/" .. alias .. "`")
		end
		return " · also " .. table.concat(list, ", ")
	end
	return ""
end

local function escapeCell(text: string): string
	return (tostring(text):gsub("|", "\\|"))
end

local function commandRows(filter: (any) -> boolean): { any }
	local Commands = commandsModule()
	local rows = {}
	for _, command in (if Commands then Commands.list() else {}) do
		if not command.Hidden and filter(command) then
			local usage = command.Usage or ("/" .. command.Name)
			if command.Owner ~= "core" then
				usage = usage:gsub("^/", ":" .. command.Owner .. ".", 1)
			end
			table.insert(rows, {
				"`" .. escapeCell(usage) .. "`",
				escapeCell(command.Description or "") .. aliasText(command) .. (if command.Owner ~= "core" then " · from " .. command.Owner else ""),
			})
		end
	end
	return rows
end

local function tableBlock(header: { string }, rows: { any }, empty: string): { any }
	if #rows == 0 then
		return { { Kind = "tip", Text = empty } }
	end
	return { { Kind = "table", Header = header, Rows = rows } }
end

directives["commands"] = {
	Owner = "core",
	Blocks = function(group)
		group = tostring(group or "")
		local rows = commandRows(function(command)
			return group == "" or (command.Group or "Other"):lower() == group:lower()
		end)
		return tableBlock({ "Command", "What it does" }, rows, ("No %s commands."):format(group))
	end,
}

-- Groups that no {{commands:Group}} in the Commands topic lists.
directives["commands-other"] = {
	Owner = "core",
	Blocks = function(_, topic)
		local listed = {}
		for name in (topic and topic.Source or ""):gmatch("{{commands:([^}]+)}}") do
			listed[name:lower()] = true
		end
		local Commands = commandsModule()
		local byGroup, names = {}, {}
		for _, command in (if Commands then Commands.list() else {}) do
			local group = command.Group or "Other"
			if not listed[group:lower()] and not command.Hidden then
				if not byGroup[group] then
					byGroup[group] = true
					table.insert(names, group)
				end
			end
		end
		table.sort(names)
		local blocks = {}
		for _, group in names do
			table.insert(blocks, { Kind = "heading", Level = 2, Text = group })
			local rows = commandRows(function(command)
				return (command.Group or "Other") == group
			end)
			table.insert(blocks, { Kind = "table", Header = { "Command", "What it does" }, Rows = rows })
		end
		return blocks
	end,
}

directives["plugin-commands"] = {
	Owner = "core",
	Blocks = function()
		local rows = commandRows(function(command)
			return command.Owner ~= "core"
		end)
		return tableBlock({ "Command", "What it does" }, rows, "No plugin commands yet. Commands that plugins add show up here.")
	end,
}

directives["menus"] = {
	Owner = "core",
	Blocks = function()
		local Menus = T.import("base/ui/menus")
		local rows = {}
		for _, id in Menus.list() do
			local definition = Menus.get(id)
			table.insert(rows, {
				"`" .. id .. "`",
				escapeCell(tostring(definition and definition.Title or "")),
				if definition and definition.Locked then "fixed" else "may add",
			})
		end
		return tableBlock({ "Menu", "Opens on", "Plugins" }, rows, "No menus.")
	end,
}

directives["components"] = {
	Owner = "core",
	Blocks = function()
		local UI = T.import("base/ui/ui")
		local rows = {}
		for _, name in UI.list() do
			local info = UI.describe(name)
			local events = {}
			for _, event in info.Events do
				table.insert(events, event.Name)
			end
			local filters = {}
			for _, filter in info.Filters do
				table.insert(filters, filter.Name)
			end
			table.insert(rows, { "**" .. name .. "**", escapeCell(info.Description), table.concat(events, ", "), if #filters > 0 then table.concat(filters, ", ") else "—" })
		end
		return tableBlock({ "Component", "What it is", "Events", "Filters" }, rows, "No components.")
	end,
}

directives["filter-groups"] = {
	Owner = "core",
	Blocks = function()
		local ok, Filter = pcall(T.import, "base/explorer/filter")
		local rows = {}
		if ok then
			for _, group in Filter.groups() do
				table.insert(rows, { "`" .. group.Id .. "`", group.Text, if group.Classes then table.concat(group.Classes, ", ") else "(a test)" })
			end
		end
		return tableBlock({ "Group", "Shown as", "Classes (and subclasses)" }, rows, "No filter groups.")
	end,
}

directives["groups"] = {
	Owner = "core",
	Blocks = function()
		local rows = {}
		for _, group in Docs.groups() do
			local count = 0
			for _, topic in Docs.topics() do
				if topic.Group == group.Name then
					count += 1
				end
			end
			table.insert(rows, { group.Title, tostring(count), group.Owner })
		end
		return tableBlock({ "Group", "Topics", "From" }, rows, "No groups.")
	end,
}

----------------------------------------------------------------------
-- Class pages (Explorer › Load into the Documentation tab)
----------------------------------------------------------------------

-- A page for a class from the bundled data: base classes and properties.
function Docs.classTopic(className: string)
	local Api = T.import("base/explorer/api")
	local info = Api.class(className)
	if not info then
		return nil
	end
	local lines = { "# " .. className, "" }
	local chain = Api.superclasses(className)
	local tags = {}
	for _, key in { "Service", "NotCreatable", "Deprecated" } do
		if info[key] then
			table.insert(tags, key)
		end
	end
	table.insert(lines, ("Inherits from %s.%s"):format(
		if #chain > 0 then "`" .. table.concat(chain, "` › `") .. "`" else "nothing",
		if #tags > 0 then " · " .. table.concat(tags, ", ") else ""
	))
	table.insert(lines, "")
	local byCategory, categories = {}, {}
	for _, prop in Api.properties(className) do
		if not prop.Hidden and not prop.NotScriptable then
			if not byCategory[prop.Category] then
				byCategory[prop.Category] = {}
				table.insert(categories, prop.Category)
			end
			table.insert(byCategory[prop.Category], prop)
		end
	end
	table.sort(categories, function(a, b)
		local ra, rb = Api.categoryRank(a), Api.categoryRank(b)
		if ra ~= rb then
			return ra < rb
		end
		return a < b
	end)
	for _, category in categories do
		table.insert(lines, "## " .. category)
		table.insert(lines, "")
		table.insert(lines, "| Property | Type | Notes |")
		table.insert(lines, "|---|---|---|")
		for _, prop in byCategory[category] do
			local notes = {}
			if prop.ReadOnly then
				table.insert(notes, "read only")
			end
			if prop.Deprecated then
				table.insert(notes, "deprecated")
			end
			if prop.Class ~= className then
				table.insert(notes, "from " .. prop.Class)
			end
			table.insert(lines, ("| `%s` | %s | %s |"):format(prop.Name, prop.DataType or prop.Type, table.concat(notes, ", ")))
		end
		table.insert(lines, "")
	end
	local id = "class-" .. className:lower()
	return Docs.addTopic({
		Id = id,
		Title = className,
		Order = 0,
		Group = "Classes",
		Hidden = true,
		Source = table.concat(lines, "\n"),
		Owner = "core",
	}) and Docs.get(id)
end

T.Bin:Add(function()
	Docs.Changed:DisconnectAll()
	Docs.OpenRequested:DisconnectAll()
	table.clear(codeTopics)
	table.clear(sections)
	fileTopics = nil
end)

return Docs
