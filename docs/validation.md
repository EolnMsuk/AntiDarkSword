# Release checklist

Use this checklist when preparing a release or checking future changes.

## Metadata and builds

After editing `control` or the current changelog, synchronize the depiction and
bundle metadata before pushing:

```sh
python3 scripts/version.py sync
python3 scripts/version.py check
```

The Actions workflow builds legacy, rootful, rootless, native Roothide and
TrollFools targets and creates a draft after all five succeed. For a configured
macOS checkout, the equivalent commands are:

```sh
bash scripts/build_target.sh legacy
bash scripts/build_target.sh rootful
bash scripts/build_target.sh rootless
bash scripts/build_target.sh roothide
bash scripts/build_target.sh trollfools
python3 scripts/collect_product.py verify-release
```

## Package inspection

Confirm the five asset names, platform requirements and package variants in the
[compatibility guide](release-compatibility.md). From the project root:

```sh
version="$(python3 scripts/version.py print)"
for target in legacy rootful rootless roothide; do
    asset="output/com.eolnmsuk.antidarksword_${version}_${target}.deb"
    dpkg-deb -f "$asset" Package Version Architecture Depends
    dpkg-deb -c "$asset"
    inspection=".build/inspection/$target"
    mkdir -p "$inspection"
    dpkg-deb -x "$asset" "$inspection"
    dpkg-deb -e "$asset" "$inspection/DEBIAN"
    prefix=""
    [ "$target" != rootless ] || prefix="/var/jb"
    prefs="$inspection$prefix/Library/PreferenceBundles/AntiDarkSwordPrefs.bundle/AntiDarkSwordPrefs"
    decoy="$inspection$prefix/usr/libexec/corelliumd"
    lipo -info "$prefs"
    otool -L "$prefs"
    otool -l "$prefs"
    ldid -e "$decoy"
    plutil -p "$inspection$prefix/Library/PreferenceBundles/AntiDarkSwordPrefs.bundle/Info.plist"
    plutil -p "$inspection$prefix/Library/LaunchDaemons/c.eolnmsuk.corelliumdecoy.plist"
    cat "$inspection/DEBIAN/postinst" "$inspection/DEBIAN/prerm"
done
lipo -info "output/AntiDarkSword_${version}_TrollFools.dylib"
otool -L "output/AntiDarkSword_${version}_TrollFools.dylib"
otool -l "output/AntiDarkSword_${version}_TrollFools.dylib"
```

Inspect both tweak dylibs and the preferences binary for signatures, slices,
minimum OS and dependency paths. Package versions must match `control`.
Rootless uses `/var/jb`; native Roothide uses its native package namespace and
`.jbroot` library paths. AltList is a runtime dependency and is not bundled.
TrollFools has no MobileSubstrate, ElleKit or Roothide runtime dependency.

## Device regression checks

| Area | Checks |
|---|---|
| Installation | Install, upgrade and remove; open preferences; check launchd state and environment paths |
| Settings | Enable/disable protection, change presets and per-app rules, save, respring and exercise decoy controls |
| Preference updates | Repeated saves propagate to apps, extensions and protected daemons without freezing Settings |
| Update checker | Manual feedback, correct stable-release link, silent automatic no-update/errors, rolling 24-hour limit including failed attempts |
| Update lifecycle | Reopening Settings, device sleep/reboot, clock changes, overlapping manual/automatic requests and controller dismissal |
| Venmo | Exact `https://venmo.com/EolnMsuk/` destination in the default browser, with and without Venmo installed |
| Crypto | All eight wallets match `ADSDonationController.m`; independent copy confirmations, readable addresses and reachable Cancel |
| WebKit and apps | Protected/unprotected behavior in browsers, Mail, Messages, extensions and commonly used apps; coexistence with other installed tweaks |
| Games and audio | Open/close games, change scenes, toggle music, trigger rapid sounds, rotate and dismiss Settings |
| TrollFools | Injection, biometric authentication, settings gesture, default protection state and app-local rules |

## Publication

Review the draft's five assets and compatibility guide. Check Sileo's
Details → Changelog → Information tab order, current version, changelog text,
screenshots and links. Publish the stable draft when ready; the update checker
can discover it after publication.
