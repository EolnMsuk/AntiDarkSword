# AntiDarkSword — Compatibility & Conflict Audit

Version: 4.8.1. Updated: 2026-04-26. **Supported range: iOS 13.0 – 17.0. iOS 13–14 uses the `_legacy.deb` (rootful, arm64); iOS 15–17 uses the modern `.deb` or TrollFools dylib.**

---

## 1. Hardware Compatibility Matrix

| SoC Family | Chip Examples | Arch | iOS Range | Status |
|---|---|---|---|---|
| A8 / A8X | iPad mini 4, iPad Air 2 | arm64 (no e) | 13.0–15.8 | Modern .deb for iOS 15.x; `_legacy.deb` for iOS 13–14 (rootful, checkra1n). iPhone 6 (A8) max iOS is 12 — incompatible. |
| A9 / A9X | iPhone 6s, iPad Pro (1st gen) | arm64 | 13.0–16.7 | Modern .deb for iOS 15+; `_legacy.deb` for iOS 13–14 (rootful). All hooks functional on both. |
| A10 / A10X | iPhone 7, iPad Pro 10.5 | arm64 | 13.0–16.7 | Modern .deb for iOS 15+; `_legacy.deb` for iOS 13–14 (rootful). All features available on both. |
| A11 | iPhone 8, iPhone X | arm64 | 13.0–16.7 | Modern .deb for iOS 15+; `_legacy.deb` for iOS 13–14 (rootful). PAC not enforced on jailbreaks (PACSIM disabled). |
| A12 | iPhone XS, XR | arm64e | 15.0–17.0 | Modern .deb arm64e slice. PPL active; Substrate patches via trustcache. Full support. |
| A13 | iPhone 11 | arm64e | 15.0–17.0 | As A12. Full support. |
| A14 | iPhone 12 | arm64e | 15.0–17.0 | As A12. Full support. Rootless path tested. |
| A15 | iPhone 13/14 | arm64e | 15.0–17.0 | Primary test target. All features validated rootful + rootless. |
| A16 | iPhone 14 Pro | arm64e | 16.0–17.0 | LockdownModeEnabled API available natively; no forward-declare needed. Full support. |
| A17 Pro | iPhone 15 Pro | arm64e | 17.0+ | Not formally tested. Binary format compatible; SDK 16.5 headers sufficient for tested API surface. Hook points unchanged. |

**Edge cases:**
- **A8 on iPhone**: iPhone 6 (A8) max iOS is 12 — cannot run AntiDarkSword. iPad mini 4 / iPad Air 2 (A8/A8X) support iOS 13–15 and are compatible with both builds.
- **A8–A11 on iOS 15**: Apple dropped these chips from iOS 16. The modern .deb (arm64 slice) applies for iOS 15.x. Corellium decoy path spoofing is rootless-only; rootful builds deploy the real binary.
- **iOS 13–14 (`_legacy.deb`)**: All mitigations are present. Rootful only (no rootless jailbreaks for iOS 13–14). arm64 only — no arm64e slice needed since A12+ devices on iOS 13–14 load arm64 dylibs without issue. CI produces this as `_iphoneos-arm_legacy.deb`.
- **A12+ PAC**: `%hookf` and `MSHookFunction` on `stat`/`sysctl` are installed by Substrate which handles PAC stripping via `JAILBREAK_ENTITLEMENT`. No code change required.

---

## 2. iOS Version Compatibility

| iOS | JIT API | JS API | Notes |
|---|---|---|---|
| 13.0–14.x | `_WKProcessPoolConfiguration.JITEnabled` | `javaScriptEnabled` (WKPreferences) · `allowsContentJavaScript` (iOS 14+) | Rootful only. Use `_legacy.deb`. All mitigations active; no Client Hints (iOS 16+ only). Corellium decoy installs real binary via LaunchDaemon. |
| 15.0–15.x | `_WKProcessPoolConfiguration.JITEnabled` + `allowsContentJavaScript` | Both | Rootless available (Dopamine, palera1n rootless). `disableJIT15` path active. |
| 16.0–16.x | `lockdownModeEnabled` public (SDK 160000). Pool config still hooking for belt-and-suspenders. | Both | `disableJIT` path via lockdown mode. UA Client Hints `userAgentData` available. |
| 17.0+ | Same as 16. | Both | Not yet formally tested against jailbreaks targeting A17. Binary compatible. |

---

## 3. Jailbreak Environment Compatibility

| JB | Scheme | Known Issues |
|---|---|---|
| palera1n (rootful fakefs) | Rootful | Full support. CorelliumDecoy binary at `/usr/libexec/corelliumd`. |
| palera1n (rootless) | Rootless | `isRootlessJB = YES`. Stat spoof active. Plist path `/var/jb/…`. Validated. |
| Dopamine | Rootless | Same as palera1n rootless. Roothide-variant `jbroot()` detected via `dlsym`; `ads_root_path()` resolves correctly. |
| Roothide | Rootless (rooted paths remapped) | `ads_root_path()` explicitly probes `dlsym(RTLD_DEFAULT, "jbroot")` and calls it when valid. Prefs path and launchctl paths resolve correctly. |
| NathanLR | Rootless | No known issues. |
| TrollStore / TrollFools | No JB | AntiDarkSwordTF dylib only. No daemon hooks. No tier preset matching. Master switch defaults OFF. |

---

## 4. Native iOS Feature Interactions

### 4.1 Lockdown Mode (iOS 16+)
`applyDisableJIT` sets `WKWebpagePreferences.lockdownModeEnabled = YES`. The hook on `setLockdownModeEnabled:` prevents the app from disabling it. **Interaction:** If the device has system-wide Lockdown Mode enabled, the user is already running with all WebKit restrictions Apple provides. AntiDarkSword's per-app lockdown enforce is additive and harmless; it does not conflict with system Lockdown Mode.

**Risk:** If `globalDisableJIT` is enabled (level-3 global override) AND the system is in Lockdown Mode, some apps that use lockdown-mode APIs for their own DRM checks may behave unexpectedly. No specific breakage identified; low risk.

### 4.2 iCloud Private Relay
Private Relay routes Safari traffic through Apple relay nodes. AntiDarkSword's UA spoofing hook replaces `navigator.userAgent` at the JS level and injects `customUserAgent` on `WKWebView`. These operate at the WebKit layer above the network stack. **No interaction** with Private Relay. DNS or IP routing is unaffected.

**Edge:** The `WKContentRuleList` remote-content blocker in AntiDarkSwordTF and AntiDarkSwordUI blocks external `http/https` resource loads at the content-rule level. This is orthogonal to Private Relay routing — blocked requests never reach the network regardless of relay status.

### 4.3 Custom DNS Profiles / VPN Apps
CorelliumDecoy runs as a LaunchDaemon at `/usr/libexec/corelliumd`. It opens no network sockets and performs no DNS lookups. The daemon hooks in AntiDarkSwordDaemon spoof filesystem path lookups (`stat`, `access`) for that binary path only. **No interaction** with DNS or VPN tunneling.

**Risk:** VPN apps that inspect `/proc` or use `sysctlbyname(hw.model)` for device attestation will receive the spoofed model identifier `iPhone15,2` if `globalDecoyEnabled` is active in the process. This is intentional behaviour (Corellium spoof). If a VPN app's server-side checks flag `iPhone15,2` as a suspicious model (e.g., if the device is actually an iPhone 6), the VPN connection may be rejected. Mitigation: disable Corellium Decoy at level 2 or configure per-app rules to exclude VPN bundle IDs.

### 4.4 Managed Device Profiles (MDM)
MDM profiles can enforce `allowJavaScript=false` on supervised devices via `WKWebViewConfiguration`. AntiDarkSword's hooks set `allowsContentJavaScript = NO`; this direction (restricting JS) is additive with MDM policy. If an MDM profile tries to force `javaScriptEnabled = YES`, the `%hook WKPreferences setJavaScriptEnabled:` hook will downgrade it to `NO` when `applyDisableJS` is active. This is intended behaviour and does not violate MDM supervision — the restriction is only more aggressive, not a bypass.

---

## 5. Third-Party Tweak Conflict Analysis

### 5.1 Safari Plus (`com.alexandred.safaripluscolorflow`, `com.opa334.safariplusweb`)
Safari Plus hooks `WKWebView` extensively for download management, open-in-background, and tab enhancements. Both tweaks hook `WKWebView loadRequest:`. Execution order depends on Substrate injection order (typically alphabetical by plist name).

**Risk:** Safari Plus may re-enable `javaScriptEnabled` or replace `customUserAgent` after AntiDarkSword sets them. Observed in practice: Safari Plus's `setCustomUserAgent:` override competes with AntiDarkSword's hook which calls `%orig(customUAString)`. Because both hooks call `%orig`, the last writer wins depending on injection order.

**Mitigation:** AntiDarkSword's `setCustomUserAgent:` hook intercepts the setter unconditionally when `shouldSpoofUA` is true, so even if Safari Plus later tries to set a different UA it will be overridden — provided AntiDarkSword's hook sits closer to the original implementation in the chain (i.e., injects after Safari Plus). No code change required; users experiencing UA bleed-through should check injection order via Choicy.

### 5.2 Choicy / libhooker-configurator
Choicy allows per-app dylib injection blocklists. If a user blocklists `AntiDarkSword.dylib` in a target app, the `%ctor` never runs — no hooks install, no prefs are loaded. This is the expected bypass for compatibility exceptions.

**Risk:** If `AntiDarkSwordDaemon.dylib` is blocked in `apsd` or `imagent` via Choicy, the Corellium path hooks and iMessage download blocks will not be active for that daemon. The `currentProcessRestricted` guard means no hooks run even if the dylib loads but the daemon is in `disabledPresetRules`.

**No code conflict.** Choicy operates at the injection layer, above AntiDarkSword's hook installation.

### 5.3 iCleaner Pro / DaemonDisabler
These tools can disable LaunchDaemons including `c.eolnmsuk.corelliumdecoy.plist`. If DaemonDisabler prevents `corelliumd` from launching, the Corellium honeypot binary is absent on rootless (where the decoy binary is the only copy). The `hook_stat`/`hook_access` POSIX spoofs remain active in the daemon processes (AntiDarkSwordDaemon still injects); they spoof the path lookup at the syscall level regardless of whether the actual binary exists. The decoy binary's purpose is to satisfy any process that forks/execs it, not just stat-checks.

**Risk:** If `corelliumd` is disabled at launch but an exploit attempts to execute it (not just stat it), the exec will fail. However, exploit detection via `access()`/`stat()` is the primary vector mitigated by AntiDarkSword; exec-based checks are not in scope.

**Recommendation:** Users should add `c.eolnmsuk.corelliumdecoy` to the DaemonDisabler whitelist. The `postinst` script loads the daemon; DaemonDisabler's `launchctl unload` after install will conflict. `AntiDarkSwordPrefsRootListController.setCorelliumEnabled:` calls `launchctl load` directly and will re-enable the daemon when the user toggles it in Settings.

### 5.4 LetMeBlock / UHB (Unified Hosts Blocker)
These tools hook `mDNSResponder` or inject `WKContentRuleList` items to block ad domains. Both AntiDarkSwordTF and AntiDarkSwordUI compile a `WKContentRuleList` (identifier: `com.eolnmsuk.ads.remoteblock`) that blocks all `http/https` remote resource loads when `blockRemoteContent` is active.

**Risk:** WKWebView supports multiple `WKContentRuleList` items; they are ORed together (a request is blocked if any list blocks it). AntiDarkSword's broad rule subsumes UHB's domain-specific rules within the same WebView. The rules do not conflict — they are additive. No crash or infinite-loop risk.

**Edge:** `WKContentRuleListStore` caches compiled lists by identifier. If UHB or another tweak uses the same identifier `com.eolnmsuk.ads.remoteblock` (unlikely), the store returns the cached (possibly wrong) list. Not a realistic scenario.

**AntiDarkSwordUI note:** The content rule list is compiled once per process lifetime in `%ctor` (async, main-queue write). It is applied in `applyWebKitMitigations` only when `applyBlockRemoteContent` is set. If the store initialisation fails, `%ctor` silently skips it and `adsContentBlocker` remains nil — `applyWebKitMitigations` guards against nil before adding.

### 5.5 JIT-Dependent Apps (UTM, DolphiniOS, JITStreamer)
AntiDarkSword's `_WKProcessPoolConfiguration.setJITEnabled:` hook and `lockdownModeEnabled` enforcement will prevent JIT from being enabled in any WKWebView when `applyDisableJIT` or `applyDisableJIT15` is active for that process.

**Risk:** UTM, DolphiniOS, and similar emulators rely on JIT for acceptable performance. If `com.utmapp.UTM` or `net.deltaemulator.delta` are added to AntiDarkSword's restricted app list (manually or via a future tier), the JIT block will reduce performance to ~10× slowdown or break the app entirely.

**Mitigation:** UTM and DolphiniOS are not in tier1, tier2, or tier3 preset lists. The risk only materialises if the user manually adds them to custom rules with `disableJIT = YES`. The Settings UI shows a "⚠︎ Disable JavaScript" warning for this reason; a similar advisory should be added for JIT-sensitive apps. No code conflict; this is a usage guidance issue.

### 5.6 Corellium's Real Platform (Corporate MDM Devices / Research VMs)
If AntiDarkSword is installed on an actual Corellium-hosted VM (researchers sometimes jailbreak Corellium iOS instances for testing), the Corellium decoy will mask the real Corellium environment from itself — defeating the purpose of the VM's detection capabilities. This is not a conflict in the traditional sense but a logical recursion: the decoy works too well. No code issue; advisory only.

---

## 6. Identified Conflict Mitigations Built Into Codebase

| Conflict | Existing Mitigation |
|---|---|
| cfprefsd ↔ apsd deadlock on counter write | Serial async queue `com.eolnmsuk.ads.counter`; `CFPreferencesSynchronize` uses `kCFPreferencesAnyHost` |
| GCD `hw.ncpu` sysctl re-entry in hook | Thread-local `_ads_sysctl_active` forward-safety sentinel at top of `hook_sysctlbyname`; not actively set; probe counting is not performed in sysctl hooks |
| NSFileManager `fileExistsAtPath:isDirectory:` NULL deref | `if (isDirectory) *isDirectory = NO;` guard |
| Multiple overlays stacking in TF | `[top isKindOfClass:[ADSTFSettingsViewController class]]` early return |
| Duplicate UA script injection | Generation-based `objc_setAssociatedObject` per-UCC marker; `adsUAGeneration` incremented on pref reload to allow re-injection after UA changes |
| `adsContentBlocker` write/read race (UI + TF) | `dispatch_async(dispatch_get_main_queue(), …)` for the write; all reads occur on main thread |
| NSE `.appex` fast-exit blocking notification hooks | Whitelist `com.apple.messages.NotificationServiceExtension` + `com.apple.MailNotificationServiceExtension` in `%ctor`; all other `.appex` paths still exit early |
| CFPreferences host-key mismatch (NSUserDefaults vs CFPrefs) | `ads_cfwrite()` uses `kCFPreferencesAnyHost` (canonical read scope); `ads_migrate_prefs_if_needed()` one-time migration on Settings launch; `MigrationDone_v1` flag prevents re-migration |
| TF settings overlay shown without authentication | `LAContext` `LAPolicyDeviceOwnerAuthentication` gate; presenter dispatched to main queue on auth success; silently falls through if no passcode is set |

---

## 7. Feature Compatibility Details

### 7.1 NSE (Notification Service Extension) Interception

| Item | Detail |
|---|---|
| Affected bundle IDs | `com.apple.messages.NotificationServiceExtension`, `com.apple.MailNotificationServiceExtension` |
| Applicable builds | AntiDarkSwordUI (all modern .deb variants, rootful + rootless). Not in `_legacy.deb` — NSE zero-click mitigations are most relevant on iOS 15+ where kernel exploits targeting NSEs are documented. |
| iOS range | iOS 10+ for the extension mechanism; mitigations are meaningful from iOS 13 onward. Both bundle IDs are present on all supported devices. |
| Hooks applied inside NSE | WKWebView mitigations, JS disable, `applyBlockRemoteContent` content rule list, `applyBlockRiskyAttachments` attachment guard — same set as a tier1 app process. |
| `.appex` fast-exit behaviour | Non-whitelisted `.appex` processes exit early in `%ctor`. The two NSE bundle IDs are exempted and added to both `tier1` and `allowedServices`. Logos hooks are lazy — WebKit hooks only fire if WebKit is already loaded in the NSE process, so there is no memory overhead for NSEs that do not render HTML. |
| Risk | If a future iOS update changes the NSE bundle ID, the whitelist will not match and the NSE will fall back to fast-exit (no hooks). Monitor for silent regressions on iOS updates. |

### 7.2 WKContentRuleList Remote-Content Blocker

| Item | Detail |
|---|---|
| Pref keys | `blockRemoteContent` (per-app), `globalBlockRemoteContent` (global override) |
| Default | OFF globally; auto-enabled for `msgAndMail`-tier apps at protect level ≥ 2 via `populateDefaultRulesForLevel:` |
| Applicable builds | AntiDarkSwordUI (jailbreak, all iOS 13+ variants) and AntiDarkSwordTF (TrollFools). Both use identifier `com.eolnmsuk.ads.remoteblock`; within a single process only one dylib injects, so no identifier collision. |
| iOS minimum | `WKContentRuleListStore` and `WKContentRuleList` are available from iOS 13.0 in the SDK. The store compilation call is fire-and-forget inside `%ctor`; a nil result silently leaves `adsContentBlocker = nil` — `applyWebKitMitigations` guards against nil before adding. |
| Thread safety | Store compilation runs on a background thread (system-managed). The `adsContentBlocker` pointer is written once via `dispatch_async(dispatch_get_main_queue(), …)`. All reads occur on the main thread (WebKit configuration hooks). No lock needed. |

### 7.3 Risky Attachment Preview Suppression (ChatKit)

| Item | Detail |
|---|---|
| Class | `CKAttachmentMessagePartChatItem` (`ChatKit.framework`) |
| Hooked method | `-fullSizeImageURL` |
| Suppressed extensions | `heic`, `heif`, `webp`, `pdf` (evaluated on `url.pathExtension.lowercaseString`) |
| Pref keys | `blockRiskyAttachments` (per-app), `globalBlockRiskyAttachments` (global override) |
| Default | OFF globally; not preset-populated by default (can be added via per-app rule or global toggle) |
| Applicable builds | AntiDarkSwordUI (modern .deb, iOS 15+ jailbreak), AntiDarkSwordTF (TrollFools). Present in `_legacy.deb` on iOS 13–14 — `CKAttachmentMessagePartChatItem` exists on iOS 13+, so the hook compiles and loads correctly. |
| iOS minimum | `ChatKit.framework` and this class are available on iOS 13+. The `fullSizeImageURL` selector has been stable since iOS 12. |
| Effect | Returns `nil` for the matched URL. Messages.app treats a nil `fullSizeImageURL` as "no full-size preview available" and falls back to placeholder or thumbnail. Does not affect `_needsPreviewGeneration` (the existing hook for that is unchanged). |
| Risk | ChatKit private API — no App Store submissions involved, but the selector could be renamed in a future iOS release. If `fullSizeImageURL` disappears, the `%hook` block becomes a no-op (Logos/Substrate silently skips hooks for unknown selectors). |

### 7.4 Biometric Authentication Gate for TF Settings Overlay

| Item | Detail |
|---|---|
| Framework | `LocalAuthentication.framework` |
| Policy | `LAPolicyDeviceOwnerAuthentication` — Face ID, Touch ID, or passcode fallback |
| Available | iOS 8+ (LAContext); AntiDarkSwordTF targets iOS 15+, so always available. |
| Devices without passcode | `canEvaluatePolicy:error:` returns `NO`; the overlay presents immediately without auth prompt. This is intentional — a device without a passcode has no meaningful auth barrier to enforce. |
| Main-queue dispatch | Auth reply block dispatches `ads_present_overlay_on_main()` to main queue on success. The reply block itself runs on an unspecified system thread (per Apple documentation). |
| Failure path | Auth denial or error: overlay is not presented. No user-visible error message shown (silent failure is appropriate for a hidden gesture). |
| Jailbreak builds | The biometric gate is only present in AntiDarkSwordTF — the overlay triggers inside arbitrary app processes. The PreferenceLoader Settings UI in jailbreak builds is already sandboxed to Settings.app and protected by device lock. |

### 7.5 Corellium Decoy (Daemon Spoofs)

| Item | Detail |
|---|---|
| `getenv("CORELLIUM_ENV")` hook | Returns `NULL` when `globalDecoyEnabled`. Real Corellium VMs export this variable; returning NULL makes the environment look non-Corellium. Installed via `MSHookFunction` in `%ctor`. Probe counter not incremented — this hook fires on normal env-var scanning at process startup, not in response to an explicit Corellium probe. |
| `kern.osversion` spoof | Returns `"21C62"` (iOS 17.2 build for iPhone15,2, consistent with spoofed `hw.model`) when queried via `sysctlbyname`. Prevents fingerprinting via OS build string. `_ads_sysctl_active` thread-local is present at the top of `hook_sysctlbyname` as a forward-safety re-entry sentinel; probe counting is not performed in sysctl hooks — they fire constantly during normal ObjC/Foundation initialisation and do not indicate a Corellium probe. |
| `/var/db/uuidtext/` access spoof | `hook_access` returns `0` (exists) for paths beginning with `/var/db/uuidtext`. This directory is absent on Corellium VMs; returning exists prevents detection by this heuristic. Probe counter not incremented — OSLog hits this path on every log write throughout daemon lifetime, making it unsuitable as a probe signal. |
| Probe counter scope | Fires **only** on explicit `/usr/libexec/corelliumd` path queries: `hook_access`, `hook_stat`, `hook_lstat`, `NSFileManager -fileExistsAtPath:`. Something specifically searching for the Corellium binary is the meaningful detection signal. |
| Applicable builds | AntiDarkSwordDaemon only. Hooks target `imagent`, `identityservicesd`, `apsd`, `IMDPersistenceAgent`. |
| iOS range | `getenv` is libc — available on all iOS versions. `kern.osversion` via `sysctlbyname` is POSIX — available on all iOS versions. No version-gating required. |
| Probe counter: rootful vs rootless | **Rootful**: real `corelliumd` binary exists at `/usr/libexec/corelliumd`. `hook_stat`/`hook_lstat` pass through without fabricating stats (file is real). `hook_access` and `NSFileManager -fileExistsAtPath:` still intercept explicit checks and increment the counter. **Rootless**: binary lives under `/var/jb/usr/libexec/corelliumd`; canonical path does not exist. `hook_stat`/`hook_lstat` fabricate a `struct stat` via `ads_fill_corellium_stat`; all four hooks increment the counter. In both environments, a per-process 2-second CAS debounce (`lastProbeTime`) collapses burst queries within one process — it does not coordinate across the four injected daemons. |

### 7.6 CFPreferences Write-Path and Migration

| Item | Detail |
|---|---|
| Write path | `ads_cfwrite()` in `RootListController.m` writes via `CFPreferencesSetValue(…, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)` + `CFPreferencesSynchronize`. Called from `setPreferenceValue:specifier:` and `setFeatureValue:specifier:` alongside the existing `NSUserDefaults` write (dual-write ensures both host scopes are updated). |
| Read path | All tweaks read via `CFPreferencesCopyMultiple` with `kCFPreferencesAnyHost`. Writing to the same scope ensures preference changes are visible to the tweaks immediately without a daemon restart. |
| One-time migration | `ads_migrate_prefs_if_needed()` runs once in `viewDidLoad` (gated by `MigrationDone_v1` plist key). Re-writes all known preference keys and `TargetRules_*` / `restrictedApps-*` dicts through `ads_cfwrite`. Non-destructive: skips keys that do not exist. |
| Affected environments | Most critical on Roothide and fresh-install configurations where `NSUserDefaults initWithSuiteName:` may write under `kCFPreferencesCurrentHost`, causing prefs to be invisible to the tweaks for up to 30 s. |
| Pref keys | All preference keys — including `blockRemoteContent`, `blockRiskyAttachments`, `globalBlockRemoteContent`, `globalBlockRiskyAttachments` — are written via `ads_cfwrite`. |
