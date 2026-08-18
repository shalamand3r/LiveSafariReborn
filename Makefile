TARGET = iphone:clang:latest:15.0
ARCHS = arm64 arm64e

THEOS_PACKAGE_SCHEME = rootless

INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

MODULE_CACHE_DIR = $(THEOS_PROJECT_DIR)/.theos/modulecache
ADDITIONAL_CFLAGS += -fmodules-cache-path=$(MODULE_CACHE_DIR)

TWEAK_NAME = LiveSafariReborn
LiveSafariReborn_FILES = Tweak.xm
LiveSafariReborn_FRAMEWORKS = CoreLocation

include $(THEOS_MAKE_PATH)/tweak.mk

after-stage::
	chmod 0755 "$(THEOS_STAGING_DIR)/Library" "$(THEOS_STAGING_DIR)/Library/Application Support" "$(THEOS_STAGING_DIR)/Library/Application Support/LiveSafariReborn"
	chmod 0644 "$(THEOS_STAGING_DIR)/Library/Application Support/LiveSafariReborn/"*.png "$(THEOS_STAGING_DIR)/Library/MobileSubstrate/DynamicLibraries/$(TWEAK_NAME).plist"
