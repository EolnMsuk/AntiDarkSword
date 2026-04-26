# [⛨](https://www.reddit.com/r/jailbreak_/comments/1snqkii/antidarksword_v4_webkit_imessage_exploit/) AntiDarkSword
An iOS tweak and TrollStore dylib that hardens jailbroken devices against WebKit RCE and iMessage zero-click exploits. Blocks JIT, spoofs user agents, blocks remote content, suppresses risky attachment previews, intercepts Notification Service Extensions, isolates system daemons, and deploys a Corellium honeypot to cause advanced payloads to self abort.

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
1. Install the [latest release](https://github.com/EolnMsuk/AntiDarkSword/releases).
> On iOS 15+ use `arm.deb` for rootful, `arm64.deb` for rootless.  
> On iOS 13–14 use `arm_legacy.deb`.  

**TrollFools Dylib**
1. Install [TrollStore](https://github.com/opa334/TrollStore/releases) and [TrollFools](https://github.com/Lessica/TrollFools/releases).
2. Download `AntiDarkSword.dylib` from the [latest release](https://github.com/EolnMsuk/AntiDarkSword/releases).
3. Open TrollFools → select an app → inject the `.dylib`.
4. **Three-finger double-tap** inside an app to open the settings overlay.

---

## 📱 Compatibility

| File | Jailbreak | iOS | Chip |
| :--- | :--- | :--- | :--- |
| `*_iphoneos-arm64.deb` | Dopamine, meowbrek2, palera1n **rootless** | 15.0 – 17.0 | A12+ · A9–A11 |
| `*_iphoneos-arm.deb` | unc0ver, Taurine, checkra1n, palera1n **rootful** | 15.0 – 17.0 | A9+ |
| `*_iphoneos-arm_legacy.deb` | unc0ver, checkra1n, Taurine **rootful** | 13.0 – 14.8 | A9–A11 (arm64) |
| `*_TrollFools.dylib` | TrollStore + TrollFools (no jailbreak needed) | 15.0 – 17.0 | A9+ |

---

## 🛡️ Protections

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
| Block risky attachments¹ | ✅ | ✅ | ✅ |
| NSE interception² | ✅ | ✅ | ✅ |
| Daemon protection | ✅ | ✅ | ✅ |
| Corellium decoy | ✅ | ✅ | ✅ |

<br>

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
| Mitigation Shortcut³ | ✅ | ✅ |

> ¹ **Block risky attachments:** Suppresses full-size previews of HEIC, HEIF, WebP, and PDF attachments in Messages — formats historically exploited via ImageIO/CoreGraphics parsing bugs.  
> ² **NSE interception:** Hooks load inside `com.apple.messages.NotificationServiceExtension` and `com.apple.MailNotificationServiceExtension` to apply WebKit and attachment mitigations before a zero-click payload can reach the parser.  
> ³ **Mitigation Shortcut:** Three-finger double-tap on open app to trigger the settings overlay (biometric-gated).

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
    ├── System Hooking: ON (blocks zero-click payload parsing)
    ├── Individual daemon switches: Settings > Restrict System Daemons
    └── Corellium Honeypot: ON
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
Support me [BTC](https://www.blockchain.com/explorer/addresses/btc/bc1qm06lzkdfule3f7flf4u70xvjrp5n74lzxnnfks) → [Venmo](https://venmo.com/user/eolnmsuk)
