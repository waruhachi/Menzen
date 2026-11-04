#import "../../Shared/MenzenSettings.h"
#import "MenzenPrivacyModule.h"

static void MenzenSettingsChanged(CFNotificationCenterRef center, void *observer, CFNotificationName name, const void *object, CFDictionaryRef userInfo) {
	MenzenPrivacyModule *module = (__bridge MenzenPrivacyModule *)observer;
	dispatch_async(dispatch_get_main_queue(), ^{
		[module refreshState];
	});
}

// The mark from Menzen's icon. Off, it's a template so Control Center tints it
// like its own glyphs; on, it keeps its colors: black with a green status dot.
static UIImage *MenzenGlyph(NSString *name, UIImageRenderingMode mode) {
	NSBundle *bundle = [NSBundle bundleForClass:MenzenPrivacyModule.class];
	UIImage *glyph = [UIImage imageNamed:name inBundle:bundle compatibleWithTraitCollection:nil];
	return [glyph imageWithRenderingMode:mode];
}

@implementation MenzenPrivacyModule

- (instancetype)init {
	if ((self = [super init])) {
		CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge void *)self, MenzenSettingsChanged, CFSTR(MenzenSettingsChangedNotification), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
	}

	return self;
}

- (void)dealloc {
	CFNotificationCenterRemoveObserver(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge void *)self, CFSTR(MenzenSettingsChangedNotification), NULL);
}

- (UIImage *)iconGlyph {
	return MenzenGlyph(@"Glyph", UIImageRenderingModeAlwaysTemplate);
}

- (UIImage *)selectedIconGlyph {
	return MenzenGlyph(@"GlyphSelected", UIImageRenderingModeAlwaysOriginal);
}

// Used if Control Center tints the selected glyph anyway.
- (UIColor *)selectedColor {
	return UIColor.blackColor;
}

- (BOOL)isSelected {
	// Settings writes from another process.
	CFPreferencesAppSynchronize((__bridge CFStringRef)MenzenSettingsDomain);
	return MenzenSettingBool(MenzenSettingPrivacy, NO);
}

- (void)setSelected:(BOOL)selected {
	CFPreferencesSetAppValue((__bridge CFStringRef)MenzenSettingPrivacy, (__bridge CFPropertyListRef) @(selected), (__bridge CFStringRef)MenzenSettingsDomain);
	CFPreferencesAppSynchronize((__bridge CFStringRef)MenzenSettingsDomain);
	CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFSTR(MenzenSettingsChangedNotification), NULL, NULL, true);
	[super refreshState];
}

@end
