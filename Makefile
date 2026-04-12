ARCHS = arm64 arm64e
export TARGET := iphone:clang:latest:14.0

include $(THEOS)/makefiles/common.mk

SUBPROJECTS += AntiDarkSwordUI AntiDarkSwordDaemon antidarkswordprefs CorelliumDecoy
include $(THEOS_MAKE_PATH)/aggregate.mk

internal-stage::
	$(ECHO_NOTHING)mkdir -p $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences$(ECHO_END)
	$(ECHO_NOTHING)cp antidarkswordprefs/entry.plist $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences/AntiDarkSword.plist$(ECHO_END)
