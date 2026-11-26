#import <Foundation/Foundation.h>
#import <unistd.h>

// The pane and menzend share mobile's plist. Some apps that host the pane
// run as root (R3v4mp's own app), so the pane asks cfprefsd for mobile's
// settings by name.

#define MenzenSettingsDomain @"moe.waru.menzen"
#define MenzenSettingsChangedNotification "moe.waru.menzen.settings"

#define MenzenSettingEnabled @"enabled"
#define MenzenSettingSourcePrefix @"source."
#define MenzenSettingOtherApps @"otherApps"
#define MenzenSettingGamePrefix @"game."
// Only read for card parts that haven't been set yet (MenzenCard.h).
#define MenzenSettingShowArtist @"showArtist"
#define MenzenSettingShowCover @"showCover"
#define MenzenSettingShowProgress @"showProgress"
#define MenzenSettingShowArtistPicture @"showArtistPicture"
#define MenzenSettingLinks @"links"
#define MenzenSettingOpenButton @"openButton"
#define MenzenSettingHeading @"heading"
#define MenzenSettingHeadingText @"headingText"
#define MenzenSettingMemberList @"memberList"
// 0 clears at once, -1 keeps it until something else takes over.
#define MenzenSettingPauseGrace @"pauseGrace"
#define MenzenSettingPriority @"priority"
#define MenzenSettingPrivacy @"privacy"
#define MenzenSettingPrivatePrefix @"private."

static inline CFStringRef MenzenSettingsUser(void) {
	return geteuid() == 0 ? CFSTR("mobile") : kCFPreferencesCurrentUser;
}

static inline void MenzenSettingsSynchronize(void) {
	CFPreferencesSynchronize((__bridge CFStringRef)MenzenSettingsDomain, MenzenSettingsUser(), kCFPreferencesAnyHost);
}

static inline id MenzenSettingValue(NSString *key) {
	return CFBridgingRelease(CFPreferencesCopyValue((__bridge CFStringRef)key, (__bridge CFStringRef)MenzenSettingsDomain, MenzenSettingsUser(), kCFPreferencesAnyHost));
}

static inline void MenzenWriteSetting(NSString *key, id value) {
	CFPreferencesSetValue((__bridge CFStringRef)key, (__bridge CFPropertyListRef)value, (__bridge CFStringRef)MenzenSettingsDomain, MenzenSettingsUser(), kCFPreferencesAnyHost);
	MenzenSettingsSynchronize();
}

static inline void MenzenPostDarwinNotification(CFStringRef name) {
	CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), name, NULL, NULL, true);
}

static inline BOOL MenzenSettingBool(NSString *key, BOOL fallback) {
	id value = MenzenSettingValue(key);
	return [value respondsToSelector:@selector(boolValue)] ? [value boolValue] : fallback;
}

static inline NSString *MenzenSettingString(NSString *key, NSString *fallback) {
	id value = MenzenSettingValue(key);
	return [value isKindOfClass:NSString.class] ? value : fallback;
}

static inline double MenzenSettingDouble(NSString *key, double fallback) {
	id value = MenzenSettingValue(key);
	return [value respondsToSelector:@selector(doubleValue)] ? [value doubleValue] : fallback;
}

static inline BOOL MenzenAppIsPrivate(NSString *bundleIdentifier) {
	if (MenzenSettingBool(MenzenSettingPrivacy, NO)) return YES;
	return bundleIdentifier.length && MenzenSettingBool([MenzenSettingPrivatePrefix stringByAppendingString:bundleIdentifier], NO);
}

#define MenzenSourceCustom @"custom"
#define MenzenSourceConnected @"connected"
#define MenzenSourceGames @"games"
#define MenzenSourceMedia @"media"

static inline NSArray<NSString *> *MenzenPriority(void) {
	NSArray<NSString *> *defaults = @[MenzenSourceCustom, MenzenSourceConnected, MenzenSourceGames, MenzenSourceMedia];
	NSMutableArray<NSString *> *order = [NSMutableArray array];
	id value = MenzenSettingValue(MenzenSettingPriority);
	for (id source in [value isKindOfClass:NSArray.class] ? value : nil) {
		if ([defaults containsObject:source] && ![order containsObject:source]) [order addObject:source];
	}

	for (NSString *source in defaults) {
		if (![order containsObject:source]) [order addObject:source];
	}

	return order;
}
