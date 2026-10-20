--[[
	Script Viewer · lib/actions
	The right-click menu on rows ("scriptviewer.row") and the forms its
	entries open. Every change goes through lib/edit, records an /undo
	step and says what it did in the console.

		Actions.define(api, getView)   -- defines the menu (plugin Load)
		Actions.editValue(view, panelId, node)
		Actions.setNil(view, panelId, node)
		Actions.addEntry(view, panelId, t, label)
		Actions.renameKey(view, panelId, node)
		Actions.setVariable(view, node)
		Actions.inspect(view, node)        -- load a row's table, function or Instance
		Actions.pathOf(view, node) -> code | nil   -- the row's path, when it has one
		Actions.applyText(view, panelId)   -- the Table view's Apply
		Actions.parseValue(api, typeName, text) -> ok, value | why
		Actions.typesFor(kind, value, anyType) -> the types a form offers
		Actions.readField(api, field) -> ok, value | why  (the value field)
	The forms' value field ("scriptviewer_value") is a Type dropdown with
	only the types that fit, and a value box that becomes a variable picker
	for the type "variable".

	A read-only table is made writable only after you say so, and is made
	read-only again straight after the write (Q10).
]]

local P = ...

local Edit = P.import("lib/edit")
local Serialize = P.import("lib/serialize")

local Actions = {}

-- Types a new entry may take ("variable": a $variable's value).
Actions.NewEntryTypes = { "string", "number", "boolean", "table", "Instance", "Vector3", "CFrame", "Color3", "UDim2", "EnumItem", "function", "variable" }
local CONSTANT_TYPES = { "string", "number", "boolean" }
local KEY_TYPES = { "string", "number", "boolean" }
local PLAIN = { string = true, number = true, boolean = true, ["nil"] = true }

-- The types the Change value form offers for a row: only those that fit.
--   a constant: its own type (or string, number, boolean and a vector it
--     already is, with "Constants may change type" on)
--   a string / number / boolean / nil: those four
--   a table, function, Instance or datatype: that type or nil
-- and always "variable" (a $variable's value).
function Actions.typesFor(kind: string, value: any, anyType: boolean?): { string }
	local current = typeof(value)
	local out
	if kind == "constant" then
		if anyType then
			out = table.clone(CONSTANT_TYPES)
			if current == "vector" then
				table.insert(out, "vector")
			end
		else
			out = { if value == nil then "string" else current }
		end
	elseif PLAIN[current] then
		out = { "string", "number", "boolean", "nil" }
	else
		out = { current, "nil" }
	end
	table.insert(out, "variable")
	return out
end

-- The text a value starts as in a form.
function Actions.valueText(value: any): string
	local kind = typeof(value)
	if kind == "nil" then
		return ""
	elseif kind == "string" then
		return value
	elseif kind == "number" then
		return Serialize.number(value)
	elseif kind == "boolean" then
		return tostring(value)
	elseif kind == "table" then
		return "{}"
	elseif kind == "function" then
		return "$"
	elseif kind == "Instance" then
		local ok, path = pcall(function()
			return value:GetFullName()
		end)
		return if ok then "game." .. path else ""
	end
	local ok, text = pcall(Serialize.write, value)
	if ok then
		-- a constructor: keep only what is inside the brackets
		local inside = text:match("^[%w%.]+%((.*)%)$")
		return inside or text
	end
	return tostring(value)
end

-- Text -> a value of a type. Values from text never run code: Tungsten's
-- own parser (Types.parse), which also takes $variables.
function Actions.parseValue(api, typeName: string, text: string): (boolean, any)
	local trimmed = (text or ""):match("^%s*(.-)%s*$")
	if typeName == "nil" then
		return true, nil
	elseif typeName == "string" then
		if trimmed:match("^%$[%a_][%w_]*$") then
			return api.types.parse(trimmed, "string")
		end
		return true, text or ""
	elseif typeName == "table" then
		if trimmed == "" or trimmed == "{}" then
			return true, {}
		end
		return api.types.parse(trimmed, "table")
	elseif typeName == "function" then
		if not trimmed:match("^%$[%a_][%w_]*$") then
			return false, "a function comes from a variable: $name"
		end
		return api.types.parse(trimmed, "function")
	end
	return api.types.parse(trimmed, typeName)
end

-- A form's value field (kind "scriptviewer_value") read back:
-- { Type, Text, Variable } -> ok, value | why
function Actions.readField(api, field: any): (boolean, any)
	if type(field) ~= "table" then
		return false, "no value"
	end
	if field.Type == "variable" then
		local name = field.Variable
		if type(name) ~= "string" or name == "" then
			return false, "pick a variable"
		end
		local value, exists = api.variables.get(name)
		if not exists then
			return false, ("$%s doesn't exist"):format(name)
		end
		return true, value
	end
	return Actions.parseValue(api, field.Type, field.Text)
end

-- Variables whose values fit the types (all of them for "any").
local function variableOptions(api, types: { string }): { any }
	local wanted = {}
	for _, name in types do
		wanted[name] = true
	end
	local out = {}
	for _, name in api.variables.names() do
		local value = api.variables.get(name)
		local kind = typeof(value)
		if wanted.any or wanted[kind] then
			table.insert(out, { Value = name, Text = "$" .. name, Hint = kind })
		end
	end
	if #out == 0 then
		table.insert(out, { Value = false, Text = "no variables of these types", Disabled = true })
	end
	return out
end
Actions.variableOptions = variableOptions

-- The form field: a Type dropdown and a value box, which becomes a
-- variable picker when the type is "variable". Field options: Types,
-- DefaultType, Default (text), Variables (types the picker lists; default
-- the field's Types).
function Actions.defineFieldKind(api)
	api.prompt.registerFieldKind("scriptviewer_value", {
		Height = 26,
		Build = function(holder, field, form)
			local types = field.Types or { "string" }
			local valueTypes = {}
			for _, name in field.Variables or types do
				if name ~= "variable" and name ~= "nil" then
					table.insert(valueTypes, name)
				end
			end
			local typeBox = api.ui.new("Dropdown", {
				Parent = holder,
				Name = "Type",
				Options = types,
				Value = if table.find(types, field.DefaultType) then field.DefaultType else types[1],
				Size = UDim2.new(0, 104, 1, 0),
			})
			local textBox = api.ui.new("Input", {
				Parent = holder,
				Name = "Text",
				Text = if field.Default ~= nil then tostring(field.Default) else "",
				Position = UDim2.fromOffset(110, 0),
				Size = UDim2.new(1, -110, 1, 0),
			})
			local varBox = api.ui.new("Dropdown", {
				Parent = holder,
				Name = "Variable",
				Options = variableOptions(api, valueTypes),
				Placeholder = "Pick a variable",
				Searchable = true,
				Position = UDim2.fromOffset(110, 0),
				Size = UDim2.new(1, -110, 1, 0),
			})
			local function show()
				local kind = typeBox:GetValue()
				local isVariable = kind == "variable"
				textBox.Instance.Visible = not isVariable
				varBox.Instance.Visible = isVariable
				if textBox.Box then
					textBox.Box.PlaceholderText = if kind == "nil" then "nil (nothing to type)" else api.types.hint(kind)
				end
			end
			form.Bin:Add(typeBox.Changed:Connect(show))
			form.Bin:Add(typeBox)
			form.Bin:Add(textBox)
			form.Bin:Add(varBox)
			show()
			return {
				Get = function()
					local name = varBox:GetValue()
					return { Type = typeBox:GetValue(), Text = textBox:GetText(), Variable = if type(name) == "string" then name else nil }
				end,
				Set = function(value)
					if type(value) ~= "table" then
						return
					end
					if value.Type then
						typeBox:SetValue(value.Type)
					end
					if value.Text ~= nil then
						textBox:SetText(tostring(value.Text))
					end
					if value.Variable ~= nil then
						varBox:SetValue(value.Variable)
					end
					show()
				end,
				Focus = function()
					textBox:Focus()
				end,
				Control = typeBox,
				TypeBox = typeBox,
				TextBox = textBox,
				VariableBox = varBox,
			}
		end,
	})
end

local function describe(node): string
	return tostring(node.Path or node.Key or "?")
end

-- Shows the result and records the undo step.
local function done(view, panelId: string, ok: boolean, why: string?, undo, text: string)
	local api = view.Api
	if not ok then
		api.console.error(("couldn't %s: %s"):format(text, tostring(why)))
		return false, why
	end
	if undo then
		api.undo.record({
			Text = text,
			Undo = function()
				undo()
				if not view.Destroyed then
					view:Refresh()
				end
			end,
		})
	end
	api.console.success(text)
	if not view.Destroyed then
		view:Refresh()
	end
	return true, nil
end

-- Runs a write; a read-only table asks first and retries unlocked.
local function withUnlock(view, attempt: (opts: any) -> (boolean, string?, any), onFinish: (boolean, string?, any) -> ())
	local api = view.Api
	-- Subject: a script's constants go to its running functions (lib/edit)
	local opts = { AnyType = api.settings.get("constantAnyType") == true, Subject = view.Subject }
	local ok, why, undo = attempt(opts)
	if ok or why ~= "read-only" then
		onFinish(ok, why, undo)
		return
	end
	api.prompt.confirm({
		Title = "Make the table writable?",
		Text = "This table is read-only. It will be made writable for this change and read-only again right after.",
		ConfirmText = "Change it",
		OnConfirm = function()
			opts.Unlock = true
			onFinish(attempt(opts))
		end,
		OnCancel = function()
			onFinish(false, "the table is read-only (left as it was)", nil)
		end,
	})
end

----------------------------------------------------------------------
-- Forms
----------------------------------------------------------------------

function Actions.editValue(view, panelId: string, node)
	local api = view.Api
	local kind = Edit.kindOf(node)
	if not kind then
		api.console.warn("only constants, upvalues and table entries can be changed")
		return
	end
	local currentType = typeof(node.Value)
	local options = Actions.typesFor(kind, node.Value, api.settings.get("constantAnyType") == true)
	local defaultType = if table.find(options, currentType) then currentType else options[1]
	return api.prompt.form({
		Title = ("Change %s"):format(describe(node)),
		Text = if kind == "constant" and view.Subject and (view.Subject.Kind == "script" or view.Subject.Kind == "module") then "Written to the script's running functions that are this function (the view reads a copy compiled again from its bytecode). Changing a constant used in several places changes it everywhere."
			elseif kind == "constant" then "Constants are changed in the function's bytecode for this session. Changing a constant used in several places changes it everywhere."
			else "Changed in the game's memory for this session (nothing replicates).",
		Fields = {
			-- the picker: any variable for an upvalue or entry (a variable is how
			-- one changes type), only constant-shaped ones for a constant
			{ Key = "value", Label = "Value", Kind = "scriptviewer_value", Types = options, DefaultType = defaultType, Default = Actions.valueText(node.Value),
				Variables = if kind == "constant" then { "string", "number", "boolean", "vector" } else { "any" } },
		},
		OnSubmit = function(values)
			local okParse, value = Actions.readField(api, values.value)
			if not okParse then
				return false, tostring(value)
			end
			local result
			withUnlock(view, function(opts)
				return Edit.write(node, value, opts)
			end, function(ok, why, undo)
				result = { ok, why }
				done(view, panelId, ok, why, undo, ("change %s to %s"):format(describe(node), api.types.display(value)))
			end)
			if result and not result[1] then
				return false, tostring(result[2]) -- the form stays open to fix it
			end
			return true -- done, or waiting for "make the table writable?"
		end,
	})
end

function Actions.setNil(view, panelId: string, node)
	withUnlock(view, function(opts)
		return Edit.remove(node, opts)
	end, function(ok, why, undo)
		done(view, panelId, ok, why, undo, ("set %s to nil"):format(describe(node)))
	end)
end

local function parseKey(api, keyType: string, text: string): (boolean, any)
	if keyType == "string" then
		if text == "" then
			return false, "the key is empty"
		end
		return true, text
	end
	local ok, key = api.types.parse(text, keyType)
	if ok and key == nil then
		return false, "the key is missing"
	end
	return ok, key
end

function Actions.addEntry(view, panelId: string, t: any, label: string?)
	local api = view.Api
	if typeof(t) ~= "table" then
		api.console.warn("entries are added to tables")
		return
	end
	return api.prompt.form({
		Title = ("Add an entry to %s"):format(label or "the table"),
		Fields = {
			{ Key = "keyType", Label = "Key type", Kind = "dropdown", Options = KEY_TYPES, Default = "string" },
			{ Key = "key", Label = "Key", Kind = "text", Default = "" },
			{ Key = "value", Label = "Value", Kind = "scriptviewer_value", Types = Actions.NewEntryTypes, DefaultType = "string", Default = "", Variables = { "any" } },
		},
		OnSubmit = function(values)
			local okKey, key = parseKey(api, values.keyType, values.key)
			if not okKey then
				return false, tostring(key)
			end
			local okValue, value = Actions.readField(api, values.value)
			if not okValue then
				return false, tostring(value)
			end
			if value == nil then
				return false, "a new entry needs a value"
			end
			withUnlock(view, function(opts)
				return Edit.add(t, key, value, opts)
			end, function(ok, why, undo)
				done(view, panelId, ok, why, undo, ("add %s to %s"):format(tostring(key), label or "the table"))
			end)
			return true
		end,
	})
end

function Actions.renameKey(view, panelId: string, node)
	local api = view.Api
	if Edit.kindOf(node) ~= "entry" then
		api.console.warn("only table entries have keys to rename")
		return
	end
	local keyType = type(node.RawKey)
	return api.prompt.form({
		Title = ("Rename %s"):format(describe(node)),
		Fields = {
			{ Key = "keyType", Label = "Key type", Kind = "dropdown", Options = KEY_TYPES, Default = if table.find(KEY_TYPES, keyType) then keyType else "string" },
			{ Key = "key", Label = "New key", Kind = "text", Default = Actions.valueText(node.RawKey) },
		},
		OnSubmit = function(values)
			local okKey, key = parseKey(api, values.keyType, values.key)
			if not okKey then
				return false, tostring(key)
			end
			withUnlock(view, function(opts)
				return Edit.rename(node, key, opts)
			end, function(ok, why, undo)
				done(view, panelId, ok, why, undo, ("rename %s to %s"):format(describe(node), tostring(key)))
			end)
			return true
		end,
	})
end

-- A variable name from a row's key ("max speed" -> "max_speed").
function Actions.suggestName(node): string
	local key = if type(node) == "table" then tostring(node.RawKey or node.Key or "") else ""
	key = key:gsub("^%s+", ""):gsub("%s+.*$", ""):gsub("[^%w_]", "_")
	if key == "" or key:match("^%d") then
		key = "value" .. (if key ~= "" then "_" .. key else "")
	end
	return key:sub(1, 40)
end

function Actions.setVariable(view, node)
	local api = view.Api
	return api.prompt.input({
		Title = "Keep it in a variable",
		Text = ("$name will hold %s"):format(describe(node)),
		Default = Actions.suggestName(node),
		Placeholder = "name (letters, digits, _)",
		OnSubmit = function(name)
			name = tostring(name or ""):gsub("^%$", "")
			if not name:match("^[%a_][%w_]*$") then
				return false, "a name is letters, digits and _"
			end
			local ok, why = api.variables.set(name, node.Value)
			if ok == false then
				return false, tostring(why)
			end
			api.console.success(("$%s = %s"):format(name, api.types.display(node.Value)))
			return true
		end,
	})
end

function Actions.applyText(view, panelId: string)
	local api = view.Api
	local panel = view.Panels[panelId]
	local subject = view.Subject
	if not panel or not subject then
		return false
	end
	local target = if panelId == "contents" then subject.Table else subject.Fn
	local text = panel.Text:GetText()
	local finished = false
	withUnlock(view, function(opts)
		local ok, why, count, undo = Edit.applyText(panelId, target, text, opts)
		if ok and count == 0 then
			return false, "nothing changed", nil
		end
		return ok, why, { Count = count, Undo = undo }
	end, function(ok, why, result)
		finished = true
		if not ok then
			if why == "nothing changed" then
				api.console.info("nothing changed")
				return
			end
			done(view, panelId, false, why, nil, "apply the table")
			return
		end
		done(view, panelId, true, nil, result.Undo, ("apply %d %s to %s"):format(result.Count, if result.Count == 1 then "change" else "changes", panelId))
	end)
	return finished
end

----------------------------------------------------------------------
-- Where a row's value is in its script (the path bar shows it:
-- require(game.ReplicatedStorage.Util).Sub.fn)
----------------------------------------------------------------------

-- How the loaded thing itself is reached: given with the load, a script's
-- root (require / getsenv), or searched for.
function Actions.subjectAccess(api, subject): any
	local A = api.loaded.access
	if not A or type(subject) ~= "table" then
		return nil
	end
	local item = subject.Item
	if type(item) == "table" and A.is(item.Access) then
		return item.Access
	end
	if subject.Instance and (subject.Kind == "module" or subject.Kind == "script") then
		return A.root(subject.Instance)
	end
	local value = subject.Fn or subject.Table
	if value ~= nil then
		local ok, found = pcall(A.find, value)
		return if ok then found else nil
	end
	return nil
end

-- base extended by base/access steps (a heading's Chain).
local function along(A, base, steps): any
	local access = base
	for _, step in steps do
		access = A.extend(access, step)
	end
	return access
end

function Actions.accessOf(api, subject, node): any
	local A = api.loaded.access
	if not A or type(node) ~= "table" then
		return nil
	end
	local base = Actions.subjectAccess(api, subject)
	-- steps from the loaded function hold only when a function (or nested
	-- function) is loaded: a script's main function is a copy no path reaches
	local fromFunction = base ~= nil and subject ~= nil and (subject.Kind == "function" or subject.Kind == "proto")
	-- a loaded nested function's k-th running copy: its last step, activated
	local function copyAccess(k: number): any
		local last = base.Steps[#base.Steps]
		if not last or last.Kind ~= "proto" then
			return nil
		end
		return A.extend(A.prefix(base, #base.Steps - 1), { Kind = "closure", Index = last.Index, Copy = k })
	end
	if node.Kind == "heading" and type(node.CopyIndex) == "number" and fromFunction and subject.Kind == "proto" then
		return copyAccess(node.CopyIndex)
	end
	if node.Kind == "heading" and type(node.Chain) == "table" and fromFunction then
		return along(A, base, node.Chain)
	end
	if node.Kind == "proto" and type(node.Chain) == "table" and not node.FromCopy then
		-- a row of the Functions sub-tab: from the loaded function, or from
		-- the running function it is nested in
		local root = nil
		if node.Root ~= nil then
			local ok, found = pcall(A.find, node.Root)
			root = if ok then found else nil
		elseif fromFunction then
			root = base
		end
		return if root then along(A, root, node.Chain) else nil
	end
	if node.Kind == "upvalue" and node.Owner ~= nil and type(node.Index) == "number" then
		local owner = nil
		if fromFunction and subject.Kind == "proto" and type(node.CopyIndex) == "number" then
			owner = copyAccess(node.CopyIndex)
		elseif fromFunction and type(node.OwnerChain) == "table" then
			owner = along(A, base, node.OwnerChain)
		elseif fromFunction and rawequal(node.Owner, subject.Fn) then
			owner = base
		else
			local ok, found = pcall(A.find, node.Owner)
			owner = if ok then found else nil
		end
		if owner then
			return A.upvalue(owner, node.Index)
		end
	end
	if base then
		local ok, found = pcall(A.findFrom, base, node.Value)
		if ok and found then
			return found
		end
	end
	local ok, found = pcall(A.find, node.Value)
	return if ok then found else nil
end

----------------------------------------------------------------------
-- Inspect and Copy path
----------------------------------------------------------------------

-- Can a row's value be inspected (loaded so the viewer shows it)?
function Actions.inspectable(node): boolean
	if type(node) ~= "table" or node.Kind == "more" then
		return false
	end
	local kind = typeof(node.Value)
	return kind == "table" or kind == "function" or kind == "Instance" or kind == "ProtoProxy"
end

-- The sub-tab that fits a value: the open one when it applies.
local FUNCTION_TABS = { constants = true, upvalues = true }
local function tabFor(value: any, current: string?): string?
	local kind = typeof(value)
	if kind == "table" then
		return "contents"
	elseif kind == "function" or kind == "ProtoProxy" then
		return if current and FUNCTION_TABS[current] then current else "constants"
	end
	return nil
end
Actions.tabFor = tabFor

-- Where a nested function row came from, for its running copies:
-- { Owner, Index, FromCopy, ScriptSubject } (see Rows.runningCopies).
function Actions.protoOrigin(view, node): { [string]: any }
	local subject = view.Subject
	local origin = { Owner = node.Owner, Index = node.Index, FromCopy = node.FromCopy == true }
	if subject and (subject.Kind == "script" or subject.Kind == "module") and node.Kind == "heading" then
		origin.FromCopy = true -- a heading of a script's bytecode copy
	end
	if subject and subject.Kind == "proto" and subject.Proto and subject.Proto.FromCopy then
		origin.FromCopy = true
		origin.ScriptSubject = subject.Proto.ScriptSubject
	elseif origin.FromCopy then
		origin.ScriptSubject = subject
	end
	return origin
end

-- Loads a row's table, function, nested function or Instance (its path
-- goes to the path bar). opts.Tab: the sub-tab to open (false: stay);
-- by default the one that fits.
function Actions.inspect(view, node, opts: { [string]: any }?): boolean
	local api = view.Api
	if not Actions.inspectable(node) then
		return false
	end
	local value = node.Value
	local current = view.Tabs and view.Tabs.Selected
	if typeof(value) == "Instance" then
		api.loaded.set(value)
	else
		local access = Actions.accessOf(api, view.Subject, node)
		local info = if typeof(value) == "ProtoProxy" then Actions.protoOrigin(view, node) else nil
		api.loaded.set(api.loaded.target(value, { Label = describe(node), Access = access, Info = info }))
	end
	local wants = if opts and opts.Tab ~= nil then opts.Tab else tabFor(value, current)
	if wants and not view.Destroyed and view.Tabs.Selected ~= wants then
		view:Select(wants)
	end
	return true
end

-- Loads it and stays on the sub-tab that is open.
function Actions.load(view, node): boolean
	return Actions.inspect(view, node, { Tab = false })
end

-- The running copies of a nested function row (or of the loaded one).
function Actions.copiesOf(view, node): ({ any }?, string?)
	if typeof(node.Value) ~= "ProtoProxy" then
		return nil, "only a nested function has running copies"
	end
	local subject = view.Subject
	if subject and subject.Kind == "proto" and rawequal(node.Value, subject.Fn) then
		return P.import("lib/rows").runningCopies(node.Value, subject.Proto)
	end
	return P.import("lib/rows").runningCopies(node.Value, Actions.protoOrigin(view, node))
end

-- Loads a nested function's running copy (asks which when there are
-- several) and opens Upvalues, where its upvalues are.
function Actions.inspectCopy(view, node): boolean
	local api = view.Api
	local copies, why = Actions.copiesOf(view, node)
	if not copies or #copies == 0 then
		api.console.warn(why or "no running copies of it exist now")
		return false
	end
	local A = api.loaded.access
	local function loadCopy(k: number)
		local fn = copies[k]
		local access = nil
		local protoAccess = Actions.accessOf(api, view.Subject, node)
		local last = protoAccess and protoAccess.Steps[#protoAccess.Steps]
		if last and last.Kind == "proto" then
			access = A.extend(A.prefix(protoAccess, #protoAccess.Steps - 1), { Kind = "closure", Index = last.Index, Copy = k })
		else
			local ok, found = pcall(A.find, fn)
			access = if ok then found else nil
		end
		api.loaded.set(api.loaded.target(fn, { Label = ("%s · running %d"):format(describe(node), k), Access = access }))
		if not view.Destroyed then
			view:Select("upvalues")
		end
	end
	if #copies == 1 then
		loadCopy(1)
		return true
	end
	local options = {}
	for k, fn in copies do
		local okLine, line = pcall(debug.info, fn, "l")
		table.insert(options, { Value = k, Text = ("running %d%s"):format(k, if okLine and type(line) == "number" and line > 0 then " · line " .. line else "") })
	end
	api.prompt.choice({
		Title = "Which running copy?",
		Text = ("%d copies of %s are running; each has its own upvalues."):format(#copies, describe(node)),
		Options = options,
		OnChoose = function(k)
			if type(k) == "number" then
				loadCopy(k)
			end
		end,
	})
	return true
end

-- A function's hash (getfunctionhash) or a nested function's code hash.
function Actions.hashOf(value: any): string?
	if typeof(value) == "ProtoProxy" then
		local ok, hash = pcall(function()
			return value.CodeHash
		end)
		return if ok and hash ~= nil then tostring(hash) else nil
	end
	if type(value) ~= "function" then
		return nil
	end
	local fn = getfenv(1).getfunctionhash
	if type(fn) ~= "function" then
		return nil
	end
	local ok, hash = pcall(fn, value)
	return if ok and type(hash) == "string" then hash else nil
end

-- A row's path as code: an Instance's path, or how the value is reached
-- inside a script (base/access). Only for values Inspect can load.
function Actions.pathOf(view, node): string?
	if not Actions.inspectable(node) then
		return nil
	end
	local api = view.Api
	if typeof(node.Value) == "Instance" then
		local ok, path = pcall(api.types.path, node.Value)
		return if ok and type(path) == "string" then path else nil
	end
	local access = Actions.accessOf(api, view.Subject, node)
	if access == nil then
		return nil
	end
	local ok, code = pcall(api.loaded.access.code, access)
	return if ok then code else nil
end

----------------------------------------------------------------------
-- The menu
----------------------------------------------------------------------

local function isEditable(ctx): boolean
	return Edit.kindOf(ctx.Item) ~= nil
end

local function tableOf(ctx): (any, string?)
	local node = ctx.Item
	if type(node) ~= "table" then
		return nil
	end
	if typeof(node.Value) == "table" then
		return node.Value, describe(node)
	end
	if node.Kind == "entry" then
		return node.Parent, if node.Depth == 0 then "the table" else "the table holding " .. describe(node)
	end
	return nil
end

function Actions.define(api, getView)
	local function view(ctx)
		return ctx.View or getView()
	end
	Actions.defineFieldKind(api)
	api.menus.define("scriptviewer.row", {
		Title = "Script Viewer row",
		Header = function(ctx)
			local node = ctx.Item
			return if type(node) == "table" then describe(node) else "Script Viewer"
		end,
		Sections = {
			{ Id = "edit", Header = "Change" },
			{ Id = "use", Header = "Use" },
		},
		Empty = "Nothing to do with this row",
	})
	api.menus.addMany("scriptviewer.row", {
		{
			Id = "edit",
			Section = "edit",
			Order = 10,
			Text = "Change value…",
			Icon = "edit",
			When = isEditable,
			Callback = function(ctx)
				Actions.editValue(view(ctx), ctx.Panel, ctx.Item)
			end,
		},
		{
			Id = "nil",
			Section = "edit",
			Order = 20,
			Text = function(ctx)
				return if Edit.kindOf(ctx.Item) == "entry" then "Remove entry" else "Set to nil"
			end,
			Icon = "trash",
			Danger = true,
			When = function(ctx)
				local kind = Edit.kindOf(ctx.Item)
				return (kind == "entry" or kind == "upvalue") and ctx.Item.Value ~= nil
			end,
			Callback = function(ctx)
				Actions.setNil(view(ctx), ctx.Panel, ctx.Item)
			end,
		},
		{
			Id = "add",
			Section = "edit",
			Order = 30,
			Text = function(ctx)
				local _, label = tableOf(ctx)
				return "Add entry to " .. (label or "the table") .. "…"
			end,
			Icon = "add",
			When = function(ctx)
				return tableOf(ctx) ~= nil
			end,
			Callback = function(ctx)
				local t, label = tableOf(ctx)
				Actions.addEntry(view(ctx), ctx.Panel, t, label)
			end,
		},
		{
			Id = "rename",
			Section = "edit",
			Order = 40,
			Text = "Rename key…",
			Icon = "edit",
			When = function(ctx)
				return Edit.kindOf(ctx.Item) == "entry"
			end,
			Callback = function(ctx)
				Actions.renameKey(view(ctx), ctx.Panel, ctx.Item)
			end,
		},
		{
			Id = "inspect",
			Section = "use",
			Order = 10,
			Text = "Inspect",
			Icon = "arrow_right",
			When = function(ctx)
				return Actions.inspectable(ctx.Item)
			end,
			Callback = function(ctx)
				Actions.inspect(view(ctx), ctx.Item)
			end,
		},
		{
			Id = "loadhere",
			Section = "use",
			Order = 12,
			Text = "Load (stay here)",
			Icon = "arrow_right",
			When = function(ctx)
				return ctx.Panel == "functions" and Actions.inspectable(ctx.Item)
			end,
			Callback = function(ctx)
				Actions.load(view(ctx), ctx.Item)
			end,
		},
		{
			Id = "copy_running",
			Section = "use",
			Order = 14,
			Text = "Inspect running copy…",
			Icon = "arrow_right",
			When = function(ctx)
				return type(ctx.Item) == "table" and typeof(ctx.Item.Value) == "ProtoProxy"
			end,
			Callback = function(ctx)
				Actions.inspectCopy(view(ctx), ctx.Item)
			end,
		},
		{
			Id = "variable",
			Section = "use",
			Order = 20,
			Text = "Keep in a variable…",
			Icon = "variable",
			When = function(ctx)
				return type(ctx.Item) == "table" and ctx.Item.Value ~= nil and ctx.Item.Kind ~= "more"
			end,
			Callback = function(ctx)
				Actions.setVariable(view(ctx), ctx.Item)
			end,
		},
		{
			Id = "copy",
			Section = "use",
			Order = 30,
			Text = "Copy value",
			Icon = "copy",
			When = function(ctx)
				return type(ctx.Item) == "table" and ctx.Item.Kind ~= "more"
			end,
			Callback = function(ctx)
				local text = if type(ctx.Item.ValueText) == "string" then ctx.Item.ValueText else api.types.display(ctx.Item.Value)
				if pcall(setclipboard, text) then
					api.console.success("copied " .. text)
				else
					api.console.error("couldn't copy: the clipboard isn't available")
				end
			end,
		},
		{
			Id = "path",
			Section = "use",
			Order = 40,
			Text = "Copy path",
			Icon = "copy",
			-- only where Inspect applies and a real path exists (code that
			-- reaches it), never a row number
			When = function(ctx)
				local v = view(ctx)
				return v ~= nil and Actions.pathOf(v, ctx.Item) ~= nil
			end,
			Callback = function(ctx)
				local path = Actions.pathOf(view(ctx), ctx.Item)
				if not path then
					return
				end
				if pcall(setclipboard, path) then
					api.console.success("copied " .. path)
				else
					api.console.error("couldn't copy: the clipboard isn't available")
				end
			end,
		},
	})
end

return Actions
