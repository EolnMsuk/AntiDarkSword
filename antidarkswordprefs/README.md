# antidarkswordprefs

The PreferenceLoader bundle of [AntiDarkSword](../README.md). It installs into Settings.app and provides the full configuration UI for all four tweak layers: auto-protection tiers, per-app mitigation rules, daemon overrides, and the Corellium honeypot.

---

## Where it loads

`entry.plist` registers the bundle with PreferenceLoader:

```xml
<key>bundle</key>  <string>AntiDarkSwordPrefs</string>
<key>detail</key>  <string>AntiDarkSwordPrefsRootListController</string>
```

PreferenceLoader dlopens `/Library/PreferenceBundles/AntiDarkSwordPrefs.bundle` inside the Settings.app process when the user taps the entry. The bundle's `NSPrincipalClass` (`AntiDarkSwordPrefsRootListController`) is instantiated as the root controller.

Frameworks required:

- **`Preferences`** (private) — `PSListController`, `PSSpecifier`, `PSTableCell`, and all pref cell types
- **`AltList`** (extra) — `ATLApplicationListMultiSelectionController` for the app-picker view
- **`MobileCoreServices`** — UTI lookups used inside `ads_plugins_for_bundle_id()`

The `AltList.framework` in `vendor/` is always a copy — never edit it directly:

- **`AltList_New`** — arm64 + arm64e, linked against iPhoneOS16.5.sdk — used for modern iOS 15+ builds
- **`AltList_Old`** — arm64-only, thinned via `lipo` — used for the iOS 13–14 legacy build

The appropriate framework must be copied to `vendor/AltList.framework` before each `make` invocation. CI and `build_all.sh` do this automatically.

---

## Preference read/write lifecycle

All pref writes go through two parallel paths to avoid a host-scope mismatch that causes the tweaks to see stale values for up to ~30 seconds.

### Dual-write with `ads_cfwrite()`

`NSUserDefaults` on supervised or Roothide devices may silently write under `kCFPreferencesCurrentHost`, while the tweaks read under `kCFPreferencesAnyHost`. `ads_cfwrite()` resolves this by writing the same key through CFPreferences at `kCFPreferencesAnyHost` alongside every `NSUserDefaults` write:

```objc
CFPreferencesSetValue(key, value, appID,
                      kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
CFPreferencesSynchronize(appID, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
```

Every setter that touches a preference key (`setPreferenceValue:specifier:`, `setFeatureValue:specifier:`, `setAutoProtectLevel:specifier:`, etc.) calls `ads_cfwrite()` immediately after the `NSUserDefaults` write.

### One-time migration (`ads_migrate_prefs_if_needed()`)

Runs once in `viewDidLoad` of the root controller. Re-writes all known pref keys — plus any `TargetRules_` and `restrictedApps-` prefixed keys found in `NSUserDefaults.dictionaryRepresentation` — through `ads_cfwrite()`, so values previously saved under the wrong host scope become visible to the tweaks. Guarded by the `ADSPrefsMigrated_v2` boolean flag.

### Darwin notification

Every save posts `com.eolnmsuk.antidarkswordprefs/saved` via `CFNotificationCenterPostNotification` on the Darwin notify center. All three tweak subprojects (`AntiDarkSwordUI`, `AntiDarkSwordDaemon`, `AntiDarkSwordTF`) register a `reloadPrefsNotification` handler that resets `prefsLoaded = NO` and calls `loadPrefs()` on receipt. A separate `com.eolnmsuk.antidarkswordprefs/counter` notification is used exclusively by the daemon stats view to refresh the probe count label without triggering a full prefs reload in the tweaks.

---

## Root controller (`AntiDarkSwordPrefsRootListController`)

Loads specifiers from `Root.plist` and programmatically injects the current preset rules list and custom daemon IDs inline. Hosts the main settings view.

### Banner and footer

A full-width `UIImageView` header (`banner.png`) is set as `self.table.tableHeaderView` in `viewDidLoad`. The footer group reads `CFBundleShortVersionString` from the bundle's `Info.plist` and detects jailbreak type at runtime — `access("/Library/MobileSubstrate/DynamicLibraries")` → rootful; `dlsym(RTLD_DEFAULT, "jbroot")` → Roothide; fallback → rootless — to render a version/environment string in the form `AntiDarkSword v4.8.2 (iOS 17.4 Rootless)`.

### Global enable switch

The master `enabled` switch uses a custom red background (`UISwitch.backgroundColor = systemRedColor`, `layer.cornerRadius = 15.5`) to visually distinguish it from feature toggles. Toggling it invokes `setEnableProtection:specifier:`, which:

1. Unconditionally unloads the CorelliumDecoy LaunchDaemon plist via `posix_spawn + launchctl unload`.
2. Re-loads it if both `masterEnabled` and `corelliumDecoyEnabled` are `YES`.
3. Sets `ADSPendingDaemonChanges = YES` if level ≥ 3 or any custom daemon IDs are configured.
4. Immediately presents `ads_present_save_prompt()` — a cancel action provided to the prompt restores the prior `enabled`, `ADSNeedsRespring`, and `ADSPendingDaemonChanges` flags and reverts the launchctl state.

### User Agent section

A `PSLinkListCell` (`selectedUAPreset`) presents eight preset UA strings plus a `"CUSTOM"` sentinel. Selecting `"CUSTOM"` causes a `PSEditTextCell` (`customUAString`) to appear in the next specifier reload; all other presets hide it. Both cells write through `ads_cfwrite()` and post `saved`.

Preset UA values cover:

- iPhone Safari at iOS 18.1 (default), 17.6.1, 16.7.8, 15.8.2
- iPad Safari at iOS 18.1
- Android Chrome (`SM-S918B`)
- Windows Edge
- macOS Safari 14.5

If the custom text field is submitted empty, the controller silently resets `selectedUAPreset` to the iOS 18.1 default and triggers a specifier reload that hides the text field.

### Auto-protect level segment

A `PSSegmentCell` with integer values `1 / 2 / 3`. Changing the level calls `setAutoProtectLevel:specifier:`, which:

1. Re-runs `populateDefaultRulesForLevel:force:YES` to write fresh `TargetRules_` dicts for all affected targets.
2. Sets `ADSPendingDaemonChanges = YES` if either the old or new level involves level 3.
3. **Level 3 → auto-enables Corellium Honeypot**: sets `corelliumDecoyEnabled = YES`, clears all four daemon IDs from `disabledPresetRules`, and synchronously `launchctl load`s the plist if protection is enabled.
4. **Dropping below level 3** → auto-disables the honeypot and `launchctl unload`s the plist.

The footer under the "Preset Rules" group updates dynamically on each specifier reload to describe the active level's scope:

- Level 1: core Apple apps (Safari, Messages, Mail, Notes, Calendar, QuickLook, etc.)
- Level 2: expands to major third-party browsers, email, messaging, social media, finance, crypto, package managers
- Level 3: maximum — unlocks daemon restrictions and global rules, accessible via the Level 3 Settings cell

### Preset rules list

After the level segment, `specifiers` injects a "Current Preset Rules" group followed by one `PSLinkCell` per target returned by `autoProtectedItemsForLevel:`. Only installed targets appear — `isTargetInstalled:` queries `LSApplicationWorkspace -applicationIsInstalled:` and `LSApplicationProxy.bundleURL` for app bundle IDs, and skips the check for known core Apple services and short-form process names. Cells are colored green or red (15% alpha) based on `disabledPresetRules`. Tapping a row pushes `AntiDarkSwordAppController` with `ruleType = 0`.

**Tier structure:**

| Tier | Active at | Contents |
|---|---|---|
| Tier 1 | Level 1+ | Safari, Messages, Mail, Notes, Books, News, Podcasts, Stocks, QuickLook, SafariViewService, MailCompositionService, iMessageAppsViewService, ActivityMessagesApp, QuickLookUIService, QuickLookDaemon |
| Tier 2 | Level 2+ | 60+ third-party apps: major browsers, email clients, messaging platforms, social media, AI chat, finance, crypto, jailbreak package managers — sorted alphabetically by display name |

### Custom Rules section (AltList)

A `PSLinkCell` that pushes `AntiDarkSwordAltListController`, backed by AltList's `ATLApplicationListMultiSelectionController`. Lists all installed apps (visible + hidden sections) with bundle ID subtitles and a search bar. Toggle state is stored under `restrictedApps-{bundleID}`. Tapping a non-preset row pushes `AntiDarkSwordAppController` with `ruleType = 1`.

### Advanced Rules section

A `PSButtonCell` (`addCustomID`) presents a `UIAlertController` with a text field accepting comma-separated bundle IDs or process names. Each entry is written to both `customDaemonIDs` (persistent list) and `activeCustomDaemonIDs` (runtime active set). Existing entries appear as `PSLinkCell` rows with swipe-left-to-delete support; deletion also removes the corresponding `TargetRules_` dict.

---

## Level 3 Settings (`AntiDarkSwordDaemonListController`)

Accessible only at auto-protect level 3 (the "Advanced Options" cell is disabled and renamed "🔒 Level 3 Settings" at lower levels). Registers observers for both `saved` and `counter` Darwin notifications so the probe-count label refreshes live without a full prefs reload.

### Corellium Honeypot

Toggles `corelliumDecoyEnabled`. On enable: clears all four daemons from `disabledPresetRules`, sets `ADSPendingDaemonChanges = YES`, then synchronously `launchctl unload` + `launchctl load`s the CorelliumDecoy plist via `posix_spawn`. The plist path is resolved through `ads_root_path()`, which consults the `jbroot()` symbol (Roothide), falls back to `/var/jb/` prefix detection, and finally returns the rootful path unchanged.

### Attack statistics

`countersEnabled` toggles probe counting in the daemon tweak. When both `countersEnabled` and `corelliumDecoyEnabled` are on, a static text cell displays the live `corelliumProbeCount` value (incremented by the daemon and refreshed via the `counter` Darwin notification) plus a Reset button that zeros the key via `NSUserDefaults`.

### System daemon toggles

Four `PSSwitchCell` rows for `imagent`, `apsd`, `identityservicesd`, and `IMDPersistenceAgent`. Enabled state is derived from absence in `disabledPresetRules`. Disabling a daemon writes both the short name and its bundle ID alias (via `ads_daemon_alias_map()`) to the disabled array, ensuring the tweak's bundle-ID and short-name lookup paths are both blocked. All four rows are non-interactive when the Corellium Honeypot is on — the honeypot requires all four daemons to remain monitored.

### Global Rules (beta)

Ten `PSSwitchCell` rows, all disabled unless auto-protect level is 3. Enabling any row triggers a destructive confirmation alert. Enabling `globalDisableJS` also programmatically sets `globalDisableJIT` or `globalDisableJIT15` (iOS-version-branched) and calls `reloadSpecifiers` to reflect the coupled state. Disabling `globalDisableJS` clears both JIT flags in the same write.

| Pref key | Label |
|---|---|
| `globalUASpoofingEnabled` | Spoof User Agent |
| `globalDisableJIT` | Block JIT (iOS 16+) |
| `globalDisableJIT15` | Block JIT (Legacy) |
| `globalDisableJS` | Block JavaScript ⚠︎ |
| `globalDisableRTC` | Block WebGL & WebRTC |
| `globalDisableMedia` | Block Media Auto-Play |
| `globalDisableIMessageDL` | Block Msg Auto-Download |
| `globalDisableFileAccess` | Block Local File Access |
| `globalBlockRemoteContent` | Block Remote Content |
| `globalBlockRiskyAttachments` | Block Attachment Previews |

---

## App selection controller (`AntiDarkSwordAltListController`)

Subclasses AltList's `ATLApplicationListMultiSelectionController`. Overrides `tableView:cellForRowAtIndexPath:` to:

- Hide the built-in AltList checkbox control and replace it with a `UITableViewCellAccessoryDisclosureIndicator`.
- Color non-preset cells green (`systemGreenColor` at 15% alpha) when `restrictedApps-{bundleID}` is `YES`, red otherwise.
- Gray out and disable interaction for any cell whose bundle ID is already in the current preset tier — preset apps are already protected and cannot be added as manual rules.

Tapping an eligible cell pushes `AntiDarkSwordAppController` with `ruleType = 1`. The navigation bar Save button tracks the `ADSNeedsRespring` / `ADSPendingDaemonChanges` state via a `saved` Darwin notification observer registered in `viewDidLoad`.

---

## Per-app config controller (`AntiDarkSwordAppController`)

Handles three distinct rule types through a single `ruleType` property:

| `ruleType` | Meaning | Enable toggle writes to |
|---|---|---|
| `0` | Preset rule | `disabledPresetRules` array |
| `1` | Custom app rule | `restrictedApps-{bundleID}` key |
| `2` | Custom daemon/process | `activeCustomDaemonIDs` array |

### Feature applicability (`isApplicableFeature:forTarget:`)

Gates which toggles are interactive for a given target:

- **`disableJIT`** — non-daemon targets, iOS 16+ only
- **`disableJIT15`** — non-daemon targets, iOS ≤15 only
- **`disableJS`, `disableRTC`, `disableMedia`, `disableFileAccess`, `blockRemoteContent`** — non-daemon targets only
- **`disableIMessageDL`** — `com.apple.MobileSMS`, `com.apple.ActivityMessagesApp`, `com.apple.iMessageAppsViewService` only
- **`blockRiskyAttachments`** — messaging/mail apps; extension bundle IDs containing `NotificationService`, `ShareExtension`, or `.share.`
- **`spoofUA`** — all targets

If a global override is active for a feature, the toggle is shown locked in the ON position (non-interactive).

**Cross-mitigation dependencies:**

- **JS → JIT (Dep A):** Enabling `disableJS` saves the current JIT flag value into an ephemeral `disableJIT_savedBeforeJS` / `disableJIT15_savedBeforeJS` key (iOS-version-branched) before forcing JIT ON. The save only writes if the key is absent, preventing double-save on repeated JS toggles. Disabling `disableJS` restores the prior JIT value from the saved key and removes it, then calls `reloadSpecifiers`. JIT is never blindly reset to OFF.
- **Media locked when JIT is OFF (Dep B):** `disableMedia` is rendered non-interactive (`enabled = NO`) when the active JIT toggle is OFF (`activeJITOn = isIOS16 ? isJITOn : isJIT15On`). A JIT-disabled process cannot execute the JS runtime that triggers autoplay, making the toggle meaningless in that state.

### Default feature values (`getFeatureValue:`)

When `TargetRules_{bundleID}` has no entry for a key, the controller computes a context-sensitive default without persisting it:

- JIT disable defaults ON for all targets in the protected set, version-branched by `ads_is_ios16()`.
- `spoofUA` defaults ON for Safari/SafariViewService always; ON for non-`com.apple.*` apps at level ≥ 2.
- `disableMedia`, `disableRTC`, `disableFileAccess`, `disableIMessageDL`, `blockRemoteContent` default ON for messaging/mail apps.
- `disableRTC` additionally defaults ON for browsers at level 3. `disableMedia` is not applied to browsers at any level — it gates JS-triggered autoplay, which has no memory-safety or RCE impact and is not a meaningful mitigation outside messaging/mail contexts.

### Feature writes (`setFeatureValue:specifier:`)

Writes are stored in a mutable copy of `TargetRules_{bundleID}`, a `NSDictionary` sub-key inside the prefs plist. After updating the dict, both `NSUserDefaults -setObject:forKey:` and `ads_cfwrite()` write the full dict under the key, and a `saved` Darwin notification is posted immediately. JS toggle changes apply the save/restore JIT logic described in the cross-mitigation dependency above before the dict write, then call `reloadSpecifiers`; all other feature toggles return immediately after the write without specifier reload.

### App Plugins section

Appended dynamically after the feature toggles when `ads_plugins_for_bundle_id()` returns at least one result. Two enumeration strategies are tried in order:

**Strategy 1 — LSPlugInKitProxy:** Calls `[LSPlugInKitProxy pluginKitProxiesForHostBundleIdentifier:]` (wrapped in `@try/@catch`). Filters by four extension-point categories: `com.apple.usernotifications.service`, `com.apple.usernotifications.content-extension`, `com.apple.share-services`, `com.apple.message-payload-provider`.

**Strategy 2 — PlugIns/ directory scan:** If PlugInKit returns empty (daemon not yet indexed, fresh restore, system-partition extension DB), falls back to reading `NSExtensionPointIdentifier` and `CFBundleIdentifier` directly from each `.appex` bundle's `Info.plist` under the parent's `PlugIns/` directory. Reliable regardless of PlugInKit daemon state.

Each plugin appears as a `PSLinkCell` with a human-readable category suffix (e.g., `"Signal NSE (Notification Service)"`). Plugin specifier cells inherit `@(isRuleEnabled)` on their `enabled` property, so they are grayed-out and non-tappable when the parent app rule is OFF; the sub-state is preserved in `TargetRules_{pluginBundleID}` and becomes active again when the parent rule is re-enabled. Tapping pushes a nested `AntiDarkSwordAppController` with `isPlugin = YES` and `ruleType = 1`. When `isPlugin = YES` and the rule is disabled, the features footer reads: `"Inheriting parent app rules. Enable the rule to configure plugin-specific overrides."`.

---

## Default rules population (`populateDefaultRulesForLevel:force:`)

Writes initial `TargetRules_` dicts for all targets that do not yet have one (or all targets when `force = YES`). Runs once on first launch (guarded by `hasInitializedDefaultRules`) and again on every level change. Targets are all apps from tier 1 through tier 3, plus the four daemon IDs in both short-name and bundle-ID form.

**Plugin defaults follow a risk-weighted, level-stratified model.**

Two intermediate booleans drive `blockRemoteContent` and `blockRiskyAttachments` for all three handled extension categories:

- **`pluginBlockRC`** = `parentIsMessagingOrMail && (level >= 3 || !parentIsMailOnly)` — non-mail messaging parents get `YES` at all levels; `mailOnlyApps` parents get `YES` only at L3, `NO` at L1/L2 (mirrors the parent-app policy that avoids breaking email rendering at lower levels). `mailOnlyApps` = Mail, MailCompositionService, Gmail, Outlook, Yahoo Mail, Proton Mail.
- **`pluginBlockRA`** = `level >= 3 && parentIsMessagingOrMail` — `YES` at L3 for all messaging/mail parents; `NO` otherwise.

| Plugin category | `blockRemoteContent` | `blockRiskyAttachments` | `disableMedia` |
|---|---|---|---|
| NSE or notification content extension | `pluginBlockRC` | `pluginBlockRA` | YES if messaging/mail parent |
| Share extension (messaging/mail parent) | `pluginBlockRC` | `pluginBlockRA` | — |
| iMessage app extension | `pluginBlockRC` | `pluginBlockRA` | — |

Plugins with any non-trivial override (`blockRemoteContent`, `blockRiskyAttachments`, or `disableMedia = YES`) also receive `restrictedApps-{pluginBundleID} = YES` written via `ads_cfwrite()`, so the "Enable Rule" toggle starts ON and the tweaks enforce the override immediately without requiring user action.

A one-time `ADSPluginEnablesMigrated_v1` pass runs on subsequent opens of existing installs to backfill the enable key for plugins that had non-trivial `TargetRules_` entries written by earlier builds that predated this logic.

---

## Save flow

Every navigation controller that can modify prefs installs a Save button in the navigation bar. The button is enabled when `ADSNeedsRespring = YES` or (`enabled = YES` AND `ADSPendingDaemonChanges = YES`). All four controllers subscribe to the `saved` Darwin notification to keep Save button state synchronized across the navigation stack without requiring explicit cross-controller calls.

`ads_present_save_prompt()` inspects `ADSPendingDaemonChanges` to choose the restart action:

- **`ADSPendingDaemonChanges = NO`**: offers a respring via `posix_spawn(killall backboardd)`.
- **`ADSPendingDaemonChanges = YES`**: offers a userspace reboot via `posix_spawn(launchctl reboot userspace)`.
- **Protection disabled, no pending daemon changes**: silently clears both flags, posts `saved`, and returns without showing any alert.

`setEnableProtection:specifier:` is the only caller that passes a non-nil cancel handler; all other callers pass `nil`. The cancel handler restores the prior `enabled`, `ADSNeedsRespring`, and `ADSPendingDaemonChanges` values and reverts the CorelliumDecoy launchctl state.

---

## Credits controller and easter-egg games (`AntiDarkSwordCreditsController`)

`AntiDarkSwordCreditsController` is a `PSListController` subclass that builds contributor entries programmatically in `specifiers` — no backing plist. It hosts two hidden SpriteKit arcade games.

### Shake to reveal

The controller becomes first responder in `viewDidAppear:` and resigns in `viewWillDisappear:`. A device shake (`UIEventSubtypeMotionShake`) triggers `launchGame` if no game is currently active.

### KVC table access

Both `launchGame` and `teardownGame` access `PSListController`'s private `_table` ivar via `[self valueForKey:@"_table"]`, wrapped in `@try/@catch (NSException *)` with an `isKindOfClass:[UITableView class]` guard before use. If the accessor fails (future Preferences.framework rename or removal), the game is silently skipped rather than crashing Settings.app.

The game `SKView` (480 pt tall, 16 pt inset, `layer.cornerRadius = 12`) is embedded in a `UIView` container and set as `table.tableFooterView`. It fades in over 0.5 s and auto-scrolls the table to reveal it. While the game is active `table.scrollEnabled = NO`. Teardown fades the `SKView` out, presents `nil` to stop the scene, removes the view from the hierarchy, and restores scroll.

### SpriteKit audio engine

All three scenes share a single `ADSSynthState` struct for real-time synthesis via `AVAudioSourceNode`. The render block runs on the audio thread; all SpriteKit mutations happen on the main thread. `ADSSynthState` tracks independent oscillator phases and durations for two simultaneous SFX voices plus a three-voice BGM layer (melody, bass square, arpeggiated pulse). Frequency sweeps (`sfxSweepRate`, `sfxSweep2Rate`) and linear amplitude envelopes (`sfxEnvInit`) give each SFX a distinct character. The engine is torn down in `willMoveFromView:` and freed to prevent audio thread dangling-pointer access after the scene is removed.

**`ADSGameMenuScene`** — selection screen. Two `SKShapeNode` buttons (PyEater cyan, JailTris gold), a close button, and a pulsing dedication label with glow overlay. Button taps produce square-wave SFX tones and trigger `SKTransition pushWithDirection` to the selected game scene.

**`ADSJailTrisScene`** — Tetris on a 10×20 grid at 22 pt per cell. Board state stored as a `NSMutableDictionary` keyed by `"x,y"` strings. A `UIPanGestureRecognizer` handles lateral moves (velocity ≥800 pt/s or translation ≥60 pt → 3-cell move, dispatched in 25 ms intervals) and hard-drop (downward pan with y/x ratio ≥1.5). A `UITapGestureRecognizer` rotates the active piece using up to five horizontal offset wall-kick attempts plus a two-row up-kick fallback. BGM is a 24-note melody + bass + arpeggiated overlay synthesized in the render block at 44100 Hz. Line-clear effects: color-coded flash bars with scale pulse, score pop-up label, board-layer shake animation; Tetris (4-line) fires a 12-particle burst, full-screen strobe, animated score overlay, and triple `UINotificationFeedbackGenerator` haptic sequence. High score is persisted to `NSUserDefaults` suite `com.eolnmsuk.antidarkswordprefs` under `ADS_JailTrisHighScore`.

**`ADSPyEaterScene`** — Snake at 20 pt grid size, 16-tick/s update rate, `UISwipeGestureRecognizer` per direction. An `SKEffectNode` with `CIBloom` (radius 0.8, intensity 1.5) wraps all game layer nodes for a neon glow effect. Food node pulses via a looping scale-to animation (1.25×/0.8×, 0.25 s). Eating food spawns an expand-fade `SKShapeNode` pulse ring. Death triggers a red screen-fill flash, a shockwave ring expanding from the snake head, and a four-keyframe shake sequence on the game layer. BGM is a 16-note pattern at 0.12-beat intervals. High score persisted under `ADS_SnakeHighScore`.

---

## Files

| File | Role |
|---|---|
| `entry.plist` | PreferenceLoader registration — bundle ID, root controller class, entry cell, icon |
| `Resources/Root.plist` | Declarative specifier plist: master switch, UA section, preset rules segment, custom rules/daemons sections, Info section |
| `Resources/Info.plist` | Bundle metadata — `CFBundleIdentifier: com.eolnmsuk.antidarkswordprefs`, `NSPrincipalClass` |
| `RootListController.m` | All preference controllers (`AntiDarkSwordPrefsRootListController`, `AntiDarkSwordDaemonListController`, `AntiDarkSwordAltListController`, `AntiDarkSwordAppController`) plus all static helpers: `ads_cfwrite()`, `ads_migrate_prefs_if_needed()`, `ads_plugins_for_bundle_id()`, `ads_root_path()`, `ads_present_save_prompt()` |
| `ADSCreditsMenu.m` | `AntiDarkSwordCreditsController` (credits list + game host), `ADSGameMenuScene` (selection screen) |
| `ADSGames.h` | Shared interfaces: `ADSSynthState` struct, `ADSGameState` enum, scene class declarations |
| `ADSJailTris.m` | `ADSJailTrisScene` — full Tetris implementation |
| `ADSPyEater.m` | `ADSPyEaterScene` — full snake implementation |
| `Makefile` | Theos bundle rules: `Preferences` (private), `AltList` (extra), `MobileCoreServices` frameworks; install path `/Library/PreferenceBundles` |
