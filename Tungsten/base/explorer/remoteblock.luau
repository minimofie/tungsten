--[[
	Tungsten · base/explorer/remoteblock
	Block / Unblock for remotes and bindables (Object › Block remote).

	One shared __namecall hook (hookmetamethod on game, Volt) covers
	RemoteEvent, RemoteFunction, UnreliableRemoteEvent, BindableEvent and
	BindableFunction: a game script calling FireServer / InvokeServer /
	Fire / Invoke on a blocked object gets nothing back and the call goes
	nowhere. Your own calls (checkcaller) still go through.

	The hook is installed once per game session and kept in getgenv, so
	running Tungsten again reuses it instead of stacking a second one.
	Closing Tungsten unblocks everything (the hook then just passes calls
	on).

		RemoteBlock.block(remote) ; RemoteBlock.unblock(remote)
		RemoteBlock.isBlocked(remote) ; RemoteBlock.stopped(remote) -> calls stopped
		RemoteBlock.list() ; RemoteBlock.unblockAll()
		RemoteBlock.canBlock(obj)
]]

local T = ...

local RemoteBlock = {}

local STATE_KEY = "TungstenRemoteBlock"
local CLASSES = { "RemoteEvent", "RemoteFunction", "UnreliableRemoteEvent", "BindableEvent", "BindableFunction" }
local METHODS = { FireServer = true, InvokeServer = true, Fire = true, Invoke = true }

-- Shared with the hook through getgenv (survives re-runs).
local function state()
	local genv = getgenv()
	local current = genv[STATE_KEY]
	if type(current) ~= "table" then
		current = { Installed = false, List = {}, Stopped = {} }
		genv[STATE_KEY] = current
	end
	return current
end

local function same(a: Instance, b: Instance): boolean
	if a == b then
		return true
	end
	local ok, yes = pcall(compareinstances, a, b)
	return ok and yes == true
end

local function indexOf(list: { Instance }, obj: Instance): number?
	for index, item in list do
		if same(item, obj) then
			return index
		end
	end
	return nil
end

function RemoteBlock.canBlock(obj: any): boolean
	for _, className in CLASSES do
		local ok, yes = pcall(function()
			return obj:IsA(className)
		end)
		if ok and yes then
			return true
		end
	end
	return false
end

local function install()
	local st = state()
	if st.Installed then
		return true
	end
	local original
	local ok, err = pcall(function()
		original = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
			local shared = getgenv()[STATE_KEY]
			if shared and #shared.List > 0 and not checkcaller() then
				local method = getnamecallmethod()
				if method and METHODS[method] and typeof(self) == "Instance" then
					for index, item in shared.List do
						if item == self or compareinstances(item, self) then
							shared.Stopped[index] = (shared.Stopped[index] or 0) + 1
							return nil
						end
					end
				end
			end
			return original(self, ...)
		end))
	end)
	if not ok then
		return false, tostring(err)
	end
	st.Installed = true
	return true
end

function RemoteBlock.block(obj: Instance): (boolean, string?)
	if not RemoteBlock.canBlock(obj) then
		return false, "only remotes and bindables can be blocked"
	end
	local st = state()
	if indexOf(st.List, obj) then
		return true
	end
	local ok, err = install()
	if not ok then
		return false, err
	end
	table.insert(st.List, obj)
	st.Stopped[#st.List] = 0
	return true
end

function RemoteBlock.unblock(obj: Instance): boolean
	local st = state()
	local index = indexOf(st.List, obj)
	if not index then
		return false
	end
	table.remove(st.List, index)
	table.remove(st.Stopped, index)
	return true
end

function RemoteBlock.isBlocked(obj: Instance): boolean
	return indexOf(state().List, obj) ~= nil
end

-- How many calls were stopped since it was blocked.
function RemoteBlock.stopped(obj: Instance): number
	local st = state()
	local index = indexOf(st.List, obj)
	return if index then st.Stopped[index] or 0 else 0
end

function RemoteBlock.list(): { Instance }
	return table.clone(state().List)
end

function RemoteBlock.unblockAll(): number
	local st = state()
	local count = #st.List
	table.clear(st.List)
	table.clear(st.Stopped)
	return count
end

-- Closing Tungsten undoes every block (the hook stays as a pass-through).
T.Bin:Add(function()
	pcall(RemoteBlock.unblockAll)
end)

return RemoteBlock
