--[[
	Tungsten
	Main loader — the only file you execute.

	Everything is loaded from the local Tungsten folder in Volt's
	workspace; nothing is downloaded. Running this again shuts the
	previous copy down first.
]]

local ROOT = "Tungsten"
local VERSION = "0.4.0"

local genv = getgenv()

----------------------------------------------------------------------
-- Replace a previous run
----------------------------------------------------------------------
local previous = genv.Tungsten
if type(previous) == "table" and type(previous.Shutdown) == "function" then
	local ok, err = pcall(previous.Shutdown, "replaced by a new run")
	if not ok then
		warn("[Tungsten] previous copy did not shut down cleanly: " .. tostring(err))
	end
end
genv.Tungsten = nil

----------------------------------------------------------------------
-- Importer
----------------------------------------------------------------------
local IMPORTER = ROOT .. "/base/import.luau"
if not isfile(IMPORTER) then
	error(("[Tungsten] %s not found. Put the Tungsten folder inside Volt's workspace folder."):format(IMPORTER), 0)
end

local importerChunk, compileError = loadfile(IMPORTER)
if not importerChunk then
	error("[Tungsten] could not compile the importer: " .. tostring(compileError), 0)
end

local T = {
	Root = ROOT,
	Version = VERSION,
}
T.import = importerChunk()(ROOT, T)

local signal = T.import("base/signal")
T.Bin = signal.bin()

local Log = T.import("base/logger")
T.Log = Log
Log.start()
Log.info("core", ("Tungsten %s starting"):format(VERSION))

----------------------------------------------------------------------
-- Shutdown
----------------------------------------------------------------------
local handle
local alive = true

local function shutdown(reason: string?)
	if not alive then
		return
	end
	alive = false
	Log.info("core", "shutting down: " .. tostring(reason or "requested"))
	-- Plugins first (newest first), while everything they use still exists.
	if T.Plugins and T.Plugins.started() then
		local ok, err = pcall(T.Plugins.stop)
		if not ok then
			Log.error("core", "stopping plugins failed: " .. tostring(err))
		end
	end
	T.Bin:Clean()
	Log.close()
	if genv.Tungsten == handle then
		genv.Tungsten = nil
	end
end
T.Shutdown = shutdown

-- Registered at once, so running Tungsten again while this copy is still
-- on its splash screen shuts this one down.
handle = {
	Version = VERSION,
	Shutdown = shutdown,
	Context = T,
}
genv.Tungsten = handle

----------------------------------------------------------------------
-- Start-up
----------------------------------------------------------------------
local started = os.clock()

local ok, err = xpcall(function()
	T.Settings = T.import("base/settings")
	T.Settings.load()

	T.Services = T.import("base/services")
	T.Theme = T.import("base/theme")
	T.Scale = T.import("base/scale")
	T.Registry = T.import("base/registry")
	T.Access = T.import("base/access") -- how a value inside a script is reached (require(...).a.b)
	T.Loaded = T.import("base/loaded") -- the one loaded target every tab works on
	T.Icons = T.import("base/data/icons")

	-- Splash screen first: the brand icon, the name and a progress bar
	-- that fills over 3 seconds. Everything else loads behind it and
	-- appears only when it is done.
	local loading = T.import("base/ui/loading").show()
	T.Loading = loading
	T.Types = T.import("base/types")
	T.Variables = T.import("base/variables")
	T.Undo = T.import("base/undo") -- /undo: what Tungsten changed, newest last
	-- tungsten.api("myplugin") -> what a plugin works with (base/api)
	T.api = function(id: string, opts: { [string]: any }?)
		return T.import("base/api").new(id, opts)
	end

	-- Console logic first: commands load and lines collect even before
	-- the Console tab is opened.
	T.Console = T.import("console/core")
	T.Console.start()

	local Window = T.import("base/ui/window")
	T.Window = T.Bin:Add(Window.new({ SideOpen = T.Settings.get("ExplorerOpen") ~= false }))

	-- Top layer for menus and dropdowns.
	T.Overlay = T.import("base/ui/overlay")
	T.Overlay.start(T.Window, Window.randomName())
	-- Menu framework: every right-click / button menu is a named menu.
	T.Menus = T.import("base/ui/menus")
	-- UI framework: components register here; plugins hook and filter them.
	T.UI = T.import("base/ui/ui")
	-- Components that own a named menu define it when loaded; load them
	-- now so the menus exist (and can be extended) before first use.
	for _, component in { "button", "toggle", "input", "label", "dropdown", "typepicker", "list", "celleditor", "texteditor", "scroll", "contextmenu", "colorpicker", "sequenceeditor", "tooltip", "prompt", "notify", "subtabs", "page" } do
		T.import("base/ui/components/" .. component)
	end

	T.Prompt = T.import("base/ui/components/prompt") -- dialogs (confirm, input, choice, form)
	T.Notify = T.import("base/ui/components/notify") -- toasts
	T.Docs = T.import("documentation/docs") -- documentation registry (plugins add topics)
	T.Preferences = T.import("base/preferences") -- every setting (Plugins › tungsten)

	local TabBar = T.import("base/ui/tabbar")
	T.Tabs = T.Bin:Add(TabBar.new(T.Window))
	T.Overlay.watchTabs(T.Tabs)

	for _, path in { "console/console", "documentation/documentation", "plugins/manager" } do
		T.Registry.addTab(T.import(path))
	end

	-- Explorer on the window's right edge (Tungsten's own UI is left out
	-- of its tree), then the path bar that follows its selection.
	T.Explorer = T.import("base/explorer/explorer")
	T.Editors = T.import("base/explorer/editors") -- property editors (plugins add their own)
	-- The command bar (' by default): its own ScreenGui, apart from the window.
	T.CommandBar = T.import("base/ui/commandbar") -- its key works once the splash is done
	T.Explorer.start(T.Window, { T.Window.Gui, T.Overlay.gui(), T.CommandBar.gui() })
	T.PathBar = T.import("base/ui/pathbar")
	T.PathBar.start(T.Window, T.Explorer, T.Tabs)

	-- Plugins (Tungsten/plugins): after the explorer and the path bar,
	-- before the splash ends. Their load time is counted apart.
	T.Plugins = T.import("base/plugins")
	local pluginsStarted = os.clock()
	T.Plugins.start()
	T.PluginLoadTime = os.clock() - pluginsStarted
	-- the Plugins tab lists them (and its badge counts the ones that didn't start)
	T.Manager.attachHost(T.Plugins)
	if not alive then
		return -- replaced by a newer run while plugins loaded
	end

	-- Always start on the console (the open tab isn't remembered).
	T.Tabs:Select("console")

	T.import("base/ui/components/tooltip").watchWindow(T.Window)
	-- How long loading took (the splash time and plugins aren't counted).
	T.LoadTime = os.clock() - started - (T.PluginLoadTime or 0)
	-- Hold everything back until the splash has had its 3 seconds.
	loading:Wait()
	if not alive then
		return -- replaced by a newer run during the splash
	end
	loading:Finish()
	T.CommandBar.start()
	T.Window:Open()
	T.Console.welcome({ LoadTime = T.LoadTime, PluginLoadTime = T.PluginLoadTime })
end, debug.traceback)

if not ok then
	Log.error("core", "start-up failed:\n" .. tostring(err))
	shutdown("start-up failure")
	error("[Tungsten] start-up failed: " .. tostring(err), 0)
end

if not alive then
	return
end

Log.info("core", ("ready in %.0f ms"):format((os.clock() - started) * 1000))
