#import <Foundation/Foundation.h>

// The pane and menzend both run as mobile, so they share one plist.

#define MZSettingsDomain @"moe.waru.menzen"
#define MZSettingsChangedNotification "moe.waru.menzen.settings"

// BOOL, default YES.
#define MZSettingEnabled @"enabled"
// BOOL per source, "source.<bundle identifier>", default YES.
#define MZSettingSourcePrefix @"source."
// BOOL, default NO: any app not in MZProviders().
#define MZSettingOtherApps @"otherApps"
// BOOL per game, "game.<bundle identifier>", default YES: the game on screen
// shows as "Playing <game>", over whatever's playing.
#define MZSettingGamePrefix @"game."
// The card's parts are in MZCard.h. These switches came before them and are
// only read for parts that haven't been set yet.
#define MZSettingShowArtist @"showArtist"
#define MZSettingShowCover @"showCover"
#define MZSettingShowProgress @"showProgress"
#define MZSettingShowArtistPicture @"showArtistPicture"
// BOOL, default YES.
#define MZSettingLinks @"links"
#define MZSettingHeading @"heading"
#define MZSettingHeadingText @"headingText"
#define MZSettingMemberList @"memberList"
// Seconds to keep a paused activity before clearing it; 0 clears at once,
// -1 keeps it until playback stops. Default 10.
#define MZSettingPauseGrace @"pauseGrace"
// BOOL, default NO: only the app's (or game's) name and icon, with no
// titles, pictures, links or time.
#define MZSettingPrivacy @"privacy"

static inline id MZSettingValue(NSString *key) {
	return CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)key, (__bridge CFStringRef)MZSettingsDomain));
}

static inline BOOL MZSettingBool(NSString *key, BOOL fallback) {
	id value = MZSettingValue(key);
	return [value respondsToSelector:@selector(boolValue)] ? [value boolValue] : fallback;
}

static inline NSString *MZSettingString(NSString *key, NSString *fallback) {
	id value = MZSettingValue(key);
	return [value isKindOfClass:NSString.class] ? value : fallback;
}

static inline double MZSettingDouble(NSString *key, double fallback) {
	id value = MZSettingValue(key);
	return [value respondsToSelector:@selector(doubleValue)] ? [value doubleValue] : fallback;
}
