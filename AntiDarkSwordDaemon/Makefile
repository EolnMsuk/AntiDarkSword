ARCHS = arm64 arm64e
TARGET := iphone:clang:16.5:14.5
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = AntiDarkSwordDaemon
AntiDarkSwordDaemon_FILES = Tweak.x
AntiDarkSwordDaemon_CFLAGS = -fobjc-arc -Wno-deprecated-declarations
AntiDarkSwordDaemon_FRAMEWORKS = Foundation

include $(THEOS_MAKE_PATH)/tweak.mk
