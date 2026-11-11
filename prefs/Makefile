TARGET = iphone:clang:16.5:15.0
ARCHS = arm64 arm64e

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = Calculator18Prefs

# The tweak's version, from the control file
C18_VERSION := $(shell awk '/^Version:/ {print $$2}' ../control)

Calculator18Prefs_FILES = Calculator18RootListController.m ../Calculator18Prefs.m ../Calculator18Log.m
Calculator18Prefs_INSTALL_PATH = /Library/PreferenceBundles
Calculator18Prefs_FRAMEWORKS = UIKit
Calculator18Prefs_PRIVATE_FRAMEWORKS = Preferences
Calculator18Prefs_CFLAGS = -fobjc-arc -DC18_VERSION=\"$(C18_VERSION)\"

include $(THEOS_MAKE_PATH)/bundle.mk

internal-stage::
	$(ECHO_NOTHING)mkdir -p $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences$(ECHO_END)
	$(ECHO_NOTHING)cp entry.plist $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences/Calculator18Prefs.plist$(ECHO_END)
