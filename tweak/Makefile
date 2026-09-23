THEOS_PACKAGE_DIR_NAME = debs
TARGET = iphone:clang:15.0:15.0
ARCHS = arm64 arm64e

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = FullScreenBackTweak
FullScreenBackTweak_FILES = FullScreenBackTweak.x
FullScreenBackTweak_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/tweak.mk
