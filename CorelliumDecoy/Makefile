include $(THEOS)/makefiles/common.mk

TOOL_NAME = corelliumd
corelliumd_FILES = main.m
corelliumd_CFLAGS = -fobjc-arc
corelliumd_CODESIGN_FLAGS = -Sentitlements.plist
corelliumd_INSTALL_PATH = /usr/libexec

include $(THEOS_MAKE_PATH)/tool.mk

internal-stage::
	$(ECHO_NOTHING)mkdir -p $(THEOS_STAGING_DIR)/Library/LaunchDaemons$(ECHO_END)
	$(ECHO_NOTHING)sed -e "s|@EXEC_PATH@|$(THEOS_PACKAGE_INSTALL_PREFIX)/usr/libexec/corelliumd|g" c.eolnmsuk.corelliumdecoy.plist > $(THEOS_STAGING_DIR)/Library/LaunchDaemons/c.eolnmsuk.corelliumdecoy.plist$(ECHO_END)
