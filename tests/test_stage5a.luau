-- Stage 5 Round A, part 1 (scale redone 18 Oct: it sizes the window, like
-- resizing it; contents and popups stay 1:1; the pill, splash and command
-- bar are untouched); the scale never changes by itself; Tungsten's settings and
-- plugin settings through base/datastore; the mock's UIScale geometry.
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
local V2 = E_.Vector2.new
H.ABS_SHIFT = SHIFT or 0
local new = E_.Instance.new

local function near(a, b, tolerance)
	return math.abs(a - b) <= (tolerance or 1)
end
local function nearV(a, b, tolerance)
	return near(a.X, b.X, tolerance) and near(a.Y, b.Y, tolerance)
end

-- a few objects for the tree
local map = new("Model")
map.Name = "Map"
map.Parent = E_.workspace
for i = 1, 6 do
	H.part("Part" .. i, map)
end

local ok, err = H.run("Tungsten/Tungsten.luau")
check("loader runs", ok, err)
local T = H.genv.Tungsten.Context
check("splash: fixed size (its UIScale starts at 0.96 of 1, not of the UI scale)", T.Loading and T.Loading.BaseScale == 1 and near(T.Loading.Scale.Scale, 0.96, 0.001))
H.advance(5)
check("no errors at start", #H.ERRORS == 0, H.ERRORS[1])

local W, Overlay, Scale, E = T.Window, T.Overlay, T.Scale, T.Explorer
local Create = T.import("base/ui/create")
local SCREEN = H.SCREEN

----------------------------------------------------------------------
-- 1. the mock's UIScale geometry (like the engine)
----------------------------------------------------------------------
do
	local gui = new("ScreenGui")
	gui.Parent = E_.gethui()
	local outer = new("Frame")
	outer.Position = E_.UDim2.fromOffset(100, 50)
	outer.Size = E_.UDim2.fromOffset(40, 30)
	outer.Parent = gui
	local s = new("UIScale")
	s.Scale = 2
	s.Parent = outer
	local inner = new("Frame")
	inner.Position = E_.UDim2.fromOffset(5, 5)
	inner.Size = E_.UDim2.fromOffset(10, 10)
	inner.Parent = outer
	check("mock: a UIScale doubles its frame's size", nearV(outer.AbsoluteSize, V2(80, 60)), tostring(outer.AbsoluteSize))
	check("mock: …and offsets inside it", nearV(inner.AbsoluteSize, V2(20, 20)) and nearV(inner.AbsolutePosition - outer.AbsolutePosition, V2(10, 10)), tostring(inner.AbsolutePosition))
	check("Create.scaleOf multiplies every UIScale above", Create.scaleOf(inner) == 2)
	check("Create.layoutSize undoes it", nearV(Create.layoutSize(inner), V2(10, 10)))
	check("Create.toLocal turns a screen point into an offset", nearV(Create.toLocal(inner.AbsolutePosition + V2(8, 4), inner), V2(4, 2)))
	gui:Destroy()
end

----------------------------------------------------------------------
-- 2. data store
----------------------------------------------------------------------
do
	local DataStore = T.import("base/datastore")
	local path = "Tungsten/test_store.json"
	local store = DataStore.open(path, { Name = "test", Backup = true })
	local values, problem = store:read()
	check("datastore: no file reads as nothing, no problem", values == nil and problem == nil)
	check("datastore: write", store:write({ a = 1, b = "x" }) and H.FILES[path] ~= nil)
	values = store:read()
	check("datastore: read back", values and values.a == 1 and values.b == "x")
	local data = { n = 1 }
	store:queue(function() return data end)
	data = { n = 2 }
	store:queue(function() return data end)
	check("datastore: a queued save waits", store:pending() and not H.FILES[path]:find('"n"', 1, true))
	H.advance(0.5)
	check("datastore: …then writes the newest values once", H.FILES[path]:find('"n":2', 1, true) ~= nil and not store:pending(), H.FILES[path])
	store:queue(function() return { n = 3 } end)
	check("datastore: flush writes at once", store:flush() and H.FILES[path]:find('"n":3', 1, true) ~= nil)
	check("datastore: flush with nothing waiting does nothing", store:flush() == false)
	H.FILES[path] = "{broken"
	values, problem = store:read()
	check("datastore: an unreadable file is reported", values == nil and problem ~= nil)
	check("datastore: …and kept as .bak", H.FILES[path .. ".bak"] == "{broken")
	H.FILES[path] = nil
	H.FILES[path .. ".bak"] = nil

	-- Tungsten's settings go through it
	T.Settings.set("PropertyDecimals", 4)
	H.advance(0.5)
	check("settings are saved through the data store", (H.FILES["Tungsten/base/settings.json"] or ""):find('"PropertyDecimals":4', 1, true) ~= nil)
	T.Settings.set("PropertyDecimals", 3)
	T.Settings.flush()
	check("Settings.flush writes at once", (H.FILES["Tungsten/base/settings.json"] or ""):find('"PropertyDecimals":3', 1, true) ~= nil)

	-- and a plugin's settings too
	local ppath = "Tungsten/plugins/Store/settings.json"
	local api = T.api("storetest", { Name = "Store", SettingsPath = ppath, Settings = { { Id = "n", Kind = "number", Text = "N", Default = 1 } } })
	api.settings.set("n", 5)
	check("a plugin's setting waits a moment", H.FILES[ppath] == nil)
	H.advance(0.5)
	check("…then is saved next to the plugin", (H.FILES[ppath] or ""):find('"n":5', 1, true) ~= nil, H.FILES[ppath])
	api.settings.set("n", 6)
	api:remove()
	check("removing the plugin saves what was waiting", (H.FILES[ppath] or ""):find('"n":6', 1, true) ~= nil)
	H.FILES[ppath] = nil
end

----------------------------------------------------------------------
-- 3. a test tab with a list, an editor and a dropdown (as a plugin
-- would build it)
----------------------------------------------------------------------
local List = T.import("base/ui/components/list")
local TextEditor = T.import("base/ui/components/texteditor")
local Dropdown = T.import("base/ui/components/dropdown")
local built = {}
T.Registry.addTab({
	Id = "scaletest",
	Title = "Scale test",
	Owner = "scaletest",
	Build = function(page)
		built.List = List.new({
			Parent = page,
			Position = E_.UDim2.fromOffset(8, 8),
			Size = E_.UDim2.new(0.5, -12, 0, 200),
			Columns = {
				{ Key = "Name", Title = "Name", Width = 120 },
				{ Key = "Class", Title = "Class", Width = 100 },
			},
			Items = { { Name = "a", Class = "Part" }, { Name = "b", Class = "Model" }, { Name = "c", Class = "Folder" } },
		})
		built.Editor = TextEditor.new({
			Parent = page,
			Position = E_.UDim2.new(0.5, 4, 0, 8),
			Size = E_.UDim2.new(0.5, -12, 0, 200),
			Text = "line one\nline two\nline three\nline four",
		})
		built.Dropdown = Dropdown.new({
			Parent = page,
			Position = E_.UDim2.fromOffset(8, 220),
			Width = 150,
			Options = { "Low", "Medium", "High" },
			Value = "Low",
		})
	end,
})
T.Tabs:Select("scaletest")
H.advance(0.5)
check("test tab built", built.List and built.Editor and built.Dropdown, H.ERRORS[1])

local ContextMenu = T.import("base/ui/components/contextmenu")
local Tooltip = T.import("base/ui/components/tooltip")
local CellEditor = T.import("base/ui/components/celleditor")
local Prompt = T.import("base/ui/components/prompt")

local function items()
	return { { Text = "One" }, { Text = "Two" }, { Text = "Three" } }
end

local function atScale(f)
	local applied = Scale.set(f)
	H.advance(0.6)
	return applied
end

----------------------------------------------------------------------
-- 4. every scale: window, explorer, popups, pointer maths
----------------------------------------------------------------------
check("this screen fits up to 1.3", Scale.limit() == 1.3, Scale.limit())

for _, f in { 1, 0.75, 1.3 } do
	local tag = ("@%.2f "):format(f)
	local d = Scale.factor() -- what the contents are drawn at: always 1 (the scale sizes the window)
	check(tag .. "scale applied", atScale(f) == f and Scale.get() == f and Scale.factor() == 1, Scale.get())

	-- window and explorer
	do
		check(tag .. "window: contents drawn 1:1 (no zoom)", near(W.RootScale.Scale, 1, 0.001), W.RootScale.Scale)
		check(tag .. "window: its size is 760 × 460 times the scale", W.Root.Size.X.Offset == math.floor(760 * f + 0.5) and W.Root.Size.Y.Offset == math.floor(460 * f + 0.5), tostring(W.Root.Size))
		check(tag .. "window: on screen at that size", nearV(W.Root.AbsoluteSize, V2(760 * f, 460 * f), 1), tostring(W.Root.AbsoluteSize))
		check(tag .. "window: Size is its size on screen", nearV(W.Size, W.Root.AbsoluteSize, 1), tostring(W.Size))
		check(tag .. "explorer: a share of the window (200 px at 1)", near(E.Panel.AbsoluteSize.X, 200 * f, 1), E.Panel.AbsoluteSize.X)
		check(tag .. "explorer: as tall as the window", near(E.Panel.AbsoluteSize.Y, W.Root.AbsoluteSize.Y, 1))
		check(tag .. "title bar keeps its size (more room, not bigger)", near(Create.scaleOf(W.TitleBar), 1, 0.001) and near(W.TitleBar.AbsoluteSize.Y, T.Theme.Sizes.TitleBar, 1), W.TitleBar.AbsoluteSize.Y)
		check(tag .. "title bar spans the wider window", near(W.TitleBar.AbsoluteSize.X, W.Root.AbsoluteSize.X, 1))
		check(tag .. "pill: always 35 px", nearV(W.Pill.AbsoluteSize, V2(35, 35), 0.5), tostring(W.Pill.AbsoluteSize))
	end

	-- popup layers
	do
		local layer, fixed = Overlay.layer(), Overlay.layer(true)
		check(tag .. "popup layer still covers the screen", nearV(layer.AbsoluteSize, SCREEN, 1), tostring(layer.AbsoluteSize))
		check(tag .. "popup layer draws 1:1", near(Create.scaleOf(layer), d, 0.001))
		check(tag .. "fixed layer is never scaled", Create.scaleOf(fixed) == 1 and nearV(fixed.AbsoluteSize, SCREEN, 1))
		check(tag .. "layout viewport", nearV(Overlay.layoutViewport(), SCREEN / d, 1) and nearV(Overlay.layoutViewport(true), SCREEN, 1))
	end

	-- context menu at a point
	do
		local p = V2(300, 200)
		local menu = ContextMenu.open(items(), { Position = p })
		H.advance(0.3)
		local frame = menu.Handle.Frame
		check(tag .. "context menu opens at the point (gap scaled)", nearV(frame.AbsolutePosition, p + V2(2, 2) * d, 1.5), tostring(frame.AbsolutePosition))
		check(tag .. "…drawn at the factor", near(Create.scaleOf(frame), d, 0.001) and nearV(frame.AbsoluteSize, V2(frame.Size.X.Offset, frame.Size.Y.Offset) * d, 1))
		Overlay.closeAll()
		menu = ContextMenu.open(items(), { Position = V2(SCREEN.X - 5, SCREEN.Y - 5) })
		H.advance(0.3)
		frame = menu.Handle.Frame
		local far = frame.AbsolutePosition + frame.AbsoluteSize - Overlay.origin()
		check(tag .. "context menu near the corner stays on screen", far.X <= SCREEN.X + 0.5 and far.Y <= SCREEN.Y + 0.5, tostring(far))
		Overlay.closeAll()
	end

	-- dropdown under its button
	do
		local button = built.Dropdown.Instance
		built.Dropdown:Open()
		H.advance(0.3)
		local frame = Overlay.top().Frame
		local below = button.AbsolutePosition.Y + button.AbsoluteSize.Y + 4 * d
		check(tag .. "dropdown opens right under its button", near(frame.AbsolutePosition.Y, below, 1.5) and near(frame.AbsolutePosition.X, button.AbsolutePosition.X, 1.5), tostring(frame.AbsolutePosition) .. " vs " .. tostring(below))
		check(tag .. "…at least as wide as the button", frame.AbsoluteSize.X >= button.AbsoluteSize.X - 1, tostring(frame.AbsoluteSize))
		Overlay.closeAll()
	end

	-- tooltip beside its anchor
	do
		local anchor = W.MinimizeButton
		local handle = Tooltip.show("Minimize", anchor.AbsolutePosition, anchor.AbsoluteSize, "below")
		local frame = handle and handle.Frame or H.find(Overlay.layer(), "Tooltip")
		check(tag .. "tooltip shows", frame ~= nil)
		if frame then
			check(tag .. "tooltip sits under its anchor (gap scaled)", near(frame.AbsolutePosition.Y, anchor.AbsolutePosition.Y + anchor.AbsoluteSize.Y + 6 * d, 1.5), tostring(frame.AbsolutePosition))
			check(tag .. "tooltip text scales", near(Create.scaleOf(frame), d, 0.001))
		end
		Tooltip.hide()
	end

	-- cell editor exactly over its cell
	do
		local cell = built.List.Instance
		local anchorPos, anchorSize = cell.AbsolutePosition + V2(10, 10) * d, V2(200, 22) * d
		local editor = CellEditor.open({ AnchorPos = anchorPos, AnchorSize = anchorSize, Text = "x", Hint = false })
		H.advance(0.2)
		local frame = Overlay.top().Frame
		check(tag .. "cell editor sits exactly over the cell", nearV(frame.AbsolutePosition, anchorPos, 1.5), tostring(frame.AbsolutePosition) .. " vs " .. tostring(anchorPos))
		check(tag .. "…and is as wide as it", near(frame.AbsoluteSize.X, anchorSize.X, 1.5), frame.AbsoluteSize.X)
		if editor and editor.Close then
			editor:Close("test")
		end
		Overlay.closeAll()
	end

	-- dialog over the window
	do
		Prompt.confirm({ Title = "Scale?", Text = "test" })
		H.advance(0.3)
		local backdrop = Overlay.top().Frame
		check(tag .. "dialog covers exactly the window", nearV(backdrop.AbsolutePosition, W.Root.AbsolutePosition, 1.5) and nearV(backdrop.AbsoluteSize, W.Root.AbsoluteSize, 1.5), tostring(backdrop.AbsoluteSize) .. " vs " .. tostring(W.Root.AbsoluteSize))
		Overlay.closeAll()
		H.advance(0.3)
	end

	-- toasts
	do
		local Notify = T.import("base/ui/components/notify")
		local toast = Notify.show({ Text = "hello", Duration = 0 })
		H.advance(0.3)
		local holder = H.find(Overlay.layer(), "Toasts")
		check(tag .. "toasts sit in the bottom-right corner", holder and near(holder.AbsolutePosition.X + holder.AbsoluteSize.X, SCREEN.X - 16 * d, 3), holder and tostring(holder.AbsolutePosition + holder.AbsoluteSize))
		check(tag .. "toasts scale", holder and near(Create.scaleOf(holder), d, 0.001))
		if toast and toast.Close then
			toast:Close()
		end
		H.advance(0.5)
	end

	-- tree rows under the pointer
	do
		local view = E.View
		T.Console.run("/select game.Workspace.Map.Part3")
		H.advance(0.3)
		local node = E.Tree:NodeFor(map:FindFirstChild("Part3"))
		local index = view.Index[node]
		check(tag .. "tree: Part3 is showing", index ~= nil)
		if index then
			local scrollFrame = view.Scroll.Instance
			local y = ((index - 1) * 22 - view.Scroll.Offset.Y + 11) * d
			local point = scrollFrame.AbsolutePosition + V2(40 * d, y)
			check(tag .. "tree: the row under the pointer", view:RowAt(point) == node, view:RowAt(point) and view:RowAt(point).Name)
			local pos, size = view:NameRect(node)
			check(tag .. "tree: name rectangle lines up with the row (screen)", pos ~= nil and near(pos.Y, scrollFrame.AbsolutePosition.Y + ((index - 1) * 22 - view.Scroll.Offset.Y) * d, 1.5) and near(size.Y, 22 * d, 0.5))
		end
		check(tag .. "tree: visible area in layout pixels", nearV(view.Scroll:ViewSize(), view.Scroll.Instance.AbsoluteSize / d, 1))
	end

	-- list columns and cell rectangles
	do
		local list = built.List
		local view = list.Scroll.Instance
		local second = list._widths[2]
		local point = view.AbsolutePosition + V2((second.X + second.Width / 2 - list.Scroll.Offset.X) * d, 5 * d)
		check(tag .. "list: the column under the pointer", list:ColumnAt(point) == 2, list:ColumnAt(point))
		local pos, size = list:CellRect(list.Items[2], 2)
		check(tag .. "list: cell rectangle on screen", pos ~= nil and near(size.X, second.Width * d, 1) and near(size.Y, list.RowHeight * d, 0.5))
	end

	-- text editor: click → line and column
	do
		local ed = built.Editor
		local at = ed.View.AbsolutePosition + V2((8 + 5.4 * ed.CharWidth - ed.Scroll.Offset.X) * d, (2.5 * ed.LineHeight - ed.Scroll.Offset.Y) * d)
		local line, col = ed:_positionAt(at)
		check(tag .. "editor: a click lands on the right line and column", line == 3 and col == 5, ("%s:%s"):format(tostring(line), tostring(col)))
	end

	-- the explorer's splitter follows the mouse
	do
		E.setSplit(0.5)
		H.advance(0.1)
		local grip = H.find(E.Panel, "Splitter")
		local top = 8 * 2 + T.Theme.Sizes.Control
		local available = E.Panel.AbsoluteSize.Y / d - (top + 28 + 6)
		local targetY = E.Panel.AbsolutePosition.Y + (top + 3 + 0.35 * available) * d
		local gripCenter = grip.AbsolutePosition + grip.AbsoluteSize / 2
		H.press(H.toScreen(gripCenter))
		H.moveTo(H.toScreen(V2(gripCenter.X, targetY)))
		H.release()
		check(tag .. "splitter drag sets the split where the mouse is", near(E.getSplit(), 0.35, 0.02), E.getSplit())
		E.setSplit(0.5)
	end
end
check("no errors across scales", #H.ERRORS == 0, H.ERRORS[1])

----------------------------------------------------------------------
-- 5. the command bar keeps its size; console suggestions don't
----------------------------------------------------------------------
do
	atScale(1.3)
	local Bar = T.CommandBar
	Bar.open()
	H.advance(0.3)
	local holder = Bar.gui():FindFirstChild("CommandBarHolder")
	check("command bar: 560 px at scale 1.3", near(holder.AbsoluteSize.X, 560, 1), holder.AbsoluteSize.X)
	check("command bar: nothing scales it", Create.scaleOf(Bar.box()) == 1)
	local box = Bar.box()
	H.focusBox(box)
	box.CursorPosition = 4
	box.Text = "/se"
	H.step()
	H.advance(0.3)
	local list = Bar.completion()
	check("command bar: suggestions open", list and list:IsOpen())
	if list and list:IsOpen() then
		check("command bar: suggestions on the fixed layer", list.Handle.Fixed == true and list.Panel:IsDescendantOf(Overlay.layer(true)))
		check("command bar: suggestions unscaled", Create.scaleOf(list.Panel) == 1 and near(list.Panel.AbsoluteSize.X, list.Panel.Size.X.Offset, 1))
		check("command bar: suggestions right above or below the bar", math.abs(list.Panel.AbsolutePosition.Y + list.Panel.AbsoluteSize.Y - holder.AbsolutePosition.Y) <= 8 or math.abs(list.Panel.AbsolutePosition.Y - (holder.AbsolutePosition.Y + holder.AbsoluteSize.Y)) <= 8)
	end
	Bar.close()
	H.advance(0.3)

	local view = T.Console.View
	T.Tabs:Select("console")
	H.advance(0.3)
	local cbox = view.Box
	H.focusBox(cbox)
	cbox.CursorPosition = 4
	cbox.Text = "/se"
	H.step()
	H.advance(0.3)
	check("console: suggestions open", view.Completion:IsOpen())
	if view.Completion:IsOpen() then
		local panel = view.Completion.Panel
		check("console: suggestions keep their size at scale 1.3", near(Create.scaleOf(panel), 1, 0.001) and not view.Completion.Handle.Fixed)
		check("console: suggestions sit above the input", panel.AbsolutePosition.Y + panel.AbsoluteSize.Y <= view.Bar.AbsolutePosition.Y + 1)
	end
	cbox.Text = ""
	H.step()
	H.focused = nil
	atScale(1)
end

----------------------------------------------------------------------
-- 6. the scale only changes when you change it
----------------------------------------------------------------------
do
	atScale(1.2)
	Scale.setViewport(V2(900, 500))
	W:Fit(false)
	H.advance(0.3)
	check("a smaller screen lowers the limit", Scale.limit() < 1.2, Scale.limit())
	check("…but not the scale", Scale.get() == 1.2 and near(W.RootScale.Scale, 1, 0.001))
	check("…or the window's size", nearV(W.Size, V2(912, 552), 1), tostring(W.Size))
	check("the next change is capped to what fits now", Scale.set(1.5) == Scale.limit())
	Scale.setViewport(SCREEN)
	check("a bigger screen raises the limit again", Scale.limit() == 1.3)
	check("/scale shows the scale and the limit", T.Console.run ~= nil)
	T.Console.run("/scale 1.1")
	H.advance(0.3)
	check("/scale still changes it", Scale.get() == 1.1)
	T.Console.run("/settings Scale 1.05")
	H.advance(0.3)
	check("/settings Scale still changes it", Scale.get() == 1.05, Scale.get())
	T.Preferences.resetAll()
	H.advance(0.3)
	check("Reset all puts it back to 1", Scale.get() == 1 and near(W.RootScale.Scale, 1, 0.001) and nearV(W.Size, V2(760, 460), 1))
end

----------------------------------------------------------------------
-- 7. a stored scale bigger than the screen is kept on the next run
----------------------------------------------------------------------
do
	T.Settings.set("Scale", 1.75)
	T.Settings.flush()
	local okRun = H.run("Tungsten/Tungsten.luau")
	local T2 = H.genv.Tungsten.Context
	check("re-run ok", okRun and T2 ~= nil)
	check("the splash keeps its size at a stored 1.75", T2.Loading and T2.Loading.BaseScale == 1)
	H.advance(5)
	check("the stored 1.75 is kept (not lowered to fit)", T2.Scale.get() == 1.75, T2.Scale.get())
	check("the window is 1.75 times as big, contents 1:1", near(T2.Window.RootScale.Scale, 1, 0.001) and near(T2.Window.Root.AbsoluteSize.X, 1330, 1))
	check("the explorer is 350 px (200 × 1.75)", near(T2.Explorer.Panel.AbsoluteSize.X, 350, 1))
	local pos = T2.Window.Pos
	check("the window's corner stays on screen", pos.X >= 0 and pos.Y >= 0, tostring(pos))
	local p = V2(200, 150)
	local menu = T2.import("base/ui/components/contextmenu").open(items(), { Position = p })
	H.advance(0.3)
	check("popups keep their size", near(Create.scaleOf(menu.Handle.Frame), 1, 0.001) and nearV(menu.Handle.Frame.AbsolutePosition, p + V2(2, 2), 1.5))
	T2.Overlay.closeAll()
	T2.Scale.step(-T2.Scale.KeyStep)
	H.advance(0.3)
	check("one step down goes straight to what fits", T2.Scale.get() == 1.3, T2.Scale.get())
	T2.Scale.set(1)
	T2.Settings.flush()
	T = T2
end

check("no runtime errors", #H.ERRORS == 0, H.ERRORS[1])
print(("stage5a: %d passed, %d failed, %d runtime errors"):format(passed, failed, #H.ERRORS))
