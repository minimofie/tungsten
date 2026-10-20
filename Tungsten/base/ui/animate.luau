--[[
	Tungsten · base/ui/animate
	Tween helpers and standard interaction animations.
]]

local T = ...
local Services = T.import("base/services")
local Create = T.import("base/ui/create")

local TweenService = Services.TweenService

local Animate = {}
Animate.Fast = 0.12
Animate.Normal = 0.2
Animate.Slow = 0.3

function Animate.tween(
	instance: Instance,
	goal: { [string]: any },
	duration: number?,
	style: Enum.EasingStyle?,
	direction: Enum.EasingDirection?
): Tween
	local tween = TweenService:Create(
		instance,
		TweenInfo.new(duration or Animate.Normal, style or Enum.EasingStyle.Quint, direction or Enum.EasingDirection.Out),
		goal
	)
	tween:Play()
	return tween
end

-- Tween when a duration is given, otherwise assign immediately.
function Animate.set(instance: Instance, goal: { [string]: any }, duration: number?)
	if duration and duration > 0 then
		return Animate.tween(instance, goal, duration)
	end
	for key, value in goal do
		(instance :: any)[key] = value
	end
	return nil
end

-- Small press-down effect for buttons. Returns the UIScale it uses.
function Animate.pressable(button: GuiButton, bin): UIScale
	local scale = Create.new("UIScale", { Parent = button })
	local function down()
		Animate.tween(scale, { Scale = 0.92 }, 0.08)
	end
	local function up()
		Animate.tween(scale, { Scale = 1 }, 0.18, Enum.EasingStyle.Back)
	end
	bin:Add(button.MouseButton1Down:Connect(down))
	bin:Add(button.MouseButton1Up:Connect(up))
	bin:Add(button.MouseLeave:Connect(up))
	return scale
end

----------------------------------------------------------------------
-- Fading a whole tree of GUI objects (window minimize / restore)
----------------------------------------------------------------------

local FADE_PROPS = {
	GuiObject = { "BackgroundTransparency" },
	TextLabel = { "TextTransparency", "TextStrokeTransparency" },
	TextButton = { "TextTransparency", "TextStrokeTransparency" },
	TextBox = { "TextTransparency", "TextStrokeTransparency" },
	ImageLabel = { "ImageTransparency" },
	ImageButton = { "ImageTransparency" },
	ScrollingFrame = { "ScrollBarImageTransparency" },
	UIStroke = { "Transparency" },
}

-- Every fading property under (and of) root with its current value.
local function snapshot(root: Instance): { any }
	local list = {}
	local function add(object: Instance)
		for className, props in FADE_PROPS do
			local ok, is = pcall(function()
				return object:IsA(className)
			end)
			if ok and is then
				for _, prop in props do
					local okRead, value = pcall(function()
						return (object :: any)[prop]
					end)
					if okRead and type(value) == "number" then
						table.insert(list, { object, prop, value })
					end
				end
			end
		end
	end
	add(root)
	for _, object in root:GetDescendants() do
		add(object)
	end
	return list
end

local function setAll(list: { any }, alpha: number)
	-- alpha 0: true values, 1: fully transparent
	for _, item in list do
		local object, prop, base = item[1], item[2], item[3]
		pcall(function()
			(object :: any)[prop] = base + (1 - base) * alpha
		end)
	end
end

local fades = setmetatable({}, { __mode = "k" }) -- root -> { List, Alpha }

--[[
	Animate.fade(root, "out" | "in", duration, done?)
	out: everything fades to transparent, then root is hidden and every
	value is put back (so the next fade in starts from the real look).
	in: root is shown and fades from transparent to its real look.
	A fade that starts while another runs on the same root takes over
	from where that one is (no jump back, no flash) and only takes the
	time the remaining distance needs. done runs only when a fade
	finishes (not when another one takes over).
]]
function Animate.fade(root: GuiObject, direction: string, duration: number?, done: (() -> ())?)
	duration = duration or Animate.Normal
	local previous = fades[root]
	local list, from
	if previous then
		-- The running fade's snapshot holds the real look; carry on from
		-- its current point.
		list, from = previous.List, previous.Alpha
	elseif direction == "in" then
		root.Visible = false
		list, from = snapshot(root), 1
	else
		list, from = snapshot(root), 0
	end
	local target = if direction == "in" then 0 else 1
	local state = { List = list, Alpha = from }
	fades[root] = state
	setAll(list, from)
	root.Visible = true
	local span = (duration :: number) * math.abs(target - from)
	local function finish()
		fades[root] = nil
		if direction ~= "in" then
			root.Visible = false
		end
		setAll(list, 0)
		if done then
			pcall(done)
		end
	end
	if span <= 0 then
		finish()
		return state
	end
	local started = os.clock()
	local connection
	connection = Services.RunService.RenderStepped:Connect(function()
		if fades[root] ~= state then
			-- Another fade took over; it owns the values now.
			connection:Disconnect()
			return
		end
		local t = math.clamp((os.clock() - started) / span, 0, 1)
		local eased = 1 - (1 - t) * (1 - t)
		state.Alpha = from + (target - from) * eased
		setAll(list, state.Alpha)
		if t >= 1 then
			connection:Disconnect()
			finish()
		end
	end)
	return state
end

-- Is a fade running on root?
function Animate.fading(root: GuiObject): boolean
	return fades[root] ~= nil
end

-- Calls onChange(true/false) as the pointer enters/leaves.
function Animate.hover(target: GuiObject, bin, onChange: (boolean) -> ())
	bin:Add(target.MouseEnter:Connect(function()
		onChange(true)
	end))
	bin:Add(target.MouseLeave:Connect(function()
		onChange(false)
	end))
end

return Animate
