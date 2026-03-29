# Import common Theos configuration directives
include $(THEOS)/makefiles/common.mk

# Define the preference bundle identifier
BUNDLE_NAME = antidarkswordprefs

# Specify source files and compilation flags for the preference bundle
antidarkswordprefs_FILES = RootListController.m
antidarkswordprefs_FRAMEWORKS = UIKit
antidarkswordprefs_PRIVATE_FRAMEWORKS = Preferences
antidarkswordprefs_INSTALL_PATH = /Library/PreferenceBundles
antidarkswordprefs_CFLAGS = -fobjc-arc

# Include the standard bundle compilation rules
include $(THEOS_MAKE_PATH)/bundle.mk
