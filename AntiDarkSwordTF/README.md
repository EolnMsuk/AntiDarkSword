# AntiDarkSword ⚔️ — TrollFools / TrollStore

A standalone `.dylib` build of AntiDarkSword for **TrollFools** and **TrollStore** users. No jailbreak required — inject it per-app directly from TrollFools to harden that app's WebKit engine against 1-click and browser-based exploits.

> **This is not the full tweak.** See the [main README](../README.md) for the jailbreak version, which adds daemon-level iMessage zero-click mitigations and the Corellium Honeypot on top of everything here.

---

## ✨ What it protects

Injected per-app. All mitigations apply only inside the app you injected into.

| Mitigation | Default | Notes |
|---|---|---|
| **Spoof User Agent** | ON | Masks browser fingerprint used by DarkSword & Coruna to profile targets |
| **Block JIT** | ON | iOS 16+: sets `lockdownModeEnabled = YES` **and** `_WKProcessPoolConfiguration.JITEnabled = NO` (dual-path). iOS 15: `JITEnabled = NO` only |
| **Block JavaScript** | OFF | Breaks most apps — opt in explicitly. Enabling JS block auto-enables JIT block |
| **Block Media Autoplay** | OFF | Stops drive-by audio/video loading inside WebViews |
| **Block WebGL & WebRTC** | OFF | Disables GPU and peer-connection APIs used by some exploit kits |
| **Block `file://` Access** | OFF | Prevents local file exfiltration via WebView |
| **Block Remote Content** | OFF | Blocks all external `http`/`https` resource loads (images, scripts, fonts, media) via `WKContentRuleList`. Strongly recommended for Mail.app — removes the primary zero-click attack surface in HTML email rendering |

---

## 🚫 What's NOT included vs. the jailbreak version

The dylib is sandboxed to the injected app and has no system-level access. These features require a jailbreak:

| Feature | Jailbreak | TrollFools |
|---|---|---|
| iMessage zero-click blocking (`imagent`, `IMDPersistenceAgent`) | ✅ | ❌ — TrollFools cannot inject into system daemons; `IMFileTransfer` hooks are intentionally absent from this build. **Mail.app** (`com.apple.mobilemail`) is a valid TrollFools target — the WebKit hooks harden HTML email rendering. Use "Block Remote Content" in the overlay to block external resource loads in HTML emails as a zero-click mitigation |
| Corellium Honeypot (file-path spoofing + `corelliumd` process) | ✅ | ❌ — needs POSIX hook installation and LaunchDaemon |
| System-wide auto-protection tiers (Level 1/2/3) | ✅ | ❌ — no PreferenceLoader; settings are per-app in-overlay |
| Settings.app preferences UI | ✅ | ❌ — replaced by in-app three-finger double-tap overlay |
| MobileSubstrate / ElleKit | required | ❌ — not used; hooks use the ObjC runtime directly (`LOGOS_DEFAULT_GENERATOR = internal`) |
| Protects all apps at once | ✅ | ❌ — you inject per-app via TrollFools |

---

## 📱 Requirements

- **TrollStore 2** installed on your device ([opa334/TrollStore](https://github.com/opa334/TrollStore))
- **TrollFools** installed via TrollStore ([Lessica/TrollFools](https://github.com/Lessica/TrollFools))
- iOS **14.5 – 17.0** (arm64 / arm64e) — exact device support depends on your TrollStore install method (see [Device Compatibility](#-device-compatibility) below)
- The target app must be a **third-party App Store app** — Apple system apps cannot be injected by TrollFools

---

## 🛠️ Installation

1. Install [TrollStore](https://github.com/opa334/TrollStore) on your device.
2. Install [TrollFools](https://github.com/Lessica/TrollFools/releases) via TrollStore.
3. Download `AntiDarkSword.dylib` from [Latest Release](https://github.com/EolnMsuk/AntiDarkSword/releases).
4. Open **TrollFools**, find the app you want to protect, tap **+**, and select the `.dylib`.
5. TrollFools re-signs and relaunches the app with the dylib injected.

To **remove**: open TrollFools, tap the app, and remove the dylib entry.

---

## ⚙️ Configuration (In-App Overlay)

There is no Settings.app UI for the TrollFools build. Settings are configured inside each injected app:

**Double-tap with three fingers** anywhere on screen → the AntiDarkSword overlay appears.

The overlay shows:
- **Enable Protection** master toggle (defaults OFF — tap to activate). The row background is **green** when protection is ON and **red** when OFF, making the active state immediately obvious at a glance.
- Per-feature toggles for UA spoof, JIT, JS, media, WebRTC, file access, and **Block Remote Content**
- **Save & Restart** — writes settings and prompts to restart the app so WebKit picks up the new configuration

> Settings are saved per-app. Each injected app stores its own configuration. If you inject into five apps, each has independent toggle states.

**First launch behavior:** Protection is OFF by default. Open the overlay, enable protection, configure what you want, and save. UA spoofing and JIT blocking are pre-checked as sensible defaults when you first enable protection.

**JS + JIT coupling:** Enabling "Block JavaScript" automatically forces "Block JIT" on and locks it. Disabling JS unlocks JIT so you can control it independently. This matches the jailbreak version's behavior.

---

## 🔒 Should I jailbreak instead?

If your device and iOS version support a jailbreak, the full tweak gives meaningfully stronger protection:

- iMessage zero-click mitigation (blocking at `imagent` and `IMDPersistenceAgent` before content reaches any UI)
- Corellium Honeypot causing advanced payloads to self-abort
- System-wide auto-protection across all apps in one configuration
- Settings.app UI with per-app and per-feature granular control

Use TrollFools when you cannot or do not want to jailbreak, or when you want surgical per-app hardening without touching the rest of the system.

---

## 📲 Device Compatibility

### TrollStore (no jailbreak)

TrollStore's availability depends on which exploit method is available for your device and iOS version. Consult the [TrollStore README](https://github.com/opa334/TrollStore) for the current install method for your specific device.

| iOS Range | Architecture | TrollStore Status |
|---|---|---|
| 14.0 – 14.8.1 | arm64, arm64e | ✅ Supported |
| 15.0 – 16.6.1 | arm64, arm64e | ✅ Supported |
| 16.7.x | arm64 (A12+) | ⚠️ Limited — check TrollStore docs |
| 17.0 | arm64e (select devices) | ⚠️ Limited — check TrollStore docs |
| 17.1+ | all | ❌ Not supported (as of this writing) |

> Check [TrollStore](https://github.com/opa334/TrollStore) directly — supported iOS versions expand as new exploits are found.

### Jailbreak (full tweak)

For users who can jailbreak and want the complete protection stack:

| Jailbreak | Type | Supported iOS |
|---|---|---|
| **Dopamine (2)** | Rootless/hide | 15.0 – 16.6.1 |
| **Palera1n** | Rootless/ful | 15.0 – 17.x |
| **meowbrek2** | Rootless | 15.0 – 15.8.3 |
| **NekoJB** | Rootless | 15.0 – 15.8.3 |
| **XinaA15** | Hybrid | 15.0 – 15.1.1 |
| **checkra1n** | Rootful | 14.5 – 14.8.1 |
| **Taurine** | Rootful | 14.5 – 14.8.1 |
| **unc0ver** | Rootful | 14.5 – 14.8 |

Install the full `.deb` from [Latest Release](https://github.com/EolnMsuk/AntiDarkSword/releases) via Sileo or Zebra, or add the repo: `https://f0rd0w.github.io/`

---

## 🏗️ Building

Requires [Theos](https://theos.dev/) with `$THEOS` set.

```sh
# From the repo root:
make -f Makefile.trollfools

# Output:
# .theos/obj/AntiDarkSwordTF/AntiDarkSword.dylib
```

The dylib uses `LOGOS_DEFAULT_GENERATOR = internal` — no CydiaSubstrate or ElleKit is linked. The `TROLLFOOLS_BUILD=1` preprocessor flag gates any jailbreak-only code paths in shared headers.

---

## 👨‍💻 Developer

Created by: [EolnMsuk](https://github.com/EolnMsuk) / [AntiDarkSword](https://github.com/EolnMsuk/AntiDarkSword/)

Support my work: [Venmo](https://venmo.com/user/eolnmsuk)
