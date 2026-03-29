# Define the processes that should be terminated upon tweak compilation and installation
INSTALL_TARGET_PROCESSES = SpringBoard MobileSafari MobileSMS MobileMail

# Import common Theos configuration directives
include $(THEOS)/makefiles/common.mk

# Define the primary tweak module identifier
TWEAK_NAME = AntiDarkSword

# Specify source files and compilation flags for the main tweak
AntiDarkSword_FILES = Tweak.x
AntiDarkSword_CFLAGS = -fobjc-arc
AntiDarkSword_FRAMEWORKS = Foundation WebKit UIKit CoreFoundation

# Include the standard tweak compilation rules
include $(THEOS_MAKE_PATH)/tweak.mk

# Instruct Theos to also compile the preference bundle directory
SUBPROJECTS += antidarkswordprefs
include $(THEOS_MAKE_PATH)/aggregate.mk
