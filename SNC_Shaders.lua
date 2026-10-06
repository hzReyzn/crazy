-- S&NC Shaders 4.0 | standalone + HzReyzn Hub compatibility
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
local teardownUI = function() end

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
    Name = "SNCShaders",
    ResetOnSpawn = false,
    DisplayOrder = 45,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
})

connect(gui.Destroying, function()
    if S.dead then return end
    S.dead = true
    teardownUI()

    for _, c in ipairs(connections) do
        c:Disconnect()
    end

    cleanup()
    folder:Destroy()
end)

-- Native UI only: no loading screen, downloaded images or startup delay.
local ui={width=368,height=476,expanded=false,ticket=0,closing=false,busy=false,
    dragTarget=nil,tweens={},buttonState={},feedback={},fxClock=0}
local surface=make("Frame",gui,{Size=UDim2.fromScale(1,1),BackgroundTransparency=1})
local lensLayer=make("Frame",surface,{Size=UDim2.fromScale(1,1),BackgroundTransparency=1,ClipsDescendants=true})
local panel=make("CanvasGroup",surface,{Name="SCPanel",Size=UDim2.fromOffset(368,476),
    BackgroundColor3=RGB(2,2,3),BackgroundTransparency=0,BorderSizePixel=0,
    GroupTransparency=1,Visible=true,ZIndex=5,ClipsDescendants=true})
round(panel,18)
local scale=make("UIScale",panel,{Scale=1})
local panelHeight=476
local function animate(o,duration,props,style)
    local previous=ui.tweens[o]
    if previous then previous:Cancel() end
    local tween=TweenService:Create(o,TweenInfo.new(duration,style or Enum.EasingStyle.Quint,Enum.EasingDirection.Out),props)
    ui.tweens[o]=tween;tween:Play()
    return tween
end
local function cancelTween(o)
    local tween=ui.tweens[o]
    if tween then tween:Cancel();ui.tweens[o]=nil end
end
local function border(o)
    local edge=make("UIStroke",o,{Name="NeonBorder",ApplyStrokeMode=Enum.ApplyStrokeMode.Border,
        Thickness=1.5,Color=RGB(255,255,255),Transparency=.12})
    local gradient=make("UIGradient",edge,{Color=ColorSequence.new({
        ColorSequenceKeypoint.new(0,RGB(70,70,76)),ColorSequenceKeypoint.new(.43,RGB(255,255,255)),
        ColorSequenceKeypoint.new(.63,RGB(255,255,255)),ColorSequenceKeypoint.new(1,RGB(85,85,92))}),Rotation=25})
    return gradient
end
local panelGradient=border(panel)
local inner=make("Frame",panel,{Position=UDim2.fromOffset(4,4),Size=UDim2.new(1,-8,1,-8),
    BackgroundTransparency=1,BorderSizePixel=0})
round(inner,15)
make("UIStroke",inner,{Color=RGB(255,255,255),Thickness=1,Transparency=.90})
local topGlow=make("Frame",panel,{Position=UDim2.fromOffset(28,1),Size=UDim2.new(1,-56,0,2),
    BackgroundColor3=RGB(255,255,255),BorderSizePixel=0,BackgroundTransparency=.12})
make("UIGradient",topGlow,{Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,1),
    NumberSequenceKeypoint.new(.35,.05),NumberSequenceKeypoint.new(.65,.05),NumberSequenceKeypoint.new(1,1)})})
local function styleButton(o)
    local state=ui.buttonState[o]
    if not state or S.dead then return end
    local key=(state.selected and "1" or "0")..(state.hover and "1" or "0")
    if state.style==key then return end
    state.style=key
    animate(o,.22,{BackgroundColor3=state.selected and RGB(24,24,28) or state.hover and RGB(18,18,21) or RGB(8,8,10),
        TextColor3=state.selected and RGB(255,255,255) or RGB(218,218,225)})
    animate(state.edge,.24,{Transparency=state.selected and .08 or state.hover and .28 or .78,
        Thickness=state.selected and 1.5 or 1})
    if state.marker then animate(state.marker,.24,{BackgroundTransparency=state.selected and .04 or 1}) end
end
local function button(parent,text,x,y,w,h)
    local o=make("TextButton",parent,{Name=text,Text=text,Position=UDim2.fromOffset(x,y),Size=UDim2.fromOffset(w,h),
        BackgroundColor3=RGB(8,8,10),TextColor3=RGB(218,218,225),BorderSizePixel=0,
        Font=Enum.Font.GothamMedium,TextSize=13,AutoButtonColor=false,ClipsDescendants=true})
    round(o,11)
    local edge=make("UIStroke",o,{Name="OptionEdge",ApplyStrokeMode=Enum.ApplyStrokeMode.Border,
        Color=RGB(255,255,255),Transparency=.78,Thickness=1})
    local press=make("UIScale",o,{Scale=1})
    ui.buttonState[o]={edge=edge,press=press,selected=false,hover=false,held=false}
    connect(o.MouseEnter,function()
        if ui.closing then return end
        ui.buttonState[o].hover=true;styleButton(o)
    end)
    connect(o.MouseLeave,function()
        local state=ui.buttonState[o];state.hover=false;state.held=false;styleButton(o)
        animate(press,.23,{Scale=1})
    end)
    connect(o.InputBegan,function(input)
        if ui.closing then return end
        if input.UserInputType==Enum.UserInputType.Touch or input.UserInputType==Enum.UserInputType.MouseButton1 then
            ui.buttonState[o].held=true;animate(press,.11,{Scale=.965})
        end
    end)
    connect(o.InputEnded,function(input)
        if input.UserInputType==Enum.UserInputType.Touch or input.UserInputType==Enum.UserInputType.MouseButton1 then
            ui.buttonState[o].held=false;animate(press,.32,{Scale=1},Enum.EasingStyle.Back)
        end
    end)
    return o
end
local brand=make("Frame",panel,{Position=UDim2.fromOffset(15,15),Size=UDim2.fromOffset(34,34),
    BackgroundColor3=RGB(246,246,250),BorderSizePixel=0,Active=true});round(brand,10)
make("TextLabel",brand,{Size=UDim2.fromScale(1,1),BackgroundTransparency=1,Text="SC",
    Font=Enum.Font.GothamBold,TextSize=14,TextColor3=RGB(2,2,3)})
local heading=make("TextLabel",panel,{Text="S&NC Shaders",Position=UDim2.fromOffset(59,13),
    Size=UDim2.new(1,-193,0,23),BackgroundTransparency=1,Font=Enum.Font.GothamBold,
    TextSize=16,TextColor3=RGB(255,255,255),TextXAlignment=Enum.TextXAlignment.Left,Active=true})
make("TextLabel",panel,{Text="LIGHT  /  ATMOSPHERE",Position=UDim2.fromOffset(60,37),Size=UDim2.new(1,-193,0,13),
    BackgroundTransparency=1,Font=Enum.Font.Gotham,TextSize=8,TextColor3=RGB(130,130,141),TextXAlignment=Enum.TextXAlignment.Left})
local expandButton=button(panel,"↔",0,16,30,30);expandButton.Position=UDim2.new(1,-115,0,16)
local mini=button(panel,"−",0,16,30,30);mini.Position=UDim2.new(1,-79,0,16)
local close=button(panel,"×",0,16,30,30);close.Position=UDim2.new(1,-43,0,16);close.TextSize=20
local divider=make("Frame",panel,{Position=UDim2.fromOffset(17,64),Size=UDim2.new(1,-34,0,1),
    BackgroundColor3=RGB(255,255,255),BackgroundTransparency=.84,BorderSizePixel=0})
local dividerGradient=make("UIGradient",divider,{Transparency=NumberSequence.new({
    NumberSequenceKeypoint.new(0,1),NumberSequenceKeypoint.new(.5,0),NumberSequenceKeypoint.new(1,1)})})
local scroll=make("ScrollingFrame",panel,{Name="ShaderOptions",Position=UDim2.fromOffset(12,77),
    Size=UDim2.new(1,-24,1,-113),CanvasSize=UDim2.fromOffset(0,390),BackgroundTransparency=1,
    BorderSizePixel=0,ScrollBarThickness=2,ScrollBarImageColor3=RGB(245,245,255),ScrollingDirection=Enum.ScrollingDirection.Y})
make("TextLabel",scroll,{Text="CLASSIC ATMOSPHERES",Position=UDim2.fromOffset(6,0),Size=UDim2.new(1,-12,0,21),
    BackgroundTransparency=1,Font=Enum.Font.GothamBold,TextSize=10,TextColor3=RGB(149,149,160),TextXAlignment=Enum.TextXAlignment.Left})
local function halfButton(text,y,column,height)
    local o=button(scroll,text,0,y,100,height or 43)
    o.Position=UDim2.new(column*.5,5,0,y);o.Size=UDim2.new(.5,-10,0,height or 43)
    return o
end
local function fullButton(text,y)
    local o=button(scroll,text,5,y,100,35);o.Size=UDim2.new(1,-10,0,35);return o
end
local buttons={}
for i,name in ipairs({"Noon","Sunrise","Sunset","Night","Rain","Snowfall"}) do
    local b=halfButton(name,29+math.floor((i-1)/2)*51,(i-1)%2)
    buttons[name]=b
    local marker=make("Frame",b,{Position=UDim2.new(0,3,.5,-9),Size=UDim2.fromOffset(2,18),
        BackgroundColor3=RGB(255,255,255),BackgroundTransparency=1,BorderSizePixel=0});round(marker,2)
    ui.buttonState[b].marker=marker
    -- Reusable feedback: bright ripple, moving reflection and five short sparks.
    local layer=make("Frame",b,{Name="SCPressVFX",Size=UDim2.fromScale(1,1),BackgroundTransparency=1,
        ClipsDescendants=true,Visible=false,ZIndex=3});round(layer,11)
    local flash=make("Frame",layer,{Size=UDim2.fromScale(1,1),BackgroundColor3=RGB(255,255,255),
        BackgroundTransparency=1,BorderSizePixel=0});round(flash,11)
    local wave=make("Frame",layer,{AnchorPoint=Vector2.new(.5,.5),BackgroundColor3=RGB(255,255,255),
        BackgroundTransparency=.94,BorderSizePixel=0});round(wave,1000)
    local waveEdge=make("UIStroke",wave,{Color=RGB(255,255,255),Thickness=1.2,Transparency=.15})
    local sheen=make("Frame",layer,{Size=UDim2.fromScale(1,1),BackgroundColor3=RGB(255,255,255),
        BackgroundTransparency=.80,BorderSizePixel=0})
    local gradient=make("UIGradient",sheen,{Rotation=22,Offset=Vector2.new(-1.3,0),
        Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,1),NumberSequenceKeypoint.new(.40,1),
            NumberSequenceKeypoint.new(.50,.05),NumberSequenceKeypoint.new(.60,1),NumberSequenceKeypoint.new(1,1)})})
    local sparks={}
    for j=1,5 do
        local spark=make("Frame",layer,{AnchorPoint=Vector2.new(.5,.5),Size=UDim2.fromOffset(5,1),
            BackgroundColor3=RGB(255,255,255),BackgroundTransparency=1,BorderSizePixel=0,Rotation=(j-1)*72})
        sparks[j]={object=spark,angle=math.rad((j-1)*72)}
    end
    ui.feedback[b]={layer=layer,flash=flash,wave=wave,edge=waveEdge,gradient=gradient,sparks=sparks,age=1}
end
local realButton=fullButton("Real Time: OFF",186)
local randomButton=fullButton("Random weather: ON",228)
local soundButton=button(scroll,"Sound: ON",5,277,100,35);soundButton.Size=UDim2.new(.5,-10,0,35)
local quieter=button(scroll,"−",0,277,34,35);quieter.Position=UDim2.new(.5,5,0,277)
local volumeLabel=make("TextLabel",scroll,{Text="30%",Position=UDim2.new(.5,44,0,277),Size=UDim2.new(.5,-88,0,35),
    BackgroundTransparency=1,Font=Enum.Font.GothamMedium,TextSize=12,TextColor3=RGB(225,225,233)})
local louder=button(scroll,"+",0,277,34,35);louder.Position=UDim2.new(1,-39,0,277)
local backButton=halfButton("Restore shader",326,0,36)
local defaultButton=halfButton("Default",326,1,36)
make("TextLabel",scroll,{Text="Made by hzReyzn",Position=UDim2.fromOffset(5,370),Size=UDim2.new(1,-10,0,17),
    BackgroundTransparency=1,Font=Enum.Font.Gotham,TextSize=9,TextColor3=RGB(106,106,117)})
local status=make("TextLabel",panel,{Text="Choose an atmosphere",Position=UDim2.new(0,18,1,-27),Size=UDim2.new(1,-36,0,17),
    BackgroundTransparency=1,Font=Enum.Font.Gotham,TextSize=10,TextTruncate=Enum.TextTruncate.AtEnd,
    TextColor3=RGB(150,150,160),TextXAlignment=Enum.TextXAlignment.Left})
local launcher=button(surface,"SC",20,85,58,58)
launcher.Visible=false;launcher.ZIndex=6;launcher.TextSize=19
local launcherScale=launcher:FindFirstChildOfClass("UIScale")
local launcherGradient=border(launcher)
local function pressShader(b,input)
    if S.dead or ui.closing or ui.busy then return end
    local fx=ui.feedback[b]
    if not fx then return end
    local x,y=.5,.5
    local size=b.AbsoluteSize
    if input and (input.UserInputType==Enum.UserInputType.Touch or input.UserInputType==Enum.UserInputType.MouseButton1) then
        x=math.clamp((input.Position.X-b.AbsolutePosition.X)/math.max(1,size.X),0,1)
        y=math.clamp((input.Position.Y-b.AbsolutePosition.Y)/math.max(1,size.Y),0,1)
    end
    fx.age=0;fx.x=x;fx.y=y;fx.diameter=math.max(size.X,size.Y)*2.2/math.max(.2,scale.Scale)
    fx.layer.Visible=true;fx.wave.Position=UDim2.fromScale(x,y);fx.wave.Size=UDim2.fromOffset(2,2)
    fx.flash.BackgroundTransparency=.84;fx.gradient.Offset=Vector2.new(-1.3,0)
    ui.fxClock=0
    divider.BackgroundTransparency=.20
    animate(divider,.65,{BackgroundTransparency=.84})
    animate(ui.buttonState[b].press,.30,{Scale=1},Enum.EasingStyle.Back)
end
local function refreshUI()
    for name,b in pairs(buttons) do
        ui.buttonState[b].selected=name==S.active;styleButton(b)
    end
    realButton.Text=S.real and "Real Time: ON" or "Real Time: OFF"
    randomButton.Text=S.autoWeather and "Random weather: ON" or "Random weather: OFF"
    soundButton.Text=S.sound and "Sound: ON" or "Sound: OFF"
    volumeLabel.Text=tostring(math.floor(S.volume*100+.5)).."%"
    backButton.TextTransparency=S.previous and 0 or .55
    status.Text=S.error or (S.active and ((S.real and "Real Time" or S.active).."  •  "..S.audioStatus) or "Choose an atmosphere")
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

-- Preserve the original Rain/Snowfall pool settings.
local function qualityCount(low,balanced,high)
    return S.quality=="High" and high or S.quality=="Balanced" and balanced or low
end

-- Each ambience is an original, loopable soundscape synthesized for this release.
-- Roblox Sound IDs are also supported when custom local assets are unavailable.
local audioFiles={Rain="rain",Snowfall="snow"}
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
    connect(b.Activated, function(input)
        if ui.closing or ui.busy then return end
        pressShader(b,input)
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
end))
local minimized=false
local launcherPlaced=false
local function boundedPanel(x,y)
    local size=surface.AbsoluteSize
    return UDim2.fromOffset(math.clamp(x,6,math.max(6,size.X-ui.width*scale.Scale-6)),
        math.clamp(y,6,math.max(6,size.Y-panelHeight*scale.Scale-6)))
end
local function clampLauncher(x,y)
    local size=surface.AbsoluteSize
    launcher.Position=UDim2.fromOffset(math.clamp(x,6,math.max(6,size.X-64)),math.clamp(y,6,math.max(6,size.Y-64)))
end
local function finishMotion(duration,callback)
    ui.ticket=ui.ticket+1;ui.busy=true
    local ticket=ui.ticket
    task.delay(duration,function()
        if S.dead or ui.closing or ticket~=ui.ticket then return end
        ui.busy=false
        if callback then callback() end
    end)
end
local function resize(center,animated)
    local size=surface.AbsoluteSize
    if size.X<1 or size.Y<1 then return end
    ui.width=ui.expanded and math.min(600,math.max(368,size.X-24)) or 368
    scale.Scale=math.max(.2,math.min(1,(size.X-20)/ui.width))
    panelHeight=math.clamp((size.Y-20)/scale.Scale,240,476)
    ui.height=panelHeight
    local position=center and boundedPanel((size.X-ui.width*scale.Scale)/2,(size.Y-panelHeight*scale.Scale)/2)
        or boundedPanel(panel.Position.X.Offset,panel.Position.Y.Offset)
    if not minimized then
        cancelTween(panel)
        if animated then
            animate(panel,.38,{Size=UDim2.fromOffset(ui.width,panelHeight),Position=position,GroupTransparency=0})
            finishMotion(.39)
        else panel.Size=UDim2.fromOffset(ui.width,panelHeight);panel.Position=position;panel.GroupTransparency=0 end
    end
    clampLauncher(launcher.Position.X.Offset,launcher.Position.Y.Offset)
end
local function revealPanel(first)
    if S.dead or ui.closing then return end
    minimized=false;panel.Visible=true;launcher.Visible=false
    resize(first,false)
    if ui.openPosition then panel.Position=boundedPanel(ui.openPosition.X.Offset,ui.openPosition.Y.Offset) end
    local target=panel.Position
    panel.Size=UDim2.fromOffset(ui.width*.88,panelHeight*.97)
    panel.Position=UDim2.fromOffset(target.X.Offset+ui.width*.06*scale.Scale,target.Y.Offset+12)
    panel.GroupTransparency=1
    animate(panel,.42,{Size=UDim2.fromOffset(ui.width,panelHeight),Position=target,GroupTransparency=0})
    finishMotion(.43)
end
local function toggleMinimize()
    if ui.closing or ui.busy or S.dead then return end
    ui.dragTarget=nil;cancelTween(panel)
    if minimized then
        animate(launcherScale,.13,{Scale=.76})
        finishMotion(.14,function() launcherScale.Scale=1;revealPanel(false) end)
    else
        minimized=true;ui.openPosition=panel.Position
        if not launcherPlaced then clampLauncher(panel.Position.X.Offset,panel.Position.Y.Offset);launcherPlaced=true end
        animate(panel,.26,{Size=UDim2.fromOffset(58/scale.Scale,58/scale.Scale),Position=launcher.Position,GroupTransparency=1})
        finishMotion(.27,function()
            panel.Visible=false;launcher.Visible=true;launcherScale.Scale=.7
            animate(launcherScale,.32,{Scale=1},Enum.EasingStyle.Back)
        end)
    end
end
local function closeAnimated()
    if ui.closing or S.dead then return end
    ui.closing=true;ui.busy=true;ui.ticket=ui.ticket+1;ui.dragTarget=nil
    cleanup()
    local x=panel.Position.X.Offset+ui.width*.06*scale.Scale
    animate(panel,.30,{Size=UDim2.fromOffset(ui.width*.88,panelHeight*.96),
        Position=UDim2.fromOffset(x,panel.Position.Y.Offset+18),GroupTransparency=1})
    animate(launcherScale,.25,{Scale=.1})
    task.delay(.32,function() if not S.dead then gui:Destroy() end end)
end
local function draggable(handle,target,isLauncher,onTap)
    local held,startPoint,startPosition,moved
    connect(handle.InputBegan,function(input)
        if held or ui.closing or ui.busy then return end
        if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then
            held=input;startPoint=input.Position;startPosition=target.Position;moved=false
            cancelTween(target)
        end
    end)
    connect(UIS.InputChanged,function(input)
        if not held or ui.closing then return end
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
    if ui.closing or ui.busy or minimized then return end
    ui.dragTarget=nil;ui.expanded=not ui.expanded;resize(false,true)
end)
connect(surface:GetPropertyChangedSignal("AbsoluteSize"),function()
    if ui.closing then return end
    ui.dragTarget=nil;resize(false,false)
end)
connect(UIS.WindowFocusReleased,function()
    for _,state in pairs(ui.buttonState) do
        state.held=false;animate(state.press,.2,{Scale=1})
    end
end)
local function stepInterface(dt)
    if S.dead or ui.closing then return end
    dt=math.min(dt,.15)
    if ui.dragTarget then
        local drag=ui.dragTarget
        local current=drag.object.Position
        local dx=drag.goal.X.Offset-current.X.Offset
        local dy=drag.goal.Y.Offset-current.Y.Offset
        local a=1-math.exp(-dt*24)
        drag.object.Position=UDim2.fromOffset(current.X.Offset+dx*a,current.Y.Offset+dy*a)
        if math.abs(dx)+math.abs(dy)<.25 and not drag.held then
            drag.object.Position=drag.goal;ui.dragTarget=nil
        end
    end
    for _,fx in pairs(ui.feedback) do
        if fx.age<.7 then
            fx.age=math.min(.7,fx.age+dt)
            local t=fx.age/.7
            local expansion=1-(1-t)^3
            local diameter=2+fx.diameter*expansion
            fx.wave.Size=UDim2.fromOffset(diameter,diameter)
            fx.wave.BackgroundTransparency=.94+.06*t
            fx.edge.Transparency=.18+.82*t
            fx.flash.BackgroundTransparency=1-.16*(1-t)^3
            fx.gradient.Offset=Vector2.new(-1.3+2.6*expansion,0)
            for _,spark in ipairs(fx.sparks) do
                local distance=6+42*expansion
                spark.object.Position=UDim2.new(fx.x,math.cos(spark.angle)*distance,fx.y,math.sin(spark.angle)*distance)
                spark.object.BackgroundTransparency=math.clamp(.2+t*.8,0,1)
                spark.object.Size=UDim2.fromOffset(5-3*t,1)
            end
            if t>=1 then fx.layer.Visible=false end
        end
    end
end
teardownUI=function()
    ui.closing=true;ui.ticket=ui.ticket+1;ui.dragTarget=nil
    for _,tween in pairs(ui.tweens) do pcall(function() tween:Cancel() end) end
    table.clear(ui.tweens);table.clear(ui.feedback);table.clear(ui.buttonState)
end
connect(RunService.RenderStepped,function(dt)
    local ok,err=pcall(stepInterface,dt)
    if not ok and not S.dead then
        ui.dragTarget=nil
        for _,fx in pairs(ui.feedback) do fx.age=1;fx.layer.Visible=false end
        warn("[S&NC Shaders/interface] "..tostring(err))
    end
end)
refreshUI()
task.defer(function()
    if not S.dead then revealPanel(true) end
end)

-- Optional controller for hub/Studio integration. Execution still opens the UI.
return {
    Version="4.0.0",
    SetMode=function(name) if not S.dead then setMode(name) end;return S.active==name end,
    Default=defaultMode,
    Destroy=function() if not S.dead then gui:Destroy() end end,
    Show=function() if not S.dead and minimized then toggleMinimize() end end,
    SetSound=setSound,
    SetAutoWeather=function(enabled) S.autoWeather=enabled==true;S.chance=0;refreshUI() end,
    GetState=function() return {Mode=S.active,RealTime=S.real,Loading=false,
        Sound=S.sound,Volume=S.volume,AudioStatus=S.audioStatus,Destroyed=S.dead} end,
}
