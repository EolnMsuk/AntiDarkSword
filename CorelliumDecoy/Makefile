TARGET ?= iphone:clang:16.5:14.5
include $(THEOS)/makefiles/common.mk

TOOL_NAME = corelliumd
corelliumd_FILES = main.m
corelliumd_CFLAGS = -fobjc-arc
corelliumd_INSTALL_PATH = /usr/libexec

include $(THEOS_MAKE_PATH)/tool.mk

internal-stage::
	$(ECHO_NOTHING)mkdir -p $(THEOS_STAGING_DIR)/Library/LaunchDaemons$(ECHO_END)
ifeq ($(THEOS_PACKAGE_SCHEME),rootless)
	$(ECHO_NOTHING)sed 's|/usr/libexec/corelliumd|/var/jb/usr/libexec/corelliumd|g' c.eolnmsuk.corelliumdecoy.plist > $(THEOS_STAGING_DIR)/Library/LaunchDaemons/c.eolnmsuk.corelliumdecoy.plist$(ECHO_END)
else
	$(ECHO_NOTHING)cp c.eolnmsuk.corelliumdecoy.plist $(THEOS_STAGING_DIR)/Library/LaunchDaemons/$(ECHO_END)
endif
