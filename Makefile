TARGET := iphone:clang:latest:15.0
INSTALL_TARGET_PROCESSES = SpringBoard
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = AntiDarkSword
AntiDarkSword_FILES = Tweak.x
AntiDarkSword_CFLAGS = -fobjc-arc -Wno-deprecated-declarations
AntiDarkSword_FRAMEWORKS = WebKit JavaScriptCore

include $(THEOS_MAKE_PATH)/tweak.mk
SUBPROJECTS += antidarkswordprefs
include $(THEOS_MAKE_PATH)/aggregate.mk
