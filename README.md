<img width="1266" height="920" alt="readmeORIG" src="https://github.com/user-attachments/assets/163aa186-5940-4a25-a4bf-e0570d81d795" />

# AntiDarkSword ⚔️ (Rootless / Rootful / Roothide)

AntiDarkSword is an iOS security tweak that hardens vulnerable jailbroken devices against WebKit and iMessage-based exploits (DarkSword & Coruna). It mitigates / spoofs vectors used in 1-click and 0-click attacks while isolating background daemons.

## 🔍 Core Mechanisms

The tweak detects native security restrictions based on the iOS version:
* **iOS 16+:** Disables the JIT compiler by hooking native WebKit (`lockdownModeEnabled`) and ChatKit (`isAutoDownloadable`) logic gates.
* **iOS 15.x:** Disables the JIT compiler via undocumented WebKit `_WKProcessPoolConfiguration` APIs (`JITEnabled`), bridging the gap for devices lacking native Lockdown Mode.

## ✨ Features

* **WebKit Hardening:** Forcibly disables the JIT compiler, inline media auto-playback, Picture-in-Picture, WebGL, WebRTC (peer connections), and local file access in targeted `WKWebView` instances.
* **iMessage Mitigation:** Blocks automatic attachment downloading and previews within IMCore and ChatKit.
* **Corellium Honeypot:** Spoofs a research environment using low-level file hooks and a dummy background process, causing advanced payloads to abort delivery.
* **User Agent Spoofing:** Spoofs the `WKWebView` Custom User Agent to bypass fingerprinting. Includes presets for iOS 18.1, Android Chrome, Windows Edge, macOS.
* **Granular Controls:** Assign app-specific mitigation rules. 
* **Custom Targeting:** Manually assign rules to custom bundle IDs or background daemons.
* **Global Mitigations:** System-wide kill-switches that indiscriminately apply mitigations to all processes, use with extreme caution.
* **Zero-Crash Architecture:** Web mitigations are isolated from system tasks, preventing hardware DSP deadlocks and memory limit crashes.

## 🛑 Mitigated Exploits

* **Exploit Kits & Spyware:** DarkSword, Coruna, Predator, PWNYOURHOME, Chaos, Operation Triangulation, Hermit.
* **iMessage 0-Clicks:** BLASTPASS (PassKit attachments).
* **CVEs Patched:** CVE-2025-43529, CVE-2024-44308, CVE-2022-42856.

## 📱 Compatibility & Dependencies

* **iOS Versions:** 15.0 – 17.0
* **Architecture:** arm64 / arm64e 
* **Supported Jailbreaks:** * **Rootless:** Dopamine, Palera1n (iOS 15.0 – 16.7.x)
  * **Rootful:** Palera1n, XinaA15 (iOS 15.0 – 16.7.x)
  * **Roothide:** Dopamine Roothide 2 
* **Dependencies:** `mobilesubstrate` (or `ElleKit`), `preferenceloader`, `altlist`.

## 🛠️ Installation

**Rootless & Rootful Installation:**
1. Download the appropriate `.deb` (`-Rootless.deb` or `-Rootful.deb`) from the **[Releases](https://github.com/EolnMsuk/AntiDarkSword/releases)** page.
2. Install via Sileo, Zebra, or Filza.
3. Respring.

**Roothide Installation:**
1. Download the `-Rootless.deb` from the **[Releases](https://github.com/EolnMsuk/AntiDarkSword/releases)** page.
2. Open the **Roothide Patcher** app and select the `.deb` to convert paths.
3. Install the generated `-roothide.deb` via Sileo or Filza.
4. Respring.

## ⚙️ Configuration

Configure mitigations via the native **Settings** app. 

> [!WARNING]  
> Remove protected apps from Roothide's Blacklist / Choicy to ensure the tweak can successfully inject. Level 3 restricts critical background daemons; lower the tier if system instability occurs.

### Protection Tiers

```text
Level 1
├── 🌐 Safari & Safari View Services
│   ├── OS Baseline (JIT/JS Lockdown)
│   └── Spoof User Agent: ON
│
├── 💬 Apple Messages (MobileSMS, ActivityMessages, iMessageAppsViewService)
│   ├── OS Baseline (JIT/JS Lockdown)
│   ├── Disable Media Auto-Play: ON
│   ├── Disable WebGL & WebRTC: ON
│   ├── Disable Local File Access: ON
│   ├── Disable Msg Auto-Download: ON
│   └── Spoof User Agent: OFF
│
└── ✉️ Apple Mail & Other Native Apps
    ├── OS Baseline (JIT/JS Lockdown)
    ├── Disable Media Auto-Play: ON (Mail)
    ├── Disable WebGL & WebRTC: ON (Mail)
    ├── Disable Local File Access: ON (Mail)
    └── Spoof User Agent: OFF

Level 2
├── 📱 All Level 1 Native Apple Apps & Rules
│
├── 🌐 3rd-Party Browsers (Chrome, Firefox, Brave, DuckDuckGo)
│   ├── OS Baseline (JIT/JS Lockdown)
│   └── Spoof User Agent: ON
│
├── 💬 3rd-Party Messaging & Email (WhatsApp, Discord, Signal, Telegram, Gmail, Outlook)
│   ├── OS Baseline (JIT/JS Lockdown)
│   ├── Disable Media Auto-Play: ON
│   ├── Disable WebGL & WebRTC: ON
│   ├── Disable Local File Access: ON
│   └── Spoof User Agent: ON
│
└── 🏦 Social, Finance, & JB Apps (TikTok, Facebook, PayPal, CashApp, Sileo, Zebra, Filza)
    ├── OS Baseline (JIT/JS Lockdown)
    └── Spoof User Agent: ON

Level 3
├── 📱 All Level 1 & Level 2 Apps & Rules
│
├── 🌐 Browsers (Safari, Chrome, Firefox, Brave, DuckDuckGo)
│   ├── Disable WebGL & WebRTC: ON
│   └── Disable Media Auto-Play: ON 
│
└── ⚙️ System Daemons (imagent, apsd, identityservicesd)
    ├── WebKit Mitigations: BYPASSED
    └── System Hooking: ON (Disables zero-click payload parsing)
```

-----

## 👨‍💻 Developer

Created by: [EolnMsuk](https://github.com/EolnMsuk) / [AntiDarkSword](https://github.com/EolnMsuk/AntiDarkSword/) 

Thanks to: [ghh-jb](https://github.com/ghh-jb) / [CorelliumDecoy](https://github.com/ghh-jb/CorelliumDecoy)

Support my work: [Venmo](https://venmo.com/user/eolnmsuk)
