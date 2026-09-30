--[[
	PANTALLA DE CARGA v2 - Roblox (Luau)
	Tipo: LocalScript
	Ubicación: StarterGui  (o StarterPlayer > StarterPlayerScripts)

	Novedades:
	- Cubre TODA la pantalla (incluye notch/bordes y oculta la barra superior de Roblox).
	- Marco con degradado hacia ADENTRO, con colores que cambian constantemente
	  y una luz que recorre todo el perímetro.
	- Aura con rayos giratorios, halos pulsantes, partículas flotantes,
	  barrido de luz, glitch cromático en el logo, brillo en la barra y
	  onda de choque al completar la carga.
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local StarterGui = game:GetService("StarterGui")
local ContentProvider = game:GetService("ContentProvider")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

----------------------------------------------------------------------
-- CONFIGURACIÓN
----------------------------------------------------------------------
local CONFIG = {
	BackgroundId = 93969776014252,  -- Fondo   (acepta número o "rbxassetid://...")
	LogoId       = 131601007093891, -- Logo/Texto

	StartDelay  = 1,    -- segundos antes de aparecer
	LoadTime    = 5,    -- segundos que tarda la barra
	FadeInTime  = 1,
	FadeOutTime = 2.2,  -- desaparición (más alto = más suave)

	LogoCenter = Vector2.new(0.74, 0.42), -- posición del logo (derecha del personaje)
	LogoHeight = 0.44,                    -- alto del logo relativo al alto de pantalla
	LogoAspect = 1672 / 941,              -- proporción de la imagen del logo

	HideRobloxUI = true, -- oculta la barra superior/chat mientras carga
}

-- Paleta que se recorre continuamente
local PALETTE = {
	Color3.fromRGB(255, 50, 220),  -- rosa
	Color3.fromRGB(150, 60, 255),  -- morado
	Color3.fromRGB(40, 110, 255),  -- azul
	Color3.fromRGB(0, 220, 255),   -- cian
}
local PINK = PALETTE[1]
local CYAN = PALETTE[4]

local function paletteColor(x)
	x = x % 1
	local n = #PALETTE
	local p = x * n
	local i = math.floor(p)
	local f = p - i
	return PALETTE[i % n + 1]:Lerp(PALETTE[(i + 1) % n + 1], f)
end

local function cycleSequence(x0)
	return ColorSequence.new({
		ColorSequenceKeypoint.new(0, paletteColor(x0)),
		ColorSequenceKeypoint.new(0.25, paletteColor(x0 + 0.25)),
		ColorSequenceKeypoint.new(0.5, paletteColor(x0 + 0.5)),
		ColorSequenceKeypoint.new(0.75, paletteColor(x0 + 0.75)),
		ColorSequenceKeypoint.new(1, paletteColor(x0 + 1)),
	})
end

local function toAsset(id)
	if typeof(id) == "number" then
		return "rbxassetid://" .. id
	end
	local s = tostring(id)
	if s:match("^%d+$") then
		return "rbxassetid://" .. s
	end
	return s
end

local BG_IMAGE = toAsset(CONFIG.BackgroundId)
local LOGO_IMAGE = toAsset(CONFIG.LogoId)

local RNG = Random.new()
local CX, CY = CONFIG.LogoCenter.X, CONFIG.LogoCenter.Y

----------------------------------------------------------------------
-- HELPERS
----------------------------------------------------------------------
local function new(class, props, parent)
	local inst = Instance.new(class)
	for k, v in pairs(props) do
		inst[k] = v
	end
	inst.Parent = parent
	return inst
end

local function tween(inst, time, props, style, dir)
	local t = TweenService:Create(
		inst,
		TweenInfo.new(time, style or Enum.EasingStyle.Sine, dir or Enum.EasingDirection.InOut),
		props
	)
	t:Play()
	return t
end

----------------------------------------------------------------------
-- UI DE ROBLOX (ocultar / restaurar)
----------------------------------------------------------------------
local savedCore = {}
local coreTypes = {
	Enum.CoreGuiType.PlayerList,
	Enum.CoreGuiType.Health,
	Enum.CoreGuiType.Backpack,
	Enum.CoreGuiType.Chat,
	Enum.CoreGuiType.EmotesMenu,
}

local function hideRobloxUI()
	for _, ct in ipairs(coreTypes) do
		local ok, v = pcall(function()
			return StarterGui:GetCoreGuiEnabled(ct)
		end)
		savedCore[ct] = (ok and v) or false
		pcall(function()
			StarterGui:SetCoreGuiEnabled(ct, false)
		end)
	end
	for _ = 1, 10 do
		local ok = pcall(function()
			StarterGui:SetCore("TopbarEnabled", false)
		end)
		if ok then
			break
		end
		task.wait(0.1)
	end
end

local function restoreRobloxUI()
	for ct, v in pairs(savedCore) do
		pcall(function()
			StarterGui:SetCoreGuiEnabled(ct, v)
		end)
	end
	pcall(function()
		StarterGui:SetCore("TopbarEnabled", true)
	end)
end

----------------------------------------------------------------------
-- INTERFAZ
----------------------------------------------------------------------
local gui = new("ScreenGui", {
	Name = "LoadingScreen",
	IgnoreGuiInset = true,
	ResetOnSpawn = false,
	DisplayOrder = 999,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	Enabled = false,
}, nil)
pcall(function()
	gui.ScreenInsets = Enum.ScreenInsets.None -- cubre notch y bordes
end)

local root = new("CanvasGroup", {
	Name = "Root",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.new(0, 0, 0),
	BorderSizePixel = 0,
	GroupTransparency = 1,
	Active = true,
}, gui)

-- 1) Fondo -------------------------------------------------------------
local bg = new("ImageLabel", {
	Name = "Background",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromScale(1.08, 1.08),
	BackgroundTransparency = 1,
	Image = BG_IMAGE,
	ScaleType = Enum.ScaleType.Crop,
	ZIndex = 1,
}, root)

-- 2) Luz ambiental que cambia de color
local tint = new("Frame", {
	Name = "Tint",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = PINK,
	BackgroundTransparency = 0.88,
	BorderSizePixel = 0,
	ZIndex = 2,
}, root)

-- 3) Oscurecido inferior
local shade = new("Frame", {
	Name = "Shade",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.new(0, 0, 0),
	BorderSizePixel = 0,
	ZIndex = 3,
}, root)
new("UIGradient", {
	Rotation = 90,
	Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.6, 1),
		NumberSequenceKeypoint.new(1, 0.35),
	}),
}, shade)

-- 4) Barrido de luz diagonal
local sweep = new("Frame", {
	Name = "Sweep",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(-0.3, 0.5),
	Size = UDim2.fromScale(0.28, 2),
	Rotation = 18,
	BackgroundColor3 = Color3.new(1, 1, 1),
	BorderSizePixel = 0,
	ZIndex = 4,
}, root)
new("UIGradient", {
	Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.5, 0.86),
		NumberSequenceKeypoint.new(1, 1),
	}),
}, sweep)

-- 5) Aura detrás del logo: halos + rayos giratorios --------------------
local aura = new("Frame", {
	Name = "Aura",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(CX, CY),
	Size = UDim2.fromScale(0.95, 0.95),
	BackgroundTransparency = 1,
	ZIndex = 5,
}, root)
new("UIAspectRatioConstraint", { AspectRatio = 1, DominantAxis = Enum.DominantAxis.Height }, aura)
local auraScale = new("UIScale", { Scale = 0.5 }, aura)

local halo = {}
for i, base in ipairs({ 0.35, 0.5, 0.65, 0.8, 0.95 }) do
	local f = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(base, base),
		BackgroundColor3 = PINK,
		BackgroundTransparency = 0.93,
		BorderSizePixel = 0,
		ZIndex = 1,
	}, aura)
	new("UICorner", { CornerRadius = UDim.new(1, 0) }, f)
	table.insert(halo, { frame = f, base = base })
end

local rayRoot = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	ZIndex = 2,
}, aura)

local RAY_COUNT = 12
local rays = {}
for i = 1, RAY_COUNT do
	local pivot = new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Rotation = (i - 1) * (360 / RAY_COUNT) + RNG:NextNumber(-8, 8),
	}, rayRoot)
	local len = RNG:NextNumber(0.3, 0.5)
	local th = RNG:NextInteger(2, 5)
	local ray = new("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(len, 0, 0, th),
		BackgroundColor3 = PINK,
		BorderSizePixel = 0,
	}, pivot)
	new("UIGradient", { Transparency = NumberSequence.new(0, 1) }, ray)
	table.insert(rays, { frame = ray, len = len })
end

-- 6) Partículas flotantes (unas detrás y otras delante del logo)
local particles = {}
for i = 1, 38 do
	local big = (i % 5 == 0)
	local size = big and RNG:NextInteger(12, 22) or RNG:NextInteger(2, 6)
	local f = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(size, size),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		ZIndex = (i % 2 == 0) and 6 or 8,
	}, root)
	new("UICorner", { CornerRadius = UDim.new(1, 0) }, f)
	table.insert(particles, {
		inst = f,
		big = big,
		x = RNG:NextNumber(),
		y = RNG:NextNumber(),
		speed = big and RNG:NextNumber(0.02, 0.05) or RNG:NextNumber(0.05, 0.14),
		amp = RNG:NextNumber(0.005, 0.02),
		wob = RNG:NextNumber(0.5, 1.5),
		phase = RNG:NextNumber(0, math.pi * 2),
		tw = RNG:NextNumber(1, 3),
		hue = RNG:NextNumber(0, 1),
		white = (i % 3 == 0),
	})
end

-- 7) LOGO --------------------------------------------------------------
local logoAnchor = new("Frame", {
	Name = "LogoAnchor",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(CX + 0.16, CY), -- entra desde la derecha
	Size = UDim2.fromScale(0.5, CONFIG.LogoHeight),
	BackgroundTransparency = 1,
	ZIndex = 7,
}, root)
new("UIAspectRatioConstraint", {
	AspectRatio = CONFIG.LogoAspect,
	DominantAxis = Enum.DominantAxis.Height,
}, logoAnchor)

local logoHolder = new("Frame", {
	Name = "LogoHolder",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
}, logoAnchor)
local logoScale = new("UIScale", { Scale = 1 }, logoHolder)

local function logoLayer(name, size, color, transparency, z)
	return new("ImageLabel", {
		Name = name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(size, size),
		BackgroundTransparency = 1,
		Image = LOGO_IMAGE,
		ImageColor3 = color,
		ImageTransparency = transparency,
		ZIndex = z,
	}, logoHolder)
end

-- Capas de aura que orbitan y cambian de color
local glowLayers = {}
for i, def in ipairs({
	{ size = 1.05, trans = 0.55 },
	{ size = 1.10, trans = 0.72 },
	{ size = 1.17, trans = 0.86 },
}) do
	table.insert(glowLayers, { inst = logoLayer("Glow" .. i, def.size, PINK, def.trans, 3), base = def.trans })
end

-- Capas para el efecto glitch (separación cromática)
local chromaR = logoLayer("ChromaR", 1, Color3.fromRGB(255, 40, 120), 1, 5)
local chromaC = logoLayer("ChromaC", 1, Color3.fromRGB(0, 230, 255), 1, 5)

-- Logo principal
local logoMain = logoLayer("Logo", 1, Color3.new(1, 1, 1), 0, 6)

-- Destellos alrededor del logo
local sparkles = {}
for i = 1, 16 do
	local s = RNG:NextInteger(3, 8)
	local f = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(RNG:NextNumber(0.02, 0.98), RNG:NextNumber(0.05, 0.95)),
		Size = UDim2.fromOffset(s, s),
		BackgroundColor3 = (i % 2 == 0) and Color3.new(1, 1, 1) or CYAN,
		BorderSizePixel = 0,
		ZIndex = 7,
	}, logoHolder)
	new("UICorner", { CornerRadius = UDim.new(1, 0) }, f)
	table.insert(sparkles, {
		inst = f,
		size = s,
		phase = RNG:NextNumber(0, math.pi * 2),
		speed = RNG:NextNumber(1.5, 4),
	})
end

-- 8) MARCO: degradado hacia adentro, colores cambiantes, pantalla completa
local edgeFrame = new("Frame", {
	Name = "Edges",
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	ZIndex = 9,
}, root)

local edgeFade = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0),
	NumberSequenceKeypoint.new(0.3, 0.5),
	NumberSequenceKeypoint.new(0.65, 0.85),
	NumberSequenceKeypoint.new(1, 1),
})

local edgeSegs = {}
local function addSeg(props, rotation, p)
	props.BorderSizePixel = 0
	props.BackgroundColor3 = PINK
	local f = new("Frame", props, edgeFrame)
	new("UIGradient", { Rotation = rotation, Transparency = edgeFade }, f)
	table.insert(edgeSegs, { inst = f, p = p })
end

local TH_Y, TH_X = 0.2, 0.11 -- grosor del degradado interior
local NH, NV = 14, 8         -- segmentos horizontales / verticales
for k = 0, NH - 1 do
	local x = k / NH
	-- arriba (izq -> der)
	addSeg({
		AnchorPoint = Vector2.new(0, 0),
		Position = UDim2.fromScale(x, 0),
		Size = UDim2.new(1 / NH, 2, TH_Y, 0),
	}, 90, ((k + 0.5) / NH) * 0.25)
	-- abajo (der -> izq)
	addSeg({
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(x, 1),
		Size = UDim2.new(1 / NH, 2, TH_Y, 0),
	}, 270, 0.5 + (1 - (k + 0.5) / NH) * 0.25)
end
for k = 0, NV - 1 do
	local y = k / NV
	-- derecha (arriba -> abajo)
	addSeg({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, y),
		Size = UDim2.new(TH_X, 0, 1 / NV, 2),
	}, 180, 0.25 + ((k + 0.5) / NV) * 0.25)
	-- izquierda (abajo -> arriba)
	addSeg({
		AnchorPoint = Vector2.new(0, 0),
		Position = UDim2.fromScale(0, y),
		Size = UDim2.new(TH_X, 0, 1 / NV, 2),
	}, 0, 0.75 + (1 - (k + 0.5) / NV) * 0.25)
end

-- Línea de neón fina en el borde
local border = new("Frame", {
	Name = "Border",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.new(1, -6, 1, -6),
	BackgroundTransparency = 1,
	ZIndex = 10,
}, root)
new("UICorner", { CornerRadius = UDim.new(0, 12) }, border)
local borderStroke = new("UIStroke", {
	Thickness = 3,
	Color = Color3.new(1, 1, 1),
	ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
}, border)
local borderGrad = new("UIGradient", { Color = cycleSequence(0) }, borderStroke)

-- 9) BARRA DE CARGA ----------------------------------------------------
local BAR_W = 0.42

local barGlow = new("Frame", {
	Name = "BarGlow",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 0.92, 8),
	Size = UDim2.new(BAR_W, 24, 0, 28),
	BackgroundColor3 = PINK,
	BackgroundTransparency = 0.8,
	BorderSizePixel = 0,
	ZIndex = 11,
}, root)
new("UICorner", { CornerRadius = UDim.new(1, 0) }, barGlow)

local loadingLabel = new("TextLabel", {
	Name = "LoadingText",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 0.92, -20),
	Size = UDim2.new(BAR_W, 0, 0, 18),
	BackgroundTransparency = 1,
	Text = "Loading",
	Font = Enum.Font.GothamMedium,
	TextSize = 14,
	TextColor3 = Color3.new(1, 1, 1),
	TextStrokeColor3 = PINK,
	TextStrokeTransparency = 0.45,
	ZIndex = 12,
}, root)

local barHolder = new("Frame", {
	Name = "BarHolder",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.fromScale(0.5, 0.92),
	Size = UDim2.new(BAR_W, 0, 0, 12),
	BackgroundTransparency = 1,
	ZIndex = 12,
}, root)

local barBack = new("Frame", {
	Name = "BarBack",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.fromRGB(12, 8, 28),
	BackgroundTransparency = 0.15,
	BorderSizePixel = 0,
	ClipsDescendants = true,
	ZIndex = 1,
}, barHolder)
new("UICorner", { CornerRadius = UDim.new(1, 0) }, barBack)

local fill = new("Frame", {
	Name = "Fill",
	Size = UDim2.fromScale(0, 1),
	BackgroundColor3 = Color3.new(1, 1, 1),
	BorderSizePixel = 0,
	ClipsDescendants = true,
	ZIndex = 2,
}, barBack)
new("UICorner", { CornerRadius = UDim.new(1, 0) }, fill)
local fillGrad = new("UIGradient", { Color = ColorSequence.new(PINK, CYAN) }, fill)

-- Brillo que recorre el relleno
local shine = new("Frame", {
	Name = "Shine",
	Size = UDim2.fromScale(0.3, 1),
	BackgroundColor3 = Color3.new(1, 1, 1),
	BorderSizePixel = 0,
	ZIndex = 3,
}, fill)
new("UIGradient", {
	Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.5, 0.35),
		NumberSequenceKeypoint.new(1, 1),
	}),
}, shine)

local barOutline = new("Frame", {
	Name = "BarOutline",
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	ZIndex = 4,
}, barHolder)
new("UICorner", { CornerRadius = UDim.new(1, 0) }, barOutline)
local barStroke = new("UIStroke", {
	Thickness = 2,
	Color = Color3.new(1, 1, 1),
	ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
}, barOutline)
local barStrokeGrad = new("UIGradient", { Color = cycleSequence(0) }, barStroke)

-- Punta luminosa de la barra
local tipGlow = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(0, 0, 0.5, 0),
	Size = UDim2.fromOffset(26, 26),
	BackgroundColor3 = CYAN,
	BackgroundTransparency = 0.7,
	BorderSizePixel = 0,
	Visible = false,
	ZIndex = 5,
}, barHolder)
new("UICorner", { CornerRadius = UDim.new(1, 0) }, tipGlow)
local tipCore = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(0, 0, 0.5, 0),
	Size = UDim2.fromOffset(9, 9),
	BackgroundColor3 = Color3.new(1, 1, 1),
	BorderSizePixel = 0,
	Visible = false,
	ZIndex = 6,
}, barHolder)
new("UICorner", { CornerRadius = UDim.new(1, 0) }, tipCore)

-- Destello blanco (al completar)
local flash = new("Frame", {
	Name = "Flash",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.new(1, 1, 1),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ZIndex = 13,
}, root)

gui.Parent = playerGui

----------------------------------------------------------------------
-- PRECARGA DE IMÁGENES (avisa en Output si algún ID falla)
----------------------------------------------------------------------
local imagesReady = false
task.spawn(function()
	pcall(function()
		ContentProvider:PreloadAsync({ bg, logoMain }, function(contentId, status)
			if status ~= Enum.AssetFetchStatus.Success then
				warn(("[LoadingScreen] No se pudo cargar %s (%s). Verifica que sea el ID de la IMAGEN (no del Decal) y que esté aprobada.")
					:format(tostring(contentId), tostring(status)))
			end
		end)
	end)
	imagesReady = true
end)

----------------------------------------------------------------------
-- ANIMACIONES CONTINUAS
----------------------------------------------------------------------
local exitAlpha = new("NumberValue", { Value = 0 }, nil) -- 0 -> 1 al cerrar
local energy = new("NumberValue", { Value = 0 }, nil)    -- pico de energía al completar
local completed = false
local closing = false
local t0 = os.clock()
local nextGlitch = 2.2
local glitchUntil = 0

local function startAnimations()
	local last = os.clock()
	return RunService.RenderStepped:Connect(function()
		local now = os.clock()
		local dt = math.min(now - last, 0.1)
		last = now
		local t = now - t0
		local ex = exitAlpha.Value
		local en = energy.Value

		-- Fondo: respiración, deriva suave y zoom al salir
		local z = 1.08 + 0.02 * math.sin(t * 0.5) + ex * 0.15
		bg.Size = UDim2.fromScale(z, z)
		bg.Position = UDim2.fromScale(0.5 + 0.006 * math.sin(t * 0.31), 0.5 + 0.005 * math.cos(t * 0.23))
		tint.BackgroundColor3 = paletteColor(t * 0.05)
		tint.BackgroundTransparency = math.clamp(0.86 + 0.04 * math.sin(t * 1.3) - en * 0.1, 0, 1)

		-- Barrido de luz cada 5 s
		sweep.Position = UDim2.fromScale(-0.3 + 1.6 * ((t % 5) / 5), 0.5)

		-- Aura: rayos giratorios y halos pulsantes
		rayRoot.Rotation = t * 7
		for i, r in ipairs(rays) do
			local len = r.len * (0.85 + 0.15 * math.sin(t * 2.2 + i) + en * 0.3)
			r.frame.Size = UDim2.new(len, 0, 0, r.frame.Size.Y.Offset)
			r.frame.BackgroundColor3 = paletteColor(t * 0.1 + i / RAY_COUNT * 0.6)
			r.frame.BackgroundTransparency = math.clamp(0.5 + 0.25 * math.sin(t * 3 + i * 1.7) - en * 0.25, 0, 1)
		end
		for i, h in ipairs(halo) do
			local s = h.base * (1 + 0.06 * math.sin(t * 1.8 + i * 0.7) + en * 0.12)
			h.frame.Size = UDim2.fromScale(s, s)
			h.frame.BackgroundColor3 = paletteColor(t * 0.08 + i * 0.05)
			h.frame.BackgroundTransparency = math.clamp(0.93 - en * 0.05 - 0.02 * math.sin(t * 2 + i), 0, 1)
		end

		-- Logo: flotación, balanceo, pulso y glitch periódico
		if t >= nextGlitch then
			glitchUntil = t + 0.2
			nextGlitch = t + RNG:NextNumber(2.5, 5)
		end
		local glitching = t < glitchUntil
		local jx, jy = 0, 0
		if glitching then
			jx = RNG:NextNumber(-0.012, 0.012)
			jy = RNG:NextNumber(-0.006, 0.006)
		end
		logoHolder.Position = UDim2.fromScale(0.5 + jx, 0.5 + 0.015 * math.sin(t * 1.4) + jy)
		logoHolder.Rotation = 1.5 * math.sin(t * 0.9)
		logoScale.Scale = 1 + 0.025 * math.sin(t * 2) + ex * 0.1 + en * 0.04

		if glitching then
			chromaR.ImageTransparency = 0.35
			chromaC.ImageTransparency = 0.35
			chromaR.Position = UDim2.fromScale(0.5 + RNG:NextNumber(0.008, 0.03), 0.5)
			chromaC.Position = UDim2.fromScale(0.5 - RNG:NextNumber(0.008, 0.03), 0.5)
		else
			chromaR.ImageTransparency = 1
			chromaC.ImageTransparency = 1
		end

		for i, g in ipairs(glowLayers) do
			local a = t * 1.3 + i * 2.1
			g.inst.Position = UDim2.fromScale(0.5 + 0.008 * math.cos(a), 0.5 + 0.008 * math.sin(a))
			g.inst.ImageColor3 = paletteColor(t * 0.1 + i * 0.12)
			local pulse = (math.sin(t * 2 + i * 0.7) + 1) / 2
			g.inst.ImageTransparency = math.clamp(g.base + 0.15 * (1 - pulse) - 0.12 - en * 0.25, 0, 1)
		end

		for _, s in ipairs(sparkles) do
			local v = math.max(0, math.sin(t * s.speed + s.phase))
			s.inst.BackgroundTransparency = 1 - v
			local sz = s.size * (0.6 + 0.8 * v)
			s.inst.Size = UDim2.fromOffset(sz, sz)
		end

		-- Partículas flotantes
		local speedMul = 1 + en * 4 + ex * 6
		for _, p in ipairs(particles) do
			p.y = p.y - p.speed * dt * speedMul
			if p.y < -0.05 then
				p.y = 1.05
				p.x = RNG:NextNumber()
			end
			p.inst.Position = UDim2.fromScale(p.x + p.amp * math.sin(t * p.wob + p.phase), p.y)
			local tw = (math.sin(t * p.tw + p.phase) + 1) / 2
			if p.big then
				p.inst.BackgroundTransparency = 0.86 + 0.08 * (1 - tw)
			else
				p.inst.BackgroundTransparency = 0.05 + 0.6 * (1 - tw)
			end
			p.inst.BackgroundColor3 = p.white and Color3.new(1, 1, 1) or paletteColor(t * 0.06 + p.hue)
		end

		-- Marco: color fluyendo por el perímetro + luz que lo recorre
		local breathe = 0.05 * math.sin(t * 1.5)
		for _, s in ipairs(edgeSegs) do
			s.inst.BackgroundColor3 = paletteColor(s.p + t * 0.08)
			local wave = 0.5 + 0.5 * math.sin((s.p * 2 - t * 0.25) * math.pi * 2)
			s.inst.BackgroundTransparency = math.clamp(0.25 + 0.5 * (1 - wave) - breathe - en * 0.2, 0, 1)
		end
		borderGrad.Color = cycleSequence(t * 0.1)
		borderGrad.Rotation = (t * 80) % 360

		-- Barra
		local fs = fill.Size.X.Scale
		local showTip = fs > 0.004 and not completed
		tipGlow.Visible = showTip
		tipCore.Visible = showTip
		if showTip then
			tipGlow.Position = UDim2.new(fs, 0, 0.5, 0)
			tipCore.Position = UDim2.new(fs, 0, 0.5, 0)
			local pulse = 26 + 8 * math.sin(t * 7)
			tipGlow.Size = UDim2.fromOffset(pulse, pulse)
			tipGlow.BackgroundColor3 = paletteColor(t * 0.15 + 0.35)
		end
		shine.Position = UDim2.fromScale(((t * 0.9) % 1.4) - 0.3, 0)
		fillGrad.Color = ColorSequence.new(paletteColor(t * 0.15), paletteColor(t * 0.15 + 0.35))
		barStrokeGrad.Color = cycleSequence(t * 0.15)
		barStrokeGrad.Rotation = (t * 120) % 360
		barGlow.BackgroundColor3 = paletteColor(t * 0.15 + 0.15)
		barGlow.BackgroundTransparency = math.clamp(0.78 + 0.08 * math.sin(t * 3) - en * 0.25, 0, 1)
		loadingLabel.TextStrokeColor3 = paletteColor(t * 0.15)

		if completed and not closing then
			loadingLabel.TextTransparency = 0.25 * (math.sin(t * 4) + 1) / 2
		end
	end)
end

----------------------------------------------------------------------
-- EFECTOS AL COMPLETAR
----------------------------------------------------------------------
local function shockwave(delay, color)
	task.delay(delay, function()
		local ring = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(CX, CY),
			Size = UDim2.fromScale(0.05, 0.05),
			BackgroundTransparency = 1,
			ZIndex = 12,
		}, root)
		new("UIAspectRatioConstraint", { AspectRatio = 1, DominantAxis = Enum.DominantAxis.Height }, ring)
		new("UICorner", { CornerRadius = UDim.new(1, 0) }, ring)
		local st = new("UIStroke", { Thickness = 4, Color = color, Transparency = 0.1 }, ring)
		tween(ring, 1.4, { Size = UDim2.fromScale(1.7, 1.7) }, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
		tween(st, 1.4, { Transparency = 1, Thickness = 1 }, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
		task.wait(1.5)
		ring:Destroy()
	end)
end

local function celebrate()
	energy.Value = 1
	tween(energy, 1.8, { Value = 0 }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	tween(flash, 0.12, { BackgroundTransparency = 0.8 })
	task.delay(0.12, function()
		tween(flash, 0.7, { BackgroundTransparency = 1 })
	end)
	shockwave(0, PINK)
	shockwave(0.25, CYAN)
end

----------------------------------------------------------------------
-- SECUENCIA PRINCIPAL
----------------------------------------------------------------------
task.spawn(function()
	local startClock = os.clock()
	task.wait(CONFIG.StartDelay)
	-- espera (máx. 4 s extra) a que carguen las imágenes para que no aparezcan "de golpe"
	while not imagesReady and os.clock() - startClock < CONFIG.StartDelay + 4 do
		task.wait()
	end

	if CONFIG.HideRobloxUI then
		task.spawn(hideRobloxUI)
	end
	gui.Enabled = true
	t0 = os.clock()
	local animConn = startAnimations()

	-- Aparición
	tween(root, CONFIG.FadeInTime, { GroupTransparency = 0 })
	tween(logoAnchor, 1.3, { Position = UDim2.fromScale(CX, CY) }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	tween(auraScale, 1.6, { Scale = 1 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

	-- Barra de carga (5 s)
	local fillTween = TweenService:Create(
		fill,
		TweenInfo.new(CONFIG.LoadTime, Enum.EasingStyle.Linear),
		{ Size = UDim2.fromScale(1, 1) }
	)
	fillTween:Play()
	fillTween.Completed:Wait()

	loadingLabel.Text = "Loading Completed"
	completed = true
	celebrate()

	-- Espera clic / toque (la pantalla NO se quita sola)
	local inputConn
	inputConn = UserInputService.InputBegan:Connect(function(input)
		if closing then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			closing = true
			inputConn:Disconnect()

			loadingLabel.TextTransparency = 0
			tween(exitAlpha, CONFIG.FadeOutTime, { Value = 1 })
			local out = tween(root, CONFIG.FadeOutTime, { GroupTransparency = 1 })
			out.Completed:Wait()

			animConn:Disconnect()
			exitAlpha:Destroy()
			energy:Destroy()
			gui:Destroy()
			if CONFIG.HideRobloxUI then
				restoreRobloxUI()
			end
		end
	end)
end)
