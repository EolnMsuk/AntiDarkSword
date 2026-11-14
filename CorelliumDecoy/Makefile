include ../config/target.mk
include $(THEOS)/makefiles/common.mk

TOOL_NAME = corelliumd
corelliumd_FILES        = main.m
corelliumd_CFLAGS       = -fobjc-arc
corelliumd_INSTALL_PATH = /usr/libexec
# Required for rootless: grants platform-application so jetsam/sandbox
# does not kill the process.  Also applied on rootful for consistency.
corelliumd_CODESIGN_FLAGS = -Sentitlements.plist
ifeq ($(THEOS_PACKAGE_SCHEME),roothide)
corelliumd_CODESIGN_FLAGS = -Sentitlements-roothide.plist
endif

include $(THEOS_MAKE_PATH)/tool.mk

internal-stage::
	$(ECHO_NOTHING)mkdir -p $(THEOS_STAGING_DIR)/Library/LaunchDaemons$(ECHO_END)
ifeq ($(ADS_RELEASE_TARGET),rootless)
	$(ECHO_NOTHING)sed 's|/usr/libexec/corelliumd|/var/jb/usr/libexec/corelliumd|g' c.eolnmsuk.corelliumdecoy.plist > $(THEOS_STAGING_DIR)/Library/LaunchDaemons/c.eolnmsuk.corelliumdecoy.plist$(ECHO_END)
else
	$(ECHO_NOTHING)cp c.eolnmsuk.corelliumdecoy.plist $(THEOS_STAGING_DIR)/Library/LaunchDaemons/$(ECHO_END)
endif
