# Loading Screens — HzReyzn Hub

Recreation of the supplied Roblox loading-screen video using the background and metallic wordmark asset IDs supplied by hzReyzn.

## Run

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/hzReyzn/crazy/main/Loading%20Screens.lua"))()
```

The linked script is a **client-side visual intro**. Its progress bar is a fixed five-second animation, not a measurement of Roblox game loading.

## Timing

| Event | Behavior |
| --- | --- |
| Appearance | Smooth 0.3-second fade-in |
| Progress | 0–100% in 5 seconds, starting after the appearance |
| Completion | `Loading completed`, 100%, and a click/tap prompt |
| Completion effect | Soft 10%-opacity flash, wordmark splash and two expanding rings, first at 100% and then every 3 seconds |
| Dismissal | Click/tap anywhere on the loading screen after completion |
| Exit | All visible elements fade over 2.1 seconds |

Clicks before completion are ignored. Completion never dismisses the screen automatically. Multiple clicks cannot restart the exit. Running the script again disposes of its previous screen, animation connection and pending image jobs.

The interface includes a thicker violet/blue/pink outline and a broad glow that fades inward, with a narrower luminous core, travelling edge lights, and two soft inward waves synchronized with completion pulses. The edge glow gently breathes and expands during each pulse. Fine orbit rings, floating glints, particles, a travelling highlight on the bar and a small depth effect complete the interface. Layout adapts to desktop, mobile landscape and portrait.

## Images

| Image | Roblox asset ID |
| --- | --- |
| Background | `89640728908311` |
| Logo/text | `80679809117691` |

Both ImageLabels receive their native `rbxassetid://` values when constructed. The script no longer requires `getcustomasset`, `writefile`, or GitHub image downloads, and does not substitute a generic text wordmark. The PNG files in this folder remain source references; the running script uses the Roblox IDs above.

Native preloading and decoding run independently of the intro timer. A successful preload callback or `IsLoaded` enables the short image fade-in. Slow or failed asset loading cannot hold the bar below 100%; failed asset fetches are reported in the console. The IDs must be available to the Roblox experience where the script runs.

For **Roblox Studio**, place the code in a LocalScript under StarterPlayerScripts. The supplied image IDs are already configured at the top of the script.

## Validation

The delivered Lua source passed syntax checks and a deterministic mock of the client APIs. Checks covered the exact native IDs, successful and failed preloads, operation without local file/image APIs, 60/30/15-FPS timelines, early and repeated clicks, the 3-second flash interval, the 2.1-second exit, repeated execution, stalled preloading, moving edge lights and inward waves. Layout bounds were checked at 1920×1080, 2400×1080, 844×390, 390×844 and 320×568.

These are simulated checks. The script has not been executed in the Roblox client or Roblox Studio in this environment.
