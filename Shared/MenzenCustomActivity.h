#import <Foundation/Foundation.h>

#import "MenzenSettings.h"

#define MenzenSettingCustom @"custom"
// Kept by Reset Settings: they're the user's own writing.
#define MenzenSettingCustomPresets @"customPresets"
#define MenzenSettingCustomPreset @"customPreset"
#define MenzenSettingCustomStart @"customStart"

#define MenzenPresetIdentifierKey @"id"
#define MenzenPresetKindKey @"kind"
#define MenzenPresetNameKey @"name"
#define MenzenPresetDetailsKey @"details"
#define MenzenPresetStateKey @"state"
#define MenzenPresetLargeImageKey @"largeImage"
#define MenzenPresetLargeTextKey @"largeText"
#define MenzenPresetSmallImageKey @"smallImage"
#define MenzenPresetSmallTextKey @"smallText"
#define MenzenPresetTimerKey @"timer"

static inline NSArray<NSDictionary *> *MenzenCustomPresets(void) {
	NSArray *presets = MenzenSettingValue(MenzenSettingCustomPresets);
	if (![presets isKindOfClass:NSArray.class]) return @[];
	return [presets filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(id preset, NSDictionary *bindings) {
		return [preset isKindOfClass:NSDictionary.class] && [preset[MenzenPresetIdentifierKey] isKindOfClass:NSString.class];
	}]];
}

static inline NSDictionary *MenzenCustomPreset(NSString *identifier) {
	if (!identifier) return nil;
	for (NSDictionary *preset in MenzenCustomPresets()) {
		if ([preset[MenzenPresetIdentifierKey] isEqualToString:identifier]) return preset;
	}
	return nil;
}

static inline NSString *MenzenPresetString(NSDictionary *preset, NSString *key) {
	id value = preset[key];
	if (![value isKindOfClass:NSString.class]) return nil;
	NSString *text = [value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
	return text.length ? text : nil;
}

// A link that can go in the activity: https, and nothing in it that looks
// like a credential, since Discord shows the activity to everyone.
static inline BOOL MenzenCustomURLIsAllowed(NSString *string) {
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

static inline NSString *MenzenPresetKind(NSDictionary *preset) {
	NSString *kind = MenzenPresetString(preset, MenzenPresetKindKey);
	return [@[@"listening", @"watching"] containsObject:kind] ? kind : @"playing";
}
