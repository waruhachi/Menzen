#import <Foundation/Foundation.h>

#import "MenzenSettings.h"

NS_ASSUME_NONNULL_BEGIN

// Custom activities: presets the user writes, one of which shows instead of
// anything detected while MenzenSettingCustom is on. Privacy Mode still applies.

// BOOL, default NO.
#define MenzenSettingCustom @"custom"
// Array of preset dictionaries (MenzenPreset*Key), in the order they were added.
// Kept by Reset Settings: they're the user's own writing.
#define MenzenSettingCustomPresets @"customPresets"
// String: the MenzenPresetIdentifierKey of the preset shown.
#define MenzenSettingCustomPreset @"customPreset"
// Date the shown preset was chosen, for its elapsed time.
#define MenzenSettingCustomStart @"customStart"

// String, a UUID.
#define MenzenPresetIdentifierKey @"id"
// String: playing, listening or watching.
#define MenzenPresetKindKey @"kind"
// Strings, any of them empty or missing.
#define MenzenPresetNameKey @"name"
#define MenzenPresetDetailsKey @"details"
#define MenzenPresetStateKey @"state"
#define MenzenPresetLargeImageKey @"largeImage"
#define MenzenPresetLargeTextKey @"largeText"
#define MenzenPresetSmallImageKey @"smallImage"
#define MenzenPresetSmallTextKey @"smallText"
// BOOL, default YES: the time since the preset was chosen.
#define MenzenPresetTimerKey @"timer"

static inline NSArray<NSDictionary *> *MenzenCustomPresets(void) {
	NSArray *presets = MenzenSettingValue(MenzenSettingCustomPresets);
	if (![presets isKindOfClass:NSArray.class]) return @[];
	return [presets filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(id preset, NSDictionary *bindings) {
		return [preset isKindOfClass:NSDictionary.class] && [preset[MenzenPresetIdentifierKey] isKindOfClass:NSString.class];
	}]];
}

static inline NSDictionary *_Nullable MenzenCustomPreset(NSString *_Nullable identifier) {
	if (!identifier) return nil;
	for (NSDictionary *preset in MenzenCustomPresets()) {
		if ([preset[MenzenPresetIdentifierKey] isEqualToString:identifier]) return preset;
	}
	return nil;
}

static inline NSString *_Nullable MenzenPresetString(NSDictionary *preset, NSString *key) {
	id value = preset[key];
	if (![value isKindOfClass:NSString.class]) return nil;
	NSString *text = [value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
	return text.length ? text : nil;
}

// A link that can go in the activity: https, and nothing in it that looks
// like a credential, since Discord shows the activity to everyone.
static inline BOOL MenzenCustomImageURLIsAllowed(NSString *_Nullable string) {
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
