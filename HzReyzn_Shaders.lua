-- Compatibility entry for existing HzReyzn Hub and standalone links.
-- The current independent controller is S&NC Shaders.
local source = game:HttpGet("https://raw.githubusercontent.com/hzReyzn/crazy/main/SNC_Shaders.lua")
local run, err = loadstring(source)
assert(run, err)
return run()
