# AntiDarkSword [⛨](https://www.reddit.com/r/jailbreak_/comments/1snqkii/antidarksword_v4_webkit_imessage_exploit/)
An iOS tweak and TrollStore dylib that hardens Jailbroken devices against WebKit RCE and iMessage zero-click exploits. Blocks JIT, spoofs user agents, isolates system daemons, and deploys a Corellium honeypot to cause advanced payloads to self abort.

  - [Installation](#%EF%B8%8F-installation)
  - [Compatibility](#-compatibility)
  - [Protection](#%EF%B8%8F-protections)
  - [Details](#-details)
  - [Developer](#%E2%80%8D-developer)

---

[<img width="1280" height="1030" alt="ReadMeNew" src="https://github.com/user-attachments/assets/0564c070-59a3-4667-8328-924ce73e685d" />](https://www.reddit.com/r/jailbreak_/comments/1snqkii/antidarksword_v4_webkit_imessage_exploit/)

> **Exploit kits:** DarkSword, Coruna, Predator, PWNYOURHOME, Chaos, Operation Triangulation, Hermit  
> **Zero-clicks:** BLASTPASS (PassKit iMessage attachment)  
> **CVEs:** CVE-2025-43529, CVE-2024-44308, CVE-2022-42856

---

## 🛠️ Installation

**Jailbreak Tweak**
1. Add repo in Sileo/Zebra: https://f0rd0w.github.io/
2. Or install the [latest release](https://github.com/EolnMsuk/AntiDarkSword/releases) manually using the table above.
> Use `arm.deb` for rootful, `arm64.deb` for rootless/roothide.

**TrollFools Dylib**
1. Install [TrollStore](https://github.com/opa334/TrollStore/releases) and [TrollFools](https://github.com/Lessica/TrollFools/releases).
2. Download `AntiDarkSword.dylib` from the [latest release](https://github.com/EolnMsuk/AntiDarkSword/releases).
3. Open TrollFools → select an app → inject the `.dylib`.
4. **Three-finger double-tap** inside an app to open the settings overlay.

---

## 📱 Compatibility

| File | Jailbreak | iOS | Chip |
| :--- | :--- | :--- | :--- |
| `*_iphoneos-arm64.deb` | Dopamine, meowbrek2, palera1n **rootless** | 15.0 – 16.6.1 | A12+ · A8–A11 |
| `*_iphoneos-arm.deb` | unc0ver, Taurine, checkra1n, palera1n **rootful** | 13.0¹ – 15.x | N/A |
| `*_TrollFools.dylib` | TrollStore + TrollFools (no jailbreak needed) | 14.0¹ – 16.x | N/A |    
> **¹ Installation on iOS 13/14 requires manual compilation**   
> 1. Clone repository. 
> 2. Replace `vendor/AltList.framework` with the legacy `arm64e.old` ABI version. 
> 3. Execute `make package` or `make package THEOS_PACKAGE_SCHEME=rootless`. 

---

## 🛡️ Protections

| **Jailbreak (tweak)** | 13 – 14 | iOS 15  | iOS 16+ |
| :--- | :--- | :--- | :--- |
| Disable JIT | ❌ | ✅ | ✅ |
| Disable JavaScript | 🟡 | ✅ | ✅ |
| UA Spoofing | ✅ | ✅ | ✅ |
| UA Client Hints | ❌ | ❌ | ✅ |
| Disable WebRTC / WebGL | ✅ | ✅ | ✅ |
| Disable media autoplay | ✅ | ✅ | ✅ |
| Disable local file access | ✅ | ✅ | ✅ |
| Mail auto-download block | ✅ | ✅ | ✅ |
| iMessage auto-download block | ✅ | ✅ | ✅ |
| Daemon protection | ✅ | ✅ | ✅ |
| Corellium decoy | ✅ | ✅ | ✅ |

<br>

| **TrollStore (dylib)** | 13 – 14 | iOS 15  | iOS 16+ |
| :--- | :--- | :--- | :--- |
| Disable JIT | ❌ | ✅ | ✅ |
| Disable JavaScript | 🟡 | 🟡 | 🟡 |
| UA Spoofing | ✅ | ✅ | ✅ |
| UA Client Hints | ❌ | ❌ | ✅ |
| Disable WebRTC / WebGL | ✅ | ✅ | ✅ |
| Disable media autoplay | ✅ | ✅ | ✅ |
| Disable local file access | ✅ | ✅ | ✅ |
| Mail auto-download block | ✅ | ✅ | ✅ |
| iMessage auto-download block | ❌ | ❌ | ❌ |
| Daemon protection | ❌ | ❌ | ❌ |
| Corellium decoy | ❌ | ❌ | ❌ |
| Mitigation Shortcut² | ✅ | ✅ | ✅ |

> ² **Mitigation Shortcut:** Three-finger double-tap on open app to trigger a shortcut mitigation settings panel.

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

### 📝 Details

- [AntiDarkSwordUI.md](https://github.com/EolnMsuk/AntiDarkSword/blob/main/AntiDarkSwordUI/README.md) 
- [AntiDarkSwordDaemon.md](https://github.com/EolnMsuk/AntiDarkSword/blob/main/AntiDarkSwordDaemon/README.md) 
- [AntiDarkSwordTF.md](https://github.com/EolnMsuk/AntiDarkSword/blob/main/AntiDarkSwordTF/README.md) 
- [CorelliumDecoy.md](https://github.com/EolnMsuk/AntiDarkSword/blob/main/CorelliumDecoy/README.md) 

---

### 👨‍💻 Developer

Created by [EolnMsuk](https://github.com/EolnMsuk) → [AntiDarkSword](https://github.com/EolnMsuk/AntiDarkSword/)  
Thanks to [ghh-jb](https://github.com/ghh-jb) → [CorelliumDecoy](https://github.com/ghh-jb/CorelliumDecoy)  
Support me [BTC](https://www.blockchain.com/explorer/addresses/btc/bc1qm06lzkdfule3f7flf4u70xvjrp5n74lzxnnfks) - [Venmo](https://venmo.com/user/eolnmsuk)
