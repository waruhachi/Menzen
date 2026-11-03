# The Social SDK is arm64 only. That's fine: it only ever loads into this
# daemon, never into arm64e system processes.
ARCHS = arm64

# The SDK ships in the package from layout/ (Discord allows redistributing
# it); its headers are only for building, so they stay here.
DISCORD_SDK_DIR = Library/Tweak Support/Menzen/DiscordSDK

TOOL_NAME = menzend

menzend_FILES = main.m $(wildcard MZApelin/*.m) $(wildcard MZDiscord/*.m MZDiscord/*.mm) $(wildcard MZPresence/*.m) $(wildcard MZNowPlaying/*.m) $(wildcard MZForegroundApps/*.m) $(wildcard MZApps/*.m) $(wildcard MZServiceListener/*.m)
MENZEN_VERSION := $(shell sed -n 's/^Version: *//p' ../layout/DEBIAN/control)

menzend_CFLAGS = -fobjc-arc -IDiscordSDK/Headers -DMZ_VERSION='"$(MENZEN_VERSION)"'
menzend_CCFLAGS = -std=gnu++17
menzend_LDFLAGS = "-F../layout/$(DISCORD_SDK_DIR)" -framework discord_partner_sdk
# Installed at <jbroot>/usr/libexec, the SDK at <jbroot>/$(DISCORD_SDK_DIR),
# whatever kind of jailbreak it is.
menzend_LDFLAGS += -Xlinker -rpath -Xlinker "@executable_path/../../$(DISCORD_SDK_DIR)"
menzend_FRAMEWORKS = Foundation Security MobileCoreServices
menzend_CODESIGN_FLAGS = -Sentitlements.plist
menzend_INSTALL_PATH = /usr/libexec

include $(THEOS)/makefiles/common.mk
include $(THEOS_MAKE_PATH)/tool.mk

# The launchd plist is written by postinst, which knows the jailbreak's root.
