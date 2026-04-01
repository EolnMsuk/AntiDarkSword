TARGET := iphone:clang:14.5:16.5
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = AntiDarkSwordPrefs
AntiDarkSwordPrefs_FILES = RootListController.m
AntiDarkSwordPrefs_FRAMEWORKS = UIKit
AntiDarkSwordPrefs_PRIVATE_FRAMEWORKS = Preferences
AntiDarkSwordPrefs_INSTALL_PATH = /Library/PreferenceBundles
# Enforce minimum version and classic linker here as well
AntiDarkSwordPrefs_CFLAGS = -fobjc-arc -miphoneos-version-min=14.5
AntiDarkSwordPrefs_LDFLAGS = -Wl,-ld_classic

include $(THEOS_MAKE_PATH)/bundle.mk
