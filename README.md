<img width="800" height="806" alt="IMG_6776" src="https://github.com/user-attachments/assets/8016d1ce-f04c-44ff-8666-cfd2a0dc9c0c" />

# AntiDarkSword ⚔️

AntiDarkSword is an advanced iOS security tweak designed to harden jailbroken devices against WebKit and iMessage-based exploits. It significantly reduces your device's attack surface by neutralizing common vectors used in one-click and zero-click attacks.

---

## 🔍 How the Protection Works (Allow-By-Default)

To protect yourself, you must go into the tweak settings and explicitly **RESTRICT** the apps you want to lock down. You can do this manually by selecting specific apps, or by enabling the built-in **Preset Rules** tiers. 

> **Note:** Restricting an app means it will no longer be able to run interactive web elements. Web pages will still load text and images (HTML/CSS), but apps built with native UI like YouTube and Discord will continue to function normally.

## ✨ Features

* **WebKit Hardening:** Forcibly disables JavaScript execution, inline media playback, Picture-in-Picture, WebGL, WebRTC (peer connections), and local file access within targeted web views.
* **iMessage Mitigation:** Defends against BlastPass/FORCEDENTRY-style attacks by disabling automatic attachment downloading and preview generation.
* **User Agent Spoofing:** Globally spoof the `WKWebView` Custom User Agent for restricted apps to bypass strict fingerprinting modules. Includes modern presets (iOS 18.1, Android Chrome, Windows Edge, macOS, etc.) or the ability to inject a custom string.
* **Tiered Protection:**
  * **Level 1:** Protects native Apple apps and services.
  * **Level 2:** Expands protection to major third-party browsers and social media apps.
  * **Level 3:** Locks down critical system daemons to prevent daemon-level zero-clicks.
* **Custom Targeting:** Manually specify bundle IDs or process names to restrict specific apps or background tasks.

> [!WARNING]
> **Level 1 disables email and text previews of files.** You have to hold the file down and save it to the Files app to view it. 
> 
> **Level 3 restricts critical background daemons.** `imagent` and `mediaserverd` filtering may break media playback in some apps.

## 🛑 Mitigated Exploits

By disabling WebKit and JavaScriptCore attack vectors, this tweak prevents several known exploit chains:

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
* **Architecture:** arm64 / arm64e (A11 through A16/M-series)
* **Jailbreaks:** * **Rootless:** Dopamine (iOS 15.0 – 17.0), Palera1n (iOS 15.0 – 16.7.x)
  * **Roothide:** Dopamine Roothide 2 (via Roothide Patcher)
  * **Rootful:** Palera1n / Checkm8 users should use: [AntiDarkSword-rootful](https://github.com/EolnMsuk/AntiDarkSword-rootful)

## 📦 Dependencies

Before installing this tweak, you **must** install the following from your package manager (Sileo/Zebra):

* `mobilesubstrate`
* `preferenceloader`
* `com.opa334.altlist` (AltList)

## 🛠️ Installation Instructions

### Option 1: Installation (Rootless)
1. Navigate to the **[Releases](https://github.com/EolnMsuk/AntiDarkSword/releases)** page of this repository.
2. Click on the latest release version.
3. Under the **Assets** section, download the attached `.deb` file.
4. Open the `.deb` file on your iPhone and install it via your preferred package manager (Sileo, Zebra, or Filza).
5. Respring your device.

### Option 2: Installation (Roothide)
If you are using Dopamine Roothide 2 to bypass jailbreak detection, you must patch the `.deb` before installing:
1. Download the `.deb` file from the **[Releases](https://github.com/EolnMsuk/AntiDarkSword/releases)** page.
2. Send the file to your iPhone.
3. Open the **Roothide Patcher** app.
4. Select the `.deb` file and let the app convert the rootless paths to dynamic Roothide paths.
5. Open the newly generated `-roothide.deb` file in **Sileo** or **Filza**, tap Install, and Respring.

## ⚙️ Configuration

1. Open your iPhone's native **Settings** app.
2. Scroll down to the Tweak section and tap **AntiDarkSword**.
3. Toggle **ON** the master `Enable Protection` switch.
4. **User Agent Spoofing:** Select a preset modern user agent (or enter a custom string) to spoof fingerprinting payloads. Select "None" to disable.
5. Choose your protection rules (Preset and Manual rules can be combined!):
   * **Preset Rules:** Turn on `Enable Preset Rules` and select Level 1, 2, or 3 for immediate, system-wide coverage. You can individually toggle specific apps from that tier on or off directly on the main page.
   * **Manual Selection:** Use the **Select Apps...** menu to individually turn ON restrictions for specific apps. Active apps will appear as a quick-toggle list directly below the button.
6. Use the **Add Custom Bundle ID / Process** button to paste comma-separated lists of hidden background daemons you wish to restrict. Active custom rules will appear as a list; swipe left on any ID to delete it.
7. Tap the **Save** button in the top right corner (available in both the main menu and app list) to apply your new security rules and respring/reboot userspace.
8. To quickly clear your settings, use the **Reset to Defaults** button at the bottom of the main menu.

> [!WARNING]
> **Remove any apps you want secured from Roothide's Blacklist app.** This allows the tweak to filter that app.

---

## 👨‍💻 Developer

Created by: [EolnMsuk](https://github.com/EolnMsuk)

Donate 🤗: [eolnmsuk](https://venmo.com/user/eolnmsuk)
