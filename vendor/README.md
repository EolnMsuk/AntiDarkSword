# Build references

The original `AltList.framework`, `AltList_New.framework`, and
`AltList_Old.framework` are preserved. Builds copy a selected reference to an
isolated directory; no framework is bundled into AntiDarkSword packages.

`AltList_Roothide.framework` is the unmodified framework (including headers)
extracted from the official native Roothide AltList package:

- Source: https://github.com/roothide/AltList
- Package: https://roothide.github.io/debfiles/com.opa334.altlist_1.0.11_iphoneos-arm64e.deb
- Package SHA-256: `7d145977d3fbcd5030564dc429e18f7456c29f92020c36f32e61d4a82418f737`
- Package identifier/version/architecture: `com.opa334.altlist`, `1.0.11`, `iphoneos-arm64e`.
- Mach-O: arm64 and current arm64e ABI; minimum iOS 15.0; install ID
  `@loader_path/.jbroot/Library/Frameworks/AltList.framework/AltList`.
- License: MIT; see `AltList-LICENSE.md` and the upstream source.

The supplied modern reference requires iOS 15.0 and uses an `@rpath` install ID;
the preferences bundle supplies the target's framework rpath. The old reference
has a rootful absolute install ID and an arm64 slice supporting the legacy
baseline. Debian package architecture names and Mach-O CPU slices are separate.
