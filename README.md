# AntiDarkSword ⚔️

A jailbreak tweak and TrollFools dylib that hardens iOS devices against WebKit RCE and iMessage zero-click exploits. Blocks JIT, spoofs user agents, isolates system daemons, and deploys a Corellium honeypot to cause advanced payloads to self-abort.

[<img width="1280" height="1030" alt="ReadMeNew" src="https://github.com/user-attachments/assets/0564c070-59a3-4667-8328-924ce73e685d" />](https://www.reddit.com/r/jailbreak_/comments/1snqkii/antidarksword_v4_webkit_imessage_exploit/)

---

## 🛡️ Protections

| Feature | What it does |
|---|---|
| **Disable JIT** | iOS 16+: `lockdownModeEnabled` + `JITEnabled = NO`. iOS 13–15: `JITEnabled = NO` only |
| **WebKit Hardening** | Disable media autoplay, PiP, WebGL, WebRTC, and local file access |
| **iMessage Blocking** | Block auto-download and preview generation in IMCore / ChatKit (jailbreak only) |
| **User Agent Spoofing** | Mask the WKWebView UA to defeat browser fingerprinting used by exploit kits |
| **Corellium Honeypot** | Spoof `/usr/libexec/corelliumd` + live daemon process — payload aborts on detection |
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
| **NathanLR** | Rootless (semi-jailbreak) | 16.5.1 – 17.0 ¹ |
| **Dopamine 2** | Rootless / RootHide | 15.0 – 16.6.1 |
| **palera1n** | Rootless / Rootful | 15.0 – 17.x |
| **meowbrek2** | Rootless | 15.0 – 15.8.3 |
| **NekoJB** | Rootless | 15.0 – 15.8.3 |
| **XinaA15** | Hybrid | 15.0 – 15.1.1 |
| **checkra1n** | Rootful | 13.0 – 14.8.1 |
| **Taurine** | Rootful | 14.0 – 14.8.1 |
| **unc0ver** | Rootful | 13.0 – 14.8 |
| **Odyssey** | Rootful | 13.0 – 13.7 |

> ¹ **NathanLR** is a semi-jailbreak (fork of Serotonin) that requires **TrollStore** to install. It uses the TrollInstallerX kernel exploit and natively supports standard rootless tweaks without any conversion. It is the primary option for **A12+ (arm64e) devices** on iOS 16.5.1–17.0 that lack Dopamine or palera1n support. v2.0 extends support to iOS 17.0 across all devices including iPhone 14 and 15 lineups. Supports daemon injection, so the full `.deb` including system daemon hooks works as expected.

### TrollFools / TrollStore (WebKit dylib only)

No jailbreak required. Injects per-app — iMessage and Corellium protections not included.

| iOS | TrollStore |
|---|---|
| 14.0 – 14.8.1 | ✅ |
| 15.0 – 16.6.1 | ✅ |
| 16.7.x | ⚠️ Limited (device/exploit dependent) |
| 17.0 | ⚠️ Limited (device/exploit dependent) |
| 17.1+ | ❌ Not supported |

> For iOS 17.0 on **A12+ devices** (iPhone XS and newer): use **NathanLR** for the full `.deb` (includes daemon hooks and iMessage protection), or **TrollFools** for per-app WebKit protection only.

---

## 🛠️ Installation

**Jailbroken**
1. Add repo in Sileo/Zebra: `https://f0rd0w.github.io/`
2. Or install the [`latest .deb`](https://github.com/EolnMsuk/AntiDarkSword/releases) manually (`arm64` = rootless, `arm` = rootful).
3. Configure in **Settings > AntiDarkSword** and remove protected apps from Choicy or Roothide Blacklist.

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
