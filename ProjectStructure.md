# Project structure

```text
AntiDarkSword/
├── control                         # Only release-version authority; package ID/dependencies
├── Makefile                        # UI, daemon, preferences and decoy aggregate
├── Makefile.legacy                 # Explicit legacy target, then the same aggregate
├── Makefile.trollfools             # Standalone TF aggregate only
├── build_all.sh                    # User-run wrapper for all five targets
├── ADSLogging.h                    # Existing debug/release logging macro
├── ADSPaths.h                      # Build-selected install paths; typed native Roothide API
├── config/
│   ├── targets.json                # SDK, minimum OS, slices, scheme, package arch, AltList
│   └── target.mk                   # Before-Theos target/version/isolation preparation
├── scripts/
│   ├── version.py                 # print/sync/check/notes from control and current changelog
│   ├── target_config.py           # Reads shared target definitions
│   ├── prepare_reference.py       # Validates/copies link-only AltList and target preferences resources
│   ├── stage_lifecycle.py         # Prepares derived control/dependencies and fixed-environment scripts
│   ├── build_target.sh            # User/CI build, exact collection; never run in this session
│   ├── collect_product.py         # Package metadata/dylib checks; verifies complete five-asset set
│   ├── macho.py                   # Read-only Mach-O slice/load-command inspection
│   ├── release_notes.py           # Compatibility guide with control-derived asset examples
│   └── check_sources.py           # Syntax-only check of actual preferences .m list; see limitations
├── AntiDarkSwordUI/
│   ├── Tweak.x                    # UIKit/WebKit/JS/attachment hooks; existing process/Gecko gates
│   ├── AntiDarkSwordUI.plist       # Existing broad com.apple.UIKit injection filter
│   ├── Makefile                   # Shared target config; native library selection
│   └── README.md
├── AntiDarkSwordDaemon/
│   ├── Tweak.x                    # IMFileTransfer and POSIX decoy hooks; async diagnostic counter
│   ├── AntiDarkSwordDaemon.plist   # Existing four-process filter
│   ├── Makefile
│   └── README.md
├── AntiDarkSwordTF/
│   ├── Tweak.x                    # Internal Logos hooks; authenticated settings gesture/overlay
│   │                              # No updater or donation features
│   ├── Makefile                   # Standalone iOS 15+ arm64/arm64e baseline
│   └── README.md
├── antidarkswordprefs/
│   ├── RootListController.m       # Preference controllers, rules, existing Save/process actions
│   ├── ADSUpdateChecker.h/.m      # PreferenceLoader-only stable-release coordinator and daily gate
│   ├── ADSDonationController.h/.m # PreferenceLoader-only Venmo/Crypto menu and wallet modal
│   ├── ADSProcessRunner.h/.m      # Serial bounded waits for explicit existing process controls
│   ├── ADSAudio.h/.m              # Render-retained synth owner and bounded sound-command mailbox
│   ├── ADSGames.h                 # Scene/controller declarations and game-state enum
│   ├── ADSCreditsMenu.m           # Contributor list, game host, selection scene
│   ├── ADSPyEater.m               # Existing Snake game; safe audio communication/lifetime
│   ├── ADSJailTris.m               # Existing Tetris game; safe audio communication/lifetime
│   ├── entry.plist                # PreferenceLoader registration
│   ├── Resources/
│   │   ├── Info.plist             # Generated/checked bundle version mirrors
│   │   ├── Root.plist             # Root settings specifiers; GitHub/update/Donate rows
│   │   └── *.png                  # Existing banners, icons and screenshots
│   ├── Makefile                   # Explicit .m/framework list and isolated AltList reference
│   └── README.md
├── CorelliumDecoy/
│   ├── main.m                     # Existing idle decoy process
│   ├── c.eolnmsuk.corelliumdecoy.plist # Single source launch plist
│   ├── entitlements.plist         # Existing rootful/rootless signing entitlements
│   ├── entitlements-roothide.plist # Official native base entitlement requirements
│   ├── Makefile                   # Environment-aware binary/plist staging and signing
│   └── README.md
├── layout/DEBIAN/
│   ├── postinst                   # Fixed environment token; configure/load and partial-install checks
│   └── prerm                      # Unload on removal/deconfiguration/upgrade
├── vendor/
│   ├── AltList.framework          # Original active vendor copy, preserved
│   ├── AltList_New.framework      # Original iOS 15+ @rpath reference, preserved
│   ├── AltList_Old.framework      # Original rootful legacy reference, preserved
│   ├── AltList_Roothide.framework # Verified official native framework incl. original headers
│   ├── AltList-LICENSE.md          # Native reference's MIT license
│   └── README.md                  # Package/source/checksum/load-command provenance
├── .github/workflows/build.yml    # macos-15: metadata, five isolated targets, gated draft
├── docs/
│   ├── building.md                # Pinned requirements, native paths, user-run commands
│   ├── release-compatibility.md   # Draft compatibility guide; <version> placeholders
│   ├── validation.md              # Exact pending CI/package/device/release checks
│   └── local-validation.md        # Actual local results and unavailable checks
├── changelog.md                   # Completed source changes; current heading checked against control
├── depiction.json                # Raw Sileo JSON: Details → Changelog → Information
├── README.md
├── compatibility.md               # Source-backed audit, limitations and validation matrix
├── plan.md                        # Original requirements plus factual implementation status
├── prompt.md                      # Original handoff
├── .gitignore                     # Local references/baselines and generated output excluded
└── LICENSE
```