-- HzReyzn Shaders 2.0 | standalone + HzReyzn Hub
-- Cosmetic client effects. No shader is enabled until you choose one.
-- SoundIds may be supplied through getgenv().HzReyznShaderOptions for Studio assets.
local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local SoundService = game:GetService("SoundService")
local options = (type(getgenv) == "function" and getgenv() or _G).HzReyznShaderOptions or {}
if type(options) ~= "table" then options = {} end
local mobile = UIS.TouchEnabled and not UIS.KeyboardEnabled
local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
local terrain = workspace.Terrain
local rng = Random.new()
local RGB = Color3.fromRGB

local CFG = {
    ChanceInterval = 5,
    WeatherChance = 0.01,

    StageSeconds = 120,
    CycleTransition = 40,

    RainArrival = 3.5,
    SnowArrival = 4,

    Radius = 100,
    RainLimit = 120,
    SnowLimit = 140,
    RainRate = 150,
    SnowRate = 24,

    PuddleLimit = 36,
    RippleLimit = 24,
    LensLimit = 20,
}

for _, name in ipairs({
    "HzReyznShaders",
    "HzReyznRain",
    "HzReyznSnow",
    "HZCinematicLighting"
}) do
    local old = playerGui:FindFirstChild(name)
    if old then old:Destroy() end
end

local S = {
    active = nil,
    real = false,
    cycle = 0,
    chance = 0,
    age = 0,
    intensity = 0,
    time = 0,
    dead = false,
    previous = nil,
    transition = nil,
    current = nil,
}

S.autoWeather = true
S.sound = options.Sound ~= false
S.volume = math.clamp(tonumber(options.Volume) or 0.3, 0, 1)
S.quality = mobile and "Balanced" or "High"
S.serial = 0
S.audioStatus = "Ready"
local updateSpecials, initSpecials, clearSpecials = function() end, function() end, function() end
local startAudio, stopAudio, updateAudio = function() end, function() end, function() end
local setQuality = function() end
local connections, created, parked = {}, {}, {}
local envConnections, ownedObjects, seenForeign = {}, {}, {}
local watchedContainers = {}
local envReady = false
local savedEffects, saved = {}, {}
local objects, flakes, ripples, puddles, lenses = {}, {}, {}, {}, {}
local snowGround = {}
local cleanup = function() end

local function connect(signal, fn)
    local c = signal:Connect(fn)
    table.insert(connections, c)
    return c
end

local function make(class, parent, props)
    local o = Instance.new(class)
    for k, v in pairs(props or {}) do
        o[k] = v
    end
    o.Parent = parent
    return o
end

local function round(o, r)
    make("UICorner", o, {
        CornerRadius = UDim.new(0, r)
    })
end

local function smooth(t)
    t = math.clamp(t, 0, 1)
    return t * t * (3 - 2 * t)
end

local function weather(name)
    return name == "Rain" or name == "Snowfall"
end

local function celestial(name)
    return name == "Noon" or name == "Sunrise"
        or name == "Sunset" or name == "Night"
end

local folder = make("Folder", workspace, {
    Name = "HZWeatherLocal"
})

local gui = make("ScreenGui", playerGui, {
    Name = "HzReyznShaders",
    ResetOnSpawn = false,
    DisplayOrder = 45,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
})

connect(gui.Destroying, function()
    if S.dead then return end
    S.dead = true

    for _, c in ipairs(connections) do
        c:Disconnect()
    end

    cleanup()
    folder:Destroy()
end)

local surface = make("Frame", gui, {
    Size = UDim2.fromScale(1, 1),
    BackgroundTransparency = 1,
})

local lensLayer = make("Frame", surface, {
    Size = UDim2.fromScale(1, 1),
    BackgroundTransparency = 1,
    ClipsDescendants = true,
})
local panel = make("Frame", surface, {
    Size = UDim2.fromOffset(340, 540),
    BackgroundColor3 = RGB(17, 18, 29),
    BackgroundTransparency = 0.08,
    BorderSizePixel = 0,
    ZIndex = 5,
})
round(panel, 17)

local scale = make("UIScale", panel, {Scale = 1})
local panelHeight = 540

local function border(o)
    local stroke = make("UIStroke", o, {
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
        Thickness = 1.8,
        Color = Color3.new(1, 1, 1),
    })

    return make("UIGradient", stroke, {
        Color = ColorSequence.new(
            RGB(239, 112, 182),
            RGB(138, 145, 255)
        ),
        Rotation = 25,
    })
end

local panelGradient = border(panel)

local function button(parent, text, x, y, w, h)
    local o = make("TextButton", parent, {
        Text = text,
        Position = UDim2.fromOffset(x, y),
        Size = UDim2.fromOffset(w, h),
        Font = Enum.Font.GothamBold,
        TextSize = 14,
        TextColor3 = RGB(242, 239, 255),
        BackgroundColor3 = RGB(35, 29, 48),
        BorderSizePixel = 0,
    })
    round(o, 11)
    make("UIGradient", o, {
        Color=ColorSequence.new(RGB(255,255,255),RGB(164,179,216)), Rotation=35,
    })
    make("UIStroke", o, {
        Name="OptionEdge", ApplyStrokeMode=Enum.ApplyStrokeMode.Border,
        Color=RGB(154,142,221), Thickness=1, Transparency=0.65,
    })
    return o
end

local heading = make("TextLabel", panel, {
    Text = "HzReyzn Shaders",
    Position = UDim2.fromOffset(15, 10),
    Size = UDim2.fromOffset(225, 30),
    BackgroundTransparency = 1,
    Font = Enum.Font.GothamBold,
    TextSize = 17,
    TextColor3 = RGB(245, 237, 255),
    TextXAlignment = Enum.TextXAlignment.Left,
    Active = true,
})

local mini = button(panel, "HZ", 253, 9, 34, 33)
mini.TextSize = 12
local close = button(panel, "×", 293, 9, 34, 33)
close.TextSize = 23
local scroll = make("ScrollingFrame", panel, {
    Name = "ShaderOptions", Position = UDim2.fromOffset(12, 51),
    Size = UDim2.new(1, -24, 1, -84), CanvasSize = UDim2.fromOffset(0, 570),
    BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 3,
    ScrollBarImageColor3 = RGB(173, 135, 237), ScrollingDirection = Enum.ScrollingDirection.Y,
})
local function section(text, y)
    return make("TextLabel", scroll, {Text = text, Position = UDim2.fromOffset(3,y),
        Size = UDim2.new(1,-6,0,24), BackgroundTransparency = 1, Font = Enum.Font.GothamBold,
        TextSize = 13, TextColor3 = RGB(182,174,215), TextXAlignment = Enum.TextXAlignment.Left})
end
section("CLASSIC SHADERS", 0)
local buttons = {}
for i, name in ipairs({"Noon", "Sunrise", "Sunset", "Night", "Rain", "Snowfall"}) do
    buttons[name] = button(scroll, name, 3+((i-1)%2)*155, 29+math.floor((i-1)/2)*46, 147, 38)
end
local realButton = button(scroll, "Real Time: OFF", 3, 172, 302, 37)
local randomButton = button(scroll, "Random weather: ON", 3, 216, 302, 37)
section("Especial Shaders 💎", 267)
for i, name in ipairs({"Meteor Shower", "Starfall", "Aurora Sky", "Deep Space"}) do
    buttons[name] = button(scroll, name, 3+((i-1)%2)*155, 297+math.floor((i-1)/2)*46, 147, 38)
end
local qualityButton = button(scroll, "Quality: "..S.quality, 3, 393, 302, 37)
local soundButton = button(scroll, "Sound: ON", 3, 437, 147, 37)
local quieter = button(scroll, "−", 158, 437, 38, 37)
local volumeLabel = make("TextLabel", scroll, {Text="30%", Position=UDim2.fromOffset(197,437),
    Size=UDim2.fromOffset(66,37), BackgroundTransparency=1, Font=Enum.Font.GothamBold,
    TextSize=13, TextColor3=RGB(228,224,244)})
local louder = button(scroll, "+", 267, 437, 38, 37)
local backButton = button(scroll, "Restore shader", 3, 485, 147, 38)
local defaultButton = button(scroll, "Default", 158, 485, 147, 38)
make("TextLabel", scroll, {Text="Made by hzReyzn", Position=UDim2.fromOffset(3,534),
    Size=UDim2.fromOffset(302,24), BackgroundTransparency=1, Font=Enum.Font.Gotham,
    TextSize=12, TextColor3=RGB(132,130,159)})
local status = make("TextLabel", panel, {Text="Choose a shader to begin", Position=UDim2.new(0,16,1,-29),
    Size=UDim2.new(1,-32,0,21), BackgroundTransparency=1, Font=Enum.Font.Gotham,
    TextSize=11, TextTruncate=Enum.TextTruncate.AtEnd, TextColor3=RGB(172,171,195),
    TextXAlignment=Enum.TextXAlignment.Left})
local launcher = button(surface, "HZ", 20, 85, 58, 58)
launcher.Visible = false
launcher.ZIndex = 5
launcher.TextSize = 21
local launcherGradient = border(launcher)
local function refreshUI()
    for name, b in pairs(buttons) do
        local edge = b:FindFirstChild("OptionEdge")
        local selected = name == S.active
        edge.Transparency = selected and 0.08 or 0.65
        edge.Thickness = selected and 1.8 or 1
        edge.Color = selected and RGB(225,156,255) or RGB(154,142,221)
        b.BackgroundColor3 = selected and RGB(76,43,97) or RGB(35,29,48)
        b.TextColor3 = selected and RGB(250,216,255) or RGB(242,239,255)
    end
    realButton.Text = S.real and "Real Time: ON" or "Real Time: OFF"
    randomButton.Text = S.autoWeather and "Random weather: ON" or "Random weather: OFF"
    soundButton.Text = S.sound and "Sound: ON" or "Sound: OFF"
    qualityButton.Text = "Quality: "..S.quality
    volumeLabel.Text = tostring(math.floor(S.volume*100+0.5)).."%"
    backButton.TextTransparency = S.previous and 0 or 0.6
    status.Text = S.error or (S.active and ((S.real and "Real Time" or S.active).."  •  "..S.audioStatus)
        or "Choose a shader to begin")
end
local BASE = {
    L = {
        ClockTime = 13.2,
        Brightness = 2.6,
        ExposureCompensation = 0.02,
        Ambient = RGB(53, 57, 68),
        OutdoorAmbient = RGB(112, 120, 135),
        ColorShift_Top = RGB(12, 6, 2),
        ColorShift_Bottom = RGB(0, 0, 0),
        EnvironmentDiffuseScale = 1,
        EnvironmentSpecularScale = 1,
        ShadowSoftness = 0.22,
        GeographicLatitude = 35,
        FogStart = 0, FogEnd = 100000,
    },
    A = {
        Density = 0.28, Offset = 0.15,
        Haze = 1.4, Glare = 0.15,
        Color = RGB(213, 217, 222),
        Decay = RGB(135, 127, 136),
    },
    C = {
        Cover = 0.42, Density = 0.55,
        Color = RGB(241, 234, 230),
    },
    CC = {
        Brightness = 0, Contrast = 0.1,
        Saturation = 0.035,
        TintColor = RGB(255, 251, 244),
    },
    B = {Intensity = 0.13, Size = 28, Threshold = 1.15},
    R = {Intensity = 0.035, Spread = 0.8},
    K = {SunAngularSize = 11, MoonAngularSize = 10, StarCount = 2200},
}

local function profile(overrides)
    local result = {}

    for group, props in pairs(BASE) do
        result[group] = {}
        for k, v in pairs(props) do
            result[group][k] = v
        end
    end

    for group, props in pairs(overrides or {}) do
        for k, v in pairs(props) do
            result[group][k] = v
        end
    end

    return result
end

local profiles = {
    -- Conserva el aspecto del antiguo Original.
    Noon = profile(),

    Sunrise = profile({
        L = {
            ClockTime = 6.65, Brightness = 2.3,
            ExposureCompensation = 0.1,
            Ambient = RGB(76, 72, 97),
            OutdoorAmbient = RGB(145, 149, 176),
            ColorShift_Top = RGB(31, 18, 14),
            ShadowSoftness = 0.35,
        },
        A = {
            Density = 0.34, Offset = 0.1, Haze = 2, Glare = 0.32,
            Color = RGB(225, 205, 229), Decay = RGB(178, 146, 188),
        },
        C = {Cover = 0.43, Density = 0.48, Color = RGB(255, 221, 210)},
        CC = {
            Brightness = 0.015, Contrast = 0.055,
            Saturation = 0.06, TintColor = RGB(255, 244, 251),
        },
        B = {Intensity = 0.18, Size = 34, Threshold = 1.05},
        R = {Intensity = 0.055, Spread = 0.85},
        K = {SunAngularSize = 12, StarCount = 0},
    }),

    Sunset = profile({
        L = {
            ClockTime = 17.55, Brightness = 2.2,
            ExposureCompensation = -0.04,
            Ambient = RGB(59, 45, 51),
            OutdoorAmbient = RGB(123, 95, 88),
            ColorShift_Top = RGB(55, 25, 5),
            ShadowSoftness = 0.3,
        },
        A = {
            Density = 0.37, Offset = 0.08, Haze = 2.55, Glare = 0.65,
            Color = RGB(255, 204, 151), Decay = RGB(190, 112, 84),
        },
        C = {Cover = 0.27, Density = 0.43, Color = RGB(255, 191, 140)},
        CC = {
            Contrast = 0.12, Saturation = 0.09,
            TintColor = RGB(255, 231, 210),
        },
        B = {Intensity = 0.22, Size = 40, Threshold = 1.05},
        R = {Intensity = 0.075, Spread = 0.87},
        K = {SunAngularSize = 13, StarCount = 0},
    }),

    Night = profile({
        L = {
            ClockTime = 23, Brightness = 0.85,
            ExposureCompensation = -0.18,
            Ambient = RGB(24, 30, 43),
            OutdoorAmbient = RGB(59, 72, 93),
            ColorShift_Top = RGB(0, 0, 0),
            ShadowSoftness = 0.25,
        },
        A = {
            Density = 0.24, Offset = 0.12, Haze = 1.15, Glare = 0,
            Color = RGB(99, 130, 146), Decay = RGB(24, 39, 52),
        },
        C = {Cover = 0.22, Density = 0.38, Color = RGB(52, 67, 80)},
        CC = {
            Contrast = 0.14, Saturation = -0.08,
            TintColor = RGB(219, 239, 249),
        },
        B = {Intensity = 0.24, Size = 30, Threshold = 0.95},
        R = {Intensity = 0},
        K = {MoonAngularSize = 8, StarCount = 1600},
    }),
}
profiles.Rain = profile({
    L = {
        ClockTime = 14, Brightness = 1.25,
        ExposureCompensation = -0.28,
        Ambient = RGB(47, 53, 65),
        OutdoorAmbient = RGB(91, 104, 121),
        ColorShift_Top = RGB(0, 0, 0),
    },
    A = {
        Density = 0.4, Offset = 0.12, Haze = 2.35, Glare = 0.02,
        Color = RGB(161, 177, 191), Decay = RGB(83, 101, 121),
    },
    C = {Cover = 0.94, Density = 0.86, Color = RGB(81, 91, 105)},
    CC = {
        Contrast = 0.075, Saturation = -0.15,
        TintColor = RGB(225, 237, 250),
    },
    B = {Intensity = 0.08},
    R = {Intensity = 0},
    K = {StarCount = 0},
})

profiles.Snowfall = profile({
    L = {
        ClockTime = 14, Brightness = 1.6,
        ExposureCompensation = 0.02,
        Ambient = RGB(79, 93, 115),
        OutdoorAmbient = RGB(137, 158, 181),
        ColorShift_Top = RGB(0, 0, 0),
    },
    A = {
        Density = 0.36, Offset = 0.13, Haze = 2.1, Glare = 0.06,
        Color = RGB(207, 223, 241), Decay = RGB(148, 171, 197),
    },
    C = {Cover = 0.88, Density = 0.72, Color = RGB(184, 199, 218)},
    CC = {
        Contrast = 0.035, Saturation = -0.17,
        TintColor = RGB(226, 240, 255),
    },
    B = {Intensity = 0.1},
    R = {Intensity = 0.015},
    K = {StarCount = 0},
})

-- The special modes use actual world-space visuals, occluded by buildings.
profiles["Meteor Shower"] = profile({
    L={ClockTime=20.3, Brightness=1.2, ExposureCompensation=-0.08,
        Ambient=RGB(43,29,38), OutdoorAmbient=RGB(87, 60, 63), ColorShift_Top=RGB(30,8,0)},
    A={Density=0.23, Haze=0.7, Glare=0, Color=RGB(148,103,116), Decay=RGB(62,32,54)},
    C={Cover=0.2,Density=0.35,Color=RGB(83,53,63)},
    CC={Contrast=0.11,Saturation=0.04,TintColor=RGB(255,225,216)},
    B={Intensity=0.25,Size=38,Threshold=1.05}, R={Intensity=0}, K={StarCount=2200,MoonAngularSize=7},
})
profiles.Starfall = profile({
    L={ClockTime=22.4,Brightness=1.0,ExposureCompensation=0,
        Ambient=RGB(28,33,56),OutdoorAmbient=RGB(58,74,107),ColorShift_Top=RGB(0,0,9)},
    A={Density=0.16,Haze=0.4,Glare=0,Color=RGB(111,141,201),Decay=RGB(32,38,81)},
    C={Cover=0.08,Density=0.23,Color=RGB(54,62,91)},
    CC={Contrast=0.1,Saturation=0.07,TintColor=RGB(220,235,255)},
    B={Intensity=0.28,Size=36,Threshold=1},R={Intensity=0},K={StarCount=5000,MoonAngularSize=8},
})
profiles["Aurora Sky"] = profile({
    L={ClockTime=23,Brightness=0.95,ExposureCompensation=-0.02,
        Ambient=RGB(25, 40, 48),OutdoorAmbient=RGB(57,90,96),ColorShift_Top=RGB(0,13,11)},
    A={Density=0.12,Haze=0.32,Glare=0,Color=RGB(91,155,171),Decay=RGB(28,43,77)},
    C={Cover=0.05,Density=0.2,Color=RGB(47,70, 80)},
    CC={Contrast=0.07,Saturation=0.09,TintColor=RGB(216,255,243)},
    B={Intensity=0.29,Size=42,Threshold=1.05},R={Intensity=0},K={StarCount=4400,MoonAngularSize=6},
})
profiles["Deep Space"] = profile({
    L={ClockTime=0,Brightness=1.1,ExposureCompensation=0.04,
        Ambient=RGB(39,32, 60),OutdoorAmbient=RGB(81, 70,116),ColorShift_Top=RGB(14,0,30)},
    A={Density=0.025,Offset=0.05,Haze=0,Glare=0,Color=RGB( 70,60,128),Decay=RGB(15,12,35)},
    C={Cover=0,Density=0,Color=RGB(32,22,55)},
    CC={Contrast=0.12,Saturation=0.12,TintColor=RGB(238,223,255)},
    B={Intensity=0.3,Size=40,Threshold=1.05},R={Intensity=0},K={StarCount=5000,MoonAngularSize=0,SunAngularSize=0},
})

local function blend(a, b, t, forward)
    local result = {}

    for group, props in pairs(a) do
        result[group] = {}

        for k, v in pairs(props) do
            local goal = b[group][k]

            if typeof(v) == "Color3" then
                result[group][k] = v:Lerp(goal, t)
            elseif k == "ClockTime" then
                local delta = forward
                    and ((goal - v) % 24)
                    or ((goal - v + 12) % 24 - 12)

                result[group][k] = (v + delta * t) % 24
            else
                result[group][k] = v + (goal - v) * t
            end
        end
    end

    return result
end

local function apply(p)
    for group, props in pairs(p) do
        local o = objects[group]

        if o then
            for k, v in pairs(props) do
                o[k] = k == "StarCount" and math.floor(v + 0.5) or v
            end
        end
    end
end

local function park(o)
    table.insert(parked, {Object = o, Parent = o.Parent})
    o.Parent = nil
end

local function clearVisuals()
    clearSpecials()
    stopAudio()
    folder:ClearAllChildren()
    lensLayer:ClearAllChildren()

    table.clear(flakes)
    table.clear(ripples)
    table.clear(puddles)
    table.clear(lenses)
    table.clear(snowGround)
end

local function restoreEnvironment()
    envReady = false
    for _, c in ipairs(envConnections) do c:Disconnect() end
    table.clear(envConnections)
    table.clear(seenForeign)
    table.clear(watchedContainers)
    for _, o in ipairs(created) do o:Destroy() end
    table.clear(created)
    table.clear(objects)
    table.clear(ownedObjects)

    for k, v in pairs(saved) do
        pcall(function() Lighting[k] = v end)
    end
    table.clear(saved)

    for _, entry in ipairs(parked) do
        pcall(function()
            if entry.Object.Parent == nil then
                entry.Object.Parent = entry.Parent
            end
        end)
    end
    table.clear(parked)

    for o, v in pairs(savedEffects) do
        pcall(function() o.Enabled = v end)
    end
    table.clear(savedEffects)
end

cleanup = function()
    S.serial = S.serial + 1
    S.current = nil
    S.error = nil
    S.active = nil
    S.real = false
    S.previous = nil
    S.transition = nil

    clearVisuals()
    restoreEnvironment()
end
local function owned(class, parent, props)
    local o = Instance.new(class)
    table.insert(created, o)
    ownedObjects[o] = true

    for k, v in pairs(props or {}) do o[k] = v end

    o.Parent = parent
    return o
end

local function watchForeign(o)
    if not envReady or ownedObjects[o] or seenForeign[o] then return end
    seenForeign[o] = true
    if o:IsA("Sky") or o:IsA("Atmosphere") or o:IsA("Clouds") then
        park(o)
    elseif o:IsA("PostEffect") then
        savedEffects[o] = o.Enabled
        o.Enabled = false
        table.insert(envConnections, o:GetPropertyChangedSignal("Enabled"):Connect(function()
            if envReady and o.Enabled then o.Enabled = false end
        end))
    end
end
local function watchContainer(parent)
    if not parent or watchedContainers[parent] then return end
    watchedContainers[parent] = true
    for _, o in ipairs(parent:GetChildren()) do watchForeign(o) end
    table.insert(envConnections, parent.ChildAdded:Connect(watchForeign))
end
local function initEnvironment()
    local initial = profile()

    for k in pairs(BASE.L) do
        saved[k] = Lighting[k]
        initial.L[k] = Lighting[k]
    end
    saved.GlobalShadows = Lighting.GlobalShadows

    local oldA = Lighting:FindFirstChildOfClass("Atmosphere")
    local oldC = terrain:FindFirstChildOfClass("Clouds")

    if oldA then
        for k in pairs(BASE.A) do initial.A[k] = oldA[k] end
    else
        initial.A.Density = 0
        initial.A.Haze = 0
        initial.A.Glare = 0
    end

    if oldC then
        for k in pairs(BASE.C) do initial.C[k] = oldC[k] end
        if not oldC.Enabled then initial.C.Cover = 0 end
    else
        initial.C.Cover = 0
    end

    initial.CC = {
        Brightness = 0,
        Contrast = 0,
        Saturation = 0,
        TintColor = Color3.new(1, 1, 1),
    }
    initial.B.Intensity = 0
    initial.R.Intensity = 0

    envReady = true
    watchContainer(Lighting)
    watchContainer(terrain)
    watchContainer(workspace.CurrentCamera)
    table.insert(envConnections, workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
        watchContainer(workspace.CurrentCamera)
    end))

    Lighting.GlobalShadows = true

    objects.L = Lighting
    objects.A = owned("Atmosphere", Lighting, {Name = "HZAtmosphere"})
    objects.C = owned("Clouds", terrain, {Enabled = true})
    objects.CC = owned("ColorCorrectionEffect", Lighting, {Enabled = true})
    objects.B = owned("BloomEffect", Lighting, {Enabled = true})
    objects.R = owned("SunRaysEffect", Lighting, {Enabled = true})

    objects.K = owned("Sky", Lighting, {
        SkyboxBk = "rbxasset://textures/sky/sky512_bk.tex",
        SkyboxDn = "rbxasset://textures/sky/sky512_dn.tex",
        SkyboxFt = "rbxasset://textures/sky/sky512_ft.tex",
        SkyboxLf = "rbxasset://textures/sky/sky512_lf.tex",
        SkyboxRt = "rbxasset://textures/sky/sky512_rt.tex",
        SkyboxUp = "rbxasset://textures/sky/sky512_up.tex",
        CelestialBodiesShown = true,
    })

    apply(initial)
    return initial
end

local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Exclude
params.IgnoreWater = false

local function refreshFilter()
    local list = {folder}

    for _, p in ipairs(Players:GetPlayers()) do
        if p.Character then table.insert(list, p.Character) end
    end

    params.FilterDescendantsInstances = list
end

local function visualPart(name)
    return make("Part", folder, {
        Name = name,
        Anchored = true,
        CanCollide = false,
        CanTouch = false,
        CanQuery = false,
        CastShadow = false,
        Transparency = 1,
        Size = Vector3.new(1, 0.02, 1),
    })
end
local function snowShape(parent)
    local frame = make("Frame", parent, {
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
    })

    local lines = {}

    for _, angle in ipairs({0, 60, 120}) do
        local line = make("Frame", frame, {
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.fromScale(0.5, 0.5),
            Size = UDim2.fromScale(0.14, 1),
            Rotation = angle,
            BorderSizePixel = 0,
            BackgroundColor3 = RGB(238, 248, 255),
            BackgroundTransparency = 1,
        })
        table.insert(lines, line)
    end

    return frame, lines
end

local function opacity(lines, value)
    for _, line in ipairs(lines) do
        line.BackgroundTransparency = 1 - math.clamp(value, 0, 1)
    end
end

-- The weather footprint follows the character, independently of camera zoom.
local function weatherCenter()
    local character = Players.LocalPlayer.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    if root then return root.Position end
    local camera = workspace.CurrentCamera
    return camera and camera.CFrame.Position or Vector3.new(0,0,0)
end

local function inWeatherRadius(position, center)
    local dx, dz = position.X-center.X, position.Z-center.Z
    return dx*dx + dz*dz <= CFG.Radius*CFG.Radius
end

local function initVisuals(name)
    local snow = name == "Snowfall"

    for i = 1, (snow and CFG.SnowLimit or CFG.RainLimit) do
        local p = visualPart(snow and "Snowflake" or "RainDrop")
        local item = {Part = p, Active = false}

        if snow then
            item.Gui = make("BillboardGui", p, {
                Adornee = p,
                Size = UDim2.fromScale(0.2, 0.2),
                AlwaysOnTop = false,
                LightInfluence = 0,
                MaxDistance = 0,
                Enabled = false,
            })
            item.Shape, item.Lines = snowShape(item.Gui)
        else
            -- Short, tapered streaks with faded ends; no opaque neon geometry.
            local length = rng:NextNumber(0.55, 1.0)
            local a = make("Attachment",p,{Position=Vector3.new(0,0,length/2)})
            local b = make("Attachment",p,{Position=Vector3.new(0,0,-length/2)})
            item.Beam = make("Beam",p,{
                Attachment0=a, Attachment1=b, FaceCamera=true, Segments=3,
                Width0=0.024, Width1=0.055, LightEmission=0, LightInfluence=0.25,
                Color=ColorSequence.new(RGB(185,209,225)), Enabled=false,
                Transparency=NumberSequence.new({
                    NumberSequenceKeypoint.new(0,1),
                    NumberSequenceKeypoint.new(0.3,0.58),
                    NumberSequenceKeypoint.new(0.75,0.42),
                    NumberSequenceKeypoint.new(1,1),
                }),
            })
        end

        table.insert(flakes, item)
    end

    for i = 1, CFG.LensLimit do
        local f = make("Frame", lensLayer, {
            BackgroundTransparency = 1,
            Visible = false,
        })

        local item = {Frame = f, Active = false}

        if snow then
            item.Shape, item.Lines = snowShape(f)
        else
            f.BackgroundColor3 = RGB(139, 170, 190)
            round(f, 20)
            make("UIGradient", f, {
                Rotation=30,
                Transparency=NumberSequence.new({
                    NumberSequenceKeypoint.new(0,0.75),
                    NumberSequenceKeypoint.new(0.4,0.15),
                    NumberSequenceKeypoint.new(1,0.9),
                }),
            })

            item.Stroke = make("UIStroke", f, {
                Color = RGB(215, 237, 249),
                Transparency = 1,
                Thickness = 1,
            })

            make("UIGradient", item.Stroke, {
                Rotation = 65,
                Transparency = NumberSequence.new({
                    NumberSequenceKeypoint.new(0, 0.2),
                    NumberSequenceKeypoint.new(0.5, 1),
                    NumberSequenceKeypoint.new(1, 0.95),
                }),
            })
        end

        table.insert(lenses, item)
    end

    if snow then
        for i = 1, (S.quality == "High" and 40 or S.quality == "Balanced" and 24 or 12) do
            local p = visualPart("SettledSnow")
            local g = make("SurfaceGui", p, {
                Face = Enum.NormalId.Top, CanvasSize = Vector2.new(64,64),
                AlwaysOnTop = false, LightInfluence = 0, Enabled = false,
            })
            local shape, lines = snowShape(g)
            table.insert(snowGround, {Part=p, Gui=g, Lines=lines, Active=false})
        end
        return
    end

    for i = 1, CFG.PuddleLimit do
        local p = visualPart("RainPuddle")
        p.Shape = Enum.PartType.Cylinder
        p.Material = Enum.Material.Glass
        p.Color = RGB(172, 190, 201)
        p.Reflectance = 0.45

        table.insert(puddles, {Part = p, Active = false})
    end

    for i = 1, CFG.RippleLimit do
        local p = visualPart("RainRipple")

        local g = make("SurfaceGui", p, {
            Face = Enum.NormalId.Top,
            CanvasSize = Vector2.new(100, 100),
            AlwaysOnTop = false,
            LightInfluence = 0,
            Enabled = false,
        })

        local f = make("Frame", g, {
            Position = UDim2.fromScale(0.1, 0.1),
            Size = UDim2.fromScale(0.8, 0.8),
            BackgroundTransparency = 1,
        })
        round(f, 50)

        local stroke = make("UIStroke", f, {
            Thickness = 2,
            Color = RGB(198, 220, 235),
            Transparency = 1,
        })

        table.insert(ripples, {
            Part = p, Gui = g, Stroke = stroke, Age = 1,
        })
    end
end

-- Bounded pools: no per-frame Instance.new and no permanent world modifications.
local special
local specialNames = {["Meteor Shower"]=true, Starfall=true, ["Aurora Sky"]=true, ["Deep Space"]=true}
local sparkleTexture = "rbxasset://textures/particles/sparkles_main.dds"
local smokeTexture = "rbxasset://textures/particles/smoke_main.dds"
local function qualityCount(low, balanced, high)
    return S.quality == "High" and high or S.quality == "Balanced" and balanced or low
end
local function point(parent, position)
    return make("Attachment", parent, {Position=position})
end
local function glow(parent, position, size, color, texture, transparency)
    local att = point(parent, position)
    local display = make("BillboardGui", att, {Adornee=att, Size=UDim2.fromScale(size,size),
        AlwaysOnTop=false, LightInfluence=0, MaxDistance=0})
    local picture = make("ImageLabel", display, {Size=UDim2.fromScale(1,1),BackgroundTransparency=1,
        Image=texture or sparkleTexture, ImageColor3=color, ImageTransparency=transparency or 0})
    table.insert(special.images, {image=picture, base=transparency or 0})
    return att, display, picture
end
local function beam(parent, a, b, color, width, transparency)
    local o = make("Beam", parent, {Attachment0=a,Attachment1=b,FaceCamera=true,
        Color=color,Width0=width,Width1=width,Segments=10,LightEmission=1,LightInfluence=0,
        Transparency=transparency or NumberSequence.new(0.3)})
    return o
end
local function buildStreaks(name)
    local meteor = name == "Meteor Shower"
    special.streaks = {}
    local tail = NumberSequence.new({NumberSequenceKeypoint.new(0,0.06),
        NumberSequenceKeypoint.new(0.28,0.28),NumberSequenceKeypoint.new(1,1)})
    for _=1,qualityCount(4,7,10) do
        local a, guiHead = glow(special.anchor,Vector3.new(),meteor and 19 or 9,
            meteor and RGB(255,207,127) or RGB(192,221,255))
        local b = point(special.anchor,Vector3.new())
        local streak = beam(special.anchor,a,b,ColorSequence.new(
            meteor and RGB(255,236,193) or RGB(226,243,255),
            meteor and RGB(242,71,18) or RGB(122,136,255)),meteor and 3.4 or 1.1,tail)
        streak.Width1=0.02
        local halo = beam(special.anchor,a,b,streak.Color,meteor and 11 or 3.5,
            NumberSequence.new({NumberSequenceKeypoint.new(0,0.72),NumberSequenceKeypoint.new(1,1)}))
        halo.Width1=0.1
        streak.Enabled=false;halo.Enabled=false;guiHead.Enabled=false
        table.insert(special.streaks,{a=a,b=b,beam=streak,halo=halo,head=guiHead,active=false})
    end
    special.meteor=meteor
    special.budget=0.9
end
local function buildAurora()
    special.curtains={}
    local count=qualityCount(15,23,31)
    for band=1,3 do
        for i=0,count-1 do
            local angle=i/(count-1)*math.rad(118)+math.rad((band-1)*120-62)
            local bottom=point(special.anchor,Vector3.new())
            local top=point(special.anchor,Vector3.new())
            local tint=band==2 and ColorSequence.new(RGB(80,237,186),RGB(154,81,247))
                or ColorSequence.new(RGB(72,252,199),RGB(100,128,252))
            local ribbon=beam(special.anchor,bottom,top,tint,qualityCount(210,143,109),
                NumberSequence.new({NumberSequenceKeypoint.new(0,1),NumberSequenceKeypoint.new(0.18,0.37),
                    NumberSequenceKeypoint.new(0.6,0.66),NumberSequenceKeypoint.new(1,1)}))
            ribbon.Texture=smokeTexture
            ribbon.TextureMode=Enum.TextureMode.Stretch
            ribbon.TextureSpeed=0.018
            ribbon.CurveSize0=35;ribbon.CurveSize1=-18
            ribbon.Width1=ribbon.Width0*0.55
            table.insert(special.curtains,{bottom=bottom,top=top,angle=angle,band=band,beam=ribbon,index=i})
        end
    end
end
local function spacePart(name, offset, size, color, transparency, material)
    local p=visualPart(name)
    p.Shape=Enum.PartType.Ball;p.Size=Vector3.new(size,size,size);p.Color=color
    p.Material=material or Enum.Material.SmoothPlastic;p.Transparency=transparency or 0
    table.insert(special.parts,{part=p,offset=offset,base=transparency or 0})
    return p
end
local function buildSpace()
    special.parts={}
    local center=Vector3.new(550,1650,-3300)
    local plane=CFrame.lookAt(center,Vector3.new())*CFrame.Angles(0,0,math.rad(-24))
    local starRng=Random.new(8041)
    glow(special.anchor,center,550,RGB(171,147,255),smokeTexture,0.3)
    glow(special.anchor,center,240,RGB(255,233,220),smokeTexture,0.08)
    glow(special.anchor,center,160,RGB(255,241,217),sparkleTexture,0.12)
    for i=1,qualityCount( 60,100,150) do
        local arm=i%3
        local t=starRng:NextNumber(0.05,1)
        local theta=arm*math.pi*2/3+t*math.pi*3.1
        local radius=80+t*1000
        local pos=plane:PointToWorldSpace(Vector3.new(math.cos(theta)*radius,
            math.sin(theta)*radius*0.48,starRng:NextNumber(-65,65)))
        local purple=RGB(181,126,247):Lerp(RGB(113,191,255),t)
        glow(special.anchor,pos,starRng:NextNumber(10,27),purple,sparkleTexture,starRng:NextNumber(0.05,0.32))
        if i%8==0 then glow(special.anchor,pos,210,purple,smokeTexture,0.84) end
    end
    local planet=Vector3.new(-2100,1000,-2900)
    spacePart("HZRingedPlanet",planet,680,RGB(162,133,172))
    spacePart("HZPlanetAtmosphere",planet,700,RGB(150,109,247),0.9,Enum.Material.Neon)
    local ringPlane=CFrame.new(planet)*CFrame.Angles(math.rad( 20),0,math.rad(-25))
    local ringCount=qualityCount(36,54,72)
    for layer=1,2 do
        local radius=430+layer*62
        for i=0,ringCount-1 do
            local angle=i/ringCount*math.pi*2
            local nextAngle=(i+1)/ringCount*math.pi*2
            local a=point(special.anchor,ringPlane:PointToWorldSpace(Vector3.new(math.cos(angle)*radius,0,math.sin(angle)*radius)))
            local b=point(special.anchor,ringPlane:PointToWorldSpace(Vector3.new(math.cos(nextAngle)*radius,0,math.sin(nextAngle)*radius)))
            local ring=beam(special.anchor,a,b,ColorSequence.new(RGB(183,157,210),RGB(134,149,207)),layer==1 and 49 or 28,
                NumberSequence.new(layer==1 and 0.3 or 0.52))
            ring.LightEmission=0.4;ring.Segments=1
            table.insert(special.fadeBeams,ring)
        end
    end
    local blue=Vector3.new(2520,640,-2850)
    spacePart("HZBluePlanet",blue,490,RGB(65,136,173))
    spacePart("HZBlueAtmosphere",blue,512,RGB(67,170,231),0.87,Enum.Material.Neon)
    spacePart("HZDistantMoon",Vector3.new(2250,1080,-3200),130,RGB(167,178,203))
end
clearSpecials=function()
    special=nil -- All instances are owned by the existing effect folder.
end
initSpecials=function(name)
    if not specialNames[name] then return end
    special={name=name,time=0,clock=1,images={},fadeBeams={},parts={}}
    special.anchor=visualPart("HZSkyAnchor")
    if name=="Meteor Shower" or name=="Starfall" then buildStreaks(name)
    elseif name=="Aurora Sky" then buildAurora()
    else buildSpace() end
end
updateSpecials=function(dt,camera)
    if not special then return end
    special.time=special.time+dt
    special.clock=special.clock+dt
    special.anchor.CFrame=CFrame.new(camera.CFrame.Position)
    for _,item in ipairs(special.parts) do
        item.part.Position=camera.CFrame.Position+item.offset
    end
    if special.streaks then
        special.budget=math.min(2,special.budget+dt*(special.meteor and 0.8 or 1.35))
        for _,item in ipairs(special.streaks) do
            if not item.active and special.budget>=1 then
                special.budget=special.budget-1
                local direction=camera.CFrame.LookVector
                local forward=Vector3.new(direction.X,0,direction.Z)
                forward=forward.Magnitude>0.01 and forward.Unit or Vector3.new(0,0,-1)
                local right=Vector3.new(-forward.Z,0,forward.X)
                local from=forward*rng:NextNumber(550,1050)+right*rng:NextNumber(-700,700)
                    +Vector3.new(0,rng:NextNumber(310,690),0)
                local to=from+right*rng:NextNumber(180,430)+Vector3.new(0,special.meteor and -360 or -70,0)
                item.origin=from;item.travel=to-from;item.age=0
                item.life=special.meteor and rng:NextNumber(2,3.6) or rng:NextNumber(1.1,1.9)
                item.active=true;item.beam.Enabled=true;item.halo.Enabled=true;item.head.Enabled=true
            end
            if item.active then
                item.age=item.age+dt
                local t=math.clamp(item.age/item.life,0,1)
                local head=item.origin+item.travel*t
                local fade=math.min(1,t*8,(1-t)*6)*S.intensity
                item.a.Position=head
                item.b.Position=head-item.travel.Unit*(special.meteor and 125 or 180)*math.min(1,t*5)
                item.beam.Width0=(special.meteor and 3.4 or 1.1)*fade
                item.halo.Width0=(special.meteor and 11 or 3.5)*fade
                item.head.Size=UDim2.fromScale((special.meteor and 19 or 9)*fade,(special.meteor and 19 or 9)*fade)
                if t>=1 then item.active=false;item.beam.Enabled=false;item.halo.Enabled=false;item.head.Enabled=false end
            end
        end
    end
    if special.clock<1/24 then return end
    special.clock=0
    for _,item in ipairs(special.images) do
        item.image.ImageTransparency=1-(1-item.base)*S.intensity
    end
    for _,item in ipairs(special.parts) do item.part.Transparency=1-(1-item.base)*S.intensity end
    for _,ring in ipairs(special.fadeBeams) do
        -- Width fade keeps the original ring transparency sequence intact.
        if not ring:GetAttribute("HZWidth") then ring:SetAttribute("HZWidth",ring.Width0) end
        ring.Width0=ring:GetAttribute("HZWidth")*S.intensity
        ring.Width1=ring.Width0
    end
    if special.curtains then
        local t=special.time*0.28
        for _,item in ipairs(special.curtains) do
            local angle=item.angle
            local wave=math.sin(angle*4+t+item.band)*65+math.cos(angle*7-t*0.6)*24
            local radius=1900+item.band*130
            local bottom=Vector3.new(math.sin(angle)*radius,450+wave,math.cos(angle)*radius)
            item.bottom.Position=bottom
            item.top.Position=bottom+Vector3.new(math.sin(t+angle*3)*50,330+math.sin(angle*5+t)*100,30)
            item.beam.Width0=qualityCount(210,143,109)*S.intensity
            item.beam.Width1=item.beam.Width0*0.55
        end
    end
end

-- Each ambience is an original, loopable soundscape synthesized for this release.
-- Roblox Sound IDs are also supported when custom local assets are unavailable.
local audioFiles={Rain="rain",Snowfall="snow",["Meteor Shower"]="meteors",
    Starfall="starfall",["Aurora Sky"]="aurora",["Deep Space"]="space"}
local audioRoot="https://raw.githubusercontent.com/hzReyzn/crazy/main/assets/shaders/"
local audioCache={}
local currentSound
local audioTicket=0
local customAsset=type(getcustomasset)=="function" and getcustomasset
    or type(getsynasset)=="function" and getsynasset
stopAudio=function()
    audioTicket=audioTicket+1
    if currentSound then currentSound:Stop();currentSound:Destroy();currentSound=nil end
    S.audioStatus=S.sound and "Ready" or "Sound off"
end
startAudio=function(name)
    stopAudio()
    if not S.sound then return end
    local file=audioFiles[name]
    if not file then S.audioStatus="Ambient lighting";return end
    local ticket=audioTicket
    local configured=type(options.SoundIds)=="table" and options.SoundIds[name]
    if not configured and (not customAsset or type(writefile)~="function") then
        S.audioStatus="Audio unavailable";return
    end
    S.audioStatus="Loading ambience…"
    -- Neither network fetch nor asset loading blocks shader selection or cleanup.
    task.delay(12,function()
        if S.dead or ticket~=audioTicket then return end
        if not currentSound or not currentSound.IsLoaded then
            stopAudio();S.audioStatus="Audio unavailable";refreshUI()
        end
    end)
    task.spawn(function()
        local ok,id=pcall(function()
            if configured then
                local value=tostring(configured)
                return value:match("^%d+$") and "rbxassetid://"..value or value
            end
            if audioCache[file] then return audioCache[file] end
            local path="HzReyznShaders_v2_"..file..".ogg"
            local exists=type(isfile)=="function" and isfile(path)
            if not exists then
                local data=game:HttpGet(audioRoot..file..".ogg")
                if ticket~=audioTicket or S.dead then return nil end
                if type(data)~="string" or data:sub(1,4)~="OggS" then error("Invalid ambience file") end
                writefile(path,data)
            end
            local asset=customAsset(path)
            audioCache[file]=asset
            return asset
        end)
        if ticket~=audioTicket or S.dead then return end
        if not ok or not id then S.audioStatus="Audio unavailable";refreshUI();return end
        local success,err=pcall(function()
            currentSound=make("Sound",SoundService,{Name="HzReyzn_"..file,SoundId=id,
                Looped=true,Volume=0,PlaybackSpeed=1})
            currentSound:Play()
        end)
        if not success then
            stopAudio();S.audioStatus="Audio unavailable"
            warn("[HzReyzn Shaders/audio] "..tostring(err))
        end
    end)
end
updateAudio=function(dt)
    if not currentSound then return end
    local target=S.volume*S.intensity
    currentSound.Volume=currentSound.Volume+(target-currentSound.Volume)*(1-math.exp(-dt*3))
    if currentSound.IsLoaded then S.audioStatus="Ambience on" end
end


local function stable(hit)
    if not hit or hit.Normal.Y < 0.7
        or hit.Material == Enum.Material.Water then
        return false
    end

    return hit.Instance == terrain
        or (hit.Instance:IsA("BasePart") and hit.Instance.Anchored)
end

local function impact(hit)
    if not stable(hit) or not inWeatherRadius(hit.Position, weatherCenter()) then return end

    local n = hit.Normal
    local tangent = Vector3.new(1, 0, 0)
    tangent = (tangent - n * tangent:Dot(n)).Unit

    if S.active == "Snowfall" then
        local slot
        for _, f in ipairs(snowGround) do
            if not f.Active then slot=f; break end
        end
        if not slot then return end
        slot.Active=true; slot.Born=S.time; slot.Support=hit.Instance
        local size=rng:NextNumber(0.35,0.75)
        slot.Part.Size=Vector3.new(size,0.02,size)
        slot.Part.CFrame=CFrame.fromMatrix(hit.Position+n*0.035,tangent,n,tangent:Cross(n))
        slot.Gui.Enabled=true
        opacity(slot.Lines,0.9)
        return
    end

    if rng:NextNumber() < 0.65 then
        for _, r in ipairs(ripples) do
            if r.Age >= 0.65 then
                r.Age = 0
                r.Gui.Enabled = true

                r.Part.CFrame = CFrame.fromMatrix(
                    hit.Position + n * 0.045,
                    tangent, n, tangent:Cross(n)
                )
                r.Part.Size = Vector3.new(0.2, 0.02, 0.2)
                break
            end
        end
    end

    if S.intensity < 0.35 or rng:NextNumber() > 0.1 then return end

    local slot
    for _, p in ipairs(puddles) do
        if p.Active and (p.Position - hit.Position).Magnitude < 2.5 then
            p.Born = S.time
            return
        end
        if not p.Active then slot = p end
    end
    if not slot then return end

    local diameter = rng:NextNumber(1.8, 4)
    local radius = diameter / 2

    for _, offset in ipairs({
        Vector3.new(radius, 0, 0),
        Vector3.new(-radius, 0, 0),
        Vector3.new(0, 0, radius),
        Vector3.new(0, 0, -radius),
    }) do
        local h = workspace:Raycast(
            hit.Position + offset + Vector3.new(0, 0.5, 0),
            Vector3.new(0, -1.1, 0), params
        )

        if not stable(h) or h.Instance ~= hit.Instance
            or math.abs(h.Position.Y - hit.Position.Y) > 0.07 then
            return
        end
    end

    slot.Active = true
    slot.Position = hit.Position
    slot.Support = hit.Instance
    slot.Born = S.time
    slot.Wet = 0
    slot.Diameter = diameter
    slot.Aspect = rng:NextNumber(0.65, 1)

    slot.Part.CFrame = CFrame.fromMatrix(
        hit.Position + n * 0.02,
        n, tangent, n:Cross(tangent)
    )
end

local function spawnFlake(camera)
    local slot

    for _, f in ipairs(flakes) do
        if not f.Active then slot = f; break end
    end
    if not slot then return end

    local snow = S.active == "Snowfall"
    local angle = rng:NextNumber(0, math.pi * 2)
    local radius = math.sqrt(rng:NextNumber()) * (rng:NextNumber() < 0.7 and 32 or CFG.Radius)

    local center = weatherCenter()
    local origin = center + Vector3.new(
        math.cos(angle) * radius,
        snow and rng:NextNumber(3, 12) or rng:NextNumber(10, 20),
        math.sin(angle) * radius
    )

    if workspace:Raycast(origin, Vector3.new(0, 220, 0), params) then
        return
    end

    slot.Active = true
    slot.Origin = origin
    slot.Age = 0
    slot.Part.Position = origin

    if snow then
        slot.Last = origin
        slot.Check = 0
        slot.Speed = rng:NextNumber(3, 6)
        slot.Life = rng:NextNumber(8, 12)
        slot.Phase = rng:NextNumber(0, math.pi * 2)
        slot.Sway = rng:NextNumber(0.35, 1.1)
        slot.Spin = rng:NextNumber(-45, 45)

        local size = rng:NextNumber(0.25, 0.45)
        slot.Gui.Size = UDim2.fromScale(size, size)
        slot.Gui.Enabled = true
        opacity(slot.Lines, 0)
    else
        slot.Direction = Vector3.new(0.065, -1, 0.025).Unit
        slot.Hit = workspace:Raycast(origin, slot.Direction * 80, params)
        slot.Distance = slot.Hit
            and (slot.Hit.Position - origin).Magnitude or 80
    end
end

local function spawnLens()
    for _, f in ipairs(lenses) do
        if not f.Active then
            f.Active = true
            f.Age = 0
            f.Life = rng:NextNumber(3, 5)
            f.X = rng:NextNumber(0.025, 0.975)
            f.Y = rng:NextNumber(0.02, 0.8)
            f.Speed = rng:NextNumber(0.007, 0.022)
            f.Spin = rng:NextNumber(-20, 20)

            local size = rng:NextInteger(
                8, S.active == "Snowfall" and 18 or 12
            )
            f.Frame.Size = UDim2.fromOffset(size, size * (S.active == "Snowfall" and 1.15 or 1.6))
            f.Frame.Position = UDim2.fromScale(f.X, f.Y)
            f.Frame.Visible = true
            return
        end
    end
end

local rainOpacity = {}
for i=0,20 do
    local a = i/20
    rainOpacity[i] = NumberSequence.new({NumberSequenceKeypoint.new(0,1),
        NumberSequenceKeypoint.new(0.3,1-0.42*a), NumberSequenceKeypoint.new(0.75,1-0.58*a),
        NumberSequenceKeypoint.new(1,1)})
end
local function updateVisuals(dt, camera)
    local center = weatherCenter()
    local snow = S.active == "Snowfall"

    for _, f in ipairs(flakes) do
        if f.Active then
            f.Age = f.Age + dt
            local remove = false

            if snow then
                local age = f.Age
                local phase = f.Phase

                local pos = f.Origin + Vector3.new(
                    age * 0.55
                        + (math.sin(age * 1.8 + phase) - math.sin(phase)) * f.Sway,
                    -age * f.Speed,
                    (math.cos(age * 1.3 + phase) - math.cos(phase)) * f.Sway
                )

                remove = age >= f.Life
                    or not inWeatherRadius(pos, center)

                f.Check = f.Check + dt

                if not remove and f.Check >= 0.12 then
                    f.Check = 0
                    local travel = pos - f.Last

                    if travel.Magnitude > 0 then
                        local hit = workspace:Raycast(f.Last, travel, params)
                        remove = hit ~= nil
                        if hit then impact(hit) end
                    end
                    f.Last = pos
                end

                f.Part.Position = pos
                f.Shape.Rotation = age * f.Spin

                opacity(
                    f.Lines,
                    0.85 * S.intensity * math.min(1, age / 0.5)
                        * math.clamp((f.Life - age) / 1.2, 0, 1)
                )
            else
                local travel = f.Age * 85
                local pos = f.Origin + f.Direction * travel
                remove = travel >= f.Distance or not inWeatherRadius(pos, center)

                if remove then
                    if travel >= f.Distance and f.Hit then impact(f.Hit) end
                else
                    f.Part.CFrame = CFrame.lookAt(pos, pos + f.Direction)
                    local distance = (pos-camera.CFrame.Position).Magnitude
                    -- Fade drops extremely close to the lens instead of enlarging them.
                    f.Beam.Enabled = distance > 1.5
                    local visibility = S.intensity * math.clamp((distance-1.5)/3,0,1)
                    f.Beam.Transparency = rainOpacity[math.floor(visibility*20+0.5)]
                end
            end

            if remove then
                f.Active = false
                f.Part.Transparency = 1
                if f.Gui then f.Gui.Enabled = false end
                if f.Beam then f.Beam.Enabled = false end
            end
        end
    end

    for _, f in ipairs(snowGround) do
        if f.Active then
            local age=S.time-f.Born
            local expired=age>=12 or not f.Support.Parent
                or not inWeatherRadius(f.Part.Position, center)
            if expired then
                f.Active=false; f.Gui.Enabled=false
            else
                opacity(f.Lines,0.9*math.clamp((12-age)/3,0,1))
            end
        end
    end

    for _, r in ipairs(ripples) do
        if r.Age < 0.65 then
            r.Age = r.Age + dt

            if not inWeatherRadius(r.Part.Position, center) then r.Age=0.65 end
            local a = math.clamp(r.Age / 0.65, 0, 1)
            local size = 0.2 + a * 1.7

            r.Part.Size = Vector3.new(size, 0.02, size)
            r.Stroke.Transparency = 0.2 + a * 0.8

            if a >= 1 then r.Gui.Enabled = false end
        end
    end

    for _, p in ipairs(puddles) do
        if p.Active then
            local outside = not inWeatherRadius(p.Position, center)
            local expired = S.time - p.Born > 65
                or not p.Support.Parent or outside
            if outside then p.Wet=0 end

            local target = expired and 0 or S.intensity

            p.Wet = p.Wet + (target - p.Wet) * math.min(1, dt * 0.7)

            local growth = 0.25 + 0.75 * p.Wet
            p.Part.Size = Vector3.new(
                0.018,
                p.Diameter * growth,
                p.Diameter * p.Aspect * growth
            )
            p.Part.Transparency = 1 - p.Wet * 0.26

            if expired and p.Wet < 0.015 then
                p.Active = false
                p.Part.Transparency = 1
            end
        end
    end

    for _, f in ipairs(lenses) do
        if f.Active then
            f.Age = f.Age + dt
            f.Y = f.Y + f.Speed * dt

            local a = math.min(1, f.Age / 0.5)
                * math.clamp((f.Life - f.Age) / 1.2, 0, 1)
                * S.intensity

            f.Frame.Position = UDim2.fromScale(
                f.X + math.sin(f.Age) * 0.003, f.Y
            )

            if snow then
                f.Shape.Rotation = f.Age * f.Spin
                opacity(f.Lines, a * 0.85)
            else
                f.Frame.BackgroundColor3 = RGB(139, 170, 190)
                f.Frame.BackgroundTransparency = 1 - a * 0.18
                f.Stroke.Transparency = 1 - a * 0.35
            end

            if f.Age >= f.Life then
                f.Active = false
                f.Frame.Visible = false
            end
        end
    end
end
local spawnBudget = 0
local lensBudget = 0
local filterClock = 0
local visualClock = 0
local paintClock = 0
local outdoors = false

local function setMode(name, resume)
    if S.dead or not profiles[name] then return end

    local previous = S.previous

    if weather(name) and celestial(S.active) then
        previous = {
            name = S.active,
            real = S.real,
            cycle = S.cycle,
            profile = S.current,
        }
    elseif not weather(name) then
        previous = nil
    end

    -- Termina el modo anterior antes de iniciar el siguiente.
    S.active = nil
    S.real = false
    S.transition = nil

    clearVisuals()
    S.serial = S.serial + 1
    S.error = nil

    spawnBudget = 0
    lensBudget = 0
    visualClock = 0
    paintClock = 0
    filterClock = 0
    outdoors = false

    S.age = 0
    S.intensity = 0
    S.chance = 0
    S.cycle = 0
    S.previous = previous

    local ok, err = pcall(function()
        local initial = envReady and S.current or initEnvironment()

        if weather(name) then
            initVisuals(name)
        end

        S.active = name
        initSpecials(name)
        startAudio(name)
        S.current = initial
        S.real = resume and resume.real or false
        S.cycle = resume and resume.cycle or 0

        S.transition = {
            from = initial,
            target = resume and resume.profile or profiles[name],
            time = 0,
            duration = name == "Rain" and CFG.RainArrival
                or name == "Snowfall" and CFG.SnowArrival
                or 2.5,
        }

        refreshFilter()
    end)

    if not ok then
        cleanup()
        S.error = "Shader failed • select it to retry"
        warn("[HzReyzn Shaders] " .. tostring(err))
    end

    refreshUI()

    if not ok then
        heading.Text = "Shader unavailable • Retry"
    else
        heading.Text = "HzReyzn Shaders"
    end
end

local function defaultMode()
    if S.dead then return end
    cleanup()

    S.age = 0
    S.intensity = 0
    S.chance = 0
    S.cycle = 0
    S.current = nil
    heading.Text = "HzReyzn Shaders"

    refreshUI()
end

setQuality=function(name)
    if S.dead then return false end
    if name~="Low" and name~="Balanced" and name~="High" then return false end
    S.quality=name
    CFG.RainLimit=qualityCount(65,105,165)
    CFG.SnowLimit=qualityCount(60,100,155)
    CFG.RainRate=qualityCount(90,145,220)
    CFG.SnowRate=qualityCount(13, 20,30)
    CFG.PuddleLimit=qualityCount(10, 20,32)
    CFG.RippleLimit=qualityCount(8,16,24)
    CFG.LensLimit=qualityCount(6,10,16)
    if S.active then
        local resume={real=S.real,cycle=S.cycle,profile=S.current}
        local previous=S.previous
        setMode(S.active,resume)
        S.previous=previous
    end
    refreshUI()
    return true
end
local function setSound(enabled)
    if S.dead then return end
    S.sound=enabled==true
    if S.active then startAudio(S.active) else stopAudio() end
    refreshUI()
end
connect(randomButton.Activated,function()
    S.autoWeather=not S.autoWeather;S.chance=0;refreshUI()
end)
connect(qualityButton.Activated,function()
    setQuality(S.quality=="High" and "Low" or S.quality=="Low" and "Balanced" or "High")
end)
connect(soundButton.Activated,function() setSound(not S.sound) end)
connect(quieter.Activated,function() S.volume=math.clamp(S.volume-0.1,0,1);refreshUI() end)
connect(louder.Activated,function() S.volume=math.clamp(S.volume+0.1,0,1);refreshUI() end)
setQuality(options.Quality or S.quality)


for name, b in pairs(buttons) do
    local mode = name
    connect(b.Activated, function()
        setMode(mode)
    end)
end

connect(defaultButton.Activated, defaultMode)

connect(backButton.Activated, function()
    local previous = S.previous
    if not previous then return end

    setMode(previous.name, previous)
end)

connect(realButton.Activated, function()
    if S.real then
        S.real = false
        refreshUI()
    else
        setMode("Sunrise")

        if S.active then
            S.real = true
            S.cycle = 0
            refreshUI()
        end
    end
end)

local ORDER = {"Sunrise", "Noon", "Sunset", "Night"}
local function guardFrame(fn)
    return function(...)
        if S.dead then return end
        local ok, err = pcall(fn, ...)
        if not ok then
            cleanup()
            S.error = "Effect interrupted • select a shader to retry"
            warn("[HzReyzn Shaders/frame] "..tostring(err))
            refreshUI()
        end
    end
end
connect(RunService.Heartbeat, guardFrame(function(rawDt)
    local dt = math.min(rawDt, 0.25)
    S.time = S.time + dt

    panelGradient.Rotation = (S.time * 15) % 360
    launcherGradient.Rotation = panelGradient.Rotation

    if not S.active then return end

    S.age = S.age + dt
    S.intensity = smooth(S.age / 2.5)
    updateAudio(dt)

    if S.transition then
        local t = S.transition
        t.time = t.time + dt

        S.current = blend(
            t.from, t.target,
            smooth(t.time / t.duration),
            false
        )

        if t.time >= t.duration then
            S.current = t.target
            S.transition = nil
        end

    elseif S.real then
        local stage = math.max(1, CFG.StageSeconds)
        local fade = math.clamp(CFG.CycleTransition, 0.1, stage)

        S.cycle = (S.cycle + rawDt) % (stage * #ORDER)

        local index = math.floor(S.cycle / stage) + 1
        local nextIndex = index % #ORDER + 1
        local alpha = smooth(
            ((S.cycle % stage) - (stage - fade)) / fade
        )

        S.active = ORDER[index]
        S.current = blend(
            profiles[ORDER[index]],
            profiles[ORDER[nextIndex]],
            alpha,
            true
        )
    end

    -- 1% total cada 5 segundos.
    -- Si ocurre: Rain o Snowfall, con igual probabilidad.
    if S.autoWeather and celestial(S.active) then
        S.chance = S.chance + rawDt

        while S.chance >= CFG.ChanceInterval do
            S.chance = S.chance - CFG.ChanceInterval

            if rng:NextNumber() < CFG.WeatherChance then
                setMode(
                    rng:NextInteger(1, 2) == 1
                        and "Rain" or "Snowfall"
                )
                return
            end
        end
    end

    paintClock = paintClock + dt
    if paintClock >= 1 / 30 then
        paintClock = 0
        apply(S.current)
        refreshUI()
    end

    if not weather(S.active) then return end

    local duration = S.active == "Rain"
        and CFG.RainArrival or CFG.SnowArrival

    S.intensity = smooth(S.age / 2.5)

    local camera = workspace.CurrentCamera
    if not camera then return end

    filterClock = filterClock + dt
    if filterClock >= 0.4 then
        filterClock = 0
        refreshFilter()

        outdoors = workspace:Raycast(
            camera.CFrame.Position,
            Vector3.new(0, 220, 0),
            params
        ) == nil
    end

    local rate = S.active == "Rain" and CFG.RainRate or CFG.SnowRate

    spawnBudget = math.min(
        spawnBudget + dt * rate * S.intensity, 12
    )

    local count = math.floor(spawnBudget)
    spawnBudget = spawnBudget - count

    for i = 1, count do
        spawnFlake(camera)
    end

    if outdoors and S.intensity > 0.1 then
        lensBudget = lensBudget + dt * 4 * S.intensity

        if lensBudget >= 1 then
            lensBudget = lensBudget - 1
            spawnLens()
        end
    else
        lensBudget = 0
    end

end))
connect(RunService.RenderStepped, guardFrame(function(dt)
    if not S.active or S.dead then return end
    local camera = workspace.CurrentCamera
    if not camera then return end
    dt = math.min(dt, 0.15)
    if weather(S.active) then updateVisuals(dt, camera) end
    updateSpecials(dt, camera)
end))
local minimized = false
local launcherPlaced = false

local function clampPanel(x, y)
    local size = surface.AbsoluteSize

    panel.Position = UDim2.fromOffset(
        math.clamp(x, 5, math.max(5, size.X - 340 * scale.Scale - 5)),
        math.clamp(y, 5, math.max(5, size.Y - panelHeight * scale.Scale - 5))
    )
end

local function clampLauncher(x, y)
    local size = surface.AbsoluteSize

    launcher.Position = UDim2.fromOffset(
        math.clamp(x, 6, math.max(6, size.X - 64)),
        math.clamp(y, 6, math.max(6, size.Y - 64))
    )
end

local function resize(center)
    local size = surface.AbsoluteSize
    if size.X < 1 or size.Y < 1 then return end

    scale.Scale = math.max(0.05, math.min(
        1, (size.X - 20) / 340
    ))

    panelHeight = math.clamp((size.Y-20)/scale.Scale, 220, 540)
    panel.Size = UDim2.fromOffset(340, panelHeight)
    if center then
        clampPanel(
            (size.X - 340 * scale.Scale) / 2,
            (size.Y - panelHeight * scale.Scale) / 2
        )
    else
        clampPanel(panel.Position.X.Offset, panel.Position.Y.Offset)
    end

    clampLauncher(
        launcher.Position.X.Offset,
        launcher.Position.Y.Offset
    )
end

local function toggleMinimize()
    minimized = not minimized

    if minimized and not launcherPlaced then
        clampLauncher(
            panel.Position.X.Offset,
            panel.Position.Y.Offset
        )
        launcherPlaced = true
    end

    panel.Visible = not minimized
    launcher.Visible = minimized
end

local function draggable(handle, target, clamp, onTap)
    local held, startPoint, startPosition
    local moved = false

    connect(handle.InputBegan, function(input)
        if held then return end

        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then

            held = input
            startPoint = input.Position
            startPosition = target.Position
            moved = false
        end
    end)

    connect(UIS.InputChanged, function(input)
        if not held then return end

        local mouse = held.UserInputType
            == Enum.UserInputType.MouseButton1

        if input == held
            or (mouse and input.UserInputType
                == Enum.UserInputType.MouseMovement) then

            local delta = input.Position - startPoint
            if delta.Magnitude > 8 then moved = true end

            if moved then
                clamp(
                    startPosition.X.Offset + delta.X,
                    startPosition.Y.Offset + delta.Y
                )
            end
        end
    end)

    connect(UIS.InputEnded, function(input)
        if input ~= held then return end

        local dragged = moved
            or (input.Position - startPoint).Magnitude > 8

        held = nil

        if onTap and not dragged then
            local p = input.Position
            local a = handle.AbsolutePosition
            local s = handle.AbsoluteSize

            if p.X >= a.X and p.X <= a.X + s.X
                and p.Y >= a.Y and p.Y <= a.Y + s.Y then
                onTap()
            end
        end
    end)

    connect(UIS.WindowFocusReleased, function()
        held = nil
    end)
end

draggable(heading, panel, clampPanel)

draggable(launcher, launcher, clampLauncher, function()
    if minimized then
        toggleMinimize()
    end
end)

connect(mini.Activated, toggleMinimize)

connect(close.Activated, function()
    gui:Destroy()
end)

connect(surface:GetPropertyChangedSignal("AbsoluteSize"), function()
    resize(false)
end)

-- Al ejecutar: solo aparece la interfaz.
-- No se activa ningún shader ni ninguna comprobación aleatoria.
refreshUI()

task.defer(function()
    if not S.dead and gui.Parent then
        resize(true)
    end
end)




-- Optional controller for hub/Studio integration. Execution still opens the UI.
return {
    Version="2.0.0",
    SetMode=function(name) if not S.dead then setMode(name) end;return S.active==name end,
    Default=defaultMode,
    Destroy=function() if not S.dead then gui:Destroy() end end,
    Show=function() if not S.dead and minimized then toggleMinimize() end end,
    SetQuality=setQuality,
    SetSound=setSound,
    SetAutoWeather=function(enabled) S.autoWeather=enabled==true;S.chance=0;refreshUI() end,
    GetState=function() return {Mode=S.active,RealTime=S.real,Quality=S.quality,
        Sound=S.sound,Volume=S.volume,AudioStatus=S.audioStatus,Destroyed=S.dead} end,
}
