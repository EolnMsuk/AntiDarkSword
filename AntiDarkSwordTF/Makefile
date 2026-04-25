ARCHS ?= arm64 arm64e
TARGET ?= iphone:clang:latest:14.0

TARGET_CODESIGN_FLAGS = -S -Hsha1 -Hsha256

include $(THEOS)/makefiles/common.mk

# Use the ObjC-runtime Logos backend so the dylib has no CydiaSubstrate
# dependency — required for TrollFools injection on non-jailbroken devices.
LOGOS_DEFAULT_GENERATOR = internal

TWEAK_NAME = AntiDarkSword
AntiDarkSword_FILES = Tweak.x
# ARC + silence deprecation warnings for private API usage.
# TROLLFOOLS_BUILD guards any conditional code in shared headers.
AntiDarkSword_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Wno-unguarded-availability-new -DTROLLFOOLS_BUILD=1
AntiDarkSword_LDFLAGS = -Wl,-fixup_chains
AntiDarkSword_FRAMEWORKS = Foundation UIKit WebKit JavaScriptCore CoreFoundation

include $(THEOS_MAKE_PATH)/tweak.mk
