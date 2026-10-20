--[[
	Tungsten · base/data/icons
	Icons are local PNG files in Tungsten/base/data/icons/ (drawn white,
	tinted at runtime). The matching .svg sources sit beside them.

		local icon = Icons.new("console", 18, "TextMuted")
		Icons.tint(icon, "Accent", 0.15)
		Icons.set(icon, "explorer")

	Icons of your own (plugins too):
		Icons.register("myplugin.gear", "Tungsten/plugins/MyPlugin/gear.png", { Owner = "myplugin" })
		Icons.register("myplugin.logo", "rbxassetid://1234567", { Colored = true })
		Icons.register("myplugin.sheet", { Image = "rbxassetid://99", RectOffset = Vector2.new(0, 0), RectSize = Vector2.new(32, 32) })
		Icons.new("myplugin.gear", 18)     -- like any other icon (tabs, menus, lists)
	A source is a file (loaded with getcustomasset), an rbxasset:// or
	rbxassetid:// image, or a sprite table. Colored icons keep their own
	colors (no tint). Icons.new also takes a source directly.
	Icons.removeOwner("myplugin") drops a plugin's icons.
]]

local T = ...
local Theme = T.import("base/theme")
local Create = T.import("base/ui/create")

local ICON_DIR = T.Root .. "/base/data/icons"
local COLORED_ATTRIBUTE = "TungstenColored"

-- Shown only if an icon file is missing, so the UI still makes sense.
local GLYPHS = {
	logo = "◆",
	console = ">",
	documentation = "?",
	plugins = "+",
	minimize = "–",
	dummy = "•",
	check = "✓",
	chevron_right = "›",
	chevron_down = "⌄",
	search = "⌕",
	close = "×",
}

-- Icons drawn in their own colors (never tinted).
local BUILTIN_COLORED = {}

local Icons = {}
-- The standard brand icon: a plain W tinted with the accent color. Used
-- for the pill, the window's title bar and the command bar. "logo" is
-- the same picture.
Icons.Brand = "mark_w"
local cache: { [string]: any } = {} -- name -> { Image, RectOffset?, RectSize?, Colored? } | false
local registered: { [string]: any } = {} -- name -> { Source, Owner, Colored }

local function isSource(text: string): boolean
	return text:find("://", 1, true) ~= nil or text:match("%.png$") ~= nil or text:match("%.jpe?g$") ~= nil
end

-- A source -> { Image, RectOffset, RectSize } or nil + reason.
local function load(source: any): (any, string?)
	if type(source) == "table" then
		if type(source.Image) ~= "string" then
			return nil, "a sprite needs Image"
		end
		local loaded, reason = load(source.Image)
		if not loaded then
			return nil, reason
		end
		return { Image = loaded.Image, RectOffset = source.RectOffset, RectSize = source.RectSize }, nil
	end
	if type(source) ~= "string" or source == "" then
		return nil, "no image"
	end
	if source:find("://", 1, true) then
		return { Image = source }, nil
	end
	if not isfile(source) then
		return nil, "missing file " .. source
	end
	local ok, result = pcall(getcustomasset, source)
	if ok and type(result) == "string" then
		return { Image = result }, nil
	end
	return nil, ("could not load %s: %s"):format(source, tostring(result))
end

function Icons.register(name: string, source: any, opts: { [string]: any }?)
	assert(type(name) == "string" and name ~= "", "an icon needs a name")
	opts = opts or {}
	registered[name] = { Source = source, Owner = (opts :: any).Owner or "core", Colored = (opts :: any).Colored == true }
	cache[name] = nil
	return name
end

function Icons.unregister(name: string): boolean
	if registered[name] then
		registered[name] = nil
		cache[name] = nil
		return true
	end
	return false
end

function Icons.removeOwner(owner: string): number
	local count = 0
	for name, entry in table.clone(registered) do
		if entry.Owner == owner then
			Icons.unregister(name)
			count += 1
		end
	end
	return count
end

-- Every icon name: the bundled files and registered ones.
function Icons.list(): { string }
	local names = {}
	local ok, files = pcall(listfiles, ICON_DIR)
	if ok and type(files) == "table" then
		for _, file in files do
			local base = tostring(file):match("([^/\\]+)%.png$")
			if base then
				table.insert(names, base)
			end
		end
	end
	for name in registered do
		if not table.find(names, name) then
			table.insert(names, name)
		end
	end
	table.sort(names)
	return names
end

-- { Image, RectOffset?, RectSize?, Colored } for a name or source, or nil.
function Icons.resolve(name: string)
	local cached = cache[name]
	if cached ~= nil then
		return cached or nil
	end
	local info, reason
	local entry = registered[name]
	if entry then
		info, reason = load(entry.Source)
		if info then
			info.Colored = entry.Colored
		end
	elseif isSource(name) then
		info, reason = load(name)
	else
		info, reason = load(("%s/%s.png"):format(ICON_DIR, name))
		if info then
			info.Colored = BUILTIN_COLORED[name] == true
		end
	end
	if not info then
		T.Log.warn("icons", ("icon '%s': %s"):format(name, tostring(reason)))
	end
	cache[name] = info or false
	return info
end

-- The image id for an icon (nil when it can't be loaded).
function Icons.get(name: string): string?
	local info = Icons.resolve(name)
	return if info then info.Image else nil
end

local function apply(image: ImageLabel, info)
	image.Image = info.Image
	if info.RectSize then
		image.ImageRectOffset = info.RectOffset or Vector2.zero
		image.ImageRectSize = info.RectSize
	else
		image.ImageRectOffset = Vector2.zero
		image.ImageRectSize = Vector2.zero
	end
	image:SetAttribute(COLORED_ATTRIBUTE, info.Colored == true)
	if info.Colored then
		image.ImageColor3 = Color3.new(1, 1, 1)
	end
end

local function glyph(image: ImageLabel, name: string, size: number, tint: Color3?)
	local existing = image:FindFirstChild("Glyph")
	if existing then
		existing.Text = GLYPHS[name] or "•"
		return
	end
	Create.new("TextLabel", {
		Name = "Glyph",
		Size = UDim2.fromScale(1, 1),
		Text = GLYPHS[name] or "•",
		TextSize = size,
		FontFace = Theme.Fonts.Bold,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = tint,
		Parent = image,
	})
end

function Icons.new(name: string, size: number, colorKey: (string | Color3)?): ImageLabel
	local image = Create.new("ImageLabel", {
		Name = "Icon",
		Size = UDim2.fromOffset(size, size),
		ScaleType = Enum.ScaleType.Fit,
	})
	local info = Icons.resolve(name)
	if info then
		apply(image, info)
	else
		glyph(image, name, size)
	end
	Icons.tint(image, colorKey or "Text")
	return image
end

-- colorKey is a theme color key or a fixed Color3. Colored icons keep
-- their own colors.
function Icons.tint(image: ImageLabel, colorKey: string | Color3, duration: number?)
	if image:GetAttribute(COLORED_ATTRIBUTE) == true then
		return
	end
	Theme.apply(image, "ImageColor3", colorKey, duration)
	local mark = image:FindFirstChild("Glyph")
	if mark then
		Theme.apply(mark, "TextColor3", colorKey, duration)
	end
end

-- Swap the picture of an existing icon.
function Icons.set(image: ImageLabel, name: string)
	local info = Icons.resolve(name)
	local mark = image:FindFirstChild("Glyph")
	if info then
		apply(image, info)
		if mark then
			mark:Destroy()
		end
	else
		image.Image = ""
		image:SetAttribute(COLORED_ATTRIBUTE, false)
		glyph(image, name, image.Size.X.Offset, image.ImageColor3)
	end
end

T.Bin:Add(function()
	table.clear(registered)
	table.clear(cache)
end)

return Icons
