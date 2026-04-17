# AntiDarkSword ⚔️

A jailbreak tweak and TrollFools dylib that hardens iOS devices against WebKit RCE and iMessage zero-click exploits. Blocks JIT, spoofs user agents, isolates system daemons, and deploys a Corellium honeypot to cause advanced payloads to self-abort.

[<img width="1249" height="918" alt="readmeORIG" src="https://github.com/user-attachments/assets/2634bd49-f315-4035-a446-3ef48ffdd134" />](https://www.reddit.com/r/jailbreak_/comments/1snqkii/antidarksword_v4_webkit_imessage_exploit/)

---

## 🛡️ Protections

| Feature | What it does |
|---|---|
| **JIT Disable** | iOS 16+: `lockdownModeEnabled` + `JITEnabled = NO`. iOS 14–15: `JITEnabled = NO` only |
| **WebKit Hardening** | Disables media autoplay, PiP, WebGL, WebRTC, and local file access per-app |
| **iMessage Blocking** | Blocks auto-download and preview generation in IMCore / ChatKit (jailbreak only) |
| **User Agent Spoofing** | Masks the WKWebView UA to defeat browser fingerprinting used by exploit kits |
| **Corellium Honeypot** | Spoofs `/usr/libexec/corelliumd` + live daemon process — payload aborts on detection |
| **Granular Rules** | Per-app, per-daemon, and system-wide override controls in Settings |

## 🛑 Mitigated Threats

**Exploit kits:** DarkSword, Coruna, Predator, PWNYOURHOME, Chaos, Operation Triangulation, Hermit  
**Zero-clicks:** BLASTPASS (PassKit iMessage attachment)  
**CVEs:** CVE-2025-43529, CVE-2024-44308, CVE-2022-42856

---

## 📱 Compatibility

### Jailbreak (full tweak — `.deb`)

Requires: `mobilesubstrate` (or `ElleKit`), `preferenceloader`, `altlist`

| Jailbreak | Type | iOS |
|---|---|---|
| **Dopamine 2** | Rootless / RootHide | 15.0 – 16.6.1 |
| **Palera1n** | Rootless / Rootful | 15.0 – 17.x |
| **meowbrek2** | Rootless | 15.0 – 15.8.3 |
| **NekoJB** | Rootless | 15.0 – 15.8.3 |
| **XinaA15** | Hybrid | 15.0 – 15.1.1 |
| **checkra1n** | Rootful | 13.0 – 14.8.1 |
| **Taurine** | Rootful | 14.0 – 14.8.1 |
| **unc0ver** | Rootful | 13.0 – 14.8 |
| **Odyssey** | Rootful | 13.0 – 13.7 |

### TrollFools / TrollStore (WebKit dylib only)

No jailbreak required. Injects per-app — iMessage and Corellium protections not included.

| iOS | TrollStore |
|---|---|
| 14.0 – 14.8.1 | ✅ |
| 15.0 – 16.6.1 | ✅ |
| 16.7.x | ⚠️ Limited |
| 17.0 | ⚠️ Limited |
| 17.1+ | ❌ |

---

## 🛠️ Installation

**Jailbroken**
1. Add repo in Sileo/Zebra: `https://f0rd0w.github.io/`
2. Or install the [`latest .deb`](https://github.com/EolnMsuk/AntiDarkSword/releases) manually (`arm64` = rootless, `arm` = rootful).
3. Configure in **Settings > AntiDarkSword**.

> [!WARNING]
> Remove protected apps from Roothide's Blacklist / Choicy before installing.

**TrollStore**
1. Install [TrollStore](https://github.com/opa334/TrollStore/releases) and [TrollFools](https://github.com/Lessica/TrollFools/releases).
2. Download `AntiDarkSword.dylib` from the [latest release](https://github.com/EolnMsuk/AntiDarkSword/releases).
3. Open TrollFools → select a 3rd-party app → inject the `.dylib`.
4. **Three-finger double-tap** inside the app to open the protection overlay.

---

## ⚙️ Auto-Protect Levels

> Level 3 hooks system daemons. Toggle individual daemons under **Settings > Restrict System Daemons**.

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
├── 📱 All Level 1 Apps & Rules
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
└── 🏦 Social, Finance & JB Apps (TikTok, Facebook, PayPal, CashApp, Sileo, Zebra, Filza)
    ├── OS Baseline (JIT/JS Lockdown)
    └── Spoof User Agent: ON

Level 3
├── 📱 All Level 1 & Level 2 Apps & Rules
│
├── 🌐 Browsers (Safari, Chrome, Firefox, Brave, DuckDuckGo)
│   ├── Disable WebGL & WebRTC: ON
│   └── Disable Media Auto-Play: ON
│
└── ⚙️ System Daemons (imagent, apsd, identityservicesd, IMDPersistenceAgent)
    ├── System Hooking: ON (blocks zero-click payload parsing)
    ├── Individual daemon switches: Settings > Restrict System Daemons
    └── Corellium Honeypot: ON
```

---

## 👨‍💻 Developer

Created by [EolnMsuk](https://github.com/EolnMsuk) — [AntiDarkSword](https://github.com/EolnMsuk/AntiDarkSword/)  
Thanks to [ghh-jb](https://github.com/ghh-jb) — [CorelliumDecoy](https://github.com/ghh-jb/CorelliumDecoy)  
Support: [Venmo](https://venmo.com/user/eolnmsuk)
