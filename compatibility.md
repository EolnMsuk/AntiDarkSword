# Compatibility

The supplied 4.9.3 baseline was reported working on ordinary rootless and
patcher-converted rootless. This source port still needs device validation;
native Roothide is a separate, unverified route.

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
  Update checks run only when the Updates button is tapped and compare against
  published stable releases. Opening settings sends no update request.
- TrollFools provides app-local WebKit protection through its biometric-gated
  three-finger double-tap overlay. System daemon protection and CorelliumDecoy
  require the jailbreak package.

## App behavior

Blocking JavaScript, remote content or media can affect normal app features.
Use per-app rules to adjust protection when needed. Existing web pages may need
navigation or reloading after a user-agent change. The runtime follows the supplied 4.9.3 implementation; behavior with other
WebKit customizations requires device testing.

Corellium path spoofing applies inside the protected daemon processes.
Diagnostic probe totals are approximate across processes and resets.

If an app behaves unexpectedly, compare its behavior with protection disabled
and with other WebKit, user-agent or jailbreak-hiding tweaks disabled. Include
the device, iOS version, jailbreak, package variant and relevant logs when
[reporting an issue](https://github.com/EolnMsuk/AntiDarkSword/issues).
