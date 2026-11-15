# Compatibility

AntiDarkSword has been tested on device. Install the package that matches your
iOS version and jailbreak environment.

## Packages

| Target | Platform | CPU slices | Package architecture |
|---|---|---|---|
| legacy | iOS 13–14 rootful | arm64 | iphoneos-arm |
| rootful | iOS 15–17 rootful | arm64, arm64e | iphoneos-arm |
| rootless | iOS 15–17 rootless | arm64, arm64e | iphoneos-arm64 |
| roothide | Native Roothide; iOS 15+ | arm64, arm64e | iphoneos-arm64e |
| TrollFools | Per-app injection; iOS 15+ | arm64, arm64e | dylib |

## Dependencies

Jailbreak packages require PreferenceLoader, AltList and a compatible hook
loader. Use dependencies built for the same jailbreak environment as the
package. Native Roothide requires native PreferenceLoader and AltList 1.0.11 or
later; install the `_roothide.deb` directly without an external patcher.

TrollFools requires a compatible TrollStore/TrollFools setup and stores settings
separately for each injected app. It uses the Objective-C runtime directly and
has no MobileSubstrate dependency.

## Feature availability

- The jailbreak packages provide Settings.app preferences, preset levels,
  per-app rules, daemon protection and CorelliumDecoy.
- Update checking and the Donate menu are available in PreferenceLoader.
  Automatic update checks run when opening AntiDarkSword settings, at most once
  per rolling 24 hours. Only published stable releases can trigger an alert.
- TrollFools provides app-local WebKit protection through its biometric-gated
  three-finger double-tap overlay. System daemon protection and CorelliumDecoy
  require the jailbreak package.

## App behavior

Blocking JavaScript, remote content or media can affect normal app features.
Use per-app rules to adjust protection when needed. Existing web pages may need
navigation or reloading after a user-agent change. AntiDarkSword manages its own
WebKit scripts and content rules without clearing those belonging to apps or
other tweaks.

Corellium path spoofing applies inside the protected daemon processes.
Diagnostic probe totals are approximate across processes and resets.

If an app behaves unexpectedly, compare its behavior with protection disabled
and with other WebKit, user-agent or jailbreak-hiding tweaks disabled. Include
the device, iOS version, jailbreak, package variant and relevant logs when
[reporting an issue](https://github.com/EolnMsuk/AntiDarkSword/issues).
