#import <Preferences/PSSpecifier.h>

#import "../../Shared/MenzenSettings.h"
#import "MenzenListController.h"

// As root, PSListController would read and write root's own settings.
static BOOL MenzenSpecifierIsMenzenSetting(PSSpecifier *specifier) {
	return geteuid() == 0 && [[specifier propertyForKey:@"defaults"] isEqualToString:MenzenSettingsDomain];
}

@implementation MenzenListController

- (id)readPreferenceValue:(PSSpecifier *)specifier {
	if (!MenzenSpecifierIsMenzenSetting(specifier)) return [super readPreferenceValue:specifier];
	MenzenSettingsSynchronize();
	return MenzenSettingValue([specifier propertyForKey:@"key"]) ?: [specifier propertyForKey:@"default"];
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
	if (!MenzenSpecifierIsMenzenSetting(specifier)) {
		[super setPreferenceValue:value specifier:specifier];
		return;
	}

	MenzenWriteSetting([specifier propertyForKey:@"key"], value);
	NSString *notification = [specifier propertyForKey:@"PostNotification"];
	if (notification.length) CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge CFStringRef)notification, NULL, NULL, YES);
}

@end
