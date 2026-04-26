ARCHS ?= arm64 arm64e
TARGET ?= iphone:clang:16.5:13.0

# Force dual SHA1+SHA256 signing so Dopamine/RootHide trust cache (SHA1 lookup) accepts the dylibs.
# macOS CI uses codesign which produces both automatically; on-device ldid defaults to SHA256-only.
TARGET_CODESIGN_FLAGS = -S -Hsha1 -Hsha256

include $(THEOS)/makefiles/common.mk

SUBPROJECTS += AntiDarkSwordUI AntiDarkSwordDaemon antidarkswordprefs CorelliumDecoy
include $(THEOS_MAKE_PATH)/aggregate.mk

internal-stage::
	$(ECHO_NOTHING)mkdir -p $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences$(ECHO_END)
	$(ECHO_NOTHING)cp antidarkswordprefs/entry.plist $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences/AntiDarkSword.plist$(ECHO_END)
