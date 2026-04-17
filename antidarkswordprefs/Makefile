ARCHS = arm64 arm64e
TARGET = iphone:clang:16.5:14.0

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = AntiDarkSwordPrefs
AntiDarkSwordPrefs_FILES = RootListController.m
AntiDarkSwordPrefs_FRAMEWORKS = UIKit
AntiDarkSwordPrefs_PRIVATE_FRAMEWORKS = Preferences
AntiDarkSwordPrefs_EXTRA_FRAMEWORKS = AltList
AntiDarkSwordPrefs_INSTALL_PATH = /Library/PreferenceBundles

AntiDarkSwordPrefs_CFLAGS = -fobjc-arc -F../vendor
AntiDarkSwordPrefs_LDFLAGS = -F../vendor -Wl,-headerpad_max_install_names

include $(THEOS_MAKE_PATH)/bundle.mk

# Fix AltList install name after the bundle binary is staged.
# The vendor AltList ships with @loader_path/jbroot/… or @loader_path/.jbroot/…
# install names that expand to non-existent paths inside the bundle directory.
# @loader_path/../../Frameworks/AltList resolves to /var/jb/Library/Frameworks/AltList
# (rootless) and /Library/Frameworks/AltList (rootful) at runtime — both correct.
internal-stage::
	$(ECHO_NOTHING)install_name_tool -change @loader_path/jbroot/Library/Frameworks/AltList.framework/AltList @loader_path/../../Frameworks/AltList.framework/AltList $(THEOS_STAGING_DIR)/var/jb/Library/PreferenceBundles/AntiDarkSwordPrefs.bundle/AntiDarkSwordPrefs 2>/dev/null || true$(ECHO_END)
	$(ECHO_NOTHING)install_name_tool -change @loader_path/.jbroot/Library/Frameworks/AltList.framework/AltList @loader_path/../../Frameworks/AltList.framework/AltList $(THEOS_STAGING_DIR)/var/jb/Library/PreferenceBundles/AntiDarkSwordPrefs.bundle/AntiDarkSwordPrefs 2>/dev/null || true$(ECHO_END)
	$(ECHO_NOTHING)install_name_tool -change /var/jb/Library/Frameworks/AltList.framework/AltList @loader_path/../../Frameworks/AltList.framework/AltList $(THEOS_STAGING_DIR)/var/jb/Library/PreferenceBundles/AntiDarkSwordPrefs.bundle/AntiDarkSwordPrefs 2>/dev/null || true$(ECHO_END)
	$(ECHO_NOTHING)install_name_tool -change @loader_path/jbroot/Library/Frameworks/AltList.framework/AltList @loader_path/../../Frameworks/AltList.framework/AltList $(THEOS_STAGING_DIR)/Library/PreferenceBundles/AntiDarkSwordPrefs.bundle/AntiDarkSwordPrefs 2>/dev/null || true$(ECHO_END)
	$(ECHO_NOTHING)install_name_tool -change @loader_path/.jbroot/Library/Frameworks/AltList.framework/AltList @loader_path/../../Frameworks/AltList.framework/AltList $(THEOS_STAGING_DIR)/Library/PreferenceBundles/AntiDarkSwordPrefs.bundle/AntiDarkSwordPrefs 2>/dev/null || true$(ECHO_END)
	$(ECHO_NOTHING)install_name_tool -change /Library/Frameworks/AltList.framework/AltList @loader_path/../../Frameworks/AltList.framework/AltList $(THEOS_STAGING_DIR)/Library/PreferenceBundles/AntiDarkSwordPrefs.bundle/AntiDarkSwordPrefs 2>/dev/null || true$(ECHO_END)
