# The Social SDK is arm64 only. That's fine: it only ever loads into this
# daemon, never into arm64e system processes.
ARCHS = arm64

# The SDK ships in the package from layout/ (Discord allows redistributing
# it); its headers are only for building, so they stay here.
DISCORD_SDK_DIR = Library/Tweak Support/Menzen/DiscordSDK

TOOL_NAME = menzend

$(TOOL_NAME)_FILES = main.m $(wildcard MenzenApelin/*.m) $(wildcard MenzenDiscord/*.m MenzenDiscord/*.mm) $(wildcard MenzenPresence/*.m) $(wildcard MenzenNowPlaying/*.m) $(wildcard MenzenForegroundApps/*.m) $(wildcard MenzenApps/*.m) $(wildcard MenzenServiceListener/*.m) $(wildcard MenzenConnectedApps/*.m) $(wildcard ../Shared/MenzenLocalization/*.m)
MENZEN_VERSION := $(shell sed -n 's/^Version: *//p' ../layout/DEBIAN/control)

$(TOOL_NAME)_CFLAGS = -fobjc-arc -IDiscordSDK/Headers -DMENZEN_VERSION='"$(MENZEN_VERSION)"'
$(TOOL_NAME)_CCFLAGS = -std=gnu++17
$(TOOL_NAME)_LDFLAGS = "-F../layout/$(DISCORD_SDK_DIR)" -framework discord_partner_sdk
# Installed at <jbroot>/usr/libexec, the SDK at <jbroot>/$(DISCORD_SDK_DIR),
# whatever kind of jailbreak it is.
$(TOOL_NAME)_LDFLAGS += -Xlinker -rpath -Xlinker "@executable_path/../../$(DISCORD_SDK_DIR)"
$(TOOL_NAME)_FRAMEWORKS = Foundation Security MobileCoreServices
$(TOOL_NAME)_CODESIGN_FLAGS = -Sentitlements.plist
$(TOOL_NAME)_INSTALL_PATH = /usr/libexec

include $(THEOS)/makefiles/common.mk
include $(THEOS_MAKE_PATH)/tool.mk

# The launchd plist is written by postinst, which knows the jailbreak's root.
