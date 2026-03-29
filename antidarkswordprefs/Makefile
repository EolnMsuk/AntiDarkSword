TARGET := iphone:clang:14.5:15.0
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = AntiDarkSwordPrefs
AntiDarkSwordPrefs_FILES = RootListController.m
AntiDarkSwordPrefs_FRAMEWORKS = UIKit
AntiDarkSwordPrefs_PRIVATE_FRAMEWORKS = Preferences
AntiDarkSwordPrefs_INSTALL_PATH = /Library/PreferenceBundles
AntiDarkSwordPrefs_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/bundle.mk

# This part tells Theos to create the entry point for Settings
internal-stage::
	$(ECHO_NOTHING)mkdir -p $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences$(ECHO_END)
	$(ECHO_NOTHING)cp entry.plist $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences/AntiDarkSword.plist$(ECHO_END)
