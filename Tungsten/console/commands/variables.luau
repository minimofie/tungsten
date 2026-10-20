--[[
	Tungsten · console/commands/variables
	vars, set, text, setas, cast, get, unset, rename, dup, swap, inc, dec,
	push, pop, len, keys, isa, call, export, watch, unwatch.

		/set a = 5            value is Luau: 5, "text", $b, workspace.Baseplate
		/text name hi there   a text value without quotes
		/get a                5 <number>
		/vars                 every variable with its type
		/unset a b            remove (also: /unset *)
]]

local T = ...
local Variables = T.import("base/variables")
local Types = T.import("base/types")

-- Watched variable names (this session).
local watched: { [string]: boolean } = {}
T.Bin:Add(Variables.Changed:Connect(function(name, value, _old, removed)
	if not watched[name] then
		return
	end
	local Console = T.Console
	if not Console then
		return
	end
	if removed then
		Console.write("var", { { Text = "$" .. name, Color = "Text" }, { Text = " removed", Color = "TextMuted" } })
	else
		local source = Variables.source(name)
		local segments, opts = Console.valueSegments("$" .. name .. " = ", value)
		if source and source ~= "console" then
			table.insert(segments, { Text = "  · " .. source, Color = "TextMuted" })
		end
		Console.write("var", segments, opts)
	end
end))

-- Gets a variable or fails the command.
local function need(ctx, word: string?): (string, any)
	local name = word and word:gsub("^%$", "")
	if not name or name == "" then
		ctx.usage()
	end
	local value, exists = Variables.get(name :: string)
	if not exists then
		ctx.fail(("no variable $%s · /vars lists them"):format(name))
	end
	return name :: string, value
end

local function put(ctx, name: string, value: any)
	local isNew = not Variables.has(name)
	local ok, reason = Variables.set(name, value, { Source = "console" })
	if not ok then
		ctx.fail(reason :: string)
	end
	if isNew then
		ctx.Console.shadowWarning(name)
	end
end

local function shallowCopy(value: any): any
	if type(value) == "table" then
		return table.clone(value)
	end
	return value
end

local function deepCopy(value: any, seen): any
	if type(value) ~= "table" then
		return value
	end
	seen = seen or {}
	if seen[value] then
		return seen[value]
	end
	local copy = {}
	seen[value] = copy
	for key, item in value do
		copy[deepCopy(key, seen)] = deepCopy(item, seen)
	end
	return copy
end

local function variableNames(): { string }
	local names = {}
	for _, entry in Variables.list() do
		if not entry.Reserved then
			table.insert(names, entry.Name)
		end
	end
	return names
end

local function plainName(word: string?): string?
	if word == nil then
		return nil
	end
	return (word:gsub("^%$", ""))
end

-- "· deleted (frozen)" style tags for a value while the explorer is frozen.
local FROZEN_ORDER = { "deleted", "inside_deleted", "moved", "inside_moved" }
local function frozenTags(value: any): { any }
	local state = Variables.frozenState(value)
	if state == nil then
		return {}
	end
	local Explorer = T.Explorer
	local words, colors = Explorer.FrozenWords, Explorer.FrozenColors
	if type(state) == "string" then
		return { { Text = ("  · %s (frozen)"):format(words[state]), Color = colors[state] } }
	end
	local tags = {}
	for _, key in FROZEN_ORDER do
		local count = state[key]
		if count then
			table.insert(tags, { Text = ("  · %d %s (frozen)"):format(count, words[key]), Color = colors[key] })
		end
	end
	return tags
end

return {
	{
		Name = "vars",
		Aliases = { "variables" },
		Group = "Variables",
		Usage = "/vars [filter]",
		Description = "list variables with their types",
		Run = function(ctx)
			local filter = ctx.Args[1] and plainName(ctx.Args[1]):lower()
			local list = {}
			local width = 0
			for _, entry in Variables.list() do
				-- The filter matches names and types ("/vars number", "/vars Part").
				if filter == nil or entry.Name:lower():find(filter, 1, true) or Types.tag(entry.Value):lower():find(filter, 1, true) then
					table.insert(list, entry)
					width = math.max(width, #entry.Name)
				end
			end
			if #list == 0 then
				if filter then
					ctx.info(("no variables match \"%s\""):format(filter))
				else
					ctx.info("no variables yet · /set name = value  or  > name = value")
				end
				return
			end
			width = math.min(width + 3, 24)
			for _, entry in list do
				local label = entry.Name
				if #label < width then
					label ..= string.rep(" ", width - #label)
				else
					label ..= "  "
				end
				local segments, opts = ctx.Console.valueSegments(nil, entry.Value)
				table.insert(segments, 1, { Text = label, Color = if entry.Reserved then "Accent" else "Text" })
				if opts.IconAt then
					opts.IconAt += #label
				end
				if not Variables.isUser(entry.Source) then
					-- a plugin's: it alone (and you) may change it
					table.insert(segments, { Text = "  · owned by " .. entry.Source, Color = "TextMuted" })
				elseif entry.Source ~= "console" then
					table.insert(segments, { Text = "  · " .. entry.Source, Color = "TextMuted" })
				end
				-- explorer frozen: what happened to the object(s) since
				for _, tag in frozenTags(entry.Value) do
					table.insert(segments, tag)
				end
				ctx.detail(segments, opts)
			end
		end,
		Complete = function(_, argIndex)
			return if argIndex == 1 then Variables.names() else {}
		end,
	},
	{
		Name = "set",
		Aliases = { "let" },
		Group = "Variables",
		Usage = "/set <name> = <value>",
		Description = "set a variable (the value is Luau)",
		Run = function(ctx)
			local name, expression = ctx.Raw:match("^%$?([%a_][%w_]*)%s*=%s*(.-)%s*$")
			if not name then
				name, expression = ctx.Raw:match("^%$?([%a_][%w_]*)%s+(.-)%s*$")
			end
			if not name or expression == "" then
				ctx.usage()
			end
			local ok, reason = Variables.validName(name)
			if not ok then
				ctx.fail(reason :: string)
			end
			if Variables.isReserved(name) then
				ctx.fail(("$%s is reserved"):format(name))
			end
			local value = ctx.eval(expression)
			if value == nil then
				ctx.fail(("the value is nil · put text in quotes (\"%s\"), or /unset %s"):format(expression, name))
			end
			local isNew = not Variables.has(name)
			local set, problem = Variables.set(name, value, { Source = "console" })
			if not set then
				ctx.fail(problem :: string)
			end
			ctx.value("success", name .. " = ", value)
			if isNew then
				ctx.Console.shadowWarning(name)
			end
			return value
		end,
		Complete = function(_, argIndex)
			return if argIndex == 1 then variableNames() else {}
		end,
	},
	{
		Name = "get",
		Group = "Variables",
		Usage = "/get <name>",
		Description = "show a variable's value and type",
		Run = function(ctx)
			local name = plainName(ctx.Args[1])
			if not name or name == "" then
				ctx.usage()
			end
			local value, exists = Variables.get(name)
			if not exists then
				ctx.fail(("no variable $%s · /vars lists them"):format(name))
			end
			if type(value) == "table" and next(value) ~= nil then
				ctx.success(("%s  %s"):format(Types.short(value, 80), Types.tag(value)))
				for _, line in Types.pretty(value) do
					ctx.detail(line)
				end
			else
				ctx.value("success", nil, value)
				if typeof(value) == "Instance" then
					ctx.detail({ { Text = Types.path(value), Color = "TextDim" } })
				end
			end
			return value
		end,
		Complete = function(_, argIndex)
			return if argIndex == 1 then Variables.names() else {}
		end,
	},
	{
		Name = "clearvars",
		Aliases = { "resetvars", "clearvariables" },
		Group = "Variables",
		Usage = "/clearvars [source]",
		Description = "remove every variable ($sel and other reserved names stay); a source (console, explorer, a plugin id) removes only its variables",
		Run = function(ctx)
			local source = ctx.Args[1]
			local count = Variables.clear(source)
			if count == 0 then
				ctx.info(if source then ("no variables from %s"):format(source) else "there were no variables")
			else
				ctx.success(("removed %d variable%s%s"):format(count, if count == 1 then "" else "s", if source then " from " .. source else ""))
			end
			return count
		end,
		Complete = function(_, argIndex)
			return if argIndex == 1 then { "console", "explorer" } else {}
		end,
	},
	{
		Name = "unset",
		Aliases = { "del" },
		Group = "Variables",
		Usage = "/unset <name ...> | *",
		Description = "remove variables",
		Run = function(ctx)
			if #ctx.Args == 0 then
				ctx.usage()
			end
			if ctx.Args[1] == "*" then
				local count = Variables.clear()
				ctx.success(("removed %d variable%s"):format(count, if count == 1 then "" else "s"))
				return
			end
			local removed = {}
			for _, word in ctx.Args do
				local name = plainName(word) :: string
				local ok, reason = Variables.unset(name)
				if ok then
					table.insert(removed, "$" .. name)
				else
					ctx.warn(reason)
				end
			end
			if #removed > 0 then
				ctx.success("removed " .. table.concat(removed, ", "))
			end
		end,
		Complete = function()
			return variableNames()
		end,
	},
	{
		Name = "text",
		Aliases = { "setstr" },
		Group = "Variables",
		Usage = "/text <name> <words…>",
		Description = "set a text variable without quotes ($name is replaced)",
		Run = function(ctx)
			local name, rest = ctx.Raw:match("^%$?([%a_][%w_]*)%s+(.-)%s*$")
			if not name then
				name = ctx.Raw:match("^%$?([%a_][%w_]*)%s*$")
				rest = ""
			end
			if not name then
				ctx.usage()
			end
			local value = ctx.interpolate(rest :: string)
			put(ctx, name :: string, value)
			ctx.value("success", name .. " = ", value)
			return value
		end,
		Complete = function(_, argIndex)
			return if argIndex == 1 then variableNames() else {}
		end,
	},
	{
		Name = "rename",
		Aliases = { "mv" },
		Group = "Variables",
		Usage = "/rename <name> <new name>",
		Description = "give a variable a new name",
		Run = function(ctx)
			local name, value = need(ctx, ctx.Args[1])
			local target = ctx.Args[2] and ctx.Args[2]:gsub("^%$", "")
			if not target or target == "" then
				ctx.usage()
			end
			if Variables.has(target :: string) then
				ctx.fail(("$%s already exists · /unset it first"):format(target))
			end
			local source = Variables.source(name)
			local Undo = T.import("base/undo")
			local restore = Undo.rememberVariables({ name, target :: string })
			local ok, reason = Undo.quiet(function()
				return Variables.set(target :: string, value, { Source = source or "console" })
			end)
			if not ok then
				ctx.fail(reason :: string)
			end
			Undo.quiet(function()
				Variables.unset(name)
			end)
			Undo.record({ Text = ("rename $%s to $%s"):format(name, target), Undo = restore })
			ctx.success(("$%s is now $%s"):format(name, target))
		end,
		Complete = function(_, argIndex)
			return if argIndex == 1 then variableNames() else {}
		end,
	},
	{
		Name = "dup",
		Aliases = { "cp" },
		Group = "Variables",
		Usage = "/dup <name> <new name> [deep]",
		Description = "copy a variable (tables: a copy, deep copies nested tables)",
		Run = function(ctx)
			local name, value = need(ctx, ctx.Args[1])
			local target = ctx.Args[2] and ctx.Args[2]:gsub("^%$", "")
			if not target or target == "" then
				ctx.usage()
			end
			local deep = (ctx.Args[3] or ""):lower() == "deep"
			local copy = if deep then deepCopy(value) else shallowCopy(value)
			put(ctx, target :: string, copy)
			ctx.value("success", target .. " = ", copy)
			if type(value) == "table" then
				ctx.detail({ { Text = if deep then "deep copy of $" .. name else "copy of $" .. name .. " (nested tables shared)", Color = "TextMuted" } })
			end
			return copy
		end,
		Complete = function(_, argIndex)
			return if argIndex == 1 then variableNames() elseif argIndex == 3 then { "deep" } else {}
		end,
	},
	{
		Name = "swap",
		Group = "Variables",
		Usage = "/swap <name> <name>",
		Description = "swap two variables' values",
		Run = function(ctx)
			local a, va = need(ctx, ctx.Args[1])
			local b, vb = need(ctx, ctx.Args[2])
			put(ctx, a, vb)
			put(ctx, b, va)
			ctx.success(("swapped $%s and $%s"):format(a, b))
		end,
		Complete = function()
			return variableNames()
		end,
	},
	{
		Name = "inc",
		Group = "Variables",
		Usage = "/inc <name> [amount]",
		Description = "add to a number variable (starts at 0)",
		Run = function(ctx)
			local name = ctx.Args[1] and ctx.Args[1]:gsub("^%$", "")
			if not name or name == "" then
				ctx.usage()
			end
			local amount = tonumber(ctx.resolve(ctx.Args[2])) or (if ctx.Args[2] then nil else 1)
			if amount == nil then
				ctx.fail("the amount must be a number")
			end
			local value, exists = Variables.get(name :: string)
			if exists and type(value) ~= "number" then
				ctx.fail(("$%s is %s, not a number"):format(name, Types.tag(value)))
			end
			local result = (if exists then value else 0) + amount
			put(ctx, name :: string, result)
			ctx.value("success", name .. " = ", result)
			return result
		end,
		Complete = function(_, argIndex)
			return if argIndex == 1 then variableNames() else {}
		end,
	},
	{
		Name = "dec",
		Group = "Variables",
		Usage = "/dec <name> [amount]",
		Description = "subtract from a number variable",
		Run = function(ctx)
			local name = ctx.Args[1] and ctx.Args[1]:gsub("^%$", "")
			if not name or name == "" then
				ctx.usage()
			end
			local amount = tonumber(ctx.resolve(ctx.Args[2])) or (if ctx.Args[2] then nil else 1)
			if amount == nil then
				ctx.fail("the amount must be a number")
			end
			local value, exists = Variables.get(name :: string)
			if exists and type(value) ~= "number" then
				ctx.fail(("$%s is %s, not a number"):format(name, Types.tag(value)))
			end
			local result = (if exists then value else 0) - amount
			put(ctx, name :: string, result)
			ctx.value("success", name .. " = ", result)
			return result
		end,
		Complete = function(_, argIndex)
			return if argIndex == 1 then variableNames() else {}
		end,
	},
	{
		Name = "push",
		Aliases = { "append" },
		Group = "Variables",
		Usage = "/push <name> <value>",
		Description = "add a value to the end of a table variable (made if missing)",
		Run = function(ctx)
			local name, expression = ctx.Raw:match("^%$?([%a_][%w_]*)%s+(.-)%s*$")
			if not name or expression == "" then
				ctx.usage()
			end
			local item = ctx.eval(expression :: string)
			if item == nil then
				ctx.fail("the value is nil · put text in quotes")
			end
			local list, exists = Variables.get(name :: string)
			if exists and type(list) ~= "table" then
				ctx.fail(("$%s is %s, not a table"):format(name, Types.tag(list)))
			end
			if not exists then
				list = {}
				put(ctx, name :: string, list)
			end
			table.insert(list, item)
			ctx.value("success", ("%s[%d] = "):format(name, #list), item)
			return list
		end,
		Complete = function(_, argIndex)
			return if argIndex == 1 then variableNames() else {}
		end,
	},
	{
		Name = "pop",
		Group = "Variables",
		Usage = "/pop <name>",
		Description = "remove and show the last value of a table variable",
		Run = function(ctx)
			local name, list = need(ctx, ctx.Args[1])
			if type(list) ~= "table" then
				ctx.fail(("$%s is %s, not a table"):format(name, Types.tag(list)))
			end
			if #list == 0 then
				ctx.fail(("$%s is empty"):format(name))
			end
			local item = table.remove(list)
			ctx.value("success", ("%s[%d] was "):format(name, #list + 1), item)
			return item
		end,
		Complete = function(_, argIndex)
			return if argIndex == 1 then variableNames() else {}
		end,
	},
	{
		Name = "len",
		Aliases = { "count" },
		Group = "Variables",
		Usage = "/len <name>",
		Description = "length of text, size of a table, children of an Instance",
		Run = function(ctx)
			local name, value = need(ctx, ctx.Args[1])
			local length, what
			if type(value) == "string" then
				length, what = #value, "characters"
			elseif type(value) == "table" then
				local total = 0
				for _ in value do
					total += 1
				end
				length, what = total, ("entries (%d in order)"):format(#value)
			elseif typeof(value) == "Instance" then
				local ok, children = pcall(function()
					return value:GetChildren()
				end)
				length, what = if ok then #children else 0, "children"
			else
				ctx.fail(("$%s is %s and has no length"):format(name, Types.tag(value)))
			end
			ctx.success(("$%s · %d %s"):format(name, length, what))
			return length
		end,
		Complete = function(_, argIndex)
			return if argIndex == 1 then variableNames() else {}
		end,
	},
	{
		Name = "keys",
		Aliases = { "children" },
		Group = "Variables",
		Usage = "/keys <name>",
		Description = "a table's keys or an Instance's children",
		Run = function(ctx)
			local name, value = need(ctx, ctx.Args[1])
			local rows = {}
			if type(value) == "table" then
				for key, item in value do
					table.insert(rows, { Key = key, Value = item })
				end
				table.sort(rows, function(a, b)
					return tostring(a.Key) < tostring(b.Key)
				end)
			elseif typeof(value) == "Instance" then
				local ok, children = pcall(function()
					return value:GetChildren()
				end)
				for _, child in if ok then children else {} do
					table.insert(rows, { Key = Types.short(child), Value = child })
				end
			else
				ctx.fail(("$%s is %s and has no keys"):format(name, Types.tag(value)))
			end
			ctx.info(("$%s · %d %s"):format(name, #rows, if typeof(value) == "Instance" then "children" else "keys"))
			for index, row in rows do
				if index > 200 then
					ctx.detail(("… %d more"):format(#rows - 200))
					break
				end
				local label = (if type(row.Key) == "string" then row.Key else "[" .. Types.short(row.Key) .. "]") .. "  "
				local segments, opts = ctx.Console.valueSegments(label, row.Value)
				ctx.detail(segments, opts)
			end
		end,
		Complete = function(_, argIndex)
			return if argIndex == 1 then variableNames() else {}
		end,
	},
	{
		Name = "isa",
		Group = "Variables",
		Usage = "/isa <name> <ClassName | type>",
		Description = "check a variable's class (Instances) or type",
		Run = function(ctx)
			local name, value = need(ctx, ctx.Args[1])
			local wanted = ctx.Args[2]
			if not wanted then
				ctx.usage()
			end
			local result
			if typeof(value) == "Instance" then
				local ok, is = pcall(function()
					return value:IsA(wanted)
				end)
				result = ok and is or typeof(value) == wanted
			else
				result = typeof(value) == wanted or type(value) == wanted
			end
			if result then
				ctx.success(("$%s is a %s"):format(name, wanted))
			else
				ctx.warn(("$%s is not a %s · it is %s"):format(name, wanted, Types.tag(value)))
			end
			return result
		end,
		Complete = function(_, argIndex)
			if argIndex == 1 then
				return variableNames()
			end
			return { "BasePart", "Model", "GuiObject", "LuaSourceContainer", "number", "string", "table", "Instance" }
		end,
	},
	{
		Name = "export",
		Group = "Variables",
		Usage = "/export <name ...> | *",
		Description = "copy variables to the clipboard as Luau code",
		Run = function(ctx)
			local names = {}
			if ctx.Args[1] == "*" then
				names = variableNames()
			else
				for _, word in ctx.Args do
					table.insert(names, (need(ctx, word)))
				end
			end
			if #names == 0 then
				ctx.usage()
			end
			local lines = {}
			for _, name in names do
				local value = Variables.get(name)
				table.insert(lines, ("local %s = %s"):format(name, Types.literal(value)))
			end
			local text = table.concat(lines, "\n")
			local ok, err = pcall(setclipboard, text)
			if not ok then
				ctx.fail("could not copy: " .. tostring(err))
			end
			ctx.success(("copied %d variable%s as Luau (%d characters)"):format(#names, if #names == 1 then "" else "s", #text))
			return text
		end,
		Complete = function()
			return variableNames()
		end,
	},
	{
		Name = "watch",
		Group = "Variables",
		Usage = "/watch [name ...]",
		Description = "print a [$] line whenever these variables change",
		Run = function(ctx)
			if #ctx.Args == 0 then
				local names = {}
				for name in watched do
					table.insert(names, "$" .. name)
				end
				table.sort(names)
				ctx.info(if #names == 0 then "nothing watched · /watch name" else "watching " .. table.concat(names, ", "))
				return
			end
			local added = {}
			for _, word in ctx.Args do
				local name = word:gsub("^%$", "")
				local ok, reason = Variables.validName(name)
				if not ok then
					ctx.fail(reason :: string)
				end
				watched[name] = true
				table.insert(added, "$" .. name)
			end
			ctx.success("watching " .. table.concat(added, ", "))
		end,
		Complete = function()
			return Variables.names()
		end,
	},
	{
		Name = "unwatch",
		Group = "Variables",
		Usage = "/unwatch <name ...> | *",
		Description = "stop watching variables",
		Run = function(ctx)
			if #ctx.Args == 0 then
				ctx.usage()
			end
			if ctx.Args[1] == "*" then
				table.clear(watched)
				ctx.success("stopped watching everything")
				return
			end
			for _, word in ctx.Args do
				watched[(word:gsub("^%$", ""))] = nil
			end
			ctx.success("stopped watching " .. table.concat(ctx.Args, ", "))
		end,
		Complete = function()
			local names = {}
			for name in watched do
				table.insert(names, name)
			end
			return names
		end,
	},
	{
		Name = "setas",
		Group = "Variables",
		Usage = "/setas <name> <type> <text>",
		Description = "set a variable from text read as a type (/setas v Vector3 1, 2, 3)",
		Run = function(ctx)
			local name, typeName, text = ctx.Raw:match("^%$?([%a_][%w_]*)%s+([%a_][%w_%.]*)%s*(.-)%s*$")
			if not name then
				ctx.usage()
			end
			local opts = {}
			-- "Enum.Material" or "Material" (an enum's name) mean EnumItem.
			local enumName = (typeName :: string):match("^Enum%.([%a_][%w_]*)$")
			if not enumName and (typeName :: string):match("^%u") and not Types.default(typeName :: string)
				and not table.find({ "Instance", "EnumItem", "Color3", "BrickColor", "CFrame" }, typeName) then
				local ok = pcall(function()
					return (Enum :: any)[typeName]:GetEnumItems()
				end)
				if ok then
					enumName = typeName
				end
			end
			if enumName then
				typeName, opts.Enum = "EnumItem", enumName
			end
			local ok, value = Types.parse(text :: string, typeName :: string, opts)
			if not ok then
				ctx.fail(value)
			end
			if value == nil then
				ctx.fail("that gives nil · /unset " .. name .. " removes a variable")
			end
			put(ctx, name :: string, value)
			ctx.value("success", name .. " = ", value)
			return value
		end,
		Complete = function(_, argIndex)
			if argIndex == 1 then
				return variableNames()
			elseif argIndex == 2 then
				return { "number", "string", "boolean", "Vector2", "Vector3", "Color3", "UDim", "UDim2", "CFrame", "Instance", "BrickColor", "NumberRange", "Rect", "table", "Material" }
			end
			return {}
		end,
	},
	{
		Name = "cast",
		Aliases = { "convert" },
		Group = "Variables",
		Usage = "/cast <name> <type>",
		Description = "convert a variable to another type (\"5\" -> 5, Vector3 -> text, ...)",
		Run = function(ctx)
			local name, value = need(ctx, ctx.Args[1])
			local typeName = ctx.Args[2]
			if not typeName then
				ctx.usage()
			end
			local ok, converted = Types.convert(value, typeName)
			if not ok then
				ctx.fail(("can't make %s a %s: %s"):format(Types.tag(value), typeName, tostring(converted)))
			end
			if converted == nil then
				ctx.fail("that gives nil")
			end
			put(ctx, name, converted)
			ctx.value("success", name .. " = ", converted)
			return converted
		end,
		Complete = function(_, argIndex)
			if argIndex == 1 then
				return variableNames()
			elseif argIndex == 2 then
				return { "number", "string", "boolean", "Vector2", "Vector3", "Color3", "UDim2", "CFrame", "Instance" }
			end
			return {}
		end,
	},
	{
		Name = "call",
		Group = "Variables",
		Usage = "/call <name> [arguments]",
		Description = "call a function variable; arguments are Luau (/call f 1, \"x\", $a)",
		Run = function(ctx)
			local name, args = ctx.Raw:match("^%$?([%a_][%w_]*)%s*(.-)%s*$")
			if not name or name == "" then
				ctx.usage()
			end
			local fn, exists = Variables.get(name :: string)
			if not exists then
				ctx.fail(("no variable $%s · /vars lists them"):format(name))
			end
			local callable = type(fn) == "function"
			if not callable and type(fn) == "table" then
				local meta = getmetatable(fn)
				callable = type(meta) == "table" and rawget(meta, "__call") ~= nil
			end
			if not callable then
				ctx.fail(("$%s is %s, not a function"):format(name, Types.tag(fn)))
			end
			local argList = { n = 0 }
			if args ~= "" then
				local _, packed = ctx.eval("table.pack(" .. args .. ")")
				argList = packed[1]
			end
			local started = os.clock()
			local results = table.pack(pcall(fn, table.unpack(argList, 1, argList.n)))
			local took = os.clock() - started
			if not results[1] then
				ctx.fail(("$%s failed: %s"):format(name, tostring(results[2])))
			end
			if results.n == 1 then
				ctx.success(("$%s returned nothing"):format(name))
			else
				for index = 2, results.n do
					ctx.value("success", if results.n > 2 then ("%d: "):format(index - 1) else nil, results[index])
				end
			end
			if took > 0.05 then
				ctx.Console.write("time", ("took %.0f ms"):format(took * 1000))
			end
			return results[2]
		end,
		Complete = function(ctx, argIndex)
			local names = {}
			if argIndex == 1 then
				for _, entry in Variables.list() do
					if type(entry.Value) == "function" then
						table.insert(names, entry.Name)
					end
				end
			end
			return names
		end,
	},
}
