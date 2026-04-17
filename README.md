# AntiDarkSword ⚔️

A jailbreak tweak and TrollFools dylib that hardens iOS 13.X - iOS 17.0 devices against WebKit RCE and iMessage zero-click exploits. Blocks JIT, spoofs user agents, isolates system daemons, and deploys a Corellium honeypot to cause advanced payloads to self-abort.

---

[<img width="1280" height="1030" alt="ReadMeNew" src="https://github.com/user-attachments/assets/0564c070-59a3-4667-8328-924ce73e685d" />](https://www.reddit.com/r/jailbreak_/comments/1snqkii/antidarksword_v4_webkit_imessage_exploit/)

## 🛑 Mitigated Threats

**Exploit kits:** DarkSword, Coruna, Predator, PWNYOURHOME, Chaos, Operation Triangulation, Hermit  
**Zero-clicks:** BLASTPASS (PassKit iMessage attachment)  
**CVEs:** CVE-2025-43529, CVE-2024-44308, CVE-2022-42856

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

## 🛡️ Protections & Compatibility

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

---

## ⚙️ Preset Level Protection

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
