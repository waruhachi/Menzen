# Shows Connected Apps' requests as notifications, which only SpringBoard can
# post with Menzen's icon and actions of their own.
TWEAK_NAME = MenzenSpringBoard

# Absolute, so arm64 and arm64e don't share the shared file's objects.
$(TWEAK_NAME)_FILES = MenzenSpringBoard.x $(abspath ../Shared/MenzenLocalization/MenzenLocalization.m)
$(TWEAK_NAME)_CFLAGS = -fobjc-arc
$(TWEAK_NAME)_FRAMEWORKS = Foundation
$(TWEAK_NAME)_PRIVATE_FRAMEWORKS = BulletinBoard

include $(THEOS)/makefiles/common.mk
include $(THEOS_MAKE_PATH)/tweak.mk
