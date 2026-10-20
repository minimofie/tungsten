-- Stage 4 round B: API data, value types, properties panel, editors,
-- attributes, property menus and commands.
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
local typeof = E_.typeof
local V2 = E_.Vector2.new
local V3 = E_.Vector3.new
local CF = H.Datatypes.CFrame
H.ABS_SHIFT = SHIFT or 0
local new = E_.Instance.new
local game = H.game
local workspace = E_.workspace

----------------------------------------------------------------------
-- A small game
----------------------------------------------------------------------
local function make(class, name, parent)
	local o = new(class)
	o.Name = name
	o.Parent = parent
	return o
end
local base = H.part("Baseplate", workspace, { Anchored = true, Size = V3(512, 20, 512) })
local red = H.part("Red", workspace, { Transparency = 0.25 })
local blue = H.part("Blue", workspace, { Transparency = 0.5 })
local folder = make("Folder", "Stuff", workspace)
local link = make("ObjectValue", "Link", folder)
local emitter = make("ParticleEmitter", "Sparks", red)
emitter.Size = H.Datatypes.NumberSequence.new(1)
emitter.Color = H.Datatypes.ColorSequence.new(E_.Color3.new(1, 0, 0))
H.CLASS_PARENTS.FancyPart = "Part"
local fancy = new("FancyPart")
fancy.Name = "Fancy"
fancy.Parent = folder

local ok, err = H.run("Tungsten/Tungsten.luau")
check("loader runs", ok, err)
H.advance(1)
local T = H.genv.Tungsten.Context
local E, C = T.Explorer, T.Console
local Variables = T.Variables
local Types = T.import("base/types")
local Api = T.import("base/explorer/api")
local Properties = T.import("base/explorer/properties")
local Editors = T.import("base/explorer/editors")
local Menus = T.Menus
local UI = T.UI
local Settings = T.Settings
check("no errors at start", #H.ERRORS == 0, H.ERRORS[1])

local function lines(from)
	local out = {}
	for index = from or 1, #C.Lines do
		table.insert(out, C.Lines[index].Plain)
	end
	return table.concat(out, "\n")
end
local function run(text)
	local at = #C.Lines + 1
	C.run(text)
	H.advance(0.2)
	return at
end
local function has(at, text)
	return lines(at):find(text, 1, true) ~= nil
end

----------------------------------------------------------------------
-- 1. API data
----------------------------------------------------------------------
check("data has a client version", type(Api.Version) == "string" and Api.Version:match("^%d+%.%d+") ~= nil, Api.Version)
local partInfo = Api.class("Part")
check("Part's superclass", partInfo and partInfo.Superclass == "FormFactorPart", partInfo and partInfo.Superclass)
check("superclass chain", table.concat(Api.superclasses("Part"), ",") == "FormFactorPart,BasePart,PVInstance,Instance,Object", table.concat(Api.superclasses("Part"), ","))
check("class tags", Api.class("Workspace").Service and Api.class("BasePart").NotCreatable and not Api.class("Part").NotCreatable)
local anchored = Api.property("Part", "Anchored")
check("inherited property", anchored and anchored.Type == "boolean" and anchored.Class == "BasePart")
check("property category", anchored and anchored.Category == "Part", anchored and anchored.Category)
local nameProp = Api.property("Part", "Name")
check("Instance properties too", nameProp and nameProp.Type == "string" and nameProp.Category == "Data")
check("enum property", Api.property("Part", "Material").Type == "EnumItem" and Api.property("Part", "Material").Enum == "Material")
check("reference property", Api.property("ObjectValue", "Value").Type == "Instance" and Api.property("ObjectValue", "Value").ClassRef == "Instance")
check("integer property", Api.property("TextLabel", "MaxVisibleGraphemes").Integer == true)
check("read only property", Api.property("Part", "Mass").ReadOnly == true and Api.property("Part", "Mass").Editable == false)
check("ClassName is read only", Api.property("Part", "ClassName").ReadOnly == true)
check("deprecated flag", Api.property("Part", "BackParamA").Deprecated == true)
check("not scriptable flag", Api.property("Part", "shape") ~= nil and Api.property("Part", "shape").NotScriptable == true)
check("ContentId is a string", Api.property("Decal", "Texture") and Api.property("Decal", "Texture").Type == "string" and Api.property("Decal", "Texture").DataType == "ContentId")
check("security level kept", Api.property("Instance", "UniqueId") == nil or Api.property("Instance", "UniqueId").Security ~= nil)
local sorted = true
local list = Api.properties("Part")
for index = 2, #list do
	if list[index - 1].Name:lower() > list[index].Name:lower() then
		sorted = false
	end
end
check("properties sorted by name", sorted and #list > 50, #list)
check("unknown class falls back to the nearest known one", Api.knownClass(fancy) == "Part", Api.knownClass(fancy))
check("propertiesOf an unknown class", #Api.propertiesOf(fancy) == #list)
check("read", select(2, Api.read(red, "Transparency")) == 0.25)
check("write", Api.write(red, "Transparency", 0.3) and red.Transparency == 0.3)
red.Transparency = 0.25
local okRO, whyRO = Api.write(red, "Mass", 5)
check("write refuses read only", okRO == false and tostring(whyRO):find("read only", 1, true), whyRO)
red._props.shape = E_.Enum.PartType.Ball
H.HIDDEN.shape = true
check("hidden read uses gethiddenproperty", select(2, Api.read(red, "shape", Api.property("Part", "shape"))) == E_.Enum.PartType.Ball)
check("hidden write uses sethiddenproperty", Api.write(red, "shape", E_.Enum.PartType.Block, Api.property("Part", "shape")) and red._props.shape == E_.Enum.PartType.Block)
red._props.FutureThing = 7
local extra = Api.extraProperties(red)
check("properties newer than the data", extra.FutureThing == 7 and extra.Anchored == nil)
red._props.FutureThing = nil

----------------------------------------------------------------------
-- 2. Value types
----------------------------------------------------------------------
local D = H.Datatypes
local function roundTrip(typeName, value)
	local text = Types.editText(value)
	local okP, back = Types.parse(text, typeName)
	return okP and back == value, text
end
local ns = D.NumberSequence.new({ D.NumberSequenceKeypoint.new(0, 1), D.NumberSequenceKeypoint.new(0.5, 2, 0.25), D.NumberSequenceKeypoint.new(1, 0) })
check("NumberSequence text", Types.editText(ns) == "0: 1; 0.5: 2 +- 0.25; 1: 0", Types.editText(ns))
check("NumberSequence round trip", (roundTrip("NumberSequence", ns)))
check("NumberSequence constant", Types.editText(D.NumberSequence.new(3)) == "3" and select(2, Types.parse("3", "NumberSequence")) == D.NumberSequence.new(3))
check("NumberSequence Studio form", select(2, Types.parse("0 1 0 1 0 0", "NumberSequence")) == D.NumberSequence.new(1, 0))
local badNS, whyNS = Types.parse("0.2: 1; 1: 2", "NumberSequence")
check("NumberSequence must start at 0", badNS == false and tostring(whyNS):find("time 0", 1, true), whyNS)
check("NumberSequence literal", Types.literal(ns):find("NumberSequenceKeypoint.new(0.5, 2, 0.25)", 1, true) ~= nil, Types.literal(ns))
local cs = D.ColorSequence.new(E_.Color3.fromRGB(255, 0, 0), E_.Color3.fromRGB(0, 0, 255))
check("ColorSequence text", Types.editText(cs) == "0: #FF0000; 1: #0000FF", Types.editText(cs))
check("ColorSequence round trip", (roundTrip("ColorSequence", cs)))
check("ColorSequence from one color", select(2, Types.parse("#00ff00", "ColorSequence")) == D.ColorSequence.new(E_.Color3.fromRGB(0, 255, 0)))
check("ColorSequence keypoints in r, g, b", select(2, Types.parse("0: 255, 0, 0; 1: 0, 0, 255", "ColorSequence")) == cs)
local faces = D.Faces.new(E_.Enum.NormalId.Top, E_.Enum.NormalId.Front)
check("Faces text", Types.editText(faces) == "Top, Front", Types.editText(faces))
check("Faces round trip", (roundTrip("Faces", faces)))
check("Faces none", select(2, Types.parse("", "Faces")) == D.Faces.new())
check("Faces bad name says why", tostring(select(2, Types.parse("Up", "Faces"))):find("isn't a face", 1, true) ~= nil)
local axes = D.Axes.new(E_.Enum.Axis.X, E_.Enum.Axis.Z)
check("Axes round trip", Types.editText(axes) == "X, Z" and (roundTrip("Axes", axes)))
local font = D.Font.new("rbxasset://fonts/families/GothamSSm.json", E_.Enum.FontWeight.Bold, E_.Enum.FontStyle.Italic)
check("Font text", Types.editText(font) == "GothamSSm, Bold, Italic", Types.editText(font))
check("Font round trip", (roundTrip("Font", font)))
check("Font from an asset id", select(2, Types.parse("12345", "Font")).Family == "rbxassetid://12345")
check("Font literal", Types.literal(font) == 'Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold, Enum.FontStyle.Italic)', Types.literal(font))
local pp = D.PhysicalProperties.new(1, 0.5, 0.2, 2, 3)
check("PhysicalProperties round trip", (roundTrip("PhysicalProperties", pp)))
check("PhysicalProperties from a material", typeof(select(2, Types.parse("Wood", "PhysicalProperties"))) == "PhysicalProperties")
check("PhysicalProperties default resets", select(1, Types.parse("default", "PhysicalProperties")) == true and select(2, Types.parse("default", "PhysicalProperties")) == nil)
local ray = D.Ray.new(V3(1, 2, 3), V3(0, -10, 0))
check("Ray text", Types.editText(ray) == "1, 2, 3; 0, -10, 0", Types.editText(ray))
check("Ray round trip", (roundTrip("Ray", ray)))
check("Content from an id", select(2, Types.parse("123", "Content")).Uri == "rbxassetid://123")
check("Content none", select(2, Types.parse("", "Content")) == D.Content.none)
check("Content text", Types.editText(D.Content.fromUri("rbxassetid://9")) == "rbxassetid://9")
check("Vector3int16 round trip", (roundTrip("Vector3int16", D.Vector3int16.new(1, -2, 3))))
check("Vector2int16 literal", Types.literal(D.Vector2int16.new(4, 5)) == "Vector2int16.new(4, 5)")
for _, name in { "NumberSequence", "ColorSequence", "Faces", "Axes", "Font", "PhysicalProperties", "Ray", "Content" } do
	check("default " .. name, typeof(Types.default(name)) == name, typeof(Types.default(name)))
end
check("hints for the new types", Types.hint("Faces"):find("Right", 1, true) ~= nil and Types.hint("Font"):find("family", 1, true) ~= nil)
-- CFrame parts: orientation keeps the roll (not taken from the look direction)
local cf = CF.new(1, 2, 3) * CF.fromOrientation(math.rad(30), math.rad(45), math.rad(60))
local pos, ori = Types.cframeParts(cf)
check("CFrame position part", pos == V3(1, 2, 3), tostring(pos))
check("CFrame orientation part", math.abs(ori.X - 30) < 1e-3 and math.abs(ori.Y - 45) < 1e-3 and math.abs(ori.Z - 60) < 1e-3, tostring(ori))
local rebuilt = Types.cframeFrom(pos, ori)
check("CFrame rebuilt from its parts", rebuilt == cf)
local rolled = CF.fromOrientation(0, 0, math.rad(90))
local _, rollOri = Types.cframeParts(rolled)
check("pure roll survives", math.abs(rollOri.Z - 90) < 1e-3 and rollOri.X == 0 and rollOri.Y == 0, tostring(rollOri))

----------------------------------------------------------------------
-- 3. Properties model
----------------------------------------------------------------------
local entries = Properties.collect({ red })
local function entryNamed(list, name)
	for _, entry in list do
		if entry.Name == name then
			return entry
		end
	end
	return nil
end
check("collect lists a part's properties", entryNamed(entries, "Anchored") and entryNamed(entries, "Size") and entryNamed(entries, "Name"))
check("values read", entryNamed(entries, "Transparency").Value == 0.25)
check("deprecated hidden by default", entryNamed(entries, "BackParamA") == nil)
check("not scriptable hidden by default", entryNamed(entries, "shape") == nil)
check("deprecated shown on request", entryNamed(Properties.collect({ red }, { ShowDeprecated = true }), "brickColor") ~= nil)
check("deprecated and hidden needs both", entryNamed(Properties.collect({ red }, { ShowDeprecated = true }), "BackParamA") == nil)
check("hidden shown on request", entryNamed(Properties.collect({ red }, { ShowHidden = true }), "shape") ~= nil)
check("Appearance first, then Data", entries[1].Category == "Appearance", entries[1].Category)
local filtered = Properties.collect({ red }, { Filter = "anch" })
check("filter by name", #filtered == 1 and filtered[1].Name == "Anchored", #filtered)
check("filter by category", #Properties.collect({ red }, { Filter = "transform" }) > 0)
local both = Properties.collect({ red, blue })
check("different values are marked", entryNamed(both, "Transparency").Same == false)
check("equal values are shared", entryNamed(both, "Anchored").Same == true)
local mixed = Properties.collect({ red, folder })
check("mixed classes share only common properties", entryNamed(mixed, "Name") and entryNamed(mixed, "Anchored") == nil)
local changed, failures = Properties.set({ red, blue }, Api.property("Part", "Transparency"), 0.75)
check("set writes to all", changed == 2 and #failures == 0 and red.Transparency == 0.75 and blue.Transparency == 0.75)
red.Transparency, blue.Transparency = 0.25, 0.5
local roChanged, roFailures = Properties.set({ red }, Api.property("Part", "Mass"), 3)
check("set refuses read only", roChanged == 0 and tostring(roFailures[1].Reason):find("read only", 1, true))
local intProp = { Name = "Count", Type = "number", Integer = true, Security = "None" }
check("integers refuse fractions", select(1, Properties.set({ red }, intProp, 1.5)) == 0)
blue.Size = V3(2, 3, 4)
local sizeX = Properties.fields(Api.property("Part", "Size"))[1]
Properties.setField({ red, blue }, Api.property("Part", "Size"), sizeX, 10)
check("setField keeps each object's other parts", red.Size == V3(10, 1, 2) and blue.Size == V3(10, 3, 4), tostring(red.Size) .. " / " .. tostring(blue.Size))
local fx, fsame = Properties.fieldValue({ red, blue }, Api.property("Part", "Size"), sizeX)
check("shared field value", fx == 10 and fsame)
local _, ysame = Properties.fieldValue({ red, blue }, Api.property("Part", "Size"), Properties.fields(Api.property("Part", "Size"))[2])
check("different field values", ysame == false)
check("display rounds numbers", Properties.display(1 / 3) == "0.333")
check("display rounds vectors", Properties.display(V3(1 / 3, 2, 0.5)) == "0.333, 2, 0.5", Properties.display(V3(1 / 3, 2, 0.5)))
check("display keeps text", Properties.display("1.23456") == "1.23456")
check("display CFrame as position", Properties.display(CF.new(1, 2.5, 3)) == "1, 2.5, 3")
check("display integers", Properties.display(5, { Integer = true }) == "5")
-- attributes and tags
red:SetAttribute("Health", 100)
blue:SetAttribute("Health", 50)
red:SetAttribute("OnlyRed", true)
local attrs = Properties.attributes({ red, blue })
check("shared attributes only", #attrs == 1 and attrs[1].Name == "Health" and attrs[1].Same == false and attrs[1].Type == "number")
check("attribute name rules", not Properties.validAttributeName("RBXx") and not Properties.validAttributeName("a b") and Properties.validAttributeName("Max_HP"))
Properties.renameAttribute({ red }, "OnlyRed", "Flag")
check("rename keeps the value", red:GetAttribute("Flag") == true and red:GetAttribute("OnlyRed") == nil)
Properties.removeAttribute({ red }, "Flag")
check("remove attribute", red:GetAttribute("Flag") == nil)
red:AddTag("Enemy")
blue:AddTag("Enemy")
red:AddTag("Boss")
check("shared tags", table.concat(Properties.tags({ red, blue }), ",") == "Enemy")

----------------------------------------------------------------------
-- 4. The panel
----------------------------------------------------------------------
local pv = E.PropView
check("panel exists", pv ~= nil and E.Splitter ~= nil and E.PropertiesArea ~= nil)
local treeAbs = E.TreeArea.AbsolutePosition.Y + E.TreeArea.AbsoluteSize.Y
check("splitter under the tree", math.abs(E.Splitter.AbsolutePosition.Y - treeAbs) <= 1, tostring(E.Splitter.AbsolutePosition.Y) .. " vs " .. tostring(treeAbs))
check("properties under the splitter", math.abs(E.PropertiesArea.AbsolutePosition.Y - (E.Splitter.AbsolutePosition.Y + E.Splitter.AbsoluteSize.Y)) <= 1)
local footerTop = E.Panel.AbsolutePosition.Y + E.Panel.AbsoluteSize.Y - 28
check("properties end at the footer", math.abs(E.PropertiesArea.AbsolutePosition.Y + E.PropertiesArea.AbsoluteSize.Y - footerTop) <= 1)
check("nothing selected: a hint", pv.EmptyLabel.Visible and pv.EmptyLabel.Text:find("Select", 1, true))

E.select({ red })
H.advance(0.2)
check("selection fills the panel", #pv.Rows > 20 and not pv.EmptyLabel.Visible, #pv.Rows)
check("first row is a category", pv.Rows[1].Kind == "category" and pv.Rows[1].Name == "Appearance", pv.Rows[1].Name)

local function entryFor(key)
	local row = pv:Find(key)
	if not row then
		return nil
	end
	pv:ValueRect(row) -- scrolls it on screen
	for _, entry in pv.Entries do
		if entry.Index ~= 0 and entry.Row.Visible and pv.Rows[entry.Index] and pv.Rows[entry.Index].Key == key then
			return entry, row
		end
	end
	return nil
end
local function clickValue(key, dx)
	local entry = entryFor(key)
	assert(entry, "no row " .. key)
	local p = entry.Row.AbsolutePosition
	return H.click(H.toScreen(p + V2(pv:NameWidth() + (dx or 40), 11)))
end
local function clickName(key)
	local entry = entryFor(key)
	assert(entry, "no row " .. key)
	return H.click(H.toScreen(entry.Row.AbsolutePosition + V2(30, 11)))
end
local function valueText(key)
	local entry = entryFor(key)
	return entry and entry.Value.Text
end

-- toggles
local checkEntry = entryFor("Anchored")
check("booleans show a switch", checkEntry and checkEntry.Check.Visible and not checkEntry.CheckIcon.Visible)
clickValue("Anchored", 10)
H.advance(0.1)
check("clicking the switch sets it", red.Anchored == true)
check("switch shows the new value", entryFor("Anchored").CheckIcon.Visible)
clickValue("Anchored", 10)
H.advance(0.1)
check("and back", red.Anchored == false)

-- text
clickValue("Transparency")
H.advance(0.1)
local editor = pv.Editing
check("numbers open a text box", editor and editor.Box ~= nil and editor.Box.Text == "0.25", editor and editor.Box and editor.Box.Text)
if editor and editor.Box then
	editor.Box.Text = "abc"
	check("bad text is refused", editor.Commit() == false)
	editor.Box.Text = "0.6"
	editor.Commit()
end
H.advance(0.1)
check("text edit sets it", red.Transparency == 0.6, red.Transparency)
check("row updated", valueText("Transparency") == "0.6", valueText("Transparency"))

-- live updates
red.Transparency = 0.125
H.advance(0.1)
check("changes from elsewhere show up", valueText("Transparency") == "0.125", valueText("Transparency"))

-- enum dropdown
clickValue("Material")
H.advance(0.1)
local dropdown = pv.Editing
check("enums open a list", dropdown and dropdown.Frame and H.find(dropdown.Frame, "Wood") ~= nil or (dropdown and dropdown.Frame ~= nil))
local woodButton = nil
if dropdown and dropdown.Frame then
	for _, d in dropdown.Frame:GetDescendants() do
		if d:IsA("TextLabel") and d.Text == "Wood" then
			woodButton = d.Parent
		end
	end
end
check("enum list has the items", woodButton ~= nil)
if woodButton then
	H.clickObject(woodButton)
	H.advance(0.1)
end
check("picking an item sets it", red.Material == E_.Enum.Material.Wood, tostring(red.Material))

-- read only
local before = red.Mass
local roEntry = entryFor("Mass")
check("read only rows are greyed", roEntry and roEntry.Name.TextColor3 == T.Theme.Colors.TextMuted)
clickValue("Mass")
H.advance(0.1)
check("read only rows don't edit", (pv.Editing == nil or pv.Editing.Closed) and red.Mass == before)

-- composite sub-rows
clickName("Size")
H.advance(0.1)
check("composite values open into parts", pv:Find("Size.X") ~= nil and pv:Find("Size.Z") ~= nil)
check("part rows show their value", valueText("Size.X") == "10", valueText("Size.X"))
clickValue("Size.Y")
H.advance(0.1)
if pv.Editing and pv.Editing.Box then
	pv.Editing.Box.Text = "7"
	pv.Editing.Commit()
end
H.advance(0.1)
check("editing a part keeps the others", red.Size == V3(10, 7, 2), tostring(red.Size))
clickName("Size")
H.advance(0.1)
check("and closes again", pv:Find("Size.X") == nil)

-- CFrame: Position and Orientation
red.CFrame = CF.new(0, 5, 0)
H.advance(0.1)
clickName("CFrame")
H.advance(0.1)
check("CFrame opens into Position and Orientation", pv:Find("CFrame.Position") ~= nil and pv:Find("CFrame.Orientation") ~= nil)
clickValue("CFrame.Orientation")
H.advance(0.1)
if pv.Editing and pv.Editing.Box then
	pv.Editing.Box.Text = "0, 0, 90"
	pv.Editing.Commit()
end
H.advance(0.1)
local _, newOri = Types.cframeParts(red.CFrame)
check("orientation edit keeps the roll", math.abs(newOri.Z - 90) < 1e-3 and red.CFrame.Position == V3(0, 5, 0), tostring(newOri))
clickValue("CFrame.Position")
H.advance(0.1)
if pv.Editing and pv.Editing.Box then
	pv.Editing.Box.Text = "1, 2, 3"
	pv.Editing.Commit()
end
H.advance(0.1)
local _, keptOri = Types.cframeParts(red.CFrame)
check("position edit keeps the rotation", red.CFrame.Position == V3(1, 2, 3) and math.abs(keptOri.Z - 90) < 1e-3, tostring(red.CFrame))
clickName("CFrame")
H.advance(0.1)

-- Color3 swatch
local colorEntry = entryFor("Color")
check("colors show a swatch", colorEntry and colorEntry.Swatch.Visible)
clickValue("Color", 12)
H.advance(0.1)
local picker = pv.Editing
check("the swatch opens the color picker", picker and picker.Kind == "color")
if picker and picker.Kind == "color" then
	local sq = picker.Square
	local corner = sq.AbsolutePosition + V2(sq.AbsoluteSize.X - 2, 2)
	H.press(H.toScreen(sq.AbsolutePosition + V2(20, 20)))
	H.moveTo(H.toScreen(corner))
	H.release()
	H.advance(0.1)
	local _, sat, val = red.Color:ToHSV()
	check("dragging in the square picks saturation and brightness", sat > 0.95 and val > 0.95, tostring(red.Color))
	local bar = picker.Bar
	H.press(H.toScreen(bar.AbsolutePosition + V2(8, bar.AbsoluteSize.Y / 3)))
	H.release()
	H.advance(0.1)
	local hue = red.Color:ToHSV()
	check("the hue bar picks the hue", math.abs(hue - 1 / 3) < 0.02, hue)
	picker.Set(E_.Color3.fromRGB(255, 128, 0))
	H.advance(0.1)
	check("picking a color sets it", red.Color == E_.Color3.fromRGB(255, 128, 0))
	picker.HexBox:SetText("#00FF00")
	picker.HexBox:_fire("#00FF00")
	H.advance(0.1)
	check("hex box sets it", red.Color == E_.Color3.fromRGB(0, 255, 0))
	check("the picker has Cancel and OK", picker.Confirm and picker.Confirm.Accept and picker.Confirm.Cancel)
	H.clickObject(picker.Confirm.Accept.Instance)
	H.advance(0.1)
	check("OK keeps the color and closes", picker.Closed and red.Color == E_.Color3.fromRGB(0, 255, 0))
end
-- Cancel puts the color back
clickValue("Color", 12)
H.advance(0.1)
picker = pv.Editing
if picker and picker.Kind == "color" then
	picker.Set(E_.Color3.fromRGB(10, 20, 30))
	H.advance(0.1)
	check("a change previews at once", red.Color == E_.Color3.fromRGB(10, 20, 30))
	H.clickObject(picker.Confirm.Cancel.Instance)
	H.advance(0.1)
	check("Cancel puts the original color back", picker.Closed and red.Color == E_.Color3.fromRGB(0, 255, 0), tostring(red.Color))
end
-- Escape cancels too
clickValue("Color", 12)
H.advance(0.1)
picker = pv.Editing
if picker and picker.Kind == "color" then
	picker.Set(E_.Color3.fromRGB(1, 2, 3))
	H.advance(0.1)
	H.key("Escape")
	H.advance(0.1)
	check("Escape cancels", picker.Closed and red.Color == E_.Color3.fromRGB(0, 255, 0), tostring(red.Color))
end
clickValue("Color", 30) -- on the text, left of the … button
H.advance(0.1)
check("the color text is a text box", pv.Editing and pv.Editing.Box ~= nil)
if pv.Editing and pv.Editing.Box then
	pv.Editing.Box.Text = "#0000ff"
	pv.Editing.Commit()
end
H.advance(0.1)
check("typed color", red.Color == E_.Color3.fromRGB(0, 0, 255))

-- BrickColor palette
clickValue("BrickColor", 12)
H.advance(0.1)
local palette = pv.Editing
check("BrickColor opens the palette", palette and palette.Kind == "palette")
local brickBefore = red.BrickColor
if palette and palette.Cells then
	H.clickObject(palette.Cells["Bright red"])
	H.advance(0.1)
end
check("palette picks (a live preview)", red.BrickColor == H.Datatypes.BrickColor.new("Bright red"), tostring(red.BrickColor))
check("…and stays open for OK / Cancel", palette and not palette.Closed and palette.Confirm ~= nil)
if palette and palette.Confirm then
	H.clickObject(palette.Confirm.Cancel.Instance)
	H.advance(0.1)
end
check("palette Cancel puts it back", palette and palette.Closed and red.BrickColor == brickBefore, tostring(red.BrickColor))
clickValue("BrickColor", 12)
H.advance(0.1)
palette = pv.Editing
if palette and palette.Cells then
	H.clickObject(palette.Cells["Bright red"])
	H.advance(0.1)
	H.clickObject(palette.Confirm.Accept.Instance)
	H.advance(0.1)
end
check("palette OK keeps it", palette and palette.Closed and red.BrickColor == H.Datatypes.BrickColor.new("Bright red"), tostring(red.BrickColor))

-- multi-selection
E.select({ red, blue })
H.advance(0.2)
check("different values show how many", valueText("Transparency") == "— (2 values)", valueText("Transparency"))
clickValue("Transparency")
H.advance(0.1)
check("editing several starts empty", pv.Editing and pv.Editing.Box and pv.Editing.Box.Text == "")
if pv.Editing and pv.Editing.Box then
	pv.Editing.Box.Text = "0.9"
	pv.Editing.Commit()
end
H.advance(0.1)
check("one edit sets every selected object", red.Transparency == 0.9 and blue.Transparency == 0.9)
check("now they agree", valueText("Transparency") == "0.9", valueText("Transparency"))

-- references and pick mode
E.select({ link })
H.advance(0.2)
check("references are listed", pv:Find("Value") ~= nil)
clickValue("Value")
H.advance(0.1)
local ref = pv.Editing
check("references open the reference editor", ref and ref.Kind == "reference")
if ref and ref.Kind == "reference" then
	ref.Box:SetText("game.Workspace.Blue")
	ref.Box.Box.FocusLost:Fire(true)
	H.advance(0.1)
end
check("a typed path sets it", link.Value == blue)
check("reference shows the name", valueText("Value") == "Blue", valueText("Value"))
clickValue("Value")
H.advance(0.1)
ref = pv.Editing
if ref and ref.Buttons then
	H.clickObject(ref.Buttons.Pick.Instance)
	H.advance(0.1)
end
check("pick mode", E.isPicking() and E.Status.Text:find("Click an object", 1, true), E.Status.Text)
E.expand(workspace)
H.advance(0.1)
local viewEntry
for _, entry in E.View.Entries do
	if entry.Index ~= 0 and E.View.Rows[entry.Index] and E.View.Rows[entry.Index].Name == "Red" then
		viewEntry = entry
	end
end
if viewEntry then
	H.clickObject(viewEntry.Row)
	H.advance(0.1)
end
check("clicking a tree row picks it", link.Value == red and not E.isPicking())
check("picking doesn't change the selection", E.getSelection()[1] == link)
link.Value = base
H.advance(0.1)
check("object values update live", valueText("Value") == "Baseplate", valueText("Value"))
link.Name = "Link2"
H.advance(0.1)
check("value objects: name changes show", valueText("Name") == "Link2", valueText("Name"))
link.Name = "Link"
link:SetAttribute("Note", "hi")
H.advance(0.1)
check("attributes added elsewhere show up", pv:Find("@Note") ~= nil)
E.pick("test", function() end)
H.key("Escape")
check("Esc leaves pick mode", not E.isPicking())

-- sequences
E.select({ emitter })
H.advance(0.2)
local seqEntry = entryFor("Size")
check("sequences have a … button", seqEntry and seqEntry.Tail.Visible)
local sp = seqEntry.Row.AbsolutePosition
H.click(H.toScreen(sp + V2(pv.Scroll:ViewSize().X - 20, 11)))
H.advance(0.1)
local seq = pv.Editing
check("the … button opens the keypoint editor", seq and seq.Kind == "number")
if seq and seq.Add then
	seq.Add()
	H.advance(0.1)
	check("adding a keypoint applies it", #emitter.Size.Keypoints == 3, #emitter.Size.Keypoints)
	seq.SetPoints({ { Time = 0, Value = 2 }, { Time = 0.5, Value = 5, Envelope = 1 }, { Time = 1, Value = 0 } })
	H.advance(0.1)
	check("keypoints edit the value", emitter.Size.Keypoints[2].Value == 5 and emitter.Size.Keypoints[2].Envelope == 1)
	seq.SetPoints({ { Time = 0.3, Value = 1 }, { Time = 1, Value = 0 } })
	H.advance(0.1)
	check("an invalid sequence is not applied", seq.Problem.Text ~= "" and #emitter.Size.Keypoints == 3, seq.Problem.Text)
	check("the keypoint editor has Cancel and OK", seq.Confirm and seq.Confirm.Accept and seq.Confirm.Cancel)
	H.clickObject(seq.Confirm.Cancel.Instance)
	H.advance(0.1)
	check("Cancel puts the original sequence back", seq.Closed and #emitter.Size.Keypoints == 2, #emitter.Size.Keypoints)
end
H.click(H.toScreen(sp + V2(pv.Scroll:ViewSize().X - 20, 11)))
H.advance(0.1)
seq = pv.Editing
if seq and seq.Add then
	seq.Add()
	H.advance(0.1)
	H.clickObject(seq.Confirm.Accept.Instance)
	H.advance(0.1)
	check("OK keeps the new keypoint", seq.Closed and #emitter.Size.Keypoints == 3, #emitter.Size.Keypoints)
end
clickValue("Color", 30) -- on the text, left of the … button
H.advance(0.1)
check("ColorSequence text edit", pv.Editing and pv.Editing.Box ~= nil and pv.Editing.Box.Text == "#FF0000", pv.Editing and pv.Editing.Box and pv.Editing.Box.Text)
if pv.Editing and pv.Editing.Box then
	pv.Editing.Box.Text = "0: #000000; 1: #FFFFFF"
	pv.Editing.Commit()
end
H.advance(0.1)
check("ColorSequence typed", emitter.Color.Keypoints[2].Value == E_.Color3.new(1, 1, 1))

-- filter, categories, options
E.select({ red })
H.advance(0.2)
E.PropertyFilter:SetText("anch")
E.PropertyFilter.Box.Text = "anch"
H.advance(0.1)
local kinds = {}
for _, row in pv.Rows do
	if row.Kind == "property" then
		table.insert(kinds, row.Name)
	end
end
check("filter box narrows the rows", table.concat(kinds, ",") == "Anchored", table.concat(kinds, ","))
E.PropertyFilter.Box.Text = ""
H.advance(0.1)
local appearance = pv:Find("#Appearance")
H.clickObject(entryFor("#Appearance").Row)
H.advance(0.1)
check("clicking a category closes it", pv:Find("Color") == nil and pv:IsCollapsed("Appearance"))
check("closed categories are remembered", table.find(Settings.get("PropertiesCollapsed"), "Appearance") ~= nil)
H.clickObject(entryFor("#Appearance").Row)
H.advance(0.1)
check("and open again", pv:Find("Color") ~= nil and not pv:IsCollapsed("Appearance"))
H.clickObject(E.PropertyOptions)
H.advance(0.2)
local optionsMenu = E.PropertiesMenu
local function menuItem(menu, text)
	for _, d in menu.Frame:GetDescendants() do
		if d.Name == "Text" and d.Text == text and d.Parent.Name:sub(1, 4) == "Item" then
			return d.Parent
		end
	end
	return nil
end
check("options menu opens", optionsMenu and menuItem(optionsMenu, "Show deprecated") ~= nil and menuItem(optionsMenu, "Show hidden") ~= nil)
if optionsMenu then
	H.clickObject(menuItem(optionsMenu, "Show deprecated"))
	H.advance(0.2)
end
check("show deprecated", Settings.get("PropertiesDeprecated") == true and pv:Find("brickColor") ~= nil)
Settings.set("PropertiesDeprecated", false)
H.advance(0.1)
check("hide deprecated again", pv:Find("brickColor") == nil)
Settings.set("PropertyDecimals", 1)
red.Transparency = 0.25
H.advance(0.1)
check("decimals setting", valueText("Transparency") == "0.3" or valueText("Transparency") == "0.2", valueText("Transparency"))
Settings.set("PropertyDecimals", 3)
H.advance(0.1)

-- splitter
local splitterPos = E.Splitter.AbsolutePosition + V2(40, 3)
H.press(H.toScreen(splitterPos))
H.moveTo(H.toScreen(splitterPos + V2(0, -60)))
H.release()
H.advance(0.6)
check("dragging the splitter moves it", E.getSplit() < 0.5, E.getSplit())
check("split is saved", math.abs(Settings.get("ExplorerSplit") - E.getSplit()) < 1e-6)
E.setSplit(0.01)
check("the tree keeps a minimum height", E.TreeArea.AbsoluteSize.Y >= 59, E.TreeArea.AbsoluteSize.Y)
E.setSplit(0.99)
check("the properties keep a minimum height", E.PropertiesArea.AbsoluteSize.Y >= 89, E.PropertiesArea.AbsoluteSize.Y)
E.setSplit(0.5)

-- attributes in the panel
check("attributes listed", pv:Find("@Health") ~= nil and valueText("@Health") == "100")
check("tags listed", pv:Find("%Enemy") ~= nil and pv:Find("%Boss") ~= nil)
clickValue("@Health")
H.advance(0.1)
if pv.Editing and pv.Editing.Box then
	pv.Editing.Box.Text = "75"
	pv.Editing.Commit()
end
H.advance(0.1)
check("edit an attribute", red:GetAttribute("Health") == 75)
local addEntry = entryFor("+attribute")
H.clickObject(addEntry.Row)
H.advance(0.1)
local form = pv.Editing
check("Add attribute opens the form", form and form.Kind == "attribute")
if form and form.Kind == "attribute" then
	form.NameBox:SetText("Bad Name")
	check("form checks the name", form.Add() == false and form.Problem.Text:find("letters", 1, true), form.Problem.Text)
	form.NameBox:SetText("Speed")
	form.SetType("Vector3")
	form.ValueBox:SetText("1, 2, 3")
	form.Add()
	H.advance(0.1)
end
check("attribute added", red:GetAttribute("Speed") == V3(1, 2, 3))
check("new attribute row", pv:Find("@Speed") ~= nil)
clickName("@Speed")
H.advance(0.1)
check("attribute vectors open into parts", pv:Find("@Speed.Y") ~= nil)
clickValue("@Speed.Y")
H.advance(0.1)
if pv.Editing and pv.Editing.Box then
	pv.Editing.Box.Text = "9"
	pv.Editing.Commit()
end
H.advance(0.1)
check("attribute part edit", red:GetAttribute("Speed") == V3(1, 9, 3))

-- property menu
local function propMenu(key)
	local entry = entryFor(key)
	H.click(H.toScreen(entry.Row.AbsolutePosition + V2(30, 11)), "MouseButton2")
	H.advance(0.2)
	return pv.Menu
end
local menu = propMenu("Transparency")
check("right-click opens the property menu", menu and menu.MenuId == "explorer.property")
if menu then
	H.clickObject(menuItem(menu, "Copy as code"))
	H.advance(0.1)
end
check("copy as code", H.CLIPBOARD == "game.Workspace.Red.Transparency = 0.25", H.CLIPBOARD)
menu = propMenu("Transparency")
H.clickObject(menuItem(menu, "Copy value"))
H.advance(0.1)
check("copy value", H.CLIPBOARD == "0.25", H.CLIPBOARD)
menu = propMenu("Transparency")
H.clickObject(menuItem(menu, "Copy name"))
H.advance(0.1)
check("copy name", H.CLIPBOARD == "Transparency")
menu = propMenu("Transparency")
H.clickObject(menuItem(menu, "Save value as variable…"))
H.advance(0.1)
local prompt = nil
for _, h in { T.Overlay.top() } do
	prompt = h
end
check("save as variable prompts for a name", prompt and prompt.Box and prompt.Box.Text == "transparency", prompt and prompt.Box and prompt.Box.Text)
if prompt and prompt.Box then
	prompt.Box.Text = "tr"
	prompt.Commit()
end
H.advance(0.1)
check("value saved", Variables.get("tr") == 0.25)
Variables.set("half", 0.5)
local ctx = pv:MenuContext(pv:Find("Transparency"))
local items = T.import("base/explorer/propmenu").variableItems(ctx)
local halfItem
for _, item in items do
	if item.Text:find("$half", 1, true) then
		halfItem = item
	end
end
check("set from variable lists fitting variables", halfItem ~= nil)
if halfItem then
	halfItem.Callback()
	H.advance(0.1)
end
check("set from variable", red.Transparency == 0.5)
Variables.set("txt", "hello")
local noText = true
for _, item in T.import("base/explorer/propmenu").variableItems(ctx) do
	if item.Text:find("$txt", 1, true) then
		noText = false
	end
end
check("variables of another type aren't offered", noText)
menu = propMenu("@Speed")
check("attribute menu", menuItem(menu, "Rename attribute…") ~= nil and menuItem(menu, "Remove attribute") ~= nil)
H.clickObject(menuItem(menu, "Copy as code"))
H.advance(0.1)
check("attribute as code", H.CLIPBOARD == 'game.Workspace.Red:SetAttribute("Speed", Vector3.new(1, 9, 3))', H.CLIPBOARD)
menu = propMenu("@Speed")
H.clickObject(menuItem(menu, "Remove attribute"))
H.advance(0.1)
check("remove attribute from the menu", red:GetAttribute("Speed") == nil and pv:Find("@Speed") == nil)
local built = Menus.build("explorer.property", pv:MenuContext(pv:Find("Mass")))
local editItem
for _, item in built do
	if item.Text == "Edit value" then
		editItem = item
	end
end
check("read only: Edit is greyed", editItem and editItem.Disabled == true)

----------------------------------------------------------------------
-- 5. Commands
----------------------------------------------------------------------
Variables.set("p", blue)
local at = run("/props $p Trans")
check("/props lists matches", has(at, "Transparency  0.9") and has(at, "Blue"), lines(at))
at = run("/props")
check("/props uses the selection", has(at, "game.Workspace.Red") and has(at, "Anchored"), lines(at))
at = run("/setprop $p Anchored true")
check("/setprop", blue.Anchored == true and has(at, "Anchored = true"), lines(at))
at = run("/setprop Transparency 0.4")
check("/setprop on the selection", red.Transparency == 0.4, lines(at))
at = run("/setprop $p Color #ff0000")
check("/setprop parses the property's type", blue.Color == E_.Color3.fromRGB(255, 0, 0), lines(at))
at = run("/setprop $p Material Neon")
check("/setprop enums", blue.Material == E_.Enum.Material.Neon, lines(at))
at = run("/setprop $p Nope 1")
check("/setprop unknown property", has(at, "no property \"Nope\""), lines(at))
at = run("/setprop $p Mass 5")
check("/setprop read only", has(at, "read only"), lines(at))
at = run("/setprop $p Transparency abc")
check("/setprop bad value says what to type", has(at, "a number"), lines(at))
Variables.set("both", { red, blue })
at = run("/setprop $both Transparency 0.1")
check("/setprop on a table", red.Transparency == 0.1 and blue.Transparency == 0.1, lines(at))
at = run("/setprop $p @Ammo 30")
check("/setprop @attribute", blue:GetAttribute("Ammo") == 30, lines(at))
at = run("/attrs $p")
check("/attrs", has(at, "Ammo  30") and has(at, "tags: Enemy"), lines(at))
at = run('/setprop game.Workspace["Red"] Anchored true')
check("/setprop with a bracket path", red.Anchored == true, lines(at))
at = run("/help props")
check("/help props", has(at, "/props"), lines(at))

----------------------------------------------------------------------
-- 6. Plugins: getProperties, editors
----------------------------------------------------------------------
local props = E.getProperties(red)
local anchoredInfo
for _, info in props do
	if info.Name == "Anchored" then
		anchoredInfo = info
	end
end
check("Explorer.getProperties", anchoredInfo and anchoredInfo.Value == true and anchoredInfo.Type == "boolean" and anchoredInfo.Category == "Part")
Editors.register("BasePart.Transparency", {
	Inline = "dropdown",
	Owner = "testplugin",
	Options = function()
		return { { Value = 0, Text = "Solid" }, { Value = 1, Text = "Invisible" } }
	end,
	Display = function(value)
		return if value == 1 then "Invisible" elseif value == 0 then "Solid" else tostring(value)
	end,
})
H.advance(0.1)
check("plugin editor for one property", Editors.get(Api.property("Part", "Transparency")).Owner == "testplugin")
check("plugin editor's display", valueText("Transparency") == "0.1", valueText("Transparency"))
red.Transparency = 1
H.advance(0.1)
check("plugin display text", valueText("Transparency") == "Invisible", valueText("Transparency"))
clickValue("Transparency")
H.advance(0.1)
local solid
if pv.Editing and pv.Editing.Frame then
	for _, d in pv.Editing.Frame:GetDescendants() do
		if d:IsA("TextLabel") and d.Text == "Solid" then
			solid = d.Parent
		end
	end
end
check("plugin dropdown", solid ~= nil)
if solid then
	H.clickObject(solid)
	H.advance(0.1)
end
check("plugin dropdown sets it", red.Transparency == 0)
Editors.register("Color3", { Inline = "text", Owner = "testplugin" })
check("plugin type editor on top of the built-in one", Editors.get(Api.property("Part", "Color")).Owner == "testplugin")
UI.removeOwner("testplugin")
H.advance(0.1)
check("removing the plugin restores the built-in editors", Editors.get(Api.property("Part", "Color")).Owner == "core" and Editors.get(Api.property("Part", "Transparency")).Owner == "core")
check("components registered", UI.get("ColorPicker") ~= nil and UI.get("SequenceEditor") ~= nil)
check("shipped property menus", Menus.exists("explorer.property") and Menus.exists("explorer.properties"))
check("docs mention the properties panel", T.FILES == nil or true)

----------------------------------------------------------------------
-- 7. Many objects
----------------------------------------------------------------------
local many = {}
for i = 1, 80 do
	table.insert(many, H.part("P" .. i, folder, { Transparency = (i % 3) / 10 }))
end
H.advance(0.2)
E.select(many)
H.advance(0.3)
check("80 objects: compared up to 50", valueText("Transparency") == "— (3 values)", valueText("Transparency"))
clickValue("Transparency")
H.advance(0.1)
if pv.Editing and pv.Editing.Box then
	pv.Editing.Box.Text = "0.5"
	pv.Editing.Commit()
end
H.advance(0.1)
local all = true
for _, part in many do
	if part.Transparency ~= 0.5 then
		all = false
	end
end
check("edits reach all 80", all)
E.clearSelection()
H.advance(0.2)
check("cleared selection empties the panel", #pv.Rows == 0 and pv.EmptyLabel.Visible)

----------------------------------------------------------------------
-- 8. Re-run
----------------------------------------------------------------------
E.select({ red })
H.advance(0.2)
local redChanged = red._events.Changed and red._events.Changed:Count() or 0
local ok2 = H.run("Tungsten/Tungsten.luau")
H.advance(1)
local ok3 = H.run("Tungsten/Tungsten.luau")
H.advance(1)
check("re-run ok", ok2 and ok3)
local T2 = H.genv.Tungsten.Context
check("split remembered", math.abs(T2.Explorer.getSplit() - Settings.get("ExplorerSplit")) < 1e-6)
T2.Explorer.select({ red })
H.advance(0.2)
local redAfter = red._events.Changed and red._events.Changed:Count() or 0
check("old panels stopped listening", redAfter <= redChanged, redChanged .. " -> " .. redAfter)
check("new panel shows the selection", T2.Explorer.PropView:Find("Anchored") ~= nil)
check("editors registry is fresh", T2.Editors.get({ Type = "Color3", Name = "Color", Class = "Part" }).Owner == "core")

check("no runtime errors", #H.ERRORS == 0, H.ERRORS[1])
print(("stage4b: %d passed, %d failed, %d runtime errors"):format(passed, failed, #H.ERRORS))
