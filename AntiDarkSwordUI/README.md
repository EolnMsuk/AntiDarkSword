# AntiDarkSwordUI

The UIKit-layer tweak of [AntiDarkSword](../README.md). It injects into apps and UI services to harden WebKit against browser-based exploits and add a second layer of iMessage attachment blocking on top of what the daemon tweak does.

---

## Where it injects

The injection filter (`AntiDarkSwordUI.plist`) targets any process that loads `com.apple.UIKit` — meaning every app and UI service on the device. The tweak then gates itself in `%ctor` so it only actually runs in processes that are relevant:

- **User apps** — anything installed under `/Containers/Bundle/Application/`
- **System / jailbreak apps** — anything installed under `/Applications/`
- **Specific Apple services** — `SafariViewService`, `MailCompositionService`, `iMessageAppsViewService`, `ActivityMessagesApp`, `QuickLookUIService`, `QuickLookDaemon`
- **Manual overrides** — any bundle ID or process name the user has explicitly added in the custom rules list or app selection screen

App Extensions (`.appex` bundles) are gated in `%ctor` via a parent-aware check rather than a blanket block:

- **Apple NSEs** (`com.apple.messages.NotificationServiceExtension`, `com.apple.MailNotificationServiceExtension`) pass unconditionally — they process iMessage and Mail attachment payloads before the user opens the app, making them a silent zero-click surface.
- **All other extension types** (share extensions, notification content extensions, iMessage app extensions) pass only if their parent app is a protected target — either in tier1/tier2 or added as a manual override. The parent app bundle ID is resolved by stripping the extension path (`Extension.appex` → `PlugIns/` → `Parent.app`) and reading the parent bundle's `NSBundle.bundleIdentifier`. Extensions of protected parents carry the same web-content and attachment attack surface as the parent app.
- Extensions of unprotected apps are fast-exited and incur no overhead.

Known noisy background processes (`cfprefsd`, `Spotlight`, `Preferences`, `Tunnel`, etc.) are also filtered out to avoid unnecessary memory and log overhead.

---

## What it protects

### JIT Disable

Prevents the WebKit JavaScript engine from using the Just-In-Time compiler, which is the execution primitive that most browser exploits rely on.

- **iOS 16+**: Sets `WKWebpagePreferences.lockdownModeEnabled = YES` (the same mechanism the system uses for Lockdown Mode) **and** additionally sets `_WKProcessPoolConfiguration.JITEnabled = NO` via the private process pool API. Both mechanisms are applied together for maximum coverage — lockdown mode is the primary path; the pool config is a belt-and-suspenders fallback.
- **iOS 15**: Sets `_WKProcessPoolConfiguration.JITEnabled = NO` via the private process pool configuration API only (lockdown mode is not available).

Both paths are applied via `WKWebViewConfiguration` at the moment a `WKWebView` is initialized, so they take effect before any page loads.

Two additional setter hooks prevent an exploit (or the host app) from re-enabling JIT after the tweak has disabled it:
- `WKWebpagePreferences -setLockdownModeEnabled:` — if `applyDisableJIT` is set and the caller tries to pass `NO`, the call is silently dropped.
- `_WKProcessPoolConfiguration -setJITEnabled:` — if either `applyDisableJIT` or `applyDisableJIT15` is set and the caller tries to pass `YES`, the call is silently dropped.

### JavaScript Blocking

Five separate hooks work together to prevent JavaScript execution, covering both the public API surface and the lower-level C function underneath:

| Hook | What it catches |
|---|---|
| `WKWebpagePreferences.allowsContentJavaScript` setter | New-style JS enable path (iOS 14+) |
| `WKPreferences.javaScriptEnabled` setter | Legacy JS enable path |
| `WKWebView.evaluateJavaScript:completionHandler:` | Programmatic JS execution (returns an error to the caller) |
| `WKWebView.evaluateJavaScript:inFrame:inContentWorld:completionHandler:` | Content world variant |
| `WKWebView.callAsyncJavaScript:...` | Async JS variant |
| `JSEvaluateScript` (C function via `%hookf`) | JavaScriptCore C API, catches JS execution that bypasses the ObjC layer |
| `UIWebView.stringByEvaluatingJavaScriptFromString:` | Legacy UIWebView neutralization |

All seven return a clean error or empty result to the caller — they don't crash or leave the caller hanging.

### Media Autoplay Blocking

Prevents audio and video from loading automatically, which removes a class of attack where a crafted media file triggers parsing bugs:

- `WKWebViewConfiguration.allowsInlineMediaPlayback = NO`
- `WKWebViewConfiguration.mediaTypesRequiringUserActionForPlayback = WKAudiovisualMediaTypeAll`
- `WKWebViewConfiguration.allowsPictureInPictureMediaPlayback = NO`

### WebGL & WebRTC Blocking

Disables GPU-accelerated rendering and peer-to-peer connection APIs by writing private `WKPreferences` keys via `setValue:forKey:`. These are wrapped in `@try`/`@catch` since they use internal keys that Apple can remove in future OS versions without notice:

- `webGLEnabled`
- `mediaStreamEnabled`
- `peerConnectionEnabled`

### Local File Access Blocking

Prevents WebView content from reading files off the device via `file://` URLs — a common exfiltration vector in staged attacks:

- `allowFileAccessFromFileURLs`
- `allowUniversalAccessFromFileURLs`

Both are also private `WKPreferences` keys.

### User Agent Spoofing

Replaces the real device UA with a configured string to break fingerprinting used by exploits that only target specific device/OS combinations (DarkSword and Coruna both check UA before deploying payloads).

Four hooks combine to make the spoof stick:

1. **`WKWebView.customUserAgent` setter** — intercepts any attempt to set a custom UA and forces it to the spoofed string.
2. **`WKWebViewConfiguration.applicationNameForUserAgent` setter** — cleared to an empty string to prevent the app name from leaking into the real UA.
3. **JS navigator override** — a `WKUserScript` injected at document start uses `Object.defineProperty` to override `navigator.userAgent`, `navigator.appVersion`, `navigator.platform`, `navigator.vendor`, and `navigator.userAgentData` (the Client Hints API, iOS 16+). This means even JS that reads these properties directly gets the spoofed values.
4. **HTTP header override in `loadRequest:`** — if the outgoing request already has a `User-Agent` header that doesn't match the spoofed string, the request is mutated before it goes out.

The `navigator.platform`, `navigator.vendor`, and `navigator.userAgentData.brands` values are all derived from the UA string (e.g., a Chrome Android UA gets `"Linux aarch64"` / `"Google Inc."` / a Chromium brands array), so the entire JS navigator environment is internally consistent rather than a half-spoofed mix.

### iMessage UI-Layer Blocking

Hooks `IMFileTransfer` (from IMCore) and `CKAttachmentMessagePartChatItem` (from ChatKit) inside the iMessage UI processes (`com.apple.MobileSMS`, `com.apple.iMessageAppsViewService`, `com.apple.ActivityMessagesApp`):

- `IMFileTransfer.isAutoDownloadable` → `NO`
- `IMFileTransfer.canAutoDownload` → `NO`
- `CKAttachmentMessagePartChatItem._needsPreviewGeneration` → `NO`

When `applyBlockRiskyAttachments` is active, `CKAttachmentMessagePartChatItem.fullSizeImageURL` additionally returns `nil` for attachments with HEIC, HEIF, WebP, or PDF extensions. This prevents the Messages/QuickLook preview pipeline from handing the raw file to ImageIO — a recurring zero-click attack surface (FORCEDENTRY used JBIG2-in-PDF; BLASTPASS used HEIC/WebP). Controlled by the `blockRiskyAttachments` per-app rule; defaults off.

This is a second layer of defense. The daemon tweak hooks the same `IMFileTransfer` methods at the `imagent`/`IMDPersistenceAgent` level before content ever reaches the UI. If the daemon layer is bypassed or not active, these UI-layer hooks are a fallback that stops the attachment from being processed in the UI process.

### Remote Content Blocking

A `WKContentRuleList` rule (identifier `com.eolnmsuk.ads.remoteblock`) blocks all external `http`/`https` resource loads — images, scripts, fonts, and media — from inside WebViews. It is compiled once in `%ctor` asynchronously (WebKit caches the compiled result across launches) and applied per `WKWebView` when `applyBlockRemoteContent` is active.

Default behaviour: enabled automatically for messaging and mail apps and QuickLook services; disabled for browsers and general apps so normal browsing is unaffected. Users can override per-app via the Settings UI or set `globalBlockRemoteContent` to enforce it everywhere.

---

## How targeting works

`loadPrefs()` runs on `%ctor` and on every Darwin notification from the preferences panel. It determines whether the current process should be protected and which mitigations apply.

### Process matching

The current process's bundle ID, process name, and (for extension processes) the parent app bundle ID are checked in that order against:

1. **Custom daemon IDs** (`activeCustomDaemonIDs`) — user-added process names
2. **Manual app rules** (`restrictedApps`, `restrictedApps-<bundleID>`) — apps enabled via the app selection screen
3. **Auto-protection tiers** — if neither of the above matched, the tiered preset lists are checked:
   - Tier 1 (always active): core Apple apps — Safari, Messages, Mail, Notes, Books, News, QuickLook, and their companion services
   - Tier 2 (Level 2+): third-party browsers, messaging apps, social media, finance, and jailbreak package managers
   - Tier 3 (Level 3+): intentionally empty in the UI tweak — tier 3 is daemon processes, handled exclusively by `AntiDarkSwordDaemon`

### Per-mitigation resolution

Each mitigation flag (`applyDisableJIT`, `applyDisableJS`, etc.) is resolved as:

```
global override  OR  (process is restricted  AND  per-app rule is ON)
```

Global overrides apply the mitigation to every process the tweak loads into, regardless of the tier or app list. Per-app rules come from `TargetRules_<bundleID>` preference keys, which the settings UI writes when you configure a specific app in the preset rules list or manual rules screen. For extension processes, `TargetRules_<extensionBundleID>` (plugin-specific, configured via the "App Plugins" sub-menu) takes priority over `TargetRules_<parentBundleID>`; if no plugin-specific entry exists the parent app's rules are inherited.

### Thread safety

Hook methods can fire on any thread. All flags that hooks read at call time (`applyDisableJIT`, `applyDisableJS`, `shouldSpoofUA`, etc.) are declared `_Atomic`. Flags that are only ever read and written within `loadPrefs()` itself (global overrides, intermediate per-app values) use plain `BOOL`. The `prefsLoaded` gate uses an atomic compare-and-swap to prevent two threads from running `loadPrefs()` concurrently.

---

## Hook entry points

| Hook | Trigger |
|---|---|
| `WKWebView -initWithFrame:configuration:` | Every new WKWebView created in code |
| `WKWebView -initWithCoder:` | WKWebViews loaded from storyboard/NIB |
| `WKWebView -loadRequest:` | Per-navigation JS and UA enforcement |
| `WKWebView -loadHTMLString:baseURL:` | Same for local HTML loads |
| `WKWebView -setCustomUserAgent:` | Prevents apps from overriding the spoofed UA after init |
| `WKWebViewConfiguration -setUserContentController:` | Injects UA script when a new content controller is assigned |
| `WKWebViewConfiguration -setApplicationNameForUserAgent:` | Clears app name UA suffix |
| `WKWebpagePreferences -setAllowsContentJavaScript:` | Blocks re-enabling JS via the page preference object |
| `WKWebpagePreferences -setLockdownModeEnabled:` | Drops calls that try to disable lockdown mode when `applyDisableJIT` is active |
| `_WKProcessPoolConfiguration -setJITEnabled:` | Drops calls that try to re-enable JIT when `applyDisableJIT` or `applyDisableJIT15` is active |
| `WKPreferences -setJavaScriptEnabled:` | Blocks re-enabling JS via the legacy preference |
| `WKWebView -evaluateJavaScript:...` (3 variants) | Blocks runtime JS execution calls |
| `JSEvaluateScript` (C function) | Blocks C-level JS execution |
| `UIWebView -stringByEvaluatingJavaScriptFromString:` | Neutralizes legacy UIWebView |
| `IMFileTransfer -isAutoDownloadable` | iMessage attachment auto-download (UI layer) |
| `IMFileTransfer -canAutoDownload` | iMessage attachment auto-download (UI layer) |
| `CKAttachmentMessagePartChatItem -_needsPreviewGeneration` | Attachment preview generation |
| `CKAttachmentMessagePartChatItem -fullSizeImageURL` | Returns `nil` for HEIC/HEIF/WebP/PDF attachments when `applyBlockRiskyAttachments` is active |
