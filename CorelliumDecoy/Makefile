TARGET := iphone:clang:16.5:14.5
THEOS_PACKAGE_SCHEME = rootless
include $(THEOS)/makefiles/common.mk

TOOL_NAME = corelliumd
corelliumd_FILES = main.m
corelliumd_CFLAGS = -fobjc-arc
corelliumd_INSTALL_PATH = /usr/libexec

include $(THEOS_MAKE_PATH)/tool.mk

internal-stage::
	$(ECHO_NOTHING)mkdir -p $(THEOS_STAGING_DIR)/Library/LaunchDaemons$(ECHO_END)
	$(ECHO_NOTHING)cp c.eolnmsuk.corelliumdecoy.plist $(THEOS_STAGING_DIR)/Library/LaunchDaemons/$(ECHO_END)
