#!/usr/bin/env bash
set -euo pipefail

chmod +x layout/DEBIAN/prerm 2>/dev/null || true
chmod +x layout/DEBIAN/postinst 2>/dev/null || true

VERSION=$(grep -i '^Version:' control | awk '{print $2}')
[ -z "$VERSION" ] && { echo "Error → Version not found in control file"; exit 1; }

mkdir -p output
rm -f output/*.deb output/*.dylib

SDK_16="$THEOS/sdks/iPhoneOS16.5.sdk"

# AltList_New: supports iOS 14+ (required by com.opa334.altlist dependency)
rm -rf vendor/AltList.framework
cp -R vendor/AltList_New.framework vendor/AltList.framework

# Modern Rootful (iOS 15+, palera1n fakefs)
make clean
rm -rf packages/*
make package FINALPACKAGE=1 SYSROOT="$SDK_16" TARGET="iphone:clang:16.5:15.0" ARCHS="arm64"
mv packages/*.deb "output/com.eolnmsuk.antidarksword_${VERSION}_modern_iphoneos-arm.deb"

# Modern Rootless (iOS 15+, Dopamine / palera1n rootless / NathanLR)
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
