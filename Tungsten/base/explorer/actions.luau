--[[
	Tungsten · base/explorer/actions
	What the explorer's right-click menu does to objects. Every action
	reports through the explorer's console name ([+] Explorer: …), works
	on the whole selection where that makes sense, and records a /undo
	step when it changes the game.

		Actions.duplicate(list)        Actions.delete(list)     Actions.deleteChildren(list)
		Actions.cut(list) / copy(list) / pasteInto(targets)     -- the explorer's own clipboard
		Actions.clearClipboard() ; clipboardItems() ; clipboardMode()
		Actions.isOnClipboard(obj) -> "cut" | "copy" | nil ; ClipboardChanged
		Actions.clipboardSummary() -> { Mode, Items, Lines } ; showClipboard()   -- /clipboard
		Actions.group(list, "Model")   Actions.ungroup(list)
		Actions.saveToFile(list, path?)                        -- saveinstance
		Actions.decompile(script)      -- (viewing and editing scripts is the scriptviewer prime plugin's job)
		Actions.saveScript(script, path?) ; Actions.saveBytecode(script, path?)
		Actions.dumpFunctions(script)
		Actions.playTween(list)        Actions.loadAnimation(list) ; Actions.stopAnimations()
		Actions.fire(list)             -- ClickDetector, ProximityPrompt, TouchTransmitter
		Actions.selectCharacter(players)
		Actions.watch(list) ; Actions.unwatch(list) ; Actions.isWatched(obj)

	Files go to Tungsten/saved/ unless a path is given (Volt keeps every
	path inside its workspace).
]]

local T = ...
local Types = T.import("base/types")
local Undo = T.import("base/undo")
local Services = T.import("base/services")

local Actions = {}
Actions.SaveFolder = T.Root .. "/saved"
Actions.Clipboard = { Mode = nil :: string?, Items = {} :: { Instance }, HadParent = {} }
Actions.ClipboardChanged = T.import("base/signal").new() -- (mode, items) ; mode nil = cleared

----------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------

local function report(kind: string, text: string, details: { [string]: any }?)
	local Explorer = T.Explorer
	if Explorer and Explorer.report then
		Explorer.report(kind, text, details)
	end
end

local function nameOf(obj: any): string
	local ok, name = pcall(function()
		return obj.Name
	end)
	return if ok then tostring(name) else "?"
end

local function classOf(obj: any): string
	local ok, name = pcall(function()
		return obj.ClassName
	end)
	return if ok then tostring(name) else "?"
end

local function isA(obj: any, className: string): boolean
	local ok, yes = pcall(function()
		return obj:IsA(className)
	end)
	return ok and yes == true
end

local function parentOf(obj: Instance): Instance?
	local ok, parent = pcall(function()
		return obj.Parent
	end)
	return if ok then parent else nil
end

local function plural(count: number, word: string): string
	return ("%d %s%s"):format(count, word, if count == 1 then "" else "s")
end

local describe = Undo.describe -- "Door" or "3 objects"

local function cleanError(err: any): string
	return (tostring(err):gsub("^.-:%d+: ", ""))
end

local function selectLater(list: { Instance })
	local Explorer = T.Explorer
	if not Explorer or #list == 0 then
		return
	end
	Explorer.select(list)
	-- the tree hears about new or moved objects a moment later
	task.defer(function()
		Explorer.select(list)
	end)
end

-- Objects whose ancestor is also in the list are left out (they go
-- along with it).
local function topLevel(list: { Instance }): { Instance }
	local out = {}
	for _, obj in list do
		local inner = false
		for _, other in list do
			if other ~= obj then
				local ok, yes = pcall(function()
					return obj:IsDescendantOf(other)
				end)
				if ok and yes then
					inner = true
					break
				end
			end
		end
		if not inner then
			table.insert(out, obj)
		end
	end
	return out
end
Actions.topLevel = topLevel

local function failures(verb: string, list: { any }, hint: string?)
	if #list == 0 then
		return
	end
	local first = list[1]
	report("error", ("couldn't %s %s: %s"):format(verb, if #list == 1 then first.Name else plural(#list, "object"), first.Error), {
		Hints = { hint or "locked or protected objects can't be changed from here" },
	})
end

local function safeFileName(text: string): string
	local name = text:gsub("[^%w%-_ %.]", "_"):gsub("^%s+", ""):gsub("%s+$", "")
	return if name == "" then "object" else name:sub(1, 60)
end

local function ensureFolder(path: string)
	local folder = path:match("^(.*)/[^/]*$")
	if not folder or folder == "" then
		return
	end
	local built = ""
	for part in folder:gmatch("[^/]+") do
		built = if built == "" then part else built .. "/" .. part
		if not isfolder(built) then
			makefolder(built)
		end
	end
end

-- A free file name in the save folder: "Door.lua", "Door (2).lua", …
function Actions.savePath(base: string, extension: string): string
	local stem = Actions.SaveFolder .. "/" .. safeFileName(base)
	local path = stem .. extension
	local index = 2
	while isfile(path) and index < 1000 do
		path = ("%s (%d)%s"):format(stem, index, extension)
		index += 1
	end
	return path
end

----------------------------------------------------------------------
-- Editing the tree
----------------------------------------------------------------------

-- Clones each object next to the original. Returns the copies.
function Actions.duplicate(list: { Instance }): { Instance }
	local copies, failed = {}, {}
	for _, obj in topLevel(list) do
		local ok, result = pcall(function()
			local copy = obj:Clone()
			if not copy then
				error("it can't be copied (Archivable is off)", 0)
			end
			copy.Parent = obj.Parent
			return copy
		end)
		if ok then
			table.insert(copies, result)
		else
			table.insert(failed, { Name = nameOf(obj), Error = cleanError(result) })
		end
	end
	if #copies > 0 then
		local made = table.clone(copies)
		Undo.record({
			Text = "duplicate " .. describe(made),
			Undo = function()
				for _, copy in made do
					copy.Parent = nil
				end
			end,
		})
		report("success", ("duplicated %s"):format(describe(list)))
		selectLater(copies)
	end
	failures("duplicate", failed)
	return copies
end

--[[
	Deleting takes the objects out of the game (Parent = nil) instead of
	destroying them, so /undo can put them back. They are released when
	the undo step is dropped or Tungsten closes.
]]
function Actions.delete(list: { Instance }): number
	local removed, failed = {}, {}
	for _, obj in topLevel(list) do
		local parent = parentOf(obj)
		local ok, err = pcall(function()
			obj.Parent = nil
		end)
		if ok then
			table.insert(removed, { Object = obj, Parent = parent })
		else
			table.insert(failed, { Name = nameOf(obj), Error = cleanError(err) })
		end
	end
	if #removed > 0 then
		local objects = {}
		for _, entry in removed do
			table.insert(objects, entry.Object)
		end
		Undo.record({
			Text = "delete " .. describe(objects),
			Undo = function()
				for _, entry in removed do
					entry.Object.Parent = entry.Parent
				end
			end,
		})
		report("success", ("deleted %s"):format(describe(objects)))
	end
	failures("delete", failed)
	return #removed
end

function Actions.deleteChildren(list: { Instance }): number
	local children = {}
	for _, obj in list do
		local ok, kids = pcall(function()
			return obj:GetChildren()
		end)
		if ok then
			for _, child in kids do
				table.insert(children, child)
			end
		end
	end
	if #children == 0 then
		report("info", "nothing to delete · no children")
		return 0
	end
	return Actions.delete(children)
end

----------------------------------------------------------------------
-- The explorer's clipboard (Cut / Copy / Paste Into)
----------------------------------------------------------------------

local function setClipboard(mode: string?, items: { Instance })
	local hadParent = {}
	for _, obj in items do
		hadParent[obj] = parentOf(obj) ~= nil
	end
	Actions.Clipboard = { Mode = mode, Items = items, HadParent = hadParent }
	Actions.ClipboardChanged:Fire(mode, table.clone(items))
end

-- What is on the clipboard and still there: objects deleted since they
-- were cut or copied are left out (and come back if the delete is undone).
-- Objects that were already outside the game (nil) when copied stay.
function Actions.clipboardItems(): { Instance }
	local clip = Actions.Clipboard
	local items = {}
	for _, obj in clip.Items do
		if parentOf(obj) ~= nil or clip.HadParent[obj] == false then
			table.insert(items, obj)
		end
	end
	return items
end

function Actions.clipboardMode(): string?
	return if Actions.hasClipboard() then Actions.Clipboard.Mode else nil
end

function Actions.hasClipboard(): boolean
	return Actions.Clipboard.Mode ~= nil and #Actions.clipboardItems() > 0
end

-- "cut" / "copy" when this object is on the clipboard.
function Actions.isOnClipboard(obj: Instance): string?
	local clip = Actions.Clipboard
	if clip.Mode and table.find(clip.Items, obj) then
		return clip.Mode
	end
	return nil
end

function Actions.copy(list: { Instance })
	setClipboard("copy", topLevel(list))
	report("success", ("copied %s · Paste Into puts a copy inside another object"):format(describe(list)))
end

function Actions.cut(list: { Instance })
	local movable = {}
	for _, obj in topLevel(list) do
		if not (T.Explorer and T.Explorer.isFixed(obj)) then
			table.insert(movable, obj)
		end
	end
	if #movable == 0 then
		report("warn", "datamodels cannot be moved")
		return
	end
	setClipboard("cut", movable)
	report("success", ("cut %s · Paste Into moves it inside another object"):format(describe(list)))
end

-- Empties the clipboard. Cut objects stay where they are. Returns how
-- many objects were on it; `quiet` skips the console line.
function Actions.clearClipboard(quiet: boolean?): number
	local had = Actions.clipboardItems()
	local mode = Actions.Clipboard.Mode
	local wasSet = mode ~= nil
	Actions.Clipboard = { Mode = nil, Items = {}, HadParent = {} }
	if wasSet then
		Actions.ClipboardChanged:Fire(nil, {})
	end
	if not quiet then
		if #had == 0 then
			report("info", "the clipboard is already empty")
		else
			report("success", ("clipboard cleared · %s no longer %s"):format(describe(had), if mode == "cut" then "cut (it stays where it is)" else "copied"))
		end
	end
	return #had
end

-- What is on the clipboard, as lines for the console: a heading and one
-- line per object (deleted ones are noted and left out of Items).
function Actions.clipboardSummary()
	local clip = Actions.Clipboard
	local items = Actions.clipboardItems()
	local summary = { Mode = if #items > 0 then clip.Mode else nil, Items = items, Lines = {} }
	if clip.Mode == nil then
		summary.Heading = "the clipboard is empty · Cut (Ctrl+X) or Copy (Ctrl+C) objects in the explorer, or /clipboard cut | copy"
		return summary
	end
	if #items == 0 then
		summary.Heading = "the clipboard is empty · what was on it has been deleted"
	elseif clip.Mode == "cut" then
		summary.Heading = ("clipboard · cut · %s · Paste Into (Ctrl+V) moves %s"):format(plural(#items, "object"), if #items == 1 then "it" else "them")
	else
		summary.Heading = ("clipboard · copied · %s · Paste Into (Ctrl+V) puts a copy inside another object"):format(plural(#items, "object"))
	end
	for _, obj in clip.Items do
		local line = ("%s  (%s)"):format(Types.path(obj), classOf(obj))
		if parentOf(obj) == nil then
			line ..= if clip.HadParent[obj] == false then " · outside the game (nil)" else " · deleted since, left out"
		end
		table.insert(summary.Lines, line)
	end
	return summary
end

-- Prints the clipboard to the console (Object › Show Clipboard).
function Actions.showClipboard(): { Instance }
	local summary = Actions.clipboardSummary()
	report("info", summary.Heading)
	local reporter = T.Explorer and T.Explorer.reporter and T.Explorer.reporter()
	if reporter then
		for _, line in summary.Lines do
			reporter:detail(line)
		end
	end
	return summary.Items
end

-- Copies (or moves, after Cut) the clipboard into each target.
function Actions.pasteInto(targets: { Instance }): { Instance }
	local clip = Actions.Clipboard
	local items = Actions.clipboardItems()
	if clip.Mode == nil or #items == 0 then
		report("warn", if clip.Mode then "nothing to paste · what was on the clipboard has been deleted" else "nothing to paste · Cut or Copy something first")
		return {}
	end
	if #targets == 0 then
		report("warn", "select where to paste first")
		return {}
	end
	if clip.Mode == "cut" then
		local moved = T.Explorer.moveInto(items, targets[1])
		if #moved > 0 then
			Actions.clearClipboard(true) -- moved once; the clipboard empties
		end
		return moved
	end
	local pasted, failed = {}, {}
	for _, target in targets do
		for _, obj in items do
			local ok, result = pcall(function()
				local copy = obj:Clone()
				if not copy then
					error("it can't be copied (Archivable is off)", 0)
				end
				copy.Parent = target
				return copy
			end)
			if ok then
				table.insert(pasted, result)
			else
				table.insert(failed, { Name = nameOf(obj), Error = cleanError(result) })
			end
		end
	end
	if #pasted > 0 then
		local made = table.clone(pasted)
		Undo.record({
			Text = ("paste %s into %s"):format(describe(items), describe(targets)),
			Undo = function()
				for _, copy in made do
					copy.Parent = nil
				end
			end,
		})
		report("success", ("pasted %s into %s"):format(describe(items), if #targets == 1 then Types.path(targets[1]) else plural(#targets, "object")))
		selectLater(pasted)
	end
	failures("paste", failed)
	return pasted
end

----------------------------------------------------------------------
-- Group / Ungroup
----------------------------------------------------------------------

-- Puts the objects in a new Model (or Folder) where the first one was.
function Actions.group(list: { Instance }, className: string?): Instance?
	local items = topLevel(list)
	if #items == 0 then
		return nil
	end
	local parent = parentOf(items[1])
	if not parent then
		report("warn", "objects without a parent can't be grouped")
		return nil
	end
	local kind = className or "Model"
	local okNew, group = pcall(Instance.new, kind)
	if not okNew then
		report("error", ("couldn't make a %s: %s"):format(kind, cleanError(group)))
		return nil
	end
	group.Name = kind
	local moved, failed = {}, {}
	for _, obj in items do
		local old = parentOf(obj)
		local ok, err = pcall(function()
			obj.Parent = group
		end)
		if ok then
			table.insert(moved, { Object = obj, Parent = old })
		else
			table.insert(failed, { Name = nameOf(obj), Error = cleanError(err) })
		end
	end
	if #moved == 0 then
		group:Destroy()
		failures("group", failed)
		return nil
	end
	group.Parent = parent
	Undo.record({
		Text = ("group %s"):format(plural(#moved, "object")),
		Undo = function()
			for _, entry in moved do
				entry.Object.Parent = entry.Parent
			end
			group.Parent = nil
		end,
	})
	report("success", ("grouped %s into a %s"):format(plural(#moved, "object"), kind))
	failures("group", failed)
	selectLater({ group })
	return group
end

function Actions.canUngroup(obj: Instance): boolean
	return isA(obj, "Model") or isA(obj, "Folder")
end

-- Moves the children of each Model / Folder to its parent and removes it.
function Actions.ungroup(list: { Instance }): { Instance }
	local freed, steps = {}, {}
	for _, group in list do
		local parent = parentOf(group)
		if Actions.canUngroup(group) and parent then
			local ok, children = pcall(function()
				return group:GetChildren()
			end)
			if ok then
				for _, child in children do
					if pcall(function()
						child.Parent = parent
					end) then
						table.insert(freed, child)
						table.insert(steps, { Object = child, Parent = group })
					end
				end
				if pcall(function()
					group.Parent = nil
				end) then
					table.insert(steps, { Object = group, Parent = parent, Group = true })
				end
			end
		end
	end
	if #steps == 0 then
		report("warn", "only Models and Folders can be ungrouped")
		return {}
	end
	Undo.record({
		Text = "ungroup " .. describe(list),
		Undo = function()
			-- groups first, then their children back inside
			for _, step in steps do
				if step.Group then
					step.Object.Parent = step.Parent
				end
			end
			for _, step in steps do
				if not step.Group then
					step.Object.Parent = step.Parent
				end
			end
		end,
	})
	report("success", ("ungrouped %s · %s moved up"):format(describe(list), plural(#freed, "object")))
	selectLater(freed)
	return freed
end



----------------------------------------------------------------------
-- Saving to files
----------------------------------------------------------------------

-- saveinstance (Volt): one object → <Name>.rbxm, several → one file.
function Actions.saveToFile(list: { Instance }, path: string?): string?
	if #list == 0 then
		return nil
	end
	local target = path or Actions.savePath(if #list == 1 then nameOf(list[1]) else "objects", ".rbxm")
	local ok, err = pcall(function()
		ensureFolder(target)
		local options = SaveInstanceOptions.new()
		options.FilePath = target
		saveinstance(if #list == 1 then list[1] else list, options)
	end)
	if not ok then
		report("error", ("couldn't save %s: %s"):format(describe(list), cleanError(err)))
		return nil
	end
	report("success", ("saved %s to %s"):format(describe(list), target))
	return target
end

function Actions.isScript(obj: any): boolean
	return isA(obj, "LuaSourceContainer")
end

-- decompile (Volt; yields). Returns ok, source or reason.
function Actions.decompile(script: Instance): (boolean, string)
	if not Actions.isScript(script) then
		return false, ("%s isn't a script"):format(nameOf(script))
	end
	local ok, result = pcall(decompile, script)
	if not ok then
		return false, cleanError(result)
	end
	return true, tostring(result)
end

function Actions.saveScript(script: Instance, path: string?): string?
	local ok, source = Actions.decompile(script)
	if not ok then
		report("error", ("couldn't decompile %s: %s"):format(nameOf(script), source))
		return nil
	end
	local target = path or Actions.savePath(nameOf(script), ".lua")
	local okWrite, err = pcall(function()
		ensureFolder(target)
		writefile(target, ("-- %s\n-- decompiled by tungsten (unified)\n\n%s"):format(Types.path(script), source))
	end)
	if not okWrite then
		report("error", ("couldn't write %s: %s"):format(target, cleanError(err)))
		return nil
	end
	report("success", ("saved the source of %s to %s"):format(nameOf(script), target))
	return target
end

function Actions.saveBytecode(script: Instance, path: string?): string?
	local ok, bytecode = pcall(getscriptbytecode, script)
	if not ok then
		report("error", ("couldn't read the bytecode of %s: %s"):format(nameOf(script), cleanError(bytecode)))
		return nil
	end
	local target = path or Actions.savePath(nameOf(script), ".luac")
	local okWrite, err = pcall(function()
		ensureFolder(target)
		writefile(target, bytecode)
	end)
	if not okWrite then
		report("error", ("couldn't write %s: %s"):format(target, cleanError(err)))
		return nil
	end
	report("success", ("saved %d bytes of bytecode from %s to %s"):format(#bytecode, nameOf(script), target))
	return target
end

-- The functions inside a script: its main function's nested functions
-- (getscriptclosure + debug.getprotos/getinfo), as a tree.
function Actions.dumpFunctions(script: Instance): { any }?
	local ok, closure = pcall(getscriptclosure, script)
	if not ok or type(closure) ~= "function" then
		report("error", ("couldn't read the functions of %s: %s"):format(nameOf(script), if ok then tostring(closure) else cleanError(closure)))
		return nil
	end
	local list = {}
	local function walk(fn, depth: number)
		local okProtos, protos = pcall(debug.getprotos, fn)
		if not okProtos or type(protos) ~= "table" then
			return
		end
		for _, proto in protos do
			local okInfo, info = pcall(debug.getinfo, proto)
			info = if okInfo and type(info) == "table" then info else {}
			local params = tonumber(info.numparams) or 0
			local names = {}
			for index = 1, params do
				names[index] = "a" .. index
			end
			if info.is_vararg == 1 or info.is_vararg == true then
				table.insert(names, "...")
			end
			local name = if type(info.name) == "string" and info.name ~= "" then info.name else "(anonymous)"
			table.insert(list, { Name = name, Depth = depth, Signature = ("%s(%s)"):format(name, table.concat(names, ", ")), Upvalues = tonumber(info.nups) or 0 })
			walk(proto, depth + 1)
		end
	end
	walk(closure, 0)
	local Console = T.Console
	if Console then
		Console.info(("%s · %s"):format(Types.path(script), plural(#list, "function")))
		for _, item in list do
			Console.detail({
				{ Text = string.rep("  ", item.Depth + 1) .. "function ", Color = "TextMuted" },
				{ Text = item.Signature, Color = "Text" },
				{ Text = if item.Upvalues > 0 then ("  · %d upvalue%s"):format(item.Upvalues, if item.Upvalues == 1 then "" else "s") else "", Color = "TextMuted" },
			})
		end
	end
	return list
end

----------------------------------------------------------------------
-- Gameplay
----------------------------------------------------------------------

local function localPlayer(): Player?
	return Services.Players and Services.Players.LocalPlayer
end

local function characterOf(player: Player?): Model?
	if not player then
		return nil
	end
	local ok, character = pcall(function()
		return player.Character
	end)
	return if ok then character else nil
end

local function humanoidOf(model: Instance?): Humanoid?
	if not model then
		return nil
	end
	local ok, humanoid = pcall(function()
		return model:FindFirstChildOfClass("Humanoid")
	end)
	return if ok then humanoid else nil
end

function Actions.playTween(list: { Instance }): number
	local played = 0
	for _, obj in list do
		if isA(obj, "Tween") and pcall(function()
			(obj :: any):Play()
		end) then
			played += 1
		end
	end
	if played > 0 then
		report("success", ("playing %s"):format(plural(played, "tween")))
	else
		report("warn", "nothing to play · pick a Tween")
	end
	return played
end

local tracks: { AnimationTrack } = {}

function Actions.loadAnimation(list: { Instance }): number
	local humanoid = humanoidOf(characterOf(localPlayer()))
	if not humanoid then
		report("warn", "your character has no Humanoid to animate")
		return 0
	end
	local animator = humanoid:FindFirstChildOfClass("Animator")
	local loaded = 0
	for _, obj in list do
		if isA(obj, "Animation") then
			local ok, track = pcall(function()
				return (animator or humanoid :: any):LoadAnimation(obj)
			end)
			if ok and track then
				pcall(function()
					track:Play()
				end)
				table.insert(tracks, track)
				loaded += 1
			else
				report("error", ("couldn't load %s: %s"):format(nameOf(obj), cleanError(track)))
			end
		end
	end
	if loaded > 0 then
		report("success", ("playing %s on your character · Stop Animations stops them"):format(plural(loaded, "animation")))
	end
	return loaded
end

function Actions.playingAnimations(): number
	return #tracks
end

function Actions.stopAnimations(): number
	local count = #tracks
	for _, track in tracks do
		pcall(function()
			track:Stop()
		end)
	end
	table.clear(tracks)
	if count > 0 then
		report("success", ("stopped %s"):format(plural(count, "animation")))
	end
	return count
end

function Actions.canFire(obj: Instance): boolean
	return isA(obj, "ClickDetector") or isA(obj, "ProximityPrompt") or isA(obj, "TouchTransmitter")
end

-- fireclickdetector / fireproximityprompt / firetouchinterest (Volt).
function Actions.fire(list: { Instance }): number
	local fired, failed = 0, {}
	for _, obj in list do
		local ok, err = true, nil
		if isA(obj, "ClickDetector") then
			ok, err = pcall(fireclickdetector, obj)
		elseif isA(obj, "ProximityPrompt") then
			ok, err = pcall(fireproximityprompt, obj)
		elseif isA(obj, "TouchTransmitter") then
			local part = parentOf(obj)
			local character = characterOf(localPlayer())
			local root = character and (character:FindFirstChild("HumanoidRootPart") or character:FindFirstChildWhichIsA("BasePart"))
			if not (part and isA(part, "BasePart") and root) then
				ok, err = false, "needs your character and the part the TouchInterest is in"
			else
				ok, err = pcall(firetouchinterest, root, part, 0)
				if ok then
					task.spawn(function()
						task.wait()
						pcall(firetouchinterest, root, part, 1)
					end)
				end
			end
		else
			continue
		end
		if ok then
			fired += 1
		else
			table.insert(failed, { Name = nameOf(obj), Error = cleanError(err) })
		end
	end
	if fired > 0 then
		report("success", ("fired %s"):format(plural(fired, "object")))
	end
	failures("fire", failed, "only ClickDetectors, ProximityPrompts and TouchInterests can be fired")
	return fired
end

----------------------------------------------------------------------
-- Players
----------------------------------------------------------------------

function Actions.selectCharacter(players: { Instance }): number
	local list = {}
	for _, player in players do
		local character = if isA(player, "Player") then characterOf(player :: any) else nil
		if character then
			table.insert(list, character)
		end
	end
	if #list == 0 then
		report("warn", "no character to select")
		return 0
	end
	T.Explorer.select(list)
	return #list
end




----------------------------------------------------------------------
-- Watching objects (Variable › Watch)
----------------------------------------------------------------------

local watches: { [Instance]: RBXScriptConnection } = {}

function Actions.isWatched(obj: Instance): boolean
	return watches[obj] ~= nil
end

-- Prints a [$] line whenever a property of the object changes.
function Actions.watch(list: { Instance }): number
	local added = 0
	for _, obj in list do
		if not watches[obj] then
			local ok, connection = pcall(function()
				return obj.Changed:Connect(function(property)
					local Console = T.Console
					if not Console then
						return
					end
					local okValue, value = pcall(function()
						return (obj :: any)[property]
					end)
					Console.write("var", {
						{ Text = nameOf(obj) .. "." .. tostring(property), Color = "Text" },
						{ Text = " = ", Color = "TextMuted" },
						{ Text = if okValue then Types.short(value, 60) else "?", Color = "Text" },
					})
				end)
			end)
			if ok then
				watches[obj] = connection
				added += 1
			end
		end
	end
	if added > 0 then
		report("success", ("watching %s · property changes print here"):format(describe(list)))
	end
	return added
end

function Actions.unwatch(list: { Instance }?): number
	local removed = 0
	for obj, connection in table.clone(watches) do
		if list == nil or table.find(list, obj) then
			connection:Disconnect()
			watches[obj] = nil
			removed += 1
		end
	end
	if removed > 0 then
		report("success", ("stopped watching %s"):format(plural(removed, "object")))
	end
	return removed
end

T.Bin:Add(function()
	for _, connection in watches do
		pcall(function()
			connection:Disconnect()
		end)
	end
	table.clear(watches)
	for _, track in tracks do
		pcall(function()
			track:Stop()
		end)
	end
	table.clear(tracks)
	Actions.Clipboard = { Mode = nil, Items = {}, HadParent = {} }
	Actions.ClipboardChanged:DisconnectAll()
end)

return Actions
