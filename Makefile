export ARCHS = arm64 arm64e
export TARGET = iphone:clang:16.5:14.0

# Per-app providers: hooks that add what MediaRemote lacks (cover URLs).
# Each one's Apps.mk names the apps it hooks, whose executables are restarted
# on install.
MENZEN_PROVIDERS := $(patsubst %/Apps.mk,%,$(sort $(wildcard Providers/*/Apps.mk)))
SUBPROJECTS += $(MENZEN_PROVIDERS)
$(foreach provider,$(MENZEN_PROVIDERS),$(eval include $(provider)/Apps.mk)$(eval INSTALL_TARGET_PROCESSES += $(MENZEN_PROCESSES)))
undefine MENZEN_BUNDLES
undefine MENZEN_PROCESSES

SUBPROJECTS += Daemon Preferences
INSTALL_TARGET_PROCESSES += SpringBoard Preferences

include $(THEOS)/makefiles/common.mk
include $(THEOS_MAKE_PATH)/aggregate.mk
