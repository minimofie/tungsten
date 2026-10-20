-- Plugins stage, round P0b: sub-tabs in Tungsten's own style (pills on a
-- Chrome band, AccentSoft open pill, SurfaceHover on hover, badges, the
-- strip scrolling sideways when the pills don't fit), at scale 0.75 / 1 / 1.75.
local passed, failed = 0, 0
local function check(name, cond, detail)
	if cond then
		passed += 1
	else
		failed += 1
		print("FAIL: " .. name .. (if detail ~= nil then "  [" .. tostring(detail) .. "]" else ""))
	end
end
H.ABS_SHIFT = SHIFT or 0
local genv = H.genv

local ok, err = H.run("Tungsten/Tungsten.luau")
check("loader runs", ok, err)
H.advance(5)
local T = genv.Tungsten.Context
local SubTabs = T.import("base/ui/components/subtabs")
local Create = T.import("base/ui/create")
local Colors = T.Theme.Colors

-- a tab of its own to hold the strip
local page
T.Registry.addTab({ Id = "subtest", Title = "Sub test", Owner = "core", Build = function(p) page = p end })
H.advance(0.2)
T.Tabs:Select("subtest")
H.advance(0.4)
check("test page built", page ~= nil)

local built = {}
local tabs = SubTabs.new({
	Parent = page,
	TabId = "subtest",
	Tabs = {
		{ Id = "constants", Title = "Constants", Icon = "type_number", Build = function() built.constants = true end },
		{ Id = "upvalues", Title = "Upvalues", Icon = "variable", Badge = 3 },
		{ Id = "source", Title = "Source" },
	},
})
H.advance(0.3)
local function pill(id)
	return H.find(tabs.Instance, "Tab_" .. id)
end

----------------------------------------------------------------------
-- 1. the look
----------------------------------------------------------------------
check("strip: a Chrome band 38 high", tabs.Strip.BackgroundColor3 == Colors.Chrome and tabs.Strip.Size.Y.Offset == 38, tabs.Strip.Size.Y.Offset)
check("pills are 26 high with the title-bar corner", pill("constants").Size.Y.Offset == 26 and pill("constants"):FindFirstChildOfClass("UICorner").CornerRadius.Offset == T.Theme.Sizes.RadiusSmall)
check("no underline any more", H.find(pill("constants"), "Underline") == nil)
check("open pill: AccentSoft fill", pill("constants").BackgroundTransparency == 0 and pill("constants").BackgroundColor3 == Colors.AccentSoft)
check("open pill: Accent icon", H.find(pill("constants"), "Icon").ImageColor3 == Colors.Accent and H.find(pill("upvalues"), "Icon").ImageColor3 == Colors.TextDim)
check("open pill: Text title", H.find(pill("constants"), "Text").TextColor3 == Colors.Text)
check("closed pill: no fill, TextDim title", pill("source").BackgroundTransparency == 1 and H.find(pill("source"), "Text").TextColor3 == Colors.TextDim)
check("a pill without an icon starts its title at the padding", H.find(pill("source"), "Text").Position.X.Offset == 10)
check("pills sit side by side, in order", pill("constants").AbsolutePosition.X < pill("upvalues").AbsolutePosition.X and pill("upvalues").AbsolutePosition.X < pill("source").AbsolutePosition.X)
check("pills sit inside the band, centred", math.abs((pill("source").AbsolutePosition.Y + pill("source").AbsoluteSize.Y / 2) - (tabs.Strip.AbsolutePosition.Y + (tabs.Strip.AbsoluteSize.Y - 1) / 2)) <= 1.5, tostring(pill("source").AbsolutePosition.Y) .. "/" .. tostring(pill("source").AbsoluteSize.Y) .. " strip " .. tostring(tabs.Strip.AbsolutePosition.Y) .. "/" .. tostring(tabs.Strip.AbsoluteSize.Y))

-- hover
H.hover(pill("source"))
H.advance(0.3)
check("hover: SurfaceHover fill, Text title", pill("source").BackgroundTransparency == 0 and pill("source").BackgroundColor3 == Colors.SurfaceHover and H.find(pill("source"), "Text").TextColor3 == Colors.Text)
H.moveMouse(H.env.Vector2.new(5, 5))
H.advance(0.3)
check("…and back", pill("source").BackgroundTransparency == 1 and H.find(pill("source"), "Text").TextColor3 == Colors.TextDim)

-- open another
H.clickObject(H.find(pill("source"), "Text"))
H.advance(0.3)
check("clicking opens it: fill moves", tabs.Selected == "source" and pill("source").BackgroundColor3 == Colors.AccentSoft and pill("source").BackgroundTransparency == 0 and pill("constants").BackgroundTransparency == 1)

----------------------------------------------------------------------
-- 2. badges
----------------------------------------------------------------------
local badge = H.find(pill("upvalues"), "Badge")
check("a Badge in the definition shows", badge and badge.Visible and H.find(badge, "Text").Text == "3")
check("badge: an accent dot with OnAccent text", badge.BackgroundColor3 == Colors.Accent and H.find(badge, "Text").TextColor3 == Colors.OnAccent)
check("the badge sits after the title, inside the pill", badge.Position.X.Offset > H.find(pill("upvalues"), "Text").Position.X.Offset and badge.Position.X.Offset + badge.Size.X.Offset <= pill("upvalues").Size.X.Offset - 10)
local widthBefore = pill("source").Size.X.Offset
tabs:Badge("source", 1234)
H.advance(0.1)
check("tabs:Badge adds one; long numbers are cut to 3", H.find(H.find(pill("source"), "Badge"), "Text").Text == "12+" and H.find(pill("source"), "Badge").Visible)
check("…and the pill grows to hold it", pill("source").Size.X.Offset > widthBefore)
tabs:Badge("source", 0)
H.advance(0.1)
check("0 takes it away and the pill shrinks back", not H.find(pill("source"), "Badge").Visible and pill("source").Size.X.Offset == widthBefore)
check("Badge on an unknown sub-tab is false", tabs:Badge("nope", 1) == false)

----------------------------------------------------------------------
-- 3. too many to fit: sideways scrolling
----------------------------------------------------------------------
for index = 1, 14 do
	tabs:Add({ Id = "extra" .. index, Title = "Extra view " .. index, Icon = "object" })
end
H.advance(0.3)
check("the strip can scroll sideways", tabs.Scroll:CanScroll("X"))
tabs:Select("extra14")
H.advance(0.6)
local last = pill("extra14")
local stripRight = tabs.Strip.AbsolutePosition.X + tabs.Strip.AbsoluteSize.X
check("opening one out of view scrolls it into view", last.AbsolutePosition.X + last.AbsoluteSize.X <= stripRight + 1 and last.AbsolutePosition.X >= tabs.Strip.AbsolutePosition.X, last.AbsolutePosition.X)
tabs:Select("constants")
H.advance(0.6)
check("…and back to the first", pill("constants").AbsolutePosition.X >= tabs.Strip.AbsolutePosition.X)
local offsetBefore = tabs.Scroll.Target.X
H.wheel(H.toScreen(tabs.Strip.AbsolutePosition + tabs.Strip.AbsoluteSize / 2), 3) -- wheel up = right (Tungsten's sideways rule)
H.advance(0.4)
check("the mouse wheel scrolls the strip", tabs.Scroll.Target.X > offsetBefore, tabs.Scroll.Target.X)

----------------------------------------------------------------------
-- 4. scale
----------------------------------------------------------------------
tabs.Scroll:ScrollTo(H.env.Vector2.new(0, 0), false)
H.advance(0.2)
for _, scale in { 0.75, 1.75, 1 } do
	T.Scale.set(scale)
	H.advance(0.4)
	local p = pill("constants")
	check(("scale %.2f: the strip keeps its size (drawn 1:1)"):format(scale), math.abs(Create.scaleOf(tabs.Strip) - 1) < 0.001 and (scale == 1.75 or math.abs(T.Scale.get() - scale) < 0.001), T.Scale.get())
	check(("scale %.2f: pills keep their layout size"):format(scale), math.abs(Create.layoutSize(p).Y - 26) < 0.5, Create.layoutSize(p).Y)
	H.clickObject(H.find(pill("upvalues"), "Text"))
	H.advance(0.3)
	check(("scale %.2f: clicks land on the right pill"):format(scale), tabs.Selected == "upvalues")
	tabs:Select("constants")
	H.advance(0.3)
end

tabs:Destroy()
T.Registry.removeTab("subtest")

----------------------------------------------------------------------
-- 5. the Plugins tab: the first card's outline clears the heading
----------------------------------------------------------------------
do
	T.Tabs:Select("plugins")
	H.advance(0.4)
	local M = T.Manager
	local heading = H.find(M.List, "Heading")
	local card = M.Entries.tungsten and M.Entries.tungsten.Frame
	local stroke = card and card:FindFirstChildOfClass("UIStroke")
	local outlineTop = card and (card.AbsolutePosition.Y - (stroke and stroke.Thickness or 0))
	local headingBottom = heading.AbsolutePosition.Y + heading.AbsoluteSize.Y
	check("the tungsten card's outline is below the PLUGINS heading", card ~= nil and outlineTop >= headingBottom + 2, tostring(outlineTop) .. " vs " .. tostring(headingBottom))
	check("…and inside the list's clipped area", card ~= nil and outlineTop >= M.ListScroll.Instance.AbsolutePosition.Y)
	T.Tabs:Select("console")
	H.advance(0.3)
end
H.advance(0.2)
check("no runtime errors", #H.ERRORS == 0, H.ERRORS[1])
for _, e in H.ERRORS do
	print("ERR: " .. e)
end
print(("p0b: %d passed, %d failed, %d runtime errors"):format(passed, failed, #H.ERRORS))
