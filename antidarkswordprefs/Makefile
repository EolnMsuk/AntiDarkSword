include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = AntiDarkSwordPrefs
AntiDarkSwordPrefs_FILES = RootListController.m
AntiDarkSwordPrefs_FRAMEWORKS = UIKit
AntiDarkSwordPrefs_PRIVATE_FRAMEWORKS = Preferences
AntiDarkSwordPrefs_EXTRA_FRAMEWORKS = AltList
AntiDarkSwordPrefs_INSTALL_PATH = /Library/PreferenceBundles

AntiDarkSwordPrefs_CFLAGS = -fobjc-arc -F../vendor
AntiDarkSwordPrefs_LDFLAGS = -F../vendor

include $(THEOS_MAKE_PATH)/bundle.mk

after-stage::
	install_name_tool -change .jbroot/Library/Frameworks/AltList.framework/AltList @loader_path/../../Frameworks/AltList.framework/AltList $(THEOS_STAGING_DIR)/var/jb/Library/PreferenceBundles/AntiDarkSwordPrefs.bundle/AntiDarkSwordPrefs || true
	install_name_tool -change /var/jb/Library/Frameworks/AltList.framework/AltList @loader_path/../../Frameworks/AltList.framework/AltList $(THEOS_STAGING_DIR)/var/jb/Library/PreferenceBundles/AntiDarkSwordPrefs.bundle/AntiDarkSwordPrefs || true
	install_name_tool -change .jbroot/Library/Frameworks/AltList.framework/AltList @loader_path/../../Frameworks/AltList.framework/AltList $(THEOS_STAGING_DIR)/Library/PreferenceBundles/AntiDarkSwordPrefs.bundle/AntiDarkSwordPrefs || true
	install_name_tool -change /Library/Frameworks/AltList.framework/AltList @loader_path/../../Frameworks/AltList.framework/AltList $(THEOS_STAGING_DIR)/Library/PreferenceBundles/AntiDarkSwordPrefs.bundle/AntiDarkSwordPrefs || true
