# HzReyzn Shaders 2.0

The standalone shader controller used by HzReyzn Hub. Running it opens a draggable,
minimizable interface; no lighting or weather starts until a mode is selected.

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/hzReyzn/crazy/main/HzReyzn_Shaders.lua"))()
```

## Modes

- Classic: Noon, Sunrise, Sunset, Night, Rain, Snowfall.
- Real Time: Sunrise → Noon → Sunset → Night, with gradual transitions.
- **Especial Shaders 💎**: Meteor Shower, Starfall, Aurora Sky, Deep Space.
- Meteor Shower and Starfall use luminous, animated streaks in the sky. Aurora Sky
  uses moving curtains. Deep Space includes a spiral galaxy, nebula glow, planets,
  a moon and planetary rings. These are cosmetic local effects.

## Improvements

- Switching modes keeps one environment snapshot and blends from the current
  appearance, avoiding a reset to the game's lighting between selections.
- Noon now uses daytime lighting. Night retains visibility; sunrise and sunset
  keep their distinct colors and smooth interpolation.
- Rain and snow reach their atmospheric settings in 3.5 and 4 seconds. More drops
  spawn near the player, with a maximum footprint of 100 studs.
- Weather movement updates with rendered frames. Rain opacity sequences are
  reused, and snow geometry is lighter. Ground effects and particles use pools.
- Quality can be Low, Balanced or High; touch devices default to Balanced.
- The interface scrolls on short screens and supports touch dragging, minimizing
  and restoring through the HZ button.
- Default or closing restores the original lighting, sky, clouds and post effects.
  Camera replacement, character respawn and re-execution are handled.
- Game post effects added or re-enabled while a shader is active are temporarily
  disabled and their prior enabled state is restored afterward.
- Random weather retains the original 1% check every five seconds while a classic
  sky mode is selected. It can now be switched off; it does not interrupt specials.
- Audio loads asynchronously with a timeout. Switching, muting or closing cancels
  stale playback; missing audio never prevents the visual mode from running.

## Sound

The six original Ogg Vorbis soundscapes in `assets/shaders/` accompany Rain,
Snowfall, Meteor Shower, Starfall, Aurora Sky and Deep Space. Each loops for
12 seconds. The interface includes mute and volume controls.

The raw executable loads these files with `game:HttpGet`, `writefile` and
`getcustomasset` (or `getsynasset`) when those capabilities are available.
It caches only its own `HzReyznShaders_v2_*.ogg` files. If custom assets are
unavailable, the interface reports **Audio unavailable**, and the visuals continue.
The soundscapes provide ambience, not per-meteor synchronized impacts.

For a Studio LocalScript or an environment without custom assets, supply sound IDs
that the experience is permitted to use. The script itself can be pasted into a
LocalScript in `StarterPlayerScripts`; the HTTP/loadstring launcher is not a
standard Roblox LocalScript API.

```lua
-- Optional, before running the standalone source:
local environment = type(getgenv) == "function" and getgenv() or _G
environment.HzReyznShaderOptions = {
    Quality = "Balanced", -- Low / Balanced / High
    Sound = true,
    Volume = 0.3,
    SoundIds = {
        -- ["Aurora Sky"] = "rbxassetid://YOUR_PERMITTED_AUDIO_ID",
        -- ["Deep Space"] = "rbxassetid://YOUR_PERMITTED_AUDIO_ID",
    },
}
```

The returned controller provides `SetMode`, `Default`, `Destroy`, `Show`,
`SetQuality`, `SetSound`, `SetAutoWeather` and `GetState` methods.

## Validation

Checked Lua syntax and exercised all ten selectable effects in a mocked Roblox
runtime, including Real Time, switching, quality levels, ground raycasts, respawn,
camera replacement, newly added effects, audio failure/cancellation, repeated
execution and complete cleanup. All six Ogg files were decoded successfully.

This environment cannot run Roblox or render its lighting. Visual appearance,
device frame rate, texture availability and audio support still need an in-game
check. Roblox graphics settings and the host experience can affect the result.

Reference APIs: [Beam](https://create.roblox.com/docs/reference/engine/classes/Beam),
[Lighting](https://create.roblox.com/docs/reference/engine/classes/Lighting),
[audio assets](https://create.roblox.com/docs/audio/assets).

Made by hzReyzn.
