# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working in this repository.

## Important

Role: Senior iOS Jailbreak Developer (Theos, Logos, arm64/arm64e, Rootful/Rootless). 

Rules: No filler/politeness. No self-reference. Output: Dense + Symbols. Code: Precise Logos syntax only. 

Thinking: Step-based reasoning. Validate results. Optimize for correctness over verbosity.

---

## Build Commands

```sh
# Rootful/Rootless jailbreak package (default)
make package

# Debug build
make package DEBUG=1

# Rootless scheme
make package THEOS_PACKAGE_SCHEME=rootless

# TrollFools standalone dylib (no Substrate dependency)
make -f Makefile.trollfools

# Artifact: .theos/obj/AntiDarkSwordTF/AntiDarkSword.dylib
```

Theos must be installed and `$THEOS` must be set. No test suite; validate on-device.

---

## Architecture

Four subprojects compiled together into a single `.deb`:

| Subproject | Type | Injection target | Key capability |
|---|---|---|---|
| `AntiDarkSwordDaemon` | `tweak.mk` | `imagent`, `identityservicesd`, `apsd`, `IMDPersistenceAgent` | iMessage auto-DL block · Corellium honeypot (`access`/`stat`/`lstat`/`sysctl`/`sysctlbyname` via `MSHookFunction`) |
| `AntiDarkSwordUI` | `tweak.mk` | All UIKit processes (filter: `com.apple.UIKit`) | WebKit hardening · UA spoof · iMessage UI-layer DL block |
| `AntiDarkSwordTF` | `tweak.mk` | Single app (TrollFools injection, no Substrate) | Same WebKit hardening + in-app 3-finger double-tap settings overlay · `WKContentRuleList` remote-content blocker |
| `CorelliumDecoy` | `tool.mk` | `/usr/libexec/corelliumd` (LaunchDaemon) | Idle CFRunLoop process — makes the Corellium path exist on rootful |

`Makefile.trollfools` builds only `AntiDarkSwordTF` with `LOGOS_DEFAULT_GENERATOR = internal` (pure ObjC runtime, zero Substrate dependency).

### Preferences domain
All three tweaks share `com.eolnmsuk.antidarkswordprefs`. Storage priority:
1. On-disk plist (`/var/mobile/Library/Preferences/…` or `/var/jb/…` for rootless)
2. `CFPreferencesCopyMultiple` (any-host)
3. `NSUserDefaults` suite (TrollFools sandboxed fallback only)

Reload notification: Darwin `com.eolnmsuk.antidarkswordprefs/saved`  
Counter notification: Darwin `com.eolnmsuk.antidarkswordprefs/counter`

### `loadPrefs()` pattern (identical across all three tweaks)
- Atomic CAS gate on `_Atomic BOOL prefsLoaded` — prevents re-entrant and concurrent loads.
- Evaluates: global override OR (`currentProcessRestricted` AND per-target rule) → `apply*` atomics.
- `reloadPrefsNotification` resets `prefsLoaded = NO` then calls `loadPrefs()`.
- `ADSLogging.h` → `ADSLog(…)` compiles to `NSLog` in DEBUG, `((void)0)` in release.

### Auto-protect tiers (jailbreak build)
- **Tier 1** — Apple first-party apps (Safari, Messages, Mail, …)
- **Tier 2** — Third-party browsers, messengers, social, banking, crypto
- **Tier 3** — System daemons (`imagent`, `apsd`, `identityservicesd`, `IMDPersistenceAgent`) — handled exclusively by `AntiDarkSwordDaemon`

Per-target rule key: `TargetRules_<bundleID>` (NSDictionary inside prefs plist).

### Corellium decoy flow
1. `CorelliumDecoy` binary runs as a KeepAlive LaunchDaemon at `/usr/libexec/corelliumd` — provides the real path on rootful.
2. `AntiDarkSwordDaemon` hooks `access`/`stat`/`lstat`/`NSFileManager`/`sysctl`/`sysctlbyname` via `MSHookFunction`. Path hooks return fabricated `stat` for `/usr/libexec/corelliumd` on rootless. `sysctl`/`sysctlbyname` spoof `hw.model`/`hw.machine` → `"iPhone15,2"`, `hw.cpusubtype` → `CPU_SUBTYPE_ARM64E`, `kern.boottime` → stable PID-seeded `timeval`; thread-local `_ads_sysctl_active` guard prevents GCD→sysctl recursion.
3. Probe counter is incremented with a 2-second debounce, written async on a serial dispatch queue (`ads_counter_queue`) to avoid deadlock with `apsd`/`cfprefsd`.

### TrollFools differences vs jailbreak build
- `LOGOS_DEFAULT_GENERATOR = internal` → no `#include <substrate.h>`, no `MSHookFunction`
- `JSEvaluateScript` C-function hook absent (needs fishhook/MSHookFunction)
- No tier matching — protections apply unconditionally; master switch defaults OFF
- Settings via in-app 3-finger double-tap overlay (`ADSTFSettingsViewController`) instead of PreferenceLoader
- `applyBlockRemoteContent` + `WKContentRuleList` remote-content blocker (compiled async in `%ctor`)
- Prefs write: tries system plist → `NSUserDefaults` suite fallback

### WebKit mitigation application points
`applyWebKitMitigations(WKWebViewConfiguration *)` is called from:
- `%hook WKWebView` `initWithFrame:configuration:` and `initWithCoder:`
- `%hook WKWebViewConfiguration` `setUserContentController:` (UA script injection)

JS block re-enforced at load time: `loadRequest:`, `loadHTMLString:baseURL:`, `evaluateJavaScript:*`.  
JIT lock re-enforced: `%hook _WKProcessPoolConfiguration setJITEnabled:` and `%hook WKWebpagePreferences setLockdownModeEnabled:`.

### Rootless detection
```objc
isRootlessJB = (access("/var/jb", F_OK) == 0);
```
Set in `%ctor` before `%init` and before any hook can fire. Used by `ads_prefs_path()` and Corellium spoof hooks.

### `antidarkswordprefs` bundle
PreferenceLoader bundle (`entry.plist` → `AntiDarkSwordPrefsRootListController`).  
`ads_root_path()` resolves paths via `jbroot()` symbol (Dopamine/Roothide) → `/var/jb` prefix → rootful passthrough.  
Notification posted via `ads_post_notification()` on every save triggers live reload in all injected tweaks.
