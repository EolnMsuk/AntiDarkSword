# ProjectStructure.md

Annotated file tree for AntiDarkSword ⛨. Vendor framework sub-files are omitted per project convention; see descriptions below.

```
AntiDarkSword/
│
├── ADSLogging.h                          # Shared logging macro. ADSLog(…) expands to NSLog in DEBUG builds
│                                         # and to ((void)0) in release builds, preventing operational detail leaks.
│
├── Makefile                              # Root aggregate Makefile. Compiles AntiDarkSwordUI, AntiDarkSwordDaemon,
│                                         # antidarkswordprefs, and CorelliumDecoy as subprojects; stages the
│                                         # PreferenceLoader entry plist. Targets arm64 + arm64e, iOS 14.5+ baseline.
│
├── Makefile.trollfools                   # Standalone Makefile for the TrollFools dylib. Builds only AntiDarkSwordTF
│                                         # with LOGOS_DEFAULT_GENERATOR=internal (no MobileSubstrate dependency).
│
├── build_all.sh                          # Local build script that swaps AltList_New.framework into vendor/,
│                                         # builds three targets (modern rootful, modern rootless, TrollFools dylib),
│                                         # and collects outputs into output/. Legacy arm-only .deb is built manually.
│
├── control                               # Debian package metadata (package ID, version 4.6.0, arch, dependencies:
│                                         # mobilesubstrate, preferenceloader, com.opa334.altlist).
│
├── depiction.json                        # Sileo/Zebra depiction payload. Describes feature tabs, compatibility
│                                         # matrix, and protection level summary for package managers.
│
├── LICENSE                               # Project license.
│
├── AntiDarkSwordDaemon/
│   ├── Makefile                          # Builds AntiDarkSwordDaemon tweak with -fobjc-arc; links Foundation
│   │                                     # and CoreFoundation only. Uses -Wl,-fixup_chains for pointer fixups.
│   ├── AntiDarkSwordDaemon.plist         # MobileSubstrate injection filter. Targets executables: imagent,
│   │                                     # identityservicesd, apsd, IMDPersistenceAgent.
│   ├── Tweak.x                           # Daemon-layer Logos tweak. Hooks IMFileTransfer to block iMessage
│   │                                     # auto-download; hooks access/stat/lstat/NSFileManager via MSHookFunction
│   │                                     # for Corellium path spoofing on rootless (fabricated stat with plausible
│   │                                     # timestamps derived from ads_spoofed_boottime); increments probe counter on
│   │                                     # a serial async queue to avoid cfprefsd deadlock.
│   └── README.md                         # Subproject notes for AntiDarkSwordDaemon.
│
├── AntiDarkSwordUI/
│   ├── Makefile                          # Builds AntiDarkSwordUI tweak; links Foundation, UIKit, WebKit,
│   │                                     # JavaScriptCore. Filter plist injects into all UIKit-hosting processes.
│   ├── AntiDarkSwordUI.plist             # MobileSubstrate injection filter. Bundle filter: com.apple.UIKit
│   │                                     # (covers all foreground app processes).
│   ├── Tweak.x                           # UI-layer Logos tweak. Hooks WKWebView, WKWebViewConfiguration,
│   │                                     # WKWebpagePreferences, WKPreferences, _WKProcessPoolConfiguration,
│   │                                     # JSEvaluateScript (C-level), IMFileTransfer, CKAttachmentMessagePartChatItem,
│   │                                     # and UIWebView. Applies JIT/JS/media/RTC/file-access/iMessageDL mitigations
│   │                                     # and UA spoofing with Client Hints injection. Uses associated objects on
│   │                                     # WKUserContentController to prevent duplicate script injection. Fast-exits
│   │                                     # for noisy background daemons and .appex extensions in %ctor.
│   └── README.md                         # Subproject notes for AntiDarkSwordUI.
│
├── AntiDarkSwordTF/
│   ├── Makefile                          # Builds the TrollFools dylib with LOGOS_DEFAULT_GENERATOR=internal
│   │                                     # and -DTROLLFOOLS_BUILD=1. No Substrate linkage; codesigns with sha1+sha256.
│   ├── Tweak.x                           # TrollFools variant tweak. Contains all AntiDarkSwordUI WebKit hooks plus:
│   │                                     # WKContentRuleList remote-content blocker (async compiled in %ctor;
│   │                                     # result dispatched to main queue to avoid read/write race with hooks),
│   │                                     # in-app settings overlay (ADSTFSettingsViewController + ADSTFGestureHandler),
│   │                                     # three-finger double-tap gesture via %hook UIWindow makeKeyAndVisible,
│   │                                     # associated-object UCC dedup guard, and a three-tier prefs storage
│   │                                     # fallback (system plist → CFPrefs → NSUserDefaults suite).
│   │                                     # No daemon hooks or JSEvaluateScript C hook.
│   └── README.md                         # Subproject notes for AntiDarkSwordTF.
│
├── CorelliumDecoy/
│   ├── Makefile                          # Builds corelliumd as a Theos tool installed to /usr/libexec.
│   │                                     # Codesigns with platform-application entitlement; patches the LaunchDaemon
│   │                                     # plist path for rootless installs via sed in internal-stage.
│   ├── main.m                            # Minimal CFRunLoop daemon. Registers SIGTERM/SIGINT/SIGHUP handlers (uses
│   │                                     # _exit() — async-signal-safe) and loops indefinitely at ~0% CPU.
│   ├── c.eolnmsuk.corelliumdecoy.plist   # LaunchDaemon plist. Runs /usr/libexec/corelliumd with KeepAlive=true
│   │                                     # so the process restarts automatically if killed.
│   ├── entitlements.plist                # Grants platform-application and disables container requirement so
│   │                                     # jetsam/sandbox does not terminate the process (required for rootless).
│   └── README.md                         # Subproject notes for CorelliumDecoy.
│
├── antidarkswordprefs/
│   ├── Makefile                          # Builds AntiDarkSwordPrefs as a Theos bundle (PreferenceLoader bundle).
│   │                                     # Links UIKit + Preferences private framework + AltList framework from vendor/.
│   ├── entry.plist                       # PreferenceLoader registration. Points to AntiDarkSwordPrefsRootListController
│   │                                     # inside the AntiDarkSwordPrefs bundle.
│   ├── RootListController.m              # Main PSListController subclass. Renders the Settings UI, handles
│   │                                     # auto-protect level segmented control, per-target rule editing, custom
│   │                                     # bundle ID / process name entry, AltList app picker integration, daemon
│   │                                     # toggle subcontroller, and global override switches. Posts Darwin
│   │                                     # com.eolnmsuk.antidarkswordprefs/saved on every save.
│   ├── ADSCreditsMenu.m                  # PSListController subclass rendering the Credits screen (authors,
│   │                                     # acknowledgements, links). Easter-egg SKView mini-game launcher;
│   │                                     # private _table KVC access wrapped in @try/@catch for forward-compat.
│   ├── ADSGames.h                        # Shared header for the embedded mini-game scenes. Declares
│   │                                     # ADSGameMenuScene, ADSJailTrisScene, ADSPyEaterScene, ADSSynthState,
│   │                                     # ADSGameState, AntiDarkSwordCreditsController, and ADS_PREFS_SUITE.
│   │                                     # ADSGames.m removed; all scene implementations reside in the
│   │                                     # individual .m files (ADSJailTris.m, ADSPyEater.m).
│   ├── ADSJailTris.m                     # SpriteKit mini-game accessible from the (easter-egg) screen.
│   ├── ADSPyEater.m                      # SpriteKit mini-game accessible from the (easter-egg) screen.
│   └── Resources/
│       ├── Info.plist                    # Bundle metadata for AntiDarkSwordPrefs.bundle.
│       ├── Root.plist                    # PreferenceLoader specifier tree. Defines all cells: master switch,
│       │                                 # UA preset picker, custom UA text field, auto-protect level segment,
│       │                                 # AltList app picker, custom ID button, and info/credits buttons.
│       ├── AntiDarkSword.png             # Full-size tweak icon used in Sileo/Zebra depiction and SileoIcon field.
│       ├── banner.png                    # Header banner image for the depiction page.
│       ├── eoln.png                      # Developer avatar / credit image.
│       ├── ghh-jb.png                    # Additional credit/acknowledgement image.
│       ├── icon.png                      # 1× app icon for the PreferenceLoader entry.
│       ├── icon@2x.png                   # 2× app icon.
│       └── icon@3x.png                   # 3× app icon.
│
├── layout/
│   └── DEBIAN/
│       ├── postinst                      # Post-install script. Sets ownership and permissions on corelliumd and
│       │                                 # its LaunchDaemon plist, then loads the daemon via launchctl. Detects
│       │                                 # rootless by checking for /var/jb and prepends the prefix as needed.
│       └── prerm                         # Pre-remove script. Unloads the corelliumd LaunchDaemon via launchctl
│                                         # on package removal or purge.
│
├── packages/                             # Pre-built release artifacts committed to the repository.
│   ├── AntiDarkSword_4.6.0_TrollFools.dylib              # TrollFools dylib (arm64 + arm64e).
│   ├── com.eolnmsuk.antidarksword_4.6.0_legacy_iphoneos-arm.deb   # Rootful legacy build (iOS 13–14, arm64).
│   ├── com.eolnmsuk.antidarksword_4.6.0_modern_iphoneos-arm.deb   # Rootful modern build (iOS 15+, arm64 + arm64e).
│   └── com.eolnmsuk.antidarksword_4.6.0_modern_iphoneos-arm64.deb # Rootless modern build (iOS 15+, arm64 + arm64e).
│
├── vendor/
│   ├── AltList.framework                 # Active AltList copy consumed by Theos during compilation. Always a
│   │                                     # replica of AltList_New or AltList_Old — regenerated by build scripts
│   │                                     # before each make invocation. Do not edit directly.
│   ├── AltList_New.framework             # Newer AltList build for modern iOS 15+ .deb targets. Linked against
│   │                                     # iPhoneOS16.5.sdk; contains arm64 + arm64e slices.
│   └── AltList_Old.framework             # Older AltList build required for legacy iOS 13–14 .deb targets.
│                                         # Linked against iPhoneOS14.5.sdk; thinned to arm64-only via lipo
│                                         # during the legacy build step.
│
└── .github/
    └── workflows/
        └── build.yml                     # GitHub Actions CI workflow (macos-14 runner). Installs Theos via
                                          # Randomblock1/theos-action, downloads iPhoneOS16.5.sdk only, swaps
                                          # AltList_New into vendor/, and builds three modern targets (rootful
                                          # arm.deb, rootless arm64.deb, TrollFools dylib — all iOS 15.0+).
                                          # Publishes a draft GitHub Release on every push to main. The legacy
                                          # iOS 13–14 build is NOT produced by CI; it requires manual compilation.
```
