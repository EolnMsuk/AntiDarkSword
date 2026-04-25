export ARCHS ?= arm64 arm64e
export TARGET ?= iphone:clang:latest:14.5

# Darwin ptrauth ABI — required for arm64e on Linux/WSL LLVM clang.
# Without this the linker emits "incompatible arm64e ABI compiler" and the
# resulting dylib crashes at bind time on ptrauth-capable devices (SafeMode).
export ADDITIONAL_CFLAGS += -Xclang -target-abi -Xclang darwinpcs

include $(THEOS)/makefiles/common.mk

SUBPROJECTS += AntiDarkSwordUI AntiDarkSwordDaemon antidarkswordprefs CorelliumDecoy
include $(THEOS_MAKE_PATH)/aggregate.mk

internal-stage::
	$(ECHO_NOTHING)mkdir -p $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences$(ECHO_END)
	$(ECHO_NOTHING)cp antidarkswordprefs/entry.plist $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences/AntiDarkSword.plist$(ECHO_END)