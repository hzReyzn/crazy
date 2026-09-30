# Loading Screens — HzReyzn Hub

Recreation of the supplied Roblox loading-screen video with the supplied character background and a transparent version of the metallic wordmark.

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

The interface includes a violet/blue/pink animated frame, fine orbit rings, floating glints, subtle particles, a travelling highlight on the bar and a small depth effect. Layout adapts to desktop, mobile landscape and portrait.

## Images

`background.png` is the supplied 1536×864 character image. `logo.png` is the supplied metallic text prepared as a transparent cutout using the image-editing tool, preserving the wordmark's appearance. Images are cached locally in clients that support `getcustomasset` (or `getsynasset`) and `writefile`. The script does not attempt to use a raw GitHub URL directly as a Roblox ImageLabel asset.

Downloads and decoding run independently of the intro timer. On a first run, images can appear later if the connection is slow. A text wordmark remains visible until the logo is decoded. No download or preload can hold the bar below 100%.

For **Roblox Studio**, upload the two PNGs to your experience and enter their Roblox image IDs in `BackgroundAssetId` and `LogoAssetId` at the top of the script. Put the script in a LocalScript under StarterPlayerScripts. GitHub image files alone do not provide Roblox asset IDs.

## Validation

The delivered Lua source passed syntax checks and a deterministic mock of the client APIs. Checks covered 60/30/15-FPS timelines, early clicks, repeated clicks, the 3-second flash interval, the 2.1-second exit, repeated execution, stalled preloading, missing image APIs, and layout bounds at 1920×1080, 2400×1080, 844×390, 390×844 and 320×568.

These are simulated checks. The script has not been executed in the Roblox client or Roblox Studio in this environment.
