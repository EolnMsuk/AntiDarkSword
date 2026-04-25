# AntiDarkSword ⛨

Advanced security tweak and TrollStore dylib for iOS 13–17 that mitigates WebKit RCE and iMessage zero-click exploits (Coruna / DarkSword chains). Reduces attack surface by disabling JIT, restricting JavaScript, blocking attachment auto-download, spoofing user agents, and isolating sensitive system daemons. Includes a Corellium-based honeypot that causes advanced payloads to detect a "safe" analysis environment and abort.

---

## Protection Modules

| Module | Mechanism |
|---|---|
| WebKit Hardening | Disables JIT (lockdownMode iOS 16+, pool-config iOS 15), restricts JS at WKPreferences / WKWebpagePreferences / JSEvaluateScript levels, blocks media autoplay, WebRTC, WebGL, file:// access |
| iMessage Protection | Blocks `IMFileTransfer` auto-download at both daemon layer (imagent / IMDPersistenceAgent) and UI layer (MobileSMS); blocks `CKAttachmentMessagePartChatItem` preview generation |
| Browser Isolation | WKContentRuleList remote-content blocker (TrollFools); per-app UA spoof covering `navigator.userAgent`, `navigator.platform`, `navigator.vendor`, `navigator.userAgentData` (Client Hints) |
| System Daemon Filtering | AntiDarkSwordDaemon injects into imagent, apsd, identityservicesd, IMDPersistenceAgent via MobileSubstrate |
| Corellium Honeypot | `corelliumd` LaunchDaemon holds the `/usr/libexec/corelliumd` path on rootful; POSIX hooks (access/stat/lstat/NSFileManager) spoof the path on rootless; probe counter written async to avoid apsd/cfprefsd deadlock |

### Auto-Protect Levels

| Level | Scope |
|---|---|
| 1 — Baseline | Apple first-party: Safari, Messages, Mail, Notes, News, and associated XPC services |
| 2 — Extended | Adds third-party browsers, messengers (Signal, Telegram, WhatsApp, Discord…), social, and financial apps |
| 3 — Maximum | Full Level 2 coverage + system daemons (imagent, apsd, identityservicesd, IMDPersistenceAgent) + Corellium honeypot |

Per-target rule overrides (`TargetRules_<bundleID>`) take precedence over level defaults. Custom bundle IDs and process names can be added manually via the Settings UI.

---

## Compatibility

| Package | Jailbreak type | iOS range | Arch |
|---|---|---|---|
| `modern_iphoneos-arm64.deb` | Rootless (Dopamine, palera1n rootless, NathanLR) | iOS 15+ | arm64 arm64e |
| `modern_iphoneos-arm.deb` | Rootful (palera1n fakefs) | iOS 15+ | arm64 arm64e |
| `legacy_iphoneos-arm.deb` | Rootful (unc0ver, Taurine, checkra1n, Odyssey) | iOS 13–14 | arm64 |
| `TrollFools.dylib` | TrollFools / TrollStore (no jailbreak) | iOS 14+ | arm64 arm64e |

**TrollFools mode limitations:** no daemon-layer hooks (imagent/apsd require jailbreak); JSEvaluateScript C-level hook absent; settings accessed via in-app three-finger double-tap overlay.

---

## Prerequisites

- [Theos](https://theos.dev/docs/installation) installed with `$THEOS` set
- **Modern builds:** `iPhoneOS16.5.sdk` at `$THEOS/sdks/`
- **Legacy build:** `iPhoneOS14.5.sdk` at `$THEOS/sdks/`
- `AltList.framework` in `vendor/` must match the target (see [Vendor Frameworks](#vendor-frameworks))

Patched SDKs: `https://github.com/theos/sdks/releases`

---

## Building

### Single target (manual)

Before any `make` run, copy the correct AltList variant into `vendor/AltList.framework` (see [Vendor Frameworks](#vendor-frameworks)).

```sh
# Modern rootless (iOS 15+, arm64 arm64e)
make package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=rootless \
    SYSROOT=$THEOS/sdks/iPhoneOS16.5.sdk \
    TARGET="iphone:clang:16.5:15.0" ARCHS="arm64 arm64e"

# Modern rootful (iOS 15+, arm64 arm64e)
make package FINALPACKAGE=1 \
    SYSROOT=$THEOS/sdks/iPhoneOS16.5.sdk \
    TARGET="iphone:clang:16.5:15.0" ARCHS="arm64 arm64e"

# Legacy rootful (iOS 13–14, arm64 only)
make package FINALPACKAGE=1 \
    SYSROOT=$THEOS/sdks/iPhoneOS14.5.sdk \
    TARGET="iphone:clang:14.5:13.0" ARCHS="arm64"

# TrollFools standalone dylib (no Substrate dependency)
make -f Makefile.trollfools FINALPACKAGE=1 \
    SYSROOT=$THEOS/sdks/iPhoneOS16.5.sdk \
    TARGET="iphone:clang:16.5:15.0" ARCHS="arm64 arm64e"
# → .theos/obj/AntiDarkSwordTF/AntiDarkSword.dylib

# Debug build (ADSLog → NSLog enabled)
make package DEBUG=1
```

### All targets at once

`build_all.sh` handles the AltList swap, lipo thinning for legacy, all four build targets, and places outputs in `output/`.

```sh
chmod +x build_all.sh
./build_all.sh
```

CI runs the same logic via `.github/workflows/build.yml` on every push to `main`, producing a draft GitHub Release with all four artifacts.

---

## Vendor Frameworks

The `vendor/` directory holds three versions of the [AltList](https://github.com/opa334/AltList) framework, which provides the app-picker UI used in the Settings bundle (`AntiDarkSwordPrefsRootListController`). Theos links whichever copy is named `AltList.framework`; the build scripts swap the correct version into place before each `make` invocation.

| Directory | Purpose |
|---|---|
| `vendor/AltList_New.framework` | Newer AltList build used for **modern iOS 15+** `.deb` targets. Linked against `iPhoneOS16.5.sdk`; ships arm64 + arm64e slices. |
| `vendor/AltList_Old.framework` | Older AltList build required for the **legacy iOS 13–14** `.deb` target. Linked against `iPhoneOS14.5.sdk`; the legacy build step thins it to `arm64`-only via `lipo` before compiling. |
| `vendor/AltList.framework` | The active copy consumed by Theos at build time. Always a replica of either `AltList_New` or `AltList_Old` — never edit this directory directly. The build scripts regenerate it on each run. |

---

## Settings (Jailbreak)

Managed by the `AntiDarkSwordPrefs` PreferenceLoader bundle. Accessible from **Settings → AntiDarkSword**.

- **Enable Protection** — master switch; all hooks are dormant when off
- **Select UA** — preset user-agent list (iPhone, iPad, Android, Windows Edge, macOS) or custom string
- **Preset Rules** — auto-protect level selector (1 / 2 / 3) and Advanced Options sub-menu (global overrides per feature)
- **Custom Rules** — AltList-powered app picker + manual bundle ID / process name entry
- All saves post Darwin notification `com.eolnmsuk.antidarkswordprefs/saved`, triggering live reload in all injected tweaks without respring

## Settings (TrollFools)

Three-finger double-tap anywhere in the target app opens the in-app overlay (`ADSTFSettingsViewController`). Toggle features and tap **Save & Restart** — settings write to the shared prefs plist (jailbroken) or `NSUserDefaults` suite fallback (sandboxed). The app must restart for WebKit configuration changes to take effect.

---

## Preferences Domain

All three tweaks share `com.eolnmsuk.antidarkswordprefs`. Top-level keys:

| Key | Type | Description |
|---|---|---|
| `enabled` | BOOL | Master switch |
| `autoProtectLevel` | Integer (1–3) | Tier of auto-protection |
| `selectedUAPreset` | String | UA preset value or `"CUSTOM"` |
| `customUAString` | String | Manual UA when preset is `CUSTOM` |
| `globalDisableJIT` | BOOL | Force JIT off in all processes |
| `globalDisableJS` | BOOL | Force JS off in all processes |
| `globalDisableMedia` | BOOL | Force media block globally |
| `globalDisableRTC` | BOOL | Force WebRTC/WebGL off globally |
| `globalDisableFileAccess` | BOOL | Force file:// access off globally |
| `globalDisableIMessageDL` | BOOL | Force iMessage DL block globally |
| `globalUASpoofingEnabled` | BOOL | Force UA spoof in all processes |
| `corelliumDecoyEnabled` | BOOL | Enable Corellium honeypot (level 3+) |
| `countersEnabled` | BOOL | Enable probe counter tracking |
| `corelliumProbeCount` | Integer | Running count of Corellium probes detected |
| `restrictedApps-<bundleID>` | BOOL | Per-app toggle from AltList picker |
| `activeCustomDaemonIDs` | Array | Manually added bundle IDs / process names |
| `disabledPresetRules` | Array | Preset targets explicitly disabled by user |
| `TargetRules_<bundleID>` | Dictionary | Per-app feature overrides |

---

## Project Maintainer

**eolnmsuk** — `com.eolnmsuk.antidarksword`
