### Compatibility Guide

| Asset | Intended build baseline |
|---|---|
| `com.eolnmsuk.antidarksword_<version>_legacy.deb` | iOS 13–14 rootful; arm64; SDK 14.5 |
| `com.eolnmsuk.antidarksword_<version>_rootful.deb` | iOS 15–17 rootful; arm64/arm64e; SDK 16.5 |
| `com.eolnmsuk.antidarksword_<version>_rootless.deb` | iOS 15–17 rootless; arm64/arm64e; SDK 16.5 |
| `com.eolnmsuk.antidarksword_<version>_roothide.deb` | Native Roothide scheme; iOS 15+ deployment; arm64/arm64e; SDK 16.5 |
| `AntiDarkSword_<version>_TrollFools.dylib` | Per-app TrollFools/TrollStore injection; iOS 15+ deployment; arm64/arm64e; no MobileSubstrate |

These are deployment/compilation targets, not a claim that every device or OS
combination supports that jailbreak or has been tested. Roothide uses Debian
architecture `iphoneos-arm64e`; this is separate from Mach-O CPU slices. Use
native PreferenceLoader, AltList, and the environment's compatible hook loader;
the native Roothide package requires no external patcher.

Package, install/upgrade/remove, and device regression checks are pending user
results. Review load commands, signing, package contents and the validation
matrix in `docs/validation.md` before publishing.

This release is created as a **draft**. The updater sees it only after the user
publishes it as a stable release. Tags retain `v<version>-b<run_number>`; the build
suffix does not change the three-part project version.
