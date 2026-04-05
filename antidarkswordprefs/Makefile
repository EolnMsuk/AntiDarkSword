ARCHS = arm64 arm64e
TARGET := iphone:clang:16.5:14.5
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = AntiDarkSwordPrefs
AntiDarkSwordPrefs_FILES = RootListController.m
AntiDarkSwordPrefs_FRAMEWORKS = UIKit
AntiDarkSwordPrefs_PRIVATE_FRAMEWORKS = Preferences
AntiDarkSwordPrefs_EXTRA_FRAMEWORKS = AltList
AntiDarkSwordPrefs_INSTALL_PATH = /Library/PreferenceBundles

# Explicitly tell the compiler and linker to search the vendor folder
AntiDarkSwordPrefs_CFLAGS = -fobjc-arc -F../vendor
AntiDarkSwordPrefs_LDFLAGS = -F../vendor

include $(THEOS_MAKE_PATH)/bundle.mk
