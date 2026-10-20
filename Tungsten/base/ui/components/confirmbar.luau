--[[
	Tungsten · base/ui/components/confirmbar
	Cancel / Accept buttons for popups that edit a value (the color picker,
	the BrickColor palette, the sequence editor; plugin popups too).

		local bar = ConfirmBar.new({
			Parent = frame,
			Position = UDim2.new(1, -10, 0, y), AnchorPoint = Vector2.new(1, 0),
			AcceptText = "Accept", CancelText = "Cancel",  -- optional
			Origin = "core",
			OnAccept = function() end,
			OnCancel = function() end,
		})
		bar.Accept / bar.Cancel   the Buttons
		bar.Instance              the row (sized to fit both)
		ConfirmBar.Height         its height

	The rule every such popup follows:
		Accept keeps the edit and closes; Cancel puts the value back the way
		it was when the popup opened and closes; Escape is Cancel; a click
		outside (or another popup taking its place) keeps the edit, like
		Accept.
		ConfirmBar.closeMeans(reason) -> "accept" | "cancel" applies it to
		an overlay close reason.
]]

local T = ...
local Theme = T.import("base/theme")
local Create = T.import("base/ui/create")
local Button = T.import("base/ui/components/button")
local UI = T.import("base/ui/ui")

local new = Create.new
local Sizes = Theme.Sizes

local GAP = 6

local ConfirmBar = {}
ConfirmBar.Height = Sizes.Control

function ConfirmBar.closeMeans(reason: string?): string
	if reason == "escape" or reason == "cancelled" then
		return "cancel"
	end
	return "accept"
end

function ConfirmBar.new(props: { [string]: any })
	local origin = props.Origin or "core"
	local row = new("Frame", {
		Name = props.Name or "Confirm",
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		Position = props.Position or UDim2.new(),
		Size = UDim2.fromOffset(0, ConfirmBar.Height),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		Parent = props.Parent,
	})
	local layout = Create.list(row, Enum.FillDirection.Horizontal, GAP, {
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		VerticalAlignment = Enum.VerticalAlignment.Center,
	})
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	local function call(fn)
		if fn then
			local ok, err = pcall(fn)
			if not ok then
				T.Log.error("ui", "confirm button failed: " .. tostring(err))
			end
		end
	end
	local cancel = Button.new({
		Name = "Cancel",
		Parent = row,
		Origin = origin,
		Text = props.CancelText or "Cancel",
		Style = "default",
		LayoutOrder = 1,
		OnClick = function()
			call(props.OnCancel)
		end,
	})
	local accept = Button.new({
		Name = "Accept",
		Parent = row,
		Origin = origin,
		Text = props.AcceptText or "Accept",
		Style = "accent",
		LayoutOrder = 2,
		OnClick = function()
			call(props.OnAccept)
		end,
	})
	return {
		Instance = row,
		Accept = accept,
		Cancel = cancel,
		Width = function()
			return Create.layoutSize(row).X
		end,
	}
end

return UI.register("ConfirmBar", ConfirmBar, {
	Description = "Cancel / Accept buttons for popups that edit a value",
	Constructor = "new",
})
