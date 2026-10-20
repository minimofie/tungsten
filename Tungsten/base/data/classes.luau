--[[
	Tungsten · base/data/classes
	A bundled list of classes with a display category each (no downloads).
	Classes not listed fall back to a category guessed from the name.

		Classes.category("RemoteEvent")  -> "remote"
		Classes.style("RemoteEvent")     -> { Icon = "class_remote", Color = Color3 }
		Classes.list()                   -> every listed class, sorted
		Classes.creatable()              -> classes Instance.new can make
		Classes.add("Vehicle", "vehicle", { Creatable = false, Owner = "myplugin" })
		                                 -- teach Tungsten a class (icon, pickers)
]]

local T = ...
local Categories = T.import("base/data/categories")

-- category -> classes. "!" marks a class Instance.new can't create here
-- (abstract base classes, services, engine-only objects).
local GROUPS = {
	part = {
		"Part", "MeshPart", "WedgePart", "CornerWedgePart", "TrussPart", "SpawnLocation", "Seat", "VehicleSeat",
		"SkateboardPlatform", "UnionOperation", "NegateOperation", "IntersectOperation", "PartOperation!",
		"BasePart!", "FormFactorPart!", "Terrain!", "Platform",
	},
	model = { "Model", "WorldModel", "Actor", "PVInstance!", "WorldRoot!", "Workspace!" },
	folder = { "Folder", "Configuration" },
	script = { "Script", "LuaSourceContainer!", "BaseScript!" },
	localscript = { "LocalScript" },
	modulescript = { "ModuleScript" },
	gui = {
		"ScreenGui", "SurfaceGui", "BillboardGui", "LayerCollector!", "GuiBase!", "GuiBase2d!", "GuiBase3d!",
		"PlayerGui!", "StarterGui!", "CoreGui!", "BasePlayerGui!", "SelectionBox", "SurfaceSelection", "SelectionSphere",
		"BoxHandleAdornment", "ConeHandleAdornment", "CylinderHandleAdornment", "LineHandleAdornment",
		"SphereHandleAdornment", "WireframeHandleAdornment", "ImageHandleAdornment", "Handles", "ArcHandles",
	},
	frame = { "Frame", "ScrollingFrame", "CanvasGroup", "ViewportFrame", "VideoFrame", "GuiObject!" },
	text = { "TextLabel", "TextBox" },
	button = { "TextButton", "ImageButton", "GuiButton!" },
	image = { "ImageLabel", "Decal", "Texture", "SurfaceAppearance", "FaceInstance!" },
	layout = {
		"UIListLayout", "UIGridLayout", "UITableLayout", "UIPageLayout", "UIPadding", "UIScale", "UICorner",
		"UIStroke", "UIGradient", "UIAspectRatioConstraint", "UISizeConstraint", "UITextSizeConstraint",
		"UIFlexItem", "UIDragDetector", "UIComponent!", "UIConstraint!", "UIGridStyleLayout!", "UILayout!",
	},
	remote = { "RemoteEvent", "RemoteFunction", "UnreliableRemoteEvent", "BaseRemoteEvent!" },
	bindable = { "BindableEvent", "BindableFunction" },
	value = {
		"StringValue", "NumberValue", "IntValue", "BoolValue", "ObjectValue", "CFrameValue", "Vector3Value",
		"Color3Value", "BrickColorValue", "RayValue", "ValueBase!",
	},
	light = { "PointLight", "SpotLight", "SurfaceLight", "Light!", "Lighting!" },
	sound = { "Sound", "SoundGroup", "SoundEffect!", "ReverbSoundEffect", "EchoSoundEffect", "EqualizerSoundEffect",
		"ChorusSoundEffect", "CompressorSoundEffect", "DistortionSoundEffect", "FlangeSoundEffect",
		"PitchShiftSoundEffect", "TremoloSoundEffect", "SoundService!" },
	effect = {
		"ParticleEmitter", "Beam", "Trail", "Fire", "Smoke", "Sparkles", "Explosion", "Highlight", "ForceField",
		"Atmosphere", "Sky", "Clouds", "BloomEffect", "BlurEffect", "ColorCorrectionEffect", "DepthOfFieldEffect",
		"SunRaysEffect", "PostEffect!",
	},
	constraint = {
		"Weld", "WeldConstraint", "Motor6D", "Motor", "Snap", "Glue", "ManualWeld", "JointInstance!", "Constraint!",
		"RodConstraint", "RopeConstraint", "SpringConstraint", "HingeConstraint", "BallSocketConstraint",
		"PrismaticConstraint", "CylindricalConstraint", "AlignPosition", "AlignOrientation", "LinearVelocity",
		"AngularVelocity", "VectorForce", "Torque", "LineForce", "NoCollisionConstraint", "PlaneConstraint",
		"UniversalConstraint", "TorsionSpringConstraint", "RigidConstraint", "BodyPosition", "BodyGyro",
		"BodyVelocity", "BodyAngularVelocity", "BodyForce", "BodyThrust", "BodyMover!",
	},
	attachment = { "Attachment", "Bone" },
	camera = { "Camera" },
	player = { "Player!", "Players!", "Team", "Teams!" },
	humanoid = {
		"Humanoid", "HumanoidDescription", "Shirt", "Pants", "ShirtGraphic", "Accessory", "Hat", "BodyColors",
		"CharacterMesh", "Animator", "Clothing!",
	},
	service = {
		"ReplicatedStorage!", "ReplicatedFirst!", "ServerStorage!", "ServerScriptService!", "StarterPlayer!",
		"StarterPack!", "StarterPlayerScripts!", "StarterCharacterScripts!", "Chat!", "TextChatService!",
		"RunService!", "UserInputService!", "TweenService!", "HttpService!", "MarketplaceService!",
		"CollectionService!", "ContextActionService!", "PathfindingService!", "TeleportService!",
		"DataModel!", "Debris!", "TestService!", "LocalizationService!", "GuiService!", "VRService!",
		"ProximityPromptService!", "ContentProvider!", "PhysicsService!",
	},
	mesh = { "SpecialMesh", "BlockMesh", "CylinderMesh", "FileMesh!", "DataModelMesh!" },
	animation = {
		"Animation", "AnimationController", "AnimationTrack!", "KeyframeSequence", "Keyframe", "Pose",
		"Tween!", "TweenBase!",
	},
	tool = {
		"Tool", "HopperBin", "BackpackItem!", "Backpack!", "ClickDetector", "ProximityPrompt", "DragDetector",
		"Dialog", "DialogChoice",
	},
	unknown = { "Instance!", "PathfindingModifier", "PathfindingLink" },
}

local Classes = {}

local categoryOf: { [string]: string } = {}
local creatable: { [string]: boolean } = {}
local all: { string } = {}

for category, list in GROUPS do
	for _, entry in list do
		local name = entry:gsub("!$", "")
		if categoryOf[name] == nil then
			categoryOf[name] = category
			table.insert(all, name)
		end
		if not entry:find("!$") then
			creatable[name] = true
		end
	end
end
table.sort(all)

local creatableList = {}
for _, name in all do
	if creatable[name] then
		table.insert(creatableList, name)
	end
end

-- Guess from the name when a class isn't listed.
local PATTERNS = {
	{ "RemoteEvent$", "remote" },
	{ "RemoteFunction$", "remote" },
	{ "^Bindable", "bindable" },
	{ "Value$", "value" },
	{ "LocalScript$", "localscript" },
	{ "ModuleScript$", "modulescript" },
	{ "Script$", "script" },
	{ "Service$", "service" },
	{ "Gui$", "gui" },
	{ "Button$", "button" },
	{ "^Text", "text" },
	{ "^Image", "image" },
	{ "^UI", "layout" },
	{ "Frame$", "frame" },
	{ "Light$", "light" },
	{ "Sound", "sound" },
	{ "Effect$", "effect" },
	{ "Constraint$", "constraint" },
	{ "Weld", "constraint" },
	{ "^Body", "constraint" },
	{ "Mesh", "mesh" },
	{ "Part$", "part" },
	{ "Operation$", "part" },
	{ "Model$", "model" },
	{ "Anim", "animation" },
	{ "Humanoid", "humanoid" },
	{ "Adornment$", "gui" },
}

function Classes.category(className: string): string
	local known = categoryOf[className]
	if known then
		return known
	end
	for _, rule in PATTERNS do
		if className:find(rule[1]) then
			categoryOf[className] = rule[2]
			return rule[2]
		end
	end
	categoryOf[className] = "unknown"
	return "unknown"
end

local added = {} -- class -> owner

-- Adds (or re-categorizes) a class; pickers pick it up on their next open.
function Classes.add(className: string, category: string?, opts: { [string]: any }?)
	assert(type(className) == "string" and className:match("^[%a_][%w_]*$"), "a class name is letters, digits and _")
	opts = opts or {}
	category = category or Classes.category(className)
	if not table.find(all, className) then
		table.insert(all, className)
		table.sort(all)
		added[className] = (opts :: any).Owner or "core"
	end
	categoryOf[className] = category :: string
	if (opts :: any).Creatable and not creatable[className] then
		creatable[className] = true
		table.insert(creatableList, className)
		table.sort(creatableList)
	end
	Categories.Version += 1
end

function Classes.removeOwner(owner: string): number
	local count = 0
	for className, who in table.clone(added) do
		if who == owner then
			added[className] = nil
			categoryOf[className] = nil
			creatable[className] = nil
			for _, list in { all, creatableList } do
				local index = table.find(list, className)
				if index then
					table.remove(list, index)
				end
			end
			count += 1
		end
	end
	count += Categories.removeOwner(owner)
	if count > 0 then
		Categories.Version += 1
	end
	return count
end

function Classes.style(className: string)
	return Categories.class(Classes.category(className))
end

function Classes.list(): { string }
	return table.clone(all)
end

function Classes.creatable(): { string }
	return table.clone(creatableList)
end

function Classes.isCreatable(className: string): boolean
	return creatable[className] == true
end

return Classes
