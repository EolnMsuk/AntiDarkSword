include ../config/target.mk
include $(THEOS)/makefiles/common.mk

TWEAK_NAME = AntiDarkSwordDaemon
AntiDarkSwordDaemon_FILES = Tweak.x
AntiDarkSwordDaemon_CFLAGS = -fobjc-arc -Wno-deprecated-declarations
AntiDarkSwordDaemon_LDFLAGS =
ifneq ($(ADS_RELEASE_TARGET),legacy)
AntiDarkSwordDaemon_LDFLAGS += -Wl,-fixup_chains
endif
ifeq ($(THEOS_PACKAGE_SCHEME),roothide)
AntiDarkSwordDaemon_LIBRARIES += roothide
endif
AntiDarkSwordDaemon_FRAMEWORKS = Foundation CoreFoundation

include $(THEOS_MAKE_PATH)/tweak.mk
