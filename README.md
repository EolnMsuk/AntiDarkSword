# AntiDarkSword ⚔️ (Rootless / Rootful)

AntiDarkSword is an iOS security tweak that hardens vulnerable jailbroken devices against WebKit and iMessage-based exploits (DarkSword & Coruna). It mitigates / spoofs vectors used in 1-click and 0-click attacks while isolating background daemons.

[<img width="1249" height="918" alt="readmeORIG" src="https://github.com/user-attachments/assets/2634bd49-f315-4035-a446-3ef48ffdd134" />](https://tinyurl.com/AntiDarkSword)

## ✨ Features

* **iOS 16+:** Disable / Enable the JIT compiler by hooking native WebKit (`lockdownModeEnabled`) and ChatKit (`isAutoDownloadable`) logic gates.
* **iOS 15.x:** Disable / Enable the JIT compiler via undocumented WebKit `_WKProcessPoolConfiguration` APIs (`JITEnabled`), bridging the gap for devices lacking native Lockdown Mode.
* **WebKit Hardening:** Disable / Enable media auto-playback, Picture-in-Picture, WebGL, WebRTC, and local file access.
* **iMessage Mitigation:** Blocks automatic attachment downloading and previews within IMCore and ChatKit.
* **Corellium Honeypot:** Spoofs a research environment using low-level file hooks and a dummy background process, causing advanced payloads to abort delivery.
* **User Agent Spoofing:** Spoofs the WKWebView User Agent iOS to bypass payload fingerprinting.
* **Granular Controls:** Manually assign custom process / daemon / app-specific mitigation rules. 
* **Global Mitigations:** System-wide controls that indiscriminately apply mitigations to all processes, use with extreme caution.
* **Zero-Crash Architecture:** Web mitigations are isolated from system tasks, preventing hardware DSP deadlocks and memory limit crashes.

## 🛑 Mitigated Exploits

* **Exploit Kits & Spyware:** DarkSword, Coruna, Predator, PWNYOURHOME, Chaos, Operation Triangulation, Hermit.
* **iMessage 0-Clicks:** BLASTPASS (PassKit attachments).
* **CVEs Patched:** CVE-2025-43529, CVE-2024-44308, CVE-2022-42856.

## 📱 Dependencies

`mobilesubstrate` (or `ElleKit`), `preferenceloader`, `altlist`

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

## 🛠️ Installation

1. Add this Sileo repo: `https://f0rd0w.github.io/`
2. Or manually install the [latest release](https://github.com/EolnMsuk/AntiDarkSword/releases) rootless `arm64.deb` or rootful `arm.deb`.


## ⚙️ Configuration

> [!WARNING]  
> Remove protected apps from Roothide's Blacklist / Choicy to ensure the tweak can successfully inject.
>
> Level 3 restricts critical background daemons; lower the level if you have any issues.

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
├── ⚙️ System Daemons (imagent, apsd, identityservicesd)
│   ├── WebKit Mitigations: BYPASSED
│   └── System Hooking: ON (Disables zero-click payload parsing)
│
└── 🛡️ Environment Spoofing
    └── Corellium Honeypot: ON (Spoofs research device hardware & file paths)
```

-----

## 👨‍💻 Developer

Created by: [EolnMsuk](https://github.com/EolnMsuk) / [AntiDarkSword](https://github.com/EolnMsuk/AntiDarkSword/) 

Thanks to: [ghh-jb](https://github.com/ghh-jb) / [CorelliumDecoy](https://github.com/ghh-jb/CorelliumDecoy)

Support my work: [Venmo](https://venmo.com/user/eolnmsuk)
