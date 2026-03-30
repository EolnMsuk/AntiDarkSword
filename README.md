# AntiDarkSword 🛡️

**A targeted system-wide WebKit & JavaScriptCore kill-switch for modern iOS.**

AntiDarkSword is a security mitigation tweak designed to stop zero-click, JIT-based, and drive-by WebKit exploits (such as Coruna and DarkSword) before they can execute. This tweak hooks directly into `WKWebView` and the underlying C-level `JSEvaluateScript` functions to forcefully strip the JavaScript engine from web views.

If an exploit requires JavaScript to trigger memory corruption or type confusion, this tweak mathematically prevents it from running at step zero.

## ⚠️ How the Protection Works (Allow-By-Default)
To protect yourself, you must go into the tweak settings and explicitly **RESTRICT** the apps you want to lock down. You can do this manually by selecting specific apps, or by enabling the built-in **Preset Rules** tiers. 

*Note: Restricting an app means it will no longer be able to run interactive web elements. Web pages will still load text and images (HTML/CSS), but apps built with native UI like YouTube and Discord will continue to function normally.*

## 🛑 Mitigated Exploits
By disabling WebKit and JavaScriptCore attack vectors, this tweak can prevent several known exploit chains:
* **DarkSword:** Full-chain, JavaScript-based zero-click exploit kit (iOS 18.4 – 18.7).
* **Coruna:** JavaScript-reliant iOS exploit kit (iOS 13.0 – 17.2.1).
* **Predator:** Safari JavaScript 1-click spyware (Versions before iOS 16.7).
* **BLASTPASS:** iMessage zero-click using PassKit attachments (Versions before iOS 16.6.1).
* **PWNYOURHOME:** Zero-click targeting HomeKit or iCloud Photos (iOS 15.0 – 16.3.1).
* **CVE-2025-43529:** Recent WebKit zero-day using memory corruption (Versions prior to iOS 18.7.3 and iOS 26.2).
* **CVE-2024-44308:** WebKit remote code execution via web content (Versions before iOS 17.7.2 and iOS 18.1.1).
* **CVE-2022-42856:** JavaScriptCore type confusion in JIT compiler (iOS 16.0 to 16.1.1 and earlier).
* **Operation Triangulation:** iMessage WebKit zero-click chain (iOS 15.7 and older).
* **Hermit:** JavaScriptCore type-confusion spyware chain (iOS 15.0 – 15.4.1).
* **KISMET:** iMessage rich link zero-click (Vulnerable prior to iOS 14).
* **Trident:** Safari memory corruption exploit chain (iOS versions ≤ 9.3.4).
* **Chaos:** Safari WebKit DOM vulnerability exploit (Versions older than 16.3).
* **FORCEDENTRY:** Zero-click bypassing BlastDoor via PDF/GIF (Versions before iOS 14.8).
* **Megalodon:** Variant of the FORCEDENTRY zero-click attack (Versions before iOS 14.8).

## 🛡️ Preset Rule Levels
AntiDarkSword includes a Preset Rules feature that automatically applies surgical restrictions to high-risk applications and daemons based on three escalating security tiers.

### Level 1: Native Apple Apps & Services
Restricts JavaScript and WebKit execution in all pre-installed, native Apple applications and their underlying services. Protects against drive-by exploits, malicious calendar invites, rigged emails, and zero-click links.
* **The Frontline:** Safari, Messages, Mail.
* **Silent Parsers:** Calendar, Notes, Books.
* **Content Consumers:** Apple News, Podcasts, Stocks, Maps, Weather.
* **System View Services:** Safari View Service (SFSafariViewController in-app browsers), Mail Composition Service, iMessage Apps View Service & Activity Messages (iMessage extensions, stickers, and games).

### Level 2: Third-Party Apps & Package Managers
*Includes everything in Level 1, plus:* Extends the lockdown to non-Apple applications that heavily rely on custom in-app browsers or mandate the use of the WebKit engine.
* **Third-Party Browsers:** Google Chrome, Mozilla Firefox, Brave Browser, DuckDuckGo.
* **Social Media & Messaging:** WhatsApp, Telegram, Facebook, X / Twitter, Instagram, TikTok, LinkedIn.
* **Jailbreak Package Managers:** Sileo, Zebra, Filza (prevents compromised repositories from injecting payloads via tweak depictions).

### Level 3: Extreme Lockdown (System Daemons)
*Includes everything in Levels 1 and 2, plus:* This is the maximum lockdown tier geared toward neutralizing complex zero-click exploit chains (like BLASTPASS or FORCEDENTRY) before they can even be parsed. 
* **Restricted Daemons:** `imagent` (handles incoming iMessages/FaceTime), `mediaserverd` (audio/video parsing), `networkd` (socket connections).
* **iMessage Clarification:** You DO NOT need to disable iMessage in your iOS Settings. Level 3 acts as a shield by restricting the background `imagent` daemon. You will still receive texts and notifications, but rich link previews and automatic attachment downloading will be blocked to prevent zero-click memory corruption.
* **⚠️ WARNING:** Restricting critical background daemons **will** break normal device functions like iMessage background delivery (as mentioned above), media playback, and certain network features. ONLY enable if you know what you are doing!

## 📱 Compatibility
* **iOS Versions:** iOS 15.0 - 17.0
* **Architecture:** arm64 / arm64e (A11 through A16/M-series)
* **Jailbreaks:** * Rootless: Dopamine (iOS 15.0 - 17.0), Palera1n (iOS 15.0 - 16.7.x)
  * Roothide: Dopamine Roothide 2 (via Roothide Patcher)

## ✨ Features
* **Surgical JIT Denial:** Hooks `WKWebView` and `JavaScriptCore` via MobileSubstrate.
* **Preset Rules System:** 3 escalating tiers of automatic exploit mitigation.
* **AltList Integration:** Easily restrict specific User or System apps manually natively via the Settings app.
* **Advanced Restrictions:** Paste comma-separated lists of hidden bundle IDs or custom daemon process names to dynamically generate UI switches. Includes native swipe-to-delete functionality for easy management.
* **No Daemon Panics:** Strictly filtered to ensure invisible system background daemons do not crash your device, with a process name fallback for daemons lacking standard bundles.
* **Persistent UI Controls:** Includes a top-right Save button pinned to both the main Settings menu and the App Selection list for immediate application of changes.
* **Safe Defaults:** Includes a "Reset to Defaults" option to quickly wipe all custom configurations and return the tweak to a safe, unrestrictive state.

## 📦 Dependencies
Before installing this tweak, you **must** install the following from your package manager (Sileo/Zebra):
* `mobilesubstrate`
* `preferenceloader`
* `com.opa334.altlist` (AltList)

## 🛠️ Installation Instructions

### Option 1: Direct Installation (Rootless)
1. Navigate to the **Actions** tab of this repository.
2. Click the latest successful `Compile Tweak` workflow run.
3. Download the `AntiDarkSword-Rootless.deb` artifact at the bottom of the page.
4. Transfer the `.deb` to your iPhone and install via Filza, Sileo, or Zebra.
5. Respring your device.

### Option 2: Dopamine Roothide Installation
If you are using Dopamine Roothide 2 to bypass jailbreak detection, you must patch the `.deb` before installing:
1. Download the `AntiDarkSword-Rootless.deb` artifact from the Actions tab.
2. Send the file to your iPhone.
3. Open the **Roothide Patcher** app.
4. Select the `.deb` file and let the app convert the rootless paths to dynamic Roothide paths.
5. Open the newly generated `-roothide.deb` file in **Filza**, tap Install, and Respring.

## ⚙️ Configuration
1. Open your iPhone's native **Settings** app.
2. Scroll down to the Tweak section and tap **AntiDarkSword**.
3. **Turn ON** the master Enable Protection switch.
4. Choose your protection method:
   * **Preset Rules:** Turn on Enable Preset Rules and select Level 1, 2, or 3 for immediate, system-wide coverage.
   * **Manual Selection:** If Preset Rules are off, use the **Select Apps...** menu to individually turn ON restrictions for specific apps (all are OFF by default).
5. Use the **Add Custom Bundle ID / Process** button to paste comma-separated lists of hidden background daemons you wish to restrict. Swipe left on any generated custom ID to delete it.
6. Tap the **Save** button in the top right corner (available in both the main menu and app list) to apply your new security rules and respring.
7. To quickly clear your settings, use the **Reset to Defaults** button at the bottom of the main menu.

## 👨‍💻 Developer
Created by [eolnmsuk](https://venmo.com/user/eolnmsuk)
