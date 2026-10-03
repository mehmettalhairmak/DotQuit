<div align="center">

# DotQuit

**Close the window. Quit the app.**

The zero-bloat menu bar companion that quits macOS apps when their last window closes — so your Dock stays clean and your RAM stays yours.

[![Download DMG](https://img.shields.io/badge/Download-DotQuit.dmg-30B14F?style=for-the-badge&logo=apple&logoColor=white)](https://github.com/mehmettalhairmak/dotquit/releases/latest/download/DotQuit.dmg)
[![Buy License on Polar](https://img.shields.io/badge/License-Buy%20on%20Polar-blue?style=for-the-badge&logo=polar)](https://buy.polar.sh/polar_cl_tfdIyrLDQxAYfrf82gdBeNrCVPXjyA5CqFSO90Eitzf)

[![Platform](https://img.shields.io/badge/platform-macOS%2014.0%2B-000000?logo=apple&logoColor=white)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-5.10%2B-F05138?logo=swift&logoColor=white)](https://swift.org)
[![License](https://img.shields.io/badge/license-GPLv3-0A84FF)](LICENSE)
[![Release](https://img.shields.io/badge/release-v1.0.0-6E56CF)](https://github.com/mehmettalhairmak/dotquit/releases/latest)

</div>

---

## The problem

On macOS, the red **✕** button doesn't quit anything. It closes a window.

The app stays resident — holding its memory, keeping its Dock indicator lit, and quietly waiting for a `⌘Q` that never comes. Open Preview to read one PDF, close it, and it's still there an hour later. Multiply that by a day's work and you have a Dock full of ghosts and a few gigabytes of nothing.

The usual answers are all bad: remember to press `⌘Q` every time, hunt through the Dock periodically, or reach for Activity Monitor.

## The solution

DotQuit watches for the one event that actually matters — a window being destroyed — and asks: *does this app have anything left on screen?*

If the answer is no, it sends the app a normal quit request. Same thing `⌘Q` does. Nothing more violent than that.

```
window destroyed
      ↓
  wait 600ms              ← fullscreen transitions destroy and recreate windows
      ↓
is it a regular GUI app?  ← menu bar items and daemons are never touched
      ↓
is it whitelisted?        ← hold ⌥ to invert this for one close
      ↓
any windows left?         ← on-screen (CoreGraphics) + minimized/hidden (Accessibility)
      ↓
  app.terminate()         ← never kill(9), never force
```

If the app has unsaved work it shows its own **"Save changes?"** sheet. Cancel it and the app stays open — DotQuit respects that and moves on.

---

## Features

**Zero-idle architecture**
No polling loops, no timers, no background scans. DotQuit is driven entirely by `AXObserver` window notifications and `NSWorkspace` lifecycle events. When nothing is happening, nothing runs.

| | Measured |
|---|---|
| Idle CPU | **0.00 s** over 45 s |
| Memory footprint | **~19 MB** (18 MB with telemetry off) |
| Timers while idle | **none** |

**Smart Whitelist flyout**
Hover the whitelist row in the menu bar popover and a panel slides out to the left. Two tiers: everything currently running on top (with the app you were just in pinned first), protected apps below. One click moves an app between them — no window switching, no Settings trip.

Spotify, Slack, WhatsApp, Mail and Telegram are whitelisted out of the box.

**Option (⌥) to invert**
Hold Option while closing a window to flip the decision for that one close: a whitelisted app quits, anything else is spared. Useful for the exception that doesn't deserve a permanent rule.

**Two quitting modes**
- *Last window* (default) — quits only when no windows remain at all, including minimized and hidden ones.
- *Immediate* — quits as soon as nothing is on screen, even with windows parked in the Dock.

Either way, the on-screen window count must be zero. That check is not optional.

**Safety by construction**
- `terminate()` only. No force-kill API is called anywhere in the codebase.
- Only `.regular` desktop apps are considered — `.accessory` menu bar items and `.prohibited` daemons are never observed, let alone quit.
- Finder, Dock, loginwindow and SystemUIServer are permanently exempt.
- Statistics only count an app once it has actually exited, so a cancelled save sheet never inflates the numbers.

**Native settings**
A real System Settings-style window: sidebar with search, behavior, whitelist, license, shortcuts and permissions, appearance, and general. Light and dark both supported. Global toggle shortcut defaults to `⌥⇧Q`.

**Pro licensing**
A 7-day trial, then a one-time **$2.99** lifetime license covering **2 Macs**. Activation runs through [Polar.sh](https://polar.sh) and is bound to the machine's hardware UUID, so reinstalling doesn't burn a seat. Deactivating releases the seat back. Keys live in the macOS Keychain, and DotQuit keeps working offline once activated.

---

## Installation

There are three ways to get DotQuit. They are independent — pick whichever suits you.

### 1. Download the notarized DMG — the easy path

[**⬇ Download DotQuit.dmg**](https://github.com/mehmettalhairmak/dotquit/releases/latest/download/DotQuit.dmg)

1. Open the DMG and drag **DotQuit.app** into **Applications**.
2. Launch it. DotQuit lives in the menu bar — there's no Dock icon by default.
3. Grant Accessibility access (see below).

The build is signed with a Developer ID and notarized by Apple, so it opens without Gatekeeper warnings — no right-click-Open dance, no `xattr` incantations.

### 2. Buy a license — support the project

[**Get a lifetime license on Polar — $2.99**](https://buy.polar.sh/polar_cl_tfdIyrLDQxAYfrf82gdBeNrCVPXjyA5CqFSO90Eitzf)

One payment, two Macs, every future update. Activate under **Settings → License**, or paste the key from your Polar receipt.

The source is GPLv3 and the app runs without a license during the 7-day trial — buying one funds the notarized builds and continued development rather than unlocking the code. See [License](#license).

### 3. Build from source — free, always

Everything you need is in this repository. Jump to [Building from source](#building-from-source).

### Granting Accessibility access

DotQuit cannot see window events without it. On first launch macOS will prompt; if you miss it:

**System Settings → Privacy & Security → Accessibility → enable DotQuit**

The Shortcuts & Permissions pane shows live status and has a button that takes you straight there. Until access is granted, the menu bar icon stays dimmed and DotQuit does nothing.

> Accessibility is a TCC permission, not an entitlement. DotQuit uses it to observe *when* windows open and close — never what is inside them.

### Using it

| Action | How |
|---|---|
| Open the popover | Click the dot in the menu bar |
| Whitelist an app | Hover **Smart Whitelist** → click `+` |
| Spare one app, once | Hold `⌥` while closing its window |
| Pause for an hour | **Pause for 1 Hour** in the popover |
| Toggle DotQuit | `⌥⇧Q` (configurable) |
| Open settings | `⌘,` |

---

## Building from source

**Prerequisites** — macOS 14.0 or newer, Xcode 16 or newer (built and tested on Xcode 27). Swift 5 language mode; no extra tooling required.

```bash
git clone https://github.com/mehmettalhairmak/DotQuit.git
cd DotQuit
open DotQuit.xcodeproj
```

Dependencies resolve automatically through Swift Package Manager — [TelemetryDeck](https://github.com/TelemetryDeck/SwiftClient), pinned in `Package.resolved`. Then just build and run.

### Packaging a release

```bash
./Scripts/build-release.sh                  # universal build -> ./dist
./Scripts/build-release.sh --sign           # + Developer ID signing
./Scripts/build-release.sh --notarize       # + notarization and stapling
```

The script builds a universal `arm64 + x86_64` binary, stages it in `./dist`, and zips it. Without `--sign` it prints the exact signing and notarization commands it would run, so the pipeline can be reviewed before any credentials exist. Set `DEVELOPER_ID_APP` and `NOTARY_PROFILE` first.

> **DotQuit must not be sandboxed.** The accessibility APIs it depends on — cross-process `AXObserver`, `AXUIElementCopyAttributeValue`, and `NSRunningApplication.terminate()` — are all blocked inside a sandbox container. It ships as a hardened-runtime, Developer ID app with a deliberately minimal entitlements file.

### Project layout

```
DotQuit/
├── Core/
│   ├── WindowWatcher.swift      # AXObserver, decision tree, termination
│   ├── WhitelistManager.swift   # exemptions, persisted to UserDefaults
│   ├── PermissionsManager.swift # Accessibility trust
│   ├── LicenseManager.swift     # Polar.sh activation + Keychain
│   ├── AnalyticsManager.swift   # the only file that imports TelemetryDeck
│   └── …
├── Views/
│   ├── MenuBarPopoverView.swift        # the menu bar popover
│   ├── WhitelistFlyoutController.swift # left-anchored NSPanel
│   ├── SettingsView.swift              # System Settings-style window
│   └── …
└── Scripts/build-release.sh
```

---

## Privacy & security

DotQuit observes window *lifecycle events*. It does not and cannot read window contents, text, keystrokes, clipboard, or any app's private data. There is no accessibility tree traversal beyond counting windows and reading their subrole.

**Telemetry** is anonymous, powered by [TelemetryDeck](https://telemetrydeck.com), and can be switched off in **Settings → General → Share anonymous usage diagnostics**. Turning it off doesn't merely mute the SDK — it is never initialized, and nothing is transmitted.

What is sent: five counters (launch, app quit, whitelist add, license activated, Option-invert used) plus the device metadata TelemetryDeck attaches by default. Bundle identifiers of well-known public apps are sent in the clear so the counts are meaningful; **anything else is reduced to a salted SHA-256 digest**, so a private or enterprise app never appears by name.

What is never sent: window titles, file paths, keystrokes, your license key, or any identifier that points back to you. The user identifier is a salted hash computed on-device.

---

## License

DotQuit's source code is free software under the **GNU General Public License v3.0**. The full text is in [`LICENSE`](LICENSE).

That means you may use, study, modify and redistribute the source, and distribute builds you make from it — provided derivative works stay under GPLv3 and ship their corresponding source.

**What the paid license buys.** The code is free; the convenience isn't. A [Polar.sh](https://polar.sh) purchase gets you:

- a **pre-built, Developer ID-signed and notarized** binary that launches without Gatekeeper warnings
- **packaged releases** with release notes, so you don't have to rebuild to stay current
- **support**, and a direct say in what gets built next
- the project's continued development

It is a voluntary exchange, not a restriction. Nothing in the paid license overrides the GPL: if you'd rather clone the repo and build DotQuit yourself, that is explicitly allowed and always will be.

**Third-party code.** [TelemetryDeck SwiftClient](https://github.com/TelemetryDeck/SwiftClient) is MIT-licensed, which is compatible with GPLv3.

## Author

Built by **Mehmet Talha Irmak**.

If DotQuit saves you a few gigabytes and a lot of `⌘Q`, [a lifetime license is $2.99](https://buy.polar.sh/polar_cl_tfdIyrLDQxAYfrf82gdBeNrCVPXjyA5CqFSO90Eitzf).
