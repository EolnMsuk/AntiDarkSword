TARGET := iphone:clang:16.5:14.5
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = AntiDarkSwordPrefs
AntiDarkSwordPrefs_FILES = RootListController.m
AntiDarkSwordPrefs_FRAMEWORKS = UIKit
AntiDarkSwordPrefs_PRIVATE_FRAMEWORKS = Preferences
AntiDarkSwordPrefs_INSTALL_PATH = /Library/PreferenceBundles
AntiDarkSwordPrefs_CFLAGS = -fobjc-arc
AntiDarkSwordPrefs_LDFLAGS = -Wl,-ld_classic

include $(THEOS_MAKE_PATH)/bundle.mk
