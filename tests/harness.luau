-- Mock Roblox + Volt runtime for offline tests. FILES is prepended by the
-- build script: { [path] = source }.

local H = {}
H.FN = setmetatable({}, { __mode = "k" }) -- function -> what the Volt stand-ins report for it (script viewer tests)
H.FILES = FILES
H.CLIPBOARD = nil
H.TIME = 0
H.ERRORS = {}
H.WARNINGS = {}

local realType = type

----------------------------------------------------------------------
-- typeof
----------------------------------------------------------------------
local function typeof(v)
	if realType(v) == "table" then
		local mt = getmetatable(v)
		if realType(mt) == "table" and rawget(mt, "__type") then
			return rawget(mt, "__type")
		end
	end
	return type(v)
end

----------------------------------------------------------------------
-- Signals
----------------------------------------------------------------------
local Signal = {}
Signal.__index = Signal
local ConnMT = { __type = "RBXScriptConnection" }
ConnMT.__index = ConnMT
function ConnMT:Disconnect()
	self.Connected = false
end
local function newSignal()
	return setmetatable({ _c = {} }, { __index = Signal, __type = "RBXScriptSignal" })
end
function Signal:Connect(fn)
	assert(realType(fn) == "function", "Connect needs function")
	local c = setmetatable({ Connected = true, _fn = fn }, ConnMT)
	table.insert(self._c, c)
	return c
end
function Signal:Once(fn)
	local c
	c = self:Connect(function(...)
		c:Disconnect()
		fn(...)
	end)
	return c
end
function Signal:Fire(...)
	for _, c in table.clone(self._c) do
		if c.Connected then
			local ok, err = xpcall(c._fn, debug.traceback, ...)
			if not ok then
				table.insert(H.ERRORS, err)
				print("SIGNAL ERROR: " .. tostring(err))
			end
		end
	end
end
function Signal:Count()
	local n = 0
	for _, c in self._c do
		if c.Connected then
			n += 1
		end
	end
	return n
end
H.newSignal = newSignal

----------------------------------------------------------------------
-- Datatypes
----------------------------------------------------------------------
local V2 = { __type = "Vector2" }
local function vec2(x, y)
	return setmetatable({ X = x or 0, Y = y or 0 }, V2)
end
V2.__index = function(self, k)
	if k == "Magnitude" then
		return math.sqrt(self.X * self.X + self.Y * self.Y)
	end
	return nil
end
V2.__add = function(a, b) return vec2(a.X + b.X, a.Y + b.Y) end
V2.__sub = function(a, b) return vec2(a.X - b.X, a.Y - b.Y) end
V2.__mul = function(a, b)
	if realType(a) == "number" then return vec2(a * b.X, a * b.Y) end
	if realType(b) == "number" then return vec2(a.X * b, a.Y * b) end
	return vec2(a.X * b.X, a.Y * b.Y)
end
V2.__div = function(a, b)
	if realType(b) == "number" then return vec2(a.X / b, a.Y / b) end
	return vec2(a.X / b.X, a.Y / b.Y)
end
V2.__unm = function(a) return vec2(-a.X, -a.Y) end
V2.__eq = function(a, b) return a.X == b.X and a.Y == b.Y end
V2.__tostring = function(a) return ("%g, %g"):format(a.X, a.Y) end
local Vector2 = { new = vec2, zero = vec2(0, 0), one = vec2(1, 1) }

local V3 = { __type = "Vector3" }
local function vec3(x, y, z) return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0 }, V3) end
V3.__index = function(self, k)
	if k == "Magnitude" then return math.sqrt(self.X * self.X + self.Y * self.Y + self.Z * self.Z) end
	return nil
end
V3.__tostring = function(a) return ("%g, %g, %g"):format(a.X, a.Y, a.Z) end
V3.__eq = function(a, b) return a.X == b.X and a.Y == b.Y and a.Z == b.Z end
V3.__add = function(a, b) return vec3(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end
V3.__sub = function(a, b) return vec3(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end
V3.__mul = function(a, b)
	if realType(a) == "number" then return vec3(a * b.X, a * b.Y, a * b.Z) end
	if realType(b) == "number" then return vec3(a.X * b, a.Y * b, a.Z * b) end
	return vec3(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
end
V3.__unm = function(a) return vec3(-a.X, -a.Y, -a.Z) end
local Vector3 = { new = vec3, zero = vec3(0, 0, 0), one = vec3(1, 1, 1) }

local UDimMT = { __type = "UDim" }
UDimMT.__index = UDimMT
UDimMT.__eq = function(a, b) return a.Scale == b.Scale and a.Offset == b.Offset end
local function udim(s, o) return setmetatable({ Scale = s or 0, Offset = o or 0 }, UDimMT) end
local UDim = { new = udim }

local U2 = { __type = "UDim2" }
U2.__index = function(self, k)
	if k == "Width" then return rawget(self, "X") end
	if k == "Height" then return rawget(self, "Y") end
	return nil
end
U2.__eq = function(a, b) return a.X == b.X and a.Y == b.Y end
U2.__tostring = function(a) return ("{%g,%g},{%g,%g}"):format(a.X.Scale, a.X.Offset, a.Y.Scale, a.Y.Offset) end
local function udim2(xs, xo, ys, yo)
	if typeof(xs) == "UDim" then
		return setmetatable({ X = xs, Y = xo }, U2)
	end
	return setmetatable({ X = udim(xs, xo), Y = udim(ys, yo) }, U2)
end
local UDim2 = {
	new = udim2,
	fromOffset = function(x, y) return udim2(0, x or 0, 0, y or 0) end,
	fromScale = function(x, y) return udim2(x or 0, 0, y or 0, 0) end,
}

local C3 = { __type = "Color3" }
C3.__index = C3
C3.__eq = function(a, b) return a.R == b.R and a.G == b.G and a.B == b.B end
C3.__tostring = function(a) return ("%g, %g, %g"):format(a.R, a.G, a.B) end
local function color(r, g, b) return setmetatable({ R = r or 0, G = g or 0, B = b or 0 }, C3) end
function C3:Lerp(o, t) return color(self.R + (o.R - self.R) * t, self.G + (o.G - self.G) * t, self.B + (o.B - self.B) * t) end
function C3:ToHex() return ("%02X%02X%02X"):format(math.floor(self.R * 255 + 0.5), math.floor(self.G * 255 + 0.5), math.floor(self.B * 255 + 0.5)) end
function C3:ToHSV()
	local r, g, b = self.R, self.G, self.B
	local max, min = math.max(r, g, b), math.min(r, g, b)
	local d = max - min
	local h = 0
	if d > 0 then
		if max == r then h = ((g - b) / d) % 6
		elseif max == g then h = (b - r) / d + 2
		else h = (r - g) / d + 4 end
		h /= 6
	end
	return h, (if max == 0 then 0 else d / max), max
end
local function fromHSV(h, s, v)
	local i = math.floor(h * 6)
	local f = h * 6 - i
	local p, q, t = v * (1 - s), v * (1 - f * s), v * (1 - (1 - f) * s)
	i %= 6
	if i == 0 then return color(v, t, p) elseif i == 1 then return color(q, v, p) elseif i == 2 then return color(p, v, t)
	elseif i == 3 then return color(p, q, v) elseif i == 4 then return color(t, p, v) end
	return color(v, p, q)
end
local Color3 = {
	new = color,
	fromRGB = function(r, g, b) return color(r / 255, g / 255, b / 255) end,
	fromHSV = fromHSV,
	fromHex = function(hex)
		hex = hex:gsub("^#", "")
		return color(tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255)
	end,
}

local TweenInfo = { new = function(t, s, d) return setmetatable({ Time = t, EasingStyle = s, EasingDirection = d }, { __type = "TweenInfo" }) end }
local Random = {
	new = function()
		return { NextInteger = function(_, a, b) return math.random(a, b) end, NextNumber = function() return math.random() end }
	end,
}
local DateTime = {
	now = function()
		return {
			ToLocalTime = function() return { Year = 2026, Month = 10, Day = 11, Hour = 12, Minute = 0, Second = math.floor(H.TIME) % 60, Millisecond = 0 } end,
			FormatLocalTime = function() return "Oct 11 2026" end,
		}
	end,
}

----------------------------------------------------------------------
-- Enum
----------------------------------------------------------------------
local enumTypes = {}
local ENUM_ITEMS = {
	Material = { "Plastic", "Wood", "Slate", "Concrete", "Neon", "Glass", "SmoothPlastic", "Metal" },
	NormalId = { "Right", "Top", "Back", "Left", "Bottom", "Front" },
	Axis = { "X", "Y", "Z" },
	FontWeight = { "Thin", "ExtraLight", "Light", "Regular", "Medium", "SemiBold", "Bold", "ExtraBold", "Heavy" },
	FontStyle = { "Normal", "Italic" },
	ContentSourceType = { "None", "Uri", "Object" },
	PartType = { "Ball", "Block", "Cylinder", "Wedge", "CornerWedge" },
	SurfaceType = { "Smooth", "Glue", "Weld", "Studs", "Inlet", "Universal", "Hinge", "Motor", "SteppingMotor", "SmoothNoOutlines" },
}
local EnumItemMT = { __type = "EnumItem" }
EnumItemMT.__index = EnumItemMT
EnumItemMT.__tostring = function(self) return "Enum." .. self.EnumType .. "." .. self.Name end
local function enumType(name)
	local t = enumTypes[name]
	if t then return t end
	local items, order = {}, {}
	t = setmetatable({}, {
		__type = "Enum",
		__index = function(_, k)
			if k == "GetEnumItems" then
				return function()
					return table.clone(order)
				end
			end
			local item = items[k]
			if not item then
				item = setmetatable({ Name = k, EnumType = name, Value = #order }, EnumItemMT)
				items[k] = item
				table.insert(order, item)
			end
			return item
		end,
	})
	enumTypes[name] = t
	for _, n in ENUM_ITEMS[name] or {} do
		local _ = t[n]
	end
	return t
end
local Enum = setmetatable({}, { __index = function(_, k) return enumType(k) end })
-- ContextActionPriority.High.Value
local _ = Enum.ContextActionPriority.Default
rawset(getmetatable(Enum.ContextActionPriority.High), "__x", true)
Enum.ContextActionPriority.High.Value = 3000

----------------------------------------------------------------------
-- More datatypes (property values)
----------------------------------------------------------------------
local FontMT = { __type = "Font" }
FontMT.__eq = function(a, b) return a.Family == b.Family and a.Weight == b.Weight and a.Style == b.Style end
FontMT.__tostring = function(a) return ("Font { Family = %s, Weight = %s, Style = %s }"):format(a.Family, a.Weight.Name, a.Style.Name) end
local Font = {
	new = function(family, weight, style)
		assert(realType(family) == "string", "Font.new needs a family")
		return setmetatable({ Family = family, Weight = weight or Enum.FontWeight.Regular, Style = style or Enum.FontStyle.Normal }, FontMT)
	end,
}
function Font.fromName(name, weight, style) return Font.new("rbxasset://fonts/families/" .. name .. ".json", weight, style) end

-- CFrame: position + 3x3 rotation (row major)
local CF = { __type = "CFrame" }
local function cframe(x, y, z, r)
	return setmetatable({ _p = { x or 0, y or 0, z or 0 }, _r = r or { 1, 0, 0, 0, 1, 0, 0, 0, 1 } }, CF)
end
local function matmul(a, b)
	local r = {}
	for i = 0, 2 do
		for j = 0, 2 do
			r[i * 3 + j + 1] = a[i * 3 + 1] * b[j + 1] + a[i * 3 + 2] * b[3 + j + 1] + a[i * 3 + 3] * b[6 + j + 1]
		end
	end
	return r
end
local function rotX(a) local c, s = math.cos(a), math.sin(a) return { 1, 0, 0, 0, c, -s, 0, s, c } end
local function rotY(a) local c, s = math.cos(a), math.sin(a) return { c, 0, s, 0, 1, 0, -s, 0, c } end
local function rotZ(a) local c, s = math.cos(a), math.sin(a) return { c, -s, 0, s, c, 0, 0, 0, 1 } end
CF.__index = function(self, k)
	local p, r = rawget(self, "_p"), rawget(self, "_r")
	if k == "Position" or k == "p" then return vec3(p[1], p[2], p[3]) end
	if k == "X" then return p[1] end
	if k == "Y" then return p[2] end
	if k == "Z" then return p[3] end
	if k == "LookVector" then return vec3(-r[3], -r[6], -r[9]) end
	if k == "RightVector" then return vec3(r[1], r[4], r[7]) end
	if k == "UpVector" then return vec3(r[2], r[5], r[8]) end
	if k == "Rotation" then return cframe(0, 0, 0, table.clone(r)) end
	return rawget(CF, k)
end
function CF:GetComponents()
	local p, r = self._p, self._r
	return p[1], p[2], p[3], r[1], r[2], r[3], r[4], r[5], r[6], r[7], r[8], r[9]
end
CF.components = CF.GetComponents
function CF:ToOrientation()
	local r = self._r
	local x = math.asin(math.clamp(-r[6], -1, 1))
	local y = math.atan2(r[3], r[9])
	local z = math.atan2(r[4], r[5])
	return x, y, z
end
CF.__mul = function(a, b)
	if typeof(b) == "Vector3" then
		local r, p = a._r, a._p
		return vec3(r[1] * b.X + r[2] * b.Y + r[3] * b.Z + p[1], r[4] * b.X + r[5] * b.Y + r[6] * b.Z + p[2], r[7] * b.X + r[8] * b.Y + r[9] * b.Z + p[3])
	end
	local v = a * vec3(b._p[1], b._p[2], b._p[3])
	return cframe(v.X, v.Y, v.Z, matmul(a._r, b._r))
end
CF.__add = function(a, b) return cframe(a._p[1] + b.X, a._p[2] + b.Y, a._p[3] + b.Z, table.clone(a._r)) end
CF.__eq = function(a, b)
	for i = 1, 3 do if math.abs(a._p[i] - b._p[i]) > 1e-9 then return false end end
	for i = 1, 9 do if math.abs(a._r[i] - b._r[i]) > 1e-9 then return false end end
	return true
end
CF.__tostring = function(a) return table.concat({ a:GetComponents() }, ", ") end
local CFrame = {
	new = function(...)
		local n = select("#", ...)
		local a = { ... }
		if n == 0 then return cframe() end
		if n == 1 and typeof(a[1]) == "Vector3" then return cframe(a[1].X, a[1].Y, a[1].Z) end
		if n == 3 then return cframe(a[1], a[2], a[3]) end
		if n == 12 then return cframe(a[1], a[2], a[3], { a[4], a[5], a[6], a[7], a[8], a[9], a[10], a[11], a[12] }) end
		error("CFrame.new: bad arguments (" .. n .. ")", 2)
	end,
	Angles = function(x, y, z) return cframe(0, 0, 0, matmul(matmul(rotX(x), rotY(y)), rotZ(z))) end,
	fromOrientation = function(x, y, z) return cframe(0, 0, 0, matmul(matmul(rotY(y), rotX(x)), rotZ(z))) end,
}
CFrame.fromEulerAnglesXYZ = CFrame.Angles
CFrame.fromEulerAnglesYXZ = CFrame.fromOrientation
CFrame.identity = cframe()

local function simple(typeName, fields)
	local mt = { __type = typeName }
	mt.__eq = function(a, b)
		for _, f in fields do if rawget(a, f) ~= rawget(b, f) then return false end end
		return true
	end
	mt.__tostring = function(a)
		local parts = {}
		for _, f in fields do table.insert(parts, tostring(rawget(a, f))) end
		return table.concat(parts, " ")
	end
	return mt
end

local NRMT = simple("NumberRange", { "Min", "Max" })
local NumberRange = { new = function(a, b)
	b = b or a
	if b < a then error("NumberRange: invalid range", 2) end
	return setmetatable({ Min = a, Max = b }, NRMT)
end }
local RectMT = simple("Rect", { "Min", "Max" })
RectMT.__index = function(self, k)
	if k == "Width" then return rawget(self, "Max").X - rawget(self, "Min").X end
	if k == "Height" then return rawget(self, "Max").Y - rawget(self, "Min").Y end
	return nil
end
local Rect = { new = function(a, b, c, d)
	if typeof(a) == "Vector2" then return setmetatable({ Min = a, Max = b }, RectMT) end
	return setmetatable({ Min = vec2(a or 0, b or 0), Max = vec2(c or 0, d or 0) }, RectMT)
end }
local V2i = simple("Vector2int16", { "X", "Y" })
local Vector2int16 = { new = function(x, y) return setmetatable({ X = math.floor(x or 0), Y = math.floor(y or 0) }, V2i) end }
local V3i = simple("Vector3int16", { "X", "Y", "Z" })
local Vector3int16 = { new = function(x, y, z) return setmetatable({ X = math.floor(x or 0), Y = math.floor(y or 0), Z = math.floor(z or 0) }, V3i) end }

local NKMT = simple("NumberSequenceKeypoint", { "Time", "Value", "Envelope" })
local NumberSequenceKeypoint = { new = function(t, v, e) return setmetatable({ Time = t, Value = v, Envelope = e or 0 }, NKMT) end }
local function checkKeys(keys, what)
	if #keys < 2 then error(what .. ": requires at least 2 keypoints", 3) end
	if keys[1].Time ~= 0 or keys[#keys].Time ~= 1 then error(what .. ": must start at time 0 and end at time 1", 3) end
	for i = 2, #keys do
		if keys[i].Time < keys[i - 1].Time then error(what .. ": all keypoints must be ordered by time", 3) end
	end
end
local NSMT = { __type = "NumberSequence" }
NSMT.__eq = function(a, b)
	if #a.Keypoints ~= #b.Keypoints then return false end
	for i, k in a.Keypoints do if k ~= b.Keypoints[i] then return false end end
	return true
end
NSMT.__tostring = function(a)
	local parts = {}
	for _, k in a.Keypoints do table.insert(parts, ("%g %g %g"):format(k.Time, k.Value, k.Envelope)) end
	return table.concat(parts, " ")
end
local NumberSequence = { new = function(a, b)
	local keys
	if realType(a) == "number" then
		keys = { NumberSequenceKeypoint.new(0, a), NumberSequenceKeypoint.new(1, b or a) }
	else
		keys = table.clone(a)
	end
	checkKeys(keys, "NumberSequence")
	return setmetatable({ Keypoints = keys }, NSMT)
end }
local CKMT = simple("ColorSequenceKeypoint", { "Time", "Value" })
local ColorSequenceKeypoint = { new = function(t, c) return setmetatable({ Time = t, Value = c }, CKMT) end }
local CSMT = { __type = "ColorSequence" }
CSMT.__eq = NSMT.__eq
CSMT.__tostring = function(a)
	local parts = {}
	for _, k in a.Keypoints do table.insert(parts, ("%g %s"):format(k.Time, tostring(k.Value))) end
	return table.concat(parts, " ")
end
local ColorSequence = { new = function(a, b)
	local keys
	if typeof(a) == "Color3" then
		keys = { ColorSequenceKeypoint.new(0, a), ColorSequenceKeypoint.new(1, b or a) }
	else
		keys = table.clone(a)
	end
	checkKeys(keys, "ColorSequence")
	return setmetatable({ Keypoints = keys }, CSMT)
end }

local FACE_NAMES = { "Right", "Top", "Back", "Left", "Bottom", "Front" }
local FacesMT = simple("Faces", FACE_NAMES)
local Faces = { new = function(...)
	local f = { Right = false, Top = false, Back = false, Left = false, Bottom = false, Front = false }
	for _, item in { ... } do
		assert(typeof(item) == "EnumItem" and item.EnumType == "NormalId", "Faces.new takes NormalId items")
		f[item.Name] = true
	end
	return setmetatable(f, FacesMT)
end }
local AxesMT = simple("Axes", { "X", "Y", "Z" })
local Axes = { new = function(...)
	local a = { X = false, Y = false, Z = false }
	local map = { Right = "X", Left = "X", Top = "Y", Bottom = "Y", Back = "Z", Front = "Z" }
	for _, item in { ... } do
		assert(typeof(item) == "EnumItem", "Axes.new takes Axis or NormalId items")
		a[if item.EnumType == "Axis" then item.Name else map[item.Name]] = true
	end
	return setmetatable(a, AxesMT)
end }

local PPMT = simple("PhysicalProperties", { "Density", "Friction", "Elasticity", "FrictionWeight", "ElasticityWeight" })
local PhysicalProperties = { new = function(d, f, e, fw, ew)
	if typeof(d) == "EnumItem" then
		return setmetatable({ Density = 0.7, Friction = 0.3, Elasticity = 0.5, FrictionWeight = 1, ElasticityWeight = 1 }, PPMT)
	end
	assert(realType(d) == "number" and realType(f) == "number" and realType(e) == "number", "PhysicalProperties.new: bad arguments")
	return setmetatable({ Density = d, Friction = f, Elasticity = e, FrictionWeight = fw or 1, ElasticityWeight = ew or 1 }, PPMT)
end }
local RayMT = simple("Ray", { "Origin", "Direction" })
local Ray = { new = function(o, d) return setmetatable({ Origin = o, Direction = d }, RayMT) end }

local ContentMT = simple("Content", { "SourceType", "Uri", "Object" })
local Content = {}
function Content.fromUri(uri) return setmetatable({ SourceType = Enum.ContentSourceType.Uri, Uri = uri }, ContentMT) end
function Content.fromObject(obj) return setmetatable({ SourceType = Enum.ContentSourceType.Object, Object = obj }, ContentMT) end
Content.none = setmetatable({ SourceType = Enum.ContentSourceType.None }, ContentMT)

-- BrickColor: a small palette of named colors
local BRICK = {
	{ 1, "White", 242, 243, 243 }, { 194, "Medium stone grey", 163, 162, 165 }, { 21, "Bright red", 196, 40, 28 },
	{ 23, "Bright blue", 13, 105, 172 }, { 24, "Bright yellow", 245, 205, 48 }, { 28, "Dark green", 40, 127, 71 },
	{ 26, "Black", 27, 42, 53 }, { 1001, "Institutional white", 248, 248, 248 }, { 1003, "Really black", 17, 17, 17 },
	{ 1004, "Really red", 255, 0, 0 }, { 1010, "Really blue", 0, 0, 255 }, { 1020, "Lime green", 0, 255, 0 },
}
H.BRICK = BRICK
local BCMT = { __type = "BrickColor" }
BCMT.__eq = function(a, b) return a.Number == b.Number end
BCMT.__tostring = function(a) return a.Name end
local function brick(entry)
	return setmetatable({ Number = entry[1], Name = entry[2], Color = color(entry[3] / 255, entry[4] / 255, entry[5] / 255) }, BCMT)
end
local BrickColor = {
	new = function(x)
		if typeof(x) == "Color3" then
			local best, bestD = BRICK[1], math.huge
			for _, entry in BRICK do
				local d = (entry[3] / 255 - x.R) ^ 2 + (entry[4] / 255 - x.G) ^ 2 + (entry[5] / 255 - x.B) ^ 2
				if d < bestD then best, bestD = entry, d end
			end
			return brick(best)
		end
		for _, entry in BRICK do
			if entry[1] == x or entry[2] == x then return brick(entry) end
		end
		if realType(x) == "number" then return brick(BRICK[2]) end
		error("BrickColor.new: unknown color " .. tostring(x), 2)
	end,
	palette = function(i)
		return brick(BRICK[(i % #BRICK) + 1])
	end,
}
H.Datatypes = {
	CFrame = CFrame, NumberRange = NumberRange, Rect = Rect, Vector2int16 = Vector2int16, Vector3int16 = Vector3int16,
	NumberSequence = NumberSequence, NumberSequenceKeypoint = NumberSequenceKeypoint, ColorSequence = ColorSequence,
	ColorSequenceKeypoint = ColorSequenceKeypoint, Faces = Faces, Axes = Axes, PhysicalProperties = PhysicalProperties,
	Ray = Ray, Content = Content, BrickColor = BrickColor, Font = Font,
}

----------------------------------------------------------------------
-- Scheduler (virtual time)
----------------------------------------------------------------------
local timers = {} -- { at, thread|fn, args }
local deferred = {}

local function resume(co, ...)
	local ok, err = coroutine.resume(co, ...)
	if not ok then
		table.insert(H.ERRORS, debug.traceback(co, tostring(err)))
		print("TASK ERROR: " .. tostring(err))
	end
end

local task = {}
function task.spawn(f, ...)
	local co = if realType(f) == "thread" then f else coroutine.create(f)
	resume(co, ...)
	return co
end
function task.defer(f, ...)
	local co = if realType(f) == "thread" then f else coroutine.create(f)
	table.insert(deferred, { co, table.pack(...) })
	return co
end
function task.delay(t, f, ...)
	local co = if realType(f) == "thread" then f else coroutine.create(f)
	table.insert(timers, { At = H.TIME + (t or 0), Co = co, Args = table.pack(...) })
	return co
end
function task.wait(t)
	local co = coroutine.running()
	table.insert(timers, { At = H.TIME + (t or 1 / 60), Co = co, Args = table.pack() })
	coroutine.yield()
	return t
end
function task.cancel(co)
	for i = #timers, 1, -1 do
		if timers[i].Co == co then table.remove(timers, i) end
	end
	pcall(coroutine.close, co)
end

local function runDeferred()
	local guard = 0
	while #deferred > 0 and guard < 1000 do
		guard += 1
		local list = deferred
		deferred = {}
		for _, d in list do
			if coroutine.status(d[1]) == "suspended" then
				resume(d[1], table.unpack(d[2], 1, d[2].n))
			end
		end
	end
end
H.runDeferred = runDeferred

----------------------------------------------------------------------
-- Instances
----------------------------------------------------------------------
local SCREEN = vec2(1280, 720)
H.SCREEN = SCREEN

local CLASS_PARENTS = {
	Frame = "GuiObject", TextLabel = "GuiObject", TextButton = "GuiButton", ImageButton = "GuiButton",
	TextBox = "GuiObject", ImageLabel = "GuiObject", ScrollingFrame = "GuiObject", CanvasGroup = "GuiObject",
	GuiButton = "GuiObject", GuiObject = "GuiBase2d", ScreenGui = "LayerCollector", LayerCollector = "GuiBase2d",
	GuiBase2d = "Instance", Part = "BasePart", MeshPart = "BasePart", BasePart = "PVInstance", Model = "PVInstance",
	PVInstance = "Instance", Folder = "Instance",
	Workspace = "WorldRoot", WorldRoot = "Model", WedgePart = "BasePart", SpawnLocation = "Part",
	LocalScript = "Script", Script = "BaseScript", BaseScript = "LuaSourceContainer", ModuleScript = "LuaSourceContainer",
	LuaSourceContainer = "Instance", RemoteEvent = "BaseRemoteEvent", UnreliableRemoteEvent = "BaseRemoteEvent",
	BaseRemoteEvent = "Instance", StringValue = "ValueBase", ObjectValue = "ValueBase", IntValue = "ValueBase",
	ValueBase = "Instance",
	Humanoid = "Instance", Animator = "Instance", ClickDetector = "Instance", ProximityPrompt = "Instance",
	TouchTransmitter = "Instance", Tween = "TweenBase", TweenBase = "Instance", Animation = "Instance",
	Player = "Instance", Players = "Instance", RemoteFunction = "Instance", BindableEvent = "Instance",
	BindableFunction = "Instance", Camera = "Instance",
}
H.CLASS_PARENTS = CLASS_PARENTS
local function isA(class, base)
	while class do
		if class == base then return true end
		class = CLASS_PARENTS[class]
	end
	return base == "Instance"
end

local EVENTS = {
	InputBegan = true, InputChanged = true, InputEnded = true, MouseEnter = true, MouseLeave = true,
	Activated = true, MouseButton1Down = true, MouseButton1Up = true, MouseButton2Down = true, MouseButton1Click = true,
	Focused = true, FocusLost = true, AncestryChanged = true, ChildAdded = true, ChildRemoved = true, Changed = true,
	Touched = true, Destroying = true, DescendantAdded = true, DescendantRemoving = true, AttributeChanged = true,
}

local DEFAULTS = {
	Visible = true, Size = udim2(0, 0, 0, 0), Position = udim2(0, 0, 0, 0), AnchorPoint = vec2(0, 0),
	BackgroundTransparency = 0, ZIndex = 1, Text = "", Enabled = true, Rotation = 0, LayoutOrder = 0,
	TextTransparency = 0, ImageColor3 = color(1, 1, 1), Image = "", TextEditable = true, Scale = 1,
}

local Instances = {}
local InstanceMT = { __type = "Instance" }
local methods = {}

local function newInstance(class)
	local obj = { _class = class, _props = { Name = class }, _children = {}, _events = {}, _changed = {}, _attrs = {} }
	setmetatable(obj, InstanceMT)
	table.insert(Instances, obj)
	return obj
end

local VERSION = 0
local cache = {}
local absSize, absPos

local function childByClass(obj, class)
	for _, c in obj._children do
		if c._class == class then return c end
	end
	return nil
end

-- UIScale like the engine: a UIScale inside a GuiObject multiplies the
-- object's size (about its AnchorPoint) and every offset inside it, so
-- AbsoluteSize / AbsolutePosition report scaled, on-screen pixels.
-- TextService:GetTextSize is not affected (it measures unscaled text).
local function ownScale(obj)
	if not isA(obj._class, "GuiObject") then return 1 end
	local s = childByClass(obj, "UIScale")
	if not s then return 1 end
	return s._props.Scale or 1
end

local function kOf(obj)
	if obj == nil or not isA(obj._class, "GuiObject") then return 1 end
	local c = cache[obj]
	if c and c.V == VERSION and c.K then return c.K end
	local k = kOf(obj._props.Parent) * ownScale(obj)
	cache[obj] = cache[obj] and cache[obj].V == VERSION and cache[obj] or { V = VERSION }
	cache[obj].K = k
	return k
end
H.scaleOf = kOf

local function padding(obj)
	local pad = childByClass(obj, "UIPadding")
	if not pad then return 0, 0, 0, 0 end
	local p = pad._props
	local k = kOf(obj)
	local function o(u) return if u then u.Offset * k else 0 end
	return o(p.PaddingLeft), o(p.PaddingTop), o(p.PaddingRight), o(p.PaddingBottom)
end

local function layoutChildren(obj)
	local list = {}
	for _, c in obj._children do
		if isA(c._class, "GuiObject") and c._props.Visible ~= false then table.insert(list, c) end
	end
	table.sort(list, function(a, b)
		local la, lb = a._props.LayoutOrder or 0, b._props.LayoutOrder or 0
		if la ~= lb then return la < lb end
		return table.find(obj._children, a) < table.find(obj._children, b)
	end)
	return list
end

local function textExtent(obj)
	local p = obj._props
	if obj._class == "TextLabel" or obj._class == "TextButton" or obj._class == "TextBox" then
		local text = p.Text or ""
		local size = p.TextSize or 14
		return vec2(#text * size * 0.55, if text == "" then 0 else size)
	end
	return vec2(0, 0)
end

-- Size of children content (offsets only), plus padding.
local function contentSize(obj)
	local l, t, r, b = padding(obj)
	local k = kOf(obj)
	local layout = childByClass(obj, "UIListLayout")
	local grid = childByClass(obj, "UIGridLayout")
	local w, h = 0, 0
	if grid then
		local g = grid._props
		local kids = layoutChildren(obj)
		local cols = math.max(1, math.min(#kids, g.FillDirectionMaxCells or 1))
		local rows = math.ceil(#kids / cols)
		w = (cols * g.CellSize.X.Offset + (cols - 1) * g.CellPadding.X.Offset) * k
		h = (rows * g.CellSize.Y.Offset + math.max(0, rows - 1) * g.CellPadding.Y.Offset) * k
	elseif layout then
		local horizontal = layout._props.FillDirection == Enum.FillDirection.Horizontal
		local gap = (if layout._props.Padding then layout._props.Padding.Offset else 0) * k
		local kids = layoutChildren(obj)
		for i, c in kids do
			local cs = absSize(c)
			if horizontal then
				w += cs.X + (if i > 1 then gap else 0)
				h = math.max(h, cs.Y)
			else
				h += cs.Y + (if i > 1 then gap else 0)
				w = math.max(w, cs.X)
			end
		end
	else
		for _, c in obj._children do
			if isA(c._class, "GuiObject") and c._props.Visible ~= false then
				local s = c._props.Size or DEFAULTS.Size
				local pos = c._props.Position or DEFAULTS.Position
				local cs = absSize(c)
				w = math.max(w, pos.X.Offset * k + (if s.X.Scale == 0 then cs.X else 0))
				h = math.max(h, pos.Y.Offset * k + (if s.Y.Scale == 0 then cs.Y else 0))
			end
		end
	end
	local te = textExtent(obj) * k
	w = math.max(w, te.X)
	h = math.max(h, te.Y)
	return vec2(w + l + r, h + t + b)
end

local function innerOf(parent, baseOnly)
	local ps = absSize(parent, baseOnly)
	local l, t, r, b = padding(parent)
	return vec2(ps.X - l - r, ps.Y - t - b), vec2(l, t)
end

absSize = function(obj, baseOnly)
	local c = cache[obj]
	if not baseOnly and c and c.V == VERSION and c.Size then return c.Size end
	local p = obj._props
	local result
	local pgrid = obj._props.Parent and childByClass(obj._props.Parent, "UIGridLayout")
	if obj._class == "ScreenGui" or obj._class == "Folder" or obj._class == "HUI" then
		result = SCREEN
	elseif pgrid and isA(obj._class, "GuiObject") then
		local k = kOf(obj)
		result = vec2(pgrid._props.CellSize.X.Offset * k, pgrid._props.CellSize.Y.Offset * k)
	elseif not isA(obj._class, "GuiObject") then
		result = vec2(0, 0)
	else
		local parent = p.Parent
		local s = p.Size or DEFAULTS.Size
		local pa = parent and parent._props.AutomaticSize
		local parentAuto = pa ~= nil and pa ~= Enum.AutomaticSize.None
		local ps = if parent then (innerOf(parent, parentAuto)) else SCREEN
		local auto = p.AutomaticSize
		local autoX = auto == Enum.AutomaticSize.X or auto == Enum.AutomaticSize.XY
		local autoY = auto == Enum.AutomaticSize.Y or auto == Enum.AutomaticSize.XY
		-- parent auto axis: scale counts as 0
		local pauto = parent and parent._props.AutomaticSize
		local pAutoX = pauto == Enum.AutomaticSize.X or pauto == Enum.AutomaticSize.XY
		local pAutoY = pauto == Enum.AutomaticSize.Y or pauto == Enum.AutomaticSize.XY
		local own, k = ownScale(obj), kOf(obj)
		local x = (if pAutoX then 0 else ps.X * s.X.Scale * own) + s.X.Offset * k
		local y = (if pAutoY then 0 else ps.Y * s.Y.Scale * own) + s.Y.Offset * k
		if (autoX or autoY) and not baseOnly then
			local cs = contentSize(obj)
			if autoX then x = math.max(x, cs.X) end
			if autoY then y = math.max(y, cs.Y) end
		end
		result = vec2(x, y)
	end
	if baseOnly then return result end
	cache[obj] = cache[obj] and cache[obj].V == VERSION and cache[obj] or { V = VERSION }
	cache[obj].Size = result
	return result
end

absPos = function(obj)
	local c = cache[obj]
	if c and c.V == VERSION and c.Pos then return c.Pos end
	local p = obj._props
	local result
	if obj._class == "ScreenGui" or obj._class == "Folder" or obj._class == "HUI" or not isA(obj._class, "GuiObject") then
		-- Roblox quirk: AbsolutePosition may be measured from below the top bar.
		result = vec2(0, -(H.ABS_SHIFT or 0))
	else
		local parent = p.Parent
		local pp = if parent then absPos(parent) else vec2(0, 0)
		local inner, off = vec2(SCREEN.X, SCREEN.Y), vec2(0, 0)
		if parent then inner, off = innerOf(parent) end
		local layout = parent and childByClass(parent, "UIListLayout")
		local grid = parent and childByClass(parent, "UIGridLayout")
		local kp = kOf(parent)
		if grid then
			local g = grid._props
			local kids = layoutChildren(parent)
			local cols = math.max(1, math.min(#kids, g.FillDirectionMaxCells or 1))
			local i = (table.find(kids, obj) or 1) - 1
			local cx, cy = i % cols, i // cols
			result = vec2(pp.X + off.X + cx * (g.CellSize.X.Offset + g.CellPadding.X.Offset) * kp, pp.Y + off.Y + cy * (g.CellSize.Y.Offset + g.CellPadding.Y.Offset) * kp)
		elseif layout then
			local horizontal = layout._props.FillDirection == Enum.FillDirection.Horizontal
			local gap = (if layout._props.Padding then layout._props.Padding.Offset else 0) * kp
			local along = 0
			for _, k in layoutChildren(parent) do
				if k == obj then break end
				local ks = absSize(k)
				along += (if horizontal then ks.X else ks.Y) + gap
			end
			result = if horizontal then vec2(pp.X + off.X + along, pp.Y + off.Y) else vec2(pp.X + off.X, pp.Y + off.Y + along)
		else
			local pos = p.Position or DEFAULTS.Position
			local a = p.AnchorPoint or DEFAULTS.AnchorPoint
			local size = absSize(obj)
			result = vec2(
				pp.X + off.X + inner.X * pos.X.Scale + pos.X.Offset * kp - a.X * size.X,
				pp.Y + off.Y + inner.Y * pos.Y.Scale + pos.Y.Offset * kp - a.Y * size.Y
			)
		end
	end
	cache[obj] = cache[obj] and cache[obj].V == VERSION and cache[obj] or { V = VERSION }
	cache[obj].Pos = result
	return result
end

InstanceMT.__index = function(self, k)
	if k == "ClassName" then return self._class end
	if k == "AbsoluteSize" then return absSize(self) end
	if k == "AbsolutePosition" then return absPos(self) end
	if k == "AbsoluteWindowSize" then return absSize(self) end
	if k == "ViewportSize" then return SCREEN end
	if methods[k] then return methods[k] end
	if EVENTS[k] then
		local s = self._events[k]
		if not s then
			s = newSignal()
			self._events[k] = s
		end
		return s
	end
	local v = self._props[k]
	if v ~= nil then return v end
	if DEFAULTS[k] ~= nil then return DEFAULTS[k] end
	for _, child in self._children do
		if child._props.Name == k then return child end
	end
	if self._class == "TextButton" or self._class == "TextLabel" or self._class == "TextBox" or self._class == "Frame" or self._class == "ImageLabel" then
		return nil
	end
	return nil
end

InstanceMT.__newindex = function(self, k, v)
	if self._destroyed and k ~= "Parent" then
		error("cannot set " .. k .. " on destroyed " .. self._class, 2)
	end
	if k == "Parent" then
		local old = self._props.Parent
		if old == v then return end
		if self._locked then error("parent locked (destroyed)", 2) end
		if self._lockedParent then
			error(("The Parent property of %s is locked, current parent: %s, new parent %s"):format(self._props.Name, tostring(old), tostring(v)), 2)
		end
		if v ~= nil and getmetatable(v) ~= InstanceMT then error("Parent must be an Instance", 2) end
		if old then
			-- like the engine: DescendantRemoving before the move
			local cur = old
			while cur do
				local ev = cur._events.DescendantRemoving
				if ev then
					ev:Fire(self)
					for _, d in self:GetDescendants() do ev:Fire(d) end
				end
				cur = cur._props.Parent
			end
			local i = table.find(old._children, self)
			if i then table.remove(old._children, i) end
		end
		self._props.Parent = v
		VERSION += 1
		if v then
			table.insert(v._children, self)
		end
		local s = self._changed.Parent
		if s then s:Fire() end
		if old and old._events.ChildRemoved then old._events.ChildRemoved:Fire(self) end
		if v and v._events.ChildAdded then v._events.ChildAdded:Fire(self) end
		local function ancestry(o)
			local ev = o._events.AncestryChanged
			if ev then ev:Fire(self, v) end
			for _, c in o._children do ancestry(c) end
		end
		ancestry(self)
		local cur = v
		while cur do
			local ev = cur._events.DescendantAdded
			if ev then
				ev:Fire(self)
				for _, d in self:GetDescendants() do ev:Fire(d) end
			end
			cur = cur._props.Parent
		end
		return
	end
	if realType(v) == "number" and v ~= v then
		error("NaN assigned to " .. k, 2)
	end
	if (k == "Size" or k == "Position") and typeof(v) ~= "UDim2" and isA(self._class, "GuiBase2d") then
		error(("bad %s: %s"):format(k, typeof(v)), 2)
	end
	if (k == "BackgroundColor3" or k == "TextColor3" or k == "ImageColor3" or k == "Color" or k == "ScrollBarImageColor3" or k == "PlaceholderColor3") and typeof(v) ~= "Color3" and not (self._class == "UIGradient" and typeof(v) == "ColorSequence") and self._class ~= "ParticleEmitter" then
		error(("bad %s: %s"):format(k, typeof(v)), 2)
	end
	if k == "Text" and realType(v) ~= "string" then
		error("Text must be a string, got " .. typeof(v), 2)
	end
	if self._readonly and self._readonly[k] then
		error(("Unable to assign property %s. Property is read only"):format(k), 2)
	end
	if self._typed and self._typed[k] and v ~= nil and typeof(v) ~= self._typed[k] then
		error(("Unable to assign property %s. %s expected, got %s"):format(k, self._typed[k], typeof(v)), 2)
	end
	local old = self._props[k]
	self._props[k] = v
	VERSION += 1
	if old ~= v then
		local s = self._changed[k]
		if s then s:Fire() end
		local changed = self._events.Changed
		if changed then changed:Fire(k) end
		if k == "Text" and self._class == "TextBox" then
			-- fine
		end
	end
end
InstanceMT.__tostring = function(self) return self._props.Name end

function methods:GetPropertyChangedSignal(prop)
	local s = self._changed[prop]
	if not s then
		s = newSignal()
		self._changed[prop] = s
	end
	return s
end
function methods:GetChildren() return table.clone(self._children) end
function methods:GetDescendants()
	local out = {}
	local function walk(o)
		for _, c in o._children do
			table.insert(out, c)
			walk(c)
		end
	end
	walk(self)
	return out
end
function methods:FindFirstChild(name, recursive)
	for _, c in self._children do
		if c._props.Name == name then return c end
	end
	if recursive then
		for _, c in self._children do
			local f = c:FindFirstChild(name, true)
			if f then return f end
		end
	end
	return nil
end
function methods:FindFirstChildWhichIsA(class, recursive)
	for _, c in self._children do
		if isA(c._class, class) then return c end
	end
	if recursive then
		for _, c in self._children do
			local f = c:FindFirstChildWhichIsA(class, true)
			if f then return f end
		end
	end
	return nil
end
function methods:Clone()
	if self._props.Archivable == false then
		return nil
	end
	local copy = newInstance(self._class)
	for k, v in self._props do
		if k ~= "Parent" then
			copy._props[k] = v
		end
	end
	for _, child in self._children do
		local c = child:Clone()
		if c then
			c.Parent = copy
		end
	end
	return copy
end
function methods:FindFirstAncestorWhichIsA(class)
	local p = self._props.Parent
	while p do
		if isA(p._class, class) then return p end
		p = p._props.Parent
	end
	return nil
end
function methods:GetPlayers()
	local out = {}
	for _, c in self._children do
		if c._class == "Player" then table.insert(out, c) end
	end
	return out
end
function methods:LoadAnimation(animation)
	local track = { Animation = animation, Playing = false }
	function track:Play() self.Playing = true end
	function track:Stop() self.Playing = false end
	H.TRACKS = H.TRACKS or {}
	table.insert(H.TRACKS, track)
	return track
end
function methods:Play()
	self._props.PlayCount = (self._props.PlayCount or 0) + 1
end
function methods:GetService(name)
	if self._class ~= "DataModel" then error("GetService is not a valid member of " .. self._class, 2) end
	local s = H.services[name]
	assert(s, "mock service missing: " .. tostring(name))
	return s
end
function methods:FindService(name)
	if self._class ~= "DataModel" then error("FindService is not a valid member", 2) end
	return H.services[name]
end
function methods:FindFirstChildOfClass(class)
	for _, c in self._children do
		if c._class == class then return c end
	end
	return nil
end
function methods:IsA(class) return isA(self._class, class) end
function methods:IsDescendantOf(other)
	local p = self._props.Parent
	while p do
		if p == other then return true end
		p = p._props.Parent
	end
	return false
end
function methods:Destroy()
	if self._lockedParent then
		error(("The Parent property of %s is locked, current parent: %s, new parent NULL"):format(self._props.Name, tostring(self._props.Parent)), 2)
	end
	if self._destroyed then return end
	-- like the engine: a destroyed text box loses focus
	if H.focused and (H.focused == self or H.focused:IsDescendantOf(self)) then
		H.focusBox(nil)
	end
	local ev = self._events.Destroying
	if ev then ev:Fire() end
	for _, c in table.clone(self._children) do c:Destroy() end
	self.Parent = nil
	self._destroyed = true
	rawset(self, "_locked", true)
	for _, s in self._events do
		for _, c in s._c do c.Connected = false end
	end
	for _, s in self._changed do
		for _, c in s._c do c.Connected = false end
	end
end
function methods:ClearAllChildren()
	for _, c in table.clone(self._children) do c:Destroy() end
end
function methods:SetAttribute(k, v)
	if realType(k) ~= "string" or #k > 100 or not k:match("^[%w_]+$") or k:sub(1, 3) == "RBX" then
		error("Attribute name is not valid: " .. tostring(k), 2)
	end
	local allowed = { string = true, boolean = true, number = true, UDim = true, UDim2 = true, BrickColor = true,
		Color3 = true, Vector2 = true, Vector3 = true, CFrame = true, NumberSequence = true, ColorSequence = true,
		NumberRange = true, Rect = true, Font = true, EnumItem = true, ["nil"] = true }
	if not allowed[typeof(v)] then
		error(typeof(v) .. " is not a supported attribute type", 2)
	end
	local old = self._attrs[k]
	self._attrs[k] = v
	if old ~= v then
		local ev = self._events.AttributeChanged
		if ev then ev:Fire(k) end
		local s = self._attrSignals and self._attrSignals[k]
		if s then s:Fire() end
	end
end
function methods:GetAttribute(k) return self._attrs[k] end
function methods:GetAttributes() return table.clone(self._attrs) end
function methods:GetAttributeChangedSignal(k)
	self._attrSignals = self._attrSignals or {}
	local s = self._attrSignals[k]
	if not s then
		s = newSignal()
		self._attrSignals[k] = s
	end
	return s
end
function methods:AddTag(tag)
	self._tags = self._tags or {}
	if not table.find(self._tags, tag) then table.insert(self._tags, tag) end
end
function methods:RemoveTag(tag)
	local i = self._tags and table.find(self._tags, tag)
	if i then table.remove(self._tags, i) end
end
function methods:HasTag(tag) return self._tags ~= nil and table.find(self._tags, tag) ~= nil end
function methods:GetTags() return table.clone(self._tags or {}) end
function methods:GetFullName()
	local parts = {}
	local cur = self
	while cur and cur._class ~= "DataModel" do
		table.insert(parts, 1, cur._props.Name)
		cur = cur._props.Parent
	end
	return table.concat(parts, ".")
end
function methods:CaptureFocus()
	H.focusBox(self)
end
function methods:ReleaseFocus()
	if H.focused == self then H.focusBox(nil) end
end
function methods:IsFocused() return H.focused == self end

-- Text objects start with Roblox's own default text, so code that forgets
-- to set Text shows up in tests the way it would in the game.
local DEFAULT_TEXT = { TextLabel = "Label", TextButton = "Button", TextBox = "TextBox" }
local Instance = {
	new = function(class, parent)
		local o = newInstance(class)
		if DEFAULT_TEXT[class] then
			o._props.Text = DEFAULT_TEXT[class]
		end
		if parent then o.Parent = parent end
		return o
	end,
}
H.Instances = Instances

-- A Part with the properties the panel reads (typed like the engine).
function H.part(name, parent, props)
	local p = newInstance("Part")
	local d = p._props
	d.Name = name or "Part"
	d.Anchored = false
	d.CanCollide = true
	d.CanTouch = true
	d.CanQuery = true
	d.CastShadow = true
	d.Locked = false
	d.Archivable = true
	d.Transparency = 0
	d.Reflectance = 0
	d.Size = vec3(4, 1, 2)
	d.CFrame = CFrame.new(0, 5, 0)
	d.Position = vec3(0, 5, 0)
	d.Orientation = vec3(0, 0, 0)
	d.Color = color(163 / 255, 162 / 255, 165 / 255)
	d.BrickColor = BrickColor.new("Medium stone grey")
	d.Material = Enum.Material.Plastic
	d.Shape = Enum.PartType.Block
	d.TopSurface = Enum.SurfaceType.Smooth
	d.Mass = 0.7
	d.AssemblyMass = 0.7
	d.CustomPhysicalProperties = nil
	p._readonly = { Mass = true, AssemblyMass = true, ClassName = true }
	p._typed = { Anchored = "boolean", CanCollide = "boolean", Transparency = "number", Size = "Vector3", CFrame = "CFrame",
		Color = "Color3", Material = "EnumItem", Name = "string", BrickColor = "BrickColor" }
	for k, v in props or {} do d[k] = v end
	if parent then p.Parent = parent end
	return p
end
H.NIL = {} -- what getnilinstances returns
H.LOADED = {} -- what getloadedmodules returns
H.HIDDEN = {} -- property names gethiddenproperty reports as hidden

----------------------------------------------------------------------
-- Services
----------------------------------------------------------------------
local UIS = {
	InputBegan = newSignal(),
	InputChanged = newSignal(),
	InputEnded = newSignal(),
	TextBoxFocused = newSignal(),
	PointerAction = newSignal(),
	WindowFocusReleased = newSignal(),
}
H.keys = {}
H.mouse = vec2(0, 0)
H.focused = nil
function UIS:IsKeyDown(key) return H.keys[key.Name] == true end
function UIS:GetMouseLocation() return H.mouse end
function UIS:GetFocusedTextBox() return H.focused end
H.UIS = UIS

function H.focusBox(box)
	local old = H.focused
	if old == box then return end
	H.focused = box
	if old then old.FocusLost:Fire(false) end
	if box then box.Focused:Fire() end
end

local TweenService = {}
H.tweens = 0
function TweenService:Create(inst, info, goal)
	assert(typeof(inst) == "Instance", "tween target")
	return {
		Play = function()
			H.tweens += 1
			for k, v in goal do inst[k] = v end
		end,
		Cancel = function() end,
	}
end

local RunService = { RenderStepped = newSignal(), Heartbeat = newSignal(), Stepped = newSignal() }
local TextService = {}
function TextService:GetTextSize(text, size, font, bounds)
	return vec2(#text * size * 0.55, size)
end
local CAS = { bound = {} }
function CAS:BindActionAtPriority(name, fn, touch, priority, ...)
	assert(realType(priority) == "number", "priority must be a number")
	self.bound[name] = fn
end
function CAS:UnbindAction(name) self.bound[name] = nil end
H.CAS = CAS
local GuiService = {}
function GuiService:GetGuiInset() return vec2(0, 58), vec2(0, 0) end

-- tiny JSON
local function encode(v)
	local t = realType(v)
	if t == "table" then
		if #v > 0 or next(v) == nil then
			local parts = {}
			for _, x in ipairs(v) do table.insert(parts, encode(x)) end
			return "[" .. table.concat(parts, ",") .. "]"
		end
		local parts = {}
		for k, x in v do table.insert(parts, ("%q:%s"):format(tostring(k), encode(x))) end
		table.sort(parts)
		return "{" .. table.concat(parts, ",") .. "}"
	elseif t == "string" then
		return ("%q"):format(v)
	elseif t == "number" then
		return tostring(v)
	elseif t == "boolean" then
		return tostring(v)
	end
	return "null"
end
local function decode(s)
	local src = s:gsub('"([^"]-)":', '["%1"]='):gsub("%[", "{"):gsub("%]", "}")
	src = src:gsub('{"([^"]-)"}=', '["%1"]=')
	local f = loadstring("return " .. src)
	if not f then error("bad json") end
	return f()
end
local HttpService = {}
function HttpService:JSONEncode(v) return encode(v) end
function HttpService:JSONDecode(s) return decode(s) end

local camera = newInstance("Camera")
local workspaceObj = newInstance("Workspace")
workspaceObj._props.CurrentCamera = camera
local gameObj = newInstance("DataModel")
gameObj._props.Name = "Game"
gameObj._props.PlaceId = 123
H.game = gameObj
workspaceObj.Parent = gameObj
local function serviceInstance(class)
	local o = newInstance(class)
	o.Parent = gameObj
	return o
end

local services = {
	UserInputService = UIS, TweenService = TweenService, RunService = RunService, TextService = TextService,
	ContextActionService = CAS, GuiService = GuiService, HttpService = HttpService, Players = newInstance("Players"),
	LogService = { MessageOut = newSignal() },
	Workspace = workspaceObj,
	ReplicatedStorage = serviceInstance("ReplicatedStorage"),
	Lighting = serviceInstance("Lighting"),
	StarterGui = serviceInstance("StarterGui"),
}
H.services = services
local game = gameObj
-- The local player with a character (Humanoid + Animator, HumanoidRootPart).
do
	local players = services.Players
	players._props.Name = "Players"
	local player = newInstance("Player")
	player._props.Name = "LocalTester"
	player.Parent = players
	players._props.LocalPlayer = player
	H.player = player
	-- Tests that need a character call H.spawnCharacter() (kept out of
	-- the tree otherwise, so row lists stay the same).
	function H.spawnCharacter()
		local character = newInstance("Model")
		character._props.Name = "LocalTester"
		character.Parent = workspaceObj
		local humanoid = newInstance("Humanoid")
		humanoid._props.Name = "Humanoid"
		humanoid.Parent = character
		local animator = newInstance("Animator")
		animator._props.Name = "Animator"
		animator.Parent = humanoid
		local root = newInstance("Part")
		root._props.Name = "HumanoidRootPart"
		root.Parent = character
		player._props.Character = character
		camera._props.CameraSubject = humanoid
		H.character, H.humanoid = character, humanoid
		return character
	end
end

----------------------------------------------------------------------
-- Executor functions + files
----------------------------------------------------------------------
-- A script's main function and its nested functions (for Dump Functions).
H.SCRIPT_CLOSURE = function() end
H.PROTOS = {
	[H.SCRIPT_CLOSURE] = {
		{ Info = { name = "onTouched", numparams = 1, is_vararg = 0, nups = 2 }, Protos = {
			{ Info = { name = "", numparams = 0, is_vararg = 1, nups = 0 } },
		} },
		{ Info = { name = "setup", numparams = 2, is_vararg = 0, nups = 0 } },
	},
}
local HUI = newInstance("HUI")
H.HUI = HUI
local genv = {}
local folders = { ["Tungsten/logs"] = true }

local env
local function loadfileMock(path)
	local src = H.FILES[path]
	-- Volt: a compile error returns nil + message; a missing file throws.
	if not src then error("loadfile: no file at " .. tostring(path), 2) end
	local f, err = loadstring(src, "@" .. path)
	if not f then return nil, err end
	setfenv(f, env)
	return f
end

env = setmetatable({
	typeof = typeof, Instance = Instance, Enum = Enum, game = game, workspace = workspaceObj,
	Vector2 = Vector2, Vector3 = Vector3, UDim = UDim, UDim2 = UDim2, Color3 = Color3, Font = Font,
	TweenInfo = TweenInfo, Random = Random, DateTime = DateTime, task = task,
	CFrame = CFrame, NumberRange = NumberRange, Rect = Rect, Vector2int16 = Vector2int16, Vector3int16 = Vector3int16,
	NumberSequence = NumberSequence, NumberSequenceKeypoint = NumberSequenceKeypoint, ColorSequence = ColorSequence,
	ColorSequenceKeypoint = ColorSequenceKeypoint, Faces = Faces, Axes = Axes, PhysicalProperties = PhysicalProperties,
	Ray = Ray, Content = Content, BrickColor = BrickColor,
	warn = function(...) table.insert(H.WARNINGS, table.concat({ ... }, " ")) end,
	getgenv = function() return genv end,
	isfile = function(p) return H.FILES[p] ~= nil end,
	isfolder = function(p)
		if folders[p] then return true end
		for f in H.FILES do
			if f:sub(1, #p + 1) == p .. "/" then return true end
		end
		return false
	end,
	makefolder = function(p) folders[p] = true end,
	readfile = function(p) return assert(H.FILES[p], "no file " .. p) end,
	writefile = function(p, d) H.FILES[p] = d end,
	appendfile = function(p, d) H.FILES[p] = (H.FILES[p] or "") .. d end,
	delfile = function(p) H.FILES[p] = nil end,
	delfolder = function(p)
		for f in table.clone(H.FILES) do
			if f:sub(1, #p + 1) == p .. "/" then H.FILES[f] = nil end
		end
		for f in table.clone(folders) do
			if f == p or f:sub(1, #p + 1) == p .. "/" then folders[f] = nil end
		end
	end,
	listfiles = function(dir)
		local out = {}
		-- files and folders directly inside dir (like Volt's listfiles)
		local seen = {}
		local function add(path)
			if not seen[path] then seen[path] = true; table.insert(out, path) end
		end
		for p in H.FILES do
			if p:sub(1, #dir + 1) == dir .. "/" then
				local rest = p:sub(#dir + 2)
				local first = rest:match("^([^/]+)/")
				add(if first then dir .. "/" .. first else p)
			end
		end
		for p in folders do
			if p:sub(1, #dir + 1) == dir .. "/" and not p:sub(#dir + 2):find("/") then add(p) end
		end
		return out
	end,
	loadfile = loadfileMock,
	getcustomasset = function(p)
		assert(H.FILES[p] ~= nil, "getcustomasset: missing " .. p)
		return "rbxasset://custom/" .. p
	end,
	cloneref = function(x) return x end,
	compareinstances = function(a, b) return a == b end,
	-- Round C functions (recorded so tests can see what was called)
	saveinstance = function(root, options)
		assert(type(options) == "table" and options._isOptions, "options must come from SaveInstanceOptions.new()")
		local path = options.FilePath
		if path == "" then path = "auto.rbxm" end
		H.FILES[path] = "<rbxm>"
		H.SAVED = H.SAVED or {}
		H.SAVED[path] = root
	end,
	SaveInstanceOptions = { new = function() return { _isOptions = true, FilePath = "", DecompileScripts = true } end },
	decompile = function(script)
		H.DECOMPILED = (H.DECOMPILED or 0) + 1
		if H.DECOMPILE_WAIT then task.wait(H.DECOMPILE_WAIT) end -- Volt's decompile yields
		local source = script._props.Source
		if source == nil then error("decompile failed: no bytecode", 2) end
		return source
	end,
	getscriptbytecode = function(script)
		return "\27LuauBytecode:" .. script._props.Name
	end,
	getscriptclosure = function(script)
		H.SCRIPT_CLOSURE_CALLS = (H.SCRIPT_CLOSURE_CALLS or 0) + 1
		local main = H.SCRIPT_CLOSURES and H.SCRIPT_CLOSURES[script]
		if main ~= nil then return main end
		return H.SCRIPT_CLOSURE
	end,
	-- Plugins stage round 1 (script viewer). Functions the tests describe go
	-- in H.FN[fn] = { Constants, Upvalues, Protos, Info, Hash, C, Executor }.
	getsenv = function(script) return H.SENV and H.SENV[script] or nil end,
	getrunningscripts = function() return table.clone(H.RUNNING or {}) end,
	getscripthash = function(script)
		if H.SCRIPT_HASH and H.SCRIPT_HASH[script] ~= nil then return H.SCRIPT_HASH[script] or nil end
		return string.rep("ab", 48)
	end,
	getfunctionhash = function(fn)
		assert(realType(fn) == "function", "getfunctionhash expects a function")
		local info = H.FN[fn]
		if (info and info.C) or debug.info(fn, "s") == "[C]" then error("C closures can't be hashed", 2) end
		return (info and info.Hash) or string.rep("cd", 48)
	end,
	iscclosure = function(fn)
		local info = H.FN[fn]
		if info and info.C ~= nil then return info.C end
		return debug.info(fn, "s") == "[C]"
	end,
	islclosure = function(fn)
		local info = H.FN[fn]
		if info and info.C ~= nil then return not info.C end
		return debug.info(fn, "s") ~= "[C]"
	end,
	-- getgc: H.GC's functions (and H.GC_TABLES with includeTables); H.GETGC_FAIL errors
	getgc = function(includeTables)
		H.GETGC_CALLS = (H.GETGC_CALLS or 0) + 1
		if H.GETGC_FAIL then error("getgc failed", 2) end
		local out = {}
		for _, v in H.GC or {} do
			if realType(v) == "function" or includeTables then table.insert(out, v) end
		end
		return out
	end,
	isexecutorclosure = function(fn)
		local info = H.FN[fn]
		return info ~= nil and info.Executor == true
	end,
	-- read-only in the mock: frozen tables, or ones in H.READONLY (which
	-- setreadonly can change; a frozen table stays frozen)
	isreadonly = function(t) return table.isfrozen(t) or (H.READONLY ~= nil and H.READONLY[t] == true) end,
	setreadonly = function(t, on)
		H.READONLY = H.READONLY or setmetatable({}, { __mode = "k" })
		H.READONLY[t] = on == true or nil
		H.SETREADONLY_CALLS = (H.SETREADONLY_CALLS or 0) + 1
	end,
	-- filtergc over H.GC (the functions "in memory"): every value listed in
	-- Constants / Upvalues must be among the function's (rawequal);
	-- IgnoreExecutor (default true) leaves out H.FN[fn].Executor ones.
	-- H.FILTERGC_LOOSE = true returns every function (to test re-checking).
	filtergc = function(kind, options, returnOne)
		assert(kind == "function" or kind == "table", "filtergc: type must be function or table")
		H.FILTERGC_CALLS = (H.FILTERGC_CALLS or 0) + 1
		if H.FILTERGC_WAIT then task.wait(H.FILTERGC_WAIT) end
		local out = {}
		for _, fn in H.GC or {} do
			local info = H.FN[fn] or {}
			local keep = true
			if options.IgnoreExecutor ~= false and info.Executor then keep = false end
			if options.Environment ~= nil and info.Env ~= options.Environment then keep = false end
			-- H.FILTERGC_ENV_MISS: Environment finds nothing (an executor whose
			-- function environments aren't the getsenv table)
			if options.Environment ~= nil and H.FILTERGC_ENV_MISS then keep = false end
			if options.Source ~= nil and H.FILTERGC_SOURCE_MISS then keep = false end
			if not H.FILTERGC_LOOSE then
				for field, key in { Constants = "Constants", Upvalues = "Upvalues" } do
					for _, wanted in options[field] or {} do
						local found = false
						for _, have in (info[key] or {}) do
							if rawequal(have, wanted) then found = true end
						end
						if not found then keep = false end
					end
				end
			end
			if keep then
				if returnOne then return fn end
				table.insert(out, fn)
			end
		end
		if returnOne then return nil end
		return out
	end,
	getrawmetatable = function(x) return getmetatable(x) end,
	fireclickdetector = function(d) H.FIRED = H.FIRED or {}; table.insert(H.FIRED, { "click", d }) end,
	fireproximityprompt = function(p) H.FIRED = H.FIRED or {}; table.insert(H.FIRED, { "prompt", p }) end,
	firetouchinterest = function(a, b, toggle) H.FIRED = H.FIRED or {}; table.insert(H.FIRED, { "touch", a, b, toggle }) end,
	hookmetamethod = function(obj, name, hook)
		assert(name == "__namecall", "only __namecall in the mock")
		H.HOOKS = (H.HOOKS or 0) + 1
		H.NAMECALL_HOOK = hook
		return function(self, ...)
			H.PASSED = (H.PASSED or 0) + 1
			return "passed"
		end
	end,
	getnamecallmethod = function() return H.NAMECALL_METHOD end,
	checkcaller = function() return H.CHECKCALLER ~= false end,
	newcclosure = function(fn) return fn end,
	debug = setmetatable({
		-- protos are tables in the mock: { Info = { name, numparams, is_vararg, nups },
		-- Constants, Protos = { … }, Closures = { running copies }, CodeHash }.
		-- Handed out by getprotos / getproto they become ProtoProxy (typeof).
		getprotos = function(fn)
			local list
			if realType(fn) == "table" then
				list = fn.Protos or {}
			else
				local info = H.FN[fn]
				list = if info and info.Protos then table.clone(info.Protos) else ((H.PROTOS and H.PROTOS[fn]) or {})
			end
			for _, proto in list do
				H.proto(proto)
			end
			return list
		end,
		-- debug.getproto(f, i, activated?): the ProtoProxy, or with activated
		-- = true its running copies (proto.Closures)
		getproto = function(fn, index, activated)
			assert(realType(index) == "number", "getproto: index must be a number")
			H.GETPROTO_CALLS = (H.GETPROTO_CALLS or 0) + 1
			local list = env.debug.getprotos(fn)
			local proto = list[index]
			if proto == nil then error("getproto: no proto at index " .. index, 2) end
			if activated then return table.clone(proto.Closures or {}) end
			return proto
		end,
		-- debug.info: H.FN[fn].Source stands in for a game script's chunk
		-- name ("s"); everything else is Luau's own
		info = function(fn, what, ...)
			local entry = H.FN[fn]
			if entry and entry.Source and what == "s" then
				return entry.Source
			end
			return debug.info(fn, what, ...)
		end,
		getinfo = function(fn)
			if realType(fn) == "table" then return fn.Info end
			local info = H.FN[fn]
			if info and info.Info then return info.Info end
			return { name = "", numparams = 0, is_vararg = 1, nups = 0 }
		end,
		getconstants = function(fn)
			if realType(fn) == "table" then return fn.Constants or {} end
			local info = H.FN[fn]
			if (info and info.C) or (realType(fn) == "function" and debug.info(fn, "s") == "[C]") then error("Luau closures only", 2) end
			return table.clone(info and info.Constants or {})
		end,
		getupvalues = function(fn)
			local info = H.FN[fn]
			return table.clone(info and info.Upvalues or {})
		end,
		setconstant = function(fn, index, value)
			local constants = if realType(fn) == "table" then fn.Constants else (H.FN[fn] and H.FN[fn].Constants)
			assert(constants ~= nil, "setconstant: no constants")
			assert(realType(index) == "number" and index >= 1, "setconstant: 1-based index")
			if H.SETCONSTANT_FAIL then error("setconstant refused", 2) end
			constants[index] = value
			return fn
		end,
		setupvalue = function(fn, index, value)
			local info = H.FN[fn]
			assert(info and info.Upvalues, "setupvalue: no upvalues")
			info.Upvalues[index] = value
		end,
	}, { __index = debug }),
	getnilinstances = function() return table.clone(H.NIL) end,
	getloadedmodules = function() return table.clone(H.LOADED) end,
	-- require on a ModuleScript: the value a test gave it (H.MODULE_VALUES)
	require = function(module)
		H.REQUIRED = (H.REQUIRED or 0) + 1
		local values = H.MODULE_VALUES or {}
		if values[module] == nil then error("module has no value in this test", 2) end
		return values[module]
	end,
	gethui = function() return HUI end,
	identifyexecutor = function() return "MockVolt", "1.3" end,
	setclipboard = function(s) H.CLIPBOARD = tostring(s) end,
	gethiddenproperty = function(o, k)
		local v = o._props[k]
		return v, (H.HIDDEN[k] == true)
	end,
	sethiddenproperty = function(o, k, v)
		o._props[k] = v
		return H.HIDDEN[k] == true
	end,
	getproperties = function(o)
		local out = { Name = o._props.Name, ClassName = o._class, Parent = o._props.Parent }
		for k, v in o._props do out[k] = v end
		return out
	end,
}, { __index = _G })
H.env = env
H.genv = genv

-- Marks a mock proto table as a ProtoProxy (typeof says so) and returns it.
local PROTO_MT = { __type = "ProtoProxy" }
function H.proto(t)
	if realType(t) == "table" and getmetatable(t) == nil then
		setmetatable(t, PROTO_MT)
	end
	return t
end

----------------------------------------------------------------------
-- Driving
----------------------------------------------------------------------
-- Fire AbsoluteSize/AbsolutePosition change signals like the engine does
-- after layout.
local lastAbs = setmetatable({}, { __mode = "k" })
local function layoutPass()
	for _ = 1, 4 do
		local fired = false
		for _, o in Instances do
			if not o._destroyed then
				for _, prop in { "AbsoluteSize", "AbsolutePosition" } do
					local sig = o._changed[prop]
					if sig and sig:Count() > 0 then
						local now = if prop == "AbsoluteSize" then absSize(o) else absPos(o)
						local key = prop
						lastAbs[o] = lastAbs[o] or {}
						local before = lastAbs[o][key] or vec2(0, 0)
						if before ~= now then
							lastAbs[o][key] = now
							fired = true
							sig:Fire()
						end
					end
				end
			end
		end
		if not fired then break end
	end
end
H.layoutPass = layoutPass

function H.step(dt)
	dt = dt or 1 / 60
	H.TIME += dt
	runDeferred()
	layoutPass()
	-- timers due
	local due = {}
	for i = #timers, 1, -1 do
		if timers[i].At <= H.TIME then
			table.insert(due, 1, table.remove(timers, i))
		end
	end
	table.sort(due, function(a, b) return a.At < b.At end)
	for _, t in due do
		if coroutine.status(t.Co) == "suspended" then
			resume(t.Co, table.unpack(t.Args, 1, t.Args.n))
		end
	end
	runDeferred()
	RunService.RenderStepped:Fire(dt)
	RunService.Heartbeat:Fire(dt)
	runDeferred()
	layoutPass()
end

function H.advance(seconds)
	local steps = math.ceil(seconds * 60)
	for _ = 1, steps do H.step(1 / 60) end
end

-- os.clock follows virtual time so double-click/justClosed logic works.
env.os = setmetatable({ clock = function() return H.TIME end }, { __index = os })

local InputMT = { __type = "InputObject" }
InputMT.__index = InputMT
function InputMT:IsModifierKeyDown(mod)
	return self._mods ~= nil and self._mods[mod.Name] == true
end
function H.input(kind, props)
	local o = setmetatable({
		UserInputType = Enum.UserInputType[kind],
		KeyCode = Enum.KeyCode.Unknown,
		Position = Vector3.new(H.mouse.X, H.mouse.Y, 0),
		UserInputState = Enum.UserInputState.Begin,
	}, InputMT)
	for k, v in props or {} do o[k] = v end
	return o
end

-- Topmost visible GuiObject handling an event at the mouse.
local function shown(o)
	local cur = o
	while cur do
		if cur._props.Visible == false then return false end
		if cur._class == "ScreenGui" then return cur._props.Enabled ~= false end
		cur = cur._props.Parent
	end
	return false
end
function H.shown(o) return shown(o) end

local function inside(o, p)
	local pos, size = absPos(o), absSize(o)
	return p.X >= pos.X and p.Y >= pos.Y and p.X < pos.X + size.X and p.Y < pos.Y + size.Y
end
H.inside = inside

local function zkey(o)
	-- order: ScreenGui DisplayOrder, then depth-first sibling ZIndex path
	local path = {}
	local cur = o
	while cur do
		table.insert(path, 1, cur)
		cur = cur._props.Parent
	end
	return path
end

local function above(a, b)
	-- true if a is drawn above b (approximation)
	local pa, pb = zkey(a), zkey(b)
	local guiA, guiB
	for _, x in pa do if x._class == "ScreenGui" then guiA = x end end
	for _, x in pb do if x._class == "ScreenGui" then guiB = x end end
	if guiA ~= guiB then
		return (guiA and guiA._props.DisplayOrder or 0) > (guiB and guiB._props.DisplayOrder or 0)
	end
	local i = 1
	while pa[i] and pb[i] and pa[i] == pb[i] do i += 1 end
	local x, y = pa[i], pb[i]
	if not x then return false end -- a is ancestor of b
	if not y then return true end
	local zx, zy = x._props.ZIndex or 1, y._props.ZIndex or 1
	if zx ~= zy then return zx > zy end
	local parent = x._props.Parent
	return table.find(parent._children, x) > table.find(parent._children, y)
end

-- Roblox doesn't send input to the parts of an object that an ancestor
-- with ClipsDescendants cuts off.
local function clippedAway(o, point)
	local cur = o._props.Parent
	while cur do
		if cur._props.ClipsDescendants == true and isA(cur._class, "GuiObject") and not inside(cur, point) then
			return true
		end
		cur = cur._props.Parent
	end
	return false
end

function H.topAt(point, filter)
	point = point - vec2(0, H.ABS_SHIFT or 0) -- screen -> AbsolutePosition space
	local best
	for _, o in Instances do
		if not o._destroyed and isA(o._class, "GuiObject") and shown(o) and o:IsDescendantOf(HUI) and inside(o, point) and not clippedAway(o, point) then
			if (not filter) or filter(o) then
				if not best or above(o, best) then best = o end
			end
		end
	end
	return best
end

local function isButton(o)
	return o._class == "TextButton" or o._class == "ImageButton" or o._class == "TextBox" or o._props.Active == true
end

-- Simulated mouse click at a screen point.
function H.click(point, button)
	button = button or "MouseButton1"
	H.mouse = point
	local input = H.input(button)
	-- Roblox order: the GUI object's InputBegan runs before UserInputService's.
	local target = H.topAt(point, isButton)
	if target then
		target.InputBegan:Fire(input)
		if button == "MouseButton1" then
			target.MouseButton1Down:Fire()
		end
	end
	UIS.InputBegan:Fire(input, target ~= nil)
	H.step()
	local ended = H.input(button)
	UIS.InputEnded:Fire(ended, false)
	if target and not target._destroyed then
		if button == "MouseButton1" then
			target.MouseButton1Up:Fire()
			if target._class == "TextButton" or target._class == "ImageButton" then
				target.Activated:Fire(ended)
			end
		end
	end
	H.step()
	return target
end

function H.toScreen(p) return p + vec2(0, H.ABS_SHIFT or 0) end
function H.clickObject(o, button)
	local pos, size = absPos(o), absSize(o)
	return H.click(H.toScreen(vec2(pos.X + size.X / 2, pos.Y + size.Y / 2)), button)
end
-- Click near the left end of a wide object (a row wider than the area
-- that shows it: the mock doesn't clip, the engine does).
function H.clickObjectLeft(o, button, inset)
	local pos, size = absPos(o), absSize(o)
	return H.click(H.toScreen(vec2(pos.X + math.min(inset or 30, size.X / 2), pos.Y + size.Y / 2)), button)
end

-- Roblox sends MouseEnter to every GuiObject under the pointer, even
-- ones covered by something on top; mimic that.
function H.moveMouse(screenPoint)
	H.mouse = screenPoint
	local abs = screenPoint - vec2(0, H.ABS_SHIFT or 0)
	H.hovering = H.hovering or {}
	for _, o in Instances do
		if not o._destroyed and isA(o._class, "GuiObject") and shown(o) and o:IsDescendantOf(HUI) then
			local now = inside(o, abs)
			local was = H.hovering[o] == true
			if now and not was then
				H.hovering[o] = true
				if o._events.MouseEnter then o.MouseEnter:Fire() end
			elseif was and not now then
				H.hovering[o] = nil
				if o._events.MouseLeave then o.MouseLeave:Fire() end
			end
		end
	end
	UIS.InputChanged:Fire(H.input("MouseMovement"), false)
	H.step()
end
function H.hover(o)
	local pos, size = absPos(o), absSize(o)
	H.moveMouse(H.toScreen(vec2(pos.X + size.X / 2, pos.Y + size.Y / 2)))
end

function H.press(screenPoint)
	H.mouse = screenPoint
	local input = H.input("MouseButton1")
	H.UIS.InputBegan:Fire(input, false)
	local targets = {}
	-- deliver to every GuiObject under the point that is a button/active (topmost first)
	local top = H.topAt(screenPoint, function(o) return o._class == "TextButton" or o._props.Active == true end)
	if top then top.InputBegan:Fire(input) end
	-- also its ancestors that listen (track behind thumb)
	local cur = top and top._props.Parent
	while cur do
		if cur._events.InputBegan and isA(cur._class, "GuiObject") and inside(cur, screenPoint - vec2(0, H.ABS_SHIFT or 0)) then
			cur.InputBegan:Fire(input)
		end
		cur = cur._props.Parent
	end
	H.step()
end
function H.moveTo(screenPoint)
	H.mouse = screenPoint
	H.UIS.InputChanged:Fire(H.input("MouseMovement"), false)
	H.step()
end
function H.release()
	H.UIS.InputEnded:Fire(H.input("MouseButton1"), false)
	H.step()
end

function H.key(name, processed)
	local input = H.input("Keyboard", { KeyCode = Enum.KeyCode[name] })
	H.keys[name] = true
	UIS.InputBegan:Fire(input, processed or false)
	H.step()
	H.keys[name] = nil
	UIS.InputEnded:Fire(input, processed or false)
	H.step()
end

function H.wheel(point, delta, mods)
	H.mouse = point
	UIS.InputChanged:Fire(H.input("MouseMovement"), false)
	UIS.InputChanged:Fire(H.input("MouseWheel", { Position = Vector3.new(point.X, point.Y, delta), _mods = mods }), false)
end
function H.pan(point, x)
	H.mouse = point
	UIS.InputChanged:Fire(H.input("MouseMovement"), false)
	UIS.PointerAction:Fire(0, vec2(x, 0), 0, false)
end

function H.type(box, text)
	box.Text = text
	H.step()
end

function H.find(root, name)
	if root._props.Name == name then return root end
	for _, d in root:GetDescendants() do
		if d._props.Name == name then return d end
	end
	return nil
end

-- Runs a file the way the executor does: in its own thread, so it may
-- wait (the loading screen lets a frame draw between steps). Frames are
-- stepped until it finishes.
-- The prime plugins Tungsten ships (Tungsten/plugins/<Folder>/). Suites
-- written before they shipped expect an empty plugins folder, so they are
-- set aside here (and taken out of the manifest) before any suite runs. A
-- suite that tests them calls H.keepPrimes() before H.run. (Fixtures a
-- suite installs under the same folder names are never touched.)
H.PRIME_FOLDERS = { "ScriptViewer", "InstanceViewer", "Scanner" }
local shippedPrimes, fullManifest = {}, H.FILES["Tungsten/base/data/manifest.luau"]
do
	for _, folder in H.PRIME_FOLDERS do
		local prefix = "Tungsten/plugins/" .. folder .. "/"
		for path, content in table.clone(H.FILES) do
			if path:sub(1, #prefix) == prefix then
				shippedPrimes[path] = content
				H.FILES[path] = nil
			end
		end
	end
	if fullManifest then
		local kept = {}
		for line in (fullManifest .. "\n"):gmatch("(.-)\n") do
			local primeLine = false
			for _, folder in H.PRIME_FOLDERS do
				if line:find('["plugins/' .. folder .. "/", 1, true) then
					primeLine = true
				end
			end
			if not primeLine then
				table.insert(kept, line)
			end
		end
		H.FILES["Tungsten/base/data/manifest.luau"] = table.concat(kept, "\n")
	end
end
function H.keepPrimes()
	for path, content in shippedPrimes do
		H.FILES[path] = content
	end
	H.FILES["Tungsten/base/data/manifest.luau"] = fullManifest
end

function H.run(path, ...)
	local f = assert(loadfileMock(path))
	local args = table.pack(...)
	local done, ok, err = false, false, nil
	local co = coroutine.create(function()
		ok, err = xpcall(f, debug.traceback, table.unpack(args, 1, args.n))
		done = true
	end)
	resume(co)
	local guard = 0
	while not done and guard < 600 do
		guard += 1
		H.step()
	end
	if not done then
		return false, "the file never finished running"
	end
	return ok, err
end

return H
