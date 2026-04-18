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

# Fix AltList install name and RE-SIGN the binary
# Modifying a binary with install_name_tool breaks its code signature.
# We must run `ldid -S` afterward to prevent a CODESIGNING SIGKILL on Rootless.
after-stage::
	$(ECHO_NOTHING) \
	BIN=$$(find $(THEOS_STAGING_DIR) -name "AntiDarkSwordPrefs" -type f | head -n 1); \
	if [ -n "$$BIN" ]; then \
		OLD_PATH=$$(otool -L "$$BIN" | grep "AltList\.framework" | awk '{print $$1}' | head -n 1); \
		if [ -n "$$OLD_PATH" ]; then \
			install_name_tool -change "$$OLD_PATH" "@loader_path/../../Frameworks/AltList.framework/AltList" "$$BIN" || true; \
		fi; \
		ldid -S "$$BIN"; \
	fi \
	$(ECHO_END)
