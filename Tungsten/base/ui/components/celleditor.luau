--[[
	Tungsten · base/ui/components/celleditor
	A one-line text editor that floats over a list cell (or anything else)
	on the overlay. Enter commits, Escape or clicking elsewhere cancels.
	A value that doesn't parse keeps the editor open and says why.

		CellEditor.open({
			AnchorPos = cell.AbsolutePosition, AnchorSize = cell.AbsoluteSize,
			Text = "1, 2, 3",
			Hint = "Vector3 · x, y, z",          -- shown under the box; false: none
			                                     -- (an error still shows there)
			Mono = true,
			Validate = function(text) return true, value end,   -- or false, reason
			OnCommit = function(value) return true end,         -- or false, reason
			OnClose = function(committed) end,
			Owner = list,
		})
]]

local T = ...
local signal = T.import("base/signal")
local Theme = T.import("base/theme")
local Create = T.import("base/ui/create")
local Overlay = T.import("base/ui/overlay")
local UI = T.import("base/ui/ui")

local new = Create.new
local Sizes = Theme.Sizes

local MIN_WIDTH = 170
local HINT_HEIGHT = 18

local CellEditor = {}

function CellEditor.open(opts: { [string]: any })
	local origin = opts.Origin or "core"
	local anchorPos: Vector2 = opts.AnchorPos
	-- AnchorSize is on-screen pixels (a cell's AbsoluteSize); work in the
	-- popup layer's layout pixels.
	local anchorSize: Vector2 = if opts.AnchorSize then opts.AnchorSize / Overlay.factor() else Vector2.new(MIN_WIDTH, Sizes.Row)
	local width = math.max(MIN_WIDTH, math.floor(anchorSize.X))
	local boxHeight = math.max(Sizes.Row, math.floor(anchorSize.Y))
	local quiet = opts.Hint == false -- no hint line; only errors use it
	local size = Vector2.new(width, boxHeight + HINT_HEIGHT + 4)
	-- Sit exactly over the anchor, nudged (not flipped) to stay on screen.
	local view = Overlay.layoutViewport()
	local local_ = Overlay.toLayout(anchorPos)
	local margin = Overlay.Margin
	local position = Vector2.new(
		math.floor(math.clamp(local_.X, margin, math.max(margin, view.X - margin - size.X)) + 0.5),
		math.floor(math.clamp(local_.Y, margin, math.max(margin, view.Y - margin - size.Y)) + 0.5)
	)

	local frame = new("Frame", {
		Name = "CellEditor",
		Position = UDim2.fromOffset(position.X, position.Y),
		Size = UDim2.fromOffset(size.X, if quiet then boxHeight else size.Y),
		BackgroundTransparency = 1,
		Active = true,
	})
	local holder = new("Frame", {
		Name = "Box",
		Size = UDim2.new(1, 0, 0, boxHeight),
		Active = true,
		Theme = { BackgroundColor3 = "Chrome" },
		Parent = frame,
	})
	Create.corner(holder, 5)
	local stroke = Create.stroke(holder, "Accent", 1, 0)
	local box = new("TextBox", {
		Name = "Input",
		Position = UDim2.fromOffset(7, 0),
		Size = UDim2.new(1, -14, 1, 0),
		BackgroundTransparency = 1,
		Text = tostring(UI.apply("CellEditor", "Text", origin, tostring(opts.Text or ""), opts)),
		ClearTextOnFocus = false,
		ClipsDescendants = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		FontFace = if opts.Mono then Theme.Fonts.Mono else Theme.Fonts.Regular,
		TextSize = if opts.Mono then Sizes.CodeText else Sizes.Text,
		Parent = holder,
	})
	local hint = new("TextLabel", {
		Name = "Hint",
		Position = UDim2.fromOffset(4, boxHeight + 3),
		Size = UDim2.new(1, -8, 0, HINT_HEIGHT),
		Text = if quiet then "" else opts.Hint or "Enter to save · Escape to cancel",
		TextSize = Sizes.TextSmall,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Visible = not quiet,
		Theme = { TextColor3 = "TextMuted" },
		Parent = frame,
	})
	local function setQuiet(on: boolean)
		if not quiet then
			return
		end
		hint.Visible = not on
		frame.Size = UDim2.fromOffset(size.X, if on then boxHeight else size.Y)
	end

	local bin = signal.bin()
	local committed = false
	local handle

	local function showError(reason: string)
		setQuiet(false)
		hint.Text = tostring(reason)
		Theme.bind(hint, "TextColor3", "Danger")
		Theme.bind(stroke, "Color", "Danger")
	end

	local function try(): boolean
		local text = box.Text
		local ok, value = true, text
		if opts.Validate then
			local success, a, b = pcall(opts.Validate, text)
			if not success then
				ok, value = false, tostring(a)
			else
				ok, value = a, b
			end
		end
		if not ok then
			showError(value)
			return false
		end
		if opts.OnCommit then
			local success, accepted, reason = pcall(opts.OnCommit, value)
			if not success then
				showError(tostring(accepted))
				return false
			end
			if accepted == false then
				showError(reason or "not accepted")
				return false
			end
		end
		committed = true
		UI.fire("CellEditor", "Committed", origin, value, opts)
		return true
	end

	bin:Add(box.FocusLost:Connect(function(enterPressed)
		if not handle or handle.Closed then
			return
		end
		if enterPressed then
			if try() then
				handle:Close("committed")
			else
				task.defer(function()
					if handle and not handle.Closed then
						box:CaptureFocus()
					end
				end)
			end
		end
	end))
	bin:Add(box:GetPropertyChangedSignal("Text"):Connect(function()
		-- Typing clears an error.
		Theme.bind(stroke, "Color", "Accent")
		Theme.bind(hint, "TextColor3", "TextMuted")
		if quiet then
			setQuiet(true)
		else
			hint.Text = opts.Hint or "Enter to save · Escape to cancel"
		end
	end))

	handle = Overlay.open(frame, {
		Owner = opts.Owner,
		OnClose = function(reason)
			bin:Clean()
			if opts.OnClose then
				pcall(opts.OnClose, committed, reason)
			end
			UI.fire("CellEditor", "Closed", origin, handle, committed, reason)
		end,
	})
	handle.Box = box
	handle.Commit = function()
		if try() then
			handle:Close("committed")
			return true
		end
		return false
	end
	task.defer(function()
		if not handle.Closed then
			box:CaptureFocus()
			pcall(function()
				box.CursorPosition = #box.Text + 1
			end)
		end
	end)
	UI.fire("CellEditor", "Created", origin, handle, opts)
	UI.fire("CellEditor", "Opened", origin, handle, opts)
	return handle
end

return UI.register("CellEditor", CellEditor, {
	Description = "one-line text editor over a cell (typed parsing, error shown in place)",
	Constructor = "open",
	Events = {
		Created = "handle, opts · (same as Opened)",
		Opened = "handle, opts",
		Committed = "value, opts · a value was accepted",
		Closed = "handle, committed, reason",
	},
	Filters = {
		Text = "text, opts · the text the box starts with",
	},
})
