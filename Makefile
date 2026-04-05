ARCHS = arm64 arm64e
TARGET := iphone:clang:16.5:14.5
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

# Route Theos to build the three independent subprojects
SUBPROJECTS += AntiDarkSwordUI AntiDarkSwordDaemon antidarkswordprefs
include $(THEOS_MAKE_PATH)/aggregate.mk

# This is the "Magic" part that makes the settings show up
internal-stage::
	$(ECHO_NOTHING)mkdir -p $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences$(ECHO_END)
	$(ECHO_NOTHING)cp antidarkswordprefs/entry.plist $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences/AntiDarkSword.plist$(ECHO_END)
