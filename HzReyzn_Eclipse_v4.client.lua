--!nonstrict
-- HzReyzn Eclipse V4 / black + silver UI / manual activation / PC + Mobile
-- Studio: LocalScript in StarterPlayerScripts. The eclipse starts OFF.
-- Sun and Moon are opaque 3D spheres, not image-dependent GUI discs.
-- Optional corona/detail textures use EditableImage or a local custom-asset API.
-- HD detail: one reusable 1024x1024 tile, applied in batches to every streamed
-- BasePart whose NAME contains 'part', case-insensitively, including MeshParts.
-- Existing texture assets are retained. Six face textures add surface grain;
-- matching plastic parts also receive native Concrete, with physics preserved.
-- If custom-image APIs are unavailable, the panel reports BASIC SURFACES.
-- Deactivate restores Lighting; HD SURFACES is independent. X restores both.

local CONFIG = {
    Approach=32, Totality=18, Departure=32, Daylight=10, Loop=true,
    SunDegrees=12, SunDistance=2000, MoonDistance=1400,
    ClockTime=15, Latitude=15, FocusOnActivation=true,
    DetailResolution=1024, DetailTileStuds=6, PartsPerFrame=4,
}
local Players=game:GetService("Players")
local Lighting=game:GetService("Lighting")
local RunService=game:GetService("RunService")
local Input=game:GetService("UserInputService")
local TweenService=game:GetService("TweenService")
local AssetService=game:GetService("AssetService")
local player=Players.LocalPlayer
assert(player,"Run HzReyzn Eclipse on the client.")
local playerGui=player:WaitForChild("PlayerGui")
local old=playerGui:FindFirstChild("HzReyznEclipse")
if old then
    local stop=old:FindFirstChild("StopEclipse")
    if stop and stop:IsA("BindableEvent") then stop:Fire();RunService.Heartbeat:Wait() end
    if old.Parent then old:Destroy() end
end
local state={closed=false,active=false,elapsed=0,paused=false,speed=1,loop=CONFIG.Loop,
    rays=1,minimized=false,hd=true,detailReady=false,detailAsset=nil,session=nil,
    focus=nil,camera=nil,view=Vector2.new(0,0),uiClock=0}
local owned,connections,watchers,details={},{},{},{}
local bindName="HzReyznEclipseV4_"..tostring(player.UserId)
local gui,panel,panelScale
local deactivate,restoreFocus,restoreAllDetails
local function safe(fn) return pcall(fn) end
local function cleanup()
    if state.closed then return end
    state.closed=true
    RunService:UnbindFromRenderStep(bindName)
    if deactivate then deactivate() end
    for _,c in ipairs(connections) do c:Disconnect() end
    for _,c in pairs(watchers) do c:Disconnect() end
    table.clear(watchers)
    if restoreAllDetails then restoreAllDetails() end
    for i=#owned,1,-1 do safe(function() owned[i]:Destroy() end) end
end
local function connect(signal,fn) local c=signal:Connect(fn);table.insert(connections,c);return c end
local function make(class,props,parent)
    local obj=Instance.new(class)
    for k,v in pairs(props or {}) do obj[k]=v end
    obj.Parent=parent;return obj
end
local function own(obj) table.insert(owned,obj);return obj end
local function rgb(r,g,b) return Color3.fromRGB(r,g,b) end
local function mix(a,b,t) return a+(b-a)*t end
local function smooth(t) t=math.clamp(t,0,1);return t*t*(3-2*t) end
local function damp(a,b,rate,dt) return mix(a,b,1-math.exp(-rate*dt)) end
local function corner(obj,n) make("UICorner",{CornerRadius=n and UDim.new(0,n) or UDim.new(0.5,0)},obj) end
local function circle(parent,name,size,tint,z)
    local obj=make("Frame",{Name=name,AnchorPoint=Vector2.new(0.5,0.5),Position=UDim2.fromScale(0.5,0.5),
        Size=UDim2.fromScale(size,size),BackgroundColor3=tint,BorderSizePixel=0,ZIndex=z or 1},parent)
    corner(obj);return obj
end
local cycle=CONFIG.Approach+CONFIG.Totality+CONFIG.Departure+CONFIG.Daylight
local function phaseAt(t)
    if t<CONFIG.Approach then return -2.25*(1-smooth(t/CONFIG.Approach)),"FIRST CONTACT" end
    if t<CONFIG.Approach+CONFIG.Totality then return 0,"TOTAL ECLIPSE" end
    if t<CONFIG.Approach+CONFIG.Totality+CONFIG.Departure then
        return 2.25*smooth((t-CONFIG.Approach-CONFIG.Totality)/CONFIG.Departure),"LAST CONTACT"
    end
    return 2.25,"DAYLIGHT"
end
local function coverage(distance)
    local d,r=math.abs(distance),1.024
    if d>=1+r then return 0 end
    if d<=r-1 then return 1 end
    local a=math.acos(math.clamp((d*d+1-r*r)/(2*d),-1,1))
    local b=math.acos(math.clamp((d*d+r*r-1)/(2*d*r),-1,1))
    return math.clamp((a+r*r*b-0.5*math.sqrt(math.max(0,(-d+1+r)*(d+1-r)*(d-1+r)*(d+1+r))))/math.pi,0,1)
end

local function coronalPlume(angle, h, direction, width, bend)
    local delta = angle-direction-bend*h
    local wrapped = math.atan2(math.sin(delta), math.cos(delta))
    return math.exp(-(wrapped/(width+0.035*h))^2)
end
local function opticalPixel(kind, px, py, n)
    if kind == "detail" then
        -- Periodic large-scale variation plus deterministic fine grain/pores.
        local u, v = px/n*math.pi*2, py/n*math.pi*2
        local seed = bit32.bxor(px*374761393, py*668265263)
        seed = bit32.bxor(seed, bit32.lshift(seed, 13))
        seed = bit32.bxor(seed, bit32.rshift(seed, 17))
        seed = bit32.bxor(seed, bit32.lshift(seed, 5))
        local fine = bit32.band(seed, 255)/255
        local broad = math.sin(u+0.7*math.sin(v))*math.cos(v*2+0.4*math.sin(u))
        local pores = bit32.band(bit32.rshift(seed, 8), 255)<4 and 28 or 0
        local shade = math.clamp(232+9*broad+20*(fine-0.5)-pores, 175, 252)
        return shade, shade, shade, 255
    end
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
        if i%65536 == 0 then
            task.wait()
            if state.closed then return "" end
        end
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
    local cachePath = "HzReyzn_EclipseV4_r1_"..kind..tostring(n)..".png"
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
    gui=own(make("ScreenGui",{Name="HzReyznEclipse",ResetOnSpawn=false,DisplayOrder=35,ZIndexBehavior=Enum.ZIndexBehavior.Sibling},playerGui))
    connect(make("BindableEvent",{Name="StopEclipse"},gui).Event,cleanup)
    connect(gui.Destroying,cleanup)
    local assetJobs={}
    local function applyAsset(obj,asset,isTexture)
        if not asset then return false end
        return safe(function()
            local sink=asset.sink
            if sink.Image~="" then
                if isTexture then obj.Texture=sink.Image else obj.Image=sink.Image end
            elseif isTexture then obj.ColorMapContent=sink.ImageContent
            else obj.ImageContent=sink.ImageContent end
        end)
    end
    local function requestTexture(kind,n,callback)
        local existing=assetJobs[kind]
        if existing then
            if existing.done then callback(existing.asset) else table.insert(existing.callbacks,callback) end
            return
        end
        local job={callbacks={callback},done=false};assetJobs[kind]=job
        task.spawn(function()
            if state.closed then return end
            local sink=own(make("ImageLabel",{BackgroundTransparency=1,Image=""},nil))
            local ok,result=safe(function() return makeOpticalTexture(sink,kind,n) end)
            if state.closed then return end
            job.asset=ok and result==true and {sink=sink} or nil
            job.done=true
            for _,fn in ipairs(job.callbacks) do fn(job.asset) end
            table.clear(job.callbacks)
        end)
    end

    -- All matching names are eligible, not only architectural names or anchored
    -- parts. Work is queued once and on additions/renames, not rescanned each frame.
    local queue,queued,cursor={}, {}, 1
    local appliedCount=0
    local function matches(part)
        return part:IsA("BasePart") and string.find(string.lower(part.Name),"part",1,true)~=nil
    end
    local function restoreDetail(part)
        local record=details[part]
        if not record then return end
        details[part]=nil;appliedCount=math.max(0,appliedCount-1)
        for _,tex in ipairs(record.textures) do safe(function() tex:Destroy() end) end
        if record.colorConnection then record.colorConnection:Disconnect() end
        safe(function()
            if part.Parent then
                for key,pair in pairs(record.props) do if part[key]==pair.applied then part[key]=pair.original end end
            end
        end)
    end
    restoreAllDetails=function()
        for part in pairs(details) do restoreDetail(part) end
        table.clear(queue);table.clear(queued);cursor=1
    end
    local function enqueue(part)
        if state.closed or not state.hd or not part.Parent or not matches(part) or details[part] or queued[part] then return end
        queued[part]=true;table.insert(queue,part)
    end
    local function observe(part)
        if not part:IsA("BasePart") or watchers[part] then return end
        watchers[part]=part:GetPropertyChangedSignal("Name"):Connect(function()
            if matches(part) then enqueue(part) else restoreDetail(part) end
        end)
        enqueue(part)
    end
    local faces={Enum.NormalId.Front,Enum.NormalId.Back,Enum.NormalId.Left,Enum.NormalId.Right,Enum.NormalId.Top,Enum.NormalId.Bottom}
    local function applyDetail(part)
        if not state.hd or not matches(part) or not part:IsDescendantOf(workspace) or details[part] then return end
        local record={textures={},props={}};details[part]=record;appliedCount=appliedCount+1
        local function change(key,value)
            if part[key]==value then return end
            record.props[key]={original=part[key],applied=value};part[key]=value
        end
        -- Native micro-surface shading complements the visible 1024 px tile.
        if (part.Material==Enum.Material.Plastic or part.Material==Enum.Material.SmoothPlastic) and part.MaterialVariant=="" then
            if part.CustomPhysicalProperties==nil then change("CustomPhysicalProperties",part.CurrentPhysicalProperties) end
            change("Material",Enum.Material.Concrete)
        end
        if state.detailAsset then
            for _,face in ipairs(faces) do
                local tex=make("Texture",{Name="HzEclipseHD",Face=face,Color3=part.Color,Transparency=0.35,
                    StudsPerTileU=CONFIG.DetailTileStuds,StudsPerTileV=CONFIG.DetailTileStuds,ZIndex=3},nil)
                if applyAsset(tex,state.detailAsset,true) then
                    table.insert(record.textures,tex);tex.Parent=part
                else tex:Destroy() end
            end
            record.colorConnection=part:GetPropertyChangedSignal("Color"):Connect(function()
                for _,tex in ipairs(record.textures) do if tex.Parent then tex.Color3=part.Color end end
            end)
        end
    end
    connect(workspace.DescendantAdded,observe)
    connect(workspace.DescendantRemoving,function(obj)
        if watchers[obj] then watchers[obj]:Disconnect();watchers[obj]=nil end
        if details[obj] then restoreDetail(obj) end
        queued[obj]=nil
    end)
    local initial=workspace:GetDescendants();local initialCursor=1
    connect(RunService.Heartbeat,function()
        if state.closed then return end
        for _=1,80 do
            local obj=initial[initialCursor]
            if not obj then break end
            initialCursor=initialCursor+1
            if obj.Parent then observe(obj) end
        end
        if initialCursor>#initial then table.clear(initial);initialCursor=1 end
        if not state.hd or not state.detailReady then return end
        for _=1,CONFIG.PartsPerFrame do
            local part=queue[cursor]
            if not part then break end
            cursor=cursor+1;queued[part]=nil
            local ok=safe(function() if part.Parent then applyDetail(part) end end)
            if not ok then restoreDetail(part) end
        end
        if cursor>#queue then table.clear(queue);cursor=1 end
    end)
    requestTexture("detail",CONFIG.DetailResolution,function(asset)
        local probe=make("Texture",{},nil)
        state.detailAsset=applyAsset(probe,asset,true) and asset or nil
        probe:Destroy();state.detailReady=true
    end)

    restoreFocus=function()
        local f=state.focus;state.focus=nil
        if f then safe(function() if f.camera.CameraType==Enum.CameraType.Scriptable then f.camera.CameraType=f.previousType end end) end
    end
    local function focusSun()
        restoreFocus()
        local s,cam=state.session,workspace.CurrentCamera
        if not s or not cam then return end
        state.focus={camera=cam,from=cam.CFrame,previousType=cam.CameraType,time=0,direction=s.direction}
        cam.CameraType=Enum.CameraType.Scriptable
    end
    local function suppressCamera(cam,s)
        if not cam or not s then return end
        for _,obj in ipairs(cam:GetChildren()) do
            if obj:IsA("PostEffect") and s.post[obj]==nil then s.post[obj]=obj.Enabled;obj.Enabled=false end
        end
    end
    deactivate=function()
        restoreFocus()
        state.active=false;state.paused=false;state.elapsed=0
        local s=state.session;state.session=nil
        if not s then return end
        for i=#s.owned,1,-1 do safe(function() s.owned[i]:Destroy() end) end
        for key,value in pairs(s.saved) do safe(function() Lighting[key]=value end) end
        for obj,enabled in pairs(s.post) do safe(function() if obj.Parent then obj.Enabled=enabled end end) end
        for _,obj in ipairs(s.parked) do safe(function() obj.Parent=Lighting end) end
        if s.skySaved then
            for key,value in pairs(s.skySaved) do safe(function() if s.sky.Parent then s.sky[key]=value end end) end
        end
    end
    local function activate()
        if state.active or state.closed then return end
        local s={owned={},saved={},post={},parked={},startup=0,dark=0,coronaReady=false}
        state.session=s
        local ok,err=xpcall(function()
            local function keep(obj) table.insert(s.owned,obj);return obj end
            for _,key in ipairs({"ClockTime","GeographicLatitude","Brightness","Ambient","OutdoorAmbient","ExposureCompensation",
                "ColorShift_Top","ColorShift_Bottom","GlobalShadows","ShadowSoftness","EnvironmentDiffuseScale","EnvironmentSpecularScale"}) do s.saved[key]=Lighting[key] end
            for _,obj in ipairs(Lighting:GetChildren()) do
                if obj:IsA("Atmosphere") then table.insert(s.parked,obj);obj.Parent=nil
                elseif obj:IsA("PostEffect") then s.post[obj]=obj.Enabled;obj.Enabled=false end
            end
            suppressCamera(workspace.CurrentCamera,s)
            s.sky=Lighting:FindFirstChildOfClass("Sky")
            if s.sky then s.skySaved={CelestialBodiesShown=s.sky.CelestialBodiesShown,SunAngularSize=s.sky.SunAngularSize,MoonAngularSize=s.sky.MoonAngularSize}
            else s.sky=keep(make("Sky",{Name="HzEclipseSky"},Lighting)) end
            s.sky.CelestialBodiesShown=true;s.sky.SunAngularSize=0;s.sky.MoonAngularSize=0
            Lighting.ClockTime=CONFIG.ClockTime;Lighting.GeographicLatitude=CONFIG.Latitude;Lighting.GlobalShadows=true
            s.direction=Lighting:GetSunDirection().Unit
            s.orbit=s.direction:Cross(Vector3.new(0,1,0)).Unit
            s.atmosphere=keep(make("Atmosphere",{Name="HzEclipseAtmosphere",Density=0.16,Offset=0.25,Haze=0.65,Glare=0},Lighting))
            s.grade=keep(make("ColorCorrectionEffect",{Name="HzEclipseGrade"},Lighting))
            s.bloom=keep(make("BloomEffect",{Name="HzEclipseBloom",Intensity=0.18,Size=36,Threshold=1.2},Lighting))
            s.rays=keep(make("SunRaysEffect",{Name="HzEclipseNaturalRays",Intensity=0.04,Spread=0.84},Lighting))
            s.folder=keep(make("Folder",{Name="HzEclipseBodies"},workspace))
            local cam=workspace.CurrentCamera
            local origin=cam and cam.CFrame.Position or Vector3.new(0,0,0)
            local angular=math.rad(CONFIG.SunDegrees/2)
            local function sphere(name,distance,radius,material,tint)
                return make("Part",{Name=name,Shape=Enum.PartType.Ball,Anchored=true,CanCollide=false,CanTouch=false,CanQuery=false,
                    CastShadow=false,Material=material,Color=tint,Reflectance=0,Transparency=1,
                    Size=Vector3.new(radius*2,radius*2,radius*2),Position=origin+s.direction*distance},s.folder)
            end
            s.sun=sphere("SolarBody",CONFIG.SunDistance,CONFIG.SunDistance*math.sin(angular),Enum.Material.Neon,rgb(255,247,225))
            s.moon=sphere("LunarBody",CONFIG.MoonDistance,CONFIG.MoonDistance*math.sin(angular*1.024),Enum.Material.SmoothPlastic,rgb(0,0,0))
            -- Optional corona only; failure here cannot hide the physical bodies.
            local diameter=2*CONFIG.SunDistance*math.tan(angular)
            s.board=keep(make("BillboardGui",{Name="HzEclipseCorona",Adornee=s.sun,AlwaysOnTop=false,LightInfluence=0,MaxDistance=0,
                Size=UDim2.fromScale(diameter*2.4,diameter*2.4),ZIndexBehavior=Enum.ZIndexBehavior.Sibling},playerGui))
            safe(function() s.board.Brightness=1.7 end)
            s.corona=make("ImageLabel",{Name="SoftCorona",BackgroundTransparency=1,Size=UDim2.fromScale(1,1),ImageTransparency=1},s.board)
            requestTexture("corona",512,function(asset)
                if state.session==s and not state.closed then s.coronaReady=applyAsset(s.corona,asset,false) end
            end)
            state.elapsed=0;state.paused=false;state.active=true
            if CONFIG.FocusOnActivation then focusSun() end
        end,debug.traceback)
        if not ok then deactivate();warn("HzReyzn Eclipse could not activate: "..tostring(err)) end
    end

    -- Penta black / silver UI. A moving gradient is confined to the glass layer.
    local W, H, MINI = 332, 340, 68
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
    local phaseLabel = label(body, "ECLIPSE OFF", 18, 12, 238, 19, 11, rgb(190, 190, 198), Enum.Font.GothamMedium)
    local percent = label(body, "0%", 251, 9, 63, 26, 22, nil, Enum.Font.GothamBold)
    percent.TextXAlignment = Enum.TextXAlignment.Right
    local track = make("Frame", {Position = UDim2.fromOffset(18, 43), Size = UDim2.fromOffset(W-36, 4), BackgroundColor3 = rgb(52, 52, 57), BorderSizePixel = 0}, body)
    corner(track)
    local fill = make("Frame", {Size = UDim2.fromScale(0, 1), BackgroundColor3 = rgb(240, 240, 245), BorderSizePixel = 0}, track)
    corner(fill)
    local timeLabel = label(body, "00:00 / 01:32", 18, 52, 172, 15, 10, rgb(133, 133, 142))
    local modeLabel = label(body, "MANUAL", 190, 52, 124, 15, 10, rgb(133, 133, 142))
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
    local activateButton = button(body, "Activate", "ACTIVATE ECLIPSE", 18, 78, 296, 33, true)
    local pause = button(body, "Pause", "PAUSE", 18, 120, 94, 31)
    local restart = button(body, "Restart", "RESTART", 119, 120, 94, 31)
    local speed = button(body, "Speed", "SPEED  1x", 220, 120, 94, 31)
    local raysButton = button(body, "Rays", "RAYS  NATURAL", 18, 160, 144, 31)
    local hdButton = button(body, "HD", "HD  PREPARING", 170, 160, 144, 31)
    local focusButton = button(body, "FocusSun", "VIEW ECLIPSE", 18, 200, 194, 33)
    local loopButton = button(body, "Loop", "LOOP  ON", 220, 200, 94, 33)
    local hint = label(body, "Press ACTIVATE ECLIPSE to begin", 18, 244, 296, 14, 10, rgb(117, 117, 127))
    local minimize = button(panel, "Minimize", "−", W-78, 20, 27, 27)
    local close = button(panel, "Close", "×", W-43, 20, 27, 27)
    close.TextSize = 18; minimize.TextSize = 18


    connect(close.Activated,cleanup)
    connect(activateButton.Activated,function()
        if state.active then deactivate() else activate() end
    end)
    connect(pause.Activated,function() if state.active then state.paused=not state.paused end end)
    connect(restart.Activated,function()
        if state.active then state.elapsed=0;state.paused=false end
    end)
    connect(focusButton.Activated,function() if state.active then focusSun() end end)
    connect(speed.Activated,function()
        state.speed=state.speed==1 and 2 or (state.speed==2 and 0.5 or 1)
        speed.Text="SPEED  "..tostring(state.speed).."x"
    end)
    connect(raysButton.Activated,function()
        state.rays=state.rays==1 and 1.45 or (state.rays==1.45 and 0.5 or 1)
        raysButton.Text="RAYS  "..(state.rays==1 and "NATURAL" or (state.rays==1.45 and "STRONG" or "SOFT"))
    end)
    connect(loopButton.Activated,function()
        state.loop=not state.loop;loopButton.Text=state.loop and "LOOP  ON" or "LOOP  OFF"
    end)
    connect(hdButton.Activated,function()
        state.hd=not state.hd
        if state.hd then for part in pairs(watchers) do enqueue(part) end
        else restoreAllDetails() end
    end)
    local function clampPanel()
        local area=gui.AbsoluteSize
        local scale=panelScale.Scale
        local x=math.clamp(panel.Position.X.Offset,4,math.max(4,area.X-W*scale-4))
        local y=math.clamp(panel.Position.Y.Offset,4,math.max(4,area.Y-(state.minimized and MINI or H)*scale-4))
        panel.Position=UDim2.fromOffset(x,y)
    end
    local resizeTween
    connect(minimize.Activated,function()
        state.minimized=not state.minimized
        minimize.Text=state.minimized and "+" or "−"
        if resizeTween then resizeTween:Cancel() end
        resizeTween=TweenService:Create(panel,TweenInfo.new(0.22,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),
            {Size=UDim2.fromOffset(W,state.minimized and MINI or H)})
        resizeTween:Play();clampPanel()
    end)
    local drag
    connect(header.InputBegan,function(input)
        if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then
            drag={input=input,from=input.Position,panel=panel.Position}
        end
    end)
    connect(Input.InputChanged,function(input)
        if not drag then return end
        if input==drag.input or input.UserInputType==Enum.UserInputType.MouseMovement then
            local delta=input.Position-drag.from
            panel.Position=UDim2.fromOffset(drag.panel.X.Offset+delta.X,drag.panel.Y.Offset+delta.Y)
            clampPanel()
        end
    end)
    connect(Input.InputEnded,function(input)
        if drag and (input==drag.input or input.UserInputType==Enum.UserInputType.MouseButton1) then drag=nil end
    end)
    connect(workspace:GetPropertyChangedSignal("CurrentCamera"),function()
        restoreFocus();state.camera=nil
        suppressCamera(workspace.CurrentCamera,state.session)
    end)
    connect(player.CharacterAdded,restoreFocus)
    local function clockText(seconds)
        seconds=math.floor(seconds)
        return string.format("%02d:%02d",math.floor(seconds/60),seconds%60)
    end
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
            f.camera.CFrame=f.from:Lerp(CFrame.lookAt(f.from.Position,f.from.Position+f.direction),smooth(f.time/0.8))
            if f.time>=0.8 then restoreFocus() end
        end

        local covered,phase,inView=0,"ECLIPSE OFF",false
        local s=state.session
        -- OFF never creates celestial objects, changes Lighting, or advances time.
        -- Only the Activate button creates a session. Asset jobs cannot start one.
        if state.active and s then
            if not state.paused then state.elapsed=state.elapsed+dt*state.speed end
            if state.elapsed>=cycle then
                state.elapsed=state.loop and state.elapsed%cycle or cycle
            end
            local x
            x,phase=phaseAt(state.elapsed);covered=coverage(x)
            local total=smooth((covered-0.94)/0.06)
            local contact=math.exp(-((math.abs(x)-0.075)/0.055)^2)
            s.startup=math.min(1,s.startup+dt)
            local entrance=smooth(s.startup)
            s.dark=damp(s.dark,covered^1.85,4,dt)
            local dark=s.dark

            Lighting.ClockTime=CONFIG.ClockTime;Lighting.GeographicLatitude=CONFIG.Latitude
            local function number(key,target) Lighting[key]=mix(s.saved[key],target,entrance) end
            local function tint(key,target) Lighting[key]=s.saved[key]:Lerp(target,entrance) end
            number("Brightness",mix(2.15,0.85,dark))
            number("ExposureCompensation",mix(0.03,-0.08,dark))
            number("ShadowSoftness",mix(0.25,0.42,dark))
            number("EnvironmentDiffuseScale",mix(0.78,0.70,dark))
            number("EnvironmentSpecularScale",mix(0.80,0.72,dark))
            tint("Ambient",rgb(96,94,96):Lerp(rgb(70,77,94),dark))
            tint("OutdoorAmbient",rgb(148,143,137):Lerp(rgb(112,119,136),dark))
            tint("ColorShift_Top",rgb(7,4,1):Lerp(rgb(0,2,6),dark))
            tint("ColorShift_Bottom",rgb(0,0,0))
            s.atmosphere.Color=rgb(221,216,203):Lerp(rgb(147,159,183),dark)
            s.atmosphere.Decay=rgb(145,135,126):Lerp(rgb(87,99,126),dark)
            s.atmosphere.Density=mix(0.16,0.19,dark)
            s.atmosphere.Haze=mix(0.65,0.95,dark)
            s.grade.TintColor=rgb(255,251,243):Lerp(rgb(232,239,255),dark)
            s.grade.Saturation=mix(-0.015,-0.12,dark)*entrance
            s.grade.Contrast=mix(0.025,0.055,dark)*entrance
            s.grade.Brightness=0
            s.bloom.Intensity=(0.16+0.06*contact+0.05*total)*entrance
            s.rays.Intensity=(0.045*(1-covered)^1.2+0.025*contact)*state.rays*entrance

            -- Real world geometry: nearer buildings, terrain and avatars occlude
            -- these bodies with Roblox's depth buffer. No full-screen eclipse.
            local origin=cam.CFrame.Position
            local offsetAngle=x*math.rad(CONFIG.SunDegrees/2)
            local lunarDirection=(s.direction*math.cos(offsetAngle)+s.orbit*math.sin(offsetAngle)).Unit
            s.sun.Position=origin+s.direction*CONFIG.SunDistance
            s.moon.Position=origin+lunarDirection*CONFIG.MoonDistance
            s.sun.Transparency=1-entrance
            s.moon.Transparency=1-entrance*smooth((2.25-math.abs(x))/0.18)
            local projection=cam:WorldToViewportPoint(s.sun.Position)
            inView=projection.Z>0 and projection.X>-view.Y*0.4 and projection.X<view.X+view.Y*0.4
                and projection.Y>-view.Y*0.4 and projection.Y<view.Y*1.4
            s.board.Enabled=projection.Z>0
            s.corona.ImageTransparency=s.coronaReady and 1-math.clamp((0.008+0.82*total+0.08*contact)*entrance,0,1) or 1
        end

        sheen.Offset=Vector2.new(((os.clock()%8)/8)*2.6-1.3,0)
        state.uiClock=state.uiClock+dt
        if state.uiClock>=0.1 then
            state.uiClock=0
            activateButton.Text=state.active and "DEACTIVATE ECLIPSE" or "ACTIVATE ECLIPSE"
            pause.Text=state.paused and "RESUME" or "PAUSE"
            phaseLabel.Text=state.paused and phase.."  /  PAUSED" or phase
            percent.Text=string.format("%d%%",math.floor(covered*100+0.5))
            fill.Size=UDim2.fromScale(state.active and state.elapsed/cycle or 0,1)
            timeLabel.Text=clockText(state.elapsed).." / "..clockText(cycle)
            modeLabel.Text=state.active and (state.paused and "PAUSED" or "RUNNING") or "MANUAL START"
            pause.TextTransparency=state.active and 0 or 0.55
            restart.TextTransparency=state.active and 0 or 0.55
            focusButton.TextTransparency=state.active and 0 or 0.55
            hdButton.Text=not state.hd and "HD  OFF" or (not state.detailReady and "HD  PREPARING"
                or (state.detailAsset and "HD  ON" or "BASIC SURFACES"))
            if not state.active then
                hint.Text=state.detailReady and state.hd and not state.detailAsset
                    and "HD image unavailable on this client" or "Press ACTIVATE ECLIPSE to begin"
            else hint.Text=inView and "Drag header to move  /  Close to restore" or "Tap VIEW ECLIPSE to find the Sun" end
        end
    end
    RunService:BindToRenderStep(bindName,Enum.RenderPriority.Camera.Value+1,function(dt)
        local ok,err=xpcall(function() render(dt) end,debug.traceback)
        if not ok then cleanup();warn("HzReyzn Eclipse stopped safely: "..tostring(err)) end
    end)
end

local ok,err=xpcall(start,debug.traceback)
if not ok then cleanup();warn("HzReyzn Eclipse could not load: "..tostring(err)) end
