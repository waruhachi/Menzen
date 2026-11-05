# One bundle per module, so each shows up in Control Center on its own.
BUNDLE_NAME = MenzenEnabled MenzenPrivacy

MENZEN_MODULE_FILES = $(wildcard MenzenSettingModule/*.m)

$(foreach bundle,$(BUNDLE_NAME),$(eval $(bundle)_BUNDLE_EXTENSION = bundle))
$(foreach bundle,$(BUNDLE_NAME),$(eval $(bundle)_FILES = $(MENZEN_MODULE_FILES) $(wildcard $(bundle)Module/*.m)))
$(foreach bundle,$(BUNDLE_NAME),$(eval $(bundle)_RESOURCE_DIRS = Resources/$(bundle)))
# Both bundles load into SpringBoard, so each gets the shared classes under
# its own names instead of defining them twice.
$(foreach bundle,$(BUNDLE_NAME),$(eval $(bundle)_CFLAGS = -fobjc-arc -DMenzenSettingModule=$(bundle)SettingModule -DMenzenToggleViewController=$(bundle)ToggleViewController -DMenzenGlyphImageView=$(bundle)GlyphImageView))
$(foreach bundle,$(BUNDLE_NAME),$(eval $(bundle)_FRAMEWORKS = UIKit))
$(foreach bundle,$(BUNDLE_NAME),$(eval $(bundle)_PRIVATE_FRAMEWORKS = ControlCenterUIKit))
$(foreach bundle,$(BUNDLE_NAME),$(eval $(bundle)_INSTALL_PATH = /Library/ControlCenter/Bundles))

include $(THEOS)/makefiles/common.mk
include $(THEOS_MAKE_PATH)/bundle.mk
