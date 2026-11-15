include ../config/target.mk
include $(THEOS)/makefiles/common.mk

TWEAK_NAME = AntiDarkSwordUI
AntiDarkSwordUI_FILES = Tweak.x
AntiDarkSwordUI_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Wno-unguarded-availability-new
AntiDarkSwordUI_LDFLAGS =
ifneq ($(ADS_RELEASE_TARGET),legacy)
AntiDarkSwordUI_LDFLAGS += -Wl,-fixup_chains
endif
ifeq ($(THEOS_PACKAGE_SCHEME),roothide)
AntiDarkSwordUI_LIBRARIES += roothide
endif
AntiDarkSwordUI_FRAMEWORKS = Foundation UIKit WebKit JavaScriptCore

include $(THEOS_MAKE_PATH)/tweak.mk
