TARGET = iphone:clang:16.5:15.0
ARCHS = arm64 arm64e
INSTALL_TARGET_PROCESSES = Calculator

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = Calculator18

Calculator18_FILES = Tweak.x Tracker.m Display.m ClearKey.m Keypad.xm ModeKey.m NewNote.m Debug.xm
Calculator18_FRAMEWORKS = UIKit Foundation
Calculator18_CFLAGS = -fobjc-arc

ifeq ($(CALCULATOR18_DEBUG),1)
Calculator18_CFLAGS += -DC18_DEBUG=1
endif

include $(THEOS_MAKE_PATH)/tweak.mk
