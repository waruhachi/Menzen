#import "../../Shared/MenzenLocalization/MenzenLocalization.h"
#import "MenzenLocalizeSpecifiers.h"

static NSString *MenzenLocalizedProperty(PSSpecifier *specifier, NSString *property) {
	NSString *text = [specifier propertyForKey:property];
	NSString *key = [specifier propertyForKey:[property stringByAppendingString:@"Key"]];
	if (![text isKindOfClass:NSString.class] || ![key isKindOfClass:NSString.class]) return nil;
	return MenzenLocalizedString(key, text);
}

void MenzenLocalizeSpecifiers(NSArray<PSSpecifier *> *specifiers) {
	for (PSSpecifier *specifier in specifiers) {
		NSString *label = MenzenLocalizedProperty(specifier, @"label");
		if (label) {
			specifier.name = label;
			[specifier setProperty:label forKey:@"label"];
		}

		NSString *footer = MenzenLocalizedProperty(specifier, @"footerText");
		if (footer) [specifier setProperty:footer forKey:@"footerText"];

		// The titles by value, as loaded from validTitles.
		NSArray *titles = [specifier propertyForKey:@"validTitles"];
		NSArray *keys = [specifier propertyForKey:@"validTitlesKeys"];
		if ([titles isKindOfClass:NSArray.class] && [keys isKindOfClass:NSArray.class] && titles.count == keys.count && specifier.titleDictionary) {
			NSMutableDictionary *localized = [NSMutableDictionary dictionary];
			[specifier.titleDictionary enumerateKeysAndObjectsUsingBlock:^(id value, NSString *title, BOOL *stop) {
				NSUInteger index = [titles indexOfObject:title];
				localized[value] = index == NSNotFound ? title : MenzenLocalizedString(keys[index], title);
			}];
			specifier.titleDictionary = localized;
		}
	}
}
