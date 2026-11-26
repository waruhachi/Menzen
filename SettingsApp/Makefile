# Opens Connected Apps from SpringBoard's request notifications where
# Settings is SwiftUI (iOS 26), whose links don't reach tweak panes.
TWEAK_NAME = MenzenSettingsApp

$(TWEAK_NAME)_FILES = MenzenSettingsApp.x
$(TWEAK_NAME)_CFLAGS = -fobjc-arc
$(TWEAK_NAME)_FRAMEWORKS = UIKit
$(TWEAK_NAME)_PRIVATE_FRAMEWORKS = Preferences

include $(THEOS)/makefiles/common.mk
include $(THEOS_MAKE_PATH)/tweak.mk
