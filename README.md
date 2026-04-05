<img width="1496" height="1127" alt="readme" src="https://github.com/user-attachments/assets/3e064f8b-427e-44b2-ae42-3fbc17a65365" />

# AntiDarkSword ⚔️ (Rootless Roothide)

AntiDarkSword is an advanced iOS security tweak designed to harden jailbroken devices against WebKit and iMessage-based exploits. Built on a modernized, zero-crash architecture, it significantly reduces your device's attack surface by neutralizing common vectors used in one-click and zero-click attacks without compromising system stability.

-----

## 🔍 How the Protection Works (Allow-By-Default)

AntiDarkSword effectively acts as a "Modular Lockdown Mode," featuring intelligent OS detection to adapt to your device's exact capabilities, bypassing the need for Apple's Native Lockdown Mode:
* **For iOS 16+:** It hooks into the exact same WebKit (`lockdownModeEnabled`) and ChatKit (`isAutoDownloadable`) internal logic gates used by Apple's own security engineers to surgically disable the vulnerable JIT compiler.
* **For iOS 15.x:** It utilizes undocumented WebKit `_WKProcessPoolConfiguration` APIs (`JITEnabled`) to surgically disable the JIT compiler natively, bridging the security gap for older devices that lack a system-wide Lockdown Mode. A strict, nuclear JavaScript kill-switch is also available as an ultimate fallback.

Because it targets the specific rendering and downloading processes that exploit kits use as entry points, this tweak protects equally—if not more—against known zero-click payloads, while allowing you to keep essential system features functional. You retain your wired accessory permissions, shared albums, smart home integrations, and the baseline UI of your safe apps, while neutralizing the exact memory-corruption vulnerabilities attackers rely on.

## ✨ Features

  * **WebKit Hardening:** Forcibly disables the JIT compiler, inline media auto-playback, Picture-in-Picture, WebGL, WebRTC (peer connections), and local file access within targeted web views. By disabling the highly-targeted JIT compiler while allowing baseline interpreted JavaScript, your apps retain their UI functionality while neutralizing memory-corruption zero-days.
  * **iMessage Mitigation:** Defends against BlastPass/FORCEDENTRY-style attacks by disabling automatic attachment downloading and preview generation within IMCore and ChatKit.
  * **Granular App Controls:** Tap on any restricted app in your settings to customize its specific mitigations. Want to disable WebRTC but keep JIT enabled for a specific browser? You can do that. 
  * **Zero-Crash Architecture:** Completely separates heavy web mitigations from background system tasks. This physical isolation guarantees that locking down background daemons will never cause memory limit crashes or respring loops.
  * **Global Mitigations (BETA):** Extreme system-wide kill-switches that apply mitigations to *every* process indiscriminately. Intended for emergency lockdowns only.
  * **User Agent Spoofing:** Globally spoof the `WKWebView` Custom User Agent for restricted apps to bypass strict fingerprinting modules. Includes modern presets (iOS 18.1, Android Chrome, Windows Edge, macOS, etc.) or the ability to inject a custom string.
  * **Tiered Protection:**
      * **Level 1:** Protects native Apple apps and services (Safari, Mail and Messages).
      * **Level 2:** Expands protection to major third-party browsers and social media apps.
      * **Level 3:** Locks down critical system daemons to prevent daemon-level zero-clicks.
  * **Custom Targeting:** Manually specify bundle IDs or process names to restrict specific background tasks. Swipe-to-delete makes management easy.

> [\!WARNING]
> **All Levels by default disable file previews for email and text.** You have to hold the file down and save it to the Files app to view it.
>
> **Level 3 restricts critical background daemons.** `imagent` and `mediaserverd` filtering. Lower your level if you experience any issues.

## 🛑 Mitigated Exploits

By disabling WebKit JIT and JavaScriptCore attack vectors, this tweak prevents several known exploit chains:

  * **DarkSword:** Full-chain, JavaScript-based exploit kit (iOS 18.4 – 18.7).
  * **Coruna:** JavaScript-reliant iOS exploit kit (iOS 13.0 – 17.2.1).
  * **Predator:** Safari JavaScript 1-click spyware (Versions before iOS 16.7).
  * **BLASTPASS:** iMessage zero-click using PassKit attachments (Versions before iOS 16.6.1).
  * **PWNYOURHOME:** Zero-click targeting HomeKit or iCloud Photos (iOS 15.0 – 16.3.1).
  * **Chaos:** Safari WebKit DOM vulnerability exploit (Versions older than 16.3).
  * **CVE-2025-43529:** Recent WebKit zero-day using memory corruption (Versions prior to iOS 26.2).
  * **CVE-2024-44308:** WebKit remote code execution via web content (Versions before 18.1.1).
  * **CVE-2022-42856:** JavaScriptCore type confusion in JIT compiler (iOS 16.0 to 16.1.1 and earlier).
  * **Operation Triangulation:** iMessage WebKit zero-click chain (iOS 15.7 and older).
  * **Hermit:** JavaScriptCore type-confusion spyware chain (iOS 15.0 – 15.4.1).

## 📱 Compatibility

  * **iOS Versions:** iOS 15.0 – 17.0
  * **Architecture:** arm64 / arm64e (A11 through A16/M-series fat binary)
  * **Jailbreaks:** \* **Rootless:** Dopamine (iOS 15.0 – 17.0), Palera1n (iOS 15.0 – 16.7.x)
      * **Roothide:** Dopamine Roothide 2 (via Roothide Patcher)
      * **Rootful:** Palera1n / Checkm8 users should use: [AntiDarkSword-rootful](https://github.com/EolnMsuk/AntiDarkSword-rootful)

## 📦 Dependencies

Before installing this tweak, you **must** install the following from your package manager (Sileo/Zebra):

  * `mobilesubstrate`
  * `preferenceloader`
  * `com.opa334.altlist` (AltList)

## 🛠️ Installation Instructions

### Option 1: Installation (Rootless)

1.  Navigate to the **[Releases](https://github.com/EolnMsuk/AntiDarkSword/releases)** page of this repository.
2.  Click on the latest release version.
3.  Under the **Assets** section, download the attached `.deb` file.
4.  Open the `.deb` file on your iPhone and install it via your preferred package manager (Sileo, Zebra, or Filza).
5.  Respring your device.

### Option 2: Installation (Roothide)

If you are using Dopamine Roothide 2 to bypass jailbreak detection, you must patch the `.deb` before installing:

1.  Download the `.deb` file from the **[Releases](https://github.com/EolnMsuk/AntiDarkSword/releases)** page.
2.  Send the file to your iPhone.
3.  Open the **Roothide Patcher** app.
4.  Select the `.deb` file and let the app convert the rootless paths to dynamic Roothide paths.
5.  Open the newly generated `-roothide.deb` file in **Sileo** or **Filza**, tap Install, and Respring.

## ⚙️ Configuration

1.  Open your iPhone's native **Settings** app and navigate to **AntiDarkSword**.
2.  Toggle **ON** the master `Enable Protection` switch.
3.  **User Agent Spoofing:** Select a preset modern user agent (or enter a custom string) to bypass fingerprinting modules.
4.  **Choose your protection rules:**
      * **Preset Rules:** Select Level 1, 2, or 3. The protected apps will dynamically appear below. Tap on any app to view or modify its specific mitigation features.
      * **Manual Rules:** Use the **Select Apps...** menu to target apps not covered by your preset. They will highlight in green, and you can tap them to customize their rules.
      * **Advanced Custom Rules:** Add hidden background daemons manually using comma-separated strings.
5.  **Global Mitigations (BETA):** Use these switches to indiscriminately apply a mitigation to *every* process on the phone. **Warning:** This will break core app functionality and is intended for extreme scenarios only.
6.  **Apply Changes:** Tap the **Save** button in the top right corner. The tweak will intelligently determine if a quick Respring is sufficient, or if a Userspace Reboot is required (necessary when modifying core daemons).

> [\!WARNING]
> **Remove any apps you want secured from Roothide's Blacklist / allow tweak through Choicy.** This allows the tweak to inject and filter that app.

-----

## 👨‍💻 Developer

Created by: [EolnMsuk](https://github.com/EolnMsuk)

Donate 🤗: [eolnmsuk](https://venmo.com/user/eolnmsuk)

Donate 🤗: [eolnmsuk](https://venmo.com/user/eolnmsuk)
