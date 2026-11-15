# Building AntiDarkSword

The root `control` file is the only release-version authority. Run
`python3 scripts/version.py sync`, then `python3 scripts/version.py check` after
editing its Version field or the current changelog. The helper mirrors preferences bundle version keys,
the depiction Information version, and the current changelog section embedded
in the depiction. Reusable asset examples use `<version>`.

All build entry points load `config/target.mk` before Theos. Target definitions
live in `config/targets.json`. `PACKAGE_VERSION` is forced from `control`, so
Theos debug build counters and command-line version overrides cannot silently
change release metadata. Preparation occurs before resource staging, including
direct preferences builds. Mirror writes are idempotent and atomic; submakes
only check them. The aggregate explicitly selects `Makefile` for subprojects
when invoked through `Makefile.legacy` or `Makefile.trollfools`.

## Native Roothide toolchain

Target preparation also derives an isolated control copy from root `control`,
preserving its Version and adding the selected firmware minimum (and the verified
native AltList minimum for Roothide). The pinned Theos control-input variable
points to that copy. Preferences resources are copied atomically per target;
their staged MinimumOSVersion matches the actual deployment target while both
release-version keys still come from control. Parallel instance submakes do not
expose partially copied framework binaries or resource files. Generated bundle
resources/control files use readable `0644` modes and maintainer scripts use
`0755`; metadata synchronization preserves existing source-file permissions.

| Input | Pinned source/revision |
|---|---|
| Roothide-capable Theos | [roothide/theos](https://github.com/roothide/theos/tree/958fea4f779943505b15b93c88bb4db8d97b346d), `958fea4f779943505b15b93c88bb4db8d97b346d` |
| Its headers submodule | [roothide/headers](https://github.com/roothide/headers/tree/e1132e2bbc3ca15c50e2311bcd349cb7353409e1), `e1132e2bbc3ca15c50e2311bcd349cb7353409e1` |
| Its libraries submodule | [roothide/lib](https://github.com/roothide/lib/tree/85e9b5b8aff11bbefc59525c64c8f55149926e56), `85e9b5b8aff11bbefc59525c64c8f55149926e56` |
| Its Logos submodule | [theos/logos](https://github.com/theos/logos/tree/365a4e7028234e90bc2cbc724e5c87607130d3b3), `365a4e7028234e90bc2cbc724e5c87607130d3b3` |
| CI patched SDKs | [theos/sdks](https://github.com/theos/sdks/tree/0222fd5413cf4b9af096f37b4621afa2688572f7), `0222fd5413cf4b9af096f37b4621afa2688572f7` (14.5 and 16.5) |
| Native AltList | Official `com.opa334.altlist` 1.0.11, `iphoneos-arm64e`; package SHA-256 `7d145977d3fbcd5030564dc429e18f7456c29f92020c36f32e61d4a82418f737`; see [vendor provenance](../vendor/README.md) |

The native scheme is `THEOS_PACKAGE_SCHEME=roothide`. Its Theos module sets the
Debian architecture to `iphoneos-arm64e` and uses `@loader_path/.jbroot` install
IDs. This differs from the rootless prefix and package architecture. The build
fails explicitly if its native module, typed API header, or link library is
missing. Native AltList is a separate verified link reference, never an edited
copy of the supplied rootless binary and never bundled in our package.

The official [developer guide](https://github.com/roothide/Developer),
[path interface](https://github.com/roothide/Developer/blob/main/interface.md),
[bootstrap path rules](https://github.com/roothide/Developer/blob/main/roothide.md),
and [entitlements](https://github.com/roothide/Developer/blob/main/entitlements.md)
establish the environment contract. `ADSPaths.h` calls the typed `NSString *`
`jbroot`/`rootfs` overloads; it never casts an arbitrary `dlsym` function or frees
cached C results. Native dependent libraries are linked from the native Theos
library directory, including `libroothide` and the substrate compatibility stub.
The environment must supply the matching runtime libraries/bootstrap, native
PreferenceLoader and native AltList. The official repository's package index
lists `preferenceloader` and `com.opa334.altlist` for `iphoneos-arm64e`, with
ElleKit providing the existing virtual `mobilesubstrate` dependency.

Roothide stages `/Library/...` and `/usr/libexec/corelliumd` in its native package
namespace. Native dpkg/bootstrap provide randomized-root relocation and `.jbroot`
links. Bootstrap utilities and launch plists consume jbroot-based paths; Settings
resolves executable paths with `jbroot` and converts file arguments with `rootfs`.
Maintainer scripts are generated into each target's isolated layout with a fixed
environment, before Theos copies them. A rootful package never selects `/var/jb`
merely because that directory exists. Mobile-user preferences retain their
existing domain and any-host scope, with canonical `/var/mobile` reads and a
legacy jailbreak-prefixed file fallback. Native daemon signing uses the official
base entitlements in a separate native entitlement file.

## macOS requirements and commands

The runtime/settings/game sources have been rebased on the supplied 4.9.3
reference, with only manual update/donation integration and package path adapters.
`ADSPaths.h` keeps compile-selected absolute executable paths (`/usr/bin` then
`/bin` for launchctl), typed native `jbroot` resolution and `rootfs` plist arguments.
The user-supplied reference and vendor/dependency trees remain read-only.

Process controls now follow 4.9.3: direct `posix_spawn`, literal `launchctl` or
`killall` argv[0], NULL attributes/envp, inherited stdio, and the original inline
waits where present. Settings are no longer gated by the later process runner.
This also restores 4.9.3's command ordering, Cancel reversal, preference writes,
restart flags and Reset behavior; it does not retain the later staged transaction
or bounded asynchronous runner. Child exit status is not verified by this flow.
A switch changing to OFF does not prove job removal. Installer/boot registration
is independent of the preference, and the original RunAtLoad/KeepAlive policy is
unchanged. Lifecycle scripts retain the 4.9.3 best-effort sequence with a fixed
package target and quoted paths.

The previous compatibility attempt using NULL envp and basename argv[0] did not
resolve the reported required stop: ordinary rootless still exited normally with
status 1 and empty output; native Roothide still terminated by signal 6 with a
plist-patching failure. These are distinct, unresolved command outcomes. The
source restore does not establish either underlying cause or successful cleanup.
The five-target workflow, native libraries/signing and output naming remain;
native Roothide is an unverified build route, separate from patcher-converted
rootless. Validate ordinary rootless first and each Roothide route separately.

Update checks are manual only. Network timeouts bound a button-initiated request;
there is no automatic cadence, timer, persisted gate, download or install.

The local `python -B scripts/check_sources.py` checks the six preferences sources
with its configured arm64/iOS-13 syntax arguments. It does not build/link/sign or
validate Logos, all target branches or device behavior. Its supplied dependencies
lack `arm_neon.h`, an ARM compiler intrinsic header reached through SpriteKit's
SDK imports in both the current and reference games. That local dependency gap
is not evidence that the device games fail and must not be repaired by changing
game code or copying arbitrary compiler headers into the SDK.

Use a complete pinned Roothide Theos checkout with its recursive submodules,
Xcode command-line tools (`xcrun` clang/linker), `ldid`, `dpkg-deb`, GNU make,
Python 3, Perl, `xz`/`lzma` and the normal Theos host prerequisites. CI configures the pinned
Theos and SDK checkouts on `macos-15` and prepares signing/packaging tools. It
uses the pinned SDK checkout rather than a locally installed SDK directory.

From the project root:

```sh
python3 scripts/version.py sync
python3 scripts/version.py check
bash -n build_all.sh scripts/build_target.sh
sh -n layout/DEBIAN/postinst
sh -n layout/DEBIAN/prerm
bash scripts/build_target.sh legacy
bash scripts/build_target.sh rootful
bash scripts/build_target.sh rootless
bash scripts/build_target.sh roothide
bash scripts/build_target.sh trollfools
python3 scripts/collect_product.py verify-release
```

Alternatively, `bash build_all.sh` invokes those five build targets with the same
settings. Set `THEOS` to the complete installation and optionally `ADS_SDK_DIR`
to the parent of the two SDK directories. SDK 16.5 can fall back to the supplied
local reference; SDK 14.5 is a separate legacy prerequisite. No helper deletes
old output; move existing products aside before starting a new release build.

Each target has its own `.build/<target>/` objects, staging, prepared layout,
framework reference and package directory. `output/` receives exactly one
validated product per target. Debian Package/Version/Architecture and standalone
dylib slices/dependencies are checked before collection. Legacy linking omits
`-fixup_chains` for the iOS 13 baseline. Its generated AltList link reference
contains only the original arm64 slice: current linkers reject the unused old
arm64e ABI slice in the supplied universal framework. Preparation validates the
selected fat record/header identity and range, preserves the slice bytes and
install ID, and leaves all vendor originals and modern references untouched.

The workflow's metadata job checks local mirrors and exports one control
version. Five isolated builds must all succeed, and the release job rechecks
the complete asset set. It creates a stable **draft** tagged
`v<version>-b<run_number>` with the current changelog and compatibility guide.
Review and publish the draft when ready. The updater sees published stable
releases.
