-- S&NC Shaders 3.0 | standalone + HzReyzn Hub compatibility
-- Cosmetic client effects. No shader is enabled until you choose one.
-- SoundIds may be supplied through getgenv().HzReyznShaderOptions for Studio assets.
local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
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
    "SNCShaders",
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

-- Procedural texture cache. Audio stays in the unchanged v2 sound controller.
local ASSETS = {ready={},completed=0,total=13,started=false}
do
    local names={"ton618","ringed_planet","ice_planet","galaxy","aurora_curtain","streak",
        "sky_ft","sky_bk","sky_rt","sky_lf","sky_up","sky_dn"}
    local asset=type(getcustomasset)=="function" and getcustomasset
        or type(getsynasset)=="function" and getsynasset
    local root="https://raw.githubusercontent.com/hzReyzn/crazy/main/assets/snc/"
    local blackBytes=string.char(137,80,78,71,13,10,26,10,0,0,0,13,73,72,68,82,0,0,0,4,0,0,0,4,8,2,0,0,0,38,147,9,41,0,0,0,12,73,68,65,84,120,218,99,96,32,29,0,0,0,52,0,1,72,163,125,111,0,0,0,0,73,69,78,68,174,66,96,130)
    function ASSETS.Start()
        if ASSETS.started then return end
        ASSETS.started=true
        local available=asset and type(writefile)=="function"
        if available then
            pcall(function()
                local path="SNCShaders_r3_black.png"
                writefile(path,blackBytes)
                ASSETS.ready.black=asset(path)
            end)
        end
        ASSETS.completed=1
        if not available then ASSETS.completed=ASSETS.total;return end
        local nextIndex=0
        for _=1,3 do
            task.spawn(function()
                while not S.dead do
                    nextIndex=nextIndex+1
                    local name=names[nextIndex]
                    if not name then return end
                    local ok,id=pcall(function()
                        local path="SNCShaders_r3_"..name..".png"
                        local exists=type(isfile)=="function" and isfile(path)
                        if exists and type(readfile)=="function" then
                            local data=readfile(path)
                            exists=type(data)=="string" and data:sub(1,8)=="\137PNG\r\n\26\n"
                        end
                        if not exists then
                            local data=game:HttpGet(root..name..".png")
                            if S.dead then return nil end
                            if type(data)~="string" or data:sub(1,8)~="\137PNG\r\n\26\n" then error("Texture unavailable") end
                            writefile(path,data)
                        end
                        return asset(path)
                    end)
                    if S.dead then return end
                    if ok and id then ASSETS.ready[name]=id end
                    ASSETS.completed=ASSETS.completed+1
                end
            end)
        end
    end
end

local folder = make("Folder", workspace, {
    Name = "HZWeatherLocal"
})

local gui = make("ScreenGui", playerGui, {
    Name = "SNCShaders",
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

local ui={width=368,height=520,expanded=false,phase="loading",elapsed=0,progress=0,
    ticket=0,closing=false,dragTarget=nil,stars={},rings={}}
local surface = make("Frame", gui, {Size=UDim2.fromScale(1,1),BackgroundTransparency=1})
local lensLayer = make("Frame", surface, {Size=UDim2.fromScale(1,1),BackgroundTransparency=1,ClipsDescendants=true})
local panel = make("CanvasGroup", surface, {Name="SCPanel",Size=UDim2.fromOffset(368,520),
    BackgroundColor3=RGB(12,13,15),BackgroundTransparency=0.025,BorderSizePixel=0,
    GroupTransparency=1,Visible=false,ZIndex=5,ClipsDescendants=true})
round(panel,18)
local scale = make("UIScale",panel,{Scale=1})
local panelHeight=520
local function border(o)
    local edge=make("UIStroke",o,{ApplyStrokeMode=Enum.ApplyStrokeMode.Border,Thickness=1.4,
        Color=RGB(255,255,255),Transparency=0.16})
    return make("UIGradient",edge,{Color=ColorSequence.new({ColorSequenceKeypoint.new(0,RGB(90,94,103)),
        ColorSequenceKeypoint.new(.45,RGB(255,255,255)),ColorSequenceKeypoint.new(.65,RGB(205,210,219)),
        ColorSequenceKeypoint.new(1,RGB(88,93,103))}),Rotation=25})
end
local panelGradient=border(panel)
make("UIStroke",panel,{Thickness=4,Transparency=.94,Color=RGB(255,255,255),ApplyStrokeMode=Enum.ApplyStrokeMode.Border})
local function animate(o,duration,props,style)
    local tween=TweenService:Create(o,TweenInfo.new(duration,style or Enum.EasingStyle.Quint,Enum.EasingDirection.Out),props)
    tween:Play()
    return tween
end
local function button(parent,text,x,y,w,h)
    local o=make("TextButton",parent,{Name=text,Text=text,Position=UDim2.fromOffset(x,y),Size=UDim2.fromOffset(w,h),
        BackgroundColor3=RGB( 20,22,26),TextColor3=RGB(236,238,243),BorderSizePixel=0,
        Font=Enum.Font.GothamMedium,TextSize=13,AutoButtonColor=false})
    round(o,10)
    make("UIStroke",o,{Name="OptionEdge",ApplyStrokeMode=Enum.ApplyStrokeMode.Border,
        Color=RGB(226,231,239),Transparency=.80,Thickness=1})
    make("UIGradient",o,{Color=ColorSequence.new(RGB(255,255,255),RGB(181,186,197)),Rotation=90})
    local press=make("UIScale",o,{Scale=1})
    connect(o.InputBegan,function(input)
        if input.UserInputType==Enum.UserInputType.Touch or input.UserInputType==Enum.UserInputType.MouseButton1 then
            animate(press,.12,{Scale=.975})
        end
    end)
    connect(o.InputEnded,function() animate(press,.25,{Scale=1},Enum.EasingStyle.Back) end)
    return o
end
local brand=make("Frame",panel,{Position=UDim2.fromOffset(14,14),Size=UDim2.fromOffset(34,34),
    BackgroundColor3=RGB(236,240,247),BorderSizePixel=0});round(brand,10)
make("TextLabel",brand,{Size=UDim2.fromScale(1,1),BackgroundTransparency=1,Text="SC",
    Font=Enum.Font.GothamBold,TextSize=14,TextColor3=RGB(12,13,15)})
local heading=make("TextLabel",panel,{Text="S&NC Shaders",Position=UDim2.fromOffset(58,12),
    Size=UDim2.new(1,-193,0,23),BackgroundTransparency=1,Font=Enum.Font.GothamBold,
    TextSize=16,TextColor3=RGB(248,249,252),TextXAlignment=Enum.TextXAlignment.Left,Active=true})
make("TextLabel",panel,{Text="LIGHT  /  ATMOSPHERE",Position=UDim2.fromOffset(59,36),Size=UDim2.new(1,-193,0,13),
    BackgroundTransparency=1,Font=Enum.Font.Gotham,TextSize=8,TextColor3=RGB(132,139,151),TextXAlignment=Enum.TextXAlignment.Left})
local expandButton=button(panel,"↔",0,15,30,30);expandButton.Position=UDim2.new(1,-115,0,15)
local mini=button(panel,"−",0,15,30,30);mini.Position=UDim2.new(1,-79,0,15)
local close=button(panel,"×",0,15,30,30);close.Position=UDim2.new(1,-43,0,15);close.TextSize=20
make("Frame",panel,{Position=UDim2.fromOffset(16,62),Size=UDim2.new(1,-32,0,1),
    BackgroundColor3=RGB(255,255,255),BackgroundTransparency=.85,BorderSizePixel=0})
local scroll=make("ScrollingFrame",panel,{Name="ShaderOptions",Position=UDim2.fromOffset(12, 74),
    Size=UDim2.new(1,-24,1,-111),CanvasSize=UDim2.fromOffset(0,522),BackgroundTransparency=1,
    BorderSizePixel=0,ScrollBarThickness=2,ScrollBarImageColor3=RGB(235,239,247),ScrollingDirection=Enum.ScrollingDirection.Y})
local function section(text,y)
    make("TextLabel",scroll,{Text=text,Position=UDim2.fromOffset(5,y),Size=UDim2.new(1,-10,0,21),
        BackgroundTransparency=1,Font=Enum.Font.GothamBold,TextSize=11,TextColor3=RGB(153,160,173),TextXAlignment=Enum.TextXAlignment.Left})
end
local function halfButton(text,y,column)
    local o=button(scroll,text,0,y,100,40)
    o.Position=UDim2.new(column*.5,5,0,y)
    o.Size=UDim2.new(.5,-10,0,40)
    return o
end
local function fullButton(text,y)
    local o=button(scroll,text,5,y,100,37);o.Size=UDim2.new(1,-10,0,37);return o
end
section("CLASSIC ATMOSPHERES",0)
local buttons={}
for i,name in ipairs({"Noon","Sunrise","Sunset","Night","Rain","Snowfall"}) do
    buttons[name]=halfButton(name,29+math.floor((i-1)/2)*47,(i-1)%2)
end
local realButton=fullButton("Real Time: OFF",176)
local randomButton=fullButton("Random weather: ON",220)
section("Especial Shaders 💎",270)
for i,name in ipairs({"Meteor Shower","Starfall","Aurora Sky","Deep Space"}) do
    buttons[name]=halfButton(name,300+math.floor((i-1)/2)*47,(i-1)%2)
end
local soundButton=button(scroll,"Sound: ON",5,402,100,36);soundButton.Size=UDim2.new(.5,-10,0,36)
local quieter=button(scroll,"−",0,402,34,36);quieter.Position=UDim2.new(.5,5,0,402)
local volumeLabel=make("TextLabel",scroll,{Text="30%",Position=UDim2.new(.5, 44,0,402),
    Size=UDim2.new(.5,-88,0,36),BackgroundTransparency=1,Font=Enum.Font.GothamMedium,TextSize=12,TextColor3=RGB(220,225,233)})
local louder=button(scroll,"+",0,402,34,36);louder.Position=UDim2.new(1,-39,0,402)
local backButton=halfButton("Restore shader",451,0)
local defaultButton=halfButton("Default",451,1)
make("TextLabel",scroll,{Text="Made by hzReyzn",Position=UDim2.fromOffset(5,496),Size=UDim2.new(1,-10,0,20),
    BackgroundTransparency=1,Font=Enum.Font.Gotham,TextSize=10,TextColor3=RGB(106,113,125)})
local status=make("TextLabel",panel,{Text="Choose an atmosphere",Position=UDim2.new(0,18,1,-28),Size=UDim2.new(1,-36,0,18),
    BackgroundTransparency=1,Font=Enum.Font.Gotham,TextSize=10,TextTruncate=Enum.TextTruncate.AtEnd,
    TextColor3=RGB(146,155,168),TextXAlignment=Enum.TextXAlignment.Left})
local launcher=button(surface,"SC",20,85,58,58)
launcher.Visible=false;launcher.ZIndex=6;launcher.TextSize=19
local launcherScale=launcher:FindFirstChildOfClass("UIScale")
local launcherGradient=border(launcher)
local function refreshUI()
    for name,b in pairs(buttons) do
        local selected=name==S.active
        local edge=b:FindFirstChild("OptionEdge")
        edge.Transparency=selected and .12 or .8
        edge.Thickness=selected and 1.5 or 1
        b.BackgroundColor3=selected and RGB(46, 50,57) or RGB(20,22,26)
        b.TextColor3=selected and RGB(255,255,255) or RGB(224,228,236)
    end
    realButton.Text=S.real and "Real Time: ON" or "Real Time: OFF"
    randomButton.Text=S.autoWeather and "Random weather: ON" or "Random weather: OFF"
    soundButton.Text=S.sound and "Sound: ON" or "Sound: OFF"
    volumeLabel.Text=tostring(math.floor(S.volume*100+.5)).."%"
    backButton.TextTransparency=S.previous and 0 or .55
    status.Text=S.error or (S.active and ((S.real and "Real Time" or S.active).."  •  "..S.audioStatus) or "Choose an atmosphere")
end

-- The intro is UI-only: it never modifies the camera or any weather properties.
local loading=make("CanvasGroup",surface,{Name="SNCLoading",Size=UDim2.fromScale(1,1),BackgroundColor3=RGB(3,4,6),
    BorderSizePixel=0,GroupTransparency=1,ZIndex=30,Active=true,ClipsDescendants=true})
local introCard=make("CanvasGroup",loading,{AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(.5,.52),
    Size=UDim2.new(.72,0,0,170),BackgroundTransparency=1,GroupTransparency=0})
make("UISizeConstraint",introCard,{MaxSize=Vector2.new(620,170),MinSize=Vector2.new(200,170)})
make("TextLabel",introCard,{Text="S&NC Shaders",Position=UDim2.fromOffset(0,14),Size=UDim2.new(1,0,0, 44),
    Font=Enum.Font.GothamBold,TextSize= 32,TextColor3=RGB(248,250,255),BackgroundTransparency=1})
local introCaption=make("TextLabel",introCard,{Text="PREPARING YOUR ATMOSPHERE",Position=UDim2.fromOffset(0,65),Size=UDim2.new(1,0,0,18),
    Font=Enum.Font.Gotham,TextSize=10,TextColor3=RGB(146,156,173),BackgroundTransparency=1})
local track=make("Frame",introCard,{Position=UDim2.new(0,3,0,108),Size=UDim2.new(1,-6,0,5),BackgroundColor3=RGB( 30,34,41),BorderSizePixel=0});round(track,4)
local bar=make("Frame",track,{Size=UDim2.fromScale(0,1),BackgroundColor3=RGB(238,244,255),BorderSizePixel=0});round(bar,4)
make("UIStroke",bar,{Color=RGB(224,237,255),Thickness=3,Transparency=.85})
local percent=make("TextLabel",introCard,{Text="0%",Position=UDim2.fromOffset(0,128),Size=UDim2.new(1,0,0,20),
    Font=Enum.Font.GothamMedium,TextSize=13,TextColor3=RGB(222,230,242),BackgroundTransparency=1})
local warp=make("Frame",loading,{Size=UDim2.fromScale(1,1),BackgroundTransparency=1,Visible=false})
local warpRng=Random.new(618)
for i=1,180 do
    local star=make("Frame",warp,{AnchorPoint=Vector2.new(.5,.5),BorderSizePixel=0,BackgroundColor3=RGB(230,240,255),BackgroundTransparency=1})
    ui.stars[i]={object=star,angle=warpRng:NextNumber(0,math.pi*2),depth=warpRng:NextNumber(.12,5),spread=warpRng:NextNumber(.1,1),width=warpRng:NextNumber(.8,2.1)}
end
for i=1,7 do
    local ring=make("Frame",warp,{AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(.5,.5),BackgroundTransparency=1})
    round(ring,10000)
    local edge=make("UIStroke",ring,{Color=RGB(183,209,244),Thickness=1.3,Transparency=.8})
    ui.rings[i]={object=ring,edge=edge,offset=i/7}
end
local warpGlow=make("Frame",warp,{Size=UDim2.fromScale(1,1),BackgroundColor3=RGB(225,238,255),BackgroundTransparency=1,BorderSizePixel=0})

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

-- Override only these classic profiles; BASE, Rain and Snowfall remain untouched.
profiles.Noon=profile({
    L={ClockTime=13.2,Brightness=2.8,ExposureCompensation=.08,Ambient=RGB(57,63,72),
        OutdoorAmbient=RGB(133,145,159),ShadowSoftness=.34,ColorShift_Top=RGB(8,5,1)},
    A={Density=.265,Offset=.12,Haze=1.25,Glare=.20,Color=RGB(216,231,246),Decay=RGB(148,157,176)},
    C={Cover=.36,Density=.49,Color=RGB(249,248,246)},
    CC={Brightness=.005,Contrast=.085,Saturation=.025,TintColor=RGB(255,252,247)},
    B={Intensity=.14,Size=36,Threshold=1.3},R={Intensity=.045,Spread=.78},K={SunAngularSize=10},
})
profiles.Sunrise=profile({
    L={ClockTime=6.48,Brightness=2.35,ExposureCompensation=.10,Ambient=RGB( 70, 67,87),
        OutdoorAmbient=RGB(146,137,157),ShadowSoftness=.42,ColorShift_Top=RGB(35,18,9)},
    A={Density=.32,Offset=.08,Haze=2.0,Glare=.40,Color=RGB(244,214,202),Decay=RGB(151,141,177)},
    C={Cover=.34,Density=.49,Color=RGB(255,220,199)},
    CC={Brightness=.01,Contrast=.08,Saturation=.07,TintColor=RGB(255,239,229)},
    B={Intensity=.21,Size=42,Threshold=1.2},R={Intensity=.065,Spread=.83},K={SunAngularSize=12,StarCount=0},
})
profiles.Sunset=profile({
    L={ClockTime=17.65,Brightness=2.25,ExposureCompensation=.025,Ambient=RGB( 70,58,69),
        OutdoorAmbient=RGB(141,107,99),ShadowSoftness=.43,ColorShift_Top=RGB(48, 24,7)},
    A={Density=.34,Offset=.09,Haze=2.4,Glare=.62,Color=RGB(255,211,162),Decay=RGB(177,116,111)},
    C={Cover=.31,Density=.47,Color=RGB(249,174,125)},
    CC={Contrast=.12,Saturation=.085,TintColor=RGB(255,236,216)},
    B={Intensity=.23,Size=42,Threshold=1.18},R={Intensity=.08,Spread=.85},K={SunAngularSize=13,StarCount=0},
})
profiles.Night=profile({
    L={ClockTime=23,Brightness=1.05,ExposureCompensation=.025,Ambient=RGB( 32,38,49),
        OutdoorAmbient=RGB(70,83,104),ColorShift_Top=RGB(0,0,5),ShadowSoftness=.38},
    A={Density=.19,Offset=.14,Haze=.75,Glare=0,Color=RGB(137,162,191),Decay=RGB(40,55,80)},
    C={Cover=.17,Density=.30,Color=RGB( 80,94,114)},
    CC={Contrast=.12,Saturation=-.04,TintColor=RGB(230,240,255)},
    B={Intensity=.19,Size=33,Threshold=1.3},R={Intensity=0},K={MoonAngularSize=9,StarCount=3500},
})
profiles["Meteor Shower"]=profile({
    L={ClockTime=21.8,Brightness=1.35,ExposureCompensation=.06,Ambient=RGB(43,39,43),
        OutdoorAmbient=RGB(91,86, 90),ColorShift_Top=RGB(9,5,2),ShadowSoftness=.36},
    A={Density=.12,Offset=.12,Haze=.4,Glare=0,Color=RGB(162,156,167),Decay=RGB(54,57, 70)},
    C={Cover=.12,Density=.25,Color=RGB(104,103,118)},
    CC={Contrast=.14,Saturation=.03,TintColor=RGB(255,244,235)},
    B={Intensity=.38,Size=40,Threshold=1.1},R={Intensity=0},K={StarCount=0,MoonAngularSize=0,SunAngularSize=0},
})
profiles.Starfall=profile({
    L={ClockTime=23.2,Brightness=1.3,ExposureCompensation=.06,Ambient=RGB(35,41,55),
        OutdoorAmbient=RGB( 80,92,114),ColorShift_Top=RGB(0,2,7),ShadowSoftness=.34},
    A={Density=.10,Offset=.12,Haze=.25,Glare=0,Color=RGB(148,167,197),Decay=RGB(39,49,71)},
    C={Cover=.06,Density=.17,Color=RGB(78,91,113)},
    CC={Contrast=.13,Saturation=.015,TintColor=RGB(234,243,255)},
    B={Intensity=.42,Size=40,Threshold=1.08},R={Intensity=0},K={StarCount=0,MoonAngularSize=0,SunAngularSize=0},
})
profiles["Aurora Sky"]=profile({
    L={ClockTime=23.4,Brightness=1.25,ExposureCompensation=.05,Ambient=RGB(32,45,50),
        OutdoorAmbient=RGB(76,103,112),ColorShift_Top=RGB(0,8,7),ShadowSoftness=.4},
    A={Density=.065,Offset=.12,Haze=.17,Glare=0,Color=RGB(141,183,191),Decay=RGB(39,58,77)},
    C={Cover=.03,Density=.12,Color=RGB(87,106,121)},
    CC={Contrast=.11,Saturation=.045,TintColor=RGB(233,253,250)},
    B={Intensity=.38,Size= 44,Threshold=1.12},R={Intensity=0},K={StarCount=0,MoonAngularSize=0,SunAngularSize=0},
})
profiles["Deep Space"]=profile({
    L={ClockTime=0,Brightness=1.25,ExposureCompensation=.08,Ambient=RGB( 35,39,48),
        OutdoorAmbient=RGB(81,88,103),ColorShift_Top=RGB(0,0,0),ShadowSoftness=.36},
    A={Density=0,Offset=0,Haze=0,Glare=0,Color=RGB(255,255,255),Decay=RGB(0,0,0)},
    C={Cover=0,Density=0,Color=RGB(0,0,0)},
    CC={Contrast=.15,Saturation=.025,TintColor=RGB(248,250,255)},
    B={Intensity=.28,Size= 40,Threshold=1.18},R={Intensity=0},K={StarCount=0,MoonAngularSize=0,SunAngularSize=0},
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

-- Fixed, full-detail special effects. Legacy quality values below are used only by
-- the protected v2 Rain/Snowfall pools, whose code and settings are unchanged.
local function qualityCount(low,balanced,high)
    return S.quality=="High" and high or S.quality=="Balanced" and balanced or low
end
local special
local specialNames={["Meteor Shower"]=true,Starfall=true,["Aurora Sky"]=true,["Deep Space"]=true}
local skyFaces={SkyboxFt="sky_ft",SkyboxBk="sky_bk",SkyboxRt="sky_rt",SkyboxLf="sky_lf",SkyboxUp="sky_up",SkyboxDn="sky_dn"}
local sparkleTexture="rbxasset://textures/particles/sparkles_main.dds"
local smokeTexture="rbxasset://textures/particles/smoke_main.dds"
local function attachment(parent,position)
    return make("Attachment",parent,{Position=position or Vector3.new()})
end
local function luminousBeam(parent,a,b,width,colors,alpha)
    return make("Beam",parent,{Attachment0=a,Attachment1=b,FaceCamera=true,Segments=12,
        Width0=width,Width1=width,Color=colors,LightEmission=1,LightInfluence=0,
        Transparency=alpha or NumberSequence.new(.1)})
end
local function skyCard(name,offset,width,height,texture,opacity)
    local att=attachment(special.anchor,offset)
    local card=make("BillboardGui",att,{Name=name,Adornee=att,Size=UDim2.fromScale(width,height),
        AlwaysOnTop=false,LightInfluence=0,MaxDistance=0})
    local pic=make("ImageLabel",card,{Size=UDim2.fromScale(1,1),BackgroundTransparency=1,
        Image=ASSETS.ready[texture] or "",ImageTransparency=1,ScaleType=Enum.ScaleType.Fit})
    local entry={object=pic,key=texture,base=opacity or 0,card=card}
    table.insert(special.images,entry)
    return entry
end
local function ensureSky()
    if not special or not objects.K then return end
    local complete=true
    for _,name in pairs(skyFaces) do if not ASSETS.ready[name] then complete=false end end
    local tag=complete and "stars" or ASSETS.ready.black and "black" or "fallback"
    if special.skyTag==tag then return end
    special.skyTag=tag
    if tag~="fallback" then
        for property,name in pairs(skyFaces) do objects.K[property]=complete and ASSETS.ready[name] or ASSETS.ready.black end
    end
    objects.K.CelestialBodiesShown=false
    if special.shell then
        for _,face in ipairs(special.shell) do face.part.Transparency=tag=="fallback" and 0 or 1 end
    end
end
local function makeFallbackSky()
    special.shell={}
    -- Geometry fallback for environments without custom PNG support. Mesh scale
    -- avoids the BasePart size limit; the faces are behind every scene effect.
    for _,spec in ipairs({
        {Vector3.new(0,0,-14000),Vector3.new(30,30,.002)},
        {Vector3.new(0,0,14000),Vector3.new(30,30,.002)},
        {Vector3.new(14000,0,0),Vector3.new(.002,30,30)},
        {Vector3.new(-14000,0,0),Vector3.new(.002,30,30)},
        {Vector3.new(0,14000,0),Vector3.new(30,.002,30)},
        {Vector3.new(0,-14000,0),Vector3.new(30,.002,30)},
    }) do
        local p=visualPart("SCBlackBackdrop");p.Size=Vector3.new(1000,1000,1000)
        p.Color=RGB(0,0,0);p.Material=Enum.Material.Neon;p.Transparency=0
        make("SpecialMesh",p,{MeshType=Enum.MeshType.Brick,Scale=spec[2]})
        table.insert(special.shell,{part=p,offset=spec[1]})
    end
end
local function buildEventPool(name)
    special.projectiles={};special.impacts={};special.spawn=1
    special.meteor=name=="Meteor Shower"
    for i=1,22 do
        local p=visualPart(special.meteor and "SCMeteor" or "SCFallingStar")
        p.Shape=Enum.PartType.Ball;p.Size=Vector3.new(1,1,1);p.Material=Enum.Material.Neon
        p.Color=RGB(255,251,240)
        local head=attachment(p)
        local tail=attachment(p,Vector3.new(0,0,50))
        local colors=ColorSequence.new(RGB(255,255,255),special.meteor and RGB(255,198,112) or RGB(189,217,255))
        local core=luminousBeam(p,head,tail,1.4,colors,NumberSequence.new({
            NumberSequenceKeypoint.new(0,0),NumberSequenceKeypoint.new(.48,.15),NumberSequenceKeypoint.new(1,1)}))
        core.Width1=.02
        local halo=luminousBeam(p,head,tail,5.5,colors,NumberSequence.new({
            NumberSequenceKeypoint.new(0,.73),NumberSequenceKeypoint.new(.5,.86),NumberSequenceKeypoint.new(1,1)}))
        halo.Width1=.15
        local left=attachment(p,Vector3.new(-.35,0,0));local right=attachment(p,Vector3.new(.35,0,0))
        local trail=make("Trail",p,{Attachment0=left,Attachment1=right,Lifetime=.65,
            FaceCamera=true,MinLength=.1,LightEmission=1,LightInfluence=0,Color=colors,
            WidthScale=NumberSequence.new({NumberSequenceKeypoint.new(0,1),NumberSequenceKeypoint.new(1,0)}),
            Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,.2),NumberSequenceKeypoint.new(1,1)}),Enabled=false})
        local fire=make("ParticleEmitter",p,{Texture=sparkleTexture,Color=colors,Rate=18,Lifetime=NumberRange.new(.15,.4),
            Speed=NumberRange.new(2,6),SpreadAngle=Vector2.new(35,35),LightEmission=1,LightInfluence=0,
            Size=NumberSequence.new({NumberSequenceKeypoint.new(0,.65),NumberSequenceKeypoint.new(1,0)}),
            Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,.15),NumberSequenceKeypoint.new(1,1)}),Enabled=false})
        local light=make("PointLight",p,{Range=24,Brightness=0,Color=RGB(255,244,220),Shadows=false})
        local glow=make("BillboardGui",head,{Adornee=head,AlwaysOnTop=false,LightInfluence=0,Size=UDim2.fromScale(11,11),Enabled=false})
        make("ImageLabel",glow,{Size=UDim2.fromScale(1,1),BackgroundTransparency=1,Image=sparkleTexture,ImageColor3=RGB(255,249,239)})
        core.Enabled=false;halo.Enabled=false
        table.insert(special.projectiles,{part=p,tail=tail,core=core,halo=halo,trail=trail,fire=fire,light=light,glow=glow,active=false})
    end
    for i=1,10 do
        local p=visualPart("SCImpactGlow")
        local emitter=make("ParticleEmitter",p,{Texture=sparkleTexture,Rate=0,Lifetime=NumberRange.new(.2,.7),Speed=NumberRange.new(7,22),
            SpreadAngle=Vector2.new( 70,70),Acceleration=Vector3.new(0,-20,0),LightEmission=1,LightInfluence=0,
            Size=NumberSequence.new({NumberSequenceKeypoint.new(0,.5),NumberSequenceKeypoint.new(1,0)}),
            Color=ColorSequence.new(RGB(255,255,255),special.meteor and RGB(255,181,81) or RGB(145,194,255)),
            Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,.1),NumberSequenceKeypoint.new(1,1)})})
        local glow=make("BillboardGui",p,{Adornee=p,AlwaysOnTop=false,LightInfluence=0,Size=UDim2.fromScale(1,1),Enabled=false})
        local image=make("ImageLabel",glow,{Size=UDim2.fromScale(1,1),BackgroundTransparency=1,Image=sparkleTexture,ImageColor3=RGB(255,245,225)})
        local light=make("PointLight",p,{Range=24,Brightness=0,Color=RGB(255,239,216),Shadows=false})
        table.insert(special.impacts,{part=p,emitter=emitter,glow=glow,image=image,light=light,age=2})
    end
end
local function impactFlash(position)
    for _,item in ipairs(special.impacts) do
        if item.age>=.75 then
            item.part.Position=position+Vector3.new(0,.3,0);item.age=0;item.glow.Enabled=true
            item.emitter:Emit(special.meteor and 24 or 15)
            return
        end
    end
end
local function deactivate(item)
    item.active=false;item.part.Transparency=1;item.core.Enabled=false;item.halo.Enabled=false
    item.trail.Enabled=false;item.fire.Enabled=false;item.glow.Enabled=false;item.light.Brightness=0
end
local function spawnProjectile(item,camera)
    local center=weatherCenter()
    local angle=rng:NextNumber(0,math.pi*2)
    local radius=math.sqrt(rng:NextNumber())*430
    -- Every path starts inside the requested 450-stud footprint, in world space.
    item.position=center+Vector3.new(math.cos(angle)*radius,rng:NextNumber(145,295),math.sin(angle)*radius)
    item.velocity=Vector3.new(rng:NextNumber(-20,20),special.meteor and -65 or -110,rng:NextNumber(-20,20))
    item.age=0;item.active=true
    item.part.CFrame=CFrame.lookAt(item.position,item.position+item.velocity)
    local diameter=special.meteor and rng:NextNumber(.9,1.65) or rng:NextNumber(.45,.8)
    item.part.Size=Vector3.new(diameter,diameter,diameter)
    item.trail:Clear();item.fire:Clear()
    item.core.Enabled=true;item.halo.Enabled=true;item.trail.Enabled=true;item.fire.Enabled=true;item.glow.Enabled=true
end
local function buildAurora()
    special.curtains={}
    local count=52
    for band=1,3 do
        for i=0,count-1 do
            local angle=(i/(count-1)*2.22)+(band-1)*math.pi*2/3-math.pi/3
            local bottom=attachment(special.anchor)
            local top=attachment(special.anchor)
            local tint=ColorSequence.new({ColorSequenceKeypoint.new(0,RGB(137,255,188)),
                ColorSequenceKeypoint.new(.42,RGB(58,234,172)),ColorSequenceKeypoint.new(.77,RGB(98,139,225)),
                ColorSequenceKeypoint.new(1,RGB(191,99,220))})
            local ribbon=luminousBeam(special.anchor,bottom,top,100,tint,
                NumberSequence.new({NumberSequenceKeypoint.new(0,1),NumberSequenceKeypoint.new(.13,.12),
                    NumberSequenceKeypoint.new(.50,.28),NumberSequenceKeypoint.new(.85,.75),NumberSequenceKeypoint.new(1,1)}))
            ribbon.Texture=ASSETS.ready.aurora_curtain or smokeTexture
            ribbon.TextureMode=Enum.TextureMode.Stretch;ribbon.TextureSpeed=.012
            ribbon.CurveSize0=24;ribbon.CurveSize1=-38;ribbon.Width1=135;ribbon.Segments=16
            table.insert(special.curtains,{bottom=bottom,top=top,beam=ribbon,angle=angle,band=band,index=i})
        end
    end
end
local function buildSpace()
    skyCard("SCTON618",Vector3.new(-1050,560,-6200),4200,2100,"ton618")
    skyCard("SCRingedPlanet",Vector3.new(2190,270,-7900),2400,1600,"ringed_planet")
    skyCard("SCIcePlanet",Vector3.new(-3300,200,-8500),1550,1550,"ice_planet")
    skyCard("SCDistantGalaxy",Vector3.new(1100,1950,-10800),5500,2750,"galaxy",.08)
    -- Dim, nearby motes add depth without pretending space itself is colored fog.
    local p=visualPart("SCCosmicDust");p.Size=Vector3.new(80,30,80)
    special.dust=p
    make("ParticleEmitter",p,{Texture=sparkleTexture,Rate=12,Lifetime=NumberRange.new(5,9),Speed=NumberRange.new(.1,.6),
        SpreadAngle=Vector2.new(180,180),LightEmission=.8,LightInfluence=0,
        Size=NumberSequence.new(.025),Color=ColorSequence.new(RGB(185,200,224)),
        Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,1),NumberSequenceKeypoint.new(.3,.65),NumberSequenceKeypoint.new(1,1)})})
end
clearSpecials=function()
    if special and special.skySaved and objects.K then
        for property,value in pairs(special.skySaved) do pcall(function() objects.K[property]=value end) end
    end
    special=nil
end
initSpecials=function(name)
    if not specialNames[name] then return end
    local camera=workspace.CurrentCamera
    local look=camera and camera.CFrame.LookVector or Vector3.new(0,0,-1)
    local horizontal=Vector3.new(look.X,0,look.Z)
    if horizontal.Magnitude<.01 then horizontal=Vector3.new(0,0,-1) end
    special={name=name,time=0,clock=1,filter=0,images={},orientation=CFrame.lookAt(Vector3.new(),horizontal.Unit),skySaved={}}
    special.anchor=visualPart("SCCelestialAnchor")
    if objects.K then
        for property in pairs(skyFaces) do special.skySaved[property]=objects.K[property] end
        special.skySaved.CelestialBodiesShown=objects.K.CelestialBodiesShown
    end
    if not ASSETS.ready.black then makeFallbackSky() end
    ensureSky()
    if name=="Meteor Shower" or name=="Starfall" then buildEventPool(name)
    elseif name=="Aurora Sky" then buildAurora()
    else buildSpace() end
end
updateSpecials=function(dt,camera)
    if not special then return end
    special.time=special.time+dt;special.clock=special.clock+dt;special.filter=special.filter+dt
    special.anchor.CFrame=CFrame.new(camera.CFrame.Position)*special.orientation
    if special.shell then
        for _,face in ipairs(special.shell) do face.part.Position=camera.CFrame.Position+face.offset end
    end
    if special.dust then special.dust.Position=camera.CFrame.Position+Vector3.new(0,8,0) end
    if special.filter>.4 then special.filter=0;refreshFilter();ensureSky() end
    if special.projectiles then
        local center=weatherCenter()
        special.spawn=math.min(3,special.spawn+dt*(special.meteor and 3.3 or 4.1))
        for _,item in ipairs(special.projectiles) do
            if not item.active and special.spawn>=1 then
                special.spawn=special.spawn-1;spawnProjectile(item,camera)
            end
            if item.active then
                item.age=item.age+dt
                item.velocity=item.velocity+Vector3.new(0,special.meteor and -80*dt or -40*dt,0)
                local nextPosition=item.position+item.velocity*dt
                local hit=workspace:Raycast(item.position,nextPosition-item.position,params)
                local flat=Vector3.new(nextPosition.X-center.X,0,nextPosition.Z-center.Z)
                if hit then impactFlash(hit.Position);deactivate(item)
                elseif flat.Magnitude>450 or nextPosition.Y<center.Y-100 or item.age>6 then deactivate(item)
                else
                    item.position=nextPosition
                    item.part.CFrame=CFrame.lookAt(nextPosition,nextPosition+item.velocity)
                    local strength=S.intensity*math.min(1,item.age*7)
                    item.part.Transparency=1-strength
                    item.tail.Position=Vector3.new(0,0,math.min(90,30+item.velocity.Magnitude*.22))
                    item.core.Width0=(special.meteor and 1.35 or .85)*strength
                    item.halo.Width0=(special.meteor and 6.5 or 4.3)*strength
                    item.glow.Size=UDim2.fromScale((special.meteor and 12 or 8)*strength,(special.meteor and 12 or 8)*strength)
                    item.light.Brightness=(nextPosition-camera.CFrame.Position).Magnitude<130 and 2.6*strength or 0
                end
            end
        end
        for _,item in ipairs(special.impacts) do
            if item.age<.75 then
                item.age=item.age+dt
                local alpha=math.clamp(item.age/.75,0,1)
                item.glow.Size=UDim2.fromScale(3+alpha*18,3+alpha*18)
                item.image.ImageTransparency=alpha
                item.light.Brightness=(1-alpha)^2*4.5
                if alpha>=1 then item.glow.Enabled=false;item.light.Brightness=0 end
            end
        end
    end
    if special.clock<1/30 then return end
    special.clock=0
    for _,entry in ipairs(special.images) do
        local image=ASSETS.ready[entry.key]
        if image and entry.object.Image~=image then entry.object.Image=image end
        local shimmer=entry.key=="ton618" and (.985+.015*math.sin(special.time*.7)) or 1
        entry.object.ImageTransparency=1-(1-entry.base)*S.intensity*shimmer
    end
    if special.curtains then
        local t=special.time*.24
        for _,item in ipairs(special.curtains) do
            local angle=item.angle
            local wave=math.sin(angle*4+t+item.band)*43+math.cos(angle*9-t*.7)*13
            local radius=1600+item.band*80
            local bottom=Vector3.new(math.sin(angle)*radius,140+wave,-math.cos(angle)*radius)
            item.bottom.Position=bottom
            item.top.Position=bottom+Vector3.new(math.sin(t+angle*3)*90,540+math.sin(angle*5+t)*130,45)
            item.beam.Width0=100*S.intensity*(.92+.08*math.sin(t*2+item.index*.3))
            item.beam.Width1=135*S.intensity
            item.beam.CurveSize0=35*math.sin(t+angle*3)
            if ASSETS.ready.aurora_curtain then item.beam.Texture=ASSETS.ready.aurora_curtain end
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
        heading.Text = "S&NC Shaders"
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
    heading.Text = "S&NC Shaders"

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
local minimized=false
local launcherPlaced=false
local function boundedPanel(x,y)
    local size=surface.AbsoluteSize
    return UDim2.fromOffset(math.clamp(x,6,math.max(6,size.X-ui.width*scale.Scale-6)),
        math.clamp(y,6,math.max(6,size.Y-panelHeight*scale.Scale-6)))
end
local function clampPanel(x,y) panel.Position=boundedPanel(x,y) end
local function clampLauncher(x,y)
    local size=surface.AbsoluteSize
    launcher.Position=UDim2.fromOffset(math.clamp(x,6,math.max(6,size.X-64)),math.clamp(y,6,math.max(6,size.Y-64)))
end
local function resize(center,animated)
    local size=surface.AbsoluteSize
    if size.X<1 or size.Y<1 then return end
    ui.width=ui.expanded and math.min(620,math.max(368,size.X-24)) or 368
    scale.Scale=math.max(.2,math.min(1,(size.X-20)/ui.width))
    panelHeight=math.clamp((size.Y-20)/scale.Scale,240,540)
    ui.height=panelHeight
    local position=center and boundedPanel((size.X-ui.width*scale.Scale)/2,(size.Y-panelHeight*scale.Scale)/2)
        or boundedPanel(panel.Position.X.Offset,panel.Position.Y.Offset)
    if not minimized then
        if animated then animate(panel,.42,{Size=UDim2.fromOffset(ui.width,panelHeight),Position=position})
        else panel.Size=UDim2.fromOffset(ui.width,panelHeight);panel.Position=position end
    end
    clampLauncher(launcher.Position.X.Offset,launcher.Position.Y.Offset)
end
local function revealPanel()
    if S.dead then return end
    minimized=false;panel.Visible=true;launcher.Visible=false
    resize(not ui.openPosition,false)
    if ui.openPosition then panel.Position=boundedPanel(ui.openPosition.X.Offset,ui.openPosition.Y.Offset) end
    local target=panel.Position
    panel.Size=UDim2.fromOffset(54,panelHeight)
    panel.Position=UDim2.fromOffset(target.X.Offset+(ui.width-54)*scale.Scale*.5,target.Y.Offset)
    panel.GroupTransparency=1
    animate(panel,.48,{Size=UDim2.fromOffset(ui.width,panelHeight),Position=target,GroupTransparency=0})
end
local function toggleMinimize()
    if ui.phase~="ready" or ui.closing then return end
    ui.ticket=ui.ticket+1
    local ticket=ui.ticket
    if minimized then
        animate(launcherScale,.13,{Scale=.72})
        task.delay(.12,function()
            if S.dead or ticket~=ui.ticket then return end
            revealPanel();launcherScale.Scale=1
        end)
    else
        minimized=true
        ui.openPosition=panel.Position
        if not launcherPlaced then clampLauncher(panel.Position.X.Offset,panel.Position.Y.Offset);launcherPlaced=true end
        animate(panel,.28,{Size=UDim2.fromOffset(58,58),Position=launcher.Position,GroupTransparency=1})
        task.delay(.28,function()
            if S.dead or ticket~=ui.ticket then return end
            panel.Visible=false;launcher.Visible=true;launcherScale.Scale=.65
            animate(launcherScale,.35,{Scale=1},Enum.EasingStyle.Back)
        end)
    end
end
local function closeAnimated()
    if ui.closing or S.dead then return end
    ui.closing=true;ui.ticket=ui.ticket+1
    cleanup()
    local x=panel.Position.X.Offset+(ui.width-46)*scale.Scale*.5
    animate(panel,.32,{Size=UDim2.fromOffset(46,panelHeight),Position=UDim2.fromOffset(x,panel.Position.Y.Offset),GroupTransparency=1})
    animate(launcherScale,.25,{Scale=.1})
    task.delay(.34,function() if not S.dead then gui:Destroy() end end)
end
local function draggable(handle,target,isLauncher,onTap)
    local held,startPoint,startPosition,moved
    connect(handle.InputBegan,function(input)
        if held or ui.closing or ui.phase~="ready" then return end
        if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then
            held=input;startPoint=input.Position;startPosition=target.Position;moved=false
        end
    end)
    connect(UIS.InputChanged,function(input)
        if not held then return end
        if input==held or (held.UserInputType==Enum.UserInputType.MouseButton1 and input.UserInputType==Enum.UserInputType.MouseMovement) then
            local delta=input.Position-startPoint
            if delta.Magnitude>6 then moved=true end
            if moved then
                local x,y=startPosition.X.Offset+delta.X,startPosition.Y.Offset+delta.Y
                local goal
                if isLauncher then
                    local size=surface.AbsoluteSize
                    goal=UDim2.fromOffset(math.clamp(x,6,math.max(6,size.X-64)),math.clamp(y,6,math.max(6,size.Y-64)))
                else goal=boundedPanel(x,y) end
                ui.dragTarget={object=target,goal=goal,held=true}
            end
        end
    end)
    connect(UIS.InputEnded,function(input)
        if input~=held then return end
        held=nil
        if ui.dragTarget then ui.dragTarget.held=false end
        if onTap and not moved then onTap() end
    end)
    connect(UIS.WindowFocusReleased,function()
        held=nil;if ui.dragTarget then ui.dragTarget.held=false end
    end)
end
draggable(heading,panel,false)
draggable(brand,panel,false)
draggable(launcher,launcher,true,function() if minimized then toggleMinimize() end end)
connect(mini.Activated,toggleMinimize)
connect(close.Activated,closeAnimated)
connect(expandButton.Activated,function()
    if ui.closing or ui.phase~="ready" or minimized then return end
    ui.expanded=not ui.expanded;resize(false,true)
end)
connect(surface:GetPropertyChangedSignal("AbsoluteSize"),function() resize(false,false) end)

local function stepInterface(dt)
    if S.dead then return end
    ui.elapsed=ui.elapsed+dt
    if ui.dragTarget then
        local drag=ui.dragTarget
        local current=drag.object.Position
        local dx=drag.goal.X.Offset-current.X.Offset
        local dy=drag.goal.Y.Offset-current.Y.Offset
        local a=1-math.exp(-math.min(dt,.15)*22)
        drag.object.Position=UDim2.fromOffset(current.X.Offset+dx*a,current.Y.Offset+dy*a)
        if math.abs(dx)+math.abs(dy)<.3 and not drag.held then ui.dragTarget=nil end
    end
    if ui.phase=="loading" then
        local timeProgress=math.clamp(ui.elapsed/4.2,0,1)
        local assetProgress=ASSETS.completed/ASSETS.total
        local target=math.min(.985,timeProgress*.55+assetProgress*.45)
        ui.progress=ui.progress+(target-ui.progress)*(1-math.exp(-dt*7))
        bar.Size=UDim2.fromScale(ui.progress,1)
        percent.Text=tostring(math.floor(ui.progress*100)).."%"
        if ui.elapsed>=4.2 and (ASSETS.completed>=ASSETS.total or ui.elapsed>=12) then
            ui.phase="warp";ui.warpTime=0;ui.progress=1
            bar.Size=UDim2.fromScale(1,1);percent.Text="100%"
            introCaption.Text="ENTERING ANOTHER DIMENSION"
            warp.Visible=true
            animate(introCard,.65,{GroupTransparency=1,Position=UDim2.fromScale(.5,.49)})
        end
    elseif ui.phase=="warp" then
        ui.warpTime=ui.warpTime+dt
        local t=math.clamp(ui.warpTime/5,0,1)
        local size=surface.AbsoluteSize
        local focal=math.max(size.X,size.Y)*.40
        local intensity=math.min(1,ui.warpTime*2,(5-ui.warpTime)*1.5)
        local speed=1.4+math.sin(t*math.pi)*4.5
        for _,star in ipairs(ui.stars) do
            star.depth=star.depth-dt*speed
            if star.depth<.12 then star.depth=star.depth+5 end
            local radius=focal*star.spread/star.depth
            local px=math.cos(star.angle)*radius;local py=math.sin(star.angle)*radius*.75
            local visible=math.abs(px)<size.X*.75 and math.abs(py)<size.Y*.75
            local object=star.object
            object.Visible=visible
            if visible then
                local length=math.clamp(speed*13/(star.depth*star.depth),2,size.X*.25)
                object.Position=UDim2.fromOffset(size.X*.5+px,size.Y*.5+py)
                object.Size=UDim2.fromOffset(length,star.width)
                object.Rotation=math.deg(math.atan2(py,px))
                object.BackgroundTransparency=1-math.clamp(intensity*(.8-star.depth*.10),0,1)
            end
        end
        for _,ring in ipairs(ui.rings) do
            local phase=(t*2.8+ring.offset)%1
            local width=(.06+phase^2*2.3)*math.max(size.X,size.Y)
            ring.object.Size=UDim2.fromOffset(width,width*.62)
            ring.edge.Transparency=1-.24*intensity*math.sin(phase*math.pi)
        end
        warpGlow.BackgroundTransparency=1-.055*math.sin(t*math.pi)^4
        if ui.warpTime>=5 then
            ui.phase="exit";ui.exitTime=0
            animate(loading,.65,{GroupTransparency=1})
        end
    elseif ui.phase=="exit" then
        ui.exitTime=ui.exitTime+dt
        if ui.exitTime>=.65 then
            ui.phase="ready"
            loading:Destroy()
            table.clear(ui.stars);table.clear(ui.rings)
            revealPanel()
        end
    end
end
connect(RunService.RenderStepped,function(dt)
    local ok,err=pcall(stepInterface,dt)
    if not ok and not S.dead then
        -- A UI animation failure cannot keep the controls permanently hidden.
        if loading.Parent then loading:Destroy() end
        ui.phase="ready";table.clear(ui.stars);table.clear(ui.rings)
        panel.Visible=true;panel.GroupTransparency=0;resize(true,false)
        warn("[S&NC Shaders/interface] "..tostring(err))
    end
end)
refreshUI()
task.defer(function()
    if S.dead then return end
    resize(true,false)
    animate(loading,.6,{GroupTransparency=0})
    animate(introCard,.8,{Position=UDim2.fromScale(.5,.49)})
    ASSETS.Start()
end)


-- Optional controller for hub/Studio integration. Execution still opens the UI.
return {
    Version="3.0.0",
    SetMode=function(name) if not S.dead then setMode(name) end;return S.active==name end,
    Default=defaultMode,
    Destroy=function() if not S.dead then gui:Destroy() end end,
    Show=function() if not S.dead and minimized then toggleMinimize() end end,
    SetSound=setSound,
    SetAutoWeather=function(enabled) S.autoWeather=enabled==true;S.chance=0;refreshUI() end,
    GetState=function() return {Mode=S.active,RealTime=S.real,Loading=ui.phase~="ready",
        Sound=S.sound,Volume=S.volume,AudioStatus=S.audioStatus,Destroyed=S.dead} end,
}
