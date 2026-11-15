# Changelog

## 4.9.7

- Rebased runtime, settings, games and lifecycle behavior on the supplied working 4.9.3 source. Restored its direct Save, Honeypot and Reset command flow; this source change does not verify launchctl success on a device.
- Kept the manual 🔄 Updates button with installed-version comparison against the official stable release. Removed automatic checks and their scheduling/bookkeeping.
- Kept Donate with EolnMsuk Venmo and all eight existing crypto wallets, network labels, tap-to-copy feedback and Cancel.
- Kept INFO order: Updates, GitHub, Donate, Credits.
- Retained the existing five-target build workflow and package path adapters. Native Roothide remains unverified; ordinary rootless and converted-rootless require separate device checks.

## 4.9.6

### What's New

- **Update Checker:** Added a manual **"Check for Updates"** option in settings to check for the latest stable GitHub release. The app will also perform a quiet automatic check once per day when opened, only notifying you if a new version is available.
- **Native Roothide Support:** Added native Roothide build support so users no longer need an external patcher.
- **Standardized Package Names:** Standardized all Debian release packages clearly by their jailbreak environment (legacy, rootful, rootless, and roothide), alongside the TrollFools dylib.
- **Version Management:** Streamlined versioning so that the control file serves as the single source of truth for the package version.
- **Performance & Reliability:** Fixed underlying race conditions, improved audio handling and thread safety for mini-games, and optimized notification handling.
- **Smoother Operation:** Replaced raw observer pointers with cleaner tokens and improved error handling for process controls to ensure overall system stability.
- **Sileo Depiction Update:** Added a new **Changelog** tab to the Sileo depiction page right after the Details tab.
- **Expanded Donation Options:** Combined the donation section into Venmo and a new **Crypto Wallets** menu.
