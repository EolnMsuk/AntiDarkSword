# AntiDarkSword [⛨](https://www.reddit.com/r/jailbreak_/comments/1snqkii/antidarksword_v4_webkit_imessage_exploit/)
An iOS jailbreak exploit mitigation tweak and TrollStore/TrollFools per-app mitigation dylib that hardens vulnerable iOS devices against WebKit RCE (DarkSword / Coruna) and iMessage zero-click (BLASTPASS) exploits. Selectively blocks JIT, spoofs user agents, blocks remote content, suppresses risky attachment previews, intercepts Notification Service Extensions, applies mitigations to selected system daemons, and deploys a Corellium honeypot to cause advanced payloads to self abort.

  - [Installation](#%EF%B8%8F-installation)
  - [Compatibility](#-compatibility)
  - [Protection](#%EF%B8%8F-protections)
  - [Details](#-details)
  - [Developer](#%E2%80%8D-developer)

---

[<img width="1280" height="1030" alt="ReadMeNew" src="https://i.imgur.com/kTAveDD.png" />](https://www.reddit.com/r/jailbreak_/comments/1snqkii/antidarksword_v4_webkit_imessage_exploit/)
> **Exploit kits:** DarkSword, Coruna, Predator, PWNYOURHOME, Chaos, Operation Triangulation, Hermit  
> **Zero-clicks:** BLASTPASS (PassKit iMessage attachment)  
> **CVEs:** CVE-2025-43529, CVE-2024-44308, CVE-2022-42856

---

## 🛠️ Installation

**Jailbreak tweak:** Download the matching environment asset from a published
[release](https://github.com/EolnMsuk/AntiDarkSword/releases). Native Roothide uses
the `_roothide.deb` build and matching native dependencies; no external patcher
is required. Keep legacy and modern rootful packages distinct.

**TrollFools:** With a supported TrollStore/TrollFools setup, download
`AntiDarkSword_<version>_TrollFools.dylib`, inject it per app, and use the existing
biometric-gated three-finger double-tap settings gesture. Its release deployment
baseline remains iOS 15+. The overlay has no update checker or donation menu.

## 📱 Compatibility

The supplied 4.9.3 runtime is the baseline for this manual-update/donation port.
This port needs device validation; native Roothide is separate from the
previously reported working patcher-converted rootless route.

| Release suffix | Platform | Slices / package architecture |
|---|---|---|
| `_legacy.deb` | iOS 13–14 rootful; SDK 14.5 | arm64 / iphoneos-arm |
| `_rootful.deb` | iOS 15–17 rootful; SDK 16.5 | arm64, arm64e / iphoneos-arm |
| `_rootless.deb` | iOS 15–17 rootless; SDK 16.5 | arm64, arm64e / iphoneos-arm64 |
| `_roothide.deb` | Native Roothide; iOS 15+ deployment within supported environments | arm64, arm64e / iphoneos-arm64e |
| `_TrollFools.dylib` | Per-app injection; iOS 15+ deployment | arm64, arm64e; no Debian package |

---

## 🛡️ Protections

Available mitigations vary by build and iOS version.

| **Jailbreak (tweak)** | iOS 13–14 | iOS 15 | iOS 16+ |
| :--- | :--- | :--- | :--- |
| Disable JIT | ✅ | ✅ | ✅ |
| Disable JavaScript | ✅ | ✅ | ✅ |
| UA Spoofing | ✅ | ✅ | ✅ |
| UA Client Hints | ❌ | ❌ | ✅ |
| Disable WebRTC / WebGL | ✅ | ✅ | ✅ |
| Disable media autoplay | ✅ | ✅ | ✅ |
| Disable local file access | ✅ | ✅ | ✅ |
| Mail auto-download block | ✅ | ✅ | ✅ |
| iMessage auto-download block | ✅ | ✅ | ✅ |
| Block remote content | ✅ | ✅ | ✅ |
| Block risky attachments | ✅ | ✅ | ✅ |
| NSE interception | ✅ | ✅ | ✅ |
| Daemon protection | ✅ | ✅ | ✅ |
| Corellium decoy | ✅ | ✅ | ✅ |

---

| **TrollStore (dylib)** | iOS 15 | iOS 16+ |
| :--- | :--- | :--- |
| Disable JIT | ✅ | ✅ |
| Disable JavaScript | 🟡 | 🟡 |
| UA Spoofing | ✅ | ✅ |
| UA Client Hints | ❌ | ✅ |
| Disable WebRTC / WebGL | ✅ | ✅ |
| Disable media autoplay | ✅ | ✅ |
| Disable local file access | ✅ | ✅ |
| Mail auto-download block | ✅ | ✅ |
| iMessage auto-download block | ❌ | ❌ |
| Block remote content | ✅ | ✅ |
| Block risky attachments¹ | ✅ | ✅ |
| Daemon protection | ❌ | ❌ |
| Corellium decoy | ❌ | ❌ |
| Mitigation Shortcut¹ | ✅ | ✅ |
> ¹ **Mitigation Shortcut:** Three-finger double-tap on open app to trigger the settings overlay (biometric-gated).  

---

## ⚙️ Preset Levels

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

  (Block Remote Content is added to Apple Messages & Mail at Level 2+)

Level 2
├── 📱 All Level 1 Apps & Rules
│   └── 💬 Apple Messages & Mail: Block Remote Content: ON (added at this level)
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
│   ├── Block Remote Content: ON
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
    ├── All four daemon switches start OFF when entering from Level 1 or 2
    ├── Choose individual daemons in Settings > Level 3 Settings > System Daemons
    └── Corellium Honeypot starts OFF. Turning it on selects all four daemons.
```

---

### 📝 Details

- [AntiDarkSwordUI.md](https://github.com/EolnMsuk/AntiDarkSword/blob/main/AntiDarkSwordUI/README.md) 
- [AntiDarkSwordDaemon.md](https://github.com/EolnMsuk/AntiDarkSword/blob/main/AntiDarkSwordDaemon/README.md) 
- [CorelliumDecoy.md](https://github.com/EolnMsuk/AntiDarkSword/blob/main/CorelliumDecoy/README.md) 
- [AntiDarkSwordTF.md](https://github.com/EolnMsuk/AntiDarkSword/blob/main/AntiDarkSwordTF/README.md) 
- [Compatibility.md](https://github.com/EolnMsuk/AntiDarkSword/blob/main/compatibility.md) 

---

### 👨‍💻 Developer

Created by [EolnMsuk](https://github.com/EolnMsuk) → [AntiDarkSword](https://github.com/EolnMsuk/AntiDarkSword/)  
Thanks to [ghh-jb](https://github.com/ghh-jb) → [CorelliumDecoy](https://github.com/ghh-jb/CorelliumDecoy)  
Support me [BTC](https://www.blockchain.com/explorer/addresses/btc/31uHLpioo1TbxAmo9kM7rrKcLz3wvcoZaL) → [Venmo](https://venmo.com/EolnMsuk/)
