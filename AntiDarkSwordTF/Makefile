include $(THEOS)/makefiles/common.mk

# Use the ObjC-runtime Logos backend so the dylib has no CydiaSubstrate
# dependency — required for TrollFools injection on non-jailbroken devices.
LOGOS_DEFAULT_GENERATOR = internal

TWEAK_NAME = AntiDarkSword
AntiDarkSword_FILES = Tweak.x
# ARC + silence deprecation warnings for private API usage.
# TROLLFOOLS_BUILD guards any conditional code in shared headers.
AntiDarkSword_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -DTROLLFOOLS_BUILD=1
AntiDarkSword_FRAMEWORKS = Foundation UIKit WebKit JavaScriptCore CoreFoundation
# Private frameworks are resolved at runtime via ObjC messaging — weak-link so
# the dylib loads even in apps that don't bundle IMCore or ChatKit.
AntiDarkSword_PRIVATE_FRAMEWORKS = IMCore ChatKit
AntiDarkSword_LDFLAGS = -Wl,-weak_framework,IMCore -Wl,-weak_framework,ChatKit

include $(THEOS_MAKE_PATH)/tweak.mk
