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
# This dynamically finds the embedded AltList string (whether it's @rpath, 
# an absolute path, or a jbroot path) and patches it to the universal 
# @loader_path relative string. This guarantees dyld can resolve it on 
# both Rootful and Rootless setups.
internal-stage::
	$(ECHO_NOTHING) \
	BIN=$$(find $(THEOS_STAGING_DIR) -name "AntiDarkSwordPrefs" -type f | head -n 1); \
	if [ -n "$$BIN" ]; then \
		OLD_PATH=$$(otool -L "$$BIN" | grep "AltList\.framework" | awk '{print $$1}' | head -n 1); \
		if [ -n "$$OLD_PATH" ]; then \
			install_name_tool -change "$$OLD_PATH" "@loader_path/../../Frameworks/AltList.framework/AltList" "$$BIN" || true; \
		fi; \
	fi \
	$(ECHO_END)