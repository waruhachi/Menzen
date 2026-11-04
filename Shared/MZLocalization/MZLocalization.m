#import <roothide.h>

#import "MZLocalization.h"

static NSBundle *MZLocalizationBundle(void) {
	static NSBundle *bundle;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		bundle = [NSBundle bundleWithPath:jbroot(@"/Library/Tweak Support/Menzen/Localization")];
	});
	return bundle;
}

NSString *MZLocalizedString(NSString *key, NSString *fallback) {
	NSString *localized = [MZLocalizationBundle() localizedStringForKey:key value:nil table:nil];
	return localized.length && ![localized isEqualToString:key] ? localized : fallback;
}
