TARGET := iphone:clang:14.5:16.5
INSTALL_TARGET_PROCESSES = SpringBoard
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = AntiDarkSword
AntiDarkSword_FILES = Tweak.x
AntiDarkSword_CFLAGS = -fobjc-arc -Wno-deprecated-declarations
AntiDarkSword_FRAMEWORKS = WebKit JavaScriptCore

include $(THEOS_MAKE_PATH)/tweak.mk

# This is the "Magic" part that makes the settings show up
internal-stage::
	$(ECHO_NOTHING)mkdir -p $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences$(ECHO_END)
	$(ECHO_NOTHING)cp antidarkswordprefs/entry.plist $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences/AntiDarkSword.plist$(ECHO_END)

SUBPROJECTS += antidarkswordprefs
include $(THEOS_MAKE_PATH)/aggregate.mk
