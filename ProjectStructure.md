# AntiDarkSword

**Description:** iOS security tweak hardening jailbroken devices on iOS 13.0–17.0 (rootless/rootful) against WebKit RCE & iMessage zero-click exploits (DarkSword & Coruna). Ships as rootful `.deb`, rootless `.deb`, and a TrollFools `.dylib`.

**GitHub:** https://github.com/EolnMsuk/AntiDarkSword/

---

## Project Structure

```text
AntiDarkSword/
│
├── ADSLogging.h
│     CENTRAL LOGGING: Global C-header defining the `ADSLog(fmt, ...)` macro. In DEBUG
│     builds, expands to `NSLog` with file/function/line prefix. In release builds,
│     expands to `((void)0)` — zero-overhead no-op stripping all log output & avoiding
│     leaking operational details. Included by all four Tweak.x files.
│
├── LICENSE
│     LEGAL: Open-source license governing distribution & modification.
│
├── Makefile
│     ROOT MAKEFILE: Aggregates AntiDarkSwordUI, AntiDarkSwordDaemon, antidarkswordprefs,
│     & CorelliumDecoy subprojects. Targets arm64 + arm64e, min iOS 13.0, SDK 16.5.
│     Forces dual SHA1+SHA256 codesigning (TARGET_CODESIGN_FLAGS) for Dopamine/RootHide
│     trust-cache compatibility. Stages PreferenceLoader entry plist in internal-stage::.
│
├── Makefile.trollfools
│     TROLLFOOLS MAKEFILE: Standalone build script for AntiDarkSwordTF.dylib. Uses
│     LOGOS_DEFAULT_GENERATOR=internal (no MobileSubstrate dependency). Output lands at
│     .theos/obj/AntiDarkSwordTF/AntiDarkSword.dylib.
│
├── README.md
│     REPOSITORY DOCS: Primary Markdown file — purpose, installation, technical
│     mitigations, usage instructions.
│
├── build_all.sh
│     BUILD AUTOMATION SCRIPT: Shell script automating deb/dylib compilation on Ubuntu WSL/macOS.
│     Swaps AltList_Old/New frameworks. Compiles modern (iOS 15–17 rootful/rootless),
│     legacy (iOS 13–14 rootful), & TrollFools targets. Outputs to output/ with
│     descriptive suffixes (e.g., modern_iphoneos-arm.deb).
│
├── control
│     PACKAGE METADATA: Debian package manifest — ID (com.eolnmsuk.antidarksword),
│     version, architecture (iphoneos-arm for rootful), dependencies
│     (mobilesubstrate, preferenceloader, com.opa334.altlist), Sileo icon/depiction URLs.
│
├── depiction.json
│     NATIVE DEPICTION: JSON manifest read by Sileo/Zebra rendering the tweak's store
│     page. Contains single "Details" tab with DepictionMarkdownView description &
│     header banner image. No changelogs/screenshots tabs in current version.
│
│
├── .github/
│   └── workflows/
│       └── build.yml
│             CI/CD PIPELINE: GitHub Actions workflow. Builds all three variants
│             (rootful .deb, rootless .deb, TrollFools .dylib) on macOS runners using
│             headless Theos environment on every push. Version auto-extracted from
│             `control` file. Artifacts tagged `build-<number>`.
│
│
├── AntiDarkSwordDaemon/                  SUBPROJECT: System-Level Mitigations
│   │
│   ├── AntiDarkSwordDaemon.plist
│   │     INJECTION FILTER: Targets four system daemons by executable name:
│   │     `imagent`, `identityservicesd`, `apsd`, `IMDPersistenceAgent`.
│   │     Uses `Executables` key (not `Bundles`) — processes have no bundle ID.
│   │
│   ├── Makefile
│   │     BUILD SCRIPT: Compiles AntiDarkSwordDaemon.dylib.
│   │
│   ├── README.md
│   │     SUBPROJECT DOCS: Documentation for daemon-level mitigations.
│   │
│   └── Tweak.x
│         DAEMON ENGINE: Hooks IMCore's `IMFileTransfer` (`isAutoDownloadable`,
│         `canAutoDownload`) in imagent/IMDPersistenceAgent blocking zero-click
│         iMessage auto-downloads at source daemon layer (primary block; UI tweak
│         = fallback).
│
│         Corellium honeypot: intercepts POSIX `access`, `stat`, `lstat` calls
│         + `NSFileManager.fileExistsAtPath:` via MSHookFunction. Rootless installs
│         spoof `/usr/libexec/corelliumd` as present with realistic stat struct
│         (root-owned, mode 0755, 34 520 bytes, plausible inode). Rootful installs
│         have real binary present → no spoofing needed.
│
│         Corellium probe counter: debounced (2-second window, CAS gate) counter
│         increments `corelliumProbeCount` in CFPreferences. Counter writes
│         dispatched async on private serial queue (`com.eolnmsuk.ads.counter`) preventing
│         deadlocks — apsd calls cfprefsd synchronously for APNs config, so sync
│         CFPreferences write from hooked path = circular wait. Posts
│         `antidarkswordprefs/counter` Darwin notification on each increment so Settings.app
│         refreshes counter cell independently of full prefs reload.
│
│         All state variables = `_Atomic`. Prefs loaded via CFPreferences (authoritative)
│         with physical plist fallback, guarded by CAS gate identical to UI tweak.
│         Listens for `antidarkswordprefs/saved` Darwin notifications hot-reloading prefs.
│
│
├── AntiDarkSwordTF/                      SUBPROJECT: TrollFools Injection
│   │
│   ├── Makefile
│   │     BUILD SCRIPT: Compiles AntiDarkSwordTF.dylib for TrollStore/TrollFools
│   │     injection. LOGOS_DEFAULT_GENERATOR=internal; no MobileSubstrate.
│   │
│   ├── README.md
│   │     SUBPROJECT DOCS: Instructions for injecting via TrollFools app.
│   │
│   └── Tweak.x
│         TF ENGINE: Per-app WebKit hardening dylib for non-jailbroken TrollStore users.
│
│         Differences vs. jailbreak tweak:
│           • No MobileSubstrate — %hook compiles to pure ObjC runtime calls
│           • No JSEvaluateScript C-function hook (requires MSHookFunction/fishhook)
│           • No tier-matching/process filtering — protections apply to target app unconditionally
│           • No daemon hooks (imagent/apsd require jailbreak)
│           • No PreferenceLoader settings bundle — settings via three-finger
│             double-tap in-app overlay only
│           • `blockRemoteContent` feature: compiles WKContentRuleList at launch blocking
│             all external http/https resource loads (images, scripts, fonts, media) —
│             primary zero-click surface for HTML email in Mail.app
│           • Three-tier prefs storage: CFPreferences → physical plist at
│             `ads_prefs_path()` → NSUserDefaults suite fallback (sandboxed container)
│           • Default state (master ON): UA spoof ON, JIT disabled ON; JS/media/
│             RTC/file-access OFF (user opts in explicitly)
│
│         Shares `com.eolnmsuk.antidarkswordprefs` domain with jailbreak tweak →
│         settings written by prefs bundle honoured without extra plumbing. Listens
│         for `antidarkswordprefs/saved` Darwin notifications.
│
│
├── AntiDarkSwordUI/                      SUBPROJECT: App-Level Mitigations
│   │
│   ├── AntiDarkSwordUI.plist
│   │     INJECTION FILTER: Injects into any process loading `com.apple.UIKit` bundle.
│   │     Fine-grained allowlisting applied at runtime in %ctor: only user apps
│   │     (Containers/Bundle/Application/), system/JB apps (/Applications/), specific
│   │     allowlist of Apple service processes, & manual override targets activated.
│   │     App extensions (.appex) & noisy background daemons fast-failed before hooks run.
│   │
│   ├── Makefile
│   │     BUILD SCRIPT: Compiles AntiDarkSwordUI.dylib.
│   │
│   ├── README.md
│   │     SUBPROJECT DOCS: Documentation for app-level UI mitigations.
│   │
│   └── Tweak.x
│         UI ENGINE: WebKit + iMessage hardening for UIKit processes.
│
│         WebKit hooks: WKWebView, WKWebViewConfiguration, WKWebpagePreferences,
│         WKPreferences, _WKProcessPoolConfiguration, UIWebView,
│         JSEvaluateScript (C-function via MSHookFunction). Applies:
│           • JIT disable: WKWebpagePreferences.lockdownModeEnabled (iOS 16+) or
│             _WKProcessPoolConfiguration.JITEnabled (iOS 15, private API)
│           • JS blocking: allowsContentJavaScript, javaScriptEnabled, all
│             evaluateJavaScript: / callAsyncJavaScript: call-sites
│           • Media: allowsInlineMediaPlayback, mediaTypesRequiringUserActionForPlayback,
│             allowsPictureInPictureMediaPlayback
│           • WebRTC/WebGL: webGLEnabled, mediaStreamEnabled, peerConnectionEnabled
│             (KVC on WKPreferences)
│           • File access: allowFileAccessFromFileURLs,
│             allowUniversalAccessFromFileURLs (KVC on WKPreferences)
│           • UA spoofing: sets WKWebView.customUserAgent, overrides User-Agent HTTP
│             header in loadRequest:, injects JS navigator property-override script at
│             document-start covering userAgent, appVersion, platform, vendor,
│             navigator.userAgentData (Client Hints — iOS 16+)
│
│         iMessage UI-layer hooks (second layer defense):
│           • IMFileTransfer.isAutoDownloadable / canAutoDownload → NO
│           • CKAttachmentMessagePartChatItem._needsPreviewGeneration → NO
│
│         Three-tier auto-protection: Tier 1 (core Apple apps, always protected),
│         Tier 2 (browsers, messaging, social, finance — Level 2+), Tier 3 (system
│         daemons — handled by AntiDarkSwordDaemon, empty in UI tweak). Manual
│         per-app rules from TargetRules_<bundleID> override all tier defaults.
│         Per-app smart defaults: messaging/mail apps get media+RTC+file-access
│         blocking; browsers get UA spoof ± RTC/media at Level 3.
│
│         Prefs loaded via CFPreferences (authoritative) with physical plist fallback.
│         CAS gate prevents re-entrant/concurrent loads. Listens for
│         `antidarkswordprefs/saved` Darwin notification hot-reloading.
│
│
├── CorelliumDecoy/                       SUBPROJECT: Environment Spoofing
│   │
│   ├── Makefile
│   │     BUILD SCRIPT: Compiles dummy `corelliumd` executable & stages LaunchDaemon plist.
│   │
│   ├── README.md
│   │     SUBPROJECT DOCS: Explains Corellium environment spoofing mechanism.
│   │
│   ├── c.eolnmsuk.corelliumdecoy.plist
│   │     LAUNCH DAEMON: launchd configuration for decoy. RunAtLoad+KeepAlive
│   │     ensure dummy process starts at boot & restarts if killed. Installed
│   │     to /Library/LaunchDaemons/ (rootful) or /var/jb/Library/LaunchDaemons/
│   │     (rootless) by postinst.
│   │
│   ├── entitlements.plist
│   │     ENTITLEMENTS: Grants `platform-application` & disables
│   │     `com.apple.private.security.container-required` so iOS jetsam/sandbox does
│   │     not kill decoy in background + no container sandbox enforced.
│   │
│   └── main.m
│         DUMMY PROCESS: Registers SIGTERM/SIGINT/SIGHUP handlers for clean exit,
│         then calls CFRunLoopRun() — zero CPU usage while maintaining live PID.
│         Malware enumerating running processes (or probing filesystem for
│         /usr/libexec/corelliumd) sees binary present & interprets device as Corellium
│         virtual machine, triggering self-abort in known payloads. Rootless installs
│         = binary absent at canonical path; daemon POSIX hooks in AntiDarkSwordDaemon
│         supply filesystem-level spoof.
│
│
├── antidarkswordprefs/                   SUBPROJECT: Settings UI
│   │
│   ├── Makefile
│   │     BUILD SCRIPT: Compiles antidarkswordprefs.bundle for Settings.app via
│   │     PreferenceLoader.
│   │
│   ├── RootListController.m
│   │     SETTINGS CONTROLLER: PSListController subclass. Reads/writes
│   │     `com.eolnmsuk.antidarkswordprefs` NSUserDefaults suite. Key responsibilities:
│   │       • Enable/disable global protection; set auto-protect level (1/2/3)
│   │       • UA preset picker + custom UA text field
│   │       • Per-mitigation global toggles (JIT, JS, media, RTC, file access, iMessage DL)
│   │       • Manual app selection via AltList (ATLApplicationListMultiSelectionController)
│   │       • Advanced custom daemon bundle-ID / process-name input with swipe-to-delete
│   │       • Corellium decoy toggle + live probe counter cell
│   │       • Per-app rule editing (TargetRules_<bundleID> sub-plist)
│   │       • RootHide compatibility: `ads_root_path()` calls jbroot() when available
│   │         & confirmed non-trivial remapping paths to per-process preboot prefix
│   │       • Uses posix_spawn (not system()) invoking uicache/userspace-reboot for
│   │         daemon restarts; waits with waitpid() confirming completion
│   │       • Posts `antidarkswordprefs/saved` Darwin notification after every write so
│   │         all injected tweaks hot-reload without respring
│   │
│   ├── entry.plist
│   │     INJECTOR: Tells PreferenceLoader adding AntiDarkSword entry to main iOS
│   │     Settings app, pointing to compiled bundle.
│   │
│   └── Resources/
│         UI ASSETS
│         ├── AntiDarkSword.png    — Icon shown in Sileo/Zebra depiction header
│         ├── Info.plist           — Bundle metadata: identifies prefs bundle to iOS
│         ├── Root.plist           — SETTINGS LAYOUT: XML defining full preferences
│         │                          hierarchy. Sections:
│         │                            • Global Settings (master enable switch)
│         │                            • User Agent Configuration (preset picker +
│         │                              custom UA text field)
│         │                            • Preset Rules (Level 1/2/3 segment control)
│         │                            • Manual Rules (AltList app picker)
│         │                            • Advanced Custom Rules (bundle ID / process input)
│         │                            • Global Mitigation Rules / BETA (per-mitigation
│         │                              system-wide overrides: UA spoof, JIT, JIT-legacy,
│         │                              JS, WebRTC/WebGL, media autoplay, iMessage DL,
│         │                              file access)
│         │                            • Info (Credits, Donate, GitHub links)
│         │                            • Reset to Defaults (destructive button)
│         ├── banner.png           — Image at top of settings page
│         ├── header.png           — Header image used on Sileo
│         ├── eoln.png             — Developer avatar for EolnMsuk in credits
│         ├── ghh-jb.png           — Developer avatar for ghh-jb in credits
│         ├── icon.png             — Menu icon shown in iOS Settings list
│         ├── icon@2x.png          — 2× Retina version
│         └── icon@3x.png          — 3× Super Retina version
│
│
├── layout/                               DEBIAN STAGING
│   └── DEBIAN/
│       ├── postinst
│       │     POST-INSTALL SCRIPT: Run by dpkg after extraction. Detects rootless
│       │     (/var/jb prefix). Sets corelliumd executable (chmod 755, chown root:wheel),
│       │     sets LaunchDaemon plist permissions (chmod 644), unloads + reloads
│       │     Corellium decoy via launchctl starting immediately without reboot.
│       │
│       └── prerm
│             PRE-REMOVE SCRIPT: Run by dpkg before uninstall. On `remove` or `purge`,
│             unloads Corellium decoy LaunchDaemon via launchctl preventing orphaned
│             process after files deleted.
│
│
└── vendor/                               DEPENDENCIES
    ├── AltList_New.framework/
    │     MODERN FRAMEWORK: Pre-compiled Opa334 AltList library → iOS 15–17 builds.
    │     Swapped dynamically into `vendor/AltList.framework` by build_all.sh.
    │     │
    │     ├── AltList              — Compiled Mach-O dynamic library
    │     ├── Info.plist           — Framework identifier & version metadata
    │     └── Headers/             — Public ObjC headers:
    │           ATLApplicationListControllerBase.h
    │           ATLApplicationListMultiSelectionController.h
    │           ATLApplicationListSelectionController.h
    │           ATLApplicationListSubcontroller.h
    │           ATLApplicationListSubcontrollerController.h
    │           ATLApplicationSection.h
    │           ATLApplicationSelectionCell.h
    │           ATLApplicationSubtitleCell.h
    │           ATLApplicationSubtitleSwitchCell.h
    │           LSApplicationProxy+AltList.h
    │
    └── AltList_Old.framework/
          LEGACY FRAMEWORK: Pre-compiled Opa334 AltList library → iOS 13–14 builds.
          Swapped dynamically by build_all.sh. Thinned to arm64 via lipo during legacy build.
          │
          ├── AltList              — Compiled Mach-O dynamic library
          ├── Info.plist           — Framework identifier & version metadata
          └── Headers/             — Public ObjC headers:
                ATLApplicationListControllerBase.h
                ATLApplicationListMultiSelectionController.h
                ATLApplicationListSelectionController.h
                ATLApplicationListSubcontroller.h
                ATLApplicationListSubcontrollerController.h
                ATLApplicationSection.h
                ATLApplicationSelectionCell.h
                ATLApplicationSubtitleCell.h
                ATLApplicationSubtitleSwitchCell.h
                LSApplicationProxy+AltList.h
           
```

---

## Key Architecture Notes

**Dual-layer defense:** AntiDarkSwordDaemon = primary block (source daemons before content reaches apps); AntiDarkSwordUI = fallback (app processes). Both hook IMFileTransfer independently.

**Rootful/rootless abstraction:** `ads_prefs_path()` in each component checks `access("/var/jb", F_OK)` at startup returning correct plist path. Build-time path substitutions applied in Makefile & postinst. Never hardcode `/Library/` paths.

**Thread-safe atomic flags:** All hook-read state variables declared `_Atomic`. CAS gate on `prefsLoaded` prevents concurrent re-entrant `loadPrefs()` calls. `reloadPrefsNotification` resets flag before re-calling.

**Preference priority:** CFPreferences (cfprefsd, authoritative live state) → physical plist (fresh-install fallback). Physical plist can be stale if cfprefsd hasn't flushed recent writes; reading first can silently miss keys.

**TrollFools feature gating:** `TROLLFOOLS_BUILD=1` preprocessor flag disables jailbreak-only code. AntiDarkSwordTF.x adds `blockRemoteContent` WKContentRuleList feature absent from jailbreak variant.

**Private API wrapping:** All private API calls (`_WKProcessPoolConfiguration`, `WKWebpagePreferences.lockdownModeEnabled` on pre-iOS-16 SDKs, KVC on WKPreferences) guarded with `respondsToSelector:` & wrapped in `@try/@catch`.

**Release logging:** All `ADSLog()` calls expand to `((void)0)` in release builds via `DEBUG` macro in ADSLogging.h. Never use `NSLog` directly.

**RootHide compatibility:** `ads_root_path()` in RootListController.m dlopen-resolves `jbroot()`, verifying non-trivial remap (`jbroot("/") != "/"`) before applying to preference/daemon paths.