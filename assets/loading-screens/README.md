# Loading Screens — HzReyzn Hub

Recreation of the supplied Roblox loading-screen video with the background and transparent metallic wordmark embedded directly in the Lua file.

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

## Embedded images

| Image | Embedded format |
| --- | --- |
| Supplied character background | JPEG, 1536×864, 397,876 bytes |
| Previously prepared transparent wordmark | PNG with alpha, 1672×941, 1,275,038 bytes |

The script contains both images as Base64 data. It reconstructs and verifies the files locally, then displays them with `getcustomasset` or `getsynasset`. It does not request Roblox image IDs or download images separately from GitHub. The script itself is approximately 2.3 MB because the images are included.

The uploaded background has a `.png` filename but contains JPEG bytes. The first implementation incorrectly required a PNG signature. This revision uses the actual JPEG format and a `.jpg` cache filename. The prepared transparent wordmark is a genuine PNG. Size, magic bytes and an Adler-32 checksum validate decoded files and cached copies before use. Invalid cached files are rebuilt.

Native Base64 decoding is optional; a portable decoder is included. Once a local image is registered, it can render without waiting for `IsLoaded` or a successful `PreloadAsync` callback. This prevents clients with incomplete local-image status reporting from keeping images transparent. The animation timer runs independently.

This manual-image version requires a client providing `writefile` and `getcustomasset` or `getsynasset`. It checks the caller environment and `getgenv` for these APIs. Unsupported clients display `Images unavailable in this client` and report the reason in the console; the completion and dismissal controls still work. These file APIs are not provided by a standard Roblox Studio LocalScript.

The ScreenGui's `Build` attribute is `manual-images-r3`. Per-image status attributes and the returned handle's `GetImageErrors()` function are available for diagnosis.

## Validation

The delivered Lua source passed syntax checks and a deterministic mock of the client APIs. The mock executed the real embedded-image decoder and wrote both files; their SHA-256 hashes matched the source bytes exactly, and both files passed image parsing. Tests covered local-image registration, missing or failed preload status, cache reuse and repair, `getsynasset`, APIs supplied through `getgenv`, invalid native Base64 output, missing APIs, and write failures. Existing timing, input gating, dismissal, frame animation, duplicate execution and layout checks also passed.

These are simulated checks. The script has not been executed in the Roblox client or Roblox Studio in this environment.
