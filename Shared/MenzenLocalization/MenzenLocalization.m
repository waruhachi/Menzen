#import <roothide.h>

#import "MenzenLocalization.h"

static NSBundle *MenzenLocalizationBundle(void) {
	static NSBundle *bundle;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		bundle = [NSBundle bundleWithPath:jbroot(@"/Library/Tweak Support/Menzen/Localization")];
	});
	return bundle;
}

NSString *MenzenLocalizedString(NSString *key, NSString *fallback) {
	NSString *localized = [MenzenLocalizationBundle() localizedStringForKey:key value:nil table:nil];
	return localized.length && ![localized isEqualToString:key] ? localized : fallback;
}
