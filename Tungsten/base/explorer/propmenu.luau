--[[
	Tungsten · base/explorer/propmenu
	Menus of the properties panel (base/ui/menus):

		explorer.property    right-click on a property, sub-row, attribute
		                     or tag (open to plugins)
		explorer.properties  the panel's ⋯ button: what to show (open to plugins)

	explorer.property context:
		ctx.View       the panel (base/explorer/propview)
		ctx.Explorer   the explorer module
		ctx.Row        the row ({ Kind, Name, Prop, Value, Same, Field, … })
		ctx.Kind       "property" | "field" | "attribute" | "tag" | "add_attribute"
		ctx.Name       the property / attribute / tag name
		ctx.Prop       what is known about the property (base/explorer/api)
		ctx.Value      its value (when ctx.Same)
		ctx.Same       all selected objects have the same value
		ctx.Instances  the selected objects; ctx.Count
		ctx.Point      where the menu opened
	explorer.properties context: ctx.View, ctx.Explorer.
]]

local T = ...
local Settings = T.import("base/settings")
local Variables = T.import("base/variables")
local Types = T.import("base/types")
local Overlay = T.import("base/ui/overlay")
local Menus = T.import("base/ui/menus")
local CellEditor = T.import("base/ui/components/celleditor")
local Properties = T.import("base/explorer/properties")
local Editors = T.import("base/explorer/editors")

local PropMenu = {}

local function say(kind: string, text: string)
	local reporter = if T.Console then T.Console.reporter("explorer", { Label = "Explorer", Plugin = false, Kind = "explorer" }) else nil
	if reporter then
		(reporter :: any)[kind](reporter, text)
	end
end

local function copy(text: string, what: string)
	local ok = pcall(setclipboard, text)
	if ok then
		say("success", ("copied %s"):format(what))
	else
		say("warn", "couldn't copy (setclipboard failed)")
	end
end

local function isValueRow(ctx): boolean
	return ctx.Kind == "property" or ctx.Kind == "field" or ctx.Kind == "attribute"
end

-- The property row a sub-row belongs to (or the row itself).
local function mainRow(ctx)
	local row = ctx.Row
	if row.Kind == "field" then
		return row.Parent
	end
	return row
end

local function indexText(name: string): string
	return if Types.isIdentifier(name) then "." .. name else ("[%s]"):format(Types.literal(name))
end

-- Lines of code that set the value on each selected object (its own value).
function PropMenu.codeFor(ctx): string
	local row = mainRow(ctx)
	local lines = {}
	for _, instance in Properties.compared(ctx.Instances) do
		if row.Kind == "attribute" then
			local ok, value = pcall(function()
				return instance:GetAttribute(row.Name)
			end)
			if ok then
				table.insert(lines, ("%s:SetAttribute(%s, %s)"):format(Types.path(instance), Types.literal(row.Name), Types.literal(value)))
			end
		else
			local ok, value = Properties.read(instance, row.Prop)
			if ok then
				table.insert(lines, ("%s%s = %s"):format(Types.path(instance), indexText(row.Name), Types.literal(value)))
			end
		end
	end
	if #ctx.Instances > #lines and #lines >= Properties.MaxCompare then
		table.insert(lines, ("-- … and %d more"):format(#ctx.Instances - #lines))
	end
	return table.concat(lines, "\n")
end

-- The value(s) of a row: the shared value, or a table of each object's.
local function valuesOf(ctx): (any, boolean)
	local row = ctx.Row
	if row.Same ~= false then
		return row.Value, true
	end
	local list = {}
	for _, instance in Properties.compared(ctx.Instances) do
		local value
		if row.Kind == "attribute" then
			value = instance:GetAttribute(row.Name)
		elseif row.Kind == "field" then
			local ok, whole = Properties.read(instance, row.Parent.Prop)
			value = if ok then select(2, pcall(row.Field.Get, whole)) else nil
		else
			local ok, current = Properties.read(instance, row.Prop)
			value = if ok then current else nil
		end
		table.insert(list, value)
	end
	return list, false
end

local function suggestName(name: string): string
	local base = name:gsub("[^%w_]", "")
	base = base:sub(1, 1):lower() .. base:sub(2)
	if base == "" or base:match("^%d") then
		base = "value"
	end
	return base
end

function PropMenu.promptVariable(ctx)
	local value, same = valuesOf(ctx)
	return CellEditor.open({
		AnchorPos = ctx.Point or Overlay.mouse(),
		AnchorSize = Vector2.new(220, 24),
		Text = suggestName(ctx.Name),
		Mono = true,
		Hint = if same then "variable name · holds the value" else ("variable name · holds the %d values"):format(#value),
		Validate = function(text)
			local name = text:gsub("^%$", "")
			local ok, reason = Variables.validName(name)
			if not ok then
				return false, reason
			end
			if Variables.isReserved(name) then
				return false, ("$%s is reserved"):format(name)
			end
			return true, name
		end,
		OnCommit = function(name)
			local ok, reason = Variables.set(name, value, { Source = "explorer" })
			if not ok then
				return false, reason
			end
			if T.Console then
				T.Console.value("success", name .. " = ", value)
			end
			return true
		end,
	})
end

-- Whether a value fits a row (for Set from variable).
local function fits(row, value): boolean
	local prop = row.Prop
	if prop.Type == "any" then
		return true
	end
	if prop.Type == "Instance" then
		if typeof(value) ~= "Instance" then
			return false
		end
		local ok, is = pcall(function()
			return value:IsA(prop.ClassRef or "Instance")
		end)
		return ok and is
	end
	if prop.Type == "EnumItem" then
		if typeof(value) ~= "EnumItem" then
			return false
		end
		return prop.Enum == nil or tostring(value.EnumType):gsub("^Enum%.", "") == prop.Enum
	end
	if prop.Type == "number" and type(value) == "number" then
		return not prop.Integer or value == math.floor(value)
	end
	return Types.isA(value, prop.Type)
end
PropMenu.fits = fits

function PropMenu.variableItems(ctx): { any }
	local row = ctx.Row
	local items = {}
	for _, entry in Variables.list() do
		if fits(row, entry.Value) then
			table.insert(items, {
				Text = ("$%s  %s"):format(entry.Name, Types.short(entry.Value, 40)),
				Icon = (Types.icon(entry.Value)),
				Callback = function()
					local ok, reason = ctx.View:Apply(row, entry.Value)
					if ok then
						say("success", ("%s = $%s"):format(row.Name, entry.Name))
					elseif reason then
						say("warn", reason)
					end
				end,
			})
			if #items >= 30 then
				break
			end
		end
	end
	if #items == 0 then
		table.insert(items, { Text = ("No variable holds a %s"):format(row.Prop.Type), Disabled = true })
	end
	return items
end

----------------------------------------------------------------------
-- explorer.property
----------------------------------------------------------------------

Menus.define("explorer.property", {
	Source = "explorer",
	Title = "Explorer › property (properties panel)",
	Header = function(ctx)
		if ctx.Kind == "tag" then
			return "Tag " .. ctx.Name
		elseif ctx.Kind == "attribute" then
			return "Attribute " .. ctx.Name
		end
		local prop = ctx.Prop
		if prop and prop.Type then
			return ("%s · %s"):format(ctx.Name, prop.DataType or prop.Type)
		end
		return ctx.Name
	end,
	Sections = { "edit", "copy", "variables", "attribute", "tag" },
})

Menus.addMany("explorer.property", {
	{
		Id = "edit",
		Section = "edit",
		Order = 10,
		Text = "Edit value",
		Icon = "edit",
		When = isValueRow,
		Disabled = function(ctx)
			return not ctx.View.canEdit(ctx.Row)
		end,
		Callback = function(ctx)
			task.defer(function()
				ctx.View:Edit(ctx.Row, nil)
			end)
		end,
	},
	{
		Id = "edit_text",
		Section = "edit",
		Order = 20,
		Text = "Type a value…",
		Icon = "edit",
		When = function(ctx)
			if not isValueRow(ctx) then
				return false
			end
			local inline = Editors.get(ctx.Prop).Inline or "text"
			return inline ~= "text" and inline ~= "toggle" and inline ~= "dropdown"
		end,
		Disabled = function(ctx)
			return not ctx.View.canEdit(ctx.Row)
		end,
		Callback = function(ctx)
			task.defer(function()
				ctx.View:EditText(ctx.Row)
			end)
		end,
	},
	{
		Id = "expand",
		Section = "edit",
		Order = 30,
		Text = function(ctx)
			return if ctx.View.Expanded[ctx.Row.Key] then "Close parts" else "Show parts"
		end,
		Icon = "expand_all",
		When = function(ctx)
			return ctx.Row.Expandable == true
		end,
		Callback = function(ctx)
			ctx.View:ToggleExpanded(ctx.Row)
		end,
	},
	{
		Id = "copy_value",
		Section = "copy",
		Order = 10,
		Text = "Copy value",
		Icon = "copy",
		When = isValueRow,
		Disabled = function(ctx)
			return ctx.Row.Readable == false
		end,
		Callback = function(ctx)
			local value, same = valuesOf(ctx)
			local text = if same then Editors.editText(ctx.Prop, value) else Types.literal(value)
			copy(text, if same then ctx.Name else ("%d values of %s"):format(#value, ctx.Name))
		end,
	},
	{
		Id = "copy_name",
		Section = "copy",
		Order = 20,
		Text = "Copy name",
		Icon = "copy",
		Callback = function(ctx)
			copy(ctx.Name, "the name")
		end,
	},
	{
		Id = "copy_code",
		Section = "copy",
		Order = 30,
		Text = "Copy as code",
		Icon = "copy",
		When = isValueRow,
		Disabled = function(ctx)
			return ctx.Row.Readable == false or ctx.Count == 0
		end,
		Callback = function(ctx)
			local code = PropMenu.codeFor(ctx)
			copy(code, if ctx.Count == 1 then "the code" else ("code for %d objects"):format(math.min(ctx.Count, Properties.MaxCompare)))
		end,
	},
	{
		Id = "save_variable",
		Section = "variables",
		Order = 10,
		Text = "Save value as variable…",
		Icon = "variable",
		When = isValueRow,
		Disabled = function(ctx)
			return ctx.Row.Readable == false
		end,
		Callback = function(ctx)
			task.defer(PropMenu.promptVariable, ctx)
		end,
	},
	{
		Id = "from_variable",
		Section = "variables",
		Order = 20,
		Text = "Set from variable",
		Icon = "variable",
		When = isValueRow,
		Disabled = function(ctx)
			return not ctx.View.canEdit(ctx.Row)
		end,
		Items = function(ctx)
			return PropMenu.variableItems(ctx)
		end,
	},
	{
		Id = "rename_attribute",
		Section = "attribute",
		Order = 10,
		Text = "Rename attribute…",
		Icon = "edit",
		When = function(ctx)
			return ctx.Kind == "attribute"
		end,
		Callback = function(ctx)
			task.defer(function()
				ctx.View:RenameAttribute(ctx.Row)
			end)
		end,
	},
	{
		Id = "remove_attribute",
		Section = "attribute",
		Order = 20,
		Text = "Remove attribute",
		Icon = "trash",
		Danger = true,
		When = function(ctx)
			return ctx.Kind == "attribute"
		end,
		Callback = function(ctx)
			local count = ctx.View:RemoveAttribute(ctx.Row)
			if count > 0 then
				say("success", ("removed attribute %s from %d object%s"):format(ctx.Name, count, if count == 1 then "" else "s"))
			end
		end,
	},
	{
		Id = "add_attribute",
		Section = "attribute",
		Order = 30,
		Text = "Add attribute…",
		Icon = "add",
		When = function(ctx)
			return ctx.Kind == "attribute" or ctx.Kind == "add_attribute"
		end,
		Callback = function(ctx)
			task.defer(function()
				ctx.View:AddAttribute(ctx.Point)
			end)
		end,
	},
	{
		Id = "remove_tag",
		Section = "tag",
		Order = 10,
		Text = "Remove tag",
		Icon = "trash",
		Danger = true,
		When = function(ctx)
			return ctx.Kind == "tag"
		end,
		Callback = function(ctx)
			local count = 0
			for _, instance in ctx.Instances do
				if pcall(function()
					instance:RemoveTag(ctx.Name)
				end) then
					count += 1
				end
			end
			ctx.View:Rebuild()
			say("success", ("removed tag %s from %d object%s"):format(ctx.Name, count, if count == 1 then "" else "s"))
		end,
	},
})

----------------------------------------------------------------------
-- explorer.properties (the ⋯ button)
----------------------------------------------------------------------

Menus.define("explorer.properties", {
	Source = "explorer",
	Title = "Explorer › properties options",
	Header = "Properties",
	Sections = { "show", "numbers", "categories", "attributes" },
})

local DECIMALS = { 0, 1, 2, 3, 4, 6 }

Menus.addMany("explorer.properties", {
	{
		Id = "deprecated",
		Section = "show",
		Order = 10,
		Text = "Show deprecated",
		Checked = function()
			return Settings.get("PropertiesDeprecated") == true
		end,
		Callback = function(_, item)
			Settings.set("PropertiesDeprecated", item.Checked == true)
		end,
	},
	{
		Id = "hidden",
		Section = "show",
		Order = 20,
		Text = "Show hidden",
		Checked = function()
			return Settings.get("PropertiesHidden") == true
		end,
		Callback = function(_, item)
			Settings.set("PropertiesHidden", item.Checked == true)
		end,
	},
	{
		Id = "decimals",
		Section = "numbers",
		Order = 10,
		Text = function()
			return ("Decimals: %d"):format(Properties.decimals())
		end,
		Items = function()
			local items = {}
			for _, count in DECIMALS do
				table.insert(items, {
					Text = tostring(count),
					Checked = Properties.decimals() == count,
					Callback = function()
						Settings.set("PropertyDecimals", count)
					end,
				})
			end
			return items
		end,
	},
	{
		Id = "expand_all",
		Section = "categories",
		Order = 10,
		Text = "Open all categories",
		Icon = "expand_all",
		Callback = function(ctx)
			ctx.View:SetAllCollapsed(false)
		end,
	},
	{
		Id = "collapse_all",
		Section = "categories",
		Order = 20,
		Text = "Close all categories",
		Icon = "collapse_all",
		Callback = function(ctx)
			ctx.View:SetAllCollapsed(true)
		end,
	},
	{
		Id = "add_attribute",
		Section = "attributes",
		Order = 10,
		Text = "Add attribute…",
		Icon = "add",
		Disabled = function(ctx)
			return #ctx.View.Instances == 0
		end,
		Callback = function(ctx)
			task.defer(function()
				ctx.View:AddAttribute()
			end)
		end,
	},
})

return PropMenu
