--!nonstrict
-- HzReyzn Eclipse | cinematic edition | English UI | PC / Mobile
-- Studio: StarterPlayer > StarterPlayerScripts > LocalScript.
-- All visuals are local. No downloads, custom asset IDs, or character changes.
-- The Sun is projected from a fixed sky direction; it is NOT glued to the camera.
-- Screen-space rays and lens reflections are artistic approximations inspired by
-- the supplied eclipse video. This is a Lighting/VFX script, not a GPU shader.
-- Occlusion is sampled: the celestial disc fades as a whole near obstacles.
-- Closing or rerunning restores the original Lighting and post effects.
-- Docs: create.roblox.com/docs/reference/engine/classes/Camera
--       create.roblox.com/docs/workspace/raycasting

local SETTINGS = {
    Approach = 30,
    Totality = 18,
    Departure = 30,
    Daylight = 8,
    Loop = true,
    SunAngularDiameter = 18, -- about 5x the previous apparent diameter
    ClockTime = 15.5,
    GeographicLatitude = 15,
    RayDistance = 12000,
    OcclusionInterval = 0.10,
    CoronaLayers = 26,
    RayCount = 32,
    MoonCraters = 46,
}

local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local Input = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local player = Players.LocalPlayer
assert(player, "Run HzReyzn Eclipse on the client, using a LocalScript.")
local playerGui = player:WaitForChild("PlayerGui")

-- Compatible with the original version's stop event.
local previous = playerGui:FindFirstChild("HzReyznEclipse")
if previous then
    local event = previous:FindFirstChild("StopEclipse")
    if event and event:IsA("BindableEvent") then
        event:Fire()
        -- Allow deferred event handlers to restore Lighting before taking a snapshot.
        RunService.Heartbeat:Wait()
    end
    if previous.Parent then previous:Destroy() end
end

local state = {
    closed = false, elapsed = 0, animationTime = 0, speed = 1, paused = false,
    loop = SETTINGS.Loop, size = 1, targetSize = 1, intensity = 1,
    visibility = 0, targetVisibility = 0, flareVisibility = 0, targetFlare = 0,
    darkness = 0, startup = 0, occlusionClock = 1, uiClock = 0,
    minimized = false, focus = nil, camera = nil, viewSize = Vector2.new(0, 0),
}
local connections, owned, parked, effects, snapshot = {}, {}, {}, {}, {}
local bindName = "HzReyznEclipseV2_" .. tostring(player.UserId)
local gui, sky, skySnapshot, panel, panelScale
local restoreFocus
local function safe(fn) pcall(fn) end
local function cleanup()
    if state.closed then return end
    state.closed = true
    RunService:UnbindFromRenderStep(bindName)
    for _, c in ipairs(connections) do c:Disconnect() end
    if restoreFocus then restoreFocus() end
    for i = #owned, 1, -1 do safe(function() owned[i]:Destroy() end) end
    for key, value in pairs(snapshot) do safe(function() Lighting[key] = value end) end
    for obj, enabled in pairs(effects) do
        safe(function() if obj.Parent then obj.Enabled = enabled end end)
    end
    for _, obj in ipairs(parked) do safe(function() obj.Parent = Lighting end) end
    if skySnapshot and sky and sky.Parent then
        for key, value in pairs(skySnapshot) do safe(function() sky[key] = value end) end
    end
end
local function connect(signal, callback)
    local c = signal:Connect(callback)
    table.insert(connections, c)
    return c
end
local function make(class, props, parent)
    local obj = Instance.new(class)
    for key, value in pairs(props or {}) do obj[key] = value end
    obj.Parent = parent
    return obj
end
local function own(obj) table.insert(owned, obj); return obj end
local function rgb(r, g, b) return Color3.fromRGB(r, g, b) end
local function lerp(a, b, t) return a + (b - a) * t end
local function smooth(t)
    t = math.clamp(t, 0, 1)
    return t*t*(3 - 2*t)
end
local function damp(a, b, rate, dt) return lerp(a, b, 1 - math.exp(-rate*dt)) end
local function corner(obj, pixels)
    make("UICorner", {CornerRadius = pixels and UDim.new(0, pixels) or UDim.new(0.5, 0)}, obj)
end
local function circle(parent, name, size, tint, z)
    local obj = make("Frame", {
        Name = name, AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(size, size),
        BackgroundColor3 = tint, BorderSizePixel = 0, ZIndex = z or 1,
    }, parent)
    corner(obj)
    return obj
end
local function alpha(obj, opacity)
    obj.BackgroundTransparency = 1 - math.clamp(opacity, 0, 1)
end
local function gradientFade(obj, center)
    return make("UIGradient", {Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 1),
        NumberSequenceKeypoint.new(0.22, 0.70),
        NumberSequenceKeypoint.new(0.5, center or 0),
        NumberSequenceKeypoint.new(0.78, 0.70),
        NumberSequenceKeypoint.new(1, 1),
    })}, obj)
end

-- Overlap area of the solar/lunar discs. Radius of the Sun = 1.
local function coverage(distance)
    local d, r = math.abs(distance), 1.025
    if d >= 1 + r then return 0 end
    if d <= r - 1 then return 1 end
    local a = math.acos(math.clamp((d*d + 1 - r*r)/(2*d), -1, 1))
    local b = math.acos(math.clamp((d*d + r*r - 1)/(2*d*r), -1, 1))
    local area = a + r*r*b - 0.5*math.sqrt(math.max(0, (-d+1+r)*(d+1-r)*(d-1+r)*(d+1+r)))
    return math.clamp(area/math.pi, 0, 1)
end
local cycle = SETTINGS.Approach + SETTINGS.Totality + SETTINGS.Departure + SETTINGS.Daylight
local function phaseAt(t)
    if t < SETTINGS.Approach then
        return -2.28*(1 - smooth(t/SETTINGS.Approach)), "FIRST CONTACT"
    elseif t < SETTINGS.Approach + SETTINGS.Totality then
        return 0, "TOTAL ECLIPSE"
    elseif t < SETTINGS.Approach + SETTINGS.Totality + SETTINGS.Departure then
        return 2.28*smooth((t - SETTINGS.Approach - SETTINGS.Totality)/SETTINGS.Departure), "LAST CONTACT"
    end
    return 2.28, "DAYLIGHT"
end

local function start()
    gui = own(make("ScreenGui", {
        Name = "HzReyznEclipse", ResetOnSpawn = false, DisplayOrder = 35,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    }, playerGui))
    connect(make("BindableEvent", {Name = "StopEclipse"}, gui).Event, cleanup)
    connect(gui.Destroying, cleanup)
    local scene = own(make("ScreenGui", {
        Name = "HzReyznEclipseOptics", ResetOnSpawn = false, DisplayOrder = -5,
        IgnoreGuiInset = true, ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    }, playerGui))
    -- Match WorldToViewportPoint, including phones with safe-area insets.
    safe(function() scene.ScreenInsets = Enum.ScreenInsets.None end)
    safe(function() scene.ClipToDeviceSafeArea = false end)

    for _, key in ipairs({
        "ClockTime", "GeographicLatitude", "Brightness", "Ambient", "OutdoorAmbient",
        "ExposureCompensation", "ColorShift_Top", "ColorShift_Bottom", "GlobalShadows",
        "EnvironmentDiffuseScale", "EnvironmentSpecularScale", "FogStart", "FogEnd", "FogColor",
    }) do snapshot[key] = Lighting[key] end
    local function suppress(container)
        if not container then return end
        for _, obj in ipairs(container:GetChildren()) do
            if obj:IsA("PostEffect") and effects[obj] == nil then
                effects[obj] = obj.Enabled; obj.Enabled = false
            end
        end
    end
    suppress(Lighting)
    suppress(workspace.CurrentCamera)
    for _, obj in ipairs(Lighting:GetChildren()) do
        if obj:IsA("Atmosphere") then table.insert(parked, obj); obj.Parent = nil end
    end
    sky = Lighting:FindFirstChildOfClass("Sky")
    if sky then
        skySnapshot = {CelestialBodiesShown = sky.CelestialBodiesShown, StarCount = sky.StarCount}
    else sky = own(make("Sky", {Name = "EclipseSky"}, Lighting)) end
    sky.CelestialBodiesShown = false
    sky.StarCount = 0
    local atmosphere = own(make("Atmosphere", {
        Name = "EclipseAtmosphere", Density = 0.30, Offset = 0.12, Glare = 0, Haze = 1.4,
    }, Lighting))
    local grade = own(make("ColorCorrectionEffect", {Name = "EclipseColor"}, Lighting))
    local bloom = own(make("BloomEffect", {
        Name = "EclipseBloom", Intensity = 0.20, Size = 40, Threshold = 1.2,
    }, Lighting))
    local sunRays = own(make("SunRaysEffect", {
        Name = "EclipseSunRays", Intensity = 0.04, Spread = 0.88,
    }, Lighting))
    Lighting.ClockTime = SETTINGS.ClockTime
    Lighting.GeographicLatitude = SETTINGS.GeographicLatitude
    Lighting.GlobalShadows = true
    Lighting.FogStart = 0
    Lighting.FogEnd = 100000
    local sunDirection = Lighting:GetSunDirection().Unit
    local orbitRight = sunDirection:Cross(Vector3.new(0, 1, 0)).Unit
    local orbitUp = orbitRight:Cross(sunDirection).Unit

    local root = make("Frame", {
        Name = "SkyProjection", AnchorPoint = Vector2.new(0.5, 0.5),
        BackgroundTransparency = 1, Size = UDim2.fromOffset(1, 1), Visible = false,
    }, scene)
    local corona = {}
    for i = SETTINGS.CoronaLayers, 1, -1 do
        local f = i/SETTINGS.CoronaLayers
        local tint = rgb(255, 220, 158):Lerp(rgb(214, 103, 32), f)
        local obj = circle(root, "GoldenCorona", 1.03 + f*f*3.0, tint, 1)
        table.insert(corona, {obj = obj, f = f})
    end
    local streamers = {}
    local random = Random.new(712430)
    for i = 1, SETTINGS.RayCount do
        local angle = 2*math.pi*(i - 1)/SETTINGS.RayCount + random:NextNumber(-0.045, 0.045)
        local length = random:NextNumber(0.70, 1.65)
        local width = random:NextNumber(0.015, 0.048)
        local bands = {}
        for layer = 1, 2 do
            local ray = make("Frame", {
                Name = "CoronalRay", AnchorPoint = Vector2.new(0.5, 0.5),
                Size = UDim2.fromScale(length, width*(layer == 1 and 3 or 0.55)),
                BackgroundColor3 = layer == 1 and rgb(238, 153, 71) or rgb(255, 232, 180),
                BorderSizePixel = 0, ZIndex = 2,
            }, root)
            corner(ray); gradientFade(ray)
            table.insert(bands, ray)
        end
        table.insert(streamers, {bands = bands, angle = angle, length = length, width = width})
    end
    local sun = circle(root, "SolarDisc", 1, rgb(255, 241, 196), 3)
    make("UIGradient", {
        Rotation = 65,
        Color = ColorSequence.new(rgb(255, 255, 239), rgb(255, 204, 109)),
    }, sun)
    local innerRims = {}
    for i = 1, 6 do
        local obj = circle(root, "Chromosphere", 1 + i*0.011, rgb(255, 201, 117), 2)
        table.insert(innerRims, obj)
    end

    -- Compact offscreen compositing only for the lunar disc, not the full screen.
    -- UICorner on CanvasGroup clips every crater to the circular limb.
    local moon = make("CanvasGroup", {
        Name = "TexturedMoon", AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(-0.64, 0.5), Size = UDim2.fromScale(1.025, 1.025),
        BackgroundColor3 = rgb(255, 255, 255), BorderSizePixel = 0,
        GroupTransparency = 1, ZIndex = 5,
    }, root)
    corner(moon)
    local moonGradient = make("UIGradient", {
        Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, rgb(126, 70, 33)),
            ColorSequenceKeypoint.new(0.16, rgb(66, 39, 25)),
            ColorSequenceKeypoint.new(0.43, rgb(15, 12, 13)),
            ColorSequenceKeypoint.new(0.72, rgb(5, 6, 9)),
            ColorSequenceKeypoint.new(1, rgb(3, 4, 7)),
        }), Rotation = 0,
    }, moon)
    for i = 1, SETTINGS.MoonCraters do
        local a, radial = random:NextNumber(0, math.pi*2), math.sqrt(random:NextNumber())*0.455
        local size = random:NextNumber(0.02, 0.12)
        local crater = circle(moon, "Crater", size, rgb(164, 143, 118), 1)
        crater.Position = UDim2.fromScale(0.5 + math.cos(a)*radial, 0.5 + math.sin(a)*radial)
        crater.BackgroundTransparency = random:NextNumber(0.45, 0.78)
        local hollow = circle(crater, "CraterShadow", 0.80, rgb(32, 30, 28), 1)
        hollow.Position = UDim2.fromScale(0.57, 0.46)
        hollow.BackgroundTransparency = 0.18
    end
    for _ = 1, 65 do
        local a, radial = random:NextNumber(0, math.pi*2), math.sqrt(random:NextNumber())*0.495
        local grain = circle(moon, "LunarGrain", random:NextNumber(0.005, 0.025), rgb(167, 151, 122), 2)
        grain.Position = UDim2.fromScale(0.5 + math.cos(a)*radial, 0.5 + math.sin(a)*radial)
        grain.BackgroundTransparency = random:NextNumber(0.45, 0.83)
    end
    local lunarRim = make("UIStroke", {
        Color = rgb(236, 177, 97), Transparency = 0.55, Thickness = 1,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
    }, moon)
    local contactGlows = {}
    for i = 10, 1, -1 do
        local obj = circle(root, "DiamondGlow", 0.07 + i*i*0.006, rgb(255, 221, 156), 7)
        table.insert(contactGlows, {obj = obj, i = i})
    end
    local diamond = circle(root, "DiamondRing", 0.065, rgb(255, 255, 239), 8)
    local beads = {}
    for i = 1, 5 do
        table.insert(beads, circle(root, "BailyBead", 0.014 + (i%2)*0.008, rgb(255, 245, 210), 8))
    end

    -- Lens optics are screen-aligned; reflections move opposite to the Sun
    -- as the camera rotates, and disappear when the light source is blocked.
    local optics = make("Frame", {Name = "LensOptics", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 9}, scene)
    local streaks = {}
    for i = 1, 3 do
        local obj = make("Frame", {
            Name = "AnamorphicFlare", AnchorPoint = Vector2.new(0.5, 0.5),
            BackgroundColor3 = i == 3 and rgb(255, 243, 215) or rgb(255, 174, 89),
            BorderSizePixel = 0,
        }, optics)
        gradientFade(obj)
        table.insert(streaks, obj)
    end
    local ghosts = {}
    for i, spec in ipairs({
        {factor = 0.45, size = 0.23, tint = rgb(246, 191, 104)},
        {factor = 0.85, size = 0.09, tint = rgb(113, 170, 204)},
        {factor = 1.35, size = 0.30, tint = rgb(209, 145, 62)},
        {factor = 1.8, size = 0.11, tint = rgb(167, 177, 194)},
    }) do
        local obj = circle(optics, "LensGhost", 0, spec.tint, 1)
        local rings = make("UIStroke", {Thickness = 1, Color = spec.tint, Transparency = 1}, obj)
        spec.obj = obj; spec.ring = rings; table.insert(ghosts, spec)
    end

    -- Penta black / silver UI. A moving gradient is confined to the glass layer.
    local W, H, MINI = 332, 300, 68
    panel = make("Frame", {
        Name = "ControlPanel", Position = UDim2.fromOffset(18, 82), Size = UDim2.fromOffset(W, H),
        BackgroundColor3 = rgb(3, 3, 4), BackgroundTransparency = 0.045,
        BorderSizePixel = 0, ClipsDescendants = true, Active = true,
    }, gui)
    corner(panel, 16)
    panelScale = make("UIScale", {Scale = 1}, panel)
    local panelStroke = make("UIStroke", {Color = rgb(175, 175, 180), Transparency = 0.59, Thickness = 1}, panel)
    make("UIGradient", {Rotation = 38, Color = ColorSequence.new(rgb(235, 235, 239), rgb(78, 78, 82))}, panelStroke)
    local glass = make("Frame", {
        Name = "SilverGlass", Size = UDim2.fromScale(1, 1), BackgroundColor3 = rgb(255, 255, 255),
        BackgroundTransparency = 0.79, BorderSizePixel = 0, ZIndex = 1,
    }, panel)
    corner(glass, 16)
    make("UIGradient", {Rotation = 125, Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(0.35, 0.78),
        NumberSequenceKeypoint.new(0.65, 1), NumberSequenceKeypoint.new(1, 0.68),
    })}, glass)
    local reflection = make("Frame", {
        Name = "SoftReflection", Size = UDim2.fromScale(1, 1), BackgroundColor3 = rgb(255, 255, 255),
        BackgroundTransparency = 0.86, BorderSizePixel = 0, ZIndex = 2,
    }, panel)
    corner(reflection, 16)
    local sheen = make("UIGradient", {Rotation = 22, Offset = Vector2.new(-1.25, 0), Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.33, 1),
        NumberSequenceKeypoint.new(0.5, 0.12), NumberSequenceKeypoint.new(0.67, 1),
        NumberSequenceKeypoint.new(1, 1),
    })}, reflection)
    local function label(parent, text, x, y, w, h, size, tint, font)
        return make("TextLabel", {
            Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(w, h),
            BackgroundTransparency = 1, Text = text, TextSize = size,
            TextColor3 = tint or rgb(237, 237, 241), Font = font or Enum.Font.Gotham,
            TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 4,
        }, parent)
    end
    local header = make("Frame", {Name = "DragArea", BackgroundTransparency = 1, Size = UDim2.fromOffset(W-84, MINI), Active = true, ZIndex = 4}, panel)
    local icon = circle(header, "EclipseIcon", 0, rgb(4, 4, 5), 4)
    icon.Size = UDim2.fromOffset(26, 26); icon.Position = UDim2.fromOffset(31, 34)
    make("UIStroke", {Color = rgb(227, 227, 233), Thickness = 1.4, Transparency = 0.2}, icon)
    local dot = circle(icon, "IconGlint", 0.20, rgb(255, 255, 255), 5)
    dot.Position = UDim2.fromScale(0.08, 0.39)
    label(header, "HzReyzn", 54, 13, 174, 16, 11, rgb(162, 162, 170), Enum.Font.GothamMedium)
    label(header, "ECLIPSE", 54, 31, 174, 23, 20, nil, Enum.Font.GothamBold)
    local body = make("Frame", {Name = "Controls", Position = UDim2.fromOffset(0, MINI), Size = UDim2.fromOffset(W, H-MINI), BackgroundTransparency = 1, ZIndex = 4}, panel)
    make("Frame", {Position = UDim2.fromOffset(17, 0), Size = UDim2.fromOffset(W-34, 1), BackgroundColor3 = rgb(100, 100, 105), BackgroundTransparency = 0.60, BorderSizePixel = 0}, body)
    local phaseLabel = label(body, "FIRST CONTACT", 18, 12, 238, 19, 11, rgb(190, 190, 198), Enum.Font.GothamMedium)
    local percent = label(body, "0%", 251, 9, 63, 26, 22, nil, Enum.Font.GothamBold)
    percent.TextXAlignment = Enum.TextXAlignment.Right
    local track = make("Frame", {Position = UDim2.fromOffset(18, 43), Size = UDim2.fromOffset(W-36, 4), BackgroundColor3 = rgb(52, 52, 57), BorderSizePixel = 0}, body)
    corner(track)
    local fill = make("Frame", {Size = UDim2.fromScale(0, 1), BackgroundColor3 = rgb(240, 240, 245), BorderSizePixel = 0}, track)
    corner(fill)
    local timeLabel = label(body, "00:00 / 01:26", 18, 52, 172, 15, 10, rgb(133, 133, 142))
    local modeLabel = label(body, "CINEMATIC", 190, 52, 124, 15, 10, rgb(133, 133, 142))
    modeLabel.TextXAlignment = Enum.TextXAlignment.Right
    local function button(parent, name, text, x, y, w, h, primary)
        local b = make("TextButton", {
            Name = name, Text = text, Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(w, h),
            BackgroundColor3 = primary and rgb(227, 227, 232) or rgb(27, 27, 30),
            BackgroundTransparency = primary and 0.03 or 0.15,
            TextColor3 = primary and rgb(10, 10, 12) or rgb(223, 223, 229),
            Font = Enum.Font.GothamMedium, TextSize = 11, AutoButtonColor = false,
            BorderSizePixel = 0, ZIndex = 5,
        }, parent)
        corner(b, 8)
        make("UIStroke", {Color = rgb(152, 152, 162), Transparency = primary and 0.80 or 0.82, Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border}, b)
        local tween
        local function hover(on)
            if tween then tween:Cancel() end
            tween = TweenService:Create(b, TweenInfo.new(0.16), {BackgroundTransparency = on and 0 or (primary and 0.03 or 0.15)})
            tween:Play()
        end
        connect(b.MouseEnter, function() hover(true) end)
        connect(b.MouseLeave, function() hover(false) end)
        return b
    end
    local pause = button(body, "Pause", "PAUSE", 18, 78, 94, 33, true)
    local restart = button(body, "Restart", "RESTART", 119, 78, 94, 33)
    local speed = button(body, "Speed", "SPEED  1x", 220, 78, 94, 33)
    local sizeButton = button(body, "Size", "SUN  LARGE", 18, 120, 144, 31)
    local raysButton = button(body, "Rays", "RAYS  HIGH", 170, 120, 144, 31)
    local focusButton = button(body, "FocusSun", "VIEW ECLIPSE", 18, 160, 194, 33)
    local loopButton = button(body, "Loop", "LOOP  ON", 220, 160, 94, 33)
    local hint = label(body, "Drag header to move  /  Close to restore", 18, 204, 296, 14, 10, rgb(117, 117, 127))
    local minimize = button(panel, "Minimize", "−", W-78, 20, 27, 27)
    local close = button(panel, "Close", "×", W-43, 20, 27, 27)
    close.TextSize = 18; minimize.TextSize = 18
    connect(close.Activated, cleanup)
    connect(pause.Activated, function()
        state.paused = not state.paused
        pause.Text = state.paused and "RESUME" or "PAUSE"
    end)
    connect(restart.Activated, function()
        state.elapsed = 0; state.paused = false; state.startup = 0
        pause.Text = "PAUSE"
    end)
    connect(speed.Activated, function()
        state.speed = state.speed == 1 and 2 or (state.speed == 2 and 0.5 or 1)
        speed.Text = "SPEED  " .. tostring(state.speed) .. "x"
    end)
    connect(sizeButton.Activated, function()
        state.targetSize = state.targetSize == 1 and 1.35 or (state.targetSize == 1.35 and 0.78 or 1)
        sizeButton.Text = state.targetSize == 1 and "SUN  LARGE" or (state.targetSize > 1 and "SUN  XL" or "SUN  MEDIUM")
    end)
    connect(raysButton.Activated, function()
        state.intensity = state.intensity == 1 and 1.4 or (state.intensity > 1 and 0.65 or 1)
        raysButton.Text = state.intensity == 1 and "RAYS  HIGH" or (state.intensity > 1 and "RAYS  ULTRA" or "RAYS  SOFT")
    end)
    connect(loopButton.Activated, function()
        state.loop = not state.loop
        loopButton.Text = state.loop and "LOOP  ON" or "LOOP  OFF"
    end)
    local resizeTween
    connect(minimize.Activated, function()
        state.minimized = not state.minimized
        minimize.Text = state.minimized and "+" or "−"
        if resizeTween then resizeTween:Cancel() end
        resizeTween = TweenService:Create(panel, TweenInfo.new(0.25, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
            Size = UDim2.fromOffset(W, state.minimized and MINI or H),
        })
        resizeTween:Play()
    end)
    local function clampPanel()
        local view = gui.AbsoluteSize
        local s = panelScale.Scale
        panel.Position = UDim2.fromOffset(
            math.clamp(panel.Position.X.Offset, 4, math.max(4, view.X - W*s - 4)),
            math.clamp(panel.Position.Y.Offset, 4, math.max(4, view.Y - (state.minimized and MINI or H)*s - 4)))
    end
    local dragging, dragInput, dragStart, panelStart
    connect(header.InputBegan, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true; dragInput = input; dragStart = input.Position; panelStart = panel.Position
        end
    end)
    connect(Input.InputEnded, function(input)
        if input == dragInput then dragging = false; dragInput = nil end
    end)
    connect(Input.InputChanged, function(input)
        if not dragging then return end
        if input ~= dragInput and input.UserInputType ~= Enum.UserInputType.MouseMovement then return end
        local delta = input.Position - dragStart
        panel.Position = UDim2.fromOffset(panelStart.X.Offset + delta.X, panelStart.Y.Offset + delta.Y)
        clampPanel()
    end)
    restoreFocus = function()
        local f = state.focus
        state.focus = nil
        if f then safe(function()
            if f.camera.CameraType == Enum.CameraType.Scriptable then f.camera.CameraType = f.previousType end
        end) end
    end
    connect(focusButton.Activated, function()
        restoreFocus()
        local cam = workspace.CurrentCamera
        if not cam then return end
        state.focus = {camera = cam, from = cam.CFrame, previousType = cam.CameraType, time = 0}
        cam.CameraType = Enum.CameraType.Scriptable
    end)
    connect(Input.InputBegan, function(input, processed)
        if processed or not state.focus then return end
        if input.UserInputType == Enum.UserInputType.MouseButton2 or input.UserInputType == Enum.UserInputType.Touch then restoreFocus() end
    end)
    connect(workspace:GetPropertyChangedSignal("CurrentCamera"), function()
        restoreFocus(); state.camera = nil
        suppress(workspace.CurrentCamera)
    end)
    connect(player.CharacterAdded, function() restoreFocus(); state.occlusionClock = 1 end)

    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.IgnoreWater = false
    -- Glass transmits a reduced flare; fully transparent utility parts are skipped.
    local function transmittance(cam, direction)
        local ignore = {cam}
        if player.Character then table.insert(ignore, player.Character) end
        local amount = 1
        for _ = 1, 5 do
            params.FilterDescendantsInstances = ignore
            local hit = workspace:Raycast(cam.CFrame.Position, direction.Unit*SETTINGS.RayDistance, params)
            if not hit then return amount end
            local part = hit.Instance
            if not part:IsA("BasePart") then return 0 end
            local transparency = math.max(part.Transparency, part.LocalTransparencyModifier)
            if transparency < 0.10 then return 0 end
            if transparency < 0.96 then amount = amount*transparency end
            table.insert(ignore, part)
        end
        return 0
    end
    local function clockText(t)
        local seconds = math.floor(t)
        return string.format("%02d:%02d", math.floor(seconds/60), seconds%60)
    end

    local function render(dt)
        if state.closed then return end
        local cam = workspace.CurrentCamera
        if not cam then return end
        dt = math.min(dt, 0.1) -- avoid jumping over totality after app suspension
        local view = cam.ViewportSize
        if view.X < 2 or view.Y < 2 then return end
        if state.camera ~= cam or state.viewSize ~= view then
            state.camera = cam; state.viewSize = view; state.occlusionClock = 1
            panelScale.Scale = math.clamp(math.min((gui.AbsoluteSize.X-12)/W, (gui.AbsoluteSize.Y-12)/H, 1), 0.50, 1)
            clampPanel()
        end
        if state.focus then
            local f = state.focus
            f.time = f.time + dt
            local goal = CFrame.lookAt(f.from.Position, f.from.Position + sunDirection)
            cam.CFrame = f.from:Lerp(goal, smooth(f.time/0.8))
            if f.time >= 0.8 then restoreFocus() end
        end
        if not state.paused then
            state.elapsed = state.elapsed + dt*state.speed
            state.animationTime = state.animationTime + dt*state.speed
        end
        if state.elapsed >= cycle then
            if state.loop then state.elapsed = state.elapsed%cycle else state.elapsed = cycle end
        end
        state.startup = math.min(1, state.startup + dt/1.2)
        state.size = damp(state.size, state.targetSize, 7, dt)
        local x, phase = phaseAt(state.elapsed)
        local covered = coverage(x)
        local total = smooth((covered - 0.86)/0.14)
        local contact = math.exp(-((math.abs(x)-0.115)/0.085)^2)
        local light = (1-covered)^0.65
        local side = x <= 0 and 1 or -1
        local t = state.animationTime
        state.darkness = damp(state.darkness, covered^1.7, 5, dt)
        local dark = state.darkness

        -- Keep shadows aligned with the projected solar position.
        Lighting.ClockTime = SETTINGS.ClockTime
        Lighting.GeographicLatitude = SETTINGS.GeographicLatitude
        local entrance = smooth(state.startup)
        local function lightNumber(key, target) Lighting[key] = lerp(snapshot[key], target, entrance) end
        local function lightColor(key, target) Lighting[key] = snapshot[key]:Lerp(target, entrance) end
        lightNumber("Brightness", lerp(2.5, 0.12, dark))
        lightNumber("ExposureCompensation", lerp(0.03, -1.1, dark))
        lightColor("Ambient", rgb(78, 75, 78):Lerp(rgb(12, 15, 26), dark))
        lightColor("OutdoorAmbient", rgb(141, 135, 129):Lerp(rgb(28, 32, 48), dark))
        lightColor("ColorShift_Top", rgb(14, 8, 2):Lerp(rgb(2, 4, 10), dark))
        lightColor("ColorShift_Bottom", rgb(0, 0, 0))
        lightNumber("EnvironmentDiffuseScale", lerp(0.70, 0.20, dark))
        lightNumber("EnvironmentSpecularScale", lerp(0.82, 0.32, dark))
        atmosphere.Color = rgb(221, 205, 178):Lerp(rgb(69, 77, 105), dark)
        atmosphere.Decay = rgb(133, 111, 102):Lerp(rgb(24, 29, 48), dark)
        atmosphere.Density = lerp(0.30, 0.36, dark)
        atmosphere.Haze = lerp(1.4, 2.05, dark)
        grade.TintColor = rgb(255, 248, 235):Lerp(rgb(192, 204, 234), dark)
        grade.Saturation = lerp(-0.02, -0.30, dark)*entrance
        grade.Contrast = lerp(0.045, 0.16, dark)*entrance
        grade.Brightness = -0.055*dark*entrance
        bloom.Intensity = 0.20 + 0.13*total + 0.16*contact
        sunRays.Intensity = (0.065*light + 0.035*contact)*state.flareVisibility

        local solarPoint = cam.CFrame.Position + sunDirection*1000
        local projected = cam:WorldToViewportPoint(solarPoint)
        local front = projected.Z > 1
        local angularRadius = math.rad(SETTINGS.SunAngularDiameter*state.size*0.5)
        -- Projection of an edge uses Roblox's camera matrix, including FOV modes.
        local edge = cam:WorldToViewportPoint(solarPoint + cam.CFrame.RightVector*(math.tan(angularRadius)*1000))
        local diameter = math.clamp(math.abs(edge.X-projected.X)*2, 1, view.Y*0.85)
        local margin = diameter*2.6
        local inView = front and projected.X > -margin and projected.X < view.X+margin and projected.Y > -margin and projected.Y < view.Y+margin
        local tangent = cam:WorldToViewportPoint(solarPoint + orbitRight*80)
        local angle = math.atan2(tangent.Y-projected.Y, tangent.X-projected.X)
        local axis = Vector2.new(math.cos(angle), math.sin(angle))
        local center = Vector2.new(projected.X, projected.Y)
        local brightOffset = side*diameter*0.47*smooth(covered)
        local bright = center + axis*brightOffset
        state.occlusionClock = state.occlusionClock + dt
        if state.occlusionClock >= SETTINGS.OcclusionInterval then
            state.occlusionClock = 0
            if inView then
                local radius = math.tan(angularRadius)*0.80
                local minimum = transmittance(cam, sunDirection)
                for _, offset in ipairs({orbitRight, -orbitRight, orbitUp, -orbitUp}) do
                    minimum = math.min(minimum, transmittance(cam, sunDirection + offset*radius))
                end
                state.targetVisibility = minimum
                local brightRay = cam:ViewportPointToRay(bright.X, bright.Y)
                state.targetFlare = transmittance(cam, brightRay.Direction)
            else state.targetVisibility = 0; state.targetFlare = 0 end
        end
        state.visibility = damp(state.visibility, state.targetVisibility, 18, dt)
        state.flareVisibility = damp(state.flareVisibility, state.targetFlare, 16, dt)
        local vis = state.visibility*entrance
        root.Visible = inView and vis > 0.003
        root.Position = UDim2.fromOffset(center.X, center.Y)
        root.Size = UDim2.fromOffset(diameter, diameter)
        root.Rotation = math.deg(angle)
        if root.Visible then
            alpha(sun, vis)
            moon.Position = UDim2.fromScale(0.5 + x*0.5, 0.5)
            local lunarAlpha = smooth((2.28-math.abs(x))/0.22)
            moon.GroupTransparency = 1 - vis*lunarAlpha
            moonGradient.Rotation = side == 1 and 180 or 0
            moon.GroupColor3 = rgb(255, 255, 255):Lerp(rgb(132, 132, 147), total*0.58)
            lunarRim.Transparency = lerp(0.74, 0.35, total)
            for _, item in ipairs(corona) do
                local f = item.f
                local pulse = 1 + 0.012*math.sin(t*0.75-f*4)
                local size = (1.03+f*f*3)*pulse
                item.obj.Size = UDim2.fromScale(size, size)
                alpha(item.obj, vis*(0.014*light + 0.075*total + 0.025*contact)*(1-f*0.87)*state.intensity)
            end
            for i, obj in ipairs(innerRims) do
                alpha(obj, vis*(0.055*light + 0.085*total)*(1-i/8))
            end
            for i, item in ipairs(streamers) do
                local a = item.angle + 0.008*math.sin(t*0.24+i)
                local along = 0.38 + item.length*0.42
                local exposure = (0.13*light + 0.20*total + 0.30*contact)*vis*state.intensity
                -- Prefer the exposed limb while the Moon is crossing the Sun.
                local facing = 0.30 + 0.70*math.max(0, math.cos(a)*side)
                exposure = exposure*lerp(facing, 1, total)*(0.90+0.1*math.sin(t*0.8+i))
                for layer, ray in ipairs(item.bands) do
                    ray.Position = UDim2.fromScale(0.5+math.cos(a)*along, 0.5+math.sin(a)*along)
                    ray.Rotation = math.deg(a)
                    alpha(ray, exposure*(layer == 1 and 0.30 or 1))
                end
            end
            local contactPos = UDim2.fromScale(0.5+side*0.492, 0.5)
            for _, item in ipairs(contactGlows) do
                item.obj.Position = contactPos
                alpha(item.obj, vis*contact*(0.065 + (1-item.i/11)*0.045)*state.intensity)
            end
            diamond.Position = contactPos
            alpha(diamond, contact*vis)
            for i, bead in ipairs(beads) do
                local a = (i-3)*0.09
                bead.Position = UDim2.fromScale(0.5+side*math.cos(a)*0.496, 0.5+math.sin(a)*0.496)
                alpha(bead, vis*contact*0.65*math.exp(-math.abs(i-3)*0.20))
            end
        end
        local look = math.max(0, cam.CFrame.LookVector:Dot(sunDirection))
        local lens = state.flareVisibility*entrance*(0.42*light+0.70*contact+0.045*total)*look^3*state.intensity
        optics.Visible = inView and lens > 0.002
        if optics.Visible then
            for i, obj in ipairs(streaks) do
                obj.Position = UDim2.fromOffset(bright.X, bright.Y)
                obj.Size = UDim2.fromOffset(diameter*(6.5-i*0.65), math.max(1, diameter*({0.12, 0.036, 0.006})[i]))
                alpha(obj, lens*({0.09, 0.23, 0.67})[i])
            end
            local delta = Vector2.new(view.X*0.5, view.Y*0.5)-bright
            for _, spec in ipairs(ghosts) do
                local pos = bright + delta*spec.factor
                spec.obj.Position = UDim2.fromOffset(pos.X, pos.Y)
                spec.obj.Size = UDim2.fromOffset(diameter*spec.size, diameter*spec.size)
                alpha(spec.obj, lens*0.10)
                spec.ring.Transparency = 1 - math.clamp(lens*0.16, 0, 1)
            end
        end
        -- The panel reflection remains slow even when eclipse speed changes.
        sheen.Offset = Vector2.new(((os.clock()%8)/8)*2.6-1.3, 0)
        state.uiClock = state.uiClock + dt
        if state.uiClock >= 0.1 then
            state.uiClock = 0
            phaseLabel.Text = state.paused and (phase .. "  /  PAUSED") or phase
            percent.Text = string.format("%d%%", math.floor(covered*100+0.5))
            fill.Size = UDim2.fromScale(state.elapsed/cycle, 1)
            timeLabel.Text = clockText(state.elapsed) .. " / " .. clockText(cycle)
            hint.Text = not inView and "Tap VIEW ECLIPSE to find the Sun" or "Drag header to move  /  Close to restore"
        end
    end
    RunService:BindToRenderStep(bindName, Enum.RenderPriority.Camera.Value+1, function(dt)
        local ok, err = xpcall(function() render(dt) end, debug.traceback)
        if not ok then cleanup(); warn("HzReyzn Eclipse stopped safely: " .. tostring(err)) end
    end)
end

local success, problem = xpcall(start, debug.traceback)
if not success then
    cleanup()
    warn("HzReyzn Eclipse could not start: " .. tostring(problem))
end
