# Changelog

## 4.9.7

- Stopped unnecessary honeypot commands when changing protection levels or honeypot settings with Protection off.
- Improved applying Level 3 changes: no unload before enabling, and Cancel leaves the previous settings in place.
- Kept protection, daemon, and app rules consistent when saving changes. Failed commands now show useful details and keep restart changes available to retry.
- Clarified exploit-mitigation descriptions and what the system daemon switches protect.
- Renamed the update row to 🔄 Updates and placed it above GitHub, Donate, and Credits.

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