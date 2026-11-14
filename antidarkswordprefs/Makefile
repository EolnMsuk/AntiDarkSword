include ../config/target.mk
ADS_REFERENCE_READY := $(shell python3 "$(ADS_ROOT)/scripts/prepare_reference.py" "$(ADS_RELEASE_TARGET)" >/dev/null && echo yes)
ifneq ($(ADS_REFERENCE_READY),yes)
$(error AltList reference preparation failed)
endif
ADS_FRAMEWORK_DIR := $(ADS_ROOT)/.build/$(ADS_RELEASE_TARGET)/references

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = AntiDarkSwordPrefs
AntiDarkSwordPrefs_RESOURCE_DIRS = $(ADS_ROOT)/.build/$(ADS_RELEASE_TARGET)/preferences-resources
AntiDarkSwordPrefs_FILES = RootListController.m ADSUpdateChecker.m ADSDonationController.m ADSProcessRunner.m ADSAudio.m ADSCreditsMenu.m ADSPyEater.m ADSJailTris.m
AntiDarkSwordPrefs_FRAMEWORKS = Foundation CoreFoundation UIKit MobileCoreServices SpriteKit AVFoundation CoreImage
AntiDarkSwordPrefs_PRIVATE_FRAMEWORKS = Preferences
AntiDarkSwordPrefs_EXTRA_FRAMEWORKS = AltList
AntiDarkSwordPrefs_INSTALL_PATH = /Library/PreferenceBundles

AntiDarkSwordPrefs_CFLAGS = -fobjc-arc -F$(ADS_FRAMEWORK_DIR)
AntiDarkSwordPrefs_LDFLAGS = -F$(ADS_FRAMEWORK_DIR)
ifeq ($(THEOS_PACKAGE_SCHEME),roothide)
AntiDarkSwordPrefs_LIBRARIES += roothide
else ifeq ($(THEOS_PACKAGE_SCHEME),rootless)
AntiDarkSwordPrefs_LDFLAGS += -Wl,-rpath,/var/jb/Library/Frameworks
else
AntiDarkSwordPrefs_LDFLAGS += -Wl,-rpath,/Library/Frameworks
endif

include $(THEOS_MAKE_PATH)/bundle.mk
