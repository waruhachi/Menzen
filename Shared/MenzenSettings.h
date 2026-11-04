#import <Foundation/Foundation.h>

// The pane and menzend both run as mobile, so they share one plist.

#define MenzenSettingsDomain @"moe.waru.menzen"
#define MenzenSettingsChangedNotification "moe.waru.menzen.settings"

// BOOL, default YES.
#define MenzenSettingEnabled @"enabled"
// BOOL per source, "source.<bundle identifier>", default YES.
#define MenzenSettingSourcePrefix @"source."
// BOOL, default NO: any app not in MenzenProviders().
#define MenzenSettingOtherApps @"otherApps"
// BOOL per game, "game.<bundle identifier>", default YES: the game on screen
// shows as "Playing <game>", over whatever's playing.
#define MenzenSettingGamePrefix @"game."
// The card's parts are in MenzenCard.h. These switches came before them and are
// only read for parts that haven't been set yet.
#define MenzenSettingShowArtist @"showArtist"
#define MenzenSettingShowCover @"showCover"
#define MenzenSettingShowProgress @"showProgress"
#define MenzenSettingShowArtistPicture @"showArtistPicture"
// BOOL, default YES.
#define MenzenSettingLinks @"links"
#define MenzenSettingHeading @"heading"
#define MenzenSettingHeadingText @"headingText"
#define MenzenSettingMemberList @"memberList"
// Seconds to keep a paused activity before clearing it; 0 clears at once,
// -1 keeps it until playback stops. Default 10.
#define MenzenSettingPauseGrace @"pauseGrace"
// BOOL, default NO: only the app's (or game's) name and icon, with no
// titles, pictures, links or time.
#define MenzenSettingPrivacy @"privacy"

static inline id MenzenSettingValue(NSString *key) {
	return CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)key, (__bridge CFStringRef)MenzenSettingsDomain));
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
