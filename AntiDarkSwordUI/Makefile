TARGET := iphone:clang:16.5:14.5
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = AntiDarkSwordUI
AntiDarkSwordUI_FILES = Tweak.x
AntiDarkSwordUI_CFLAGS = -fobjc-arc -Wno-deprecated-declarations
AntiDarkSwordUI_FRAMEWORKS = WebKit JavaScriptCore

include $(THEOS_MAKE_PATH)/tweak.mk
