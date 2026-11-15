#!/usr/bin/env bash
# User/CI build entry point; not executed during local source implementation.
set -euo pipefail
project_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_root"
target="${1:?Usage: bash scripts/build_target.sh legacy|rootful|rootless|roothide|trollfools}"
python3 scripts/target_config.py "$target" fields >/dev/null
: "${THEOS:?Set THEOS to a complete Theos installation; see docs/building.md}"
for tool in make python3 xcrun ldid perl; do
    command -v "$tool" >/dev/null || { echo "Required tool missing: $tool" >&2; exit 1; }
done
if [[ "$target" != trollfools ]]; then
    for tool in dpkg-deb lzma; do
        command -v "$tool" >/dev/null || { echo "Required packaging tool missing: $tool" >&2; exit 1; }
    done
fi
[[ "$(uname -s)" == Darwin ]] || { echo 'Use the documented macOS build host.' >&2; exit 1; }
sdk_version="$(python3 scripts/target_config.py "$target" sdk)"
sdk="${ADS_SDK_DIR:-$THEOS/sdks}/iPhoneOS${sdk_version}.sdk"
if [[ "$sdk_version" == 16.5 && ! -d "$sdk" && -d .theos-toolchain/iPhoneOS16.5.sdk ]]; then
    sdk="$project_root/.theos-toolchain/iPhoneOS16.5.sdk"
fi
for required in SDKSettings.plist usr/include/stdio.h System/Library/Frameworks/Foundation.framework/Headers/Foundation.h; do
    [[ -f "$sdk/$required" ]] || { echo "Incomplete SDK: $sdk/$required" >&2; exit 1; }
done
python3 scripts/version.py sync
build_dir="$project_root/.build/$target"
mkdir -p "$build_dir"
if [[ -d "$build_dir/packages" ]] && compgen -G "$build_dir/packages/*.deb" >/dev/null; then
    echo "Existing packages in $build_dir/packages; move them aside before a new build." >&2
    exit 1
fi
case "$target" in
    legacy) entry=Makefile.legacy ;;
    trollfools) entry=Makefile.trollfools ;;
    *) entry=Makefile ;;
esac
if [[ "$target" == trollfools ]]; then
    make -f "$entry" ADS_RELEASE_TARGET="$target" SYSROOT="$sdk" FINALPACKAGE=1 DEBUG=0
else
    make -f "$entry" ADS_RELEASE_TARGET="$target" SYSROOT="$sdk" FINALPACKAGE=1 DEBUG=0 package
fi
python3 scripts/collect_product.py "$target"
