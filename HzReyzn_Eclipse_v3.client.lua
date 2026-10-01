--!nonstrict
-- HzReyzn Eclipse / V3 / world-depth optics / English / PC + Mobile
-- Studio: paste into a LocalScript in StarterPlayerScripts, then Play.
-- The only ScreenGui is the control panel. Sun, Moon and corona use a distant
-- BillboardGui with AlwaysOnTop=false: the renderer handles per-pixel occlusion,
-- including your own character. There are no screen-space spokes or lens discs.
-- Rays use Roblox SunRaysEffect and depend on the client's graphics quality.
-- Textures are computed once. EditableImage is optional; supported clients may
-- cache two generated PNGs using writefile/getcustomasset. No remote assets.
-- Limited nearby material edits are reversible. Existing mesh textures, material
-- variants and avatar materials are preserved; this is not a universal 4K pack.
-- X restores the original environment. Rerunning replaces earlier HZ eclipses.
-- API: create.roblox.com/docs/reference/engine/classes/BillboardGui
--      create.roblox.com/docs/reference/engine/classes/SunRaysEffect

local CONFIG = {
    Approach = 32, Totality = 18, Departure = 32, Daylight = 10,
    Loop = true, SunDegrees = 9, SkyDistance = 24000,
    ClockTime = 15, Latitude = 15,
    CoronaResolution = 512, SunResolution = 256,
    MaterialRadius = 180, MaterialLimit = 240, MaterialScanSeconds = 2,
}
local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local Input = game:GetService("UserInputService")
local Tweens = game:GetService("TweenService")
local AssetService = game:GetService("AssetService")
local player = Players.LocalPlayer
assert(player, "HzReyzn Eclipse must run on the client.")
local playerGui = player:WaitForChild("PlayerGui")
local old = playerGui:FindFirstChild("HzReyznEclipse")
if old then
    local stop = old:FindFirstChild("StopEclipse")
    if stop and stop:IsA("BindableEvent") then stop:Fire(); RunService.Heartbeat:Wait() end
    if old.Parent then old:Destroy() end
end

local state = {
    closed = false, elapsed = 0, visualTime = 0, speed = 1, paused = false,
    loop = CONFIG.Loop, size = 1, targetSize = 1, rays = 1,
    dark = 0, startup = 0, ready = false, materials = true,
    minimized = false, focus = nil, camera = nil, view = Vector2.new(0, 0),
    materialClock = 0, uiClock = 0,
}
local owned, connections, snapshots, parked, postEffects, changedParts = {}, {}, {}, {}, {}, {}
local bindName = "HzReyznEclipseV3_" .. tostring(player.UserId)
local sky, skySaved, restoreFocus
local function safe(fn) return pcall(fn) end
local function restorePart(part, props)
    safe(function()
        if part.Parent then
            for key, pair in pairs(props) do
                -- Respect changes made by the game after our own assignment.
                if part[key] == pair.applied then part[key] = pair.original end
            end
        end
    end)
end
local function restoreMaterials()
    for part, props in pairs(changedParts) do restorePart(part, props) end
    table.clear(changedParts)
end
local function cleanup()
    if state.closed then return end
    state.closed = true
    RunService:UnbindFromRenderStep(bindName)
    for _, c in ipairs(connections) do c:Disconnect() end
    if restoreFocus then restoreFocus() end
    restoreMaterials()
    for i = #owned, 1, -1 do safe(function() owned[i]:Destroy() end) end
    for key, value in pairs(snapshots) do safe(function() Lighting[key] = value end) end
    for obj, enabled in pairs(postEffects) do safe(function() if obj.Parent then obj.Enabled = enabled end end) end
    for _, obj in ipairs(parked) do safe(function() obj.Parent = Lighting end) end
    if sky and skySaved then
        for key, value in pairs(skySaved) do safe(function() if sky.Parent then sky[key] = value end end) end
    end
end
local function connect(signal, fn)
    local c = signal:Connect(fn); table.insert(connections, c); return c
end
local function make(class, props, parent)
    local obj = Instance.new(class)
    for key, value in pairs(props or {}) do obj[key] = value end
    obj.Parent = parent
    return obj
end
local function own(obj) table.insert(owned, obj); return obj end
local function rgb(r, g, b) return Color3.fromRGB(r, g, b) end
local function mix(a, b, t) return a + (b-a)*t end
local function smooth(t) t = math.clamp(t, 0, 1); return t*t*(3-2*t) end
local function damp(a, b, rate, dt) return mix(a, b, 1-math.exp(-rate*dt)) end
local function corner(obj, radius) make("UICorner", {CornerRadius = radius and UDim.new(0, radius) or UDim.new(0.5, 0)}, obj) end
local function circle(parent, name, size, tint, z)
    local obj = make("Frame", {
        Name = name, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromScale(size, size), BackgroundColor3 = tint, BorderSizePixel = 0, ZIndex = z,
    }, parent)
    corner(obj); return obj
end
local function image(parent, name, size, z)
    return make("ImageLabel", {
        Name = name, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromScale(size, size), BackgroundTransparency = 1, ImageTransparency = 1,
        BorderSizePixel = 0, ZIndex = z, ScaleType = Enum.ScaleType.Stretch,
    }, parent)
end
local function coveredArea(distance)
    local d, r = math.abs(distance), 1.024
    if d >= 1+r then return 0 end
    if d <= r-1 then return 1 end
    local a = math.acos(math.clamp((d*d+1-r*r)/(2*d), -1, 1))
    local b = math.acos(math.clamp((d*d+r*r-1)/(2*d*r), -1, 1))
    return math.clamp((a+r*r*b-0.5*math.sqrt(math.max(0,(-d+1+r)*(d+1-r)*(d-1+r)*(d+1+r))))/math.pi, 0, 1)
end
local cycle = CONFIG.Approach+CONFIG.Totality+CONFIG.Departure+CONFIG.Daylight
local function phaseAt(t)
    if t < CONFIG.Approach then return -2.25*(1-smooth(t/CONFIG.Approach)), "FIRST CONTACT" end
    if t < CONFIG.Approach+CONFIG.Totality then return 0, "TOTALITY" end
    if t < CONFIG.Approach+CONFIG.Totality+CONFIG.Departure then
        return 2.25*smooth((t-CONFIG.Approach-CONFIG.Totality)/CONFIG.Departure), "LAST CONTACT"
    end
    return 2.25, "DAYLIGHT"
end

-- Continuous optical profiles: no stacks of circles and no straight ray bars.
-- The corona has broad asymmetric streamers, limb glow and a faint warm rim.
local function coronalPlume(angle, h, direction, width, bend)
    local delta = angle-direction-bend*h
    local wrapped = math.atan2(math.sin(delta), math.cos(delta))
    return math.exp(-(wrapped/(width+0.035*h))^2)
end
local function opticalPixel(kind, px, py, n)
    local scale = kind == "corona" and 2.4 or 1.02
    local x = ((px+0.5)/n*2-1)*scale
    local y = ((py+0.5)/n*2-1)*scale
    local r = math.sqrt(x*x+y*y)
    if kind == "sun" then
        local a = smooth((1-r)*n/2+0.5)
        local mu = math.sqrt(math.max(0, 1-r*r))
        local grain = 0.003*math.sin(115*x+19*y)*math.cos(97*y-31*x)
        local brightness = math.clamp(0.66+0.34*mu+grain, 0, 1)
        return 255*brightness, 251*brightness, 237*brightness, 255*a
    end
    local angle = math.atan2(y, x)
    local h = math.max(0, r-1.003)
    local broad = 0.76+0.20*math.cos(2*angle)+0.08*math.sin(3*angle+0.6)
    local threads = 1+0.12*math.sin(17*angle+2.1*h+math.sin(3*angle))
    local wisps = 0.16*math.exp(-h*1.8)*(coronalPlume(angle,h,0.22,0.24,0.15)+0.80*coronalPlume(angle,h,2.94,0.18,-0.16)+0.55*coronalPlume(angle,h,-1.72,0.30,0.13))
    local falloff = 0.73*math.exp(-h*20)+0.25*math.exp(-h*4.8)*broad*threads+0.13*math.exp(-h*1.9)*broad+wisps
    local fade = 1-smooth((r-1.75)/0.60)
    local a = math.clamp(falloff*fade, 0, 1)
    local warmth = math.exp(-h*50)*0.45
    return 245+10*warmth, 248-25*warmth, 255-77*warmth, 255*a
end

-- Minimal lossless PNG writer for clients exposing a local custom-asset API.
-- This is only an optional texture backend; it never requests network access.
local crcTable
local function be32(n)
    return string.char(math.floor(n/16777216)%256, math.floor(n/65536)%256, math.floor(n/256)%256, n%256)
end
local function pngChunk(kind, data)
    if not crcTable then
        crcTable = {}
        for i = 0, 255 do
            local c = i
            for _ = 1, 8 do c = c%2 == 1 and bit32.bxor(bit32.rshift(c, 1), 0xEDB88320) or bit32.rshift(c, 1) end
            crcTable[i] = c
        end
    end
    local bytes, c = kind..data, 0xFFFFFFFF
    for i = 1, #bytes do
        c = bit32.bxor(bit32.rshift(c, 8), crcTable[bit32.band(bit32.bxor(c, string.byte(bytes, i)), 255)])
    end
    return be32(#data)..bytes..be32(bit32.bxor(c, 0xFFFFFFFF))
end
local function encodePNG(pixels, n)
    local bytes = buffer.tostring(pixels)
    local rows = {}
    for y = 0, n-1 do rows[y+1] = "\0"..string.sub(bytes, y*n*4+1, (y+1)*n*4) end
    local raw = table.concat(rows)
    local blocks, a, b = {string.char(0x78, 0x01)}, 1, 0
    local position = 1
    while position <= #raw do
        if state.closed then return nil end
        local chunk = string.sub(raw, position, position+65534)
        local len = #chunk
        table.insert(blocks, string.char(position+len>#raw and 1 or 0, len%256, math.floor(len/256), (65535-len)%256, math.floor((65535-len)/256))..chunk)
        for i = 1, len do a = (a+string.byte(chunk, i))%65521; b = (b+a)%65521 end
        position = position+len
        task.wait()
    end
    table.insert(blocks, be32(b*65536+a))
    return "\137PNG\r\n\26\n"..pngChunk("IHDR", be32(n)..be32(n)..string.char(8,6,0,0,0))..pngChunk("IDAT",table.concat(blocks))..pngChunk("IEND", "")
end
local function makeOpticalTexture(target, kind, n)
    local getAsset = type(getcustomasset) == "function" and getcustomasset or (type(getsynasset) == "function" and getsynasset or nil)
    local cachePath = "HzReyzn_EclipseV3_r1_"..kind..tostring(n)..".png"
    local canCache = getAsset and type(writefile) == "function"
    if canCache and type(isfile) == "function" then
        local ok, cached = safe(function() return isfile(cachePath) and getAsset(cachePath) end)
        if ok and type(cached) == "string" and cached ~= "" then target.Image = cached; return true end
    end
    local editable
    safe(function() editable = AssetService:CreateEditableImage({Size = Vector2.new(n, n)}) end)
    if editable then own(editable) end
    if not editable and not canCache then return false end
    if type(buffer) ~= "table" then return false end
    local pixels = buffer.create(n*n*4)
    for y = 0, n-1 do
        if state.closed then return false end
        for x = 0, n-1 do
            local r,g,b,a = opticalPixel(kind, x, y, n)
            local i = (y*n+x)*4
            buffer.writeu8(pixels, i, math.floor(math.clamp(r, 0, 255)+0.5))
            buffer.writeu8(pixels, i+1, math.floor(math.clamp(g, 0, 255)+0.5))
            buffer.writeu8(pixels, i+2, math.floor(math.clamp(b, 0, 255)+0.5))
            buffer.writeu8(pixels, i+3, math.floor(math.clamp(a, 0, 255)+0.5))
        end
        if y%16 == 15 then task.wait() end
    end
    if state.closed then return false end
    if editable then
        local ok = safe(function()
            editable:WritePixelsBuffer(Vector2.new(0,0), Vector2.new(n,n), pixels)
            target.ImageContent = Content.fromObject(editable)
        end)
        if ok then return true end
    end
    if canCache then
        local ok = safe(function()
            local png = encodePNG(pixels, n)
            if not png or state.closed then return end
            writefile(cachePath, png)
            target.Image = getAsset(cachePath)
        end)
        return ok and not state.closed and target.Image ~= ""
    end
    return false
end

local function start()
    local gui = own(make("ScreenGui", {
        Name = "HzReyznEclipse", ResetOnSpawn = false, DisplayOrder = 35,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    }, playerGui))
    connect(make("BindableEvent", {Name = "StopEclipse"}, gui).Event, cleanup)
    connect(gui.Destroying, cleanup)
    for _, key in ipairs({
        "ClockTime", "GeographicLatitude", "Brightness", "Ambient", "OutdoorAmbient", "ExposureCompensation",
        "ColorShift_Top", "ColorShift_Bottom", "GlobalShadows", "ShadowSoftness", "EnvironmentDiffuseScale", "EnvironmentSpecularScale",
    }) do snapshots[key] = Lighting[key] end
    local function suppress(container)
        if not container then return end
        for _, obj in ipairs(container:GetChildren()) do
            if obj:IsA("PostEffect") and postEffects[obj] == nil then postEffects[obj] = obj.Enabled; obj.Enabled = false end
        end
    end
    suppress(Lighting); suppress(workspace.CurrentCamera)
    for _, obj in ipairs(Lighting:GetChildren()) do
        if obj:IsA("Atmosphere") then table.insert(parked, obj); obj.Parent = nil end
    end
    sky = Lighting:FindFirstChildOfClass("Sky")
    if sky then
        skySaved = {CelestialBodiesShown = sky.CelestialBodiesShown, SunAngularSize = sky.SunAngularSize, MoonAngularSize = sky.MoonAngularSize}
    else sky = own(make("Sky", {Name = "EclipseSky"}, Lighting)) end
    sky.CelestialBodiesShown = true; sky.SunAngularSize = 0; sky.MoonAngularSize = 0
    local atmosphere = own(make("Atmosphere", {Name = "EclipseAtmosphere", Density = 0.24, Offset = 0.18, Haze = 1.1, Glare = 0}, Lighting))
    local grade = own(make("ColorCorrectionEffect", {Name = "EclipseColor"}, Lighting))
    local bloom = own(make("BloomEffect", {Name = "EclipseBloom", Intensity = 0.13, Size = 32, Threshold = 1.35}, Lighting))
    local rays = own(make("SunRaysEffect", {Name = "EclipseNaturalRays", Intensity = 0.035, Spread = 0.84}, Lighting))
    Lighting.ClockTime = CONFIG.ClockTime; Lighting.GeographicLatitude = CONFIG.Latitude
    Lighting.GlobalShadows = true
    local sunDirection = Lighting:GetSunDirection().Unit
    local orbit = sunDirection:Cross(Vector3.new(0,1,0)).Unit
    local anchor = own(make("Part", {
        Name = "HzEclipseSkyAnchor", Anchored = true, Transparency = 1, Size = Vector3.new(1,1,1),
        CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false,
    }, workspace))
    local board = own(make("BillboardGui", {
        Name = "HzEclipseWorldOptics", Adornee = anchor, AlwaysOnTop = false,
        LightInfluence = 0, MaxDistance = 100000, ClipsDescendants = false,
        Size = UDim2.fromScale(1,1), ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    }, playerGui))
    safe(function() board.Brightness = 1.6 end)
    local canvas = make("Frame", {
        Name = "EclipseCanvas", AnchorPoint = Vector2.new(0.5,0.5), Position = UDim2.fromScale(0.5,0.5),
        Size = UDim2.fromScale(0.2,0.2), BackgroundTransparency = 1,
    }, board)
    local corona = image(canvas, "ContinuousCorona", 2.4, 1)
    local solarFallback = circle(canvas, "SolarFallback", 1, rgb(255,248,228), 3)
    local sun = image(canvas, "LimbDarkenedSun", 1.02, 4)
    local moon = circle(canvas, "LunarSilhouette", 1.024, rgb(2,3,5), 5)
    moon.BackgroundTransparency = 1
    local basicRim = make("UIStroke", {Color = rgb(218,227,240), Transparency = 1, Thickness = 1}, moon)
    -- The Moon is backlit in a solar eclipse; its front is a dark silhouette.
    -- A tiny contact bead appears briefly, with no giant overlay flare.
    local diamond = circle(canvas, "ContactBead", 0.028, rgb(255,253,244), 6)
    diamond.BackgroundTransparency = 1
    local sunReady, coronaReady = false, false
    task.spawn(function()
        local ok, result = safe(function() return makeOpticalTexture(sun, "sun", CONFIG.SunResolution) end)
        sunReady = ok and result == true
        if state.closed then return end
        ok, result = safe(function() return makeOpticalTexture(corona, "corona", CONFIG.CoronaResolution) end)
        coronaReady = ok and result == true
        if not state.closed then state.ready = true end
    end)

    -- Only nearby architectural parts are considered; no whole-map traversal.
    local materialQueue, materialCursor, materialCount = {}, 1, 0
    local overlap = OverlapParams.new()
    overlap.FilterType = Enum.RaycastFilterType.Exclude
    overlap.MaxParts = CONFIG.MaterialLimit*2
    local function hasCustomSurface(part)
        if part:IsA("MeshPart") or part.MaterialVariant ~= "" then return true end
        for _, child in ipairs(part:GetChildren()) do
            if child:IsA("Decal") or child:IsA("Texture") or child:IsA("SurfaceAppearance") or child:IsA("SpecialMesh") then return true end
        end
        return false
    end
    local function isArchitecture(part)
        if not part:IsA("BasePart") or not part.Anchored or part.Transparency > 0.10 or part == anchor then return false end
        if hasCustomSurface(part) then return false end
        local ancestor = part.Parent
        for _ = 1, 8 do
            if not ancestor or ancestor == workspace then break end
            if ancestor:IsA("Tool") or ancestor:IsA("Accessory") or ancestor:FindFirstChildOfClass("Humanoid") then return false end
            ancestor = ancestor.Parent
        end
        return true
    end
    local materialRules = {
        {"grass", Enum.Material.Grass}, {"pasto", Enum.Material.Grass},
        {"asphalt", Enum.Material.Asphalt}, {"road", Enum.Material.Asphalt},
        {"brick", Enum.Material.Brick}, {"ladrillo", Enum.Material.Brick},
        {"wood", Enum.Material.Wood}, {"plank", Enum.Material.WoodPlanks}, {"madera", Enum.Material.Wood},
        {"concrete", Enum.Material.Concrete}, {"pavement", Enum.Material.Pavement},
        {"rock", Enum.Material.Rock}, {"stone", Enum.Material.Slate},
        {"sand", Enum.Material.Sand}, {"metal", Enum.Material.Metal},
    }
    local function inferMaterial(part)
        if part.Material ~= Enum.Material.Plastic and part.Material ~= Enum.Material.SmoothPlastic then return nil end
        local name = string.lower(part.Name .. " " .. (part.Parent and part.Parent.Name or ""))
        for _, rule in ipairs(materialRules) do if string.find(name, rule[1], 1, true) then return rule[2] end end
        local isFloor = string.find(name,"floor",1,true) or string.find(name,"ground",1,true) or string.find(name,"baseplate",1,true)
        if isFloor then
            local c = part.Color
            if c.G > c.R*1.2 and c.G > c.B*1.15 then return Enum.Material.Grass end
            return Enum.Material.Concrete
        end
        if string.find(name,"wall",1,true) or string.find(name,"pared",1,true) then return Enum.Material.Plaster end
        return nil
    end
    local function changeProperty(part, key, value)
        if part[key] == value then return end
        if not changedParts[part] then changedParts[part] = {}; materialCount = materialCount+1 end
        changedParts[part][key] = {original = part[key], applied = value}
        part[key] = value
    end
    local function refreshMaterials()
        if not state.materials or state.closed then return end
        local cam = workspace.CurrentCamera
        if not cam then return end
        local origin = cam.CFrame.Position
        local rootPart = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
        if rootPart then origin = rootPart.Position end
        for part, props in pairs(changedParts) do
            if not part.Parent or (part.Position-origin).Magnitude > CONFIG.MaterialRadius+40 then
                restorePart(part, props); changedParts[part] = nil; materialCount = materialCount-1
            end
        end
        local exclude = {anchor, cam}
        if player.Character then table.insert(exclude, player.Character) end
        overlap.FilterDescendantsInstances = exclude
        materialQueue = workspace:GetPartBoundsInRadius(origin, CONFIG.MaterialRadius, overlap)
        materialCursor = 1
    end
    connect(RunService.Heartbeat, function()
        if state.closed or not state.materials then return end
        for _ = 1, 16 do
            local part = materialQueue[materialCursor]
            if not part then break end
            materialCursor = materialCursor+1
            if materialCount >= CONFIG.MaterialLimit then break end
            if not changedParts[part] and part.Parent and isArchitecture(part) then
                local mat = inferMaterial(part)
                if mat then
                    -- Preserve friction/density while changing only the surface look.
                    if part.CustomPhysicalProperties == nil then
                        changeProperty(part, "CustomPhysicalProperties", part.CurrentPhysicalProperties)
                    end
                    changeProperty(part, "Material", mat)
                end
                -- Keep reflection restrained on named materials, not plastic mirrors.
                if mat and part.Reflectance > 0.08 then changeProperty(part, "Reflectance", 0.04) end
            end
        end
    end)

    -- Cyan / violet cyberpunk console, with a compact animated header.
    local W, H, MINI = 336, 332, 68
    local CYAN, VIOLET = rgb(100,236,246), rgb(160,131,244)
    local panel = make("Frame", {
        Name = "CyberpunkPanel", Position = UDim2.fromOffset(18,76), Size = UDim2.fromOffset(W,H),
        BackgroundColor3 = rgb(5,7,12), BackgroundTransparency = 0.055, BorderSizePixel = 0,
        ClipsDescendants = true, Active = true,
    }, gui)
    corner(panel, 10)
    local panelScale = make("UIScale", {Scale = 1}, panel)
    local border = make("UIStroke", {Color = rgb(255,255,255), Transparency = 0.28, Thickness = 1.2}, panel)
    local edgeGradient = make("UIGradient", {
        Rotation = 24, Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0,CYAN), ColorSequenceKeypoint.new(0.5,rgb(52,62,85)), ColorSequenceKeypoint.new(1,VIOLET),
        }),
    }, border)
    local glass = make("Frame", {Size = UDim2.fromScale(1,1), BackgroundColor3 = rgb(71,88,111), BackgroundTransparency = 0.86, BorderSizePixel = 0, ZIndex = 1}, panel)
    make("UIGradient", {Rotation = 110, Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0,0.1), NumberSequenceKeypoint.new(0.48,1), NumberSequenceKeypoint.new(1,0.40),
    })}, glass)
    local scan = make("Frame", {Size = UDim2.new(1,0,0,1), BackgroundColor3 = CYAN, BackgroundTransparency = 0.91, BorderSizePixel = 0, ZIndex = 2}, panel)
    local function line(parent, x,y,w,h,tint,opacity,z)
        return make("Frame", {Position = UDim2.fromOffset(x,y), Size = UDim2.fromOffset(w,h), BackgroundColor3 = tint, BackgroundTransparency = 1-opacity, BorderSizePixel = 0, ZIndex = z or 3}, parent)
    end
    line(panel,0,10,3,31,CYAN,0.8); line(panel,W-3,H-46,3,32,VIOLET,0.8)
    local function label(parent, name, text, x,y,w,h,size,tint,font)
        return make("TextLabel", {
            Name = name, Position = UDim2.fromOffset(x,y), Size = UDim2.fromOffset(w,h), Text = text,
            TextSize = size, TextColor3 = tint or rgb(231,239,247), Font = font or Enum.Font.GothamMedium,
            TextXAlignment = Enum.TextXAlignment.Left, BackgroundTransparency = 1, ZIndex = 4,
        }, parent)
    end
    local header = make("Frame", {Name = "DragArea", Size = UDim2.fromOffset(W-83,MINI), BackgroundTransparency = 1, Active = true, ZIndex = 4}, panel)
    local badge = make("Frame", {Position = UDim2.fromOffset(16,18), Size = UDim2.fromOffset(32,32), BackgroundColor3 = rgb(12,22,30), BorderSizePixel = 0}, header)
    corner(badge,6)
    local icon = circle(badge,"Icon",0.49,rgb(7,11,18),2)
    make("UIStroke", {Color = CYAN, Thickness = 1.3, Transparency = 0.1}, icon)
    local spark = circle(icon,"Highlight",0.16,rgb(255,255,255),3); spark.Position = UDim2.fromScale(0.09,0.2)
    label(header,"Brand","HZREYZN  /  ENV",58,12,175,16,10,CYAN,Enum.Font.Code)
    label(header,"Title","ECLIPSE",57,28,187,25,22,nil,Enum.Font.GothamBold)
    local body = make("Frame", {Name = "Controls", Position = UDim2.fromOffset(0,MINI), Size = UDim2.fromOffset(W,H-MINI), BackgroundTransparency = 1, ZIndex = 4}, panel)
    line(body,16,0,W-32,1,rgb(97,129,157),0.36)
    local statusDot = circle(body,"StatusDot",0,CYAN,4); statusDot.Size = UDim2.fromOffset(5,5); statusDot.Position = UDim2.fromOffset(20,23)
    local phaseLabel = label(body,"Phase","INITIALIZING",30,12,209,23,11,rgb(181,201,215),Enum.Font.Code)
    local percent = label(body,"Coverage","00%",248,8,72,29,24,nil,Enum.Font.GothamBold)
    percent.TextXAlignment = Enum.TextXAlignment.Right
    local track = line(body,16,46,W-32,3,rgb(38,53,71),1)
    local progress = make("Frame", {Name="Progress", Size=UDim2.fromScale(0,1), BackgroundColor3=rgb(255,255,255), BorderSizePixel=0},track)
    make("UIGradient", {Color=ColorSequence.new(CYAN,VIOLET)},progress)
    local timeLabel = label(body,"Time","00:00 / 01:32",16,54,174,15,10,rgb(122,147,165),Enum.Font.Code)
    local mode = label(body,"Mode","LIVE SKY",208,54,112,15,10,VIOLET,Enum.Font.Code); mode.TextXAlignment=Enum.TextXAlignment.Right
    local function button(parent,name,text,x,y,w,h,primary)
        local b = make("TextButton", {
            Name=name, Text=text, Position=UDim2.fromOffset(x,y), Size=UDim2.fromOffset(w,h),
            BackgroundColor3=primary and rgb(111,227,237) or rgb(16,24,36), BackgroundTransparency=primary and 0.05 or 0.15,
            TextColor3=primary and rgb(5,16,23) or rgb(210,225,237), TextSize=11,
            Font=Enum.Font.Code, AutoButtonColor=false, BorderSizePixel=0, ZIndex=5,
        },parent)
        corner(b,5)
        make("UIStroke",{Color=primary and CYAN or rgb(80,111,139),Transparency=primary and 0.6 or 0.58,Thickness=1,ApplyStrokeMode=Enum.ApplyStrokeMode.Border},b)
        local hoverTween
        local function hover(active)
            if hoverTween then hoverTween:Cancel() end
            hoverTween=Tweens:Create(b,TweenInfo.new(0.15),{BackgroundTransparency=active and 0 or (primary and 0.05 or 0.15)})
            hoverTween:Play()
        end
        connect(b.MouseEnter,function() hover(true) end); connect(b.MouseLeave,function() hover(false) end)
        return b
    end
    local pause=button(body,"Pause","PAUSE",16,80,96,32,true)
    local restart=button(body,"Restart","RESTART",120,80,96,32)
    local speed=button(body,"Speed","1x SPEED",224,80,96,32)
    local sizeButton=button(body,"Size","SUN / MEDIUM",16,121,148,30)
    local rayButton=button(body,"Rays","RAYS / NATURAL",172,121,148,30)
    local materialButton=button(body,"Materials","SURFACES / ON",16,160,148,30)
    local exposureButton=button(body,"Visibility","VISIBILITY / AUTO",172,160,148,30)
    local focusButton=button(body,"FocusSun","VIEW ECLIPSE",16,199,200,32)
    local loopButton=button(body,"Loop","LOOP / ON",224,199,96,32)
    local hint=label(body,"Hint","DRAG TO MOVE   /   X RESTORES SCENE",16,243,304,14,9,rgb(111,139,157),Enum.Font.Code)
    local minimize=button(panel,"Minimize","−",W-78,21,27,27)
    local close=button(panel,"Close","×",W-42,21,27,27)
    minimize.TextSize=17; close.TextSize=17
    connect(close.Activated,cleanup)
    connect(pause.Activated,function() state.paused=not state.paused; pause.Text=state.paused and "RESUME" or "PAUSE" end)
    connect(restart.Activated,function() state.elapsed=0; state.paused=false; pause.Text="PAUSE" end)
    connect(speed.Activated,function()
        state.speed=state.speed==1 and 2 or (state.speed==2 and 0.5 or 1)
        speed.Text=tostring(state.speed).."x SPEED"
    end)
    connect(sizeButton.Activated,function()
        state.targetSize=state.targetSize==1 and 1.4 or (state.targetSize>1 and 0.68 or 1)
        sizeButton.Text=state.targetSize==1 and "SUN / MEDIUM" or (state.targetSize>1 and "SUN / LARGE" or "SUN / SMALL")
    end)
    connect(rayButton.Activated,function()
        state.rays=state.rays==1 and 1.5 or (state.rays>1 and 0.55 or 1)
        rayButton.Text=state.rays==1 and "RAYS / NATURAL" or (state.rays>1 and "RAYS / STRONG" or "RAYS / SOFT")
    end)
    connect(materialButton.Activated,function()
        state.materials=not state.materials
        materialButton.Text=state.materials and "SURFACES / ON" or "SURFACES / OFF"
        if state.materials then state.materialClock=CONFIG.MaterialScanSeconds
        else restoreMaterials();materialCount=0;materialQueue={};materialCursor=1 end
    end)
    local visibilityBoost=false
    connect(exposureButton.Activated,function()
        visibilityBoost=not visibilityBoost
        exposureButton.Text=visibilityBoost and "VISIBILITY / HIGH" or "VISIBILITY / AUTO"
    end)
    connect(loopButton.Activated,function() state.loop=not state.loop;loopButton.Text=state.loop and "LOOP / ON" or "LOOP / OFF" end)
    local resizeTween
    local function clampPanel()
        local view,s=gui.AbsoluteSize,panelScale.Scale
        panel.Position=UDim2.fromOffset(
            math.clamp(panel.Position.X.Offset,4,math.max(4,view.X-W*s-4)),
            math.clamp(panel.Position.Y.Offset,4,math.max(4,view.Y-(state.minimized and MINI or H)*s-4)))
    end
    connect(minimize.Activated,function()
        state.minimized=not state.minimized;minimize.Text=state.minimized and "+" or "−"
        if resizeTween then resizeTween:Cancel() end
        resizeTween=Tweens:Create(panel,TweenInfo.new(0.24,Enum.EasingStyle.Quart,Enum.EasingDirection.Out),{Size=UDim2.fromOffset(W,state.minimized and MINI or H)})
        resizeTween:Play();clampPanel()
    end)
    local dragging,dragInput,dragStart,panelStart
    connect(header.InputBegan,function(input)
        if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then
            dragging=true;dragInput=input;dragStart=input.Position;panelStart=panel.Position
        end
    end)
    connect(Input.InputEnded,function(input) if input==dragInput then dragging=false;dragInput=nil end end)
    connect(Input.InputChanged,function(input)
        if not dragging or (input~=dragInput and input.UserInputType~=Enum.UserInputType.MouseMovement) then return end
        local d=input.Position-dragStart
        panel.Position=UDim2.fromOffset(panelStart.X.Offset+d.X,panelStart.Y.Offset+d.Y);clampPanel()
    end)
    restoreFocus=function()
        local f=state.focus;state.focus=nil
        if f then safe(function() if f.camera.CameraType==Enum.CameraType.Scriptable then f.camera.CameraType=f.previous end end) end
    end
    connect(focusButton.Activated,function()
        restoreFocus()
        local cam=workspace.CurrentCamera
        if cam then state.focus={camera=cam,from=cam.CFrame,previous=cam.CameraType,time=0};cam.CameraType=Enum.CameraType.Scriptable end
    end)
    connect(Input.InputBegan,function(input,processed)
        if not processed and state.focus and (input.UserInputType==Enum.UserInputType.Touch or input.UserInputType==Enum.UserInputType.MouseButton2) then restoreFocus() end
    end)
    connect(workspace:GetPropertyChangedSignal("CurrentCamera"),function() restoreFocus();state.camera=nil;suppress(workspace.CurrentCamera) end)
    connect(player.CharacterAdded,function() restoreFocus();state.materialClock=CONFIG.MaterialScanSeconds end)

    local function clock(t) local s=math.floor(t);return string.format("%02d:%02d",math.floor(s/60),s%60) end
    local function render(dt)
        if state.closed then return end
        local cam=workspace.CurrentCamera
        if not cam then return end
        dt=math.min(dt,0.1)
        local view=cam.ViewportSize
        if view.X<2 or view.Y<2 then return end
        if state.camera~=cam or state.view~=view then
            state.camera=cam;state.view=view
            panelScale.Scale=math.clamp(math.min((gui.AbsoluteSize.X-12)/W,(gui.AbsoluteSize.Y-12)/H,1),0.5,1)
            clampPanel()
        end
        if state.focus then
            local f=state.focus;f.time=f.time+dt
            local goal=CFrame.lookAt(f.from.Position,f.from.Position+sunDirection)
            cam.CFrame=f.from:Lerp(goal,smooth(f.time/0.75))
            if f.time>=0.75 then restoreFocus() end
        end
        if state.ready and not state.paused then state.elapsed=state.elapsed+dt*state.speed;state.visualTime=state.visualTime+dt*state.speed end
        if state.elapsed>=cycle then state.elapsed=state.loop and state.elapsed%cycle or cycle end
        state.startup=math.min(1,state.startup+dt/1.2)
        state.size=damp(state.size,state.targetSize,7,dt)
        local x,phase=phaseAt(state.elapsed)
        local covered=coveredArea(x)
        local total=smooth((covered-0.94)/0.06)
        local contact=math.exp(-((math.abs(x)-0.065)/0.038)^2)
        state.dark=damp(state.dark,covered^1.85,4,dt)
        local dark=state.dark
        local enter=smooth(state.startup)
        Lighting.ClockTime=CONFIG.ClockTime;Lighting.GeographicLatitude=CONFIG.Latitude
        local function number(key,target) Lighting[key]=mix(snapshots[key],target,enter) end
        local function color(key,target) Lighting[key]=snapshots[key]:Lerp(target,enter) end
        -- Exposure compensation and ambient floors prevent the V2 blackout.
        -- Direct sunlight falls, but diffuse skylight stays useful for navigation.
        number("Brightness",mix(2.15,visibilityBoost and 1.0 or 0.78,dark))
        number("ExposureCompensation",mix(0.03,visibilityBoost and 0.03 or -0.12,dark))
        color("Ambient",rgb(96,98,106):Lerp(visibilityBoost and rgb(86,94,111) or rgb(68,77,96),dark))
        color("OutdoorAmbient",rgb(148,150,153):Lerp(visibilityBoost and rgb(132,141,157) or rgb(107,119,139),dark))
        color("ColorShift_Top",rgb(4,3,1):Lerp(rgb(1,2,5),dark))
        color("ColorShift_Bottom",rgb(0,0,0))
        number("EnvironmentDiffuseScale",mix(0.78,0.68,dark))
        number("EnvironmentSpecularScale",mix(0.80,0.70,dark))
        number("ShadowSoftness",mix(0.24,0.12,covered))
        atmosphere.Color=rgb(211,218,228):Lerp(rgb(120,138,169),dark)
        atmosphere.Decay=rgb(129,144,162):Lerp(rgb(71,85,112),dark)
        atmosphere.Density=mix(0.24,0.27,dark);atmosphere.Haze=mix(1.1,1.35,dark)
        grade.TintColor=rgb(255,252,247):Lerp(rgb(226,237,255),dark)
        grade.Saturation=mix(-0.025,-0.11,dark)*enter
        grade.Contrast=mix(0.025,0.055,dark)*enter
        grade.Brightness=0 -- never crush the entire scene into black
        rays.Intensity=(0.045*(1-covered)^1.2+0.025*contact)*state.rays*enter
        rays.Spread=0.84
        bloom.Intensity=(0.12+0.08*contact+0.045*total)*enter
        -- True world depth. All geometry is far behind nearby players/buildings.
        anchor.Position=cam.CFrame.Position+sunDirection*CONFIG.SkyDistance
        local diameter=2*CONFIG.SkyDistance*math.tan(math.rad(CONFIG.SunDegrees*state.size/2))
        board.Size=UDim2.fromScale(diameter*5,diameter*5)
        local projected=cam:WorldToViewportPoint(anchor.Position)
        local tangent=cam:WorldToViewportPoint(anchor.Position+orbit*100)
        canvas.Rotation=math.deg(math.atan2(tangent.Y-projected.Y,tangent.X-projected.X))
        board.Enabled=projected.Z>0
        solarFallback.Visible=not sunReady
        solarFallback.BackgroundTransparency=1-enter
        sun.ImageTransparency=sunReady and 1-enter or 1
        -- Show the physical corona mainly near totality; quiet during daylight.
        corona.ImageTransparency=coronaReady and 1-math.clamp((0.008+0.82*total+0.08*contact)*enter,0,1) or 1
        moon.Position=UDim2.fromScale(0.5+x*0.5,0.5)
        moon.BackgroundTransparency=1-enter*smooth((2.25-math.abs(x))/0.18)
        basicRim.Transparency=coronaReady and 1 or (1-total*0.55*enter)
        diamond.Position=UDim2.fromScale(0.5+(x<=0 and 1 or -1)*0.491,0.5)
        diamond.BackgroundTransparency=1-contact*enter
        -- Confine decorative animation to the panel.
        edgeGradient.Rotation=24+10*math.sin(os.clock()*0.25)
        scan.Position=UDim2.fromOffset(0,(os.clock()*13)%(state.minimized and MINI or H))
        state.materialClock=state.materialClock+dt
        if state.materialClock>=CONFIG.MaterialScanSeconds then
            state.materialClock=0
            local okScan,err=safe(refreshMaterials)
            if not okScan then warn("HzReyzn material scan skipped: "..tostring(err));state.materials=false;restoreMaterials();materialCount=0;materialButton.Text="SURFACES / OFF" end
        end
        state.uiClock=state.uiClock+dt
        if state.uiClock>=0.1 then
            state.uiClock=0
            phaseLabel.Text=not state.ready and "INITIALIZING" or (state.paused and phase.." / PAUSED" or phase)
            percent.Text=string.format("%02d%%",math.floor(covered*100+0.5))
            progress.Size=UDim2.fromScale(state.elapsed/cycle,1)
            timeLabel.Text=clock(state.elapsed).." / "..clock(cycle)
            hint.Text=projected.Z<=0 and "TAP VIEW ECLIPSE TO FIND THE SUN" or "DRAG TO MOVE   /   X RESTORES SCENE"
        end
    end
    RunService:BindToRenderStep(bindName,Enum.RenderPriority.Camera.Value+1,function(dt)
        local okRender,err=xpcall(function() render(dt) end,debug.traceback)
        if not okRender then cleanup();warn("HzReyzn Eclipse stopped safely: "..tostring(err)) end
    end)
end

local ok, problem = xpcall(start, debug.traceback)
if not ok then cleanup(); warn("HzReyzn Eclipse could not start: "..tostring(problem)) end
