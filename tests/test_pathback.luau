-- The path bar's back button (right of the menu button): goes back to what
-- was loaded before (base/loaded history).
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
H.ABS_SHIFT = SHIFT or 0
local genv = H.genv
local new = E_.Instance.new
local function make(class, name, parent)
	local o = new(class)
	o.Name = name
	o.Parent = parent
	return o
end
local map = make("Model", "Map", E_.workspace)
local door = make("Part", "Door", map)
local lamp = make("Part", "Lamp", map)
local spare = make("Part", "Spare", map)

local ok, err = H.run("Tungsten/Tungsten.luau")
check("loader runs", ok, err)
H.advance(5)
local T = genv.Tungsten.Context
local P, Loaded = T.PathBar, T.Loaded
local function lastCrumb()
	local best, order = nil, -1
	for _, c in P.Crumbs:GetChildren() do
		if c.Name:sub(1, 5) == "Crumb" and c.LayoutOrder > order then
			best, order = c, c.LayoutOrder
		end
	end
	local text = best and best:FindFirstChild("Text")
	return if text then text.Text else nil
end
local function enabled()
	return P.BackButton:GetAttribute("Enabled") == true
end

----------------------------------------------------------------------
-- 1. the button
----------------------------------------------------------------------
local back = P.BackButton
check("a Back button in the path bar", back ~= nil and back.Name == "Back" and back.Parent == P.Instance)
check("…right of the menu button", back.AbsolutePosition.X > P.MenuButton.AbsolutePosition.X and back.AbsolutePosition.X < P.Field.AbsolutePosition.X, ("%d %d %d"):format(P.MenuButton.AbsolutePosition.X, back.AbsolutePosition.X, P.Field.AbsolutePosition.X))
check("…the same size as the other buttons", back.AbsoluteSize == P.MenuButton.AbsoluteSize)
check("…the field starts after it, the arrow keeps its place", P.Field.AbsolutePosition.X >= back.AbsolutePosition.X + back.AbsoluteSize.X and P.Field.AbsolutePosition.X + P.Field.AbsoluteSize.X <= P.GoButton.AbsolutePosition.X)
check("nothing loaded yet: greyed", not enabled() and not Loaded.canGoBack())
H.clickObject(back)
H.advance(0.1)
check("…pressing it does nothing", Loaded.get() == nil)

----------------------------------------------------------------------
-- 2. going back
----------------------------------------------------------------------
Loaded.load({ door })
H.advance(0.1)
check("one load: still nothing to go back to", not enabled())
Loaded.load({ lamp })
H.advance(0.1)
check("a second load: back is on", enabled() and Loaded.previous()[1] == door)
Loaded.load({ lamp })
H.advance(0.1)
Loaded.load({ spare, door })
H.advance(0.1)
check("the same thing twice is remembered once", #Loaded.history() == 2, #Loaded.history())
H.clickObject(back)
H.advance(0.1)
check("back: the instance before", Loaded.get() == lamp and lastCrumb() == "Lamp", lastCrumb())
H.clickObject(back)
H.advance(0.1)
check("back again: the one before that", Loaded.get() == door and lastCrumb() == "Door", lastCrumb())
check("…nothing older: greyed", not enabled())
H.clickObject(back)
H.advance(0.1)
check("…pressing it stays put", Loaded.get() == door)

-- a value (path bar value crumb) and back to the instance
local function fn() end
Loaded.load(Loaded.target(fn, { Label = "function fn" }))
H.advance(0.1)
check("a value loaded", P.Crumbs:FindFirstChild("Crumb_value") ~= nil)
H.clickObject(back)
H.advance(0.1)
check("back from a value to the instance", Loaded.get() == door and P.Crumbs:FindFirstChild("Crumb_value") == nil)

-- several loaded: back restores all of them
Loaded.load({ spare, lamp })
H.advance(0.1)
Loaded.load({ door })
H.advance(0.1)
H.clickObject(back)
H.advance(0.1)
local list = Loaded.list()
check("back restores several", #list == 2 and list[1] == spare and list[2] == lamp)

-- a clear can be gone back from
Loaded.clear()
H.advance(0.1)
check("cleared: back is on", enabled())
H.clickObject(back)
H.advance(0.1)
check("…back brings it back", #Loaded.list() == 2 and Loaded.get() == spare)

-- destroyed instances are skipped
Loaded.load({ lamp })
H.advance(0.1)
Loaded.load({ door })
H.advance(0.1)
Loaded.load({ spare })
H.advance(0.1)
local temp = make("Part", "Temp", map)
Loaded.load({ temp })
H.advance(0.1)
temp:Destroy()
H.advance(0.2)
check("the loaded instance destroyed: it drops out", Loaded.get() == nil)
H.clickObject(back)
H.advance(0.1)
check("back skips what was destroyed", Loaded.get() ~= temp and Loaded.get() ~= nil, Loaded.get() and Loaded.get().Name)

----------------------------------------------------------------------
-- 3. tooltip, editing, the explorer
----------------------------------------------------------------------
Loaded.load({ lamp })
H.advance(0.1)
Loaded.load({ spare })
H.advance(0.1)
H.hover(back)
H.advance(1.5)
local tip = T.import("base/ui/components/tooltip").current()
local tipText = tip and H.find(tip, "Text")
check("hover says where back goes", tipText ~= nil and tipText.Text:find("Back to", 1, true) ~= nil and tipText.Text:find("Lamp", 1, true) ~= nil, tipText and tipText.Text)
H.moveTo(E_.Vector2.new(5, 700))
P.edit()
H.advance(0.1)
H.clickObject(back)
H.advance(0.2)
check("pressing back while typing a path stops editing and goes back", Loaded.get() == lamp and not P.EditClip.Visible)
T.Explorer.load({ spare })
H.advance(0.1)
H.clickObject(back)
H.advance(0.1)
check("Explorer › Load is remembered too", Loaded.get() == lamp)
Loaded.clearHistory()
H.advance(0.1)
check("clearHistory greys it", not enabled())
check("a menu-free change: Copy / Highlight menu unchanged", #P.menuItems() >= 2)

print(("pathback: %d passed, %d failed, 0 runtime errors"):format(passed, failed))
