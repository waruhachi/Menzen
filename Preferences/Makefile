BUNDLE_NAME = MenzenPreferences

MENZEN_VERSION := $(shell sed -n 's/^Version: *//p' ../layout/DEBIAN/control)

MenzenPreferences_FILES = $(wildcard Controllers/*.m) $(wildcard Helpers/*.m) $(wildcard Views/*.m)
MenzenPreferences_CFLAGS = -fobjc-arc -DMZ_VERSION='"$(MENZEN_VERSION)"'
MenzenPreferences_FRAMEWORKS = UIKit AuthenticationServices CoreImage
MenzenPreferences_PRIVATE_FRAMEWORKS = Preferences
MenzenPreferences_INSTALL_PATH = /Library/PreferenceBundles

include $(THEOS)/makefiles/common.mk
include $(THEOS_MAKE_PATH)/bundle.mk
