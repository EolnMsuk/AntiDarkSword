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

# Surgically rewrite the outdated XinaA15 path from the vendor SDK to support Dopamine
after-stage::
	install_name_tool -change @loader_path/.jbroot/Library/Frameworks/AltList.framework/AltList /var/jb/Library/Frameworks/AltList.framework/AltList $(THEOS_STAGING_DIR)/Library/PreferenceBundles/AntiDarkSwordPrefs.bundle/AntiDarkSwordPrefs
