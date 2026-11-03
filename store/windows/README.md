# Microsoft Store release guide (Space Shooters)

Ship path: **Godot Windows export -> MSIX -> Partner Center**. The game itself
needs no Store-only code: saves use Godot's `user://` (redirected to the app's
private data under MSIX), the Huawei plugins are Android-only and no-op on
Windows, and the game exits cleanly.

## 1. One-time setup

1. Install Godot 4.7 export templates: Editor > Manage Export Templates.
2. Install the Windows SDK (for `makeappx.exe`), or the MSIX Packaging Tool.
3. Export `icon.svg` (project root) to a **1024x1024 PNG** once with any image
   tool and save it as `store/windows/SourceIcon.png`.
4. Reserve the app name in Partner Center and note the **Package/Identity Name**
   and **Publisher** (use the exact strings from your dashboard).

## 2. Build the MSIX

1. In Godot: Project > Export > preset **Windows Desktop** > Export Project.
   Output goes to `../space-shooters-win/` (`.exe` + `.pck`).
2. In PowerShell, from `store/windows/`:
   `.\Build-Msix.ps1 -IdentityName "Your.Name" -Publisher "CN=..." -Version "1.0.1.0"`
3. Test-sideload the MSIX on a clean Windows 10/11 machine (sign with a dev
   cert for local install; Partner Center signs Store submissions for you).
4. Upload the `.msix` to your Partner Center submission.

Notes:

- Bump `-Version` (and the in-game version if you show one) for every upload.
- `runFullTrust` in the manifest is standard for packaged Win32 games; declare
  it when prompted during submission.
- If the game fails to start packaged, first check the export folder runs
  unpackaged - 99% of issues are export issues, not manifest issues.

## 3. Store listing checklist

- **Screenshots**: at least one 1366x768+ capture (use Xbox Game Bar while
  playing the Windows build). Show gameplay, the Hangar, and a boss.
- **Age rating**: complete the IARC questionnaire (a space shooter with no
  graphic content typically lands at Everyone 10+ / PEGI 7 - answer honestly).
- **Privacy policy**: required. This game collects nothing (no accounts, no
  ads/online on Windows, saves stay on-device). Host `PRIVACY.md`'s text as a
  public page (e.g. a GitHub gist) and paste that URL into the listing.
- **Capabilities**: the package declares only `runFullTrust` - no camera, mic,
  or location access to justify.
- **Gamepad**: supported (left stick/D-pad move, A = bomb, Start = confirm/pause)
  in addition to keyboard/mouse/touch - mention it in the description.
- **Certification tips**: the game must launch within ~20 s, never require
  admin, and handle window resize/minimize - all true of this build. Test on
  Windows 10 (17763+) and Windows 11.
