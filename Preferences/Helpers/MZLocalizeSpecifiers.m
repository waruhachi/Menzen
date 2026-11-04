#import "../../Shared/MZLocalization/MZLocalization.h"
#import "MZLocalizeSpecifiers.h"

static NSString *MZLocalizedProperty(PSSpecifier *specifier, NSString *property) {
	NSString *text = [specifier propertyForKey:property];
	NSString *key = [specifier propertyForKey:[property stringByAppendingString:@"Key"]];
	if (![text isKindOfClass:NSString.class] || ![key isKindOfClass:NSString.class]) return nil;
	return MZLocalizedString(key, text);
}

void MZLocalizeSpecifiers(NSArray<PSSpecifier *> *specifiers) {
	for (PSSpecifier *specifier in specifiers) {
		NSString *label = MZLocalizedProperty(specifier, @"label");
		if (label) {
			specifier.name = label;
			[specifier setProperty:label forKey:@"label"];
		}

		NSString *footer = MZLocalizedProperty(specifier, @"footerText");
		if (footer) [specifier setProperty:footer forKey:@"footerText"];

		// The titles by value, as loaded from validTitles.
		NSArray *titles = [specifier propertyForKey:@"validTitles"];
		NSArray *keys = [specifier propertyForKey:@"validTitlesKeys"];
		if ([titles isKindOfClass:NSArray.class] && [keys isKindOfClass:NSArray.class] && titles.count == keys.count && specifier.titleDictionary) {
			NSMutableDictionary *localized = [NSMutableDictionary dictionary];
			[specifier.titleDictionary enumerateKeysAndObjectsUsingBlock:^(id value, NSString *title, BOOL *stop) {
				NSUInteger index = [titles indexOfObject:title];
				localized[value] = index == NSNotFound ? title : MZLocalizedString(keys[index], title);
			}];
			specifier.titleDictionary = localized;
		}
	}
}
