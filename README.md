# AntiDarkSword 🛡️

**A targeted system-wide WebKit & JavaScriptCore kill-switch for modern iOS.**

AntiDarkSword is a security mitigation tweak designed to stop zero-click, JIT-based, and drive-by WebKit exploits (such as Coruna and DarkSword) before they can execute. This tweak hooks directly into `WKWebView` and the underlying C-level `JSEvaluateScript` functions to forcefully strip the JavaScript engine from web views.

If an exploit requires JavaScript to trigger memory corruption or type confusion, this tweak mathematically prevents it from running at step zero.

## ⚠️ How the Protection Works (Allow-By-Default)
To protect yourself, you must go into the tweak settings and explicitly **RESTRICT** the apps you want to lock down (such as Safari, Messages, Mail, Facebook etc). 

*Note: Restricting an app means it will no longer be able to run interactive web elements. Web pages will still load text and images (HTML/CSS), but apps built with native UI like YouTube and Discord will continue to function normally.*

## 🛑 Mitigated Exploits
By disabling WebKit and JavaScriptCore attack vectors, this tweak can prevent several known exploit chains:
* **Coruna:** JavaScript-reliant iOS exploit kit.
* **Operation Triangulation:** iMessage WebKit zero-click chain.
* **Predator:** Safari JavaScript 1-click spyware.
* **Hermit:** JavaScriptCore type-confusion spyware chain.
* **KISMET:** iMessage rich link zero-click.
* **Trident:** Safari memory corruption exploit chain.
* **Chaos:** Safari WebKit DOM vulnerability exploit.

## 🛡️ Recommended Native Apps to Restrict
For a paranoid-level lockdown, you should disable JavaScript for the following native Apple applications in the tweak settings to eliminate silent attack vectors:

### Tier 1: The Frontline (Critical)
* **Safari** (`com.apple.mobilesafari`): The primary target for drive-by web exploits.
* **Messages** (`com.apple.MobileSMS`): Generates rich link previews and processes incoming data automatically.
* **Mail** (`com.apple.mobilemail`): Renders complex HTML, CSS, and tracking pixels in incoming emails. 

### Tier 2: The Silent Parsers (High Risk)
* **Calendar** (`com.apple.mobilecal`): Malicious calendar invites can contain rigged HTML descriptions or web-based attachments.
* **Notes** (`com.apple.mobilenotes`): iCloud shared notes process rich web links and formatted HTML.
* **Books** (`com.apple.iBooks`): EPUB files are ZIP archives containing HTML and JavaScript. A malicious book file can trigger a WebKit exploit.

### Tier 3: The Content Consumers (Moderate Risk)
* **Apple News** (`com.apple.news`): Renders its articles and third-party ad networks almost entirely via WebKit.
* **Podcasts** (`com.apple.podcasts`): Uses web views to render complex, formatted show notes that contain links.
* **Stocks** (`com.apple.stocks`): Pulls in and renders web-based financial news articles.
* **Maps** (`com.apple.Maps`): Embeds web content for business listings, Wikipedia snippets, and Yelp integrations.
* **Weather** (`com.apple.weather`): Occasionally pulls in web-based news alerts for severe weather events.

## 🌐 Recommended Third-Party & Jailbreak Apps to Restrict
If you use the following third-party applications, they should also be restricted as they rely heavily on embedded WebKit views that can be targeted by attackers.

### Third-Party Web Browsers
Apple mandates that all iOS browsers use the WebKit engine. If you use an alternative default browser, it is just as vulnerable as Safari.
* **Google Chrome** (`com.google.chrome.ios`)
* **Mozilla Firefox** (`org.mozilla.ios.Firefox`)
* **Brave Browser** (`com.brave.ios.browser`)
* **DuckDuckGo** (`com.duckduckgo.mobile.ios`)

### Social Media & Messaging
These apps frequently utilize custom in-app browsers to open links, bypassing standard protections.
* **WhatsApp** (`net.whatsapp.WhatsApp`)
* **Telegram** (`ph.telegra.Telegraph`)
* **Facebook** (`com.facebook.Facebook`)
* **X / Twitter** (`com.atebits.Tweetie2`)
* **Instagram** (`com.burbn.instagram`)
* **TikTok** (`com.zhiliaoapp.musically`)
* **LinkedIn** (`com.linkedin.LinkedIn`)

### Jailbreak Package Managers
Package managers render tweak depictions by fetching HTML from external repositories. A compromised repository could inject a WebKit payload directly into the package manager.
* **Sileo** (`org.coolstar.sileo`)
* **Zebra** (`xyz.willy.Zebra`)
* **Filza** (`com.tigisoftware.Filza`)

## 📱 Compatibility
* **iOS Versions:** iOS 15.0 - 17.0
* **Architecture:** arm64 / arm64e (A11 through A16/M-series)
* **Jailbreaks:** * Rootless: Dopamine (iOS 15.0 - 17.0), Palera1n (iOS 15.0 - 16.7.x)
  * Roothide: Dopamine Roothide 2 (via Roothide Patcher)

## ✨ Features
* **Surgical JIT Denial:** Hooks `WKWebView` and `JavaScriptCore` via MobileSubstrate.
* **AltList Integration:** Easily restrict specific User or System apps natively via the Settings app.
* **Advanced Restrictions:** Manually enter hidden bundle IDs or custom daemon processes that do not appear in standard app lists.
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
3. You will see an option to list your apps. **All switches are ON by default.**
4. **Turn OFF** the switch for any app you wish to protect. Turning it off strips its ability to run JavaScript.
5. Tap the **Respring** button in the top right corner to apply your new security rules.

## 👨‍💻 Developer
Created by [eolnmsuk](https://venmo.com/user/eolnmsuk)
