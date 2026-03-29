# AntiDarkSword 🛡️

**A nuclear system-wide WebKit & JavaScriptCore kill-switch for modern iOS.**

AntiDarkSword is an aggressive security mitigation tweak designed to stop zero-click, JIT-based, and drive-by WebKit exploits (such as Coruna and DarkSword) before they can execute. Rather than relying on easily bypassed string-matching heuristics, this tweak hooks directly into `WKWebView` and the underlying C-level `JSEvaluateScript` functions to forcefully strip the JavaScript engine from web views across the entire operating system.

If an exploit requires JavaScript to trigger memory corruption or type confusion, this tweak mathematically prevents it from running at step zero.

## ⚠️ The "Scorched Earth" Warning
This is a highly aggressive mitigation. By default, **this tweak will break interactive web functionality** in any app it applies to. Web pages will still load HTML/CSS, but dropdowns, dynamic logins (like Google OAuth), and web-based UI elements will fail. 

To prevent your core apps (like Safari or YouTube) from breaking, you **must** whitelist them in the tweak preferences.

## 📱 Compatibility
* **iOS Versions:** iOS 15.0 - 17.0
* **Architecture:** arm64 / arm64e (A11 through A16/M-series)
* **Jailbreaks:** * Rootless / Roothide (via Patcher): Dopamine (iOS 15.0 - 17.0), Palera1n (iOS 15.0 - 16.7.x)

## ✨ Features
* **System-Wide JIT Denial:** Hooks `WKWebView` and `JavaScriptCore` via MobileSubstrate.
* **AltList Integration:** Easily whitelist specific User or System apps natively via the Settings app. Whitelisted apps will bypass the JS kill-switch.
* **Advanced Exceptions:** Manually enter hidden bundle IDs or custom daemon processes that do not appear in standard app lists.
* **No Daemon Panics:** Strictly filtered to `com.apple.UIKit` to ensure invisible system background daemons do not crash your device.
* **Persistent UI:** Includes a top-right Respring button in the Settings menu for immediate application of changes.

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
3. Under the "Whitelist" section, select any apps (like Safari, Chrome, or YouTube) that you want to allow to run JavaScript normally.
4. Tap the **Respring** button in the top right corner to apply changes.

## 👨‍💻 Developer
Created by **eolnmsuk**
