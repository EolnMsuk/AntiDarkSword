#!/usr/bin/env bash
set -euo pipefail

chmod +x layout/DEBIAN/prerm 2>/dev/null || true
chmod +x layout/DEBIAN/postinst 2>/dev/null || true

VERSION=$(grep -i '^Version:' control | awk '{print $2}')
[ -z "$VERSION" ] && { echo "Error → Version not found in control file"; exit 1; }

mkdir -p output
rm -f output/*.deb output/*.dylib

swap_altlist() {
    local target_fw=$1
    rm -rf vendor/AltList.framework
    cp -R "vendor/AltList_${target_fw}.framework" vendor/AltList.framework
}

# SDK PATHS
SDK_14="$THEOS/sdks/iPhoneOS14.5.sdk"
SDK_16="$THEOS/sdks/iPhoneOS16.5.sdk"

# ==========================================
# LEGACY TARGETS (iOS 13 - 14) → Native arm64
# ==========================================
swap_altlist "Old"

if command -v lipo >/dev/null 2>&1; then
    lipo vendor/AltList.framework/AltList -thin arm64 -output vendor/AltList.framework/AltList
fi

# Rootful Legacy
make clean
rm -rf packages/*
make package FINALPACKAGE=1 SYSROOT="$SDK_14" TARGET="iphone:clang:14.5:13.0" ARCHS="arm64"
mv packages/*.deb "output/com.eolnmsuk.antidarksword_${VERSION}_legacy_iphoneos-arm.deb"

# ==========================================
# MODERN TARGETS (iOS 15+) → arm64
# ==========================================
swap_altlist "New"

# Modern Rootful
make clean
rm -rf packages/*
make package FINALPACKAGE=1 SYSROOT="$SDK_16" TARGET="iphone:clang:16.5:15.0" ARCHS="arm64"
mv packages/*.deb "output/com.eolnmsuk.antidarksword_${VERSION}_modern_iphoneos-arm.deb"

# Modern Rootless
make clean
rm -rf packages/*
make package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=rootless SYSROOT="$SDK_16" TARGET="iphone:clang:16.5:15.0" ARCHS="arm64"
mv packages/*.deb "output/com.eolnmsuk.antidarksword_${VERSION}_modern_iphoneos-arm64.deb"

# TrollFools Dylib
cd AntiDarkSwordTF
make clean
make FINALPACKAGE=1 SYSROOT="$SDK_16" TARGET="iphone:clang:16.5:15.0" ARCHS="arm64"
DYLIB=$(find .theos/obj -name "AntiDarkSword*.dylib" | head -1)
cp "$DYLIB" "../output/AntiDarkSword_${VERSION}_TrollFools.dylib"
cd ..