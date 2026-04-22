ARCHS ?= arm64 arm64e
TARGET ?= iphone:clang:latest:14.5

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = AntiDarkSwordPrefs
AntiDarkSwordPrefs_FILES = RootListController.m ADSGames.m
AntiDarkSwordPrefs_FRAMEWORKS = UIKit
AntiDarkSwordPrefs_PRIVATE_FRAMEWORKS = Preferences
AntiDarkSwordPrefs_EXTRA_FRAMEWORKS = AltList
AntiDarkSwordPrefs_INSTALL_PATH = /Library/PreferenceBundles

AntiDarkSwordPrefs_CFLAGS = -fobjc-arc -F$(THEOS_PROJECT_DIR)/vendor
# Cleaned LDFLAGS: Standard Theos will handle /var/jb/ remapping during the rootless build scheme
AntiDarkSwordPrefs_LDFLAGS = -F$(THEOS_PROJECT_DIR)/vendor

include $(THEOS_MAKE_PATH)/bundle.mk