local env = (getgenv and getgenv()) or _G
for _, k in ipairs({ "ForgottenUnload", "CheatMenuUnload" }) do
	if env[k] then
		pcall(env[k])
		env[k] = nil
	end
end

if not game:IsLoaded() then game.Loaded:Wait() end

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local TeleportService = game:GetService("TeleportService")
local VirtualUser = game:GetService("VirtualUser")
local ContextActionService = game:GetService("ContextActionService")
local ContentProvider = game:GetService("ContentProvider")
local GuiService = game:GetService("GuiService")
local StarterGui = game:GetService("StarterGui")

local okVIM, VIM = pcall(game.GetService, game, "VirtualInputManager")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
while not camera do
	task.wait()
	camera = workspace.CurrentCamera
end
local mouse = player:GetMouse()

-- KEYBINDS (values are KeyCode names, "None" = unbound)
local BindDefaults = {
	Menu = "RightShift", Fly = "F", Noclip = "N", Aimbot = "V",
	Speed = "None", ESP = "None", Freecam = "None",
	BigHitbox = "None", AutoClick = "None", NoStun = "None", HideGui = "None",
	Zoom = "C", ClickTP = "LeftControl", FlyBoost = "LeftShift",
	Jump = "None", Invis = "None",
	RecToggle = "None", PlayToggle = "None",
}
local Binds = {}
for k, v in pairs(BindDefaults) do Binds[k] = v end

local BindList = {
	{ "Menu", "Toggle menu" }, { "Fly", "Fly" }, { "Noclip", "Noclip" }, { "Aimbot", "Aimbot" },
	{ "Speed", "Speed" }, { "ESP", "ESP" }, { "Freecam", "Freecam" },
	{ "BigHitbox", "Big hitbox" }, { "AutoClick", "Auto click" }, { "NoStun", "No stun" },
	{ "HideGui", "Hide GUI" },
	{ "Jump", "High jump (jump power)" },
	{ "Invis", "Invisibility" },
	{ "Zoom", "Zoom (hold)" }, { "ClickTP", "Click teleport key" }, { "FlyBoost", "Fly boost (hold)" },
	{ "RecToggle", "Record start/stop" }, { "PlayToggle", "Replay start/stop" },
}

-- bind id -> menu toggle it flips
local ToggleBinds = {
	{ id = "Fly", toggle = "Fly" }, { id = "Noclip", toggle = "Noclip" }, { id = "Aimbot", toggle = "Aim" },
	{ id = "Speed", toggle = "Speed" }, { id = "ESP", toggle = "ESP" }, { id = "Freecam", toggle = "Freecam" },
	{ id = "BigHitbox", toggle = "BigHitbox" }, { id = "AutoClick", toggle = "AutoClick" }, { id = "NoStun", toggle = "NoStun" },
	{ id = "HideGui", toggle = "HideGui" }, { id = "Jump", toggle = "Jump" }, { id = "Invis", toggle = "Invis" },
}

local function toKey(name)
	if type(name) == "string" and name ~= "None" then
		local ok, k = pcall(function() return Enum.KeyCode[name] end)
		if ok then return k end
	end
end

local captureFn, captureReset

local Theme = {
	Bg = Color3.fromRGB(11, 11, 14),
	Panel = Color3.fromRGB(16, 16, 20),
	Item = Color3.fromRGB(22, 22, 27),
	ItemHover = Color3.fromRGB(29, 29, 35),
	Stroke = Color3.fromRGB(40, 40, 49),
	Off = Color3.fromRGB(52, 52, 63),
	Text = Color3.fromRGB(226, 226, 235),
	SubText = Color3.fromRGB(124, 124, 142),
	Accent = Color3.fromRGB(116, 128, 232),
}

local connections = {}
local orders = {}
local registry = {}
local toggles = {}
local loading = true
local dirty = false
local canSave = true -- false if the settings could not be loaded (so defaults never overwrite them)
local saveRemote

local function changed()
	if not loading then dirty = true end
end

local function connect(signal, fn)
	local c = signal:Connect(fn)
	table.insert(connections, c)
	return c
end

-- everything created with the accent color is remembered, so the accent can be changed live
local accentTracked = {}

local function sameColor(a, b)
	return math.abs(a.R - b.R) < 0.004 and math.abs(a.G - b.G) < 0.004 and math.abs(a.B - b.B) < 0.004
end

local function new(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props) do
		o[k] = v
		if typeof(v) == "Color3" and sameColor(v, Theme.Accent) then
			table.insert(accentTracked, { o = o, p = k })
		end
	end
	o.Parent = parent
	return o
end

local function applyAccent(c)
	local old = Theme.Accent
	if sameColor(old, c) then return end
	Theme.Accent = c
	for i = #accentTracked, 1, -1 do
		local e = accentTracked[i]
		if not e.o.Parent then
			table.remove(accentTracked, i)
		else
			local ok, cur = pcall(function() return e.o[e.p] end)
			if ok and typeof(cur) == "Color3" and sameColor(cur, old) then e.o[e.p] = c end
		end
	end
end

local function corner(o, r)
	return new("UICorner", { CornerRadius = UDim.new(0, r) }, o)
end

local function outline(o)
	return new("UIStroke", { Color = Theme.Stroke, Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, o)
end

local function nextOrder(parent)
	orders[parent] = (orders[parent] or 0) + 1
	return orders[parent]
end

local function isPointer(input)
	return input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch
end

local function isMove(input)
	return input.UserInputType == Enum.UserInputType.MouseMovement
		or input.UserInputType == Enum.UserInputType.Touch
end

local function tween(o, t, props)
	TweenService:Create(o, TweenInfo.new(t, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props):Play()
end

local State = {
	Speed = false, SpeedValue = 50, SpeedMode = "Both",
	Jump = false, JumpValue = 90,
	InfJump = false, Bhop = false,
	Fly = false, FlySpeed = 80, FlyThrough = false,
	Noclip = false,
	Spin = false, SpinSpeed = 20,
	AntiVoid = false,
	ClickTP = false,
	AntiAFK = true,
	Invis = false, InvisValue = 60,

	Aim = false, AimHold = true, AimFOV = 160, AimSmooth = 30, AimPred = 0,
	AimPart = "Head", AimWall = true, AimNPC = true, AimSkipFriends = false,
	Trigger = false,
	BigHitbox = false, BigHitboxSize = 90,
	AutoClick = false, ClickCPS = 10, NoStun = false,

	ESP = false, ESPChams = true, ESPBox = true, ESPName = true, ESPTracer = false, ESPDist = 1000, ESPNPC = true,
	ESPWall = true,
	Radar = false, RadarRange = 150,
	Crosshair = false, Info = false,
	StatsHud = false, HudLock = false,
	Cursor = false, CursorSize = 32, CursorId = "", CursorAnchor = "Center",

	-- world object ESP (Chest + Halloween), each with its own distance and wall switch
	ChestESP = false, ChestDist = 500, ChestWall = true, ChestHideOpened = true,
	PumpkinESP = false, PumpkinDist = 500, PumpkinWall = true,
	PatchESP = false, PatchDist = 500, PatchWall = true,
	DoorESP = false, DoorDist = 500, DoorWall = true,

	-- auto farm (Halloween)
	FarmPumpkin = false, FarmPatch = false, FarmSpeed = 120, FarmRange = 5000,
	FarmStay = 3, FarmCool = 30, FarmCPS = 8, FarmLook = true, FarmSkipHidden = false,
	FarmTween = false, FarmBypass = false, FarmNPC = false, FarmNPCRange = 250, FarmNPCHeight = 6,
	FarmNPCName = "lantern", FarmEquip = true,
	AutoJump = false,

	TitleHide = false,

	BgGrad = false, BgAngle = 45, BgMid = 50, BgSoft = 100,

	RecLoop = true, RecCam = true, RecStart = true, RecKeys = true, RecSpeed = 100, RecPause = 1,

	FOV = math.clamp(math.floor(camera.FieldOfView + 0.5), 30, 120),
	Zoom = false, ZoomFOV = 25,
	ZoomUnlock = false,
	HideGui = false,
	Freecam = false, FreecamSpeed = 60,
	Fullbright = false, NoFog = false, NoPostFX = false,
	TimeOn = false, Time = 14,
	GravityOn = false, GravityValue = 60,
	WalkWater = false, WalkAir = false, NoShake = false,

	FxCC = false, FxSat = 0, FxCon = 0, FxBri = 0,
	FxBloom = false, FxBloomI = 100, FxBloomS = 24,
	FxAmb = false, FxFog = false,

	BgImg = false, BgImgId = "", BgImgOpacity = 60, BgImgFit = "Crop", PanelAlpha = 0,
	MenuFont = "Gotham", GameFont = "Default",
	MusicIds = "", MusicVol = 50, MusicSpeed = 100, MusicRepeat = "Off", MusicShuffle = false,
}

-- VFX settings: one block per effect type (Par = particles, Tr = trails, Be = beams,
-- Mi = fire / smoke / sparkles / explosions, Li = lights)
for _, k in ipairs({ "Par", "Tr", "Be", "Mi", "Li" }) do
	State["Vfx" .. k .. "Mode"] = "Game"
	State["Vfx" .. k .. "Amt"] = 100
	State["Vfx" .. k .. "Size"] = 100
	State["Vfx" .. k .. "Rec"] = "Off"
	State["Vfx" .. k .. "Boost"] = 0
end

-- ESP / radar colors (changed from the Visuals tab)
local espColors = {
	Player = Color3.fromRGB(232, 96, 110),
	NPC = Color3.fromRGB(222, 176, 80),
	Friend = Color3.fromRGB(90, 170, 255),
	Chest = Color3.fromRGB(255, 214, 64),
	Pumpkin = Color3.fromRGB(255, 140, 30),
	Patch = Color3.fromRGB(255, 170, 70),
	Door = Color3.fromRGB(176, 96, 255),
}

local Defaults = { WalkSpeed = 16, JumpPower = 50 }

-- shared helpers of the newer features (cleanup functions run on unload)
local Ext = {
	cleanup = {},
	fxColors = {
		Tint = Color3.new(1, 1, 1),
		Amb = Color3.fromRGB(128, 128, 128),
		Fog = Color3.fromRGB(192, 192, 192),
	},
	vfxColors = {
		Par = Color3.fromRGB(255, 140, 30), Tr = Color3.fromRGB(255, 140, 30), Be = Color3.fromRGB(255, 140, 30),
		Mi = Color3.fromRGB(255, 140, 30), Li = Color3.fromRGB(255, 220, 160),
	},
	posErr = Vector2.zero, -- difference between where a Position is set and where it really appears
	title = {},
	noSave = {
		Freecam = true, ["Hide GUI"] = true,
		["Auto Farm Pumpkin [ Tween ]"] = true, ["Auto Farm Pumpkin [ Bypass ]"] = true,
		["Auto Farm Pumpkin NPCs"] = true, ["Auto farm PumpkinPatch"] = true,
	},
	Farm = { active = false, black = setmetatable({}, { __mode = "k" }), nearT = 0, clickAcc = 0 },
}
local running = true
local zoomHeld = false
local fps = 60
local targetCache = {}
local groundTools = {}
local clickHeld = false
local clickUntil = 0

local function getHumanoid()
	local c = player.Character
	return c and c:FindFirstChildOfClass("Humanoid")
end

local function getRoot()
	local c = player.Character
	return c and c:FindFirstChild("HumanoidRootPart")
end

local isFriend
do -- BLOCK
local friendCache = {}
function isFriend(plr)
	local c = friendCache[plr.UserId]
	if c == nil then
		friendCache[plr.UserId] = false
		task.spawn(function()
			local ok, res = pcall(player.IsFriendsWith, player, plr.UserId)
			friendCache[plr.UserId] = (ok and res) and true or false
		end)
		return false
	end
	return c
end
end -- BLOCK

local function espColor(t)
	if t.friend then return espColors.Friend end
	if t.isNPC then return espColors.NPC end
	return espColors.Player
end

-- NO STUN helpers
local STUN_WORDS = { "stun", "ragdoll", "freez", "frozen", "paraly", "dizzy", "sleep", "immobil", "cantmove", "nomove" }
local function isStun(n)
	n = string.lower(n)
	for _, w in ipairs(STUN_WORDS) do
		if string.find(n, w, 1, true) then return true end
	end
	return false
end

local function noStunStates(on)
	local hum = getHumanoid()
	if not hum then return end
	pcall(function()
		hum:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, not on)
		hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, not on)
		if on then
			hum:SetStateEnabled(Enum.HumanoidStateType.GettingUp, true)
			hum:SetStateEnabled(Enum.HumanoidStateType.Running, true)
			hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
			hum:SetStateEnabled(Enum.HumanoidStateType.Freefall, true)
		end
	end)
end

-- ROOT GUI
local gui = new("ScreenGui", {
	Name = "ForgottenScript",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	DisplayOrder = 100,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
})
do -- BLOCK
if syn and syn.protect_gui then pcall(syn.protect_gui, gui) end
local ok = pcall(function()
	if gethui then
		gui.Parent = gethui()
	else
		gui.Parent = game:GetService("CoreGui")
	end
end)
if not ok or not gui.Parent then
	gui.Parent = player:WaitForChild("PlayerGui")
end
end -- BLOCK

-- real size of the screen in the same coordinates as the menu
function Ext.screen()
	local s = gui.AbsoluteSize
	if s.X < 50 or s.Y < 50 then s = camera.ViewportSize end
	return s
end

local overlay = new("Frame", {
	Name = "Overlay",
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	Active = false,
	ZIndex = 0,
}, gui)

local fovCircle = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	BackgroundTransparency = 1,
	Size = UDim2.fromOffset(320, 320),
	Visible = false,
}, overlay)
new("UICorner", { CornerRadius = UDim.new(1, 0) }, fovCircle)
local fovStroke = new("UIStroke", { Thickness = 1.5, Color = Theme.Accent, Transparency = 0.25 }, fovCircle)

local clickRing = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	BackgroundTransparency = 1,
	Size = UDim2.fromOffset(180, 180),
	Visible = false,
}, overlay)
new("UICorner", { CornerRadius = UDim.new(1, 0) }, clickRing)
new("UIStroke", { Thickness = 1.5, Color = Color3.fromRGB(222, 176, 80), Transparency = 0.35 }, clickRing)

local crosshair = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(26, 26),
	BackgroundTransparency = 1,
	Visible = false,
}, overlay)
for _, d in ipairs({
	{ UDim2.fromOffset(12, 0), UDim2.fromOffset(2, 8) },
	{ UDim2.fromOffset(12, 18), UDim2.fromOffset(2, 8) },
	{ UDim2.fromOffset(0, 12), UDim2.fromOffset(8, 2) },
	{ UDim2.fromOffset(18, 12), UDim2.fromOffset(8, 2) },
}) do
	new("Frame", { Position = d[1], Size = d[2], BackgroundColor3 = Theme.Accent, BorderSizePixel = 0 }, crosshair)
end

local infoLabel = new("TextLabel", {
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -12, 0, 12),
	Size = UDim2.fromOffset(250, 26),
	BackgroundColor3 = Theme.Panel,
	BackgroundTransparency = 0.1,
	Text = "",
	Font = Enum.Font.GothamMedium,
	TextSize = 12,
	TextColor3 = Theme.Text,
	Visible = false,
}, overlay)
corner(infoLabel, 8)
outline(infoLabel)

local statsFrame = new("TextLabel", {
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -12, 0, 46),
	Size = UDim2.fromOffset(250, 112),
	BackgroundColor3 = Theme.Panel,
	BackgroundTransparency = 0.1,
	Text = "",
	TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Top,
	Font = Enum.Font.GothamMedium,
	TextSize = 12,
	TextColor3 = Theme.Text,
	Visible = false,
}, overlay)
corner(statsFrame, 8)
outline(statsFrame)
new("UIPadding", {
	PaddingTop = UDim.new(0, 8), PaddingLeft = UDim.new(0, 10),
	PaddingRight = UDim.new(0, 10), PaddingBottom = UDim.new(0, 8),
}, statsFrame)

local RADAR_R = 75
local radar = new("Frame", {
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.new(0, 16, 1, -16),
	Size = UDim2.fromOffset(RADAR_R * 2, RADAR_R * 2),
	BackgroundColor3 = Theme.Panel,
	BackgroundTransparency = 0.15,
	Visible = false,
}, overlay)
new("UICorner", { CornerRadius = UDim.new(1, 0) }, radar)
new("UIStroke", { Color = Theme.Stroke, Thickness = 1.5 }, radar)
new("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0), Size = UDim2.new(0, 1, 1, 0), BackgroundColor3 = Theme.Stroke, BorderSizePixel = 0 }, radar)
new("Frame", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromScale(0, 0.5), Size = UDim2.new(1, 0, 0, 1), BackgroundColor3 = Theme.Stroke, BorderSizePixel = 0 }, radar)
do -- BLOCK
local radarSelf = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(7, 7),
	BackgroundColor3 = Theme.Accent,
	BorderSizePixel = 0,
}, radar)
new("UICorner", { CornerRadius = UDim.new(1, 0) }, radarSelf)
end -- BLOCK

-- WINDOW
local TITLE_H = 40
local MIN_SIZE = Vector2.new(460, 300)
local MAX_SIZE = Vector2.new(860, 600)

local main = new("Frame", {
	Name = "Main",
	Size = UDim2.fromOffset(600, 400),
	Position = UDim2.new(0.5, -300, 0.5, -200),
	BackgroundColor3 = Theme.Bg,
	BorderSizePixel = 0,
	ClipsDescendants = true,
	Active = true,
}, gui)
corner(main, 10)
new("UIStroke", { Color = Theme.Stroke, Thickness = 1.5 }, main)
local bgGrad = new("UIGradient", { Enabled = false }, main)

local titleBar = new("Frame", {
	Size = UDim2.new(1, 0, 0, TITLE_H),
	BackgroundTransparency = 1,
}, main)
new("Frame", {
	Position = UDim2.new(0, 0, 1, -1),
	Size = UDim2.new(1, 0, 0, 1),
	BackgroundColor3 = Theme.Stroke,
	BorderSizePixel = 0,
}, titleBar)

do -- BLOCK
local titleDot = new("Frame", {
	Position = UDim2.fromOffset(16, 16),
	Size = UDim2.fromOffset(8, 8),
	BackgroundColor3 = Theme.Accent,
	BorderSizePixel = 0,
}, titleBar)
new("UICorner", { CornerRadius = UDim.new(1, 0) }, titleDot)

local titleLabel = new("TextLabel", {
	BackgroundTransparency = 1,
	Position = UDim2.fromOffset(32, 0),
	Size = UDim2.new(1, -110, 1, 0),
	Text = "Forgotten Script",
	TextXAlignment = Enum.TextXAlignment.Left,
	Font = Enum.Font.GothamBold,
	TextSize = 14,
	TextColor3 = Theme.Text,
}, titleBar)
Ext.title.dot, Ext.title.label = titleDot, titleLabel
end -- BLOCK

local function titleButton(text, offsetFromRight)
	local b = new("TextButton", {
		Size = UDim2.fromOffset(28, 26),
		Position = UDim2.new(1, offsetFromRight, 0.5, -13),
		BackgroundColor3 = Theme.Item,
		BackgroundTransparency = 1,
		Text = text,
		Font = Enum.Font.GothamBold,
		TextSize = 15,
		TextColor3 = Theme.SubText,
		AutoButtonColor = false,
	}, titleBar)
	corner(b, 6)
	b.MouseEnter:Connect(function() tween(b, 0.12, { BackgroundTransparency = 0, TextColor3 = Theme.Text }) end)
	b.MouseLeave:Connect(function() tween(b, 0.12, { BackgroundTransparency = 1, TextColor3 = Theme.SubText }) end)
	return b
end
local minBtn = titleButton("-", -68)
local closeBtn = titleButton("×", -36)

local content = new("Frame", {
	Position = UDim2.fromOffset(0, TITLE_H),
	Size = UDim2.new(1, 0, 1, -TITLE_H),
	BackgroundTransparency = 1,
}, main)

local sidebar = new("ScrollingFrame", {
	Size = UDim2.new(0, 132, 1, 0),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ScrollBarThickness = 0,
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	CanvasSize = UDim2.new(),
}, content)
new("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder }, sidebar)
new("UIPadding", {
	PaddingTop = UDim.new(0, 10), PaddingLeft = UDim.new(0, 8),
	PaddingRight = UDim.new(0, 8), PaddingBottom = UDim.new(0, 10),
}, sidebar)
new("Frame", {
	Position = UDim2.fromOffset(132, 0),
	Size = UDim2.new(0, 1, 1, 0),
	BackgroundColor3 = Theme.Stroke,
	BorderSizePixel = 0,
}, content)

local pagesHolder = new("Frame", {
	Position = UDim2.fromOffset(146, 10),
	Size = UDim2.new(1, -156, 1, -20),
	BackgroundTransparency = 1,
}, content)

local resizeHandle = new("TextButton", {
	Size = UDim2.fromOffset(20, 20),
	AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.new(1, -2, 1, -2),
	BackgroundTransparency = 1,
	Text = "",
	ZIndex = 10,
}, main)
for _, l in ipairs({ { 17, 12 }, { 8, 15 } }) do
	new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(l[2], l[2]),
		Size = UDim2.fromOffset(l[1], 1),
		Rotation = -45,
		BackgroundColor3 = Theme.Off,
		BorderSizePixel = 0,
		ZIndex = 10,
	}, resizeHandle)
end

-- NOTIFICATIONS
local notify
do -- BLOCK
local notifyHolder = new("Frame", {
	AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.new(1, -14, 1, -14),
	Size = UDim2.fromOffset(250, 300),
	BackgroundTransparency = 1,
}, gui)
new("UIListLayout", {
	Padding = UDim.new(0, 6),
	VerticalAlignment = Enum.VerticalAlignment.Bottom,
	HorizontalAlignment = Enum.HorizontalAlignment.Right,
	SortOrder = Enum.SortOrder.LayoutOrder,
}, notifyHolder)

function notify(text, duration)
	local f = new("Frame", {
		Size = UDim2.fromOffset(240, 34),
		BackgroundColor3 = Theme.Panel,
		BorderSizePixel = 0,
	}, notifyHolder)
	corner(f, 8)
	local st = new("UIStroke", { Color = Theme.Stroke, Thickness = 1 }, f)
	local bar = new("Frame", {
		Size = UDim2.new(0, 3, 1, -12),
		Position = UDim2.fromOffset(6, 6),
		BackgroundColor3 = Theme.Accent,
		BorderSizePixel = 0,
	}, f)
	local lbl = new("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(18, 0),
		Size = UDim2.new(1, -24, 1, 0),
		Text = text,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Font = Enum.Font.GothamMedium,
		TextSize = 13,
		TextColor3 = Theme.Text,
	}, f)
	task.delay(duration or 2, function()
		if not f.Parent then return end
		tween(f, 0.4, { BackgroundTransparency = 1 })
		tween(lbl, 0.4, { TextTransparency = 1 })
		tween(bar, 0.4, { BackgroundTransparency = 1 })
		tween(st, 0.4, { Transparency = 1 })
		task.wait(0.45)
		f:Destroy()
	end)
end
end -- BLOCK

-- CUSTOM CURSOR
local originalMouseIcon = UIS.MouseIconEnabled
local cursor, applyCursor
do -- BLOCK
local cursorToken = 0

cursor = new("ImageLabel", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Size = UDim2.fromOffset(32, 32),
	BackgroundTransparency = 1,
	Image = "",
	ScaleType = Enum.ScaleType.Fit,
	ZIndex = 1000,
	Visible = false,
}, gui)
local cursorDot = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(8, 8),
	BackgroundColor3 = Color3.new(1, 1, 1),
	BorderSizePixel = 0,
	ZIndex = 1001,
}, cursor)
new("UICorner", { CornerRadius = UDim.new(1, 0) }, cursorDot)
new("UIStroke", { Color = Color3.new(0, 0, 0), Thickness = 1 }, cursorDot)

function applyCursor(reload)
	cursor.Size = UDim2.fromOffset(State.CursorSize, State.CursorSize)
	cursor.AnchorPoint = State.CursorAnchor == "Center" and Vector2.new(0.5, 0.5) or Vector2.zero
	cursor.Visible = State.Cursor
	UIS.MouseIconEnabled = not State.Cursor and originalMouseIcon
	if not reload then return end

	cursorToken += 1
	local token = cursorToken
	local id = State.CursorId:gsub("%D", "")
	cursor.Image = ""
	cursorDot.Visible = true
	if id == "" then return end

	task.spawn(function()
		for _, src in ipairs({ "rbxassetid://" .. id, "rbxthumb://type=Asset&id=" .. id .. "&w=420&h=420" }) do
			cursor.Image = src
			pcall(function() ContentProvider:PreloadAsync({ cursor }) end)
			if token ~= cursorToken then return end
			if cursor.IsLoaded then
				cursorDot.Visible = false
				return
			end
		end
		cursor.Image = ""
		notify("Cursor image failed to load. Check the ID", 3)
	end)
end
end -- BLOCK

-- DRAG / RESIZE / MINIMIZE
local function pointerPos(input)
	if input.UserInputType == Enum.UserInputType.Touch then
		return Vector2.new(input.Position.X, input.Position.Y)
	end
	return UIS:GetMouseLocation()
end

-- onStart may return false to cancel the drag
local function makeDrag(handle, onStart, onMove, onEnd)
	local dragging, startPos, touch = false, Vector2.zero, nil
	handle.InputBegan:Connect(function(input)
		if not isPointer(input) or dragging then return end
		if onStart() == false then return end
		dragging = true
		touch = input.UserInputType == Enum.UserInputType.Touch and input or nil
		startPos = pointerPos(input)
	end)
	connect(UIS.InputChanged, function(input)
		if not dragging then return end
		if (touch and input == touch) or (not touch and input.UserInputType == Enum.UserInputType.MouseMovement) then
			onMove(pointerPos(input) - startPos)
		end
	end)
	connect(UIS.InputEnded, function(input)
		if not dragging then return end
		if (touch and input == touch) or (not touch and input.UserInputType == Enum.UserInputType.MouseButton1) then
			dragging = false
			touch = nil
			if onEnd then onEnd() end
		end
	end)
end

-- WINDOW POSITION (smooth). winPos = where the window really is on screen, winTarget = where
-- it is going. After start the real offset between Position and the screen is measured once
-- (posErr), so grabbing the window never makes it jump. The window can never leave the screen.
do -- BLOCK
local winPos, winTarget, winReady, winDragging, winStart = nil, nil, false, false, Vector2.zero
local pendWin

local function clampWin(v)
	local sz, vp = main.AbsoluteSize, Ext.screen()
	return Vector2.new(
		math.clamp(v.X, 90 - sz.X, vp.X - 90),
		math.clamp(v.Y, 0, math.max(vp.Y - TITLE_H, 0))
	)
end

local function placeMain()
	local e = Ext.posErr
	main.Position = UDim2.fromOffset(winPos.X - e.X, winPos.Y - e.Y)
end

function Ext.setWinPos(v)
	if not winReady then
		pendWin = v
		return
	end
	winPos = clampWin(v)
	winTarget = winPos
	placeMain()
end
function Ext.getWinPos()
	return winPos or main.AbsolutePosition
end
function Ext.clampWindow()
	if winReady and not winDragging then
		winTarget = clampWin(winTarget)
	end
end

-- measure the real offset once, a few frames after start
task.spawn(function()
	for _ = 1, 3 do RunService.RenderStepped:Wait() end
	local a = main.AbsolutePosition
	main.Position = UDim2.fromOffset(a.X, a.Y)
	for _ = 1, 3 do RunService.RenderStepped:Wait() end
	Ext.posErr = main.AbsolutePosition - a
	winPos = clampWin(a)
	winTarget = winPos
	placeMain()
	winReady = true
	if Ext.reapplyHud then Ext.reapplyHud() end
	if pendWin then Ext.setWinPos(pendWin) end
end)

connect(RunService.RenderStepped, function(dt)
	if not winReady then return end
	if not winDragging then winTarget = clampWin(winTarget) end
	local d = winTarget - winPos
	if d.Magnitude > 0.25 then
		winPos = winPos:Lerp(winTarget, 1 - math.exp(-dt * 26))
		placeMain()
	elseif d.Magnitude > 0 then
		winPos = winTarget
		placeMain()
	end
end)

makeDrag(titleBar, function()
	if not winReady then return false end
	winDragging = true
	winStart = winTarget
end, function(d)
	winTarget = clampWin(winStart + d)
end, function()
	winDragging = false
	changed()
end)

local sizeStart
makeDrag(resizeHandle, function()
	sizeStart = main.AbsoluteSize
end, function(d)
	main.Size = UDim2.fromOffset(
		math.clamp(sizeStart.X + d.X, MIN_SIZE.X, MAX_SIZE.X),
		math.clamp(sizeStart.Y + d.Y, MIN_SIZE.Y, MAX_SIZE.Y)
	)
end, changed)
end -- BLOCK

-- DRAGGABLE ON-SCREEN PANELS (radar, FPS panel, server stats, menu button)
local makeHud, resetHud
do -- BLOCK
local hudPanels = {}

local function applyHud(p)
	if not p.pos then
		p.frame.AnchorPoint = p.anchor
		p.frame.Position = p.default
		return
	end
	local vp = Ext.screen()
	local e = Ext.posErr
	local x = math.clamp(p.pos.X * vp.X, 0, math.max(vp.X - p.size.X, 0))
	local y = math.clamp(p.pos.Y * vp.Y, 0, math.max(vp.Y - p.size.Y, 0))
	p.frame.AnchorPoint = Vector2.zero
	p.frame.Position = UDim2.fromOffset(x - e.X, y - e.Y)
end

function Ext.reapplyHud()
	for _, p in pairs(hudPanels) do applyHud(p) end
end

function makeHud(frame, id, size)
	local p = { frame = frame, size = size, anchor = frame.AnchorPoint, default = frame.Position, moved = false }
	hudPanels[id] = p
	frame.Active = true

	local startAbs
	makeDrag(frame, function()
		if State.HudLock then return false end
		p.moved = false
		startAbs = frame.AbsolutePosition
	end, function(d)
		if d.Magnitude > 4 then p.moved = true end
		local vp = Ext.screen()
		local x = math.clamp(startAbs.X + d.X, 0, math.max(vp.X - size.X, 0))
		local y = math.clamp(startAbs.Y + d.Y, 0, math.max(vp.Y - size.Y, 0))
		p.pos = Vector2.new(x / vp.X, y / vp.Y)
		applyHud(p)
	end, changed)

	registry["HUD " .. id .. " X"] = {
		get = function() return p.pos and p.pos.X or -1 end,
		set = function(v)
			if v < 0 then p.pos = nil else p.pos = Vector2.new(v, p.pos and p.pos.Y or 0) end
			applyHud(p)
		end,
	}
	registry["HUD " .. id .. " Y"] = {
		get = function() return p.pos and p.pos.Y or -1 end,
		set = function(v)
			if v >= 0 then
				p.pos = Vector2.new(p.pos and p.pos.X or 0, v)
				applyHud(p)
			end
		end,
	}
	return p
end

makeHud(infoLabel, "info", Vector2.new(250, 26))
makeHud(statsFrame, "stats", Vector2.new(250, 112))
makeHud(radar, "radar", Vector2.new(RADAR_R * 2, RADAR_R * 2))

function resetHud()
	for _, p in pairs(hudPanels) do
		p.pos = nil
		applyHud(p)
	end
	changed()
end
end -- BLOCK

local minimized = false
do -- BLOCK
local savedSize = main.Size
local function setMinimized(v)
	if v == minimized then return end
	minimized = v
	if v then
		if main.Size.Y.Offset > TITLE_H + 5 then
			savedSize = UDim2.fromOffset(main.Size.X.Offset, main.Size.Y.Offset)
		end
		content.Visible = false
		resizeHandle.Visible = false
		minBtn.Text = "+"
		tween(main, 0.2, { Size = UDim2.fromOffset(savedSize.X.Offset, TITLE_H) })
	else
		minBtn.Text = "-"
		tween(main, 0.2, { Size = savedSize })
		task.delay(0.18, function()
			if not minimized then
				content.Visible = true
				resizeHandle.Visible = true
			end
		end)
	end
end
minBtn.MouseButton1Click:Connect(function()
	setMinimized(not minimized)
	changed()
end)

local wantW, wantH = 600, 400
local winX, winY

local function setWinSize(w, h)
	w = math.clamp(w, MIN_SIZE.X, MAX_SIZE.X)
	h = math.clamp(h, MIN_SIZE.Y, MAX_SIZE.Y)
	if minimized then
		savedSize = UDim2.fromOffset(w, h)
		main.Size = UDim2.fromOffset(w, TITLE_H)
	else
		main.Size = UDim2.fromOffset(w, h)
	end
end
local function winW() return minimized and savedSize.X.Offset or main.Size.X.Offset end
local function winH() return minimized and savedSize.Y.Offset or main.Size.Y.Offset end

local function applyWinPos()
	if not (winX and winY) then return end
	local vp = Ext.screen()
	Ext.setWinPos(Vector2.new(winX * vp.X, winY * vp.Y))
end

registry["Window X"] = {
	get = function() return Ext.getWinPos().X / Ext.screen().X end,
	set = function(v) winX = v applyWinPos() end,
}
registry["Window Y"] = {
	get = function() return Ext.getWinPos().Y / Ext.screen().Y end,
	set = function(v) winY = v applyWinPos() end,
}
registry["Window W"] = { get = winW, set = function(v) wantW = v setWinSize(wantW, wantH) end }
registry["Window H"] = { get = winH, set = function(v) wantH = v setWinSize(wantW, wantH) end }
registry["Window Min"] = { get = function() return minimized end, set = function(v) setMinimized(v == true) end }
end -- BLOCK

local function setVisible(v)
	main.Visible = v
	if v then Ext.clampWindow() end
end
closeBtn.MouseButton1Click:Connect(function()
	setVisible(false)
	notify("Menu hidden. Press " .. Binds.Menu .. " to open")
end)

-- menu button (three bars). Drag it anywhere; a short click opens / closes the menu
do -- BLOCK
local opener = new("TextButton", {
	Size = UDim2.fromOffset(34, 34),
	Position = UDim2.new(0, 12, 0.5, -17),
	BackgroundColor3 = Theme.Panel,
	Text = "",
	AutoButtonColor = true,
}, gui)
corner(opener, 17)
outline(opener)
for i = 0, 2 do
	new("Frame", {
		Position = UDim2.fromOffset(9, 10 + i * 6),
		Size = UDim2.fromOffset(16, 2),
		BackgroundColor3 = Theme.Text,
		BorderSizePixel = 0,
	}, opener)
end
local openerHud = makeHud(opener, "opener", Vector2.new(34, 34))
opener.MouseButton1Click:Connect(function()
	if openerHud.moved then
		openerHud.moved = false
		return
	end
	setVisible(not main.Visible)
end)
end -- BLOCK

-- HIDE GUI
local applyHideGui
do -- BLOCK
local hideBackup = {}
local coreBackup = {}
local CORE_TYPES = {
	Enum.CoreGuiType.PlayerList, Enum.CoreGuiType.Backpack, Enum.CoreGuiType.Chat,
	Enum.CoreGuiType.Health, Enum.CoreGuiType.EmotesMenu,
}

function applyHideGui()
	local pg = player:FindFirstChildOfClass("PlayerGui")
	if State.HideGui then
		if pg then
			for _, g in ipairs(pg:GetChildren()) do
				if g:IsA("ScreenGui") and g ~= gui and hideBackup[g] == nil then
					hideBackup[g] = g.Enabled
					g.Enabled = false
				end
			end
		end
		for _, t in ipairs(CORE_TYPES) do
			if coreBackup[t] == nil then
				local ok, v = pcall(StarterGui.GetCoreGuiEnabled, StarterGui, t)
				coreBackup[t] = ok and v or false
			end
			pcall(StarterGui.SetCoreGuiEnabled, StarterGui, t, false)
		end
	else
		for g, was in pairs(hideBackup) do
			if g.Parent then g.Enabled = was end
			hideBackup[g] = nil
		end
		for t, was in pairs(coreBackup) do
			pcall(StarterGui.SetCoreGuiEnabled, StarterGui, t, was)
			coreBackup[t] = nil
		end
	end
end

local pg = player:WaitForChild("PlayerGui")
connect(pg.ChildAdded, function(c)
	if State.HideGui and c:IsA("ScreenGui") then task.defer(applyHideGui) end
end)
end -- BLOCK

-- TABS AND CONTROLS
local pages, tabButtons = {}, {}
local pageScales = {}
local tabColors = {}
local currentTab

local function selectTab(name)
	currentTab = name
	changed()
	for n, page in pairs(pages) do page.Visible = (n == name) end
	for n, t in pairs(tabButtons) do
		local active = (n == name)
		local tc = tabColors[n]
		if tc then
			tween(t.btn, 0.15, {
				BackgroundTransparency = active and 0.2 or 0.65,
				TextColor3 = active and Color3.fromRGB(255, 176, 70) or tc,
			})
		else
			tween(t.btn, 0.15, {
				BackgroundTransparency = active and 0 or 1,
				TextColor3 = active and Theme.Text or Theme.SubText,
			})
		end
		t.bar.Visible = active
	end
end

registry["Tab"] = {
	get = function() return currentTab or "Misc" end,
	set = function(n) if pages[n] then selectTab(n) end end,
}

local function createTab(name, color)
	local btn = new("TextButton", {
		Size = UDim2.new(1, 0, 0, 32),
		BackgroundColor3 = color and Color3.fromRGB(74, 36, 6) or Theme.Item,
		BackgroundTransparency = color and 0.65 or 1,
		Text = "   " .. name,
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = Enum.Font.GothamMedium,
		TextSize = 13,
		TextColor3 = color or Theme.SubText,
		AutoButtonColor = false,
		LayoutOrder = nextOrder(sidebar),
	}, sidebar)
	corner(btn, 7)
	if color then tabColors[name] = color end
	local bar = new("Frame", {
		Position = UDim2.fromOffset(0, 8),
		Size = UDim2.new(0, 3, 1, -16),
		BackgroundColor3 = color or Theme.Accent,
		BorderSizePixel = 0,
		Visible = false,
	}, btn)
	corner(bar, 2)

	local page = new("ScrollingFrame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 3,
		ScrollBarImageColor3 = Theme.Off,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		Visible = false,
	}, pagesHolder)
	new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, page)
	new("UIPadding", { PaddingRight = UDim.new(0, 8), PaddingBottom = UDim.new(0, 4) }, page)
	pageScales[name] = { page = page, scale = new("UIScale", {}, page) }

	pages[name], tabButtons[name] = page, { btn = btn, bar = bar }
	btn.MouseButton1Click:Connect(function() selectTab(name) end)
	return page
end

local function addSection(parent, text)
	return new("TextLabel", {
		Size = UDim2.new(1, 0, 0, 24),
		BackgroundTransparency = 1,
		Text = string.upper(text),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Bottom,
		Font = Enum.Font.GothamBold,
		TextSize = 11,
		TextColor3 = Theme.SubText,
		LayoutOrder = nextOrder(parent),
	}, parent)
end

local function baseRow(parent, height, class)
	local row = new(class or "Frame", {
		Size = UDim2.new(1, 0, 0, height),
		BackgroundColor3 = Theme.Item,
		BorderSizePixel = 0,
		LayoutOrder = nextOrder(parent),
	}, parent)
	corner(row, 8)
	outline(row)
	return row
end

local function addToggle(parent, text, default, callback, desc)
	local height = desc and 46 or 34
	local row = baseRow(parent, height, "TextButton")
	row.Text = ""
	row.AutoButtonColor = false
	row.MouseEnter:Connect(function() tween(row, 0.12, { BackgroundColor3 = Theme.ItemHover }) end)
	row.MouseLeave:Connect(function() tween(row, 0.12, { BackgroundColor3 = Theme.Item }) end)

	new("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(12, desc and 6 or 0),
		Size = UDim2.new(1, -68, 0, desc and 18 or height),
		Text = text,
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = Enum.Font.GothamMedium,
		TextSize = 13,
		TextColor3 = Theme.Text,
	}, row)
	if desc then
		new("TextLabel", {
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(12, 24),
			Size = UDim2.new(1, -68, 0, 14),
			Text = desc,
			TextXAlignment = Enum.TextXAlignment.Left,
			Font = Enum.Font.Gotham,
			TextSize = 11,
			TextColor3 = Theme.SubText,
		}, row)
	end

	local track = new("Frame", {
		Size = UDim2.fromOffset(36, 18),
		Position = UDim2.new(1, -48, 0.5, -9),
		BackgroundColor3 = Theme.Off,
		BorderSizePixel = 0,
	}, row)
	corner(track, 9)
	local knob = new("Frame", {
		Size = UDim2.fromOffset(12, 12),
		Position = UDim2.fromOffset(3, 3),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
	}, track)
	corner(knob, 6)

	local state = default
	local function render()
		tween(track, 0.15, { BackgroundColor3 = state and Theme.Accent or Theme.Off })
		tween(knob, 0.15, { Position = state and UDim2.fromOffset(21, 3) or UDim2.fromOffset(3, 3) })
	end

	local obj = {}
	function obj.Set(v)
		state = v
		render()
		callback(v)
		changed()
	end
	function obj.Get() return state end
	registry[text] = { get = obj.Get, set = obj.Set }

	row.MouseButton1Click:Connect(function() obj.Set(not state) end)
	render()
	if default then callback(true) end
	return obj
end

-- slider: drag the bar OR click the number on the right and type a value
local function addSlider(parent, text, min, max, default, callback, suffix)
	suffix = suffix or ""
	local row = baseRow(parent, 48)
	new("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(12, 6),
		Size = UDim2.new(1, -100, 0, 18),
		Text = text,
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = Enum.Font.GothamMedium,
		TextSize = 13,
		TextColor3 = Theme.Text,
	}, row)
	local valueBox = new("TextBox", {
		Position = UDim2.new(1, -86, 0, 4),
		Size = UDim2.fromOffset(76, 20),
		BackgroundColor3 = Theme.Bg,
		TextXAlignment = Enum.TextXAlignment.Center,
		Font = Enum.Font.GothamBold,
		TextSize = 12,
		TextColor3 = Theme.Accent,
		Text = "",
		ClearTextOnFocus = false,
		BorderSizePixel = 0,
	}, row)
	corner(valueBox, 5)
	outline(valueBox)
	local bar = new("Frame", {
		Position = UDim2.new(0, 12, 0, 34),
		Size = UDim2.new(1, -24, 0, 4),
		BackgroundColor3 = Theme.Off,
		BorderSizePixel = 0,
	}, row)
	corner(bar, 2)
	local fill = new("Frame", {
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = Theme.Accent,
		BorderSizePixel = 0,
	}, bar)
	corner(fill, 2)
	local knob = new("Frame", {
		Size = UDim2.fromOffset(12, 12),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(1, 0.5),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
	}, fill)
	corner(knob, 6)

	local value = default
	local function set(v)
		v = math.clamp(math.floor(tonumber(v) + 0.5), min, max)
		value = v
		fill.Size = UDim2.fromScale((v - min) / (max - min), 1)
		if not valueBox:IsFocused() then valueBox.Text = v .. suffix end
		callback(v)
		changed()
	end
	local function fromX(x)
		set(min + (max - min) * math.clamp((x - bar.AbsolutePosition.X) / bar.AbsoluteSize.X, 0, 1))
	end

	valueBox.Focused:Connect(function() valueBox.Text = tostring(value) end)
	valueBox.FocusLost:Connect(function()
		local txt = valueBox.Text:gsub(",", ".")
		local n = tonumber(txt:match("-?%d+%.?%d*"))
		if n then
			set(n)
		else
			valueBox.Text = value .. suffix
		end
	end)

	local hit = new("TextButton", {
		Position = UDim2.new(0, 6, 0, 24),
		Size = UDim2.new(1, -12, 0, 24),
		BackgroundTransparency = 1,
		Text = "",
	}, row)
	local dragging = false
	hit.InputBegan:Connect(function(input)
		if isPointer(input) then
			dragging = true
			fromX(input.Position.X)
			input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then dragging = false end
			end)
		end
	end)
	connect(UIS.InputChanged, function(input)
		if dragging and isMove(input) then fromX(input.Position.X) end
	end)

	registry[text] = { get = function() return value end, set = set }
	set(default)
end

local function addButton(parent, text, callback)
	local b = baseRow(parent, 34, "TextButton")
	b.Text = text
	b.Font = Enum.Font.GothamMedium
	b.TextSize = 13
	b.TextColor3 = Theme.Text
	b.AutoButtonColor = false
	b.MouseEnter:Connect(function() tween(b, 0.12, { BackgroundColor3 = Theme.ItemHover }) end)
	b.MouseLeave:Connect(function() tween(b, 0.12, { BackgroundColor3 = Theme.Item }) end)
	b.MouseButton1Click:Connect(callback)
	return b
end

local function addSegmented(parent, text, options, default, callback)
	local row = baseRow(parent, 58)
	new("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(12, 6),
		Size = UDim2.new(1, -24, 0, 18),
		Text = text,
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = Enum.Font.GothamMedium,
		TextSize = 13,
		TextColor3 = Theme.Text,
	}, row)
	local holder = new("Frame", {
		Position = UDim2.fromOffset(12, 30),
		Size = UDim2.new(1, -24, 0, 20),
		BackgroundColor3 = Theme.Bg,
		BorderSizePixel = 0,
	}, row)
	corner(holder, 6)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal }, holder)

	local buttons = {}
	local current = default
	local function select(name)
		current = name
		for n, b in pairs(buttons) do
			local active = n == name
			b.BackgroundTransparency = active and 0 or 1
			b.TextColor3 = active and Color3.new(1, 1, 1) or Theme.SubText
		end
		callback(name)
		changed()
	end

	for _, name in ipairs(options) do
		local b = new("TextButton", {
			Size = UDim2.new(1 / #options, 0, 1, 0),
			BackgroundColor3 = Theme.Accent,
			Text = name,
			Font = Enum.Font.GothamMedium,
			TextSize = 12,
			AutoButtonColor = false,
			BorderSizePixel = 0,
		}, holder)
		corner(b, 6)
		buttons[name] = b
		b.MouseButton1Click:Connect(function() select(name) end)
	end
	registry[text] = {
		get = function() return current end,
		set = function(n) if buttons[n] then select(n) end end,
	}
	select(default)
end

local function addChoice(parent, text, options, default, callback)
	local cols = 3
	local rows = math.ceil(#options / cols)
	local row = baseRow(parent, 34 + rows * 26)
	new("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(12, 6),
		Size = UDim2.new(1, -24, 0, 18),
		Text = text,
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = Enum.Font.GothamMedium,
		TextSize = 13,
		TextColor3 = Theme.Text,
	}, row)
	local holder = new("Frame", {
		Position = UDim2.fromOffset(12, 30),
		Size = UDim2.new(1, -24, 0, rows * 26),
		BackgroundTransparency = 1,
	}, row)
	new("UIGridLayout", {
		CellSize = UDim2.new(1 / cols, -4, 0, 22),
		CellPadding = UDim2.fromOffset(4, 4),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, holder)

	local buttons = {}
	local current = default
	local function select(name)
		current = name
		for n, b in pairs(buttons) do
			local active = n == name
			b.BackgroundColor3 = active and Theme.Accent or Theme.Bg
			b.TextColor3 = active and Color3.new(1, 1, 1) or Theme.SubText
		end
		callback(name)
		changed()
	end
	for i, name in ipairs(options) do
		local b = new("TextButton", {
			BackgroundColor3 = Theme.Bg,
			Text = name,
			Font = Enum.Font.GothamMedium,
			TextSize = 11,
			TextColor3 = Theme.SubText,
			AutoButtonColor = false,
			BorderSizePixel = 0,
			LayoutOrder = i,
		}, holder)
		corner(b, 6)
		buttons[name] = b
		b.MouseButton1Click:Connect(function() select(name) end)
	end
	registry[text] = {
		get = function() return current end,
		set = function(n) if buttons[n] then select(n) end end,
	}
	select(default)
end

-- collapsible block (state is saved)
local function addGroup(parent, title, startOpen, order)
	local holder = new("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = order or nextOrder(parent),
	}, parent)
	new("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, holder)

	local header = baseRow(holder, 34, "TextButton")
	header.Text = ""
	header.AutoButtonColor = false
	header.MouseEnter:Connect(function() tween(header, 0.12, { BackgroundColor3 = Theme.ItemHover }) end)
	header.MouseLeave:Connect(function() tween(header, 0.12, { BackgroundColor3 = Theme.Item }) end)

	local arrow = new("TextLabel", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(18, 17),
		Size = UDim2.fromOffset(16, 16),
		Text = ">",
		Font = Enum.Font.GothamBold,
		TextSize = 14,
		TextColor3 = Theme.SubText,
		Rotation = startOpen and 90 or 0,
	}, header)
	local label = new("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(30, 0),
		Size = UDim2.new(1, -100, 1, 0),
		Text = title,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Font = Enum.Font.GothamMedium,
		TextSize = 13,
		TextColor3 = Theme.Text,
	}, header)

	local body = new("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = 2,
		Visible = startOpen,
	}, holder)
	new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, body)
	new("UIPadding", { PaddingLeft = UDim.new(0, 10) }, body)

	local open = startOpen
	local function setOpen(v)
		open = v and true or false
		body.Visible = open
		tween(arrow, 0.15, { Rotation = open and 90 or 0 })
	end
	header.MouseButton1Click:Connect(function()
		setOpen(not open)
		changed()
	end)
	registry["Group: " .. title] = { get = function() return open end, set = setOpen }
	setOpen(startOpen)

	return { Body = body, Header = header, Label = label, Holder = holder, SetOpen = setOpen }
end

local function addInput(parent, text, default, callback, placeholder)
	local row = baseRow(parent, 34)
	new("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(12, 0),
		Size = UDim2.new(0.5, -12, 1, 0),
		Text = text,
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = Enum.Font.GothamMedium,
		TextSize = 13,
		TextColor3 = Theme.Text,
	}, row)
	local box = new("TextBox", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -8, 0.5, 0),
		Size = UDim2.new(0.5, -8, 0, 24),
		BackgroundColor3 = Theme.Bg,
		Text = default,
		PlaceholderText = placeholder or "",
		PlaceholderColor3 = Theme.SubText,
		TextColor3 = Theme.Text,
		Font = Enum.Font.GothamMedium,
		TextSize = 12,
		ClearTextOnFocus = false,
		BorderSizePixel = 0,
	}, row)
	corner(box, 6)
	outline(box)

	local function set(v)
		box.Text = tostring(v)
		callback(box.Text)
		changed()
	end
	box.FocusLost:Connect(function()
		callback(box.Text)
		changed()
	end)
	registry[text] = { get = function() return box.Text end, set = set }
	callback(default)
end

local function addInfo(parent, text)
	local row = baseRow(parent, 34)
	new("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(12, 0),
		Size = UDim2.new(0.5, -12, 1, 0),
		Text = text,
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = Enum.Font.GothamMedium,
		TextSize = 13,
		TextColor3 = Theme.Text,
	}, row)
	local v = new("TextLabel", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 0),
		Size = UDim2.new(0.5, -12, 1, 0),
		Text = "-",
		TextXAlignment = Enum.TextXAlignment.Right,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Font = Enum.Font.GothamBold,
		TextSize = 13,
		TextColor3 = Theme.Accent,
	}, row)
	return function(s) v.Text = s end
end

local addColor
do -- BLOCK
local BASIC_COLORS = {
	Color3.fromRGB(0, 0, 0), Color3.fromRGB(64, 64, 64), Color3.fromRGB(128, 128, 128),
	Color3.fromRGB(192, 192, 192), Color3.fromRGB(255, 255, 255),
	Color3.fromRGB(232, 96, 110), Color3.fromRGB(255, 0, 0), Color3.fromRGB(255, 128, 0),
	Color3.fromRGB(255, 255, 0), Color3.fromRGB(128, 255, 0),
	Color3.fromRGB(0, 255, 0), Color3.fromRGB(0, 255, 170), Color3.fromRGB(0, 255, 255),
	Color3.fromRGB(0, 128, 255), Color3.fromRGB(0, 0, 255),
	Color3.fromRGB(128, 0, 255), Color3.fromRGB(255, 0, 255), Color3.fromRGB(255, 0, 128),
	Color3.fromRGB(128, 64, 0), Color3.fromRGB(34, 22, 66),
}
local CUSTOM_SLOTS = 10

local function ptrXY(input)
	if input.UserInputType == Enum.UserInputType.Touch then
		return Vector2.new(input.Position.X, input.Position.Y + GuiService:GetGuiInset().Y)
	end
	return UIS:GetMouseLocation()
end

local function dragArea(btn, fn)
	local dragging = false
	btn.InputBegan:Connect(function(input)
		if isPointer(input) then
			dragging = true
			fn(ptrXY(input))
			input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then dragging = false end
			end)
		end
	end)
	connect(UIS.InputChanged, function(input)
		if dragging and isMove(input) then fn(ptrXY(input)) end
	end)
end

function addColor(parent, text, default, callback)
	local grp = addGroup(parent, text, false)
	local body = grp.Body
	local h, s, v = default:ToHSV()
	h, s, v = h * 360, s * 100, v * 100

	local swatch = new("Frame", {
		Size = UDim2.fromOffset(34, 16),
		Position = UDim2.new(1, -46, 0.5, -8),
		BackgroundColor3 = default,
		BorderSizePixel = 0,
	}, grp.Header)
	corner(swatch, 4)
	outline(swatch)

	local row = baseRow(body, 148)
	local sv = new("TextButton", {
		Position = UDim2.fromOffset(12, 9),
		Size = UDim2.fromOffset(150, 130),
		BackgroundColor3 = Color3.fromHSV(h / 360, 1, 1),
		Text = "",
		AutoButtonColor = false,
		BorderSizePixel = 0,
		ClipsDescendants = true,
	}, row)
	corner(sv, 4)
	local white = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0 }, sv)
	new("UIGradient", { Transparency = NumberSequence.new(0, 1) }, white)
	local black = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BorderSizePixel = 0 }, sv)
	new("UIGradient", { Rotation = 90, Transparency = NumberSequence.new(1, 0) }, black)
	local svMark = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(10, 10),
		BackgroundTransparency = 1,
		ZIndex = 3,
	}, sv)
	new("UICorner", { CornerRadius = UDim.new(1, 0) }, svMark)
	new("UIStroke", { Color = Color3.new(1, 1, 1), Thickness = 2 }, svMark)

	local hueBar = new("TextButton", {
		Position = UDim2.fromOffset(172, 9),
		Size = UDim2.fromOffset(16, 130),
		BackgroundColor3 = Color3.new(1, 1, 1),
		Text = "",
		AutoButtonColor = false,
		BorderSizePixel = 0,
	}, row)
	corner(hueBar, 4)
	new("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 0, 0)),
			ColorSequenceKeypoint.new(1 / 6, Color3.fromRGB(255, 255, 0)),
			ColorSequenceKeypoint.new(2 / 6, Color3.fromRGB(0, 255, 0)),
			ColorSequenceKeypoint.new(3 / 6, Color3.fromRGB(0, 255, 255)),
			ColorSequenceKeypoint.new(4 / 6, Color3.fromRGB(0, 0, 255)),
			ColorSequenceKeypoint.new(5 / 6, Color3.fromRGB(255, 0, 255)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 0, 0)),
		}),
	}, hueBar)
	local hueMark = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.new(1, 4, 0, 4),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		ZIndex = 3,
	}, hueBar)
	new("UIStroke", { Color = Color3.new(0, 0, 0), Thickness = 1 }, hueMark)

	local preview = new("Frame", {
		Position = UDim2.fromOffset(200, 9),
		Size = UDim2.fromOffset(64, 40),
		BackgroundColor3 = default,
		BorderSizePixel = 0,
	}, row)
	corner(preview, 6)
	outline(preview)

	local fieldsRow = baseRow(body, 50)
	local fields = {}
	local fieldDefs = { { "H", 360 }, { "S", 100 }, { "V", 100 }, { "R", 255 }, { "G", 255 }, { "B", 255 } }
	for i, def in ipairs(fieldDefs) do
		local name = def[1]
		new("TextLabel", {
			BackgroundTransparency = 1,
			Position = UDim2.new((i - 1) / 6, 0, 0, 4),
			Size = UDim2.new(1 / 6, 0, 0, 14),
			Text = name,
			Font = Enum.Font.GothamBold,
			TextSize = 11,
			TextColor3 = Theme.SubText,
		}, fieldsRow)
		fields[name] = new("TextBox", {
			Position = UDim2.new((i - 1) / 6, 3, 0, 20),
			Size = UDim2.new(1 / 6, -6, 0, 24),
			BackgroundColor3 = Theme.Bg,
			Text = "",
			TextColor3 = Theme.Text,
			Font = Enum.Font.GothamMedium,
			TextSize = 12,
			ClearTextOnFocus = false,
			BorderSizePixel = 0,
		}, fieldsRow)
		corner(fields[name], 5)
		outline(fields[name])
	end

	local hexRow = baseRow(body, 34)
	new("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(12, 0),
		Size = UDim2.new(0.5, -12, 1, 0),
		Text = "Hex code",
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = Enum.Font.GothamMedium,
		TextSize = 13,
		TextColor3 = Theme.Text,
	}, hexRow)
	local hexBox = new("TextBox", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -8, 0.5, 0),
		Size = UDim2.new(0.5, -8, 0, 24),
		BackgroundColor3 = Theme.Bg,
		Text = "",
		PlaceholderText = "#RRGGBB",
		PlaceholderColor3 = Theme.SubText,
		TextColor3 = Theme.Text,
		Font = Enum.Font.GothamMedium,
		TextSize = 12,
		ClearTextOnFocus = false,
		BorderSizePixel = 0,
	}, hexRow)
	corner(hexBox, 6)
	outline(hexBox)

	local function toHex(c)
		return string.format("#%02X%02X%02X",
			math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5))
	end

	local function refresh()
		h = math.clamp(h, 0, 360)
		s = math.clamp(s, 0, 100)
		v = math.clamp(v, 0, 100)
		local c = Color3.fromHSV(math.clamp(h / 360, 0, 1), s / 100, v / 100)
		swatch.BackgroundColor3 = c
		preview.BackgroundColor3 = c
		sv.BackgroundColor3 = Color3.fromHSV(math.clamp(h / 360, 0, 1), 1, 1)
		svMark.Position = UDim2.fromScale(s / 100, 1 - v / 100)
		hueMark.Position = UDim2.fromScale(0.5, h / 360)
		local vals = { H = h, S = s, V = v, R = c.R * 255, G = c.G * 255, B = c.B * 255 }
		for k, box in pairs(fields) do
			if not box:IsFocused() then box.Text = tostring(math.floor(vals[k] + 0.5)) end
		end
		if not hexBox:IsFocused() then hexBox.Text = toHex(c) end
		callback(c)
		changed()
	end

	local function setColor(c)
		local nh, ns, nv = c:ToHSV()
		if ns > 0 and nv > 0 then h = nh * 360 end
		s, v = ns * 100, nv * 100
		refresh()
	end

	dragArea(sv, function(p)
		s = math.clamp((p.X - sv.AbsolutePosition.X) / sv.AbsoluteSize.X, 0, 1) * 100
		v = (1 - math.clamp((p.Y - sv.AbsolutePosition.Y) / sv.AbsoluteSize.Y, 0, 1)) * 100
		refresh()
	end)
	dragArea(hueBar, function(p)
		h = math.clamp((p.Y - hueBar.AbsolutePosition.Y) / hueBar.AbsoluteSize.Y, 0, 1) * 360
		refresh()
	end)

	for name, box in pairs(fields) do
		box.FocusLost:Connect(function()
			local n = tonumber(box.Text:match("-?%d+%.?%d*"))
			if not n then
				refresh()
				return
			end
			if name == "H" then
				h = n
			elseif name == "S" then
				s = n
			elseif name == "V" then
				v = n
			else
				local c = Color3.fromHSV(math.clamp(h / 360, 0, 1), s / 100, v / 100)
				local r, g, b = math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5)
				n = math.clamp(math.floor(n + 0.5), 0, 255)
				if name == "R" then r = n elseif name == "G" then g = n else b = n end
				setColor(Color3.fromRGB(r, g, b))
				return
			end
			refresh()
		end)
	end

	hexBox.FocusLost:Connect(function()
		local hex = hexBox.Text:gsub("[^%x]", "")
		if #hex == 6 then
			setColor(Color3.fromRGB(
				tonumber(hex:sub(1, 2), 16), tonumber(hex:sub(3, 4), 16), tonumber(hex:sub(5, 6), 16)))
		else
			hexBox.Text = toHex(swatch.BackgroundColor3)
		end
	end)

	local basicRow = baseRow(body, 70)
	new("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(12, 4),
		Size = UDim2.new(1, -24, 0, 14),
		Text = "BASIC COLORS",
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = Enum.Font.GothamBold,
		TextSize = 11,
		TextColor3 = Theme.SubText,
	}, basicRow)
	local basicGrid = new("Frame", {
		Position = UDim2.fromOffset(12, 20),
		Size = UDim2.new(1, -24, 0, 42),
		BackgroundTransparency = 1,
	}, basicRow)
	new("UIGridLayout", {
		CellSize = UDim2.fromOffset(18, 18),
		CellPadding = UDim2.fromOffset(3, 3),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, basicGrid)
	for i, c in ipairs(BASIC_COLORS) do
		local b = new("TextButton", {
			BackgroundColor3 = c,
			Text = "",
			AutoButtonColor = false,
			BorderSizePixel = 0,
			LayoutOrder = i,
		}, basicGrid)
		corner(b, 3)
		outline(b)
		b.MouseButton1Click:Connect(function() setColor(c) end)
	end

	local customRow = baseRow(body, 84)
	new("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(12, 4),
		Size = UDim2.new(1, -24, 0, 14),
		Text = "CUSTOM COLORS",
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = Enum.Font.GothamBold,
		TextSize = 11,
		TextColor3 = Theme.SubText,
	}, customRow)
	local customGrid = new("Frame", {
		Position = UDim2.fromOffset(12, 20),
		Size = UDim2.new(1, -24, 0, 21),
		BackgroundTransparency = 1,
	}, customRow)
	new("UIGridLayout", {
		CellSize = UDim2.fromOffset(18, 18),
		CellPadding = UDim2.fromOffset(3, 3),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, customGrid)
	local customColors, customNext = {}, 1
	for i = 1, CUSTOM_SLOTS do
		local b = new("TextButton", {
			BackgroundColor3 = Theme.Panel,
			Text = "",
			AutoButtonColor = false,
			BorderSizePixel = 0,
			LayoutOrder = i,
		}, customGrid)
		corner(b, 3)
		outline(b)
		b.MouseButton1Click:Connect(function()
			if customColors[i] then setColor(customColors[i]) end
		end)
		customColors[i] = false
	end
	local customBtn = new("TextButton", {
		Position = UDim2.fromOffset(12, 50),
		Size = UDim2.new(1, -24, 0, 26),
		BackgroundColor3 = Theme.Panel,
		Text = "Add to custom colors",
		Font = Enum.Font.GothamMedium,
		TextSize = 12,
		TextColor3 = Theme.Text,
		AutoButtonColor = false,
		BorderSizePixel = 0,
	}, customRow)
	corner(customBtn, 6)
	outline(customBtn)
	customBtn.MouseEnter:Connect(function() tween(customBtn, 0.12, { BackgroundColor3 = Theme.ItemHover }) end)
	customBtn.MouseLeave:Connect(function() tween(customBtn, 0.12, { BackgroundColor3 = Theme.Panel }) end)
	customBtn.MouseButton1Click:Connect(function()
		local c = swatch.BackgroundColor3
		customColors[customNext] = c
		for _, b in ipairs(customGrid:GetChildren()) do
			if b:IsA("TextButton") and b.LayoutOrder == customNext then b.BackgroundColor3 = c end
		end
		customNext = customNext % CUSTOM_SLOTS + 1
	end)

	registry[text .. " hue"] = { get = function() return h end, set = function(x) h = tonumber(x) or h refresh() end }
	registry[text .. " sat"] = { get = function() return s end, set = function(x) s = tonumber(x) or s refresh() end }
	registry[text .. " val"] = { get = function() return v end, set = function(x) v = tonumber(x) or v refresh() end }

	refresh()
	return { Set = setColor }
end

end -- BLOCK

local bindSetters = {}

local function addKeybind(parent, text, store, id, default, noClear)
	local row = baseRow(parent, 34)
	new("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(12, 0),
		Size = UDim2.new(0.5, -12, 1, 0),
		Text = text,
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = Enum.Font.GothamMedium,
		TextSize = 13,
		TextColor3 = Theme.Text,
	}, row)
	local btn = new("TextButton", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -8, 0.5, 0),
		Size = UDim2.fromOffset(120, 24),
		BackgroundColor3 = Theme.Bg,
		Font = Enum.Font.GothamMedium,
		TextSize = 12,
		TextColor3 = Theme.Text,
		AutoButtonColor = false,
		BorderSizePixel = 0,
		Text = "",
	}, row)
	corner(btn, 6)
	outline(btn)

	store[id] = default
	local function render(listening)
		if listening then
			btn.Text = "Press a key..."
			btn.TextColor3 = Theme.Accent
		else
			btn.Text = store[id]
			btn.TextColor3 = store[id] == "None" and Theme.SubText or Theme.Text
		end
	end

	local function set(v)
		if v ~= "None" and not toKey(v) then v = default end
		if v == "None" and noClear then v = default end
		if store == Binds and v ~= "None" and not loading then
			for other, setter in pairs(bindSetters) do
				if other ~= id and Binds[other] == v then
					if other == "Menu" then
						notify("That key opens the menu", 2)
						render(false)
						return
					end
					setter("None")
					notify(v .. " was moved from " .. other, 2)
				end
			end
		end
		store[id] = v
		render(false)
		changed()
	end

	btn.MouseButton1Click:Connect(function()
		if captureReset then captureReset() end
		render(true)
		captureReset = function() render(false) end
		captureFn = function(k)
			captureReset = nil
			if k == Enum.KeyCode.Escape then
				render(false)
			elseif k == Enum.KeyCode.Backspace then
				set("None")
			else
				set(k.Name)
			end
		end
	end)

	if store == Binds then bindSetters[id] = set end
	registry["Key: " .. text] = { get = function() return store[id] end, set = set }
	render(false)
end

-- NOCLIP (also used by the fly-through-walls option and by the auto farm)
local noclipChanged = {}

local function restoreNoclip()
	for part in pairs(noclipChanged) do
		if part.Parent then part.CanCollide = true end
	end
	table.clear(noclipChanged)
end

function Ext.refreshNoclip()
	if not (State.Noclip or Ext.Farm.active or (State.Fly and State.FlyThrough)) then
		restoreNoclip()
	end
end

-- FLY (new: moves the character with CFrame, no body movers)
-- The flight position is tracked separately, so gravity never makes you sink, speed changes are
-- smoothed, and you lean a little in the direction you fly.
-- Move with WASD in the direction the camera looks. Space / E = up, Q / Left Ctrl = down.
local stopFly, startFly, flyTo
do -- BLOCK
local flyConn
local flyVel = Vector3.zero
local flyPos
local flyTarget
local lastFlat = Vector3.new(0, 0, -1)
local FLY_BOOST = 1.7

function stopFly()
	if flyConn then flyConn:Disconnect() flyConn = nil end
	flyVel = Vector3.zero
	flyPos = nil
	flyTarget = nil
	local hum, root = getHumanoid(), getRoot()
	if hum and not Ext.Farm.active then hum.PlatformStand = false end
	if root then
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
	end
end

function startFly()
	stopFly()
	local root, hum = getRoot(), getHumanoid()
	if not root or not hum then return end
	flyPos = root.Position
	hum.PlatformStand = true

	flyConn = RunService.Heartbeat:Connect(function(dt)
		if Ext.Farm.active then
			flyPos = nil
			return
		end
		local r, h = getRoot(), getHumanoid()
		if not r or not h or not r.Parent then return end
		if not flyPos or (r.Position - flyPos).Magnitude > 8 then flyPos = r.Position end
		h.PlatformStand = true

		local cam = camera.CFrame
		local md = h.MoveDirection
		local goal = Vector3.zero
		local usingTarget = false

		-- "fly to": straight to the target, slow down near it, cancel on manual input
		if flyTarget then
			local tp = flyTarget()
			if not tp then
				flyTarget = nil
			elseif md.Magnitude > 0.01 then
				flyTarget = nil
				notify("Flight cancelled")
			else
				local diff = tp - flyPos
				if diff.Magnitude < 5 then
					flyTarget = nil
					notify("Arrived")
				else
					goal = diff.Unit * math.min(State.FlySpeed, diff.Magnitude * 4 + 10)
					usingTarget = true
				end
			end
		end

		if not usingTarget then
			local move = Vector3.zero
			if md.Magnitude > 0.01 then
				local fl = Vector3.new(cam.LookVector.X, 0, cam.LookVector.Z)
				local fr = Vector3.new(cam.RightVector.X, 0, cam.RightVector.Z)
				if fl.Magnitude > 0.01 and fr.Magnitude > 0.01 then
					move = cam.LookVector * md:Dot(fl.Unit) + cam.RightVector * md:Dot(fr.Unit)
				else
					move = md
				end
			end
			if not UIS:GetFocusedTextBox() then
				if UIS:IsKeyDown(Enum.KeyCode.Space) or UIS:IsKeyDown(Enum.KeyCode.E) then move += Vector3.yAxis end
				if UIS:IsKeyDown(Enum.KeyCode.Q) or UIS:IsKeyDown(Enum.KeyCode.LeftControl) then move -= Vector3.yAxis end
			end
			if move.Magnitude > 1 then move = move.Unit end
			local speed = State.FlySpeed
			local bk = toKey(Binds.FlyBoost)
			if bk and UIS:IsKeyDown(bk) then speed *= FLY_BOOST end
			goal = move * speed
		end

		flyVel = flyVel:Lerp(goal, 1 - math.exp(-dt * 9))
		flyPos += flyVel * dt

		local flatV = Vector3.new(flyVel.X, 0, flyVel.Z)
		if flatV.Magnitude > 2 then
			lastFlat = flatV.Unit
		else
			local fl = Vector3.new(cam.LookVector.X, 0, cam.LookVector.Z)
			if fl.Magnitude > 0.05 then lastFlat = fl.Unit end
		end
		local tilt = math.clamp(flatV:Dot(lastFlat) / math.max(State.FlySpeed, 1), -1, 1) * 0.5
		r.CFrame = CFrame.lookAt(flyPos, flyPos + lastFlat) * CFrame.Angles(-tilt, 0, 0)
		r.AssemblyLinearVelocity = Vector3.zero
		r.AssemblyAngularVelocity = Vector3.zero
	end)
end

-- fly to a point; fn returns the current target position (or nil if it is gone)
function flyTo(fn, name)
	if not getRoot() then return end
	if not fn() then
		notify("Target not found")
		return
	end
	if not State.Fly and toggles.Fly then toggles.Fly.Set(true) end
	flyTarget = fn
	notify("Flying to " .. name)
end

end -- BLOCK

-- FREECAM
local freecam = { yaw = 0, pitch = 0, pos = Vector3.zero, rmb = false }
local freecamBound = false

local function stopFreecam()
	if not freecamBound then return end
	freecamBound = false
	freecam.rmb = false
	pcall(function() RunService:UnbindFromRenderStep("CheatSimFreecam") end)
	pcall(function() ContextActionService:UnbindAction("CheatSimFreecamSink") end)
	UIS.MouseBehavior = Enum.MouseBehavior.Default
	camera.CameraType = Enum.CameraType.Custom
	local hum = getHumanoid()
	if hum then camera.CameraSubject = hum end
end

local function startFreecam()
	if freecamBound then return end
	freecamBound = true
	local pitch, yaw = camera.CFrame:ToOrientation()
	freecam.pitch, freecam.yaw, freecam.pos = pitch, yaw, camera.CFrame.Position
	camera.CameraType = Enum.CameraType.Scriptable

	ContextActionService:BindActionAtPriority("CheatSimFreecamSink", function()
		return Enum.ContextActionResult.Sink
	end, false, Enum.ContextActionPriority.High.Value,
		Enum.KeyCode.W, Enum.KeyCode.A, Enum.KeyCode.S, Enum.KeyCode.D,
		Enum.KeyCode.Q, Enum.KeyCode.E, Enum.KeyCode.Space, Enum.KeyCode.LeftControl)

	RunService:BindToRenderStep("CheatSimFreecam", Enum.RenderPriority.Camera.Value + 2, function(dt)
		local rot = CFrame.fromOrientation(freecam.pitch, freecam.yaw, 0)
		local move = Vector3.zero
		if UIS:IsKeyDown(Enum.KeyCode.W) then move += rot.LookVector end
		if UIS:IsKeyDown(Enum.KeyCode.S) then move -= rot.LookVector end
		if UIS:IsKeyDown(Enum.KeyCode.D) then move += rot.RightVector end
		if UIS:IsKeyDown(Enum.KeyCode.A) then move -= rot.RightVector end
		if UIS:IsKeyDown(Enum.KeyCode.E) or UIS:IsKeyDown(Enum.KeyCode.Space) then move += Vector3.yAxis end
		if UIS:IsKeyDown(Enum.KeyCode.Q) or UIS:IsKeyDown(Enum.KeyCode.LeftControl) then move -= Vector3.yAxis end
		if move.Magnitude > 0 then
			local speed = State.FreecamSpeed * (UIS:IsKeyDown(Enum.KeyCode.LeftShift) and 3 or 1)
			freecam.pos += move.Unit * speed * dt
		end
		camera.CFrame = CFrame.new(freecam.pos) * rot
	end)
end

connect(UIS.InputChanged, function(input)
	if freecamBound and freecam.rmb and input.UserInputType == Enum.UserInputType.MouseMovement then
		freecam.yaw -= input.Delta.X * 0.0035
		freecam.pitch = math.clamp(freecam.pitch - input.Delta.Y * 0.0035, -1.5, 1.5)
	end
end)

-- TARGETS (players + NPCs) and ground items
local collectTargets
do -- BLOCK
local npcs = {}

local function trackNPC(hum)
	local m = hum.Parent
	if m and m:IsA("Model") then npcs[m] = true end
end

for _, d in ipairs(workspace:GetDescendants()) do
	if d:IsA("Humanoid") then
		trackNPC(d)
	elseif d:IsA("Tool") then
		groundTools[d] = true
	end
end
connect(workspace.DescendantAdded, function(d)
	if d:IsA("Humanoid") then
		task.defer(trackNPC, d)
	elseif d:IsA("Tool") then
		groundTools[d] = true
	end
end)

function collectTargets(includeNPC)
	local list = {}
	for _, plr in ipairs(Players:GetPlayers()) do
		local char = plr ~= player and plr.Character
		if char then
			local hum = char:FindFirstChildOfClass("Humanoid")
			local root = char:FindFirstChild("HumanoidRootPart")
			if hum and root and hum.Health > 0 then
				table.insert(list, {
					model = char, hum = hum, root = root, name = plr.DisplayName,
					isNPC = false, friend = isFriend(plr),
				})
			end
		end
	end
	if includeNPC then
		for m in pairs(npcs) do
			if not m.Parent then
				npcs[m] = nil
			elseif m ~= player.Character and not Players:GetPlayerFromCharacter(m) then
				local hum = m:FindFirstChildOfClass("Humanoid")
				local root = m:FindFirstChild("HumanoidRootPart") or m.PrimaryPart or m:FindFirstChildWhichIsA("BasePart")
				if hum and root and hum.Health > 0 then
					table.insert(list, { model = m, hum = hum, root = root, name = m.Name, isNPC = true, friend = false })
				end
			end
		end
	end
	return list
end
end -- BLOCK

-- AIMBOT / TRIGGERBOT / FOV
local clickAssist
do -- BLOCK
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function getAimPart(t)
	local m = t.model
	if State.AimPart == "Head" then
		return m:FindFirstChild("Head") or t.root
	elseif State.AimPart == "Torso" then
		return m:FindFirstChild("UpperTorso") or m:FindFirstChild("Torso") or t.root
	end
	return t.root
end

local function isVisible(part, model)
	local origin = camera.CFrame.Position
	local dir = part.Position - origin
	local filter = { player.Character, model }
	for _ = 1, 6 do
		rayParams.FilterDescendantsInstances = filter
		local res = workspace:Raycast(origin, dir, rayParams)
		if not res then return true end
		local inst = res.Instance
		local m = inst:FindFirstAncestorOfClass("Model")
		if m and m:FindFirstChildOfClass("Humanoid") then
			table.insert(filter, m)
		elseif inst.Transparency >= 0.95 then
			table.insert(filter, inst)
		else
			return false
		end
	end
	return false
end

local function getClosestTarget()
	local mousePos = UIS:GetMouseLocation()
	local best, bestDist
	for _, t in ipairs(collectTargets(State.AimNPC)) do
		if not (State.AimSkipFriends and t.friend) then
			local part = getAimPart(t)
			local pos, onScreen = camera:WorldToViewportPoint(part.Position)
			if onScreen then
				local d = (Vector2.new(pos.X, pos.Y) - mousePos).Magnitude
				if d <= State.AimFOV and (not bestDist or d < bestDist) then
					if not State.AimWall or isVisible(part, t.model) then
						best, bestDist = { part = part, t = t }, d
					end
				end
			end
		end
	end
	return best
end

local lastShot = 0
local function triggerStep()
	local char = player.Character
	local tool = char and char:FindFirstChildOfClass("Tool")
	if not tool then return end
	local mp = UIS:GetMouseLocation()
	local ray = camera:ViewportPointToRay(mp.X, mp.Y)
	rayParams.FilterDescendantsInstances = { char }
	local res = workspace:Raycast(ray.Origin, ray.Direction * 1000, rayParams)
	if not res then return end
	local model = res.Instance:FindFirstAncestorOfClass("Model")
	local hum = model and model:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then return end
	local victim = Players:GetPlayerFromCharacter(model)
	if not victim and not State.AimNPC then return end
	if victim and State.AimSkipFriends and isFriend(victim) then return end
	if os.clock() - lastShot > 0.1 then
		lastShot = os.clock()
		tool:Activate()
	end
end

-- BIG CLICK HITBOX: the camera is turned just enough so the cursor points at a nearby target
function clickAssist()
	if not State.BigHitbox or freecamBound then return end
	local mp = UIS:GetMouseLocation()
	local bestPart, bestDist
	for _, t in ipairs(collectTargets(State.AimNPC)) do
		if not (State.AimSkipFriends and t.friend) then
			local part = getAimPart(t)
			local pos, onScreen = camera:WorldToViewportPoint(part.Position)
			if onScreen then
				local d = (Vector2.new(pos.X, pos.Y) - mp).Magnitude
				if d <= State.BigHitboxSize and (not bestDist or d < bestDist) then
					if not State.AimWall or isVisible(part, t.model) then
						bestPart, bestDist = part, d
					end
				end
			end
		end
	end
	if not bestPart then return end

	local cf = camera.CFrame
	local ray = camera:ViewportPointToRay(mp.X, mp.Y)
	local from = ray.Direction.Unit
	local to = (bestPart.Position - cf.Position).Unit
	local axis = from:Cross(to)
	if axis.Magnitude < 1e-4 then return end
	local angle = math.acos(math.clamp(from:Dot(to), -1, 1))
	local rot = CFrame.fromAxisAngle(axis.Unit, angle)
	camera.CFrame = CFrame.new(cf.Position) * rot * (cf - cf.Position)
end

local fovNow = camera.FieldOfView
pcall(function() RunService:UnbindFromRenderStep("CheatSimMain") end)
RunService:BindToRenderStep("CheatSimMain", Enum.RenderPriority.Camera.Value + 1, function(dt)
	camera = workspace.CurrentCamera
	local mp = UIS:GetMouseLocation()

	fovCircle.Visible = State.Aim and not freecamBound
	fovCircle.Position = UDim2.fromOffset(mp.X, mp.Y)
	fovCircle.Size = UDim2.fromOffset(State.AimFOV * 2, State.AimFOV * 2)

	local aiming = false
	if State.Aim and not freecamBound
		and (not State.AimHold or UIS:IsMouseButtonPressed(Enum.UserInputType.MouseButton2) or UIS.TouchEnabled) then
		local tgt = getClosestTarget()
		if tgt then
			aiming = true
			local aimPos = tgt.part.Position + tgt.part.AssemblyLinearVelocity * (State.AimPred / 100)
			local goal = CFrame.lookAt(camera.CFrame.Position, aimPos)
			local a = math.clamp((101 - State.AimSmooth) / 100, 0.02, 1)
			camera.CFrame = camera.CFrame:Lerp(goal, 1 - (1 - a) ^ (dt * 60))
		end
	end
	fovStroke.Color = aiming and Color3.fromRGB(232, 96, 110) or Theme.Accent

	local clickOn = State.BigHitbox and not freecamBound
	clickRing.Visible = clickOn
	if clickOn then
		clickRing.Position = UDim2.fromOffset(mp.X, mp.Y)
		clickRing.Size = UDim2.fromOffset(State.BigHitboxSize * 2, State.BigHitboxSize * 2)
		if clickHeld or os.clock() < clickUntil then clickAssist() end
	end

	if State.Trigger and not freecamBound then triggerStep() end

	local goalFov = (State.Zoom and zoomHeld) and State.ZoomFOV or State.FOV
	fovNow += (goalFov - fovNow) * math.clamp(dt * 14, 0, 1)
	camera.FieldOfView = fovNow
end)

end -- BLOCK

-- ESP (players / NPCs)
local syncESP, updateESP
do -- BLOCK
local espObjects = {}

local function removeESPModel(model)
	local o = espObjects[model]
	if not o then return end
	for _, k in ipairs({ "hl", "box", "tag", "tracer" }) do
		if o[k] then o[k]:Destroy() end
	end
	espObjects[model] = nil
end

local function createESP(t)
	local color = espColor(t)
	local o = { t = t }

	o.hl = new("Highlight", {
		FillColor = color,
		OutlineColor = Color3.new(1, 1, 1),
		FillTransparency = 0.7,
		DepthMode = Enum.HighlightDepthMode.AlwaysOnTop,
	}, t.model)

	o.box = new("BillboardGui", {
		Size = UDim2.fromScale(3.6, 5.6),
		AlwaysOnTop = true,
		Adornee = t.root,
	}, t.root)
	local boxFrame = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, o.box)
	o.stroke = new("UIStroke", { Color = color, Thickness = 1.5 }, boxFrame)
	local hpBg = new("Frame", {
		Position = UDim2.new(0, -6, 0, 0),
		Size = UDim2.new(0, 3, 1, 0),
		BackgroundColor3 = Color3.fromRGB(16, 16, 20),
		BorderSizePixel = 0,
	}, boxFrame)
	o.hpFill = new("Frame", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(80, 220, 120),
		BorderSizePixel = 0,
	}, hpBg)

	local head = t.model:FindFirstChild("Head") or t.root
	o.tag = new("BillboardGui", {
		Size = UDim2.fromOffset(180, 34),
		StudsOffset = Vector3.new(0, 3, 0),
		AlwaysOnTop = true,
		Adornee = head,
	}, head)
	o.label = new("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Font = Enum.Font.GothamBold,
		TextSize = 13,
		TextColor3 = Color3.new(1, 1, 1),
		TextStrokeTransparency = 0.4,
		Text = t.name,
	}, o.tag)

	o.tracer = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(0, 1.5),
		Visible = false,
	}, overlay)

	espObjects[t.model] = o
end

function syncESP()
	if not State.ESP then
		for m in pairs(espObjects) do removeESPModel(m) end
		return
	end
	local seen = {}
	for _, t in ipairs(targetCache) do
		seen[t.model] = true
		if not espObjects[t.model] then
			createESP(t)
		else
			espObjects[t.model].t = t
		end
	end
	for m in pairs(espObjects) do
		if not seen[m] then removeESPModel(m) end
	end
end

function updateESP()
	if next(espObjects) == nil then return end
	local myRoot = getRoot()
	local vp = camera.ViewportSize
	local wall = State.ESPWall
	for model, o in pairs(espObjects) do
		local t = o.t
		if not model.Parent or not t.root.Parent or t.hum.Health <= 0 then
			removeESPModel(model)
		else
			local dist = myRoot and (t.root.Position - myRoot.Position).Magnitude or 0
			local show = dist <= State.ESPDist
			local col = espColor(t)
			o.hl.FillColor = col
			o.hl.DepthMode = wall and Enum.HighlightDepthMode.AlwaysOnTop or Enum.HighlightDepthMode.Occluded
			o.box.AlwaysOnTop = wall
			o.tag.AlwaysOnTop = wall
			o.stroke.Color = col
			o.tracer.BackgroundColor3 = col
			o.hl.Enabled = show and State.ESPChams
			o.box.Enabled = show and State.ESPBox
			o.tag.Enabled = show and State.ESPName

			local frac = math.clamp(t.hum.Health / math.max(t.hum.MaxHealth, 1), 0, 1)
			o.hpFill.Size = UDim2.fromScale(1, frac)
			o.hpFill.BackgroundColor3 = Color3.fromHSV(frac * 0.33, 0.7, 0.95)
			o.label.Text = string.format("%s%s\n%d HP  •  %d m",
				t.friend and "[Friend] " or "", t.name, math.floor(t.hum.Health), math.floor(dist))

			if show and State.ESPTracer then
				local p = camera:WorldToViewportPoint(t.root.Position)
				if p.Z > 0 then
					local from = Vector2.new(vp.X / 2, vp.Y)
					local d = Vector2.new(p.X, p.Y) - from
					o.tracer.Visible = true
					o.tracer.Size = UDim2.fromOffset(d.Magnitude, 1.5)
					o.tracer.Position = UDim2.fromOffset(from.X + d.X / 2, from.Y + d.Y / 2)
					o.tracer.Rotation = math.deg(math.atan2(d.Y, d.X))
				else
					o.tracer.Visible = false
				end
			else
				o.tracer.Visible = false
			end
		end
	end
end
end -- BLOCK

-- WORLD OBJECT ESP: Chest + Halloween objects (Pumpkin, PumpkinPatch, HalloweenDoor)
-- Each kind has its own on / off switch, its own distance (up to 100000 m) and its own
-- "see through walls" switch. A chest disappears from the ESP when it is opened and shows again
-- when it is closed / respawned (see chestOpened for how an opened chest is recognized).
do -- BLOCK
local CAT_LABEL = { Chest = "Chest", Pumpkin = "Pumpkin", Patch = "Pumpkin Patch", Door = "Halloween Door" }
local EXACT = { pumpkin = "Pumpkin", pumpkinpatch = "Patch", halloweendoor = "Door" }
local found = { Chest = {}, Pumpkin = {}, Patch = {}, Door = {} }
local espObjs = {}

local function classify(d)
	if not (d:IsA("Model") or d:IsA("BasePart")) then return nil end
	local ln = string.lower(d.Name)
	local c = EXACT[ln]
	if c then
		local p = d.Parent
		if p and p ~= workspace and p:IsA("Model") and string.lower(p.Name) == ln then return nil end
		return c
	end
	if string.find(ln, "chest", 1, true) then
		if string.find(ln, "plate", 1, true) or string.find(ln, "guard", 1, true) then return nil end
		local p = d.Parent
		if p and p ~= workspace and p:IsA("Model") and string.find(string.lower(p.Name), "chest", 1, true) then
			return nil
		end
		if d:IsA("Model") and d:FindFirstChildOfClass("Humanoid") then return nil end
		local owner = d:FindFirstAncestorOfClass("Model")
		if owner and owner:FindFirstChildOfClass("Humanoid") then return nil end
		if d:FindFirstAncestorOfClass("Accessory") or d:FindFirstAncestorOfClass("Tool") then return nil end
		return "Chest"
	end
	return nil
end

local function track(d)
	local c = classify(d)
	if c then found[c][d] = true end
end

task.spawn(function()
	for i, d in ipairs(workspace:GetDescendants()) do
		if not running then return end
		track(d)
		if i % 4000 == 0 then task.wait() end
	end
end)
connect(workspace.DescendantAdded, function(d)
	task.defer(track, d)
end)

local function partOf(inst)
	if inst:IsA("BasePart") then return inst end
	return inst.PrimaryPart or inst:FindFirstChildWhichIsA("BasePart", true)
end

local function posOf(inst)
	if inst:IsA("BasePart") then return inst.Position end
	local ok, cf = pcall(inst.GetPivot, inst)
	if ok then return cf.Position end
	local p = partOf(inst)
	return p and p.Position
end

Ext.found, Ext.partOf, Ext.posOf = found, partOf, posOf

-- OPENED CHEST DETECTION (looks at several signs, a chest counts as opened if any is true):
--  1. its name contains "open"
--  2. a true/false attribute or BoolValue that means "opened" (Opened, IsOpen, Looted, Collected,
--     Claimed, Used, Empty, Cooldown... = true, or Closed, Available, CanOpen... = false)
--  3. its ProximityPrompt is disabled / its prompt or click detector was removed
--  4. all parts of the chest became invisible
-- When the chest closes again (the signs go away) it is marked again.
local TRUE_WORDS = { "opened", "isopen", "open", "looted", "loot", "collected", "claimed", "taken", "used", "empty", "cooldown", "depleted" }
local FALSE_WORDS = { "closed", "isclosed", "available", "canopen", "ready", "full", "hasloot", "active" }

local function hasWord(n, words)
	n = string.lower(n)
	for _, w in ipairs(words) do
		if string.find(n, w, 1, true) then return true end
	end
	return false
end

local function flagSaysOpened(name, value)
	local ln = string.lower(name)
	if value == true then
		if string.find(ln, "can", 1, true) or string.find(ln, "close", 1, true)
			or string.find(ln, "unopen", 1, true) or string.find(ln, "not", 1, true) then
			return false
		end
		return hasWord(ln, TRUE_WORDS)
	elseif value == false then
		return hasWord(ln, FALSE_WORDS)
	end
	return false
end

local chestMemo = setmetatable({}, { __mode = "k" })
local function chestOpened(inst)
	local now = os.clock()
	local m = chestMemo[inst]
	if m and now - m.t < 0.5 then return m.v end
	m = m or { hadInteract = false, everVisible = false }
	m.t = now

	local v = false
	local ln = string.lower(inst.Name)
	if string.find(ln, "open", 1, true) and not string.find(ln, "closed", 1, true)
		and not string.find(ln, "unopen", 1, true) then
		v = true
	end
	if not v then
		for k, a in pairs(inst:GetAttributes()) do
			if type(a) == "boolean" and flagSaysOpened(k, a) then
				v = true
				break
			end
		end
	end
	if not v then
		local interact, parts, visible = 0, 0, 0
		local list = inst:GetDescendants()
		table.insert(list, inst)
		for _, d in ipairs(list) do
			if d:IsA("BoolValue") then
				if flagSaysOpened(d.Name, d.Value) then
					v = true
					break
				end
			elseif d:IsA("ProximityPrompt") then
				interact += 1
				m.hadInteract = true
				if not d.Enabled then
					v = true
					break
				end
			elseif d:IsA("ClickDetector") then
				interact += 1
				m.hadInteract = true
			elseif d:IsA("BasePart") then
				parts += 1
				if d.Transparency < 0.95 then visible += 1 end
			end
		end
		if not v then
			if m.hadInteract and interact == 0 then v = true end
			if visible > 0 then m.everVisible = true end
			if m.everVisible and parts > 0 and visible == 0 then v = true end
		end
	end
	m.v = v
	chestMemo[inst] = m
	return v
end

local function removeObj(inst)
	local e = espObjs[inst]
	if not e then return end
	if e.hl then e.hl:Destroy() end
	if e.tag then e.tag:Destroy() end
	espObjs[inst] = nil
end

local function clearObjs()
	for inst in pairs(espObjs) do removeObj(inst) end
end

local function updateObjs()
	local anyOn = false
	for cat in pairs(found) do
		if State[cat .. "ESP"] then anyOn = true end
	end
	if not anyOn then
		clearObjs()
		return
	end

	local myRoot = getRoot()
	local origin = myRoot and myRoot.Position or camera.CFrame.Position
	local list = {}
	for cat, set in pairs(found) do
		if State[cat .. "ESP"] then
			local maxD = State[cat .. "Dist"]
			for inst in pairs(set) do
				if not inst:IsDescendantOf(workspace) then
					set[inst] = nil
				else
					local p = posOf(inst)
					if p then
						local d = (p - origin).Magnitude
						if d <= maxD and not (cat == "Chest" and State.ChestHideOpened and chestOpened(inst)) then
							list[#list + 1] = { inst = inst, cat = cat, dist = d }
						end
					end
				end
			end
		end
	end
	table.sort(list, function(a, b) return a.dist < b.dist end)

	local keep, hlCount = {}, 0
	for i, it in ipairs(list) do
		if i > 150 then break end
		keep[it.inst] = true
		local col = espColors[it.cat]
		local wall = State[it.cat .. "Wall"]
		local depth = wall and Enum.HighlightDepthMode.AlwaysOnTop or Enum.HighlightDepthMode.Occluded
		local e = espObjs[it.inst]
		if not e then
			local part = partOf(it.inst)
			if part then
				e = { cat = it.cat }
				e.tag = new("BillboardGui", {
					Size = UDim2.fromOffset(170, 32),
					StudsOffset = Vector3.new(0, 2.5, 0),
					AlwaysOnTop = wall,
					Adornee = part,
				}, gui)
				e.label = new("TextLabel", {
					BackgroundTransparency = 1,
					Size = UDim2.fromScale(1, 1),
					Font = Enum.Font.GothamBold,
					TextSize = 13,
					TextColor3 = col,
					TextStrokeTransparency = 0.4,
					Text = "",
				}, e.tag)
				espObjs[it.inst] = e
			end
		end
		if e then
			e.tag.AlwaysOnTop = wall
			e.label.TextColor3 = col
			e.label.Text = CAT_LABEL[it.cat] .. "\n" .. math.floor(it.dist) .. " m"
			if hlCount < 28 then
				hlCount += 1
				if not e.hl then
					e.hl = new("Highlight", {
						FillColor = col,
						OutlineColor = Color3.new(1, 1, 1),
						FillTransparency = 0.6,
						DepthMode = depth,
						Adornee = it.inst,
					}, gui)
				end
				e.hl.FillColor = col
				e.hl.DepthMode = depth
			elseif e.hl then
				e.hl:Destroy()
				e.hl = nil
			end
		end
	end
	for inst in pairs(espObjs) do
		if not keep[inst] then removeObj(inst) end
	end
end

task.spawn(function()
	while running do
		pcall(updateObjs)
		task.wait(0.25)
	end
end)
table.insert(Ext.cleanup, clearObjs)
end -- BLOCK

-- RADAR
local clearRadar, updateRadar
do -- BLOCK
local radarDots = {}

function clearRadar()
	for m, d in pairs(radarDots) do
		d:Destroy()
		radarDots[m] = nil
	end
end

function updateRadar()
	if not State.Radar then return end
	local myRoot = getRoot()
	if not myRoot then return end
	local lv = camera.CFrame.LookVector
	local look = Vector3.new(lv.X, 0, lv.Z)
	if look.Magnitude < 0.01 then return end
	look = look.Unit
	local right = look:Cross(Vector3.yAxis)

	local seen = {}
	for _, t in ipairs(targetCache) do
		local m = t.model
		if m.Parent and t.root.Parent and t.hum.Health > 0 then
			seen[m] = true
			local dot = radarDots[m]
			if not dot then
				dot = new("Frame", {
					AnchorPoint = Vector2.new(0.5, 0.5),
					Size = UDim2.fromOffset(6, 6),
					BackgroundColor3 = espColor(t),
					BorderSizePixel = 0,
				}, radar)
				new("UICorner", { CornerRadius = UDim.new(1, 0) }, dot)
				radarDots[m] = dot
			end
			dot.BackgroundColor3 = espColor(t)
			dot.Size = t.friend and UDim2.fromOffset(8, 8) or UDim2.fromOffset(6, 6)
			local rel = t.root.Position - myRoot.Position
			local v = Vector2.new(rel:Dot(right), -rel:Dot(look)) / State.RadarRange
			if v.Magnitude > 1 then v = v.Unit end
			dot.Position = UDim2.new(0.5, v.X * (RADAR_R - 5), 0.5, v.Y * (RADAR_R - 5))
		end
	end
	for m, d in pairs(radarDots) do
		if not seen[m] then
			d:Destroy()
			radarDots[m] = nil
		end
	end
end
end -- BLOCK

-- WORLD
local applyWorld, applyGravity, applyZoomUnlock
do -- BLOCK
local atmo = Lighting:FindFirstChildOfClass("Atmosphere")
local atmoDensity = atmo and atmo.Density
local lightBackup = {
	Brightness = Lighting.Brightness,
	ClockTime = Lighting.ClockTime,
	FogEnd = Lighting.FogEnd,
	FogStart = Lighting.FogStart,
	GlobalShadows = Lighting.GlobalShadows,
	Ambient = Lighting.Ambient,
	OutdoorAmbient = Lighting.OutdoorAmbient,
}
local originalGravity = workspace.Gravity
local originalMinZoom, originalMaxZoom = player.CameraMinZoomDistance, player.CameraMaxZoomDistance
local fxBackup = {}
local fogColorBackup = Lighting.FogColor
local fxCC, fxBloom

function applyWorld()
	if State.Fullbright then
		Lighting.Brightness = 2
		Lighting.GlobalShadows = false
		Lighting.Ambient = Color3.fromRGB(178, 178, 178)
		Lighting.OutdoorAmbient = Color3.fromRGB(178, 178, 178)
	else
		Lighting.Brightness = lightBackup.Brightness
		Lighting.GlobalShadows = lightBackup.GlobalShadows
		Lighting.Ambient = lightBackup.Ambient
		Lighting.OutdoorAmbient = lightBackup.OutdoorAmbient
	end

	if State.NoFog then
		Lighting.FogEnd = 1e6
		Lighting.FogStart = 1e6
		if atmo then atmo.Density = 0 end
	else
		Lighting.FogEnd = lightBackup.FogEnd
		Lighting.FogStart = lightBackup.FogStart
		if atmo and atmoDensity then atmo.Density = atmoDensity end
	end

	Lighting.ClockTime = State.TimeOn and State.Time or lightBackup.ClockTime

	for _, parent in ipairs({ Lighting, camera }) do
		for _, e in ipairs(parent:GetChildren()) do
			if e:IsA("PostEffect") and not e:GetAttribute("CheatSim") then
				if State.NoPostFX then
					if fxBackup[e] == nil then fxBackup[e] = e.Enabled end
					e.Enabled = false
				elseif fxBackup[e] ~= nil then
					e.Enabled = fxBackup[e]
					fxBackup[e] = nil
				end
			end
		end
	end
	Ext.applyFx()
end

function applyGravity()
	workspace.Gravity = State.GravityOn and State.GravityValue or originalGravity
end

function applyZoomUnlock()
	player.CameraMinZoomDistance = State.ZoomUnlock and 0.5 or originalMinZoom
	player.CameraMaxZoomDistance = State.ZoomUnlock and 1000 or originalMaxZoom
end

function Ext.applyFx()
	if State.FxCC then
		if not (fxCC and fxCC.Parent) then
			fxCC = Instance.new("ColorCorrectionEffect")
			fxCC.Name = "CheatSimColor"
			fxCC:SetAttribute("CheatSim", true)
			fxCC.Parent = Lighting
		end
		fxCC.Enabled = true
		fxCC.TintColor = Ext.fxColors.Tint
		fxCC.Saturation = State.FxSat / 100
		fxCC.Contrast = State.FxCon / 100
		fxCC.Brightness = State.FxBri / 100
	elseif fxCC then
		fxCC:Destroy()
		fxCC = nil
	end

	if State.FxBloom then
		if not (fxBloom and fxBloom.Parent) then
			fxBloom = Instance.new("BloomEffect")
			fxBloom.Name = "CheatSimBloom"
			fxBloom:SetAttribute("CheatSim", true)
			fxBloom.Parent = Lighting
		end
		fxBloom.Enabled = true
		fxBloom.Intensity = State.FxBloomI / 100
		fxBloom.Size = State.FxBloomS
		fxBloom.Threshold = 0.8
	elseif fxBloom then
		fxBloom:Destroy()
		fxBloom = nil
	end

	if State.FxAmb then
		Lighting.Ambient = Ext.fxColors.Amb
		Lighting.OutdoorAmbient = Ext.fxColors.Amb
	end
	Lighting.FogColor = State.FxFog and Ext.fxColors.Fog or fogColorBackup
end

end -- BLOCK

-- VFX OF THE GAME, separately for particles / trails / beams / fire+smoke+sparkles+explosions / lights.
-- Every effect that exists in the world (also new ones that appear later, also effects of other
-- players) is remembered with its original values, so it can be switched off, forced on, scaled,
-- recolored, made more visible and put back exactly. Everything is client side: it changes what
-- YOU see. Roblox never sends client changes to other players.
do -- BLOCK
local tracked = setmetatable({}, { __mode = "k" })
local TYPE_OF = {
	ParticleEmitter = "Par", Trail = "Tr", Beam = "Be",
	Fire = "Mi", Smoke = "Mi", Sparkles = "Mi", Explosion = "Mi",
	PointLight = "Li", SpotLight = "Li", SurfaceLight = "Li",
}
local KEYS = { "Par", "Tr", "Be", "Mi", "Li" }
local HIDDEN = NumberSequence.new(1)
local vfxHue = 0
local pending, busy = false, false

local function scaleNS(ns, k)
	local kp = ns.Keypoints
	local out = table.create(#kp)
	for i, p in ipairs(kp) do
		out[i] = NumberSequenceKeypoint.new(p.Time, p.Value * k, p.Envelope * k)
	end
	return NumberSequence.new(out)
end

-- boost moves the transparency of a sequence towards 0 (fully visible)
local function fadeNS(ns, boost)
	local kp = ns.Keypoints
	local out = table.create(#kp)
	for i, p in ipairs(kp) do
		out[i] = NumberSequenceKeypoint.new(p.Time, p.Value * (1 - boost), p.Envelope * (1 - boost))
	end
	return NumberSequence.new(out)
end

local function snapshot(d)
	local c = d.ClassName
	local o = {}
	pcall(function()
		if c == "ParticleEmitter" then
			o.Enabled, o.Rate, o.Size, o.Color, o.Transparency, o.Emit =
				d.Enabled, d.Rate, d.Size, d.Color, d.Transparency, d.LightEmission
		elseif c == "Trail" then
			o.Enabled, o.Color, o.Transparency, o.Life = d.Enabled, d.Color, d.Transparency, d.Lifetime
		elseif c == "Beam" then
			o.Enabled, o.Color, o.W0, o.W1, o.Transparency = d.Enabled, d.Color, d.Width0, d.Width1, d.Transparency
		elseif c == "Fire" then
			o.Enabled, o.Size, o.Color, o.Sec = d.Enabled, d.Size, d.Color, d.SecondaryColor
		elseif c == "Smoke" then
			o.Enabled, o.Size, o.Color, o.Opacity = d.Enabled, d.Size, d.Color, d.Opacity
		elseif c == "Sparkles" then
			o.Enabled, o.Color = d.Enabled, d.SparkleColor
		elseif c == "Explosion" then
			o.Visible = d.Visible
		else
			o.Enabled, o.Brightness, o.Range, o.Color = d.Enabled, d.Brightness, d.Range, d.Color
		end
	end)
	return o
end

local function typeActive(k)
	return State["Vfx" .. k .. "Mode"] ~= "Game" or State["Vfx" .. k .. "Amt"] ~= 100
		or State["Vfx" .. k .. "Size"] ~= 100 or State["Vfx" .. k .. "Rec"] ~= "Off"
		or State["Vfx" .. k .. "Boost"] ~= 0
end

local function vfxActive()
	for _, k in ipairs(KEYS) do
		if typeActive(k) then return true end
	end
	return false
end

-- neutral = true puts the original values back
local function applyOne(d, o, neutral)
	if not d.Parent then return end
	local c = d.ClassName
	local k = TYPE_OF[c]
	local mode = neutral and "Game" or State["Vfx" .. k .. "Mode"]
	local off = mode == "Off"
	local force = mode == "Force on"
	local rate = neutral and 1 or State["Vfx" .. k .. "Amt"] / 100
	local size = neutral and 1 or State["Vfx" .. k .. "Size"] / 100
	local boost = neutral and 0 or State["Vfx" .. k .. "Boost"] / 100
	local rec = neutral and "Off" or State["Vfx" .. k .. "Rec"]
	local recolor = rec ~= "Off"
	local col = rec == "Rainbow" and Color3.fromHSV(vfxHue, 0.9, 1) or Ext.vfxColors[k]
	local on = (o.Enabled or force) and not off
	pcall(function()
		if c == "ParticleEmitter" then
			d.Enabled = on
			d.Rate = off and 0 or o.Rate * rate
			d.Size = size == 1 and o.Size or scaleNS(o.Size, size)
			d.Color = recolor and ColorSequence.new(col) or o.Color
			d.Transparency = off and HIDDEN or (boost > 0 and fadeNS(o.Transparency, boost) or o.Transparency)
			d.LightEmission = math.clamp(o.Emit + boost * 0.5, 0, 1)
		elseif c == "Trail" then
			d.Enabled = on
			d.Color = recolor and ColorSequence.new(col) or o.Color
			d.Transparency = off and HIDDEN or (boost > 0 and fadeNS(o.Transparency, boost) or o.Transparency)
			d.Lifetime = math.max(o.Life * rate, 0.01)
		elseif c == "Beam" then
			d.Enabled = on
			d.Color = recolor and ColorSequence.new(col) or o.Color
			d.Width0 = o.W0 * size
			d.Width1 = o.W1 * size
			d.Transparency = off and HIDDEN or (boost > 0 and fadeNS(o.Transparency, boost) or o.Transparency)
		elseif c == "Fire" then
			d.Enabled = on
			d.Size = math.clamp(o.Size * size, 2, 30)
			d.Color = recolor and col or o.Color
			d.SecondaryColor = recolor and col or o.Sec
		elseif c == "Smoke" then
			d.Enabled = on
			d.Size = math.clamp(o.Size * size, 0.1, 100)
			d.Color = recolor and col or o.Color
			d.Opacity = off and 0 or (o.Opacity + (1 - o.Opacity) * boost)
		elseif c == "Sparkles" then
			d.Enabled = on
			d.SparkleColor = recolor and col or o.Color
		elseif c == "Explosion" then
			d.Visible = (o.Visible or force) and not off
		else
			d.Enabled = on
			d.Brightness = o.Brightness * rate
			d.Range = o.Range * size
			d.Color = recolor and col or o.Color
		end
	end)
end

local runId = 0
local function applyAll(neutral, sync)
	runId += 1
	local my = runId
	local n = 0
	busy = true
	for d, o in pairs(tracked) do
		if my ~= runId then return end
		applyOne(d, o, neutral)
		n += 1
		if not sync and n % 600 == 0 then task.wait() end
	end
	busy = false
end

local function track(d)
	if TYPE_OF[d.ClassName] and not tracked[d] then
		tracked[d] = snapshot(d)
		if vfxActive() then applyOne(d, tracked[d], false) end
	end
end

task.spawn(function()
	for i, d in ipairs(workspace:GetDescendants()) do
		if not running then return end
		track(d)
		if i % 4000 == 0 then task.wait() end
	end
end)
connect(workspace.DescendantAdded, function(d)
	if TYPE_OF[d.ClassName] then task.defer(track, d) end
end)

function Ext.applyVfx()
	if pending then return end
	pending = true
	task.defer(function()
		pending = false
		task.spawn(applyAll, not vfxActive(), false)
	end)
end

-- rainbow colors, and keeping Off / Force on while the game tries to change the effects back
task.spawn(function()
	while running do
		task.wait(0.15)
		local rainbow, forced = false, false
		for _, k in ipairs(KEYS) do
			if State["Vfx" .. k .. "Rec"] == "Rainbow" then rainbow = true end
			if State["Vfx" .. k .. "Mode"] ~= "Game" then forced = true end
		end
		if rainbow then
			vfxHue = (vfxHue + 0.015) % 1
			if not busy then task.spawn(applyAll, false, false) end
		elseif forced and not busy then
			task.spawn(applyAll, false, false)
			task.wait(1)
		end
	end
end)

table.insert(Ext.cleanup, function()
	applyAll(true, true)
end)
end -- BLOCK

-- INVISIBILITY (drawn on your own screen only)
do -- BLOCK
local orig = setmetatable({}, { __mode = "k" })
local wasOn = false
local acc = 0

local function restore()
	for p, t in pairs(orig) do
		if p.Parent then pcall(function() p.Transparency = t end) end
		orig[p] = nil
	end
end

function Ext.stepInvis(dt)
	if not State.Invis then
		if wasOn then
			restore()
			wasOn = false
		end
		return
	end
	acc += dt
	if acc < 0.12 then return end
	acc = 0
	local chr = player.Character
	if not chr then return end
	wasOn = true
	local k = State.InvisValue / 100
	for _, d in ipairs(chr:GetDescendants()) do
		if (d:IsA("BasePart") and d.Name ~= "HumanoidRootPart") or d:IsA("Decal") then
			local o = orig[d]
			if o == nil then
				o = d.Transparency
				orig[d] = o
			end
			local want = o + (1 - o) * k
			if d.Transparency ~= want then d.Transparency = want end
		end
	end
end

table.insert(Ext.cleanup, restore)
end -- BLOCK

-- WALK ON WATER / WALK ON AIR
-- Walk on water works on:
--   1. the water of Roblox terrain (an invisible floor follows your feet)
--   2. every part named "WaterBase-Plane" (its collision is switched on while the option is on,
--      and an invisible floor on its top surface is added as a backup; the old collision is
--      put back when the option is switched off)
-- Walk on air: an invisible floor under your feet (Space = up, Left Ctrl = down).
do -- BLOCK
local platforms = {}
local airY
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = false
local planes = {}
local planeBackup = setmetatable({}, { __mode = "k" })

local function isPlane(d)
	return d:IsA("BasePart") and string.lower(d.Name) == "waterbase-plane"
end

task.spawn(function()
	for i, d in ipairs(workspace:GetDescendants()) do
		if not running then return end
		if isPlane(d) then planes[d] = true end
		if i % 4000 == 0 then task.wait() end
	end
end)
connect(workspace.DescendantAdded, function(d)
	task.defer(function()
		if isPlane(d) then planes[d] = true end
	end)
end)

local function getPlat(name)
	local p = platforms[name]
	if p and p.Parent then return p end
	p = Instance.new("Part")
	p.Name = "CheatSim" .. name
	p.Size = Vector3.new(14, 1, 14)
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.Transparency = 1
	p.CastShadow = false
	p.Parent = camera
	platforms[name] = p
	return p
end

local function hidePlat(name)
	local p = platforms[name]
	if p and p.CanCollide then p.CanCollide = false end
end

local function restorePlanes()
	for p, b in pairs(planeBackup) do
		if p.Parent then pcall(function() p.CanCollide = b[1] end) end
		planeBackup[p] = nil
	end
end

function Ext.resetAir() airY = nil end

connect(RunService.Heartbeat, function(dt)
	-- WaterBase-Plane collision on / off
	for p in pairs(planes) do
		if not p.Parent then
			planes[p] = nil
			planeBackup[p] = nil
		elseif State.WalkWater then
			if planeBackup[p] == nil then planeBackup[p] = { p.CanCollide } end
			if not p.CanCollide then p.CanCollide = true end
		elseif planeBackup[p] ~= nil then
			p.CanCollide = planeBackup[p][1]
			planeBackup[p] = nil
		end
	end

	local chr = player.Character
	local root, hum = getRoot(), getHumanoid()
	if not (chr and root and hum) then return end
	local feet = (hum.RigType == Enum.HumanoidRigType.R6) and 3 or (hum.HipHeight + root.Size.Y / 2)
	local pos = root.Position
	local footY = pos.Y - feet

	if State.WalkWater then
		rayParams.FilterDescendantsInstances = { chr, camera }
		local res = workspace:Raycast(pos + Vector3.new(0, 4, 0), Vector3.new(0, -400, 0), rayParams)
		local p = getPlat("Water")
		if res and res.Material == Enum.Material.Water and pos.Y > res.Position.Y - 2 then
			p.CFrame = CFrame.new(pos.X, res.Position.Y - 0.5, pos.Z)
			p.CanCollide = true
		else
			p.CanCollide = false
		end

		-- backup floor on top of a WaterBase-Plane
		local pp = getPlat("Plane")
		local placed = false
		for plane in pairs(planes) do
			local rel = plane.CFrame:PointToObjectSpace(pos)
			if math.abs(rel.X) <= plane.Size.X / 2 and math.abs(rel.Z) <= plane.Size.Z / 2 then
				local top = plane.Position.Y + plane.Size.Y / 2
				if footY >= top - 2.5 and footY <= top + 6 then
					pp.CFrame = CFrame.new(pos.X, top - 0.5, pos.Z)
					pp.CanCollide = true
					placed = true
					break
				end
			end
		end
		if not placed then pp.CanCollide = false end
	else
		hidePlat("Water")
		hidePlat("Plane")
	end

	if State.WalkAir then
		if not airY or math.abs(footY - airY) > 80 then airY = footY end
		if not UIS:GetFocusedTextBox() then
			if UIS:IsKeyDown(Enum.KeyCode.Space) and footY > airY - 1 and footY < airY + 14 then
				airY += 22 * dt
			elseif UIS:IsKeyDown(Enum.KeyCode.LeftControl) then
				airY -= 22 * dt
			end
		end
		local p = getPlat("Air")
		p.CFrame = CFrame.new(pos.X, airY - 0.5, pos.Z)
		p.CanCollide = true
	else
		airY = nil
		hidePlat("Air")
	end
end)

table.insert(Ext.cleanup, function()
	restorePlanes()
	for _, p in pairs(platforms) do pcall(function() p:Destroy() end) end
	table.clear(platforms)
end)
end -- BLOCK

-- NO CAMERA SHAKE
do -- BLOCK
local base
local NAMES = { "CheatSimShakeA", "CheatSimShakeB", "CheatSimShakeC" }

local function unbind()
	base = nil
	for _, n in ipairs(NAMES) do
		pcall(function() RunService:UnbindFromRenderStep(n) end)
	end
end

function Ext.setNoShake(on)
	unbind()
	if not on then return end
	local cam = Enum.RenderPriority.Camera.Value
	RunService:BindToRenderStep(NAMES[1], cam - 1, function()
		local hum = getHumanoid()
		if hum and hum.CameraOffset ~= Vector3.zero then hum.CameraOffset = Vector3.zero end
	end)
	RunService:BindToRenderStep(NAMES[2], cam + 5, function()
		base = camera.CFrame
	end)
	RunService:BindToRenderStep(NAMES[3], Enum.RenderPriority.Last.Value + 100, function()
		if not base then return end
		local cur = camera.CFrame
		if (cur.Position - base.Position).Magnitude < 3 and base.LookVector:Dot(cur.LookVector) > 0.96 then
			camera.CFrame = base
		end
		base = nil
	end)
end

table.insert(Ext.cleanup, unbind)
end -- BLOCK

-- TABS (Halloween is the last one, in orange)
local pagePlayer = createTab("Misc")
local pageCombat = createTab("Combat")
local pageVisuals = createTab("Visuals")
local pageWorld = createTab("World")
local pageServer = createTab("Server")
local pageAuto = createTab("Auto")
local pageRec = createTab("Record")
local pageChat = createTab("Chat")
local pageSettings = createTab("Settings")
local pageHalloween = createTab("Halloween", Color3.fromRGB(255, 140, 30))

-- Misc: movement
addSection(pagePlayer, "Movement")
toggles.Speed = addToggle(pagePlayer, "Speed", false, function(v) State.Speed = v end, "Faster walking (WalkSpeed / CFrame)")
addSlider(pagePlayer, "Walk speed", 16, 1000, State.SpeedValue, function(v) State.SpeedValue = v end)
addSegmented(pagePlayer, "Speed mode", { "WalkSpeed", "CFrame", "Both" }, "Both", function(v) State.SpeedMode = v end)
toggles.Jump = addToggle(pagePlayer, "High jump", false, function(v) State.Jump = v end, "Stronger jump power")
addSlider(pagePlayer, "Jump power", 50, 400, State.JumpValue, function(v) State.JumpValue = v end)
toggles.InfJump = addToggle(pagePlayer, "Infinite jump", false, function(v) State.InfJump = v end, "Jump again in mid-air")
toggles.Bhop = addToggle(pagePlayer, "Bunny hop", false, function(v) State.Bhop = v end, "Hold Space to keep jumping")
toggles.WalkWater = addToggle(pagePlayer, "Walk on water", false, function(v) State.WalkWater = v end,
	"Roblox water and the part \"WaterBase-Plane\"")
toggles.WalkAir = addToggle(pagePlayer, "Walk on air", false, function(v) State.WalkAir = v end, "Invisible floor: Space = up, Left Ctrl = down")
toggles.GravityOn = addToggle(pagePlayer, "Custom gravity", false, function(v)
	State.GravityOn = v
	applyGravity()
end, "Change how fast you fall")
addSlider(pagePlayer, "Gravity", 0, 300, State.GravityValue, function(v)
	State.GravityValue = v
	if State.GravityOn then applyGravity() end
end)
addSection(pagePlayer, "Flight")
toggles.Fly = addToggle(pagePlayer, "Fly", false, function(v)
	State.Fly = v
	if v then startFly() else stopFly() end
	Ext.refreshNoclip()
end, "Fly where you look. Space / E up, Q / Ctrl down")
addSlider(pagePlayer, "Fly speed", 20, 500, State.FlySpeed, function(v) State.FlySpeed = v end)
toggles.FlyThrough = addToggle(pagePlayer, "Fly through walls", false, function(v)
	State.FlyThrough = v
	Ext.refreshNoclip()
end, "No collision with walls while flying")
addSection(pagePlayer, "Invisibility")
toggles.Invis = addToggle(pagePlayer, "Invisibility", false, function(v) State.Invis = v end,
	"Makes your character transparent (on your screen)")
addSlider(pagePlayer, "Invisibility amount", 0, 100, State.InvisValue, function(v) State.InvisValue = v end, " %")
addSection(pagePlayer, "Other")
toggles.Noclip = addToggle(pagePlayer, "Noclip", false, function(v)
	State.Noclip = v
	Ext.refreshNoclip()
end, "Walk through walls")
toggles.Spin = addToggle(pagePlayer, "Spin", false, function(v) State.Spin = v end)
addSlider(pagePlayer, "Spin speed", 5, 60, State.SpinSpeed, function(v) State.SpinSpeed = v end)
toggles.AntiVoid = addToggle(pagePlayer, "Anti-void", false, function(v) State.AntiVoid = v end, "Return to last safe spot if you fall")
toggles.ClickTP = addToggle(pagePlayer, "Click teleport", false, function(v) State.ClickTP = v end, "Hold the teleport key + Click")
toggles.AntiAFK = addToggle(pagePlayer, "Anti-AFK", true, function(v) State.AntiAFK = v end)
toggles.AutoJump = addToggle(pagePlayer, "Auto jump out", false, function(v) State.AutoJump = v end,
	"Jumps off a seat or out of an NPC dialogue (cafe) by itself")

addSection(pagePlayer, "Camera")
addSlider(pagePlayer, "Field of view", 30, 120, State.FOV, function(v) State.FOV = v end)
toggles.Zoom = addToggle(pagePlayer, "Zoom", false, function(v) State.Zoom = v end, "Hold the zoom key to zoom in")
addSlider(pagePlayer, "Zoom FOV", 5, 60, State.ZoomFOV, function(v) State.ZoomFOV = v end)
toggles.ZoomUnlock = addToggle(pagePlayer, "Unlock camera distance", false, function(v)
	State.ZoomUnlock = v
	applyZoomUnlock()
end, "Scroll out much further in third person")
toggles.NoShake = addToggle(pagePlayer, "No camera shake", false, function(v)
	State.NoShake = v
	Ext.setNoShake(v)
end, "Removes screen shake (hits, explosions, effects)")
toggles.HideGui = addToggle(pagePlayer, "Hide GUI", false, function(v)
	State.HideGui = v
	applyHideGui()
end, "Hides the game and Roblox interface (this menu stays)")
toggles.Crosshair = addToggle(pagePlayer, "Custom crosshair", false, function(v)
	State.Crosshair = v
	crosshair.Visible = v
end, "A small cross in the middle of the screen")
toggles.Freecam = addToggle(pagePlayer, "Freecam", false, function(v)
	State.Freecam = v
	if v then startFreecam() else stopFreecam() end
end, "WASD + Q/E to move, hold RMB to look, Shift = fast")
addSlider(pagePlayer, "Freecam speed", 10, 300, State.FreecamSpeed, function(v) State.FreecamSpeed = v end)
addSection(pagePlayer, "Lighting")
toggles.Fullbright = addToggle(pagePlayer, "Fullbright", false, function(v)
	State.Fullbright = v
	applyWorld()
end, "Removes darkness and shadows")
toggles.NoFog = addToggle(pagePlayer, "No fog", false, function(v)
	State.NoFog = v
	applyWorld()
end)
toggles.NoPostFX = addToggle(pagePlayer, "No post effects", false, function(v)
	State.NoPostFX = v
	applyWorld()
end, "Disables blur, bloom, color grading")
toggles.TimeOn = addToggle(pagePlayer, "Custom time of day", false, function(v)
	State.TimeOn = v
	applyWorld()
end)
addSlider(pagePlayer, "Time", 0, 24, State.Time, function(v)
	State.Time = v
	if State.TimeOn then applyWorld() end
end, " h")

-- Combat
addSection(pageCombat, "Aimbot")
toggles.Aim = addToggle(pageCombat, "Aimbot", false, function(v) State.Aim = v end, "Locks the camera onto targets")
toggles.AimNPC = addToggle(pageCombat, "Target NPCs", true, function(v) State.AimNPC = v end, "Aimbot, triggerbot and click hitbox also work on NPCs")
toggles.AimSkipFriends = addToggle(pageCombat, "Skip friends", false, function(v) State.AimSkipFriends = v end, "Aimbot, triggerbot and click hitbox ignore your friends")
toggles.AimHold = addToggle(pageCombat, "Hold RMB to aim", true, function(v) State.AimHold = v end)
addSlider(pageCombat, "Aim radius", 30, 600, State.AimFOV, function(v) State.AimFOV = v end, " px")
addSlider(pageCombat, "Smoothness", 1, 100, State.AimSmooth, function(v) State.AimSmooth = v end)
addSlider(pageCombat, "Prediction", 0, 30, State.AimPred, function(v) State.AimPred = v end)
addSegmented(pageCombat, "Target part", { "Head", "Torso", "Root" }, "Head", function(v) State.AimPart = v end)
toggles.AimWall = addToggle(pageCombat, "Wall check", true, function(v) State.AimWall = v end, "Ignore targets behind walls")
addSection(pageCombat, "Assist")
toggles.Trigger = addToggle(pageCombat, "Triggerbot", false, function(v) State.Trigger = v end, "Auto-fires your Tool when aiming at a target")
addSection(pageCombat, "Combat extras")
toggles.BigHitbox = addToggle(pageCombat, "Big hitbox", false, function(v)
	State.BigHitbox = v
end, "Bigger click area: clicks near a target still hit it")
addSlider(pageCombat, "Click hitbox radius", 20, 400, State.BigHitboxSize, function(v) State.BigHitboxSize = v end, " px")
toggles.NoStun = addToggle(pageCombat, "No stun", false, function(v)
	State.NoStun = v
	if not v then noStunStates(false) end
end, "Cancels ragdoll, stun, freeze, anchoring and slow effects on you")

-- Visuals
addSection(pageVisuals, "ESP")
toggles.ESP = addToggle(pageVisuals, "ESP", false, function(v)
	State.ESP = v
	syncESP()
end, "Master switch for all markers")
toggles.ESPWall = addToggle(pageVisuals, "ESP through walls", true, function(v) State.ESPWall = v end,
	"Off = markers are hidden behind walls")
toggles.ESPNPC = addToggle(pageVisuals, "Show NPCs", true, function(v) State.ESPNPC = v end)
toggles.ESPChams = addToggle(pageVisuals, "Highlight", true, function(v) State.ESPChams = v end, "Colored body outline")
toggles.ESPBox = addToggle(pageVisuals, "Boxes + health bar", true, function(v) State.ESPBox = v end)
toggles.ESPName = addToggle(pageVisuals, "Name, health, distance", true, function(v) State.ESPName = v end)
toggles.ESPTracer = addToggle(pageVisuals, "Tracers", false, function(v) State.ESPTracer = v end, "Lines from the screen bottom to targets")
addSlider(pageVisuals, "Max distance", 50, 100000, State.ESPDist, function(v) State.ESPDist = v end, " m")
addSection(pageVisuals, "Chest ESP")
toggles.ChestESP = addToggle(pageVisuals, "Chest ESP", false, function(v) State.ChestESP = v end,
	"Marks every chest in the world (name contains \"chest\")")
toggles.ChestWall = addToggle(pageVisuals, "Chest through walls", true, function(v) State.ChestWall = v end,
	"Off = chest markers are hidden behind walls")
toggles.ChestHideOpened = addToggle(pageVisuals, "Hide opened chests", true, function(v) State.ChestHideOpened = v end,
	"Opened chest leaves the ESP, shows again when it respawns")
addSlider(pageVisuals, "Chest distance", 20, 100000, State.ChestDist, function(v) State.ChestDist = v end, " m")
addColor(pageVisuals, "Chest color", espColors.Chest, function(c) espColors.Chest = c end)
addSection(pageVisuals, "Radar")
toggles.Radar = addToggle(pageVisuals, "Radar", false, function(v)
	State.Radar = v
	radar.Visible = v
	if not v then clearRadar() end
end, "Mini-map of nearby targets (drag it where you want)")
addSlider(pageVisuals, "Radar range", 50, 500, State.RadarRange, function(v) State.RadarRange = v end, " m")
addSection(pageVisuals, "Colors (ESP and radar)")
addColor(pageVisuals, "Player color", espColors.Player, function(c) espColors.Player = c end)
addColor(pageVisuals, "NPC color", espColors.NPC, function(c) espColors.NPC = c end)
addColor(pageVisuals, "Friend color", espColors.Friend, function(c) espColors.Friend = c end)

addSection(pageVisuals, "Menu text colors")
do -- BLOCK
local defText, defSub = Theme.Text, Theme.SubText

local function applyTextTheme(key, c)
	local old = Theme[key]
	if sameColor(old, c) then return end
	Theme[key] = c
	for _, o in ipairs(gui:GetDescendants()) do
		if o:IsA("TextLabel") or o:IsA("TextButton") or o:IsA("TextBox") then
			if sameColor(o.TextColor3, old) then o.TextColor3 = c end
			if o:IsA("TextBox") and sameColor(o.PlaceholderColor3, old) then o.PlaceholderColor3 = c end
		end
	end
end

local textPick = addColor(pageVisuals, "Text color", Theme.Text, function(c) applyTextTheme("Text", c) end)
local subPick = addColor(pageVisuals, "Secondary text color", Theme.SubText, function(c) applyTextTheme("SubText", c) end)
addButton(pageVisuals, "Reset text colors", function()
	textPick.Set(defText)
	subPick.Set(defSub)
end)
end -- BLOCK

addSection(pageVisuals, "Game effects")
do -- BLOCK
local fxc = Ext.fxColors

local ccGrp = addGroup(pageVisuals, "Color filter", false)
toggles.FxCC = addToggle(ccGrp.Body, "Color filter on", false, function(v)
	State.FxCC = v
	Ext.applyFx()
end, "Tints and recolors the whole picture")
addColor(ccGrp.Body, "Filter tint", fxc.Tint, function(c)
	fxc.Tint = c
	Ext.applyFx()
end)
addSlider(ccGrp.Body, "Filter saturation", -100, 100, State.FxSat, function(v)
	State.FxSat = v
	Ext.applyFx()
end, " %")
addSlider(ccGrp.Body, "Filter contrast", -100, 100, State.FxCon, function(v)
	State.FxCon = v
	Ext.applyFx()
end, " %")
addSlider(ccGrp.Body, "Filter brightness", -50, 50, State.FxBri, function(v)
	State.FxBri = v
	Ext.applyFx()
end, " %")

local bloomGrp = addGroup(pageVisuals, "Bloom (glow)", false)
toggles.FxBloom = addToggle(bloomGrp.Body, "Bloom on", false, function(v)
	State.FxBloom = v
	Ext.applyFx()
end, "Bright things glow")
addSlider(bloomGrp.Body, "Bloom intensity", 0, 200, State.FxBloomI, function(v)
	State.FxBloomI = v
	Ext.applyFx()
end, " %")
addSlider(bloomGrp.Body, "Bloom size", 1, 56, State.FxBloomS, function(v)
	State.FxBloomS = v
	Ext.applyFx()
end)

local lightGrp = addGroup(pageVisuals, "Light and fog colors", false)
toggles.FxAmb = addToggle(lightGrp.Body, "Custom ambient light", false, function(v)
	State.FxAmb = v
	applyWorld()
end, "Changes the color of shadows and indirect light")
addColor(lightGrp.Body, "Ambient color", fxc.Amb, function(c)
	fxc.Amb = c
	Ext.applyFx()
end)
toggles.FxFog = addToggle(lightGrp.Body, "Custom fog color", false, function(v)
	State.FxFog = v
	Ext.applyFx()
end)
addColor(lightGrp.Body, "Fog color", fxc.Fog, function(c)
	fxc.Fog = c
	Ext.applyFx()
end)

-- VFX of the game, one block per effect type
local vfxGrp = addGroup(pageVisuals, "VFX (particles, trails, beams, lights)", false)
local VFX_DEF = {
	-- key, title, amount slider label, size slider label, visibility boost
	{ "Par", "Particles", "amount", "size", true },
	{ "Tr", "Trails", "length", nil, true },
	{ "Be", "Beams", nil, "width", true },
	{ "Mi", "Fire, smoke, sparkles", nil, "size", true },
	{ "Li", "Lights", "brightness", "range", false },
}
for _, def in ipairs(VFX_DEF) do
	local k, title = def[1], def[2]
	local g = addGroup(vfxGrp.Body, title, false)
	addSegmented(g.Body, title .. " mode", { "Game", "Off", "Force on" }, "Game", function(v)
		State["Vfx" .. k .. "Mode"] = v
		Ext.applyVfx()
	end)
	if def[3] then
		addSlider(g.Body, title .. " " .. def[3], 0, 300, 100, function(v)
			State["Vfx" .. k .. "Amt"] = v
			Ext.applyVfx()
		end, " %")
	end
	if def[4] then
		addSlider(g.Body, title .. " " .. def[4], 10, 300, 100, function(v)
			State["Vfx" .. k .. "Size"] = v
			Ext.applyVfx()
		end, " %")
	end
	if def[5] then
		addSlider(g.Body, title .. " visibility boost", 0, 100, 0, function(v)
			State["Vfx" .. k .. "Boost"] = v
			Ext.applyVfx()
		end, " %")
	end
	addSegmented(g.Body, title .. " recolor", { "Off", "Color", "Rainbow" }, "Off", function(v)
		State["Vfx" .. k .. "Rec"] = v
		Ext.applyVfx()
	end)
	addColor(g.Body, title .. " color", Ext.vfxColors[k], function(c)
		Ext.vfxColors[k] = c
		if State["Vfx" .. k .. "Rec"] == "Color" then Ext.applyVfx() end
	end)
end
end -- BLOCK

-- World: items lying on the server right now
do -- BLOCK
addSection(pageWorld, "Items on the server")
local setItemCount = addInfo(pageWorld, "Items lying now")
local itemsHolder = new("Frame", {
	Size = UDim2.new(1, 0, 0, 0),
	AutomaticSize = Enum.AutomaticSize.Y,
	BackgroundTransparency = 1,
	LayoutOrder = nextOrder(pageWorld),
}, pageWorld)
new("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, itemsHolder)

local function toolHandle(tool)
	if not tool.Parent or not tool:IsDescendantOf(workspace) then return nil end
	local owner = tool:FindFirstAncestorOfClass("Model")
	if owner and owner:FindFirstChildOfClass("Humanoid") then return nil end
	return tool:FindFirstChild("Handle") or tool:FindFirstChildWhichIsA("BasePart", true)
end

local function scanItems()
	local myRoot = getRoot()
	local groups, total = {}, 0
	for tool in pairs(groundTools) do
		if not tool.Parent or not tool:IsDescendantOf(workspace) then
			groundTools[tool] = nil
		else
			local handle = toolHandle(tool)
			if handle then
				local dist = myRoot and (handle.Position - myRoot.Position).Magnitude or 0
				local g = groups[tool.Name]
				if not g then
					g = { name = tool.Name, count = 0, nearest = math.huge }
					groups[tool.Name] = g
				end
				g.count += 1
				total += 1
				if dist < g.nearest then g.nearest = dist end
			end
		end
	end
	local list = {}
	for _, g in pairs(groups) do table.insert(list, g) end
	table.sort(list, function(a, b) return a.name < b.name end)
	return list, total
end

local function nearestItemPos(name)
	local myRoot = getRoot()
	local best, bestD
	for tool in pairs(groundTools) do
		if tool.Name == name then
			local handle = toolHandle(tool)
			if handle then
				local d = myRoot and (handle.Position - myRoot.Position).Magnitude or 0
				if not bestD or d < bestD then best, bestD = handle.Position, d end
			end
		end
	end
	return best
end

local itemRows = {}
local itemSig

local function renderItems()
	local list, total = scanItems()
	setItemCount(tostring(total))

	local parts = {}
	for i, g in ipairs(list) do
		if i > 40 then break end
		parts[#parts + 1] = g.name .. ":" .. g.count
	end
	local sig = table.concat(parts, "|")

	if sig == itemSig then
		for _, g in ipairs(list) do
			local lbl = itemRows[g.name]
			if lbl then lbl.Text = "nearest " .. math.floor(g.nearest) .. " m" end
		end
		return
	end
	itemSig = sig
	table.clear(itemRows)

	for _, c in ipairs(itemsHolder:GetChildren()) do
		if c:IsA("GuiObject") then c:Destroy() end
	end
	if #list == 0 then
		local row = new("Frame", {
			Size = UDim2.new(1, 0, 0, 30),
			BackgroundColor3 = Theme.Item,
			BorderSizePixel = 0,
			LayoutOrder = 1,
		}, itemsHolder)
		corner(row, 8)
		outline(row)
		new("TextLabel", {
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(12, 0),
			Size = UDim2.new(1, -24, 1, 0),
			Text = "Nothing is lying around",
			TextXAlignment = Enum.TextXAlignment.Left,
			Font = Enum.Font.Gotham,
			TextSize = 12,
			TextColor3 = Theme.SubText,
		}, row)
		return
	end
	for i, g in ipairs(list) do
		if i > 40 then break end
		local row = new("Frame", {
			Size = UDim2.new(1, 0, 0, 30),
			BackgroundColor3 = Theme.Item,
			BorderSizePixel = 0,
			LayoutOrder = i,
		}, itemsHolder)
		corner(row, 8)
		outline(row)
		new("TextLabel", {
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(12, 0),
			Size = UDim2.new(1, -190, 1, 0),
			Text = g.name .. (g.count > 1 and ("  x" .. g.count) or ""),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Font = Enum.Font.GothamMedium,
			TextSize = 13,
			TextColor3 = Theme.Text,
		}, row)
		itemRows[g.name] = new("TextLabel", {
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -62, 0, 0),
			Size = UDim2.fromOffset(110, 30),
			Text = "nearest " .. math.floor(g.nearest) .. " m",
			TextXAlignment = Enum.TextXAlignment.Right,
			Font = Enum.Font.GothamBold,
			TextSize = 12,
			TextColor3 = Theme.Accent,
		}, row)
		local fb = new("TextButton", {
			Size = UDim2.fromOffset(46, 22),
			Position = UDim2.new(1, -54, 0.5, -11),
			BackgroundColor3 = Theme.Panel,
			Text = "Fly",
			Font = Enum.Font.GothamMedium,
			TextSize = 12,
			TextColor3 = Theme.Text,
			AutoButtonColor = false,
			BorderSizePixel = 0,
		}, row)
		corner(fb, 6)
		outline(fb)
		fb.MouseEnter:Connect(function() tween(fb, 0.12, { BackgroundColor3 = Theme.ItemHover }) end)
		fb.MouseLeave:Connect(function() tween(fb, 0.12, { BackgroundColor3 = Theme.Panel }) end)
		local itemName = g.name
		fb.MouseButton1Click:Connect(function()
			flyTo(function()
				local p = nearestItemPos(itemName)
				return p and (p + Vector3.new(0, 2, 0))
			end, itemName)
		end)
	end
end
renderItems()

task.spawn(function()
	while running do
		task.wait(1)
		if pageWorld.Visible and main.Visible and not minimized then
			renderItems()
		end
	end
end)

end -- BLOCK

-- SERVER
do -- BLOCK
local joinClock = os.clock()

local function fmtTime(s)
	s = math.max(0, math.floor(s))
	return string.format("%d:%02d:%02d", s // 3600, s % 3600 // 60, s % 60)
end

local jobShort = game.JobId ~= "" and string.sub(game.JobId, 1, 8) or "Studio"

local function updateStats()
	if not State.StatsHud then return end
	statsFrame.Text = string.format(
		"Server uptime   %s\nYour time   %s\nPlayers   %d / %d\nPing   %d ms\nFPS   %d\nServer ID   %s",
		fmtTime(workspace.DistributedGameTime),
		fmtTime(os.clock() - joinClock),
		#Players:GetPlayers(), Players.MaxPlayers,
		math.floor(player:GetNetworkPing() * 1000),
		math.floor(fps),
		jobShort
	)
end

local tickN = 0
local usageBase = 0

local countryNames = {
	US = "United States", GB = "United Kingdom", CA = "Canada", AU = "Australia", NZ = "New Zealand",
	DE = "Germany", FR = "France", ES = "Spain", IT = "Italy", PT = "Portugal", NL = "Netherlands",
	BE = "Belgium", CH = "Switzerland", AT = "Austria", SE = "Sweden", NO = "Norway", DK = "Denmark",
	FI = "Finland", IE = "Ireland", PL = "Poland", CZ = "Czechia", SK = "Slovakia", HU = "Hungary",
	RO = "Romania", BG = "Bulgaria", GR = "Greece", RS = "Serbia", HR = "Croatia", SI = "Slovenia",
	MD = "Moldova", UA = "Ukraine", BY = "Belarus", RU = "Russia", LT = "Lithuania", LV = "Latvia",
	EE = "Estonia", GE = "Georgia", AM = "Armenia", AZ = "Azerbaijan", KZ = "Kazakhstan", UZ = "Uzbekistan",
	TR = "Turkey", IL = "Israel", SA = "Saudi Arabia", AE = "UAE", EG = "Egypt", ZA = "South Africa",
	NG = "Nigeria", BR = "Brazil", AR = "Argentina", CL = "Chile", CO = "Colombia", PE = "Peru",
	MX = "Mexico", JP = "Japan", KR = "South Korea", CN = "China", TW = "Taiwan", HK = "Hong Kong",
	SG = "Singapore", MY = "Malaysia", TH = "Thailand", VN = "Vietnam", ID = "Indonesia",
	PH = "Philippines", IN = "India", PK = "Pakistan", BD = "Bangladesh",
}

registry["Script usage seconds"] = {
	get = function() return math.floor(usageBase + (os.clock() - joinClock)) end,
	set = function(v) usageBase = tonumber(v) or 0 end,
}

local function fmtLong(s)
	s = math.max(0, math.floor(s))
	if s >= 3600 then return string.format("%dh %02dm", s // 3600, s % 3600 // 60) end
	return string.format("%dm %02ds", s // 60, s % 60)
end

addSection(pageServer, "Profile")
local profile = baseRow(pageServer, 72)
local avatar = new("ImageLabel", {
	Position = UDim2.fromOffset(10, 8),
	Size = UDim2.fromOffset(56, 56),
	BackgroundColor3 = Theme.Bg,
	BorderSizePixel = 0,
	Image = "rbxthumb://type=AvatarHeadShot&id=" .. player.UserId .. "&w=150&h=150",
}, profile)
new("UICorner", { CornerRadius = UDim.new(1, 0) }, avatar)
new("UIStroke", { Color = Theme.Accent, Thickness = 2 }, avatar)

local function profLabel(y, h, size, font, color)
	return new("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(76, y),
		Size = UDim2.new(1, -86, 0, h),
		Text = "",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Font = font,
		TextSize = size,
		TextColor3 = color,
	}, profile)
end
local nameLbl = profLabel(5, 18, 14, Enum.Font.GothamBold, Theme.Text)
local subLbl = profLabel(23, 14, 11, Enum.Font.Gotham, Theme.SubText)
local idLbl = profLabel(38, 14, 11, Enum.Font.GothamMedium, Theme.Text)
local useLbl = profLabel(53, 14, 11, Enum.Font.Gotham, Theme.SubText)

local countryText = "..."
nameLbl.Text = player.DisplayName
idLbl.Text = "Account ID  " .. tostring(player.UserId)
local function refreshSub()
	subLbl.Text = "@" .. player.Name .. "  •  " .. countryText
end
refreshSub()

task.spawn(function()
	local ok, code = pcall(function()
		return game:GetService("LocalizationService"):GetCountryRegionForPlayerAsync(player)
	end)
	if ok and type(code) == "string" and code ~= "" then
		countryText = countryNames[code] and (countryNames[code] .. " (" .. code .. ")") or code
	else
		countryText = "unknown"
	end
	refreshSub()
end)

local function updateProfile()
	local session = os.clock() - joinClock
	useLbl.Text = "Using this script: session " .. fmtTime(session) .. "  •  total " .. fmtLong(usageBase + session)
end
updateProfile()

addSection(pageServer, "On screen (drag the panels with the mouse)")
toggles.StatsHud = addToggle(pageServer, "Stats on screen", false, function(v)
	State.StatsHud = v
	statsFrame.Visible = v
	updateStats()
end, "Server time, players, ping, FPS")
toggles.Info = addToggle(pageServer, "FPS / ping panel", false, function(v)
	State.Info = v
	infoLabel.Visible = v
end, "Small one-line FPS, ping and players panel")
toggles.HudLock = addToggle(pageServer, "Lock panel positions", false, function(v)
	State.HudLock = v
end, "Stops the panels, radar and menu button from being dragged")
addButton(pageServer, "Reset panel positions", resetHud)

addSection(pageServer, "Time")
local setUptime = addInfo(pageServer, "Server time (uptime)")
local setMine = addInfo(pageServer, "Your time on server")
addSection(pageServer, "Info")
local setPlayers = addInfo(pageServer, "Players")
local setPing = addInfo(pageServer, "Ping")
local setJob = addInfo(pageServer, "Server ID")
setJob(jobShort)

local playersGrp = addGroup(pageServer, "Players", true)
local pBody = playersGrp.Body

local function miniBtn(parent, text, size, pos, fn)
	local b = new("TextButton", {
		Size = size,
		Position = pos or UDim2.new(),
		BackgroundColor3 = Theme.Panel,
		Text = text,
		Font = Enum.Font.GothamMedium,
		TextSize = 11,
		TextColor3 = Theme.Text,
		AutoButtonColor = false,
		BorderSizePixel = 0,
	}, parent)
	corner(b, 5)
	outline(b)
	b.MouseEnter:Connect(function() tween(b, 0.12, { BackgroundColor3 = Theme.ItemHover }) end)
	b.MouseLeave:Connect(function() tween(b, 0.12, { BackgroundColor3 = Theme.Panel }) end)
	b.MouseButton1Click:Connect(fn)
	return b
end

local qRow = baseRow(pBody, 30)
new("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	Padding = UDim.new(0, 4),
	VerticalAlignment = Enum.VerticalAlignment.Center,
}, qRow)
new("UIPadding", { PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 4) }, qRow)
miniBtn(qRow, "TP to nearest", UDim2.new(0.5, -6, 0, 22), nil, function()
	local root = getRoot()
	if not root then return end
	local best, bestD
	for _, t in ipairs(collectTargets(true)) do
		local d = (t.root.Position - root.Position).Magnitude
		if not bestD or d < bestD then best, bestD = t, d end
	end
	if best then
		root.CFrame = best.root.CFrame * CFrame.new(0, 0, 4)
		notify("Teleported to " .. best.name)
	else
		notify("No targets found")
	end
end)
miniBtn(qRow, "Stop view", UDim2.new(0.5, -6, 0, 22), nil, function()
	local hum = getHumanoid()
	if hum then camera.CameraSubject = hum end
end)

local function rebuildPlayers()
	for _, c in ipairs(pBody:GetChildren()) do
		if c.Name == "PlayerRow" then c:Destroy() end
	end
	local n, order = 0, 100
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr ~= player then
			n += 1
			order += 1
			local row = new("Frame", {
				Name = "PlayerRow",
				Size = UDim2.new(1, 0, 0, 28),
				BackgroundColor3 = Theme.Item,
				BorderSizePixel = 0,
				LayoutOrder = order,
			}, pBody)
			corner(row, 7)
			outline(row)
			local av = new("ImageLabel", {
				Position = UDim2.fromOffset(6, 4),
				Size = UDim2.fromOffset(20, 20),
				BackgroundColor3 = Theme.Bg,
				BorderSizePixel = 0,
				Image = "rbxthumb://type=AvatarHeadShot&id=" .. plr.UserId .. "&w=48&h=48",
			}, row)
			new("UICorner", { CornerRadius = UDim.new(1, 0) }, av)
			new("TextLabel", {
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(32, 0),
				Size = UDim2.new(1, -152, 1, 0),
				Text = plr.DisplayName,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextTruncate = Enum.TextTruncate.AtEnd,
				Font = Enum.Font.GothamMedium,
				TextSize = 12,
				TextColor3 = Theme.Text,
			}, row)
			local sz = UDim2.fromOffset(34, 20)
			miniBtn(row, "Fly", sz, UDim2.new(1, -116, 0.5, -10), function()
				flyTo(function()
					local tr = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
					return tr and (tr.Position + Vector3.new(0, 2, 0))
				end, plr.DisplayName)
			end)
			miniBtn(row, "TP", sz, UDim2.new(1, -78, 0.5, -10), function()
				local root, tr = getRoot(), plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
				if root and tr then root.CFrame = tr.CFrame * CFrame.new(0, 0, 3) end
			end)
			miniBtn(row, "View", sz, UDim2.new(1, -40, 0.5, -10), function()
				local h = plr.Character and plr.Character:FindFirstChildOfClass("Humanoid")
				if h then camera.CameraSubject = h end
			end)
		end
	end
	if n == 0 then
		new("TextLabel", {
			Name = "PlayerRow",
			Size = UDim2.new(1, 0, 0, 22),
			BackgroundTransparency = 1,
			Text = "No other players",
			Font = Enum.Font.GothamMedium,
			TextSize = 12,
			TextColor3 = Theme.SubText,
			LayoutOrder = 101,
		}, pBody)
	end
	playersGrp.Label.Text = "Players (" .. (n + 1) .. ")"
end
rebuildPlayers()
connect(Players.PlayerAdded, function() task.defer(rebuildPlayers) end)
connect(Players.PlayerRemoving, function() task.defer(rebuildPlayers) end)

task.spawn(function()
	while running do
		setUptime(fmtTime(workspace.DistributedGameTime))
		setMine(fmtTime(os.clock() - joinClock))
		setPlayers(#Players:GetPlayers() .. " / " .. Players.MaxPlayers)
		setPing(math.floor(player:GetNetworkPing() * 1000) .. " ms")
		updateStats()
		updateProfile()
		tickN += 1
		if tickN % 60 == 0 then changed() end
		task.wait(1)
	end
end)

end -- BLOCK

-- AUTO
local runAutoSpawn
do -- BLOCK
local Auto = {}
local AUTO_MAX = 10
local AutoCfg = { Delay = 1, Interval = 500 }

local vimWarned = false

local function activeAutoCount()
	local n = 0
	for _, a in ipairs(Auto) do
		if not a.Removed then n += 1 end
	end
	return n
end

local function pressKey(name)
	local kc = toKey(name)
	if not kc then return end
	for _, a in ipairs(ToggleBinds) do
		if Binds[a.id] == name then
			local t = toggles[a.toggle]
			if t and not t.Get() then t.Set(true) end
			return
		end
	end
	if name == Binds.Menu or name == Binds.Zoom or name == Binds.ClickTP or name == Binds.FlyBoost then return end
	local ok = okVIM and pcall(function()
		VIM:SendKeyEvent(true, kc, false, game)
		task.wait(0.05)
		VIM:SendKeyEvent(false, kc, false, game)
	end)
	if not ok and not vimWarned then
		vimWarned = true
		notify("Auto: this key can't be simulated here. Bind it to a menu action", 4)
	end
end

function runAutoSpawn()
	task.spawn(function()
		task.wait(AutoCfg.Delay)
		if not running or not getHumanoid() then return end
		for _, a in ipairs(Auto) do
			if a.On and not a.Removed and a.Mode == "Spawn" then pressKey(a.Key) end
		end
	end)
end

task.spawn(function()
	while running do
		task.wait(math.max(AutoCfg.Interval, 50) / 1000)
		if not loading and getHumanoid() then
			for _, a in ipairs(Auto) do
				if a.On and not a.Removed and a.Mode == "Always" then pressKey(a.Key) end
			end
		end
	end
end)

local function makeAuto(i)
	local a = { On = false, Mode = "Spawn", Key = "None", Removed = false }
	Auto[i] = a
	local g = addGroup(pageAuto, "Auto " .. i, false, 100 + i)
	g.Label.Size = UDim2.new(1, -150, 1, 0)

	local function retitle()
		g.Label.Text = string.format("Auto %d   ·   %s   ·   %s", i, a.Mode, a.Key == "None" and "no key" or a.Key)
	end

	local track = new("TextButton", {
		Size = UDim2.fromOffset(36, 18),
		Position = UDim2.new(1, -48, 0.5, -9),
		BackgroundColor3 = Theme.Off,
		Text = "",
		AutoButtonColor = false,
		BorderSizePixel = 0,
	}, g.Header)
	corner(track, 9)
	local knob = new("Frame", {
		Size = UDim2.fromOffset(12, 12),
		Position = UDim2.fromOffset(3, 3),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
	}, track)
	corner(knob, 6)
	local function setOn(v)
		if a.Removed then v = false end
		a.On = v and true or false
		tween(track, 0.15, { BackgroundColor3 = a.On and Theme.Accent or Theme.Off })
		tween(knob, 0.15, { Position = a.On and UDim2.fromOffset(21, 3) or UDim2.fromOffset(3, 3) })
		changed()
	end
	track.MouseButton1Click:Connect(function() setOn(not a.On) end)
	registry["Auto " .. i] = { get = function() return a.On end, set = setOn }

	local del = new("TextButton", {
		Size = UDim2.fromOffset(26, 22),
		Position = UDim2.new(1, -84, 0.5, -11),
		BackgroundColor3 = Theme.Panel,
		Text = "×",
		Font = Enum.Font.GothamBold,
		TextSize = 15,
		TextColor3 = Color3.fromRGB(232, 96, 110),
		AutoButtonColor = false,
		BorderSizePixel = 0,
	}, g.Header)
	corner(del, 6)
	outline(del)
	local function removeAuto()
		if a.Removed then return end
		a.Removed = true
		a.On = false
		g.Holder:Destroy()
		if not loading then notify("Auto " .. i .. " removed") end
		changed()
	end
	del.MouseButton1Click:Connect(removeAuto)
	registry["Auto " .. i .. " removed"] = {
		get = function() return a.Removed == true end,
		set = function(v) if v == true then removeAuto() end end,
	}

	local row = baseRow(g.Body, 38)
	local modeHolder = new("Frame", {
		Position = UDim2.fromOffset(8, 8),
		Size = UDim2.fromOffset(150, 22),
		BackgroundColor3 = Theme.Bg,
		BorderSizePixel = 0,
	}, row)
	corner(modeHolder, 6)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal }, modeHolder)
	local modeBtns = {}
	local function setMode(m)
		if not modeBtns[m] then return end
		a.Mode = m
		for n, b in pairs(modeBtns) do
			local active = n == m
			b.BackgroundTransparency = active and 0 or 1
			b.TextColor3 = active and Color3.new(1, 1, 1) or Theme.SubText
		end
		retitle()
		changed()
	end
	for _, m in ipairs({ "Spawn", "Always" }) do
		local b = new("TextButton", {
			Size = UDim2.new(0.5, 0, 1, 0),
			BackgroundColor3 = Theme.Accent,
			Text = m,
			Font = Enum.Font.GothamMedium,
			TextSize = 12,
			AutoButtonColor = false,
			BorderSizePixel = 0,
		}, modeHolder)
		corner(b, 6)
		modeBtns[m] = b
		b.MouseButton1Click:Connect(function() setMode(m) end)
	end
	registry["Auto " .. i .. " mode"] = { get = function() return a.Mode end, set = setMode }

	local keyBtn = new("TextButton", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -8, 0.5, 0),
		Size = UDim2.fromOffset(110, 24),
		BackgroundColor3 = Theme.Bg,
		Font = Enum.Font.GothamMedium,
		TextSize = 12,
		TextColor3 = Theme.Text,
		AutoButtonColor = false,
		BorderSizePixel = 0,
		Text = "",
	}, row)
	corner(keyBtn, 6)
	outline(keyBtn)
	local function renderKey(listening)
		if listening then
			keyBtn.Text = "Press a key..."
			keyBtn.TextColor3 = Theme.Accent
		else
			keyBtn.Text = a.Key
			keyBtn.TextColor3 = a.Key == "None" and Theme.SubText or Theme.Text
		end
	end
	local function setKey(v)
		if v ~= "None" and not toKey(v) then v = "None" end
		a.Key = v
		renderKey(false)
		retitle()
		changed()
	end
	keyBtn.MouseButton1Click:Connect(function()
		if captureReset then captureReset() end
		renderKey(true)
		captureReset = function() renderKey(false) end
		captureFn = function(k)
			captureReset = nil
			if k == Enum.KeyCode.Escape then
				renderKey(false)
			elseif k == Enum.KeyCode.Backspace then
				setKey("None")
			else
				setKey(k.Name)
			end
		end
	end)
	registry["Key: Auto " .. i .. " key"] = { get = function() return a.Key end, set = setKey }

	setMode("Spawn")
	renderKey(false)
	retitle()
end

registry.AutoCount = {
	get = function() return #Auto end,
	set = function(n)
		n = math.clamp(math.floor(tonumber(n) or 3), 1, 40)
		while #Auto < n do makeAuto(#Auto + 1) end
	end,
}

addSection(pageAuto, "Auto click")
toggles.AutoClick = addToggle(pageAuto, "Auto click", false, function(v) State.AutoClick = v end,
	"Clicks in the game itself (works without a Tool)")
addSlider(pageAuto, "Clicks per second", 1, 30, State.ClickCPS, function(v) State.ClickCPS = v end)

local timingGroup = addGroup(pageAuto, "Timing", false, 10)
addSlider(timingGroup.Body, "Spawn delay", 0, 10, AutoCfg.Delay, function(v) AutoCfg.Delay = v end, " s")
addSlider(timingGroup.Body, "Repeat interval", 50, 5000, AutoCfg.Interval, function(v) AutoCfg.Interval = v end, " ms")

addSection(pageAuto, "Auto buttons (Spawn: once after respawn  ·  Always: repeats)").LayoutOrder = 50
for i = 1, 3 do makeAuto(i) end

local addAutoBtn = addButton(pageAuto, "+   Add auto button", function()
	if activeAutoCount() >= AUTO_MAX then
		notify("Maximum " .. AUTO_MAX .. " auto buttons")
		return
	end
	if #Auto >= 40 then
		notify("Too many buttons were created, rejoin to reset")
		return
	end
	makeAuto(#Auto + 1)
	changed()
end)
addAutoBtn.LayoutOrder = 1000
end -- BLOCK

-- RECORDER
local Rec = {
	slots = {}, slot = 1, recSlot = 1,
	recording = false, playing = false,
	held = {}, hooked = {}, playT = 0, playDur = 0,
}
do -- BLOCK
local REC_MAX, REC_STEP = 120, 1 / 30
local REC_SKIP = {
	W = true, A = true, S = true, D = true, Space = true,
	Up = true, Down = true, Left = true, Right = true, Escape = true,
}
local recConns = {}
local recBtn, playBtn, setRecStatus, setSlotInfo
local stopPlaying

local function slotText(i)
	local d = Rec.slots[i]
	if not d then return "empty" end
	return string.format("%.1f s, %d actions", d.dur, #d.events)
end

local function refreshRec()
	if not recBtn then return end
	recBtn.Text = Rec.recording and "Stop recording" or "Start recording"
	playBtn.Text = Rec.playing and "Stop replay" or "Play slot"
	setSlotInfo(slotText(Rec.slot))
end

local function r3(v) return math.floor(v * 1000 + 0.5) / 1000 end

local function encodeRec(d)
	local s = table.create(#d.samples * 16)
	local n = 0
	local function put(v)
		n += 1
		s[n] = r3(v)
	end
	for _, p in ipairs(d.samples) do
		put(p.t)
		local pos = p.cf.Position
		put(pos.X) put(pos.Y) put(pos.Z)
		local rx, ry, rz = p.cf:ToOrientation()
		put(rx) put(ry) put(rz)
		local cpos = p.cam.Position
		put(cpos.X) put(cpos.Y) put(cpos.Z)
		local cx, cy, cz = p.cam:ToOrientation()
		put(cx) put(cy) put(cz)
		put(p.dir.X) put(p.dir.Z)
		put(p.air and 1 or 0)
	end
	local ev = {}
	for i, e in ipairs(d.events) do
		ev[i] = { t = r3(e.t), k = e.k, n = e.n and string.sub(e.n, 1, 60) or nil, d = e.d }
	end
	return { s = s, e = ev }
end

local function decodeRec(data)
	if type(data) ~= "table" or type(data.s) ~= "table" or type(data.e) ~= "table" then return nil end
	local s, samples = data.s, {}
	for i = 1, #s - 15, 16 do
		samples[#samples + 1] = {
			t = s[i],
			cf = CFrame.new(s[i + 1], s[i + 2], s[i + 3]) * CFrame.fromOrientation(s[i + 4], s[i + 5], s[i + 6]),
			cam = CFrame.new(s[i + 7], s[i + 8], s[i + 9]) * CFrame.fromOrientation(s[i + 10], s[i + 11], s[i + 12]),
			dir = Vector3.new(s[i + 13], 0, s[i + 14]),
			air = s[i + 15] == 1,
		}
	end
	if #samples < 2 then return nil end
	local events = {}
	for _, e in ipairs(data.e) do
		if type(e) == "table" and type(e.t) == "number" and type(e.k) == "string" then
			table.insert(events, {
				t = e.t, k = e.k,
				n = type(e.n) == "string" and e.n or nil,
				d = e.d == true,
			})
		end
	end
	return { samples = samples, events = events, dur = samples[#samples].t }
end

local cloudQueue, cloudWorking, lastCloud = {}, false, 0
local function cloudCall(action, payload)
	if not saveRemote then return end
	table.insert(cloudQueue, { action, payload })
	if cloudWorking then return end
	cloudWorking = true
	task.spawn(function()
		while #cloudQueue > 0 do
			local job = table.remove(cloudQueue, 1)
			local w = 3.2 - (os.clock() - lastCloud)
			if w > 0 then task.wait(w) end
			lastCloud = os.clock()
			local ok, res = pcall(saveRemote.InvokeServer, saveRemote, job[1], job[2])
			if not ok or res ~= true then notify("Cloud save failed", 3) end
		end
		cloudWorking = false
	end)
end

local function cloudSave(slot)
	local d = Rec.slots[slot]
	if not d then return end
	local p = encodeRec(d)
	p.slot = slot
	cloudCall("recSave", p)
end

local function cloudClear(slot)
	cloudCall("recClear", { slot = slot })
end

local function recDisconnect()
	for _, c in ipairs(recConns) do c:Disconnect() end
	table.clear(recConns)
	table.clear(Rec.hooked)
end

local function hookTool(tool)
	if Rec.hooked[tool] then return end
	Rec.hooked[tool] = true
	table.insert(recConns, tool.Activated:Connect(function()
		if Rec.recording then
			table.insert(Rec.data.events, { t = os.clock() - Rec.t0, k = "act" })
		end
	end))
end

local function stopRecording()
	if not Rec.recording then return end
	Rec.recording = false
	recDisconnect()
	local d = Rec.data
	if #d.samples < 2 then
		notify("Recording too short")
		refreshRec()
		return
	end
	d.dur = d.samples[#d.samples].t
	Rec.slots[Rec.recSlot] = d
	notify(string.format("Saved to slot %d (%.1f s)", Rec.recSlot, d.dur), 2.5)
	cloudSave(Rec.recSlot)
	refreshRec()
end

local function startRecording()
	if Rec.playing then stopPlaying() end
	local char = player.Character
	if not char or not getRoot() or not getHumanoid() then
		notify("No character")
		return
	end
	Rec.data = { samples = {}, events = {}, dur = 0 }
	Rec.toolName = nil
	Rec.lastT = -1
	Rec.recSlot = Rec.slot
	Rec.t0 = os.clock()
	Rec.recording = true

	for _, c in ipairs(char:GetChildren()) do
		if c:IsA("Tool") then hookTool(c) end
	end
	table.insert(recConns, char.ChildAdded:Connect(function(c)
		if c:IsA("Tool") then hookTool(c) end
	end))
	notify("Recording... do your moves", 2.5)
	refreshRec()
end

connect(RunService.Heartbeat, function()
	if not Rec.recording then return end
	local hum, root = getHumanoid(), getRoot()
	if not hum or not root then return end
	local now = os.clock() - Rec.t0
	if now >= REC_MAX then
		stopRecording()
		return
	end
	if now - Rec.lastT < REC_STEP then return end
	Rec.lastT = now
	local d = Rec.data
	table.insert(d.samples, {
		t = now,
		cf = root.CFrame,
		cam = camera.CFrame,
		dir = hum.MoveDirection,
		air = hum.FloorMaterial == Enum.Material.Air,
	})
	local tool = player.Character:FindFirstChildOfClass("Tool")
	local tn = tool and tool.Name or ""
	if tn ~= Rec.toolName then
		Rec.toolName = tn
		table.insert(d.events, { t = now, k = "tool", n = tn })
	end
end)

local function recKey(input, down)
	if not Rec.recording or not State.RecKeys then return end
	if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
	if captureFn or UIS:GetFocusedTextBox() then return end
	local name = input.KeyCode.Name
	if input.KeyCode == Enum.KeyCode.Unknown or REC_SKIP[name] then return end
	for _, v in pairs(Binds) do
		if v == name then return end
	end
	table.insert(Rec.data.events, { t = os.clock() - Rec.t0, k = "key", n = name, d = down })
end
connect(UIS.InputBegan, function(input) recKey(input, true) end)
connect(UIS.InputEnded, function(input) recKey(input, false) end)

local function sendKey(name, down)
	local kc = toKey(name)
	if not kc or not okVIM then return false end
	return (pcall(function() VIM:SendKeyEvent(down, kc, false, game) end))
end

local function releaseHeld()
	for name in pairs(Rec.held) do sendKey(name, false) end
	table.clear(Rec.held)
end

local function fireEvent(e)
	local char, hum = player.Character, getHumanoid()
	if not char or not hum then return end
	if e.k == "tool" then
		if e.n == nil or e.n == "" then
			hum:UnequipTools()
		else
			local cur = char:FindFirstChildOfClass("Tool")
			if not cur or cur.Name ~= e.n then
				local tool = player.Backpack:FindFirstChild(e.n)
				if tool and tool:IsA("Tool") then hum:EquipTool(tool) end
			end
		end
	elseif e.k == "act" then
		local tool = char:FindFirstChildOfClass("Tool")
		if tool then tool:Activate() end
	elseif e.k == "key" and e.n then
		if sendKey(e.n, e.d) then
			Rec.held[e.n] = e.d or nil
		elseif not Rec.warned then
			Rec.warned = true
			notify("Game blocks simulated keys", 4)
		end
	end
end

stopPlaying = function()
	if not Rec.playing then return end
	Rec.playing = false
	pcall(function() RunService:UnbindFromRenderStep("CheatSimPlay") end)
	releaseHeld()
	local hum, root = getHumanoid(), getRoot()
	if hum then
		hum:Move(Vector3.zero, false)
		hum.Jump = false
	end
	if root then root.AssemblyLinearVelocity = Vector3.zero end
	refreshRec()
end

local function startPlaying()
	if Rec.recording then stopRecording() end
	if Rec.playing then return end
	local d = Rec.slots[Rec.slot]
	if not d then
		notify("This slot is empty")
		return
	end
	if not getRoot() or not getHumanoid() then return end
	if State.Fly and toggles.Fly then toggles.Fly.Set(false) end
	if State.Freecam and toggles.Freecam then toggles.Freecam.Set(false) end

	local samples, events = d.samples, d.events
	local rel, t, si, ei, pauseLeft = CFrame.identity, 0, 1, 1, 0

	local function restart()
		releaseHeld()
		t, si, ei = 0, 1, 1
		local root = getRoot()
		if State.RecStart or not root then
			rel = CFrame.identity
		else
			rel = root.CFrame * samples[1].cf:Inverse()
		end
	end
	restart()

	Rec.playing = true
	Rec.playDur = d.dur
	Rec.playT = 0
	refreshRec()
	notify("Replay started")

	pcall(function() RunService:UnbindFromRenderStep("CheatSimPlay") end)
	RunService:BindToRenderStep("CheatSimPlay", Enum.RenderPriority.Camera.Value + 2, function(dt)
		local root, hum = getRoot(), getHumanoid()
		if not root or not hum or hum.Health <= 0 then
			stopPlaying()
			return
		end

		if pauseLeft > 0 then
			pauseLeft -= dt
			hum:Move(Vector3.zero, false)
			if pauseLeft <= 0 then restart() end
			return
		end

		t += dt * State.RecSpeed / 100
		Rec.playT = t
		while samples[si + 1] and samples[si + 1].t <= t do si += 1 end
		while events[ei] and events[ei].t <= t do
			fireEvent(events[ei])
			ei += 1
		end

		local a, b = samples[si], samples[si + 1]
		if not b then
			hum:Move(Vector3.zero, false)
			if State.RecLoop then
				if State.RecPause > 0 then
					pauseLeft = State.RecPause
				else
					restart()
				end
			else
				stopPlaying()
				notify("Replay finished")
			end
			return
		end

		local alpha = math.clamp((t - a.t) / math.max(b.t - a.t, 1e-4), 0, 1)
		root.CFrame = rel * a.cf:Lerp(b.cf, alpha)
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
		hum:Move(rel:VectorToWorldSpace(a.dir), false)
		hum.Jump = a.air
		if State.RecCam then camera.CFrame = rel * a.cam:Lerp(b.cam, alpha) end
	end)
end

task.spawn(function()
	while running do
		if setRecStatus then
			if Rec.recording then
				setRecStatus(string.format("Recording  %.1f s", os.clock() - Rec.t0))
			elseif Rec.playing then
				setRecStatus(string.format("Playing  %.1f / %.1f s", Rec.playT, Rec.playDur))
			else
				setRecStatus("Idle")
			end
		end
		task.wait(0.2)
	end
end)

addSection(pageRec, "Movement recorder")
setRecStatus = addInfo(pageRec, "Status")
addSegmented(pageRec, "Slot", { "1", "2", "3" }, "1", function(v)
	Rec.slot = tonumber(v) or 1
	refreshRec()
end)
setSlotInfo = addInfo(pageRec, "In this slot")
recBtn = addButton(pageRec, "Start recording", function()
	if Rec.recording then stopRecording() else startRecording() end
end)
playBtn = addButton(pageRec, "Play slot", function()
	if Rec.playing then stopPlaying() else startPlaying() end
end)
addButton(pageRec, "Clear slot", function()
	local s = Rec.slot
	if Rec.slots[s] then
		Rec.slots[s] = nil
		cloudClear(s)
		notify("Slot " .. s .. " cleared")
	end
	refreshRec()
end)

local recOpts = addGroup(pageRec, "Replay options", true)
addToggle(recOpts.Body, "Loop replay", true, function(v) State.RecLoop = v end, "Repeat until you stop it")
addSlider(recOpts.Body, "Loop pause", 0, 10, State.RecPause, function(v) State.RecPause = v end, " s")
addSlider(recOpts.Body, "Replay speed", 25, 300, State.RecSpeed, function(v) State.RecSpeed = v end, " %")
addToggle(recOpts.Body, "Start from recorded place", true, function(v) State.RecStart = v end, "Off = replay from where you stand")
addToggle(recOpts.Body, "Replay camera", true, function(v) State.RecCam = v end, "Camera follows the recorded view")
addToggle(recOpts.Body, "Record key presses", true, function(v) State.RecKeys = v end, "Ability keys (other than WASD / Space)")
refreshRec()

Rec.stopRecording = stopRecording
Rec.startRecording = startRecording
Rec.stopPlaying = stopPlaying
Rec.startPlaying = startPlaying
Rec.refresh = refreshRec
Rec.decode = decodeRec
Rec.disconnect = recDisconnect
end -- BLOCK

-- GLOBAL CHAT (public relay ntfy.sh, anonymous by default)
do -- BLOCK
local httpReq = (syn and syn.request) or http_request or request or (http and http.request) or (fluxus and fluxus.request)
local WSConnect = WebSocket and WebSocket.connect
local BASE = "https://ntfy.sh/"
local mySid = string.sub(HttpService:GenerateGUID(false), 1, 8)
local anonName = "Anon" .. math.random(1000, 9999)
local cfg = { On = false, Anon = true, Nick = "", Room = "global", Popups = true }

local seen, lastId = {}, nil
local chatToken, ws = 0, nil
local restartToken = 0
local msgCount = 0
local list, setStatus
local lastSend = 0

local function esc(s)
	s = tostring(s)
	s = s:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub("\"", "&quot;"):gsub("'", "&apos;")
	return s
end

local function hexOf(c)
	return string.format("#%02X%02X%02X",
		math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5))
end

local function nameColor(name)
	local h = 0
	for i = 1, #name do h = (h * 31 + string.byte(name, i)) % 360 end
	return Color3.fromHSV(h / 360, 0.5, 1)
end

local function topic()
	local r = string.lower(cfg.Room):gsub("[^%w_%-]", "")
	if r == "" then r = "global" end
	return "cheatmenu-" .. string.sub(r, 1, 40)
end

local function myAlias()
	if cfg.Anon then return anonName end
	local n = tostring(cfg.Nick):gsub("^%s+", ""):gsub("%s+$", "")
	if n == "" then n = player.DisplayName end
	return string.sub(n, 1, 20)
end

local function addMessage(who, text, mine)
	if not list then return end
	msgCount += 1
	local col = mine and Theme.Accent or nameColor(who)
	new("TextLabel", {
		Size = UDim2.new(1, -6, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		RichText = true,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Font = Enum.Font.GothamMedium,
		TextSize = 12,
		TextColor3 = Theme.Text,
		Text = string.format("<font color=\"%s\"><b>%s</b></font>  %s", hexOf(col), esc(who), esc(text)),
		LayoutOrder = msgCount,
	}, list)

	local labels = {}
	for _, c in ipairs(list:GetChildren()) do
		if c:IsA("TextLabel") then labels[#labels + 1] = c end
	end
	if #labels > 80 then
		table.sort(labels, function(a, b) return a.LayoutOrder < b.LayoutOrder end)
		labels[1]:Destroy()
	end
	task.defer(function()
		if list and list.Parent then list.CanvasPosition = Vector2.new(0, 1e6) end
	end)

	if not mine and cfg.Popups and (not main.Visible or currentTab ~= "Chat") then
		notify(string.sub(who .. ": " .. text, 1, 48), 3)
	end
end

local function handleLine(line)
	local ok, m = pcall(HttpService.JSONDecode, HttpService, line)
	if not ok or type(m) ~= "table" or m.event ~= "message" then return end
	if m.id then
		if seen[m.id] then return end
		seen[m.id] = true
		lastId = m.id
	end
	local ok2, d = pcall(HttpService.JSONDecode, HttpService, tostring(m.message or ""))
	if not ok2 or type(d) ~= "table" or type(d.t) ~= "string" or type(d.u) ~= "string" then return end
	if d.s == mySid then return end
	addMessage(string.sub(d.u, 1, 24), string.sub(d.t, 1, 200), false)
end

local function stopChat()
	chatToken += 1
	if ws then
		pcall(function() ws:Close() end)
		ws = nil
	end
	if setStatus then setStatus("Off") end
end

local function startChat()
	stopChat()
	if not httpReq and not WSConnect then
		if setStatus then setStatus("No HTTP in this executor") end
		notify("Chat: this executor has no HTTP / WebSocket support", 4)
		return
	end
	local my = chatToken
	local tp = topic()
	lastId = nil
	task.spawn(function()
		local wsFails = 0
		if setStatus then setStatus("Connecting...") end
		while running and cfg.On and my == chatToken do
			local usedWs = false
			if WSConnect and wsFails < 3 then
				local ok, sock = pcall(WSConnect, "wss://ntfy.sh/" .. tp .. "/ws?since=" .. (lastId or "5m"))
				if ok and sock then
					usedWs = true
					wsFails = 0
					ws = sock
					local closed = false
					sock.OnMessage:Connect(function(raw)
						if my == chatToken then handleLine(raw) end
					end)
					sock.OnClose:Connect(function() closed = true end)
					if setStatus then setStatus("Online (live)") end
					while running and cfg.On and my == chatToken and not closed do task.wait(0.5) end
					pcall(function() sock:Close() end)
					if ws == sock then ws = nil end
				else
					wsFails += 1
				end
			end
			if not usedWs and httpReq and running and cfg.On and my == chatToken then
				local ok, res = pcall(httpReq, {
					Url = BASE .. tp .. "/json?poll=1&since=" .. (lastId or "5m"),
					Method = "GET",
				})
				if ok and res and res.StatusCode == 200 and res.Body then
					for line in tostring(res.Body):gmatch("[^\n]+") do handleLine(line) end
					if setStatus then setStatus("Online (checking every 6 s)") end
					task.wait(6)
				elseif ok and res and res.StatusCode == 429 then
					if setStatus then setStatus("Too many requests, waiting...") end
					task.wait(20)
				else
					if setStatus then setStatus("No connection, retrying...") end
					task.wait(8)
				end
			elseif not usedWs then
				task.wait(3)
			else
				task.wait(2)
			end
		end
	end)
end

local function scheduleRestart()
	restartToken += 1
	local my = restartToken
	task.delay(0.6, function()
		if my ~= restartToken or not running then return end
		if cfg.On then startChat() else stopChat() end
	end)
end

local function sendMessage(text)
	text = tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", "")
	if text == "" then return end
	if not cfg.On then
		notify("Turn on Global chat first", 2.5)
		return
	end
	if os.clock() - lastSend < 2 then
		notify("Slow down a little", 1.5)
		return
	end
	if #text > 200 then text = string.sub(text, 1, 200) end
	lastSend = os.clock()
	local alias = myAlias()
	addMessage(alias, text, true)
	local payload = HttpService:JSONEncode({ s = mySid, u = alias, t = text })
	task.spawn(function()
		if not httpReq then
			notify("Chat: sending needs HTTP support", 3)
			return
		end
		local ok, res = pcall(httpReq, {
			Url = BASE .. topic(),
			Method = "POST",
			Headers = { ["Content-Type"] = "text/plain" },
			Body = payload,
		})
		if not ok or (res and res.StatusCode and res.StatusCode >= 400) then
			notify("Chat: message was not sent", 3)
		end
	end)
end

addSection(pageChat, "Global chat")
local noteRow = baseRow(pageChat, 48)
new("TextLabel", {
	BackgroundTransparency = 1,
	Position = UDim2.fromOffset(12, 4),
	Size = UDim2.new(1, -24, 1, -8),
	Text = "Public chat of everyone who uses this script in the same room. Anyone can read it, so never share personal data.",
	TextWrapped = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Center,
	Font = Enum.Font.Gotham,
	TextSize = 11,
	TextColor3 = Theme.SubText,
}, noteRow)

toggles.Chat = addToggle(pageChat, "Global chat", false, function(v)
	cfg.On = v
	scheduleRestart()
end, "Join the chat (off = nothing is sent or received)")
setStatus = addInfo(pageChat, "Status")
setStatus("Off")
toggles.ChatAnon = addToggle(pageChat, "Chat anonymous", true, function(v) cfg.Anon = v end,
	"Appear as a random Anon name, hide your Roblox name")
addInput(pageChat, "Chat nickname", "", function(v) cfg.Nick = v end, "Used if not anonymous")
addInput(pageChat, "Chat room", "global", function(v)
	local r = tostring(v)
	if r ~= cfg.Room then
		cfg.Room = r
		if cfg.On then scheduleRestart() end
	end
end, "Same name = same room")
toggles.ChatPopups = addToggle(pageChat, "Chat popups", true, function(v) cfg.Popups = v end,
	"Show new messages as notifications while the chat is closed")

addSection(pageChat, "Messages")
local logRow = baseRow(pageChat, 230)
list = new("ScrollingFrame", {
	Position = UDim2.fromOffset(8, 8),
	Size = UDim2.new(1, -16, 1, -16),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ScrollBarThickness = 3,
	ScrollBarImageColor3 = Theme.Off,
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	CanvasSize = UDim2.new(),
}, logRow)
new("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, list)

local sendRow = baseRow(pageChat, 36)
local msgBox = new("TextBox", {
	Position = UDim2.fromOffset(8, 6),
	Size = UDim2.new(1, -86, 0, 24),
	BackgroundColor3 = Theme.Bg,
	Text = "",
	PlaceholderText = "Write a message...",
	PlaceholderColor3 = Theme.SubText,
	TextColor3 = Theme.Text,
	Font = Enum.Font.GothamMedium,
	TextSize = 12,
	TextXAlignment = Enum.TextXAlignment.Left,
	ClearTextOnFocus = false,
	BorderSizePixel = 0,
}, sendRow)
corner(msgBox, 6)
outline(msgBox)
new("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6) }, msgBox)
local sendBtn = new("TextButton", {
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -8, 0, 6),
	Size = UDim2.fromOffset(66, 24),
	BackgroundColor3 = Theme.Accent,
	Text = "Send",
	Font = Enum.Font.GothamBold,
	TextSize = 12,
	TextColor3 = Color3.new(1, 1, 1),
	AutoButtonColor = false,
	BorderSizePixel = 0,
}, sendRow)
corner(sendBtn, 6)
local function doSend()
	local t = msgBox.Text
	msgBox.Text = ""
	sendMessage(t)
end
sendBtn.MouseButton1Click:Connect(doSend)
msgBox.FocusLost:Connect(function(enter)
	if enter then doSend() end
end)

addButton(pageChat, "Clear chat window", function()
	for _, c in ipairs(list:GetChildren()) do
		if c:IsA("TextLabel") then c:Destroy() end
	end
end)

table.insert(Ext.cleanup, stopChat)
end -- BLOCK

-- Settings
local function snapshot()
	local data = {}
	for name, c in pairs(registry) do
		if not Ext.noSave[name] then data[name] = c.get() end
	end
	return data
end

local function unload()
	running = false
	for k, v in pairs(State) do
		if type(v) == "boolean" then State[k] = false end
	end
	Rec.recording = false
	Rec.disconnect()
	Rec.stopPlaying()
	local hum = getHumanoid()
	if hum then
		hum.WalkSpeed = Defaults.WalkSpeed
		hum.JumpPower = Defaults.JumpPower
		camera.CameraSubject = hum
	end
	noStunStates(false)
	applyHideGui()
	restoreNoclip()
	stopFly()
	stopFreecam()
	syncESP()
	applyWorld()
	applyGravity()
	applyZoomUnlock()
	for _, f in ipairs(Ext.cleanup) do pcall(f) end
	UIS.MouseIconEnabled = originalMouseIcon
	if saveRemote and canSave then pcall(saveRemote.InvokeServer, saveRemote, "save", snapshot()) end
	pcall(function() RunService:UnbindFromRenderStep("CheatSimMain") end)
	for _, c in ipairs(connections) do c:Disconnect() end
	gui:Destroy()
	if env.ForgottenUnload == unload then env.ForgottenUnload = nil end
end
env.ForgottenUnload = unload

do -- BLOCK
-- menu background: solid color or a two-color gradient
local bgC1, bgC2 = Theme.Bg, Color3.fromRGB(34, 22, 66)
local function applyBg()
	if State.BgGrad then
		main.BackgroundColor3 = Color3.new(1, 1, 1)
		local m = math.clamp(State.BgMid / 100, 0, 1)
		local w = math.clamp(State.BgSoft / 100, 0, 1)
		local a = math.clamp(m - w / 2, 0.001, 0.997)
		local b = math.clamp(m + w / 2, a + 0.001, 0.999)
		bgGrad.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, bgC1),
			ColorSequenceKeypoint.new(a, bgC1),
			ColorSequenceKeypoint.new(b, bgC2),
			ColorSequenceKeypoint.new(1, bgC2),
		})
		bgGrad.Rotation = State.BgAngle
		bgGrad.Enabled = true
	else
		bgGrad.Enabled = false
		main.BackgroundColor3 = bgC1
	end
end

local appearance = addGroup(pageSettings, "Appearance", true)

-- hide the name and the dot in the title bar
addToggle(appearance.Body, "Hide title and dot", false, function(v)
	State.TitleHide = v
	Ext.title.dot.Visible = not v
	Ext.title.label.Visible = not v
end, "Removes the name and the dot from the title bar")

local bgToggle = addToggle(appearance.Body, "Gradient background", false, function(v)
	State.BgGrad = v
	applyBg()
end, "Two-color gradient behind the menu")
addSlider(appearance.Body, "Gradient angle", 0, 360, State.BgAngle, function(v)
	State.BgAngle = v
	applyBg()
end, "°")
addSlider(appearance.Body, "Color 1 share", 0, 100, State.BgMid, function(v)
	State.BgMid = v
	applyBg()
end, " %")
addSlider(appearance.Body, "Blend softness", 0, 100, State.BgSoft, function(v)
	State.BgSoft = v
	applyBg()
end, " %")
local pick1 = addColor(appearance.Body, "Background color 1", bgC1, function(c)
	bgC1 = c
	applyBg()
end)
local pick2 = addColor(appearance.Body, "Background color 2", bgC2, function(c)
	bgC2 = c
	applyBg()
end)
addColor(appearance.Body, "Accent color", Theme.Accent, applyAccent)

-- FONTS
local fontOrig = setmetatable({}, { __mode = "k" })
local faceCache = {}

local function getFace(name, bold)
	local key = name .. (bold and "|B" or "")
	local f = faceCache[key]
	if f == nil then
		f = false
		local ok, en = pcall(function() return Enum.Font[name] end)
		if ok and en then
			local ok2, ff = pcall(Font.fromEnum, en)
			if ok2 then f = ff end
		end
		if not f then
			local ok3, ff = pcall(Font.fromName, name, bold and Enum.FontWeight.Bold or Enum.FontWeight.Regular)
			if ok3 then f = ff end
		end
		faceCache[key] = f
	end
	return f or nil
end

local function isText(o)
	return o:IsA("TextLabel") or o:IsA("TextButton") or o:IsA("TextBox")
end

local function inMenu(o)
	return o:IsDescendantOf(gui)
end

local function setFace(o, name)
	if not isText(o) then return end
	local orig = fontOrig[o]
	if orig == nil then
		orig = o.FontFace
		fontOrig[o] = orig
	end
	if name == "Default" then
		o.FontFace = orig
		return
	end
	local face = getFace(name, orig.Weight.Value >= 700)
	o.FontFace = face or orig
end

local function menuFontName()
	return State.MenuFont == "Gotham" and "Default" or State.MenuFont
end

local function applyMenuFont()
	for _, o in ipairs(gui:GetDescendants()) do
		if isText(o) then setFace(o, menuFontName()) end
	end
end
connect(gui.DescendantAdded, function(o)
	if isText(o) and State.MenuFont ~= "Gotham" then setFace(o, menuFontName()) end
end)

local gameFontToken = 0
function Ext.applyGameFont()
	gameFontToken += 1
	local my = gameFontToken
	task.spawn(function()
		local name = State.GameFont
		local roots = { workspace }
		local pg = player:FindFirstChildOfClass("PlayerGui")
		if pg then table.insert(roots, pg) end
		local n = 0
		for _, root in ipairs(roots) do
			for _, o in ipairs(root:GetDescendants()) do
				if my ~= gameFontToken then return end
				if isText(o) and not inMenu(o) then
					if name == "Default" then
						if fontOrig[o] then setFace(o, "Default") end
					else
						setFace(o, name)
					end
				end
				n += 1
				if n % 2500 == 0 then task.wait() end
			end
		end
	end)
end

local function onNewGameText(o)
	if State.GameFont ~= "Default" and isText(o) and not inMenu(o) then
		setFace(o, State.GameFont)
	end
end
connect(workspace.DescendantAdded, onNewGameText)
do -- BLOCK
local pgui = player:FindFirstChildOfClass("PlayerGui")
if pgui then connect(pgui.DescendantAdded, onNewGameText) end
end -- BLOCK

table.insert(Ext.cleanup, function()
	gameFontToken += 1
	for o, orig in pairs(fontOrig) do
		if o.Parent and not inMenu(o) then pcall(function() o.FontFace = orig end) end
	end
end)

local MENU_FONTS = {
	"Gotham", "Fingerpaint", "Comfortaa",
	"Creepster", "Bangers", "PermanentMarker",
	"SciFi", "Code", "IndieFlower",
}
local GAME_FONTS = {
	"Default", "Gotham", "Fingerpaint",
	"Comfortaa", "Creepster", "Bangers",
	"PermanentMarker", "SciFi", "Code",
	"IndieFlower", "Fondamento", "Arcade",
}
addChoice(appearance.Body, "Menu font", MENU_FONTS, "Gotham", function(v)
	if State.MenuFont == v then return end
	State.MenuFont = v
	applyMenuFont()
end)
addChoice(appearance.Body, "Game font", GAME_FONTS, "Default", function(v)
	if State.GameFont == v then return end
	State.GameFont = v
	Ext.applyGameFont()
end)

-- BACKGROUND IMAGE (by asset ID)
local bgImage = new("ImageLabel", {
	Name = "BgImage",
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	Image = "",
	ScaleType = Enum.ScaleType.Crop,
	ImageTransparency = 0.4,
	ZIndex = 1,
	Visible = false,
}, main)
corner(bgImage, 10)
titleBar.ZIndex = 2
content.ZIndex = 2

local imgToken = 0
local FIT = { Crop = Enum.ScaleType.Crop, Fit = Enum.ScaleType.Fit, Stretch = Enum.ScaleType.Stretch }

local function applyBgImage(reload)
	bgImage.Visible = State.BgImg
	bgImage.ImageTransparency = 1 - State.BgImgOpacity / 100
	bgImage.ScaleType = FIT[State.BgImgFit] or Enum.ScaleType.Crop
	if not reload then return end

	imgToken += 1
	local token = imgToken
	local id = tostring(State.BgImgId):gsub("%D", "")
	bgImage.Image = ""
	if not State.BgImg or id == "" then return end

	task.spawn(function()
		for _, src in ipairs({ "rbxassetid://" .. id, "rbxthumb://type=Asset&id=" .. id .. "&w=420&h=420" }) do
			bgImage.Image = src
			pcall(function() ContentProvider:PreloadAsync({ bgImage }) end)
			if token ~= imgToken then return end
			if bgImage.IsLoaded then return end
		end
		bgImage.Image = ""
		notify("Background image failed to load. Check the ID", 3)
	end)
end

local panelObjs = setmetatable({}, { __mode = "k" })
local function isPanel(o)
	if not o:IsA("GuiObject") then return false end
	return sameColor(o.BackgroundColor3, Theme.Item) or sameColor(o.BackgroundColor3, Theme.ItemHover)
end
local function applyPanelAlpha()
	local a = State.PanelAlpha / 100
	for _, o in ipairs(pagesHolder:GetDescendants()) do
		if isPanel(o) and (panelObjs[o] or o.BackgroundTransparency < 0.99) then
			panelObjs[o] = true
			o.BackgroundTransparency = a
		end
	end
end
connect(pagesHolder.DescendantAdded, function(o)
	if State.PanelAlpha > 0 and isPanel(o) and o.BackgroundTransparency < 0.99 then
		panelObjs[o] = true
		o.BackgroundTransparency = State.PanelAlpha / 100
	end
end)

addToggle(appearance.Body, "Background image", false, function(v)
	State.BgImg = v
	applyBgImage(true)
end, "Shows your picture behind the menu (by ID)")
addInput(appearance.Body, "Background image ID", "", function(v)
	if v == State.BgImgId then return end
	State.BgImgId = v
	applyBgImage(true)
end, "Paste image ID")
addSlider(appearance.Body, "Image opacity", 10, 100, State.BgImgOpacity, function(v)
	State.BgImgOpacity = v
	applyBgImage(false)
end, " %")
addSegmented(appearance.Body, "Image fit", { "Crop", "Fit", "Stretch" }, "Crop", function(v)
	State.BgImgFit = v
	applyBgImage(false)
end)
addSlider(appearance.Body, "Panels transparency", 0, 80, State.PanelAlpha, function(v)
	State.PanelAlpha = v
	applyPanelAlpha()
end, " %")

local compactOn, scalePct = false, 100
local function applyScale()
	local s = (scalePct / 100) * (compactOn and 0.8 or 1)
	for _, sc in pairs(pageScales) do
		sc.scale.Scale = s
		sc.page.Size = UDim2.new(1 / s, 0, 1 / s, 0)
	end
end
addToggle(appearance.Body, "Compact mode", false, function(v)
	compactOn = v
	applyScale()
end, "Smaller controls, more on screen")
addSlider(appearance.Body, "Content scale", 60, 120, 100, function(v)
	scalePct = v
	applyScale()
end, " %")

local presets = {
	{ "Default", false, Color3.fromRGB(11, 11, 14), Color3.fromRGB(34, 22, 66) },
	{ "Midnight", true, Color3.fromRGB(12, 14, 32), Color3.fromRGB(40, 22, 74) },
	{ "Sunset", true, Color3.fromRGB(42, 14, 40), Color3.fromRGB(112, 50, 36) },
	{ "Ocean", true, Color3.fromRGB(8, 24, 40), Color3.fromRGB(14, 72, 86) },
	{ "Forest", true, Color3.fromRGB(10, 28, 20), Color3.fromRGB(30, 66, 46) },
}
local presetRow = baseRow(appearance.Body, 34)
new("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	Padding = UDim.new(0, 4),
	VerticalAlignment = Enum.VerticalAlignment.Center,
}, presetRow)
new("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6) }, presetRow)
for _, p in ipairs(presets) do
	local b = new("TextButton", {
		Size = UDim2.new(1 / #presets, -8, 0, 24),
		BackgroundColor3 = Theme.Panel,
		Text = p[1],
		Font = Enum.Font.GothamMedium,
		TextSize = 11,
		TextColor3 = Theme.Text,
		AutoButtonColor = false,
		BorderSizePixel = 0,
	}, presetRow)
	corner(b, 6)
	outline(b)
	b.MouseEnter:Connect(function() tween(b, 0.12, { BackgroundColor3 = Theme.ItemHover }) end)
	b.MouseLeave:Connect(function() tween(b, 0.12, { BackgroundColor3 = Theme.Panel }) end)
	b.MouseButton1Click:Connect(function()
		bgToggle.Set(p[2])
		pick1.Set(p[3])
		pick2.Set(p[4])
	end)
end

-- MUSIC
do -- BLOCK
local musicGrp = addGroup(pageSettings, "Music", false)
local SoundService = game:GetService("SoundService")
local snd = Instance.new("Sound")
snd.Name = "CheatSimMusic"
snd.Volume = State.MusicVol / 100
snd.PlaybackSpeed = State.MusicSpeed / 100
snd.Parent = SoundService

local playlist, idx, token = {}, 1, 0
local intent, startedAt = false, 0
local lastIds = ""

local function parseIds()
	table.clear(playlist)
	for id in tostring(State.MusicIds):gmatch("%d+") do table.insert(playlist, id) end
	if idx > #playlist then idx = 1 end
end

local function fmtT(s)
	s = math.max(0, math.floor(s or 0))
	return string.format("%d:%02d", s // 60, s % 60)
end

local function loadTrack(i)
	if #playlist == 0 then
		notify("Enter a music ID first", 2.5)
		return
	end
	idx = ((i - 1) % #playlist) + 1
	token += 1
	local my = token
	snd:Stop()
	snd.SoundId = "rbxassetid://" .. playlist[idx]
	snd.Looped = State.MusicRepeat == "One"
	snd.PlaybackSpeed = State.MusicSpeed / 100
	snd.TimePosition = 0
	snd:Play()
	intent, startedAt = true, os.clock()
	task.delay(6, function()
		if my == token and intent and not snd.IsLoaded then
			notify("Music failed to load. Check the ID", 3)
		end
	end)
end

local function nextIndex(step)
	if State.MusicShuffle and #playlist > 1 then
		local n
		repeat n = math.random(#playlist) until n ~= idx
		return n
	end
	return idx + step
end

local playBtn
local function togglePlay()
	if snd.IsPlaying then
		snd:Pause()
	elseif snd.IsPaused then
		snd:Resume()
		intent, startedAt = true, os.clock()
	else
		parseIds()
		loadTrack(idx)
	end
end

local row = baseRow(musicGrp.Body, 34)
new("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	Padding = UDim.new(0, 4),
	VerticalAlignment = Enum.VerticalAlignment.Center,
}, row)
new("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6) }, row)
local function mBtn(text, fn)
	local b = new("TextButton", {
		Size = UDim2.new(0.25, -4, 0, 24),
		BackgroundColor3 = Theme.Panel,
		Text = text,
		Font = Enum.Font.GothamMedium,
		TextSize = 12,
		TextColor3 = Theme.Text,
		AutoButtonColor = false,
		BorderSizePixel = 0,
	}, row)
	corner(b, 6)
	outline(b)
	b.MouseEnter:Connect(function() tween(b, 0.12, { BackgroundColor3 = Theme.ItemHover }) end)
	b.MouseLeave:Connect(function() tween(b, 0.12, { BackgroundColor3 = Theme.Panel }) end)
	b.MouseButton1Click:Connect(fn)
	return b
end

addInput(musicGrp.Body, "Music IDs", "", function(v)
	State.MusicIds = v
	parseIds()
	local key = table.concat(playlist, ",")
	if key ~= lastIds then
		lastIds = key
		if not loading and intent then loadTrack(1) end
	end
end, "ID or 123, 456")

mBtn("Prev", function()
	parseIds()
	loadTrack(nextIndex(-1))
end)
playBtn = mBtn("Play", togglePlay)
mBtn("Stop", function()
	intent = false
	token += 1
	snd:Stop()
end)
mBtn("Next", function()
	parseIds()
	loadTrack(nextIndex(1))
end)
row.LayoutOrder = nextOrder(musicGrp.Body)

local setNow = addInfo(musicGrp.Body, "Now playing")
addSlider(musicGrp.Body, "Music volume", 0, 100, State.MusicVol, function(v)
	State.MusicVol = v
	snd.Volume = v / 100
end, " %")
addSlider(musicGrp.Body, "Music speed", 50, 200, State.MusicSpeed, function(v)
	State.MusicSpeed = v
	snd.PlaybackSpeed = v / 100
end, " %")
addSegmented(musicGrp.Body, "Music repeat", { "Off", "One", "All" }, "Off", function(v)
	State.MusicRepeat = v
	snd.Looped = v == "One"
end)
addToggle(musicGrp.Body, "Music shuffle", false, function(v)
	State.MusicShuffle = v
end, "Random next track (list of IDs)")

task.spawn(function()
	while running do
		if intent and not snd.IsPlaying and not snd.IsPaused and snd.IsLoaded and os.clock() - startedAt > 1 then
			if State.MusicRepeat == "All" then
				loadTrack(nextIndex(1))
			elseif State.MusicRepeat == "Off" and idx < #playlist then
				loadTrack(idx + 1)
			else
				intent = false
			end
		end
		playBtn.Text = snd.IsPlaying and "Pause" or (snd.IsPaused and "Resume" or "Play")
		if #playlist == 0 then
			setNow("-")
		else
			setNow(string.format("%d/%d  %s / %s", idx, #playlist, fmtT(snd.TimePosition), fmtT(snd.TimeLength)))
		end
		task.wait(0.25)
	end
end)

table.insert(Ext.cleanup, function()
	intent = false
	pcall(function() snd:Stop() end)
	pcall(function() snd:Destroy() end)
end)
end -- BLOCK

local keybinds = addGroup(pageSettings, "Keybinds", false)
for _, b in ipairs(BindList) do
	addKeybind(keybinds.Body, b[2], Binds, b[1], BindDefaults[b[1]], b[1] == "Menu")
end
addButton(keybinds.Body, "Reset keybinds", function()
	for id in pairs(BindDefaults) do
		if id ~= "Menu" then bindSetters[id]("None") end
	end
	bindSetters.Menu(BindDefaults.Menu)
	for id, d in pairs(BindDefaults) do
		if id ~= "Menu" then bindSetters[id](d) end
	end
end)

local cursorGroup = addGroup(pageSettings, "Cursor", false)
toggles.Cursor = addToggle(cursorGroup.Body, "Custom cursor", false, function(v)
	State.Cursor = v
	applyCursor(true)
end, "Replaces the mouse cursor with your image")
addInput(cursorGroup.Body, "Cursor image ID", "", function(v)
	State.CursorId = v
	applyCursor(true)
end, "Paste image ID")
addSlider(cursorGroup.Body, "Cursor size", 12, 128, State.CursorSize, function(v)
	State.CursorSize = v
	applyCursor(false)
end, " px")
addSegmented(cursorGroup.Body, "Cursor anchor", { "Center", "Corner" }, "Center", function(v)
	State.CursorAnchor = v
	applyCursor(false)
end)

end -- BLOCK

addSection(pageSettings, "Session")
addButton(pageSettings, "Save settings now", function()
	if not saveRemote then notify("Save: storage is not ready", 3) return end
	if not canSave then notify("Save: load failed, see Output", 3) return end
	local ok = pcall(saveRemote.InvokeServer, saveRemote, "save", snapshot())
	local fok, wrote, err = pcall(saveRemote.InvokeServer, saveRemote, "flush")
	if ok and fok and wrote == true then
		notify("Settings saved", 2)
	else
		warn("[ForgottenScript] save failed: " .. tostring(err or wrote))
		notify("Save failed, see Output", 3)
	end
end)
addButton(pageSettings, "Reset character", function()
	local hum = getHumanoid()
	if hum then hum.Health = 0 end
end)
addButton(pageSettings, "Rejoin server", function()
	TeleportService:Teleport(game.PlaceId, player)
end)
addButton(pageSettings, "Unload menu", unload)

-- HALLOWEEN TAB (orange, last in the list)
do -- BLOCK
addSection(pageHalloween, "Auto farm")
local setFarm = addInfo(pageHalloween, "Farm status")
setFarm("Off")
Ext.Farm.setStatus = setFarm
toggles.FarmTween = addToggle(pageHalloween, "Auto Farm Pumpkin [ Tween ]", false, function(v)
	State.FarmTween = v
	if v and State.FarmBypass and toggles.FarmBypass then toggles.FarmBypass.Set(false) end
	State.FarmPumpkin = State.FarmTween or State.FarmBypass
end)
toggles.FarmBypass = addToggle(pageHalloween, "Auto Farm Pumpkin [ Bypass ]", false, function(v)
	State.FarmBypass = v
	if v and State.FarmTween and toggles.FarmTween then toggles.FarmTween.Set(false) end
	State.FarmPumpkin = State.FarmTween or State.FarmBypass
end)
toggles.FarmNPC = addToggle(pageHalloween, "Auto Farm Pumpkin NPCs", false, function(v) State.FarmNPC = v end)
addSlider(pageHalloween, "NPC search range", 20, 5000, State.FarmNPCRange, function(v) State.FarmNPCRange = v end, " m")
addSlider(pageHalloween, "NPC hover height", 2, 30, State.FarmNPCHeight, function(v) State.FarmNPCHeight = v end, " st")
addInput(pageHalloween, "NPC name filter", "lantern", function(v) State.FarmNPCName = v end, "names, comma separated")
toggles.FarmEquip = addToggle(pageHalloween, "Auto equip weapon", true, function(v) State.FarmEquip = v end,
	"Equips the first tool from your backpack while farming")
toggles.FarmPatch = addToggle(pageHalloween, "Auto farm PumpkinPatch", false, function(v) State.FarmPatch = v end,
	"Uses the Tween / Bypass mode that is switched on above")
addSlider(pageHalloween, "Farm speed", 20, 500, State.FarmSpeed, function(v) State.FarmSpeed = v end, " st/s")
addSlider(pageHalloween, "Farm search range", 50, 100000, State.FarmRange, function(v) State.FarmRange = v end, " m")
addSlider(pageHalloween, "Time at each object", 1, 30, State.FarmStay, function(v) State.FarmStay = v end, " s")
addSlider(pageHalloween, "Skip time after visit", 5, 300, State.FarmCool, function(v) State.FarmCool = v end, " s")
addSlider(pageHalloween, "Farm clicks per second", 1, 30, State.FarmCPS, function(v) State.FarmCPS = v end)
toggles.FarmLook = addToggle(pageHalloween, "Look at object", true, function(v) State.FarmLook = v end,
	"Turns the camera to the object so the click hits it")
toggles.FarmSkipHidden = addToggle(pageHalloween, "Skip hidden objects", false, function(v) State.FarmSkipHidden = v end,
	"Ignores objects that are invisible (already collected)")

addSection(pageHalloween, "Halloween ESP")
toggles.PumpkinESP = addToggle(pageHalloween, "Pumpkin ESP", false, function(v) State.PumpkinESP = v end,
	"Marks every object named \"Pumpkin\"")
toggles.PumpkinWall = addToggle(pageHalloween, "Pumpkin through walls", true, function(v) State.PumpkinWall = v end)
addSlider(pageHalloween, "Pumpkin distance", 20, 100000, State.PumpkinDist, function(v) State.PumpkinDist = v end, " m")
toggles.PatchESP = addToggle(pageHalloween, "PumpkinPatch ESP", false, function(v) State.PatchESP = v end,
	"Marks every object named \"PumpkinPatch\"")
toggles.PatchWall = addToggle(pageHalloween, "PumpkinPatch through walls", true, function(v) State.PatchWall = v end)
addSlider(pageHalloween, "PumpkinPatch distance", 20, 100000, State.PatchDist, function(v) State.PatchDist = v end, " m")
toggles.DoorESP = addToggle(pageHalloween, "HalloweenDoor ESP", false, function(v) State.DoorESP = v end,
	"Marks every object named \"HalloweenDoor\"")
toggles.DoorWall = addToggle(pageHalloween, "HalloweenDoor through walls", true, function(v) State.DoorWall = v end)
addSlider(pageHalloween, "HalloweenDoor distance", 20, 100000, State.DoorDist, function(v) State.DoorDist = v end, " m")
addSection(pageHalloween, "Colors")
addColor(pageHalloween, "Pumpkin color", espColors.Pumpkin, function(c) espColors.Pumpkin = c end)
addColor(pageHalloween, "PumpkinPatch color", espColors.Patch, function(c) espColors.Patch = c end)
addColor(pageHalloween, "HalloweenDoor color", espColors.Door, function(c) espColors.Door = c end)
end -- BLOCK

selectTab("Misc")

-- LOCAL STORAGE for executors (used when there is no server script).
-- The folder keeps its old name "CheatMenu", so settings saved by the old version still load.
local function makeLocalStore()
	local FOLDER = "CheatMenu"
	local canFS = type(writefile) == "function" and type(readfile) == "function" and type(isfile) == "function"

	local function path(name) return FOLDER .. "/" .. name end

	local function read(name)
		if not canFS then return nil end
		local ok, res = pcall(function()
			if not isfile(path(name)) then return nil end
			return HttpService:JSONDecode(readfile(path(name)))
		end)
		if ok then return res end
		return nil
	end

	local function write(name, data)
		if not canFS then return false end
		pcall(function()
			if type(isfolder) == "function" and type(makefolder) == "function" and not isfolder(FOLDER) then
				makefolder(FOLDER)
			end
		end)
		return (pcall(function() writefile(path(name), HttpService:JSONEncode(data)) end))
	end

	local store = {}
	function store.InvokeServer(_, action, data)
		if action == "load" then
			if not canFS then return nil, "writefile / readfile are not available in this executor" end
			return read("settings.json") or {}
		elseif action == "save" then
			return write("settings.json", data)
		elseif action == "flush" then
			return true
		elseif action == "recLoad" then
			return read("rec" .. tostring(data.slot) .. ".json")
		elseif action == "recSave" then
			return write("rec" .. tostring(data.slot) .. ".json", data)
		elseif action == "recClear" then
			pcall(function()
				local p = path("rec" .. tostring(data.slot) .. ".json")
				if type(delfile) == "function" and isfile(p) then delfile(p) end
			end)
			return true
		end
	end
	return store
end

-- LOAD + AUTO SAVE
task.spawn(function()
	saveRemote = ReplicatedStorage:FindFirstChild("CheatMenuSettings") or makeLocalStore()
	local ok, data, err = pcall(saveRemote.InvokeServer, saveRemote, "load")
	if not ok or type(data) ~= "table" then
		canSave = false
		warn("[ForgottenScript] settings load failed: " .. tostring(ok and err or data))
		notify("Save: load failed, see Output", 6)
	else
		local function restore(name, v)
			local c = registry[name]
			if not c then return end
			local sok, serr = pcall(c.set, v)
			if not sok then warn("[ForgottenScript] could not restore '" .. name .. "': " .. tostring(serr)) end
		end
		if type(data.AutoCount) == "number" then restore("AutoCount", data.AutoCount) end
		for name, v in pairs(data) do
			if not Ext.noSave[name] and name ~= "AutoCount" then restore(name, v) end
		end
	end
	loading = false
	runAutoSpawn()

	task.spawn(function()
		for slot = 1, 3 do
			local rok, res = pcall(saveRemote.InvokeServer, saveRemote, "recLoad", { slot = slot })
			if rok and res and not Rec.slots[slot] then Rec.slots[slot] = Rec.decode(res) end
		end
		Rec.refresh()
	end)

	while running do
		task.wait(2)
		if dirty and canSave then
			dirty = false
			local sok, res = pcall(saveRemote.InvokeServer, saveRemote, "save", snapshot())
			if not (sok and res == true) then dirty = true end
		end
	end
end)

-- GAME CLICK (used by Auto click and the auto farm)
local function overMenu(mp)
	if not main.Visible then return false end
	local p, s = main.AbsolutePosition, main.AbsoluteSize
	return mp.X >= p.X and mp.X <= p.X + s.X and mp.Y >= p.Y and mp.Y <= p.Y + s.Y
end

local function gameClick()
	local mp = UIS:GetMouseLocation()
	if overMenu(mp) then return end
	if okVIM then
		local ok = pcall(function()
			VIM:SendMouseButtonEvent(mp.X, mp.Y, 0, true, game, 0)
		end)
		if ok then
			task.delay(0.03, function()
				pcall(function() VIM:SendMouseButtonEvent(mp.X, mp.Y, 0, false, game, 0) end)
			end)
			return
		end
	end
	pcall(function() VirtualUser:ClickButton1(mp, camera.CFrame) end)
	local tool = player.Character and player.Character:FindFirstChildOfClass("Tool")
	if tool then tool:Activate() end
end

-- AUTO FARM (Pumpkin / PumpkinPatch)
-- The character flies (through walls) to the nearest object, hovers above it and clicks it:
-- ClickDetector / ProximityPrompt if the object has one (executor functions), plus a real mouse
-- click on the object (the camera turns to it). After "Time at each object" it goes to the next
-- one and skips the visited object for "Skip time after visit".
do -- BLOCK
local Farm = Ext.Farm
local fcd = fireclickdetector
local fpp = fireproximityprompt
local interCache = setmetatable({}, { __mode = "k" })
local farmPos

local function interactables(inst)
	local c = interCache[inst]
	if c and os.clock() - c.t < 2 then return c end
	c = { t = os.clock(), cds = {}, pps = {} }
	local list = inst:GetDescendants()
	table.insert(list, inst)
	local par = inst.Parent
	if par and par ~= workspace and par:IsA("Model") then
		for _, d in ipairs(par:GetChildren()) do table.insert(list, d) end
	end
	for _, d in ipairs(list) do
		if d:IsA("ClickDetector") then
			c.cds[#c.cds + 1] = d
		elseif d:IsA("ProximityPrompt") then
			c.pps[#c.pps + 1] = d
		end
	end
	interCache[inst] = c
	return c
end

local function doClick(inst)
	local c = interactables(inst)
	if fcd then
		for _, cd in ipairs(c.cds) do pcall(fcd, cd) end
	end
	if fpp then
		for _, pp in ipairs(c.pps) do
			if pp.Enabled then pcall(fpp, pp) end
		end
	end
	local pos = Ext.posOf(inst)
	if pos and okVIM then
		local sp, on = camera:WorldToViewportPoint(pos)
		if on and sp.Z > 0 then
			local mp = Vector2.new(sp.X, sp.Y)
			if not overMenu(mp) then
				pcall(function() VIM:SendMouseButtonEvent(mp.X, mp.Y, 0, true, game, 0) end)
				task.delay(0.03, function()
					pcall(function() VIM:SendMouseButtonEvent(mp.X, mp.Y, 0, false, game, 0) end)
				end)
			end
		end
	end
	local tool = player.Character and player.Character:FindFirstChildOfClass("Tool")
	if tool then pcall(function() tool:Activate() end) end
end

local function isHidden(inst)
	local p = Ext.partOf(inst)
	return p ~= nil and p.Transparency >= 0.95
end

local function pick(origin)
	local best, bd, bcat
	local now = os.clock()
	for _, cat in ipairs({ "Pumpkin", "Patch" }) do
		if (cat == "Pumpkin" and State.FarmPumpkin) or (cat == "Patch" and State.FarmPatch) then
			local set = Ext.found[cat]
			for inst in pairs(set) do
				if not inst:IsDescendantOf(workspace) then
					set[inst] = nil
				elseif not (Farm.black[inst] and Farm.black[inst] > now)
					and not (State.FarmSkipHidden and isHidden(inst)) then
					local p = Ext.posOf(inst)
					if p then
						local d = (p - origin).Magnitude
						if d <= State.FarmRange and (not bd or d < bd) then
							best, bd, bcat = inst, d, cat
						end
					end
				end
			end
		end
	end
	return best, bcat
end

local function status(s)
	if Farm.setStatus then Farm.setStatus(s) end
end

function Farm.start()
	Farm.active = true
	Farm.target, Farm.nearT, Farm.clickAcc = nil, 0, 0
	if State.Fly and toggles.Fly then toggles.Fly.Set(false) end
	local root, hum = getRoot(), getHumanoid()
	farmPos = root and root.Position
	if hum then hum.PlatformStand = true end
	notify("Auto farm started")
end

function Farm.stop()
	if not Farm.active then return end
	Farm.active = false
	Farm.target = nil
	Farm.hold = nil
	farmPos = nil
	local hum, root = getHumanoid(), getRoot()
	if hum and not State.Fly then hum.PlatformStand = false end
	if root then
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
	end
	Ext.refreshNoclip()
	status("Off")
end

local function npcAlive(m)
	local h = m and m.Parent and m:FindFirstChildOfClass("Humanoid")
	return h ~= nil and h.Health > 0
end

-- Quest givers / dealers are never targeted: a model that has a ProximityPrompt, ClickDetector
-- or Dialog inside, or "quest" / "giver" in its name, is skipped (so the script never flies to
-- them and never starts a conversation).
local giverCache = setmetatable({}, { __mode = "k" })
local function isGiver(m)
	local c = giverCache[m]
	if c ~= nil then return c end
	c = false
	local ln = string.lower(m.Name)
	if string.find(ln, "quest", 1, true) or string.find(ln, "giver", 1, true) then
		c = true
	else
		for _, d in ipairs(m:GetDescendants()) do
			if d:IsA("ProximityPrompt") or d:IsA("ClickDetector") or d:IsA("Dialog") then
				c = true
				break
			end
		end
	end
	giverCache[m] = c
	return c
end

-- name filter: words separated by commas, an NPC is taken if its name contains any of them.
-- Empty filter = "lantern" (Jack o' Lantern), so nothing else gets aggro.
local function parseFilter()
	local raw = string.lower(tostring(State.FarmNPCName or ""))
	local list = {}
	for w in raw:gmatch("[^,]+") do
		w = w:gsub("^%s+", ""):gsub("%s+$", "")
		if w ~= "" then list[#list + 1] = w end
	end
	if #list == 0 then list[1] = "lantern" end
	return list
end

local function pickNPC(origin)
	local words = parseFilter()
	local best, bd
	local now = os.clock()
	for _, t in ipairs(collectTargets(true)) do
		if t.isNPC and not (Farm.black[t.model] and Farm.black[t.model] > now) then
			local ln, ok = string.lower(t.model.Name), false
			local dn = string.lower(t.name)
			for _, w in ipairs(words) do
				if string.find(ln, w, 1, true) or string.find(dn, w, 1, true) then
					ok = true
					break
				end
			end
			if ok and not isGiver(t.model) then
				local d = (t.root.Position - origin).Magnitude
				if d <= State.FarmNPCRange and (not bd or d < bd) then best, bd = t, d end
			end
		end
	end
	return best
end

local function attackNPC(pos)
	if okVIM then
		local sp, on = camera:WorldToViewportPoint(pos)
		local mp = (on and sp.Z > 0) and Vector2.new(sp.X, sp.Y) or UIS:GetMouseLocation()
		if not overMenu(mp) then
			pcall(function() VIM:SendMouseButtonEvent(mp.X, mp.Y, 0, true, game, 0) end)
			task.delay(0.03, function()
				pcall(function() VIM:SendMouseButtonEvent(mp.X, mp.Y, 0, false, game, 0) end)
			end)
		end
	end
	local tool = player.Character and player.Character:FindFirstChildOfClass("Tool")
	if tool then pcall(function() tool:Activate() end) end
end

local function autoEquip(hum)
	local chr = player.Character
	if not chr or chr:FindFirstChildOfClass("Tool") then return end
	local bp = player:FindFirstChildOfClass("Backpack")
	local tool = bp and bp:FindFirstChildOfClass("Tool")
	if tool then pcall(function() hum:EquipTool(tool) end) end
end

function Farm.step(dt)
	local want = State.FarmPumpkin or State.FarmPatch or State.FarmNPC
	local root, hum = getRoot(), getHumanoid()
	if not want or not root or not hum or hum.Health <= 0 then
		Farm.stop()
		return
	end
	if not Farm.active then Farm.start() end
	local bypass = State.FarmBypass
	if bypass or not farmPos or (root.Position - farmPos).Magnitude > 10 then farmPos = root.Position end

	-- Tween: the position is moved smoothly step by step (no teleport).
	-- Bypass: the character is pushed with velocity only, the position is never written.
	local function drive(tp, spd)
		local diff = tp - farmPos
		local dist = diff.Magnitude
		if bypass then
			local cap = math.min(spd, 100)
			local v = diff * 6
			if v.Magnitude > cap then v = v.Unit * cap end
			root.AssemblyLinearVelocity = v
			root.AssemblyAngularVelocity = Vector3.zero
		else
			if dist > 0.01 then farmPos += diff.Unit * math.min(dist, spd * dt) end
			local flat = Vector3.new(diff.X, 0, diff.Z)
			local rot = flat.Magnitude > 0.5 and CFrame.lookAt(Vector3.zero, flat) or (root.CFrame - root.CFrame.Position)
			root.CFrame = CFrame.new(farmPos) * rot
			root.AssemblyLinearVelocity = Vector3.zero
			root.AssemblyAngularVelocity = Vector3.zero
		end
		return dist
	end

	if State.FarmEquip then autoEquip(hum) end

	local t = Farm.target
	if t and t.cat == "NPC" then
		if not State.FarmNPC or not npcAlive(t.model) or not t.root.Parent then
			t = nil
			Farm.target = nil
		elseif os.clock() - t.t0 > 30 then
			Farm.black[t.model] = os.clock() + 20
			t = nil
			Farm.target = nil
		end
	elseif t and (not t.inst:IsDescendantOf(workspace) or (State.FarmSkipHidden and isHidden(t.inst))) then
		t = nil
		Farm.target = nil
	end

	-- NPCs that appear after a pumpkin is killed have priority over the next pumpkin
	if State.FarmNPC and not (t and t.cat == "NPC") then
		Farm.scanT = (Farm.scanT or 0) + dt
		if Farm.scanT >= 0.4 then
			Farm.scanT = 0
			local n = pickNPC(farmPos)
			if n then
				t = { cat = "NPC", model = n.model, root = n.root, name = n.name, t0 = os.clock() }
				Farm.target = t
				Farm.nearT, Farm.clickAcc = 0, 0
			end
		end
	end

	if not t and (State.FarmPumpkin or State.FarmPatch) then
		local inst, cat = pick(farmPos)
		if inst then
			t = { inst = inst, cat = cat }
			Farm.nearT, Farm.clickAcc = 0, 0
			Farm.target = t
		end
	end

	hum.PlatformStand = true

	if not t then
		-- nothing to do: hold the current spot (never fall through the map)
		Farm.hold = Farm.hold or root.Position
		drive(Farm.hold, 50)
		status("Waiting for objects")
		return
	end
	Farm.hold = nil

	if t.cat == "NPC" then
		local npcPos = t.root.Position
		local d = drive(npcPos + Vector3.new(0, State.FarmNPCHeight, 0), State.FarmSpeed)
		status(string.format("Attacking %s (%d m)", t.name, math.floor(d)))
		if d < 14 then
			Farm.clickAcc += dt
			if Farm.clickAcc >= 1 / State.FarmCPS then
				Farm.clickAcc = 0
				attackNPC(npcPos)
			end
		end
		if State.FarmLook then
			local cp = camera.CFrame.Position
			if (npcPos - cp).Magnitude > 1 then
				camera.CFrame = camera.CFrame:Lerp(CFrame.lookAt(cp, npcPos), math.clamp(dt * 12, 0, 1))
			end
		end
		return
	end

	local objPos = Ext.posOf(t.inst)
	if not objPos then
		Farm.target = nil
		return
	end
	local tp = objPos + Vector3.new(0, 3, 0)
	local label = t.cat == "Patch" and "PumpkinPatch" or "Pumpkin"
	local dist = drive(tp, State.FarmSpeed)

	if dist > 3 then
		Farm.nearT = 0
		status(string.format("Flying to %s (%d m)", label, math.floor(dist)))
	else
		Farm.nearT += dt
		Farm.clickAcc += dt
		status(string.format("Clicking %s (%.1f s)", label, Farm.nearT))
		if Farm.clickAcc >= 1 / State.FarmCPS then
			Farm.clickAcc = 0
			doClick(t.inst)
		end
		if State.FarmLook then
			local cp = camera.CFrame.Position
			if (objPos - cp).Magnitude > 1 then
				camera.CFrame = camera.CFrame:Lerp(CFrame.lookAt(cp, objPos), math.clamp(dt * 10, 0, 1))
			end
		end
		if Farm.nearT >= State.FarmStay then
			Farm.black[t.inst] = os.clock() + State.FarmCool
			Farm.target = nil
		end
	end
end

pcall(function() RunService:UnbindFromRenderStep("CheatSimFarm") end)
RunService:BindToRenderStep("CheatSimFarm", Enum.RenderPriority.Camera.Value + 2, function(dt)
	pcall(Farm.step, dt)
end)

table.insert(Ext.cleanup, function()
	pcall(function() RunService:UnbindFromRenderStep("CheatSimFarm") end)
	Farm.stop()
end)
end -- BLOCK

-- AUTO JUMP OUT: gets you off a seat and out of an NPC dialogue (for example in the cafe).
-- Seat: the seat weld is removed and the character jumps. Dialogue: a visible GUI whose name
-- contains dialog / talk / conversation is closed and the character jumps.
do -- BLOCK
local WORDS = { "dialog", "talk", "conversation" }
local acc = 0

local function isDialogName(n)
	n = string.lower(n)
	for _, w in ipairs(WORDS) do
		if string.find(n, w, 1, true) then return true end
	end
	return false
end

local function findDialogs()
	local found = {}
	local pg = player:FindFirstChildOfClass("PlayerGui")
	if not pg then return found end
	for _, g in ipairs(pg:GetChildren()) do
		if g:IsA("ScreenGui") and g ~= gui then
			if g.Enabled and isDialogName(g.Name) then
				found[#found + 1] = g
			elseif g.Enabled then
				for _, f in ipairs(g:GetChildren()) do
					if f:IsA("GuiObject") and f.Visible and isDialogName(f.Name) then
						found[#found + 1] = f
					end
				end
			end
		end
	end
	return found
end

connect(RunService.Heartbeat, function(dt)
	if not State.AutoJump then return end
	acc += dt
	if acc < 0.15 then return end
	acc = 0
	local hum, root = getHumanoid(), getRoot()
	if not hum or not root or hum.Health <= 0 then return end

	local seat = hum.SeatPart
	local seated = hum.Sit or seat ~= nil
	local dialogs = findDialogs()
	if not seated and #dialogs == 0 then return end

	if seat then
		local w = seat:FindFirstChild("SeatWeld")
		if w then pcall(function() w:Destroy() end) end
	end
	for _, d in ipairs(dialogs) do
		pcall(function()
			if d:IsA("ScreenGui") then d.Enabled = false else d.Visible = false end
		end)
	end
	if hum.PlatformStand and not State.Fly and not Ext.Farm.active then hum.PlatformStand = false end
	hum.Sit = false
	hum:ChangeState(Enum.HumanoidStateType.Jumping)
	hum.Jump = true
	if seated and not Ext.Farm.active then
		root.CFrame += Vector3.new(0, 3, 0)
	end
end)
end -- BLOCK

-- LOOPS AND INPUT
local wasSpeed, wasJump = false, false
local lastSafe
local clickAcc = 0

connect(RunService.Heartbeat, function(dt)
	local hum = getHumanoid()
	if not hum then return end

	Ext.stepInvis(dt)

	if State.Speed then
		if State.SpeedMode ~= "CFrame" then
			hum.WalkSpeed = State.SpeedValue
		else
			hum.WalkSpeed = Defaults.WalkSpeed
		end
		wasSpeed = true
	elseif wasSpeed then
		hum.WalkSpeed = Defaults.WalkSpeed
		wasSpeed = false
	end

	if State.Jump then
		hum.UseJumpPower = true
		hum.JumpPower = State.JumpValue
		wasJump = true
	elseif wasJump then
		hum.JumpPower = Defaults.JumpPower
		wasJump = false
	end

	if State.Bhop and UIS:IsKeyDown(Enum.KeyCode.Space) and not UIS:GetFocusedTextBox()
		and hum.FloorMaterial ~= Enum.Material.Air then
		hum:ChangeState(Enum.HumanoidStateType.Jumping)
	end

	local root = getRoot()
	if root then
		if State.Speed and State.SpeedMode ~= "WalkSpeed" and not State.Fly and not Rec.playing and not Ext.Farm.active then
			local md = hum.MoveDirection
			if md.Magnitude > 0.01 then
				root.CFrame += md * (State.SpeedValue * dt)
			end
		end
		if State.Spin and not Ext.Farm.active then root.CFrame *= CFrame.Angles(0, math.rad(State.SpinSpeed), 0) end
		if State.AntiVoid and not Ext.Farm.active then
			if hum.FloorMaterial ~= Enum.Material.Air then
				lastSafe = root.CFrame
			elseif lastSafe and root.Position.Y < workspace.FallenPartsDestroyHeight + 40 then
				root.AssemblyLinearVelocity = Vector3.zero
				root.CFrame = lastSafe + Vector3.new(0, 5, 0)
			end
		end
	end

	if State.AutoClick then
		clickAcc += dt
		if clickAcc >= 1 / State.ClickCPS then
			clickAcc = 0
			clickAssist()
			gameClick()
		end
	else
		clickAcc = 0
	end

	if State.NoStun then
		if hum.PlatformStand and not State.Fly and not Ext.Farm.active then hum.PlatformStand = false end
		local st = hum:GetState()
		if st == Enum.HumanoidStateType.Ragdoll or st == Enum.HumanoidStateType.FallingDown
			or (st == Enum.HumanoidStateType.Physics and not State.Fly and not Ext.Farm.active) then
			hum:ChangeState(Enum.HumanoidStateType.GettingUp)
		end
		if root and root.Anchored and not Rec.playing then root.Anchored = false end
		if not State.Speed and hum.WalkSpeed < Defaults.WalkSpeed then hum.WalkSpeed = Defaults.WalkSpeed end
		if not State.Jump and hum.UseJumpPower and hum.JumpPower < Defaults.JumpPower then
			hum.JumpPower = Defaults.JumpPower
		end
	end

	if State.TimeOn then Lighting.ClockTime = State.Time end
end)

connect(RunService.Stepped, function()
	if (State.Noclip or Ext.Farm.active or (State.Fly and State.FlyThrough)) and player.Character then
		for _, part in ipairs(player.Character:GetDescendants()) do
			if part:IsA("BasePart") and part.CanCollide then
				noclipChanged[part] = true
				part.CanCollide = false
			end
		end
	end
end)

connect(RunService.RenderStepped, function(dt)
	fps = fps * 0.9 + (1 / math.max(dt, 0.001)) * 0.1
	if State.Cursor then
		local mp = UIS:GetMouseLocation()
		cursor.Position = UDim2.fromOffset(mp.X, mp.Y)
		UIS.MouseIconEnabled = false
	end
	updateESP()
	updateRadar()
end)

-- NO STUN scan (every 0.1 s)
task.spawn(function()
	while running do
		if State.NoStun then
			local sc = player.Character
			if sc then
				noStunStates(true)
				for _, d in ipairs(sc:GetDescendants()) do
					if d:IsA("BoolValue") then
						if d.Value and isStun(d.Name) then d.Value = false end
					elseif d:IsA("Motor6D") then
						if not d.Enabled then d.Enabled = true end
					elseif d:IsA("BallSocketConstraint") or d:IsA("BodyMover") then
						if isStun(d.Name) then d:Destroy() end
					elseif d:IsA("BasePart") then
						if d.Anchored and not Rec.playing then d.Anchored = false end
					end
				end
				for _, holder in ipairs({ sc, getHumanoid() }) do
					if holder then
						for n, v in pairs(holder:GetAttributes()) do
							if v == true and isStun(n) then holder:SetAttribute(n, false) end
						end
					end
				end
			end
		end
		task.wait(0.1)
	end
end)

task.spawn(function()
	while running do
		targetCache = (State.ESP or State.Radar) and collectTargets(State.ESPNPC) or {}
		syncESP()

		if State.Info then
			infoLabel.Text = string.format("FPS %d   •   Ping %d ms   •   Players %d",
				math.floor(fps), math.floor(player:GetNetworkPing() * 1000), #Players:GetPlayers())
		end
		task.wait(0.5)
	end
end)

connect(UIS.JumpRequest, function()
	if State.InfJump then
		local hum = getHumanoid()
		if hum then hum:ChangeState(Enum.HumanoidStateType.Jumping) end
	end
end)

connect(mouse.Button1Down, function()
	local mod = toKey(Binds.ClickTP)
	if State.ClickTP and (not mod or UIS:IsKeyDown(mod)) then
		local root = getRoot()
		if root and mouse.Hit then root.CFrame = CFrame.new(mouse.Hit.Position + Vector3.new(0, 3, 0)) end
	end
end)

connect(player.Idled, function()
	if State.AntiAFK then
		VirtualUser:CaptureController()
		VirtualUser:ClickButton2(Vector2.new())
	end
end)

connect(UIS.InputBegan, function(input, processed)
	if captureFn then
		if input.UserInputType == Enum.UserInputType.Keyboard then
			local fn = captureFn
			captureFn = nil
			fn(input.KeyCode)
		end
		return
	end
	if processed then return end

	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		clickHeld = true
		clickUntil = os.clock() + 0.15
		clickAssist()
		return
	end

	if input.UserInputType == Enum.UserInputType.MouseButton2 then
		if freecamBound then
			freecam.rmb = true
			UIS.MouseBehavior = Enum.MouseBehavior.LockCurrentPosition
		end
		return
	end

	local name = input.KeyCode.Name
	if input.KeyCode == Enum.KeyCode.Unknown then return end
	if name == Binds.Menu then
		setVisible(not main.Visible)
	elseif name == Binds.Zoom then
		zoomHeld = true
	elseif name == Binds.RecToggle then
		if Rec.recording then Rec.stopRecording() else Rec.startRecording() end
	elseif name == Binds.PlayToggle then
		if Rec.playing then Rec.stopPlaying() else Rec.startPlaying() end
	end
	for _, a in ipairs(ToggleBinds) do
		if Binds[a.id] == name then
			local t = toggles[a.toggle]
			if t then t.Set(not t.Get()) end
		end
	end
end)

connect(UIS.InputEnded, function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		clickHeld = false
		clickUntil = os.clock() + 0.12
	end
	if input.KeyCode ~= Enum.KeyCode.Unknown and input.KeyCode.Name == Binds.Zoom then
		zoomHeld = false
	elseif input.UserInputType == Enum.UserInputType.MouseButton2 and freecamBound then
		freecam.rmb = false
		UIS.MouseBehavior = Enum.MouseBehavior.Default
	end
end)

local function onCharacter(char)
	local hum = char:WaitForChild("Humanoid")
	Defaults.WalkSpeed = hum.WalkSpeed
	Defaults.JumpPower = hum.JumpPower
	wasSpeed, wasJump, lastSafe = false, false, nil
	table.clear(noclipChanged)
	if Rec.playing then Rec.stopPlaying() end
	if Rec.recording then Rec.stopRecording() end
	runAutoSpawn()
	Ext.resetAir()
	Ext.Farm.target = nil
	if State.NoStun then noStunStates(true) end
	if State.Fly then
		task.wait(0.4)
		startFly()
	end
end
connect(player.CharacterAdded, onCharacter)
if player.Character then task.spawn(onCharacter, player.Character) end

notify("Forgotten Script loaded. Press " .. Binds.Menu .. " to hide / show", 4)
