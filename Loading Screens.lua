--!nonstrict
-- Loading Screens | HzReyzn Hub
-- Client-side visual intro. Appearance: 0.3 s; loading: 5 s; exit: 2.1 s.
-- The five-second bar is an intro timer, not a measure of game asset loading.
-- GitHub PNGs use getcustomasset/getsynasset + writefile in compatible clients.
-- For Roblox Studio: upload the two PNGs and set the two asset IDs below,
-- then place this code in a LocalScript in StarterPlayerScripts.

local CONFIG = {
    AppearTime = 0.3,
    LoadTime = 5,
    ExitTime = 2.1,
    FlashInterval = 3,
    FlashOpacity = 0.10,
    BackgroundAssetId = "",
    LogoAssetId = "",
    AssetBase = "https://raw.githubusercontent.com/hzReyzn/crazy/main/assets/loading-screens/",
    CacheVersion = "20260930a",
}

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ContentProvider = game:GetService("ContentProvider")
local player = Players.LocalPlayer
if not player then
    warn("[Loading Screens] Run this script on the client.")
    return
end
local playerGui = player:WaitForChild("PlayerGui")
local previous = playerGui:FindFirstChild("HzReyzn_LoadingScreens")
if previous then previous:Destroy() end

local WHITE = Color3.fromRGB(243, 247, 255)
local BLACK = Color3.fromRGB(2, 2, 9)
local PINK = Color3.fromRGB(243, 70, 222)
local VIOLET = Color3.fromRGB(143, 79, 255)
local BLUE = Color3.fromRGB(62, 109, 255)
local CYAN = Color3.fromRGB(86, 213, 255)
local PALETTE = { VIOLET, BLUE, CYAN, PINK }
local rng = Random.new(2409)
local mobile = UserInputService.TouchEnabled
local TAU = math.pi * 2
local function clamp(x, a, b) return math.max(a, math.min(b, x)) end
local function smooth(x)
    x = clamp(x, 0, 1)
    return x * x * (3 - 2 * x)
end
local function colorAt(phase)
    local p = (phase % 1) * #PALETTE
    local i = math.floor(p)
    return PALETTE[i + 1]:Lerp(PALETTE[(i + 1) % #PALETTE + 1], p - i)
end
local COLORS = ColorSequence.new({
    ColorSequenceKeypoint.new(0, PINK),
    ColorSequenceKeypoint.new(0.28, VIOLET),
    ColorSequenceKeypoint.new(0.57, BLUE),
    ColorSequenceKeypoint.new(0.80, CYAN),
    ColorSequenceKeypoint.new(1, PINK),
})
local SOFT = NumberSequence.new({
    NumberSequenceKeypoint.new(0, 1),
    NumberSequenceKeypoint.new(0.5, 0),
    NumberSequenceKeypoint.new(1, 1),
})

-- One opacity pass keeps particles, strokes and images synchronized on exit.
-- Native Frames avoid a full-screen CanvasGroup render texture on mobile.
local fades, connections, imageJobs = {}, {}, {}
local alive, state = true, "appearing"
local readyAt, closingAt, startedAt
local imageOpacity = { background = 0, logo = 0 }
local imageLoaded = { background = false, logo = false }
local function node(className, props, parent)
    local object = Instance.new(className)
    if object:IsA("GuiObject") then
        object.BackgroundTransparency = 1
        object.BorderSizePixel = 0
    end
    for key, value in pairs(props or {}) do object[key] = value end
    object.Parent = parent
    return object
end
local function opacity(object, property, value, asset)
    local item = { object = object, property = property, value = value, asset = asset }
    fades[#fades + 1] = item
    object[property] = 1
    return item
end
local function corner(object, radius)
    return node("UICorner", { CornerRadius = UDim.new(0, radius) }, object)
end
local function round(object)
    return node("UICorner", { CornerRadius = UDim.new(1, 0) }, object)
end
local function stroke(object, thickness, alpha, color)
    local s = node("UIStroke", { Thickness = thickness, Color = color or VIOLET }, object)
    return s, opacity(s, "Transparency", alpha)
end
local function gradient(object, rotation, colors, transparency)
    return node("UIGradient", {
        Rotation = rotation or 0,
        Color = colors or COLORS,
        Transparency = transparency or NumberSequence.new(0),
    }, object)
end
local function frame(parent, name, z, color, alpha)
    local f = node("Frame", { Name = name, ZIndex = z, BackgroundColor3 = color or WHITE }, parent)
    local a = opacity(f, "BackgroundTransparency", alpha or 0)
    return f, a
end
local function label(parent, name, text, size, color, z)
    local f = node("TextLabel", {
        Name = name, Text = text, Font = Enum.Font.GothamMedium,
        TextSize = size, TextColor3 = color or WHITE,
        ZIndex = z, TextStrokeTransparency = 1,
    }, parent)
    return f, opacity(f, "TextTransparency", 1)
end
local gui = node("ScreenGui", {
    Name = "HzReyzn_LoadingScreens", IgnoreGuiInset = true, ResetOnSpawn = false,
    DisplayOrder = 100000, ZIndexBehavior = Enum.ZIndexBehavior.Global, Enabled = false,
}, playerGui)
pcall(function() gui.ScreenInsets = Enum.ScreenInsets.None end)
pcall(function() gui.ClipToDeviceSafeArea = false end)
local root = frame(gui, "Scene", 1, BLACK, 1)
root.Size = UDim2.fromScale(1, 1)
root.ClipsDescendants = true

local background = node("ImageLabel", {
    Name = "Background", AnchorPoint = Vector2.new(0.5, 0.5),
    ScaleType = Enum.ScaleType.Stretch, ZIndex = 2,
}, root)
opacity(background, "ImageTransparency", 1, "background")
local shade = frame(root, "CinematicShade", 3, BLACK, 0.44)
shade.Size = UDim2.fromScale(1, 1)
gradient(shade, 0, ColorSequence.new(WHITE), NumberSequence.new({
    NumberSequenceKeypoint.new(0, 0.58),
    NumberSequenceKeypoint.new(0.48, 0.80),
    NumberSequenceKeypoint.new(0.74, 0.16),
    NumberSequenceKeypoint.new(1, 0),
}))
local bottomShade = frame(root, "BottomShade", 4, BLACK, 0.78)
bottomShade.Size = UDim2.fromScale(1, 1)
gradient(bottomShade, 90, ColorSequence.new(WHITE), NumberSequence.new({
    NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.65, 1),
    NumberSequenceKeypoint.new(1, 0),
}))

-- Restrained grid and slowly travelling energy ribbons.
for i = 1, 17 do
    local line = frame(root, "GridX", 5, VIOLET, 0.045)
    line.Position = UDim2.fromScale(i / 18, 0)
    line.Size = UDim2.new(0, 1, 1, 0)
end
for i = 1, 9 do
    local line = frame(root, "GridY", 5, CYAN, 0.035)
    line.Position = UDim2.fromScale(0, i / 10)
    line.Size = UDim2.new(1, 0, 0, 1)
end
local ribbons = {}
for i = 1, 3 do
    local f = frame(root, "EnergyRibbon", 6, i == 2 and CYAN or PINK, 0.15)
    f.AnchorPoint = Vector2.new(0.5, 0.5)
    f.Size = UDim2.new(0.55, 0, 0, 1)
    f.Rotation = -13 + i * 3
    gradient(f, 0, ColorSequence.new(WHITE), SOFT)
    ribbons[#ribbons + 1] = f
end

-- Three outlined orbits: no opaque discs behind the supplied wordmark.
local aura = frame(root, "Orbits", 7)
aura.AnchorPoint = Vector2.new(0.5, 0.5)
local rings = {}
for i, scale in ipairs({ 0.67, 0.86, 1.06 }) do
    local f = frame(aura, "Orbit" .. i, 7)
    f.AnchorPoint = Vector2.new(0.5, 0.5)
    f.Position = UDim2.fromScale(0.5, 0.5)
    f.Size = UDim2.fromScale(scale, scale)
    round(f)
    local s, a = stroke(f, i == 1 and 1.8 or 1, i == 1 and 0.36 or 0.19, WHITE)
    local g = gradient(s, i * 70, COLORS, NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.08), NumberSequenceKeypoint.new(0.42, 0.78),
        NumberSequenceKeypoint.new(0.70, 0.22), NumberSequenceKeypoint.new(1, 0.08),
    }))
    rings[#rings + 1] = { frame = f, gradient = g, alpha = a, scale = scale }
end
local orbitLights = {}
for i = 1, 7 do
    local f, a = frame(aura, "OrbitLight", 8, i % 2 == 0 and CYAN or PINK, 0.5)
    f.AnchorPoint = Vector2.new(0.5, 0.5)
    f.Size = UDim2.fromOffset(i % 3 == 0 and 4 or 2, i % 3 == 0 and 4 or 2)
    round(f)
    orbitLights[#orbitLights + 1] = { frame = f, alpha = a, phase = i * 1.61, radius = 0.33 + (i % 3) * 0.10 }
end
local waves = {}
for i = 1, 2 do
    local f = frame(aura, "CompletionWave" .. i, 9)
    f.AnchorPoint = Vector2.new(0.5, 0.5)
    f.Position = UDim2.fromScale(0.5, 0.5)
    round(f)
    local s, a = stroke(f, 2, 0, i == 1 and CYAN or PINK)
    waves[#waves + 1] = { frame = f, alpha = a, stroke = s }
end

local logoHolder = frame(root, "LogoHolder", 12)
logoHolder.AnchorPoint = Vector2.new(0.5, 0.5)
local logoScale = node("UIScale", { Scale = 1 }, logoHolder)
local logo = node("ImageLabel", {
    Name = "HzReyznHub", Size = UDim2.fromScale(1, 1),
    ScaleType = Enum.ScaleType.Fit, ZIndex = 13,
}, logoHolder)
opacity(logo, "ImageTransparency", 1, "logo")
local fallback, fallbackAlpha = label(logoHolder, "WordmarkFallback", "HzReyzn Hub", 42, WHITE, 12)
fallback.Size = UDim2.fromScale(0.95, 0.52)
fallback.AnchorPoint = Vector2.new(0.5, 0.5)
fallback.Position = UDim2.fromScale(0.5, 0.51)
fallback.TextScaled = true
fallback.Font = Enum.Font.GothamBlack
gradient(fallback, -12)

local stars = {}
for i = 1, 6 do
    local f = frame(logoHolder, "Glint", 15)
    f.AnchorPoint = Vector2.new(0.5, 0.5)
    f.Position = UDim2.fromScale(0.10 + (i - 1) * 0.16, 0.34 + (i % 3) * 0.12)
    f.Size = UDim2.fromOffset(15, 15)
    f.Rotation = 17
    local arms = {}
    for k = 1, 2 do
        local arm, a = frame(f, "Ray", 15, WHITE, 0)
        arm.AnchorPoint = Vector2.new(0.5, 0.5)
        arm.Position = UDim2.fromScale(0.5, 0.5)
        arm.Size = k == 1 and UDim2.new(1, 0, 0, 1) or UDim2.new(0, 1, 1, 0)
        gradient(arm, k == 1 and 0 or 90, ColorSequence.new(WHITE), SOFT)
        arms[#arms + 1] = a
    end
    stars[#stars + 1] = { frame = f, arms = arms, phase = i * 1.73 }
end
local particles = {}
for i = 1, (mobile and 27 or 40) do
    local large = i % 8 == 0
    local size = large and rng:NextNumber(6, 10) or rng:NextNumber(1.5, 3)
    local f, a = frame(root, "Particle", 10, i % 3 == 0 and WHITE or colorAt(i / 40), 0)
    f.AnchorPoint = Vector2.new(0.5, 0.5)
    f.Size = UDim2.fromOffset(size, size)
    round(f)
    particles[#particles + 1] = {
        frame = f, alpha = a, x = rng:NextNumber(), y = rng:NextNumber(),
        speed = rng:NextNumber(0.017, 0.039), phase = rng:NextNumber() * TAU,
        large = large,
    }
end

-- Border gradients rotate continuously between the colors in the artwork.
local border = frame(root, "AnimatedBorder", 25)
border.Position = UDim2.fromOffset(2, 2)
border.Size = UDim2.new(1, -4, 1, -4)
corner(border, 10)
local borderStroke = stroke(border, 1.6, 0.85, WHITE)
local borderGradient = gradient(borderStroke, 0)
local edges = {}
for i = 1, 4 do
    local f, a = frame(root, "EdgeGlow" .. i, 20, VIOLET, 0.24)
    if i == 1 or i == 2 then
        f.Size = UDim2.fromScale(1, 0.10)
        f.Position = UDim2.fromScale(0, i == 1 and 0 or 0.90)
    else
        f.Size = UDim2.fromScale(0.048, 1)
        f.Position = UDim2.fromScale(i == 3 and 0 or 0.952, 0)
    end
    gradient(f, ({ 90, 270, 0, 180 })[i], ColorSequence.new(WHITE), NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.22, 0.38),
        NumberSequenceKeypoint.new(0.58, 0.84), NumberSequenceKeypoint.new(1, 1),
    }))
    edges[#edges + 1] = { frame = f, alpha = a }
end

local barHolder = frame(root, "LoadingBar", 30)
barHolder.AnchorPoint = Vector2.new(0.5, 0.5)
local barGlow, barGlowAlpha = frame(barHolder, "BarGlow", 30, VIOLET, 0.15)
barGlow.Position = UDim2.fromOffset(-4, -4)
barGlow.Size = UDim2.new(1, 8, 1, 8)
corner(barGlow, 20)
local track = frame(barHolder, "Track", 31, BLACK, 0.93)
track.Size = UDim2.fromScale(1, 1)
corner(track, 20)
local trackStroke = stroke(track, 1.2, 0.70, WHITE)
local trackGradient = gradient(trackStroke, 0)
local inner = frame(track, "Inner", 32)
inner.Position = UDim2.fromOffset(2, 2)
inner.Size = UDim2.new(1, -4, 1, -4)
corner(inner, 20)
inner.ClipsDescendants = true
local fill = frame(inner, "Fill", 33, WHITE, 1)
fill.Size = UDim2.fromScale(0, 1)
corner(fill, 20)
local fillGradient = gradient(fill, 0)
local sheen = frame(fill, "TravellingHighlight", 34, WHITE, 0.62)
sheen.Size = UDim2.fromScale(0.25, 1)
gradient(sheen, 0, ColorSequence.new(WHITE), SOFT)
fill.ClipsDescendants = true
local tip, tipAlpha = frame(inner, "ProgressTip", 35, WHITE, 0.86)
tip.AnchorPoint = Vector2.new(0.5, 0.5)
tip.Size = UDim2.new(0, 3, 1, -1)
corner(tip, 5)
local statusLabel = label(barHolder, "Status", "Loading...", 14, WHITE, 36)
statusLabel.TextXAlignment = Enum.TextXAlignment.Left
local percentLabel = label(barHolder, "Percentage", "0%", 13, CYAN, 36)
percentLabel.TextXAlignment = Enum.TextXAlignment.Right
local hint, hintAlpha = label(barHolder, "Continue", "Please wait", 12, Color3.fromRGB(185, 179, 214), 36)
local flash, flashAlpha = frame(root, "GentleFlash", 50, WHITE, 0)
flash.Size = UDim2.fromScale(1, 1)
local clickCatcher = node("TextButton", {
    Name = "ClickAnywhere", Size = UDim2.fromScale(1, 1), Text = "",
    BackgroundTransparency = 1, AutoButtonColor = false, Active = true,
    Modal = true, Selectable = false, ZIndex = 100,
}, root)

local W, H, centerX, centerY, logoWidth, orbitSize, imageW, imageH, backgroundX
local portrait = false
local function layout()
    W, H = root.AbsoluteSize.X, root.AbsoluteSize.Y
    if W < 1 or H < 1 then return end
    portrait = W / H < 1.15
    centerX = W * (portrait and 0.50 or 0.735)
    centerY = H * (portrait and 0.56 or 0.435)
    logoWidth = portrait and W * 0.86 or math.min(W * 0.46, H * 1.17)
    orbitSize = portrait and math.min(W * 0.82, H * 0.42) or math.min(W * 0.38, H * 0.75)
    logoHolder.Size = UDim2.fromOffset(logoWidth, logoWidth * 941 / 1672)
    aura.Size = UDim2.fromOffset(orbitSize, orbitSize)
    local barWidth = portrait and W * 0.80 or math.min(W * 0.48, 760)
    local barHeight = clamp(H * 0.016, 10, 16)
    barHolder.Size = UDim2.fromOffset(barWidth, barHeight)
    barHolder.Position = UDim2.fromScale(0.5, portrait and 0.84 or 0.872)
    local textSize = clamp(H * 0.019, 11, 17)
    statusLabel.TextSize, percentLabel.TextSize = textSize, textSize - 1
    hint.TextSize = clamp(H * 0.016, 10, 14)
    statusLabel.Position = UDim2.fromOffset(0, -30)
    statusLabel.Size = UDim2.new(0.8, 0, 0, 24)
    percentLabel.Position = UDim2.new(0.80, 0, 0, -30)
    percentLabel.Size = UDim2.new(0.20, 0, 0, 24)
    hint.Position = UDim2.new(0, 0, 1, 10)
    hint.Size = UDim2.new(1, 0, 0, 22)
    -- Fixed image ratio preserves the character on every viewport.
    imageW = math.max(W, H * 1536 / 864) * 1.028
    imageH = imageW * 864 / 1536
    backgroundX = portrait and clamp(W * 0.33 + imageW * 0.20, W - imageW / 2, imageW / 2) or W / 2
    background.Size = UDim2.fromOffset(imageW, imageH)
end
connections[#connections + 1] = root:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout)
layout()

local function cleanup()
    if not alive then return end
    alive = false
    for _, connection in ipairs(connections) do connection:Disconnect() end
    for _, job in ipairs(imageJobs) do
        if coroutine.status(job) ~= "dead" then pcall(task.cancel, job) end
    end
end
connections[#connections + 1] = gui.Destroying:Connect(cleanup)
connections[#connections + 1] = clickCatcher.Activated:Connect(function()
    if not alive or state ~= "ready" then return end
    state, closingAt = "closing", os.clock()
    gui:SetAttribute("State", state)
    hint.Text = "Welcome"
end)

-- Images resolve independently; HTTP and PreloadAsync never gate the timer.
local getAsset = getcustomasset or getsynasset
local writeFile, readFile, fileExists = writefile, readfile, isfile
local requestHttp = request or http_request
if not requestHttp and type(syn) == "table" then requestHttp = syn.request end
local PNG_SIGNATURE = string.char(137, 80, 78, 71, 13, 10, 26, 10)
local function validPNG(data)
    return type(data) == "string" and #data > 32 and data:sub(1, 8) == PNG_SIGNATURE
end
local function download(url)
    if type(requestHttp) == "function" then
        local ok, result = pcall(requestHttp, { Url = url, Method = "GET" })
        if ok and type(result) == "table" and tonumber(result.StatusCode) == 200 and validPNG(result.Body) then
            return result.Body
        end
    end
    local ok, result = pcall(function() return game:HttpGet(url) end)
    if ok and validPNG(result) then return result end
    return nil
end
local function toAssetId(id)
    local value = tostring(id or "")
    if value == "" or value == "0" then return nil end
    if value:match("^%d+$") then return "rbxassetid://" .. value end
    return value
end
local function resolveImage(key, configuredId)
    local id = toAssetId(configuredId)
    if id then return id end
    if type(getAsset) ~= "function" or type(writeFile) ~= "function" then
        return nil, "Set the Roblox asset IDs in CONFIG, or use a client with getcustomasset and writefile."
    end
    local path = "HzReyzn_LoadingScreens_" .. CONFIG.CacheVersion .. "_" .. key .. ".png"
    if type(fileExists) == "function" and type(readFile) == "function" then
        local ok, cached = pcall(function() return fileExists(path) and validPNG(readFile(path)) end)
        if ok and cached then
            local registered, content = pcall(getAsset, path)
            if registered and type(content) == "string" and content ~= "" then return content end
        end
    end
    local bytes = download(CONFIG.AssetBase .. key .. ".png")
    if not bytes then return nil, "Could not download " .. key .. ".png; check the connection and try again." end
    local ok, content = pcall(function()
        writeFile(path, bytes)
        return getAsset(path)
    end)
    if ok and type(content) == "string" and content ~= "" then return content end
    return nil, "The client could not register " .. key .. ".png as an image."
end
local function loadImage(key, image, configuredId)
    imageJobs[#imageJobs + 1] = task.spawn(function()
        local ok, content, problem = pcall(resolveImage, key, configuredId)
        if not alive then return end
        if not ok or not content then
            warn("[Loading Screens] " .. tostring(problem or content))
            return
        end
        local assigned, errorMessage = pcall(function() image.Image = content end)
        if not assigned then warn("[Loading Screens] " .. tostring(errorMessage)); return end
        local preloaded, preloadError = pcall(function() ContentProvider:PreloadAsync({ image }) end)
        if not alive then return end
        if image.IsLoaded then imageLoaded[key] = true end
        if not preloaded then warn("[Loading Screens] " .. tostring(preloadError)) end
    end)
end

local pointerX, pointerY, lastPercent = 0, 0, -1
startedAt = os.clock()
gui.Enabled = true
gui:SetAttribute("State", state)
gui:SetAttribute("Progress", 0)
connections[#connections + 1] = RunService.RenderStepped:Connect(function(dt)
    if not alive then return end
    if not W or W < 1 or H < 1 then layout(); return end
    local now = os.clock()
    local t = now - startedAt
    local progress = clamp((t - CONFIG.AppearTime) / CONFIG.LoadTime, 0, 1)
    if state == "appearing" and t >= CONFIG.AppearTime then
        state = "loading"
        gui:SetAttribute("State", state)
    end
    if state == "loading" and progress >= 1 then
        state = "ready"
        readyAt = startedAt + CONFIG.AppearTime + CONFIG.LoadTime
        statusLabel.Text = "Loading completed"
        hint.Text = mobile and "Tap anywhere to continue" or "Click anywhere to continue"
        gui:SetAttribute("State", state)
    end
    local exit = closingAt and clamp((now - closingAt) / CONFIG.ExitTime, 0, 1) or 0
    if exit >= 1 then
        gui:SetAttribute("State", "closed")
        gui:Destroy()
        return
    end
    local visibility = smooth(t / CONFIG.AppearTime) * (1 - smooth(exit))
    local percent = math.floor(progress * 100 + 0.000001)
    if percent ~= lastPercent then
        lastPercent = percent
        percentLabel.Text = tostring(percent) .. "%"
        gui:SetAttribute("Progress", percent)
    end
    fill.Size = UDim2.fromScale(progress, 1)
    tip.Position = UDim2.fromScale(progress, 0.5)
    tipAlpha.value = progress > 0 and progress < 1 and 0.86 or 0
    sheen.Position = UDim2.fromScale((t * 0.50) % 1.65 - 0.35, 0)
    fillGradient.Offset = Vector2.new(0.07 * math.sin(t * 0.7), 0)
    trackGradient.Rotation = (t * 22) % 360
    borderGradient.Rotation = (t * 19) % 360
    barGlow.BackgroundColor3 = colorAt(t * 0.07)
    barGlowAlpha.value = 0.12 + 0.03 * math.sin(t * 2)
    hintAlpha.value = state == "ready" and 0.68 + 0.25 * (0.5 + 0.5 * math.sin(t * 2)) or 0.72

    -- The completion pulse fires immediately at 100%, then every 3 seconds.
    -- Exiting stops further flashes and lets all existing visuals fade together.
    local pulseAge = readyAt and ((now - readyAt) % CONFIG.FlashInterval) or 10
    if state == "closing" then pulseAge = 10 end
    local flashPulse = 0
    if pulseAge < 0.10 then
        flashPulse = smooth(pulseAge / 0.10)
    elseif pulseAge < 0.68 then
        flashPulse = 1 - smooth((pulseAge - 0.10) / 0.58)
    end
    flashAlpha.value = CONFIG.FlashOpacity * flashPulse
    local splash = pulseAge < 1.4 and 0.145 * math.exp(-4.2 * pulseAge) * math.sin(7.2 * pulseAge) or 0
    logoScale.Scale = (1 + 0.006 * math.sin(t * 1.6) + splash) * (1 + smooth(exit) * 0.035)
    for i, wave in ipairs(waves) do
        local age = pulseAge - (i - 1) * 0.17
        local phase = clamp(age / 1.25, 0, 1)
        local size = 0.54 + 0.90 * (1 - (1 - phase) ^ 3)
        wave.frame.Size = UDim2.fromScale(size, size)
        wave.alpha.value = age >= 0 and age < 1.25 and 0.30 * (1 - phase) ^ 2 or 0
        wave.stroke.Thickness = 1 + (1 - phase)
    end

    local targetX, targetY = 0, 0
    if not mobile then
        local point = UserInputService:GetMouseLocation()
        targetX = clamp(point.X / W - 0.5, -0.5, 0.5)
        targetY = clamp(point.Y / H - 0.5, -0.5, 0.5)
    end
    local damping = 1 - math.exp(-5 * math.min(dt, 0.1))
    pointerX = pointerX + (targetX - pointerX) * damping
    pointerY = pointerY + (targetY - pointerY) * damping
    background.Position = UDim2.fromOffset(backgroundX + math.sin(t * 0.24) * W * 0.003 - pointerX * 7, H / 2 + math.sin(t * 0.29) * H * 0.003 - pointerY * 5)
    logoHolder.Position = UDim2.fromOffset(centerX + pointerX * 8, centerY + math.sin(t * 1.25) * 3 + pointerY * 5 - splash * 18)
    logoHolder.Rotation = 0.50 * math.sin(t * 0.65)
    aura.Position = UDim2.fromOffset(centerX - pointerX * 3, centerY)
    for i, ring in ipairs(rings) do
        ring.gradient.Rotation = (i * 75 + t * (i % 2 == 0 and -13 or 11)) % 360
        local scale = ring.scale * (1 + 0.012 * math.sin(t * 0.9 + i))
        ring.frame.Size = UDim2.fromScale(scale, scale)
    end
    for i, light in ipairs(orbitLights) do
        local angle = light.phase + t * (i % 2 == 0 and -0.16 or 0.20)
        light.frame.Position = UDim2.fromScale(0.5 + math.cos(angle) * light.radius, 0.5 + math.sin(angle) * light.radius)
        light.alpha.value = 0.30 + 0.26 * (0.5 + 0.5 * math.sin(t * 1.3 + i))
    end
    for i, edge in ipairs(edges) do
        edge.frame.BackgroundColor3 = colorAt(t * 0.042 + i * 0.23)
        edge.alpha.value = 0.23 + 0.045 * math.sin(t * 1.2 + i)
    end
    for i, ribbon in ipairs(ribbons) do
        ribbon.Position = UDim2.fromScale(((t * 0.032 + i * 0.42) % 1.8) - 0.4, 0.20 + i * 0.17)
    end
    for _, particle in ipairs(particles) do
        local y = (particle.y - t * particle.speed) % 1.10 - 0.05
        particle.frame.Position = UDim2.fromScale(particle.x + 0.009 * math.sin(t * 0.7 + particle.phase), y)
        local twinkle = 0.5 + 0.5 * math.sin(t * 1.4 + particle.phase)
        particle.alpha.value = (particle.large and 0.075 or 0.18) + twinkle * (particle.large and 0.06 or 0.30)
    end
    for _, star in ipairs(stars) do
        local shine = math.max(0, math.sin(t * 0.95 + star.phase)) ^ 8
        star.frame.Size = UDim2.fromOffset(10 + 11 * shine, 10 + 11 * shine)
        for _, arm in ipairs(star.arms) do arm.value = shine * 0.70 * imageOpacity.logo end
    end
    -- Polling IsLoaded also handles a slow decode after PreloadAsync returns.
    if background.IsLoaded and background.Image ~= "" then imageLoaded.background = true end
    if logo.IsLoaded and logo.Image ~= "" then imageLoaded.logo = true end
    for key, loaded in pairs(imageLoaded) do
        if loaded then imageOpacity[key] = math.min(1, imageOpacity[key] + math.min(dt, 0.1) / 0.32) end
    end
    fallbackAlpha.value = 1 - imageOpacity.logo
    for _, item in ipairs(fades) do
        local assetOpacity = item.asset and imageOpacity[item.asset] or 1
        item.object[item.property] = 1 - clamp(item.value * visibility * assetOpacity, 0, 1)
    end
end)

loadImage("background", background, CONFIG.BackgroundAssetId)
loadImage("logo", logo, CONFIG.LogoAssetId)

-- An optional handle is returned to callers using loadstring(... )().
return {
    Gui = gui,
    Destroy = function() if alive then gui:Destroy() end end,
    IsComplete = function() return readyAt ~= nil end,
}
