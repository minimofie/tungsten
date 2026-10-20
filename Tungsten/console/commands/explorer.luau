--[[
	Tungsten · console/commands/explorer
	Explorer commands: load, select, find, path, explorer, expand, collapse,
	props, setprop, attrs, filter, insert, move, decompile, save,
	clipboard, clearclipboard.

	A target can be a variable ($door, or a table of instances), a path
	(game.Workspace.Door, workspace.Map["Spawn 1"]) or, for /select, a
	search (the same words as the explorer's search bar).
]]

local T = ...
local Types = T.import("base/types")
local Search = T.import("base/explorer/search")

local LIST_LIMIT = 25

local function explorer(ctx)
	local Explorer = T.Explorer
	if not Explorer or not Explorer.Tree then
		ctx.fail("the explorer isn't running")
	end
	return Explorer
end

local function looksLikePath(text: string): boolean
	local head = text:match("^([%a_][%w_]*)")
	if not head then
		return false
	end
	if head == "game" or head == "workspace" then
		return true
	end
	-- "ReplicatedStorage.Remotes" etc.
	if text:find("[%.%[:]") then
		local ok, service = pcall(function()
			return game:FindService(head)
		end)
		return ok and service ~= nil
	end
	return false
end

-- Instances from a variable value (one Instance or a list of them).
local function instancesFrom(value: any): { Instance }?
	if typeof(value) == "Instance" then
		return { value }
	end
	if type(value) == "table" then
		local list = {}
		for _, item in value do
			if typeof(item) == "Instance" then
				table.insert(list, item)
			end
		end
		return list
	end
	return nil
end

-- "$x", "$x.Child", a path, or nothing (the explorer selection).
local function targets(ctx, raw: string): { Instance }
	raw = raw:gsub("^%s+", ""):gsub("%s+$", "")
	if raw == "" then
		local list = explorer(ctx).getSelection()
		if #list == 0 then
			ctx.fail("nothing is selected · give a $variable or a path")
		end
		return list
	end
	if raw:sub(1, 1) == "$" then
		local value = ctx.resolve(raw)
		local list = instancesFrom(value)
		if not list or #list == 0 then
			ctx.fail(("%s is %s, not an Instance"):format(raw, Types.tag(value)))
		end
		return list :: { Instance }
	end
	local obj, reason = Types.resolvePath(raw)
	if not obj then
		ctx.fail(reason or "not a path")
	end
	return { obj :: Instance }
end

local function showInstance(ctx, obj: Instance, indent: string?)
	local icon, color = Types.icon(obj)
	ctx.detail({
		{ Text = (indent or "") .. "  ", Color = "Text" },
		{ Text = Types.path(obj), Color = "Text" },
		{ Text = "  " .. (Types.classOf(obj) or "?"), Color = "TextMuted" },
	}, { Icon = icon, IconColor = color, IconAt = #(indent or "") })
end

local function selectionValue(list: { Instance }): any
	if #list == 0 then
		return nil
	end
	return if #list == 1 then list[1] else list
end

-- How a loaded item reads in the console.
local function describeLoaded(item: any): string
	local Loaded = T.Loaded or T.import("base/loaded")
	if Loaded.isTarget(item) then
		if item.Access then
			return (T.Access or T.import("base/access")).code(item.Access)
		end
		return if item.Origin then ("%s · %s"):format(item.Label, Types.path(item.Origin)) else item.Label
	end
	return Types.path(item)
end

local commands = {
	{
		Name = "load",
		Group = "Explorer",
		Usage = "/load <path | require(path).key | $var | none>",
		Description = "load something for every tab (like explorer › Load); no argument: the selection; none: unload",
		Run = function(ctx)
			local Loaded = T.Loaded or T.import("base/loaded")
			local raw = ctx.Raw:gsub("^%s+", ""):gsub("%s+$", "")
			if raw:lower() == "none" or raw:lower() == "clear" then
				Loaded.clear("you")
				ctx.success("nothing loaded")
				return nil
			end
			if raw == "" and #explorer(ctx).getSelection() == 0 then
				local item = Loaded.get()
				if item == nil then
					ctx.info("nothing is loaded · /load <path | $var>")
					return nil
				end
				local list = Loaded.list()
				ctx.info(("loaded: %s%s"):format(describeLoaded(item), if #list > 1 then (" (+%d)"):format(#list - 1) else ""))
				return Loaded.value()
			end
			if raw:sub(1, 1) == "$" then
				local value = ctx.resolve(raw)
				local list = instancesFrom(value)
				if not list or #list == 0 then
					if value == nil then
						ctx.fail(("%s is nil · nothing to load"):format(raw))
					end
					-- a value that isn't an Instance: loaded as a target
					Loaded.load({ Loaded.target(value, { Label = ("%s (%s)"):format(raw, typeof(value)) }) }, { By = "you" })
					ctx.success("loaded " .. raw)
					return value
				end
			end
			-- require(path).a.b / getsenv(path).x / debug.getupvalues(...)[n]
			local head = raw:match("^([%a_][%w_%.]*)%s*%(")
			if head == "require" or head == "getsenv" or head == "debug.getupvalues" then
				local Access = T.Access or T.import("base/access")
				local access, why = Access.parse(raw)
				if not access then
					ctx.fail(why or "not a path")
				end
				local ok, value = Access.resolve(access)
				if not ok then
					ctx.fail(tostring(value))
				end
				if value == nil then
					ctx.fail(Access.code(access) .. " is nil · nothing to load")
				end
				if typeof(value) == "Instance" then
					explorer(ctx).load({ value })
				else
					local crumbs = Access.crumbs(access)
					Loaded.load({ Loaded.target(value, { Access = access, Label = crumbs[#crumbs].Text }) }, { By = "you" })
				end
				ctx.success("loaded " .. Access.code(access))
				return value
			end
			local list = targets(ctx, raw)
			explorer(ctx).load(list)
			return selectionValue(list)
		end,
	},
	{
		Name = "select",
		Aliases = { "sel" },
		Group = "Explorer",
		Usage = "/select <path | $var | search | none>",
		Description = "select objects in the explorer ($sel holds them)",
		Run = function(ctx)
			local Explorer = explorer(ctx)
			local raw = ctx.Raw:gsub("^%s+", ""):gsub("%s+$", "")
			if raw == "" then
				local list = Explorer.getSelection()
				if #list == 0 then
					ctx.info("nothing is selected · /select <path | $var | search>")
					return nil
				end
				ctx.info(("%d selected"):format(#list))
				for index = 1, math.min(#list, LIST_LIMIT) do
					showInstance(ctx, list[index])
				end
				return selectionValue(list)
			end
			if raw:lower() == "none" or raw:lower() == "clear" then
				Explorer.clearSelection()
				ctx.success("selection cleared")
				return nil
			end
			local list
			if raw:sub(1, 1) == "$" or looksLikePath(raw) then
				list = targets(ctx, raw)
			else
				local found, problem, capped = Explorer.find(raw)
				if not found then
					ctx.fail(problem or "nothing to search for")
				end
				if #found == 0 then
					ctx.fail(("nothing matches \"%s\""):format(raw))
				end
				if capped then
					ctx.warn(("more than %d match · selected the first %d"):format(Search.MaxResults, #found))
				end
				list = found
			end
			local selected, missing = Explorer.select(list)
			if selected == 0 then
				ctx.fail("none of those are in the explorer (hidden or destroyed)")
			end
			if missing > 0 then
				ctx.warn(("%d of them aren't in the explorer"):format(missing))
			end
			local value = selectionValue(Explorer.getSelection())
			ctx.value("success", ("selected %d · $sel = "):format(selected), value)
			return value
		end,
		Complete = function(_, argIndex)
			return if argIndex == 1 then { "none", "$sel", "game.Workspace", "remotes", "scripts", "isa:" } else {}
		end,
	},
	{
		Name = "find",
		Aliases = { "search" },
		Group = "Explorer",
		Usage = "/find <search>",
		Description = "search the game; results show here and in the explorer",
		Run = function(ctx)
			local Explorer = explorer(ctx)
			local raw = ctx.Raw
			if raw:match("^%s*$") then
				ctx.usage()
			end
			local found, problem, capped = Explorer.find(raw)
			if not found then
				ctx.fail(problem or "nothing to search for")
			end
			Explorer.setSearch(raw)
			if #found == 0 then
				ctx.info(("nothing matches \"%s\""):format(raw))
				return found
			end
			ctx.info(("%s%d match%s for \"%s\"%s"):format(
				if capped then "over " else "",
				#found,
				if #found == 1 then "" else "es",
				raw,
				if #found > LIST_LIMIT then (" · first %d shown, the explorer has all"):format(LIST_LIMIT) else ""
			))
			for index = 1, math.min(#found, LIST_LIMIT) do
				showInstance(ctx, found[index])
			end
			return found
		end,
		Complete = function(_, argIndex)
			local words = {}
			for _, word in Search.FilterWords do
				table.insert(words, word)
			end
			return if argIndex >= 1 then words else {}
		end,
	},
	{
		Name = "path",
		Group = "Explorer",
		Usage = "/path [$var | path]",
		Description = "the path (as code) of an object or the selection",
		Run = function(ctx)
			local list = targets(ctx, ctx.Raw)
			local paths = {}
			for _, obj in list do
				local path = Types.path(obj)
				table.insert(paths, path)
				showInstance(ctx, obj)
			end
			return if #paths == 1 then paths[1] else paths
		end,
	},
	{
		Name = "explorer",
		Group = "Explorer",
		Usage = "/explorer [open | close | sort on | sort off | freeze [on | off]]",
		Description = "open or close the explorer, change its order, or freeze the tree (it stops changing)",
		Run = function(ctx)
			local Explorer = explorer(ctx)
			local word = (ctx.Args[1] or ""):lower()
			if word == "sort" then
				local value = (ctx.Args[2] or ""):lower()
				if value ~= "on" and value ~= "off" then
					ctx.usage()
				end
				T.Settings.set("ExplorerSort", value == "on")
				ctx.success(if value == "on" then "explorer order: services first, then names A-Z" else "explorer order: as the game lists them")
				return nil
			end
			if word == "freeze" or word == "unfreeze" then
				local value = (ctx.Args[2] or ""):lower()
				local on
				if word == "unfreeze" or value == "off" then
					on = false
				elseif value == "on" then
					on = true
				elseif value == "" then
					on = not Explorer.isFrozen()
				else
					ctx.usage()
				end
				if Explorer.isFrozen() == on then
					ctx.info(if on then "the explorer is already frozen" else "the explorer isn't frozen")
				else
					Explorer.setFrozen(on)
				end
				return on
			end
			local wanted
			if word == "open" or word == "show" then
				wanted = true
			elseif word == "close" or word == "hide" or word == "collapse" then
				wanted = false
			elseif word == "" or word == "toggle" then
				wanted = not Explorer.isOpen()
			else
				ctx.usage()
			end
			Explorer.setOpen(wanted)
			ctx.success(if wanted then "explorer open" else "explorer collapsed · the explorer button in the title bar opens it")
			return wanted
		end,
		Complete = function(_, argIndex)
			if argIndex == 1 then
				return { "open", "close", "sort", "freeze", "unfreeze" }
			elseif argIndex == 2 then
				return { "on", "off" }
			end
			return {}
		end,
	},
	{
		Name = "expand",
		Group = "Explorer",
		Usage = "/expand [$var | path] [all]",
		Description = "open objects in the explorer tree (all: every level)",
		Run = function(ctx)
			local Explorer = explorer(ctx)
			local raw = ctx.Raw
			local all = false
			if raw:lower():match("%sall%s*$") or raw:lower():match("^%s*all%s*$") then
				all = true
				raw = raw:gsub("%s*[Aa][Ll][Ll]%s*$", "")
			end
			local count = 0
			for _, obj in targets(ctx, raw) do
				count += Explorer.expand(obj, all)
			end
			ctx.success(("opened %d object%s%s"):format(count, if count == 1 then "" else "s", if all then " and everything below" else ""))
		end,
		Complete = function(_, argIndex)
			return if argIndex <= 2 then { "all", "$sel" } else {}
		end,
	},
	{
		Name = "collapse",
		Group = "Explorer",
		Usage = "/collapse [$var | path] [all]",
		Description = "close objects in the explorer tree",
		Run = function(ctx)
			local Explorer = explorer(ctx)
			local raw = ctx.Raw
			local all = false
			if raw:lower():match("%sall%s*$") or raw:lower():match("^%s*all%s*$") then
				all = true
				raw = raw:gsub("%s*[Aa][Ll][Ll]%s*$", "")
			end
			local count = 0
			for _, obj in targets(ctx, raw) do
				count += Explorer.collapse(obj, all)
			end
			ctx.success(("closed %d object%s"):format(count, if count == 1 then "" else "s"))
		end,
		Complete = function(_, argIndex)
			return if argIndex <= 2 then { "all", "$sel" } else {}
		end,
	},
}

----------------------------------------------------------------------
-- Properties
----------------------------------------------------------------------

-- "game.Workspace["My Part"] Size" -> "game.Workspace["My Part"]", "Size":
-- splits at the first space outside brackets and quotes.
local function splitTarget(raw: string): (string, string)
	raw = raw:gsub("^%s+", "")
	local depth, quote = 0, nil
	for index = 1, #raw do
		local c = raw:sub(index, index)
		if quote then
			if c == "\\" then
				-- skip the escaped character
			elseif c == quote then
				quote = nil
			end
		elseif c == '"' or c == "'" then
			quote = c
		elseif c == "[" or c == "(" then
			depth += 1
		elseif c == "]" or c == ")" then
			depth -= 1
		elseif c:match("%s") and depth <= 0 then
			return raw:sub(1, index - 1), (raw:sub(index + 1):gsub("^%s+", ""):gsub("%s+$", ""))
		end
	end
	return raw, ""
end

-- Targets for the property commands: a $variable or path first, or the
-- explorer selection when the first word is neither.
local function propertyTargets(ctx, raw: string): ({ Instance }, string)
	local first, rest = splitTarget(raw)
	if first ~= "" and (first:sub(1, 1) == "$" or looksLikePath(first)) then
		return targets(ctx, first), rest
	end
	return targets(ctx, ""), (raw:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function describeTargets(list: { Instance }): string
	if #list == 1 then
		return Types.path(list[1])
	end
	return ("%d objects"):format(#list)
end

local function valueSegments(Properties, entry)
	local prop = entry.Prop
	if not entry.Readable then
		return { { Text = "can't read", Color = "TextMuted" } }
	end
	if not entry.Same then
		return { { Text = "— (different values)", Color = "TextMuted" } }
	end
	return { { Text = Properties.display(entry.Value, prop), Color = if prop.ReadOnly then "TextDim" else "Text" } }
end

local commands2 = {
	{
		Name = "props",
		Aliases = { "properties" },
		Group = "Explorer",
		Usage = "/props [$var | path] [filter]",
		Description = "list properties (of the selection, a variable or a path)",
		Run = function(ctx)
			local Properties = T.import("base/explorer/properties")
			local list, filter = propertyTargets(ctx, ctx.Raw)
			local entries = Properties.collect(list, {
				ShowDeprecated = T.Settings.get("PropertiesDeprecated") == true,
				ShowHidden = T.Settings.get("PropertiesHidden") == true,
				Filter = filter,
			})
			if #entries == 0 then
				ctx.info(("%s has no properties%s"):format(describeTargets(list), if filter ~= "" then (" matching \"%s\""):format(filter) else ""))
				return nil
			end
			ctx.info(("%s · %d propert%s%s"):format(
				describeTargets(list),
				#entries,
				if #entries == 1 then "y" else "ies",
				if filter ~= "" then (" matching \"%s\""):format(filter) else ""
			))
			local result = {}
			local category = nil
			for _, entry in entries do
				if entry.Category ~= category then
					category = entry.Category
					ctx.detail({ { Text = category, Color = "TextMuted" } })
				end
				local prop = entry.Prop
				local segments = { { Text = "  " .. entry.Name .. "  ", Color = if prop.ReadOnly then "TextDim" else "Text" } }
				for _, segment in valueSegments(Properties, entry) do
					table.insert(segments, segment)
				end
				table.insert(segments, { Text = "  <" .. (prop.DataType or prop.Type) .. ">" .. (if prop.ReadOnly then " read only" else ""), Color = "TextMuted" })
				ctx.detail(segments)
				if entry.Readable and entry.Same then
					result[entry.Name] = entry.Value
				end
			end
			return result
		end,
		Complete = function(_, argIndex)
			return if argIndex == 1 then { "$sel", "game.Workspace" } else {}
		end,
	},
	{
		Name = "setprop",
		Group = "Explorer",
		Usage = "/setprop [$var | path] <Property | @attribute> <value>",
		Description = "set a property (or an attribute) on the selection, a variable or a path",
		Run = function(ctx)
			local Properties = T.import("base/explorer/properties")
			local Editors = T.import("base/explorer/editors")
			local list, rest = propertyTargets(ctx, ctx.Raw)
			local name, text = rest:match("^(%S+)%s*(.*)$")
			if not name then
				ctx.usage()
			end
			-- Attributes: @Name value (the value's type is guessed, or kept
			-- from the attribute it replaces).
			if name:sub(1, 1) == "@" then
				local attribute = name:sub(2)
				local current = list[1]:GetAttribute(attribute)
				local ok, value
				if text:match("^%s*$") or text == "nil" then
					ok, value = true, nil
				elseif current ~= nil and not text:match("^%$") then
					ok, value = Types.parse(text, Types.typeName(current))
				else
					ok, value = Types.parse(text)
				end
				if not ok then
					ctx.fail(tostring(value))
				end
				local changed, failures = Properties.setAttribute(list, attribute, value)
				if changed == 0 then
					ctx.fail(if failures[1] then tostring(failures[1].Reason) else "nothing changed")
				end
				if #failures > 0 then
					ctx.warn(("%d object%s refused it: %s"):format(#failures, if #failures == 1 then "" else "s", tostring(failures[1].Reason)))
				end
				ctx.value("success", ("@%s on %s = "):format(attribute, describeTargets(list)), value)
				return value
			end
			local prop = Properties.find(list, name)
			if not prop then
				ctx.fail(("%s has no property \"%s\"%s"):format(describeTargets(list), name, if #list > 1 then " (that all of them share)" else ""))
			end
			if prop.ReadOnly then
				ctx.fail(("%s is read only"):format(prop.Name))
			end
			if not prop.Editable and not (prop.Type and Editors.get(prop).Parse) then
				ctx.fail(("%s values (%s) can't be set from here"):format(prop.Name, prop.DataType or prop.Type))
			end
			local ok, value = Editors.parse(prop, text)
			if not ok then
				local reason, hint = tostring(value), Editors.hint(prop)
				ctx.fail(if reason:find(hint, 1, true) or hint:find(reason, 1, true) then reason else ("%s · %s"):format(reason, hint))
			end
			local changed, failures = Properties.set(list, prop, value)
			if changed == 0 then
				ctx.fail(("couldn't set %s: %s"):format(prop.Name, if failures[1] then tostring(failures[1].Reason) else "nothing changed"))
			end
			if #failures > 0 then
				ctx.warn(("%d object%s refused it: %s"):format(#failures, if #failures == 1 then "" else "s", tostring(failures[1].Reason)))
			end
			ctx.value("success", ("%s.%s = "):format(describeTargets(list), prop.Name), value)
			return value
		end,
		Complete = function(_, argIndex)
			if argIndex == 1 then
				return { "$sel", "game.Workspace" }
			end
			-- Property names of the selection.
			local Explorer = T.Explorer
			local primary = Explorer and Explorer.getPrimary and Explorer.getPrimary()
			if not primary then
				return {}
			end
			local names = {}
			for _, prop in T.import("base/explorer/api").propertiesOf(primary) do
				if not prop.ReadOnly and not prop.Deprecated and not prop.Hidden and not prop.NotScriptable then
					table.insert(names, prop.Name)
				end
			end
			return names
		end,
	},
	{
		Name = "attrs",
		Aliases = { "attributes" },
		Group = "Explorer",
		Usage = "/attrs [$var | path]",
		Description = "list attributes and tags (of the selection, a variable or a path)",
		Run = function(ctx)
			local Properties = T.import("base/explorer/properties")
			local list = propertyTargets(ctx, ctx.Raw)
			local attributes = Properties.attributes(list)
			local tags = Properties.tags(list)
			local where = describeTargets(list)
			if #attributes == 0 and #tags == 0 then
				ctx.info(("%s has no attributes or tags"):format(where))
				return {}
			end
			local result = {}
			if #attributes > 0 then
				ctx.info(("%s · %d attribute%s"):format(where, #attributes, if #attributes == 1 then "" else "s"))
				for _, entry in attributes do
					ctx.detail({
						{ Text = "  " .. entry.Name .. "  ", Color = "Text" },
						{ Text = if entry.Same then Properties.display(entry.Value) else "— (different values)", Color = if entry.Same then "Text" else "TextMuted" },
						{ Text = "  <" .. entry.Type .. ">", Color = "TextMuted" },
					})
					if entry.Same then
						result[entry.Name] = entry.Value
					end
				end
			end
			if #tags > 0 then
				ctx.info(("tags: %s"):format(table.concat(tags, ", ")))
			end
			return result
		end,
		Complete = function(_, argIndex)
			return if argIndex == 1 then { "$sel", "game.Workspace" } else {}
		end,
	},
}
table.insert(commands2, {
	Name = "filter",
	Group = "Explorer",
	Usage = "/filter [show <group | Class> | hide <Class> | unhide <Class> | clear | open | groups]",
	Description = "what the explorer (and its searches) show: only some groups or classes, or hide classes",
	Run = function(ctx)
		local Explorer = explorer(ctx)
		local Filter = Explorer.Filter
		local word = (ctx.Args[1] or ""):lower()
		local rest = {}
		for index = 2, #ctx.Args do
			table.insert(rest, ctx.Args[index])
		end
		if word == "" then
			if not Filter.active() then
				ctx.info("no filter · /filter show parts, /filter hide Camera, /filter groups")
			else
				ctx.info("filter: " .. Filter.describe())
			end
			return Filter.get()
		elseif word == "clear" or word == "off" then
			Filter.clear()
			ctx.success("filter cleared · the explorer shows everything")
			return nil
		elseif word == "open" then
			if not Explorer.isOpen() then
				Explorer.setOpen(true)
			end
			Explorer.openFilter()
			return nil
		elseif word == "groups" then
			for _, group in Filter.groups() do
				ctx.detail({
					{ Text = ("  %-12s"):format(group.Id), Color = "Accent" },
					{ Text = group.Text .. (if group.Classes then " · " .. table.concat(group.Classes, ", ") else ""), Color = "TextDim" },
				})
			end
			return nil
		elseif word == "show" or word == "hide" or word == "unhide" or word == "unshow" then
			if #rest == 0 then
				ctx.usage()
			end
			for _, name in rest do
				local group = Filter.findGroup(name)
				if word == "show" and group then
					Filter.toggleGroup(group.Id, true)
				elseif word == "unshow" and group then
					Filter.toggleGroup(group.Id, false)
				else
					local className = T.import("base/explorer/api").isKnown(name) and name or nil
					if not className then
						-- any case: "part" -> "Part"
						for _, known in T.import("base/data/classes").list() do
							if known:lower() == name:lower() then
								className = known
								break
							end
						end
					end
					if not className then
						ctx.fail(("\"%s\" is not a group or a class · /filter groups lists the groups"):format(name))
					end
					if word == "show" then
						Filter.showClass(className, true)
					elseif word == "unshow" then
						Filter.showClass(className, false)
					elseif word == "hide" then
						Filter.hideClass(className, true)
					else
						Filter.hideClass(className, false)
					end
				end
			end
			ctx.success(if Filter.active() then "filter: " .. Filter.describe() else "no filter")
			return Filter.get()
		end
		ctx.usage()
		return nil
	end,
	Complete = function(_, argIndex)
		if argIndex == 1 then
			return { "show", "hide", "unhide", "unshow", "clear", "open", "groups" }
		end
		local list = {}
		local Explorer = T.Explorer
		if Explorer and Explorer.Filter then
			for _, group in Explorer.Filter.groups() do
				table.insert(list, group.Id)
			end
		end
		return list
	end,
})
table.insert(commands2, {
	Name = "insert",
	Aliases = { "new" },
	Group = "Explorer",
	Usage = "/insert <Class> [$var | path]",
	Description = "make a new object inside the selection (or a variable or a path), like Object › Insert",
	Run = function(ctx)
		local Explorer = explorer(ctx)
		local className, rest = ctx.Raw:match("^%s*([%w_]+)%s*(.-)%s*$")
		if not className then
			ctx.fail("give a class name · /insert Part")
		end
		local Insert = Explorer.Insert
		if not Insert.canCreate(className) then
			local Api = T.import("base/explorer/api")
			ctx.fail(if Api.isKnown(className) then ("%s can't be made with Instance.new"):format(className) else ("no class called %s"):format(className))
		end
		local parents = targets(ctx, rest or "")
		local created = Explorer.insert(className, parents)
		return if #created == 1 then created[1] elseif #created > 1 then created else nil
	end,
	Complete = function(_, argIndex)
		if argIndex == 1 then
			local Explorer = T.Explorer
			return if Explorer and Explorer.Insert then Explorer.Insert.classes() else {}
		end
		return { "$sel", "game.Workspace" }
	end,
})
table.insert(commands2, {
	Name = "move",
	Aliases = { "reparent" },
	Group = "Explorer",
	Usage = "/move <into: $var | path> [what: $var | path]",
	Description = "set the Parent of the selection (or a variable or a path) to another object, like dragging in the explorer",
	Run = function(ctx)
		local Explorer = explorer(ctx)
		local first, rest = splitTarget(ctx.Raw)
		if first == "" then
			ctx.fail("say where to · /move game.Workspace.Map")
		end
		local into = targets(ctx, first)
		if #into ~= 1 then
			ctx.fail("move into one object at a time")
		end
		local list = targets(ctx, rest or "")
		local moved = Explorer.moveInto(list, into[1])
		if #moved == 0 then
			local reason = if #list == 1 then Explorer.cannotMove(list[1], into[1]) else nil
			ctx.warn(reason or "nothing moved")
		end
		return moved
	end,
	Complete = function()
		return { "$sel", "game.Workspace" }
	end,
})
-- "$x file" / "path file" / "" (the selection) -> targets, file
local function targetsAndFile(ctx): ({ Instance }, string?)
	local first, rest = splitTarget(ctx.Raw)
	if first ~= "" and (first:sub(1, 1) == "$" or looksLikePath(first)) then
		return targets(ctx, first), (if rest ~= "" then rest else nil)
	end
	return targets(ctx, ""), (if first ~= "" then ctx.Raw:gsub("^%s+", ""):gsub("%s+$", "") else nil)
end

local function fileArg(file: string?, extension: string): string?
	if not file then
		return nil
	end
	file = file:gsub('^"(.*)"$', "%1")
	if not file:find("/", 1, true) then
		file = T.Root .. "/saved/" .. file
	end
	if not file:match("%.[%w]+$") then
		file ..= extension
	end
	return file
end

table.insert(commands2, {
	Name = "decompile",
	Group = "Explorer",
	Usage = "/decompile [$var | path] [file]",
	Description = "decompile scripts (the selection, a variable or a path) into .lua files in Tungsten/saved",
	Run = function(ctx)
		local Actions = T.import("base/explorer/actions")
		local list, file = targetsAndFile(ctx)
		local scripts = {}
		for _, obj in list do
			if Actions.isScript(obj) then
				table.insert(scripts, obj)
			end
		end
		if #scripts == 0 then
			ctx.fail("nothing to decompile · select a script or give $var / a path")
		end
		local saved = {}
		for index, script in scripts do
			local path = Actions.saveScript(script, if index == 1 then fileArg(file, ".lua") else nil)
			if path then
				table.insert(saved, path)
			end
		end
		return if #saved == 1 then saved[1] else saved
	end,
	Complete = function(_, argIndex)
		return if argIndex == 1 then { "$sel" } else {}
	end,
})
table.insert(commands2, {
	Name = "save",
	Aliases = { "saveinstance" },
	Group = "Explorer",
	Usage = "/save [$var | path] [file]",
	Description = "save objects (the selection, a variable or a path) to a .rbxm file in Tungsten/saved",
	Run = function(ctx)
		local Actions = T.import("base/explorer/actions")
		local list, file = targetsAndFile(ctx)
		local path = Actions.saveToFile(list, fileArg(file, ".rbxm"))
		if not path then
			ctx.fail("couldn't save · see the line above")
		end
		return path
	end,
	Complete = function(_, argIndex)
		return if argIndex == 1 then { "$sel", "game.Workspace" } else {}
	end,
})
-- The explorer's clipboard (Cut / Copy / Paste Into). Not the system
-- clipboard: that one is /copy.
local function clearClipboard(ctx)
	local Actions = T.import("base/explorer/actions")
	local mode = Actions.Clipboard.Mode
	local had = Actions.clipboardItems()
	Actions.clearClipboard(true)
	if mode == nil then
		ctx.info("the clipboard is already empty")
	elseif #had == 0 then
		ctx.success("clipboard cleared")
	else
		ctx.success(("clipboard cleared · %s no longer %s"):format(
			if #had == 1 then had[1].Name else #had .. " objects",
			if mode == "cut" then "cut (it stays where it is)" else "copied"
		))
	end
	return #had
end

local function showClipboard(ctx)
	local Actions = T.import("base/explorer/actions")
	local summary = Actions.clipboardSummary()
	ctx.info(summary.Heading)
	for _, line in summary.Lines do
		ctx.detail(line)
	end
	-- the objects become $last
	local items = summary.Items
	if #items == 0 then
		return nil
	end
	return if #items == 1 then items[1] else items
end

table.insert(commands2, {
	Name = "clipboard",
	Aliases = { "clip" },
	Group = "Explorer",
	Usage = "/clipboard [clear | cut [$var | path] | copy [$var | path] | paste [into]]",
	Description = "show the explorer's clipboard (what Cut / Copy hold for Paste Into), or clear, cut, copy and paste with it",
	Run = function(ctx)
		local Actions = T.import("base/explorer/actions")
		local action, rest = splitTarget(ctx.Raw)
		action = action:lower()
		if action == "" or action == "show" or action == "list" then
			return showClipboard(ctx)
		elseif action == "clear" then
			return clearClipboard(ctx)
		elseif action == "cut" then
			Actions.cut(targets(ctx, rest))
			return showClipboard(ctx)
		elseif action == "copy" then
			Actions.copy(targets(ctx, rest))
			return showClipboard(ctx)
		elseif action == "paste" then
			if not Actions.hasClipboard() then
				ctx.fail(if Actions.Clipboard.Mode then "nothing to paste · what was on the clipboard has been deleted" else "nothing to paste · the clipboard is empty")
			end
			local pasted = Actions.pasteInto(targets(ctx, rest))
			if #pasted == 0 then
				ctx.fail("nothing was pasted · see the line above")
			end
			return if #pasted == 1 then pasted[1] else pasted
		end
		ctx.usage()
	end,
	Complete = function(_, argIndex)
		if argIndex == 1 then
			return { "clear", "cut", "copy", "paste" }
		end
		return { "$sel", "game.Workspace" }
	end,
})
table.insert(commands2, {
	Name = "clearclipboard",
	Aliases = { "clearclip" },
	Group = "Explorer",
	Usage = "/clearclipboard",
	Description = "empty the explorer's clipboard (cut objects stay where they are)",
	Run = function(ctx)
		return clearClipboard(ctx)
	end,
})
for _, command in commands2 do
	table.insert(commands, command)
end

return commands
