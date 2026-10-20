--[[
	Script Viewer · lib/details
	The Functions sub-tab's details pane: what the selected function is and
	what can be done with it.

		local pane = Details.new(view, parent)   -- parent: a Frame
		pane:Show(node)                          -- a row of the Functions sub-tab, or nil
		pane.Facts                               -- { { Text, Value } } shown now

	Facts: name, kind (running function, nested function prototype, C
	function, made by the executor), source and line, parameters, upvalue,
	constant and nested counts, hash, running copies (nested functions:
	counted when selected, it looks through memory) and its path.
	Buttons: Inspect (load it, open Constants), Load (stay here), Running
	copy… (a nested function's running copies, for their upvalues), Keep in
	a variable…, Copy path, Copy hash.
]]

local P = ...

local Inspect = P.import("lib/inspect")
local Actions = P.import("lib/actions")
local call = Inspect.call

local Details = {}
Details.__index = Details

local function short(hash: string?): string?
	if type(hash) ~= "string" then
		return nil
	end
	return if #hash > 16 then hash:sub(1, 16) .. "…" else hash
end

-- The facts of a Functions row.
function Details.facts(view, node): { { Text: string, Value: string } }
	local out = {}
	local function add(text: string, value: any)
		if value ~= nil and value ~= "" then
			table.insert(out, { Text = text, Value = tostring(value) })
		end
	end
	if type(node) ~= "table" or node.Value == nil then
		return out
	end
	local value = node.Value
	add("Name", node.Key)
	if typeof(value) == "ProtoProxy" then
		local info = Inspect.protoInfo(value)
		add("Kind", if node.FromCopy then "nested function (in the script's bytecode)" else "nested function prototype")
		add("Source", if info.Source then info.Source .. (if info.Line then ":" .. info.Line else "") else nil)
		add("Parameters", if info.Params then tostring(info.Params) .. (if info.Vararg then " + ..." else "") else nil)
		add("Upvalues", info.Upvalues)
		add("Constants", info.Constants)
		add("Nested functions", info.Nested)
		add("Code hash", info.CodeHash)
		local copies, why = Actions.copiesOf(view, node)
		add("Running copies", if copies then #copies else why)
	elseif type(value) == "function" then
		local isC = Inspect.isC(value)
		local okExec, byExecutor = call("isexecutorclosure", value)
		add("Kind", if isC then "C function" elseif okExec and byExecutor then "made by the executor" else "running function")
		local okInfo, source, line = pcall(debug.info, value, "sl")
		if okInfo and not isC then
			add("Source", tostring(source) .. (if type(line) == "number" and line > 0 then ":" .. line else ""))
		end
		local okGet, info = call("debug.getinfo", value)
		if okGet and type(info) == "table" then
			add("Parameters", if type(info.numparams) == "number" then tostring(info.numparams) .. (if info.is_vararg == 1 or info.is_vararg == true then " + ..." else "") else nil)
			add("Upvalues", info.nups)
		end
		if not isC then
			add("Constants", node.Constants)
			add("Nested functions", node.Nested)
			add("Hash", short(Actions.hashOf(value)))
		end
	end
	add("Path", Actions.pathOf(view, node) or "no path reaches it")
	return out
end

function Details.new(view, parent: Frame)
	local api = view.Api
	local self = setmetatable({ View = view, Facts = {}, Node = nil }, Details)
	local frame = Instance.new("Frame")
	frame.Name = "Details"
	frame.BackgroundTransparency = 1
	frame.Parent = parent
	self.Instance = frame
	self.Title = api.ui.new("Label", { Parent = frame, Name = "Title", Text = "Select a function", Style = "title", Size = UDim2.new(1, 0, 0, 24) })
	self.Title.TextTruncate = Enum.TextTruncate.AtEnd
	-- the buttons first (in view without scrolling), two to a row, then the facts
	local buttons = Instance.new("Frame")
	buttons.Name = "Buttons"
	buttons.BackgroundTransparency = 1
	buttons.Position = UDim2.fromOffset(0, 28)
	buttons.Size = UDim2.new(1, 0, 0, 3 * 32)
	buttons.Parent = frame
	self.Body = api.ui.new("Label", { Parent = frame, Name = "Facts", Text = "", Style = "dim", Position = UDim2.fromOffset(0, 28 + 3 * 32 + 8), Size = UDim2.new(1, 0, 1, -(28 + 3 * 32 + 8)) })
	self.Body.TextWrapped = true
	self.Body.TextYAlignment = Enum.TextYAlignment.Top
	self.Buttons = {}
	local function button(id: string, text: string, icon: string, order: number, onClick)
		local b = api.ui.new("Button", {
			Parent = buttons,
			Name = id,
			Text = text,
			Icon = icon,
			Style = if order == 1 then "accent" else "ghost",
			OnClick = function()
				if self.Node then
					onClick(self.Node)
				end
			end,
		})
		local column, line = (order - 1) % 2, (order - 1) // 2
		b.Instance.Position = UDim2.new(column * 0.5, if column == 1 then 3 else 0, 0, line * 32)
		b.Instance.Size = UDim2.new(0.5, -3, 0, 28)
		self.Buttons[id] = b
		return b
	end
	button("Inspect", "Inspect", "arrow_right", 1, function(node)
		Actions.inspect(view, node, { Tab = "constants" })
	end)
	button("Load", "Load", "arrow_right", 2, function(node)
		Actions.load(view, node)
	end)
	button("Copy", "Running copy…", "arrow_right", 3, function(node)
		Actions.inspectCopy(view, node)
	end)
	button("Variable", "Keep in a variable…", "variable", 4, function(node)
		Actions.setVariable(view, node)
	end)
	button("Path", "Copy path", "copy", 5, function(node)
		local path = Actions.pathOf(view, node)
		if path and pcall(setclipboard, path) then
			api.console.success("copied " .. path)
		end
	end)
	button("Hash", "Copy hash", "copy", 6, function(node)
		local hash = Actions.hashOf(node.Value)
		if hash and pcall(setclipboard, hash) then
			api.console.success("copied " .. hash)
		end
	end)
	self:Show(nil)
	return self
end

function Details:Show(node)
	self.Node = if type(node) == "table" and node.Value ~= nil then node else nil
	local node2 = self.Node
	if not node2 then
		self.Facts = {}
		self.Title.Text = "Select a function"
		self.Body.Text = "Its facts and what you can do with it show here."
		for _, b in self.Buttons do
			b:SetEnabled(false)
		end
		return
	end
	local ok, facts = pcall(Details.facts, self.View, node2)
	self.Facts = if ok then facts else { { Text = "Error", Value = tostring(facts) } }
	self.Title.Text = tostring(node2.Key)
	local lines = {}
	for _, fact in self.Facts do
		table.insert(lines, ("%s: %s"):format(fact.Text, fact.Value))
	end
	self.Body.Text = table.concat(lines, "\n")
	local isProto = typeof(node2.Value) == "ProtoProxy"
	self.Buttons.Inspect:SetEnabled(true)
	self.Buttons.Load:SetEnabled(true)
	self.Buttons.Copy:SetEnabled(isProto)
	self.Buttons.Variable:SetEnabled(true)
	self.Buttons.Path:SetEnabled(Actions.pathOf(self.View, node2) ~= nil)
	self.Buttons.Hash:SetEnabled(Actions.hashOf(node2.Value) ~= nil)
end

return Details
