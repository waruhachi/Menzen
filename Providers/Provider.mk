# What every provider's Makefile shares. Set TWEAK_NAME first, then add any
# frameworks or libraries of its own, then include this. The apps it hooks
# are in its Apps.mk, which the root Makefile reads too.

_MZ_PROVIDERS_DIR := $(dir $(lastword $(MAKEFILE_LIST)))

include Apps.mk

ifeq ($(strip $(MENZEN_BUNDLES)),)
$(error $(TWEAK_NAME): Apps.mk has no MENZEN_BUNDLES)
endif

MENZEN_VERSION := $(shell sed -n 's/^Version: *//p' $(_MZ_PROVIDERS_DIR)../layout/DEBIAN/control)
ifeq ($(MENZEN_VERSION),)
$(error $(TWEAK_NAME): no version in layout/DEBIAN/control)
endif

# The filter plist, made from Apps.mk. Theos looks for it as the makefile is
# read, so it's written now, and only when it changes.
_MZ_FILTER := $(TWEAK_NAME).plist
_MZ_FILTER_LINES := \
	'<?xml version="1.0" encoding="UTF-8"?>' \
	'<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' \
	'<plist version="1.0">' \
	'<dict>' \
	'	<key>Filter</key>' \
	'	<dict>' \
	'		<key>Bundles</key>' \
	'		<array>' \
	$(foreach bundle,$(MENZEN_BUNDLES),'			<string>$(bundle)</string>') \
	'		</array>' \
	'	</dict>' \
	'</dict>' \
	'</plist>'
_MZ_FILTER_ERROR := $(shell printf '%s\n' $(_MZ_FILTER_LINES) > "$(_MZ_FILTER).$$$$" && { cmp -s "$(_MZ_FILTER).$$$$" "$(_MZ_FILTER)" && rm "$(_MZ_FILTER).$$$$" || mv "$(_MZ_FILTER).$$$$" "$(_MZ_FILTER)"; } || echo failed)
ifneq ($(_MZ_FILTER_ERROR),)
$(error $(TWEAK_NAME): couldn't write $(_MZ_FILTER))
endif

# Absolute paths: Theos puts each file's objects under the arch's folder by
# its path, and "../../" would climb out of it, so arm64 and arm64e would
# share (and delete) one preprocessed file.
_MZ_SHARED_DIR := $(abspath $(_MZ_PROVIDERS_DIR)../Shared/MZProvider)
$(TWEAK_NAME)_FILES += $(wildcard $(TWEAK_NAME).x $(TWEAK_NAME).xm) $(wildcard $(_MZ_SHARED_DIR)/*.x $(_MZ_SHARED_DIR)/*.m)
$(TWEAK_NAME)_FRAMEWORKS += Foundation MediaPlayer UIKit
$(TWEAK_NAME)_CFLAGS += -fobjc-arc -DMZ_VERSION='"$(MENZEN_VERSION)"'

include $(THEOS)/makefiles/common.mk
include $(THEOS_MAKE_PATH)/tweak.mk
