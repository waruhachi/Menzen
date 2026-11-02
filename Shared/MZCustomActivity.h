#import <Foundation/Foundation.h>

#import "MZSettings.h"

NS_ASSUME_NONNULL_BEGIN

// Custom activities: presets the user writes, one of which shows instead of
// anything detected while MZSettingCustom is on. Privacy Mode still applies.

// BOOL, default NO.
#define MZSettingCustom @"custom"
// Array of preset dictionaries (MZPreset*Key), in the order they were added.
// Kept by Reset Settings: they're the user's own writing.
#define MZSettingCustomPresets @"customPresets"
// String: the MZPresetIdentifierKey of the preset shown.
#define MZSettingCustomPreset @"customPreset"
// Date the shown preset was chosen, for its elapsed time.
#define MZSettingCustomStart @"customStart"

// String, a UUID.
#define MZPresetIdentifierKey @"id"
// String: playing, listening or watching.
#define MZPresetKindKey @"kind"
// Strings, any of them empty or missing.
#define MZPresetNameKey @"name"
#define MZPresetDetailsKey @"details"
#define MZPresetStateKey @"state"
#define MZPresetLargeImageKey @"largeImage"
#define MZPresetLargeTextKey @"largeText"
#define MZPresetSmallImageKey @"smallImage"
#define MZPresetSmallTextKey @"smallText"
// BOOL, default YES: the time since the preset was chosen.
#define MZPresetTimerKey @"timer"

static inline NSArray<NSDictionary *> *MZCustomPresets(void) {
	NSArray *presets = MZSettingValue(MZSettingCustomPresets);
	if (![presets isKindOfClass:NSArray.class]) return @[];
	return [presets filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(id preset, NSDictionary *bindings) {
		return [preset isKindOfClass:NSDictionary.class] && [preset[MZPresetIdentifierKey] isKindOfClass:NSString.class];
	}]];
}

static inline NSDictionary *_Nullable MZCustomPreset(NSString *_Nullable identifier) {
	if (!identifier) return nil;
	for (NSDictionary *preset in MZCustomPresets()) {
		if ([preset[MZPresetIdentifierKey] isEqualToString:identifier]) return preset;
	}
	return nil;
}

static inline NSString *_Nullable MZPresetString(NSDictionary *preset, NSString *key) {
	id value = preset[key];
	if (![value isKindOfClass:NSString.class]) return nil;
	NSString *text = [value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
	return text.length ? text : nil;
}

// A link that can go in the activity: https, and nothing in it that looks
// like a credential, since Discord shows the activity to everyone.
static inline BOOL MZCustomImageURLIsAllowed(NSString *_Nullable string) {
	if (!string.length) return NO;
	NSURLComponents *components = [NSURLComponents componentsWithString:string];
	if (![components.scheme.lowercaseString isEqualToString:@"https"] || !components.host.length || components.user || components.password) return NO;
	for (NSURLQueryItem *item in components.queryItems) {
		NSString *name = item.name.lowercaseString;
		for (NSString *word in @[@"token", @"key", @"auth", @"session", @"secret", @"password", @"signature", @"sig"]) {
			if ([name containsString:word]) return NO;
		}
	}
	return YES;
}

NS_ASSUME_NONNULL_END
