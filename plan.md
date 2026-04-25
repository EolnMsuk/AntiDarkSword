# AntiDarkSword — Strategic Enhancement Roadmap

Generated: 2026-04-25.

Priority ranking: **Critical** (security gap) > **High** (significant coverage expansion) > **Medium** (hardening / UX) > **Low** (quality of life).

---

## 1. [Critical] WKNavigationDelegate-level Per-Navigation Policy Enforcement

**Problem:** The current architecture sets mitigation flags at WebView *configuration* time. Once a `WKWebView` is live, injecting JS blocks via `loadRequest:` hook mutates the shared `defaultWebpagePreferences` — a pattern Apple explicitly marks as undefined for live WebViews. Any app that creates a single shared `WKWebViewConfiguration` and reuses it across multiple WebViews can observe partial or missed enforcement when the configuration is mutated mid-flight.

**Proposal:** Add a `WKNavigationDelegate` swizzle that injects a proxy delegate before the first `decidePolicyForNavigationAction:decisionHandler:` call. The proxy:
1. Creates a fresh `WKWebpagePreferences` per navigation.
2. Sets `allowsContentJavaScript`, `lockdownModeEnabled` according to live atomic flags.
3. Passes back via `decisionHandler(WKNavigationActionPolicyAllow, pagePrefs)`.

This replaces the `loadRequest:`/`loadHTMLString:` configuration mutation entirely. The proxy uses method swizzling on the app's delegate class (not a hook on the WKWebView itself) to avoid interaction with other tweaks that hook WKWebView directly.

**Architectural change:** Add `ADSNavigationProxy` class to `AntiDarkSwordUI` and `AntiDarkSwordTF`. Hook `WKWebView setNavigationDelegate:` to inject/wrap the delegate. Store the original delegate as a `weak` property and forward all other delegate methods via `forwardInvocation:`.

---

## 2. [Critical] iMessage NSE (Notification Service Extension) Interception

**Problem:** iOS 15+ delivers rich iMessage notifications via a Notification Service Extension (`com.apple.messages.NotificationServiceExtension`). AntiDarkSword's `%ctor` fast-exit condition rejects `.appex` bundle paths, meaning the NSE process is never hooked. A BLASTPASS-style attachment exploit delivered via a notification (before the user opens Messages) operates entirely within the NSE process, which is currently unprotected.

**Proposal:**
1. Remove the `.appex` blanket fast-exit. Replace with a targeted allowlist of specific NSE bundle IDs: `com.apple.messages.NotificationServiceExtension`, `com.apple.MailNotificationServiceExtension`.
2. For NSE targets, install only the `IMFileTransfer` iMessage-DL hook and the `WKWebView` hooks — skip UA spoofing and JIT hooks (irrelevant in NSEs).
3. Add `com.apple.messages.NotificationServiceExtension` and `com.apple.MailNotificationServiceExtension` to tier1 preset.

**Risk:** NSE processes have a tight memory budget (~50 MB). The tweak binary size is small, but loading `WebKit.framework` (for WKWebView hooks) in an NSE that doesn't already use it wastes ~8 MB. Solution: gate the WebKit hooks on `dlopen("/System/Library/Frameworks/WebKit.framework/WebKit", RTLD_NOLOAD)` — only hook if WebKit is already loaded in the process.

---

## 3. [High] Image I/O / CoreGraphics Attack-Surface Reduction

**Problem:** The ImageIO/CoreGraphics parsing stack (JPEG, HEIC, PNG, PDF) is a recurrent zero-click attack surface (e.g., FORCEDENTRY exploited JBIG2 in PDF rendering; BLASTPASS exploited WebP/HEIC). AntiDarkSword currently has no mitigation against image-parsing exploits triggered in iMessage or Mail attachment previews.

**Proposal:**
- **Short-term:** Hook `QLPreviewController presentPreviewAnimated:` and `QLPreviewItem` creation in `com.apple.quicklook.QuickLookUIService` to intercept attachment previews. Block preview for HEIC/HEIF files from unknown senders (require explicit user confirmation).
- **Medium-term:** Add a `com.apple.MobileSMS` hook on `CKAttachmentMessagePartChatItem` that intercepts the `fullSizeImageURL` accessor before QuickLook fetches it. If the MIME type is in a high-risk set (`image/webp`, `image/heic`, `application/pdf`), redirect the preview to a sandboxed WKWebView with a `data:` URI rather than passing the raw file to ImageIO/CoreGraphics.
- **Architecture:** New hook class `ADSAttachmentGuard` in `AntiDarkSwordUI`. Controlled by a new pref key `blockRiskyAttachmentPreviews` (default: `NO` to avoid breaking existing workflows; user opts in).

---

## 4. [High] `WKContentRuleList` for Jailbreak-Tweak Build (AntiDarkSwordUI)

**Problem:** AntiDarkSwordTF has a `WKContentRuleList` remote-content blocker, but `AntiDarkSwordUI` does not. Mail.app and iMessage WebViews in the jailbreak build are unprotected against remote resource loading.

**Proposal:** Port `adsContentBlocker` and its `applyBlockRemoteContent` atomic flag from `AntiDarkSwordTF` to `AntiDarkSwordUI`. Compile the list once in `%ctor` (same async pattern). Add `blockRemoteContent` to the per-app rule set and expose it as a toggle in `AntiDarkSwordAppController`. Default: `NO` for all apps except `com.apple.MobileSMS`, `com.apple.mobilemail`, `ch.protonmail.protonmail` (default `YES`).

**Prerequisite:** AntiDarkSwordUI links `WebKit.framework` already. No new framework dependency.

---

## 5. [High] Hardened Anti-Bypass for JS/JIT Re-Enabling

**Problem:** A sophisticated exploit payload that gains code execution inside a WKWebView renderer process can call `JSEvaluateScript` with a Corellium runtime check before AntiDarkSword's hook fires (race during early injection). Additionally, any tweak that runs after AntiDarkSword in the injection chain and calls `[WKPreferences setJavaScriptEnabled:YES]` without going through the hooked setter bypasses the guard.

**Proposal:**
1. **Process-level JIT entitlement check:** On iOS 16+, the renderer process requires `dynamic-codesigning` entitlement for JIT. Add a `%ctor` step that calls `csops(getpid(), CS_OPS_STATUS, …)` and verifies `CS_VALID | CS_RUNTIME` without `CS_ALLOW_UNSIGNED_EXECUTABLE_MEMORY`. If the renderer gained JIT after hook installation, post a Darwin notification (`com.eolnmsuk.antidarkswordprefs/jit_violation`) to trigger a Settings alert.
2. **WKPreferences KVO observation:** Register a KVO observer on the `WKPreferences` object inside the hooked WKWebView for the `javaScriptEnabled` key path. If it flips to `YES` outside of our setter hook (e.g., via direct ivar write), force it back and increment a tamper counter.

---

## 6. [Medium] Prefs Architecture: Migrate from NSUserDefaults to CFPreferences Direct Write

**Problem:** `AntiDarkSwordPrefsRootListController` writes prefs via `NSUserDefaults initWithSuiteName:`. NSUserDefaults on iOS uses `kCFPreferencesCurrentUser / kCFPreferencesCurrentHost`. The tweaks read via `CFPreferencesCopyMultiple` with `kCFPreferencesCurrentUser / kCFPreferencesAnyHost`. The host-key mismatch means that on some configurations (notably supervised devices or fresh Roothide installs where cfprefsd is sandboxed to a different host scope), the prefs written by the PreferenceLoader bundle are not visible to the tweaks until `CFPreferencesSynchronize` bridges the two host layers — sometimes with a 10–30 s delay.

**Proposal:** Replace all `NSUserDefaults` write paths in the prefs bundle with direct `CFPreferencesSetValue(..., kCFPreferencesCurrentUser, kCFPreferencesAnyHost)` + `CFPreferencesSynchronize` calls. This matches the host key used by the tweak's read path exactly. Update `ads_defaults()` to be a thin wrapper around the CFPreferences API rather than returning an `NSUserDefaults` instance.

**Risk:** Breaking change for users whose prefs are stored under `kCFPreferencesCurrentHost`. Migration code in `viewDidLoad` should detect the legacy host-keyed values and re-write them under `kCFPreferencesAnyHost` on first launch of the new version.

---

## 7. [Medium] Ephemeral WebKit Process Restart After Prefs Reload

**Problem:** When the user saves a pref change in Settings, `reloadPrefsNotification` updates all atomic flags, but live `WKWebView` instances in open apps retain their original configuration (including the UCC scripts and JIT/JS settings baked in at init time). The new settings only take effect for WebViews created after the reload. This creates a window where, e.g., disabling UA spoofing does not remove the already-injected `WKUserScript` from open Safari tabs.

**Proposal:** On `reloadPrefsNotification`, post a Darwin notification `com.eolnmsuk.antidarkswordprefs/webkitreset` (separate from `/saved` to avoid triggering in processes that do not need it). In `AntiDarkSwordUI`, observe this notification and:
1. Clear the `kADSUCCInjectedKey` associations on all known UCCs (via a weak `NSHashTable` of live UCCs).
2. If `shouldSpoofUA` changed from YES to NO, call `[ucc removeAllUserScripts]` and re-add any scripts the app itself had added (recoverable only if the app's scripts were captured at hook time — not trivial).

For the simpler near-term fix: on pref reload, if the tweak is disabled, enumerate all `WKWebView` instances via the private `+allWebViews` method (iOS 14+ private API, forward-declared) and call `webView.customUserAgent = nil` to restore the default.

---

## 8. [Medium] PreferenceLoader UX Modernisation

**Problems:**
- The Settings UI uses `PSListController` with a `PSTableCell` based layout. On iOS 16+ with Dynamic Island devices, the narrow safe area clips some cells.
- The auto-protect level is a segmented control with no visible description of what each level adds incrementally.
- The credentials screen with embedded SpriteKit games is only accessible via shake gesture, making it undiscoverable.
- No indication in the UI when the tweak is actively blocking something (no per-session activity log).

**Proposals:**
1. **Progressive disclosure for levels:** Replace the flat segmented control with a `PSLinkListCell` that pushes a dedicated level-selection screen. Each level shows a diff-view of what apps get added vs. the previous level, with icons.
2. **Activity badge:** Add a `PSStaticTextCell` at the top of the root screen that reads "X mitigations active today" by reading a daily counter written by the tweaks. Requires a new pref key `dailyMitigationCount` incremented in `reloadPrefsNotification` when any flag goes from false to true.
3. **Quick-access widget:** Add a WidgetKit extension that shows the master switch state and daily mitigation count. Requires a new App Group (or the existing suite can be used as the shared container for WidgetKit read access).
4. **iOS 17 Symbol animation support:** Replace the static `AntiDarkSword.png` banner with an `SKView` or `LottieView` animated shield on iOS 17+ devices.

---

## 9. [Medium] TrollFools: Secure Enclave / Biometric Gate for Settings Overlay

**Problem:** The three-finger double-tap gesture that opens `ADSTFSettingsViewController` is not authenticated. Any app (including a malicious one) can trigger the gesture programmatically by posting a synthesised touch sequence, gaining access to toggle all mitigations off.

**Proposal:** Gate the settings overlay presentation behind `LAContext evaluatePolicy:localizedReason:reply:` (Face ID / Touch ID). If authentication fails or the device has no biometry, fall back to a 6-digit PIN stored in the Keychain under `kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly`.

**Architecture:** Add `#import <LocalAuthentication/LocalAuthentication.h>` to `AntiDarkSwordTF/Tweak.x`. In `ads_show_settings_overlay`, authenticate before presenting `ADSTFSettingsViewController`.

---

## 10. [Low] Corellium Decoy: Realistic `/proc/…` and `sysfs`-Style Path Coverage

**Problem:** The current decoy spoofs `access`, `stat`, `lstat`, `sysctl hw.model`, `sysctl hw.machine`, `sysctl kern.boottime`. A more exhaustive Corellium detector may also probe:
- `/var/db/uuidtext/` (Corellium replaces this)
- `/System/Library/CoreServices/SystemVersion.plist` (Corellium patches `ProductVersion`)
- `getenv("CORELLIUM_ENV")` (Corellium sets this in some configurations)
- `NSBundle mainBundle infoDictionary[@"CFBundleIdentifier"]` consistency checks

**Proposal:**
1. Extend the `hook_access`/`hook_stat`/`hook_lstat` pattern to cover `/var/db/uuidtext/` (return plausible device UUIDs).
2. Add a `getenv` hook via `MSHookFunction` to intercept `CORELLIUM_ENV` lookups and return `NULL`.
3. Add `sysctlbyname("kern.osversion")` spoofing to return a version string consistent with the spoofed model.
4. These hooks remain gated on `globalDecoyEnabled` with the same thread-local re-entrancy guard.

---

## Implementation Priority Order

1. `[Critical]` Per-navigation `WKNavigationDelegate` proxy (#1) — replaces fragile config-time mutations
2. `[Critical]` NSE interception for iMessage/Mail notifications (#2) — closes the silent-delivery gap
3. `[High]` `WKContentRuleList` in AntiDarkSwordUI jailbreak build (#4) — parity with TF variant
4. `[High]` ImageIO/CoreGraphics attachment guard (#3) — next major zero-click surface
5. `[Medium]` CFPreferences direct-write migration (#6) — fixes host-key mismatch reliably
6. `[High]` Anti-bypass hardening for JS/JIT re-enabling (#5) — closes post-exploit detection gap
7. `[Medium]` PreferenceLoader UX overhaul (#8) — user-facing quality
8. `[Medium]` TF biometric gate (#9) — security for no-jailbreak deployment
9. `[Medium]` Ephemeral WKWebKit reset on pref change (#7) — UX correctness
10. `[Low]` Expanded Corellium path coverage (#10) — hardening
