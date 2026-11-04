BUNDLE_NAME = MenzenPreferences

MENZEN_VERSION := $(shell sed -n 's/^Version: *//p' ../layout/DEBIAN/control)

$(BUNDLE_NAME)_FILES = $(wildcard Controllers/*.m) $(wildcard Helpers/*.m) $(wildcard Views/*.m) $(wildcard ../Shared/MZLocalization/*.m)
$(BUNDLE_NAME)_CFLAGS = -fobjc-arc -DMZ_VERSION='"$(MENZEN_VERSION)"'
$(BUNDLE_NAME)_FRAMEWORKS = UIKit AuthenticationServices CoreImage
$(BUNDLE_NAME)_PRIVATE_FRAMEWORKS = Preferences
$(BUNDLE_NAME)_INSTALL_PATH = /Library/PreferenceBundles

include $(THEOS)/makefiles/common.mk
include $(THEOS_MAKE_PATH)/bundle.mk
