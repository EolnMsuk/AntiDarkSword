# Included before Theos common.mk by every entry point.
ADS_ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))/..)
ADS_RELEASE_TARGET ?= $(if $(filter rootless roothide,$(THEOS_PACKAGE_SCHEME)),$(THEOS_PACKAGE_SCHEME),rootful)
export ADS_RELEASE_TARGET
ADS_TARGET_FIELDS := $(shell python3 "$(ADS_ROOT)/scripts/target_config.py" "$(ADS_RELEASE_TARGET)" fields)
ifneq ($(words $(ADS_TARGET_FIELDS)),5)
$(error Invalid release target; use legacy, rootful, rootless, roothide, or trollfools)
endif
ADS_COMMA := ,
override TARGET := iphone:clang:$(word 1,$(ADS_TARGET_FIELDS)):$(word 2,$(ADS_TARGET_FIELDS))
override ARCHS := $(subst $(ADS_COMMA), ,$(word 3,$(ADS_TARGET_FIELDS)))
override THEOS_PACKAGE_SCHEME := $(filter-out -,$(word 4,$(ADS_TARGET_FIELDS)))
export TARGET ARCHS THEOS_PACKAGE_SCHEME
ADS_VERSION := $(shell python3 "$(ADS_ROOT)/scripts/version.py" print)
ifeq ($(ADS_VERSION),)
$(error Invalid control release version)
endif
override PACKAGE_VERSION := $(ADS_VERSION)
override PACKAGE_BUILDNAME :=
export PACKAGE_VERSION PACKAGE_BUILDNAME
ifeq ($(MAKELEVEL),0)
ADS_METADATA_READY := $(shell python3 "$(ADS_ROOT)/scripts/version.py" sync >/dev/null && echo yes)
else
ADS_METADATA_READY := $(shell python3 "$(ADS_ROOT)/scripts/version.py" check >/dev/null && echo yes)
endif
ifneq ($(ADS_METADATA_READY),yes)
$(error Release metadata preparation failed)
endif
# Isolate objects by target AND subproject, with a shared aggregate staging root.
override _THEOS_LOCAL_DATA_DIR := $(ADS_ROOT)/.build/$(ADS_RELEASE_TARGET)/theos/$(notdir $(CURDIR))
override THEOS_BUILD_DIR := $(ADS_ROOT)/.build/$(ADS_RELEASE_TARGET)/build
override THEOS_PACKAGE_DIR := $(ADS_ROOT)/.build/$(ADS_RELEASE_TARGET)/packages
export THEOS_STAGING_DIR := $(ADS_ROOT)/.build/$(ADS_RELEASE_TARGET)/staging
override THEOS_LAYOUT_DIR_NAME := $(ADS_ROOT)/.build/$(ADS_RELEASE_TARGET)/layout
override THEOS_LAYOUT_DIR := $(THEOS_LAYOUT_DIR_NAME)
export THEOS_LAYOUT_DIR_NAME THEOS_LAYOUT_DIR
# Pinned Theos deb.mk reads this path for control fields. The prepared copy
# derives Version unchanged from root control and adds only target dependencies.
override _THEOS_DEB_PACKAGE_CONTROL_PATH := $(THEOS_LAYOUT_DIR)/DEBIAN/control
ifneq ($(ADS_RELEASE_TARGET),trollfools)
ifeq ($(MAKELEVEL),0)
ADS_LAYOUT_READY := $(shell python3 "$(ADS_ROOT)/scripts/stage_lifecycle.py" "$(ADS_RELEASE_TARGET)" >/dev/null && echo yes)
ifneq ($(ADS_LAYOUT_READY),yes)
$(error Package lifecycle preparation failed)
endif
endif
endif
export _THEOS_PROJECT_MAKEFILE_NAME := Makefile
ifeq ($(THEOS_PACKAGE_SCHEME),roothide)
ifeq ($(wildcard $(THEOS)/vendor/mod/roothide/package/deb.mk),)
$(error Native Roothide Theos is required; see docs/building.md)
endif
ifeq ($(wildcard $(THEOS)/vendor/include/roothide/roothide.h),)
$(error Roothide headers are missing; initialize the pinned Theos submodules)
endif
ifeq ($(wildcard $(THEOS)/vendor/lib/iphone/roothide/libroothide.tbd),)
$(error Native Roothide libraries are missing)
endif
endif
