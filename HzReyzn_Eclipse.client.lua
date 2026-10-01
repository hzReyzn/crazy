-- HzReyzn Eclipse | LocalScript | PC / Mobile
-- INSTALACION: StarterPlayer > StarterPlayerScripts > LocalScript.
-- Pega este contenido y pulsa Play. El efecto es local para cada jugador.
-- No requiere IDs, HttpGet, assets externos ni modificaciones al personaje.
-- Es una simulacion cinematografica con Lighting y geometria GUI, no GLSL.
-- MIRAR SOL orienta la camara una sola vez; luego puedes moverla normalmente.
-- X restaura el ambiente original. Reejecutar reemplaza la instancia anterior.
-- API consultada: https://create.roblox.com/docs/reference/engine/classes/BillboardGui
-- https://create.roblox.com/docs/reference/engine/classes/Lighting/GetSunDirection

local CONFIG = {
    Approach = 34,       -- segundos: acercamiento
    Totality = 16,       -- segundos: luna centrada sobre el sol
    Departure = 34,
    Daylight = 12,       -- descanso antes de repetir
    Loop = true,
    ClockTime = 15,      -- sol a una altura facil de observar
    Latitude = 20,
    Distance = 6000,
    CanvasStuds = 1500,
    SunDiameter = 0.25,  -- fraccion del lienzo: tamano cinematografico
    CoronaLayers = 24,
}

local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local player = Players.LocalPlayer
assert(player, "Ejecuta Eclipse desde un LocalScript en el cliente.")
local playerGui = player:WaitForChild("PlayerGui")

local old = playerGui:FindFirstChild("HzReyznEclipse")
if old then
    local stop = old:FindFirstChild("StopEclipse")
    if stop and stop:IsA("BindableEvent") then stop:Fire() end
    if old.Parent then old:Destroy() end
end

local function make(class, props, parent)
    local obj = Instance.new(class)
    for key, value in pairs(props) do obj[key] = value end
    obj.Parent = parent
    return obj
end
local function round(obj, amount)
    make("UICorner", {CornerRadius = UDim.new(amount or 1, 0)}, obj)
end
local function mix(a, b, t) return a + (b - a) * t end
local function smooth(t)
    t = math.clamp(t, 0, 1)
    return t * t * (3 - 2 * t)
end
local function color(r, g, b) return Color3.fromRGB(r, g, b) end

local gui = make("ScreenGui", {
    Name = "HzReyznEclipse", ResetOnSpawn = false,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling, DisplayOrder = 30,
}, playerGui)
local stopEvent = make("BindableEvent", {Name = "StopEclipse"}, gui)
local connections, saved, disabled, parked = {}, {}, {}, {}
local closed = false
local lightingKeys = {
    "ClockTime", "GeographicLatitude", "Brightness", "Ambient", "OutdoorAmbient",
    "ExposureCompensation", "ColorShift_Top", "ColorShift_Bottom", "GlobalShadows",
    "EnvironmentDiffuseScale", "EnvironmentSpecularScale", "FogStart", "FogEnd", "FogColor",
}
for _, key in ipairs(lightingKeys) do saved[key] = Lighting[key] end
-- Conservar las instancias originales para restaurarlas al cerrar.
for _, obj in ipairs(Lighting:GetChildren()) do
    if obj:IsA("Atmosphere") then
        table.insert(parked, obj)
        obj.Parent = nil
    elseif obj:IsA("PostEffect") then
        disabled[obj] = obj.Enabled
        obj.Enabled = false
    end
end
local function suppressCameraEffects(camera)
    if not camera then return end
    for _, obj in ipairs(camera:GetChildren()) do
        if obj:IsA("PostEffect") and disabled[obj] == nil then
            disabled[obj] = obj.Enabled
            obj.Enabled = false
        end
    end
end
suppressCameraEffects(workspace.CurrentCamera)
local sky = Lighting:FindFirstChildOfClass("Sky")
local ownSky = not sky
if not sky then sky = make("Sky", {}, Lighting) end
local celestial, stars = sky.CelestialBodiesShown, sky.StarCount
sky.CelestialBodiesShown = false
sky.StarCount = 0

local atmosphere = make("Atmosphere", {
    Name = "EclipseAtmosphere", Density = 0.25, Offset = 0.1,
    Color = color(199, 218, 238), Decay = color(114, 135, 172), Haze = 1.1, Glare = 0,
}, Lighting)
local grade = make("ColorCorrectionEffect", {Name = "EclipseGrade"}, Lighting)
local bloom = make("BloomEffect", {
    Name = "EclipseBloom", Intensity = 0.12, Size = 30, Threshold = 1.3,
}, Lighting)
local rays = make("SunRaysEffect", {
    Name = "EclipseRays", Intensity = 0.045, Spread = 0.82,
}, Lighting)
Lighting.ClockTime = CONFIG.ClockTime
Lighting.GeographicLatitude = CONFIG.Latitude
Lighting.GlobalShadows = true
Lighting.FogStart = 0
Lighting.FogEnd = 100000
local sunDirection = Lighting:GetSunDirection()

local anchor = make("Part", {
    Name = "EclipseCelestialAnchor", Anchored = true, Transparency = 1,
    CanCollide = false, CanQuery = false, CanTouch = false,
    CastShadow = false, Size = Vector3.new(1, 1, 1),
}, workspace)
-- AlwaysOnTop=false: los edificios y montanas ocultan el eclipse.
local skyGui = make("BillboardGui", {
    Name = "ProceduralEclipse", Adornee = anchor,
    Size = UDim2.fromScale(CONFIG.CanvasStuds, CONFIG.CanvasStuds),
    AlwaysOnTop = false, LightInfluence = 0, Brightness = 2,
    MaxDistance = 100000, ClipsDescendants = false,
    ZIndexBehavior = Enum.ZIndexBehavior.Global,
}, playerGui)

local function disc(parent, name, diameter, tint, z)
    local obj = make("Frame", {
        Name = name, AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(diameter, diameter),
        BackgroundColor3 = tint, BorderSizePixel = 0, ZIndex = z,
    }, parent)
    round(obj)
    return obj
end
local D = CONFIG.SunDiameter
local halos = {}
for i = CONFIG.CoronaLayers, 1, -1 do
    local f = i / CONFIG.CoronaLayers
    local halo = disc(skyGui, "Corona", D * (1.03 + f * 1.6), color(218, 232, 255), 1)
    halo.BackgroundTransparency = 0.98
    table.insert(halos, {obj = halo, f = f})
end
local streamers = {}
for i = 1, 12 do
    local angle = i * math.pi / 6 + 0.15
    local ray = make("Frame", {
        Name = "CoronalStreamer", AnchorPoint = Vector2.new(0.5, 0.5),
        BackgroundColor3 = color(205, 224, 255), BackgroundTransparency = 0.95,
        BorderSizePixel = 0, ZIndex = 2, Rotation = math.deg(angle),
        Size = UDim2.fromScale(D * 1.45, D * 0.09),
    }, skyGui)
    round(ray)
    make("UIGradient", {Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.28, 0.3),
        NumberSequenceKeypoint.new(0.5, 0), NumberSequenceKeypoint.new(0.72, 0.3),
        NumberSequenceKeypoint.new(1, 1),
    })}, ray)
    table.insert(streamers, {obj = ray, angle = angle})
end
local sun = disc(skyGui, "Sun", D, color(255, 244, 218), 5)
make("UIGradient", {
    Rotation = 75, Color = ColorSequence.new(color(255, 255, 241), color(255, 205, 122)),
}, sun)
local moon = disc(skyGui, "Moon", D * 1.035, color(5, 7, 12), 10)
local rim = make("UIStroke", {
    Color = color(223, 229, 255), Thickness = 1, Transparency = 1,
    ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
}, moon)
local diamond = disc(skyGui, "DiamondRing", D * 0.105, color(255, 250, 225), 12)
local diamondGlow = disc(skyGui, "DiamondGlow", D * 0.30, color(255, 228, 190), 11)

local panel = make("Frame", {
    Name = "Controls", Position = UDim2.fromOffset(18, 100), Size = UDim2.fromOffset(286, 155),
    BackgroundColor3 = color(12, 15, 24), BackgroundTransparency = 0.12,
    BorderSizePixel = 0, Active = true,
}, gui)
round(panel, 0.08)
make("UIStroke", {Color = color(107, 132, 187), Transparency = 0.35, Thickness = 1}, panel)
local title = make("TextLabel", {
    BackgroundTransparency = 1, Position = UDim2.fromOffset(12, 8), Size = UDim2.fromOffset(207, 25),
    Text = "HzReyzn • ECLIPSE", TextColor3 = color(232, 238, 255),
    TextSize = 15, Font = Enum.Font.GothamBold, TextXAlignment = Enum.TextXAlignment.Left,
    Active = true,
}, panel)
local content = make("Frame", {
    BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 39), Size = UDim2.fromOffset(286, 112),
}, panel)
local status = make("TextLabel", {
    BackgroundTransparency = 1, Position = UDim2.fromOffset(12, 0), Size = UDim2.fromOffset(262, 22),
    Text = "Acercamiento", TextColor3 = color(184, 203, 238), TextSize = 12,
    Font = Enum.Font.Gotham, TextXAlignment = Enum.TextXAlignment.Left,
}, content)
local track = make("Frame", {
    Position = UDim2.fromOffset(12, 27), Size = UDim2.fromOffset(262, 4),
    BackgroundColor3 = color(39, 47, 65), BorderSizePixel = 0,
}, content)
round(track)
local fill = make("Frame", {
    Size = UDim2.fromScale(0, 1), BackgroundColor3 = color(178, 202, 255), BorderSizePixel = 0,
}, track)
round(fill)
local function button(parent, text, x, y, w, h)
    local b = make("TextButton", {
        Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(w, h), Text = text,
        TextSize = 11, Font = Enum.Font.GothamMedium, TextColor3 = color(230, 236, 253),
        BackgroundColor3 = color(35, 44, 65), BorderSizePixel = 0, AutoButtonColor = true,
    }, parent)
    round(b, 0.18)
    return b
end
local pauseButton = button(content, "PAUSAR", 12, 40, 82, 28)
local replayButton = button(content, "REPETIR", 102, 40, 82, 28)
local speedButton = button(content, "1x", 192, 40, 82, 28)
local lookButton = button(content, "MIRAR SOL", 12, 76, 262, 27)
local minimizeButton = button(panel, "−", 224, 9, 23, 23)
local closeButton = button(panel, "×", 252, 9, 23, 23)
local function connect(signal, callback)
    local c = signal:Connect(callback)
    table.insert(connections, c)
    return c
end
local function cleanup()
    if closed then return end
    closed = true
    for _, c in ipairs(connections) do c:Disconnect() end
    for _, obj in ipairs({skyGui, anchor, atmosphere, grade, bloom, rays}) do obj:Destroy() end
    for key, value in pairs(saved) do Lighting[key] = value end
    for obj, enabled in pairs(disabled) do
        if obj.Parent then obj.Enabled = enabled end
    end
    for _, obj in ipairs(parked) do obj.Parent = Lighting end
    if ownSky then sky:Destroy()
    elseif sky.Parent then sky.CelestialBodiesShown = celestial; sky.StarCount = stars end
    gui:Destroy()
end
connect(stopEvent.Event, cleanup)
connect(closeButton.Activated, cleanup)
connect(gui.Destroying, cleanup)
local paused, elapsed, speed, minimized = false, 0, 1, false
local cycle = CONFIG.Approach + CONFIG.Totality + CONFIG.Departure + CONFIG.Daylight
connect(pauseButton.Activated, function()
    paused = not paused
    pauseButton.Text = paused and "CONTINUAR" or "PAUSAR"
end)
connect(replayButton.Activated, function()
    elapsed = 0; paused = false; pauseButton.Text = "PAUSAR"
end)
connect(speedButton.Activated, function()
    speed = speed == 1 and 2 or (speed == 2 and 0.5 or 1)
    speedButton.Text = tostring(speed) .. "x"
end)
connect(minimizeButton.Activated, function()
    minimized = not minimized
    content.Visible = not minimized
    panel.Size = UDim2.fromOffset(286, minimized and 40 or 155)
    minimizeButton.Text = minimized and "+" or "−"
end)
connect(lookButton.Activated, function()
    local camera = workspace.CurrentCamera
    if camera then
        camera.CFrame = CFrame.lookAt(camera.CFrame.Position, camera.CFrame.Position + sunDirection)
    end
end)
-- Arrastre con mouse/tactil solo desde el titulo, sin interferir con botones.
local dragging, dragInput, dragStart, panelStart
connect(title.InputBegan, function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true; dragInput = input; dragStart = input.Position; panelStart = panel.Position
    end
end)
connect(UserInputService.InputEnded, function(input)
    if input == dragInput then dragging = false; dragInput = nil end
end)
connect(UserInputService.InputChanged, function(input)
    if not dragging then return end
    if input ~= dragInput and input.UserInputType ~= Enum.UserInputType.MouseMovement then return end
    local delta = input.Position - dragStart
    local viewport = gui.AbsoluteSize
    panel.Position = UDim2.fromOffset(
        math.clamp(panelStart.X.Offset + delta.X, 0, math.max(0, viewport.X - 286)),
        math.clamp(panelStart.Y.Offset + delta.Y, 0, math.max(0, viewport.Y - panel.AbsoluteSize.Y)))
end)
connect(workspace:GetPropertyChangedSignal("CurrentCamera"), function()
    suppressCameraEffects(workspace.CurrentCamera)
end)

-- Area de interseccion de dos discos, en unidades de radio solar.
-- La iluminacion sigue la superficie realmente cubierta, no un simple temporizador.
local function coverage(d)
    local r = 1.035
    d = math.abs(d)
    if d >= 1 + r then return 0 end
    if d <= r - 1 then return 1 end
    local a = math.acos(math.clamp((d*d + 1 - r*r) / (2*d), -1, 1))
    local b = math.acos(math.clamp((d*d + r*r - 1) / (2*d*r), -1, 1))
    local area = a + r*r*b - 0.5 * math.sqrt(math.max(0, (-d+1+r)*(d+1-r)*(d-1+r)*(d+1+r)))
    return math.clamp(area / math.pi, 0, 1)
end
local uiClock = 0
connect(RunService.RenderStepped, function(dt)
    local camera = workspace.CurrentCamera
    if not camera or closed then return end
    if not paused then elapsed = elapsed + dt * speed end
    if elapsed >= cycle then
        if CONFIG.Loop then elapsed = elapsed % cycle else elapsed = cycle end
    end
    local x, phase
    if elapsed < CONFIG.Approach then
        x = -2.35 * (1 - smooth(elapsed / CONFIG.Approach)); phase = "Acercamiento"
    elseif elapsed < CONFIG.Approach + CONFIG.Totality then
        x = 0; phase = "Totalidad • corona solar"
    elseif elapsed < CONFIG.Approach + CONFIG.Totality + CONFIG.Departure then
        x = 2.35 * smooth((elapsed - CONFIG.Approach - CONFIG.Totality) / CONFIG.Departure)
        phase = "Salida del eclipse"
    else x = 2.35; phase = "Luz restaurada" end
    local covered = coverage(x)
    local darkness = covered ^ 1.65
    local total = smooth((covered - 0.92) / 0.08)
    -- Bloqueo de hora: evita que un ciclo local del mapa desplace el sol visual.
    Lighting.ClockTime = CONFIG.ClockTime
    Lighting.GeographicLatitude = CONFIG.Latitude
    anchor.Position = camera.CFrame.Position + sunDirection * CONFIG.Distance
    moon.Position = UDim2.fromScale(0.5 + x * D * 0.5, 0.5)
    -- La cara nocturna aparece solo al acercarse al disco solar.
    moon.BackgroundTransparency = 1 - smooth((2.35 - math.abs(x)) / 0.24)
    rim.Transparency = 1 - total * 0.42
    for _, h in ipairs(halos) do
        local pulse = 1 + 0.025 * math.sin(elapsed * 0.8 + h.f * 4)
        local size = D * (1.03 + h.f * 1.6) * pulse
        h.obj.Size = UDim2.fromScale(size, size)
        local opacity = (0.018 * (1 - covered) + 0.045 * total) * (1 - h.f * 0.75)
        h.obj.BackgroundTransparency = 1 - opacity
    end
    for i, item in ipairs(streamers) do
        local a = item.angle + 0.012 * math.sin(elapsed * 0.25 + i)
        item.obj.Position = UDim2.fromScale(0.5 + math.cos(a)*D*0.51, 0.5 + math.sin(a)*D*0.51)
        item.obj.Rotation = math.deg(a)
        item.obj.BackgroundTransparency = 1 - total * (0.035 + 0.012 * math.sin(elapsed * 0.55 + i))
    end
    -- Breve destello de contacto, continuo y sin parpadeo estroboscopico.
    local contact = math.exp(-((math.abs(x) - 0.075) / 0.038)^2)
    local side = x <= 0 and 1 or -1
    local p = UDim2.fromScale(0.5 + side * D * 0.49, 0.5)
    diamond.Position = p; diamondGlow.Position = p
    diamond.BackgroundTransparency = 1 - contact * 0.95
    diamondGlow.BackgroundTransparency = 1 - contact * 0.20
    Lighting.Brightness = mix(2.4, 0.18, darkness)
    Lighting.ExposureCompensation = mix(0.05, -0.65, darkness)
    Lighting.Ambient = color(92, 95, 114):Lerp(color(15, 20, 38), darkness)
    Lighting.OutdoorAmbient = color(142, 148, 166):Lerp(color(31, 39, 65), darkness)
    Lighting.ColorShift_Top = color(255, 236, 213):Lerp(color(128, 153, 215), darkness)
    Lighting.ColorShift_Bottom = color(0, 0, 0)
    Lighting.EnvironmentDiffuseScale = mix(0.75, 0.25, darkness)
    Lighting.EnvironmentSpecularScale = mix(0.8, 0.35, darkness)
    atmosphere.Color = color(199, 218, 238):Lerp(color(78, 91, 132), darkness)
    atmosphere.Decay = color(114, 135, 172):Lerp(color(31, 37, 69), darkness)
    atmosphere.Density = mix(0.25, 0.31, darkness)
    atmosphere.Haze = mix(1.1, 1.65, darkness)
    grade.TintColor = color(255, 247, 234):Lerp(color(176, 194, 235), darkness)
    grade.Saturation = mix(0.04, -0.24, darkness)
    grade.Contrast = mix(0.04, 0.16, darkness)
    grade.Brightness = mix(0, -0.035, darkness)
    rays.Intensity = 0.045 * (1 - covered)^2
    bloom.Intensity = mix(0.12, 0.28, total) + contact * 0.12
    uiClock = uiClock + dt
    if uiClock >= 0.1 then
        uiClock = 0
        status.Text = string.format("%s  |  %d%%", phase, math.floor(covered * 100 + 0.5))
        fill.Size = UDim2.fromScale(elapsed / cycle, 1)
    end
end)
