export ARCHS = arm64 arm64e
export TARGET = iphone:clang:16.5:14.0

# The MediaRemote probe logs every now playing change in detail, so it's
# only built on request (make package MENZEN_PROBE=1), and never into a
# release package, which logs nothing.
ifeq ($(MENZEN_PROBE),1)
ifeq ($(FINALPACKAGE),1)
$(error MENZEN_PROBE is for debug builds only)
endif
SUBPROJECTS += Tweak
INSTALL_TARGET_PROCESSES += SpringBoard
endif

# Per-app providers: hooks that add what MediaRemote lacks (cover URLs).
# Each one's Apps.mk names the apps it hooks, whose executables are restarted
# on install.
MENZEN_PROVIDERS := $(patsubst %/Apps.mk,%,$(sort $(wildcard Providers/*/Apps.mk)))
SUBPROJECTS += $(MENZEN_PROVIDERS)
$(foreach provider,$(MENZEN_PROVIDERS),$(eval include $(provider)/Apps.mk)$(eval INSTALL_TARGET_PROCESSES += $(MENZEN_PROCESSES)))
undefine MENZEN_BUNDLES
undefine MENZEN_PROCESSES

SUBPROJECTS += Daemon Preferences
INSTALL_TARGET_PROCESSES += Preferences

include $(THEOS)/makefiles/common.mk
include $(THEOS_MAKE_PATH)/aggregate.mk
