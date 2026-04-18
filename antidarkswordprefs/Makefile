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

# Add universal @rpath search directories directly into the linker flags
AntiDarkSwordPrefs_LDFLAGS = -F../vendor -rpath /var/jb/Library/Frameworks -rpath /Library/Frameworks

include $(THEOS_MAKE_PATH)/bundle.mk

# Patch the vendor framework's ID *before* compiling so the linker natively
# embeds the correct @rpath into the bundle without breaking code signatures.
before-all::
	@install_name_tool -id "@rpath/AltList.framework/AltList" ../vendor/AltList.framework/AltList 2>/dev/null || true
