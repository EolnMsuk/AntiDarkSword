# Project structure

AntiDarkSword is an iOS exploit-mitigation project written in Objective-C and
Logos and built with Theos. It reduces the attack surface exposed by WebKit and
message attachment processing by applying configurable restrictions inside apps,
app extensions and selected messaging daemons. Its runtime hooks can restrict
JavaScript and JIT compilation, spoof user-agent information, block remote web
resources, disable media autoplay, WebGL/WebRTC and local file access, and suppress
selected attachment downloads or previews.

The project has two delivery modes. The **jailbreak package** combines app and
daemon tweaks, a Settings.app preference bundle and a Corellium decoy process.
The **TrollFools build** is a standalone library injected into individual apps on
a supported TrollStore/TrollFools setup, with its own in-app settings overlay.
Its coverage is limited to the processes into which it is injected.

## Runtime components

| Component | Role |
|---|---|
| [AntiDarkSwordUI](AntiDarkSwordUI/Tweak.x) | Uses a UIKit injection filter, then process and extension checks, to apply WebKit, JavaScriptCore and attachment hooks in eligible apps and UI services. |
| [AntiDarkSwordDaemon](AntiDarkSwordDaemon/Tweak.x) | Loads into `imagent`, `IMDPersistenceAgent`, `apsd` and `identityservicesd`; applies attachment auto-download restrictions where `IMFileTransfer` is available, plus optional decoy-related hooks. |
| [antidarkswordprefs](antidarkswordprefs/RootListController.m) | Provides the PreferenceLoader settings UI for the master switch, presets, per-app and plugin rules, global overrides, daemon controls and diagnostics. It also hosts manual update checking, donations, credits and games. |
| [CorelliumDecoy](CorelliumDecoy/main.m) | Supplies an idle `corelliumd` process managed by launchd. Its presence is intended to trigger payloads that avoid Corellium analysis environments. |
| [AntiDarkSwordTF](AntiDarkSwordTF/Tweak.x) | Implements app-local WebKit and selected preview restrictions with the internal Logos backend, without a MobileSubstrate dependency or the jailbreak package's daemon/decoy components. |

```text
AntiDarkSword/
├── control                         # Release-version authority; package ID and dependencies
├── Makefile                        # UI, daemon, preferences and decoy aggregate
├── Makefile.legacy                  # Explicit legacy target, then the same aggregate
├── Makefile.trollfools              # Standalone TrollFools aggregate
├── build_all.sh                     # Sequential wrapper for all five build targets
├── ADSLogging.h                     # Debug-only logging macro
├── ADSPaths.h                       # Compile-selected paths and typed native Roothide API
├── config/
│   ├── targets.json                # SDK, minimum OS, slices, scheme, package arch, AltList
│   └── target.mk                   # Target/version/layout preparation and build isolation
├── scripts/
│   ├── version.py                  # print/sync/check/notes from control and current changelog
│   ├── target_config.py            # Reads shared target definitions
│   ├── prepare_reference.py        # Validates/copies AltList link reference and target resources
│   ├── stage_lifecycle.py          # Derives control dependencies and fixed-environment scripts
│   ├── build_target.sh             # macOS prerequisites, one target build and product collection
│   ├── collect_product.py          # Package metadata/TF dylib checks; complete five-asset check
│   ├── macho.py                    # Read-only Mach-O inspection and validated slice extraction
│   ├── release_notes.py            # Compatibility guide with control-derived asset examples
│   └── check_sources.py            # Syntax-only check of the six preferences .m files
├── AntiDarkSwordUI/
│   ├── Tweak.x                     # WebKit/JS/attachment hooks; process/extension/Gecko gates
│   ├── AntiDarkSwordUI.plist        # Broad com.apple.UIKit injection filter
│   ├── Makefile                    # Shared target config, frameworks and native library selection
│   └── README.md
├── AntiDarkSwordDaemon/
│   ├── Tweak.x                     # IMFileTransfer, file/sysctl/getenv decoy hooks; async counter
│   ├── AntiDarkSwordDaemon.plist    # imagent, IMDPersistenceAgent, apsd, identityservicesd filter
│   ├── Makefile
│   └── README.md
├── AntiDarkSwordTF/
│   ├── Tweak.x                     # App-local hooks, preferences and settings gesture/overlay
│   ├── Makefile                    # Internal Logos backend; iOS 15+ arm64/arm64e standalone dylib
│   └── README.md
├── antidarkswordprefs/
│   ├── RootListController.m        # Settings, rules, Save/Cancel, daemon and restart actions
│   ├── ADSUpdateChecker.h          # Manual updater interface and installed-version helper
│   ├── ADSUpdateChecker.m          # Button-triggered stable-release check; PreferenceLoader only
│   ├── ADSDonationController.h     # Donation menu/controller interface
│   ├── ADSDonationController.m     # Venmo/Crypto menu and wallet modal; PreferenceLoader only
│   ├── ADSGames.h                  # Scene/controller declarations, synth state and game-state enum
│   ├── ADSCreditsMenu.m            # Contributor list, game host and selection scene
│   ├── ADSPyEater.m                # Snake game with synthesized audio
│   ├── ADSJailTris.m               # Tetris game with synthesized audio
│   ├── entry.plist                 # PreferenceLoader registration
│   ├── Resources/
│   │   ├── Info.plist              # Bundle metadata; release versions mirrored from control
│   │   ├── Root.plist              # Root settings specifiers, including GitHub/Updates/Donate
│   │   └── *.png                   # Banners, icons, contributor images and screenshots
│   ├── Makefile                    # Six .m sources, frameworks and isolated AltList reference
│   └── README.md
├── CorelliumDecoy/
│   ├── main.m                      # Idle decoy process with termination-signal handling
│   ├── c.eolnmsuk.corelliumdecoy.plist # Single source launch plist
│   ├── entitlements.plist          # Rootful/rootless signing entitlements
│   ├── entitlements-roothide.plist # Native Roothide signing entitlements
│   ├── Makefile                    # Environment-aware binary/plist staging and signing
│   └── README.md
├── layout/DEBIAN/
│   ├── postinst                    # Fixed target token; permissions and best-effort unload/load
│   └── prerm                       # Best-effort unload for remove/purge arguments only
├── vendor/
│   ├── AltList.framework           # Preserved reference; no release target selects it directly
│   ├── AltList_New.framework       # Modern rootful/rootless @rpath link reference
│   ├── AltList_Old.framework       # Legacy reference; generated copy uses its arm64 slice
│   ├── AltList_Roothide.framework  # Native Roothide link reference, including headers
│   ├── AltList-LICENSE.md          # Native reference's MIT license
│   └── README.md                   # Package/source/checksum/load-command provenance
├── .github/workflows/build.yml     # macos-15: metadata, five isolated builds, gated release draft
├── docs/
│   ├── building.md                 # Pinned toolchain, paths, build commands and known limits
│   ├── release-compatibility.md    # Release-note compatibility table; <version> placeholders
│   └── validation.md               # Metadata, build, package, device and publication checklist
├── ProjectStructure.md             # This audited file map
├── changelog.md                    # Release notes; current heading checked against control
├── depiction.json                  # Sileo JSON: Details → Changelog → Information
├── README.md                       # Installation, protection features, presets and component links
├── compatibility.md                # Package/dependency compatibility, behavior and validation limits
├── .gitignore                      # Local references, backups and generated output exclusions
└── LICENSE
```