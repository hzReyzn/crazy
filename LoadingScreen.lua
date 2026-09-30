--[[
	PANTALLA DE CARGA - Roblox (Luau)
	Tipo: LocalScript
	Ubicación: StarterGui  (o StarterPlayer > StarterPlayerScripts)

	ANTES DE USAR:
	1) Sube tus 2 imágenes a Roblox (Creator Hub > Assets > Image).
	2) Copia el ID de cada una y pégalo en CONFIG (BackgroundId y LogoId).
	   Formato: "rbxassetid://123456789"
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

----------------------------------------------------------------------
-- CONFIGURACIÓN
----------------------------------------------------------------------
local CONFIG = {
	BackgroundId = "rbxassetid://0", -- << Imagen 1 (fondo)
	LogoId       = "rbxassetid://0", -- << Imagen 2 (logo)

	StartDelay = 1,     -- segundos antes de aparecer
	LoadTime   = 5,     -- segundos que tarda la barra
	FadeInTime = 0.8,   -- aparición
	FadeOutTime = 2,    -- desaparición (más alto = más suave)

	LogoPosition = UDim2.fromScale(0.75, 0.40), -- lado derecho del personaje
	LogoWidth = 0.42,                            -- ancho relativo a la pantalla
	LogoAspect = 1672 / 941,                     -- proporción de la imagen
}

local PINK   = Color3.fromRGB(255, 60, 255)
local PURPLE = Color3.fromRGB(140, 70, 255)
local CYAN   = Color3.fromRGB(0, 190, 255)

local borderGradient = ColorSequence.new({
	ColorSequenceKeypoint.new(0, PINK),
	ColorSequenceKeypoint.new(0.35, PURPLE),
	ColorSequenceKeypoint.new(0.7, CYAN),
	ColorSequenceKeypoint.new(1, PINK),
})

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
-- INTERFAZ
----------------------------------------------------------------------
local gui = new("ScreenGui", {
	Name = "LoadingScreen",
	IgnoreGuiInset = true,
	ResetOnSpawn = false,
	DisplayOrder = 999,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	Enabled = false, -- se activa después del delay
}, nil)

-- CanvasGroup: permite desvanecer TODO de forma uniforme y suave
local root = new("CanvasGroup", {
	Name = "Root",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.new(0, 0, 0),
	BorderSizePixel = 0,
	GroupTransparency = 1,
	Active = true, -- bloquea clics al juego mientras está visible
}, gui)

-- Fondo (imagen 1)
local bg = new("ImageLabel", {
	Name = "Background",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromScale(1.06, 1.06),
	BackgroundTransparency = 1,
	Image = CONFIG.BackgroundId,
	ScaleType = Enum.ScaleType.Crop,
	ZIndex = 1,
}, root)

-- Oscurecido inferior (para que la barra se lea bien)
local shade = new("Frame", {
	Name = "Shade",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.new(0, 0, 0),
	BorderSizePixel = 0,
	ZIndex = 2,
}, root)
new("UIGradient", {
	Rotation = 90,
	Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.6, 1),
		NumberSequenceKeypoint.new(1, 0.35),
	}),
}, shade)

-- LOGO (imagen 2) ------------------------------------------------------
local logoAnchor = new("Frame", {
	Name = "LogoAnchor",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.92, CONFIG.LogoPosition.Y.Scale), -- entra desde la derecha
	Size = UDim2.fromScale(CONFIG.LogoWidth, CONFIG.LogoWidth),
	BackgroundTransparency = 1,
	ZIndex = 5,
}, root)
new("UIAspectRatioConstraint", {
	AspectRatio = CONFIG.LogoAspect,
	DominantAxis = Enum.DominantAxis.Width,
}, logoAnchor)

local logoHolder = new("Frame", {
	Name = "LogoHolder",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	ZIndex = 5,
}, logoAnchor)
local logoScale = new("UIScale", { Scale = 1 }, logoHolder)

-- Capas de aura/brillo (copias más grandes y tintadas detrás del logo)
local glowLayers = {}
local glowDefs = {
	{ size = 1.05, trans = 0.55 },
	{ size = 1.10, trans = 0.72 },
	{ size = 1.17, trans = 0.86 },
}
for i, def in ipairs(glowDefs) do
	local layer = new("ImageLabel", {
		Name = "Glow" .. i,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(def.size, def.size),
		BackgroundTransparency = 1,
		Image = CONFIG.LogoId,
		ImageColor3 = PINK,
		ImageTransparency = def.trans,
		ZIndex = 4,
	}, logoHolder)
	table.insert(glowLayers, { inst = layer, base = def.trans })
end

-- Logo principal
new("ImageLabel", {
	Name = "Logo",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	Image = CONFIG.LogoId,
	ZIndex = 6,
}, logoHolder)

-- Destellos (luces brillantes que parpadean alrededor del logo)
local sparkles = {}
local rng = Random.new()
local sparkleColors = { Color3.new(1, 1, 1), PINK, CYAN }
for i = 1, 18 do
	local s = rng:NextInteger(3, 7)
	local f = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(rng:NextNumber(0.02, 0.98), rng:NextNumber(0.05, 0.95)),
		Size = UDim2.fromOffset(s, s),
		BackgroundColor3 = sparkleColors[rng:NextInteger(1, #sparkleColors)],
		BorderSizePixel = 0,
		ZIndex = 7,
	}, logoHolder)
	new("UICorner", { CornerRadius = UDim.new(1, 0) }, f)
	table.insert(sparkles, {
		inst = f,
		phase = rng:NextNumber(0, math.pi * 2),
		speed = rng:NextNumber(1.5, 3.5),
	})
end

-- MARCO CON DEGRADADO ---------------------------------------------------
local border = new("Frame", {
	Name = "Border",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.new(1, -16, 1, -16),
	BackgroundTransparency = 1,
	ZIndex = 10,
}, root)
new("UICorner", { CornerRadius = UDim.new(0, 14) }, border)
local borderStroke = new("UIStroke", {
	Thickness = 6,
	Color = Color3.new(1, 1, 1),
	ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
}, border)
local borderGrad = new("UIGradient", { Color = borderGradient }, borderStroke)

-- BARRA DE CARGA --------------------------------------------------------
local loadingLabel = new("TextLabel", {
	Name = "LoadingText",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 0.92, -18),
	Size = UDim2.new(0.36, 0, 0, 18),
	BackgroundTransparency = 1,
	Text = "Loading",
	Font = Enum.Font.GothamMedium,
	TextSize = 14, -- pequeño pero visible
	TextColor3 = Color3.new(1, 1, 1),
	TextStrokeColor3 = PURPLE,
	TextStrokeTransparency = 0.4,
	ZIndex = 11,
}, root)

local barBack = new("Frame", {
	Name = "BarBack",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.fromScale(0.5, 0.92),
	Size = UDim2.new(0.36, 0, 0, 12),
	BackgroundColor3 = Color3.fromRGB(12, 8, 28),
	BackgroundTransparency = 0.2,
	BorderSizePixel = 0,
	ClipsDescendants = true,
	ZIndex = 11,
}, root)
new("UICorner", { CornerRadius = UDim.new(1, 0) }, barBack)

local fill = new("Frame", {
	Name = "Fill",
	Size = UDim2.fromScale(0, 1),
	BackgroundColor3 = Color3.new(1, 1, 1),
	BorderSizePixel = 0,
	ZIndex = 12,
}, barBack)
new("UICorner", { CornerRadius = UDim.new(1, 0) }, fill)
local fillGrad = new("UIGradient", { Color = ColorSequence.new(PINK, CYAN) }, fill)

-- Borde de la barra (contorno con degradado)
local barOutline = new("Frame", {
	Name = "BarOutline",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.fromScale(0.5, 0.92),
	Size = UDim2.new(0.36, 0, 0, 12),
	BackgroundTransparency = 1,
	ZIndex = 13,
}, root)
new("UICorner", { CornerRadius = UDim.new(1, 0) }, barOutline)
local barStroke = new("UIStroke", {
	Thickness = 2,
	Color = Color3.new(1, 1, 1),
	ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
}, barOutline)
local barStrokeGrad = new("UIGradient", { Color = borderGradient }, barStroke)

gui.Parent = playerGui

----------------------------------------------------------------------
-- ANIMACIONES CONTINUAS
----------------------------------------------------------------------
local exitAlpha = new("NumberValue", { Value = 0 }, nil) -- 0 -> 1 al cerrar
local completed = false
local closing = false
local t0 = os.clock()

local function startAnimations()
	return RunService.RenderStepped:Connect(function()
		local t = os.clock() - t0

		-- Fondo: respiración lenta + zoom suave al salir
		local z = 1.06 + 0.02 * math.sin(t * 0.5) + exitAlpha.Value * 0.12
		bg.Size = UDim2.fromScale(z, z)

		-- Marco y contorno de barra: degradado giratorio
		borderGrad.Rotation = (t * 60) % 360
		barStrokeGrad.Rotation = (t * 120) % 360

		-- Logo: flotación, leve balanceo y pulso
		logoHolder.Position = UDim2.fromScale(0.5, 0.5 + 0.015 * math.sin(t * 1.4))
		logoHolder.Rotation = 1.5 * math.sin(t * 0.9)
		logoScale.Scale = 1 + 0.025 * math.sin(t * 2) + exitAlpha.Value * 0.08

		-- Aura: pulsa y cambia de color entre rosa y cian
		for i, g in ipairs(glowLayers) do
			local pulse = (math.sin(t * 2 + i * 0.6) + 1) / 2
			g.inst.ImageTransparency = math.clamp(g.base + 0.18 * (1 - pulse) - 0.1, 0, 1)
			g.inst.ImageColor3 = PINK:Lerp(CYAN, (math.sin(t * 1.2 + i) + 1) / 2)
		end

		-- Destellos parpadeando
		for _, s in ipairs(sparkles) do
			local v = math.max(0, math.sin(t * s.speed + s.phase))
			s.inst.BackgroundTransparency = 1 - v
		end

		-- Barra: el color del relleno fluye
		local a = (math.sin(t * 2) + 1) / 2
		fillGrad.Color = ColorSequence.new(PINK:Lerp(CYAN, a), CYAN:Lerp(PINK, a))

		-- Al completar: el texto "respira" invitando a hacer clic
		if completed and not closing then
			loadingLabel.TextTransparency = 0.25 * (math.sin(t * 4) + 1) / 2
		end
	end)
end

----------------------------------------------------------------------
-- SECUENCIA PRINCIPAL
----------------------------------------------------------------------
task.spawn(function()
	task.wait(CONFIG.StartDelay)

	gui.Enabled = true
	t0 = os.clock()
	local animConn = startAnimations()

	-- Aparición suave
	tween(root, CONFIG.FadeInTime, { GroupTransparency = 0 })
	tween(logoAnchor, 1.2, { Position = CONFIG.LogoPosition }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

	-- Barra de carga (5 segundos)
	local fillTween = TweenService:Create(
		fill,
		TweenInfo.new(CONFIG.LoadTime, Enum.EasingStyle.Linear),
		{ Size = UDim2.fromScale(1, 1) }
	)
	fillTween:Play()
	fillTween.Completed:Wait()

	loadingLabel.Text = "Loading Completed"
	completed = true

	-- Esperar clic / toque (la pantalla NO se quita sola)
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
			gui:Destroy()
		end
	end)
end)
