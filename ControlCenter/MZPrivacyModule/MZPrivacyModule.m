#import "../../Shared/MZSettings.h"
#import "MZPrivacyModule.h"

// Settings (or this toggle) changed Privacy Mode: show the new state.
static void MZSettingsChanged(CFNotificationCenterRef center, void *observer, CFNotificationName name, const void *object, CFDictionaryRef userInfo) {
	MZPrivacyModule *module = (__bridge MZPrivacyModule *)observer;
	dispatch_async(dispatch_get_main_queue(), ^{
		[module refreshState];
	});
}

// The mark from Menzen's icon. Off, it's a template so Control Center tints it
// like its own glyphs; on, it keeps its colors: black with a green status dot.
static UIImage *MZGlyph(NSString *name, UIImageRenderingMode mode) {
	NSBundle *bundle = [NSBundle bundleForClass:MZPrivacyModule.class];
	UIImage *glyph = [UIImage imageNamed:name inBundle:bundle compatibleWithTraitCollection:nil];
	return [glyph imageWithRenderingMode:mode];
}

@implementation MZPrivacyModule

- (instancetype)init {
	if ((self = [super init])) {
		CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge void *)self, MZSettingsChanged, CFSTR(MZSettingsChangedNotification), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
	}

	return self;
}

- (void)dealloc {
	CFNotificationCenterRemoveObserver(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge void *)self, CFSTR(MZSettingsChangedNotification), NULL);
}

- (UIImage *)iconGlyph {
	return MZGlyph(@"Glyph", UIImageRenderingModeAlwaysTemplate);
}

- (UIImage *)selectedIconGlyph {
	return MZGlyph(@"GlyphSelected", UIImageRenderingModeAlwaysOriginal);
}

// Used if Control Center tints the selected glyph anyway.
- (UIColor *)selectedColor {
	return UIColor.blackColor;
}

- (BOOL)isSelected {
	// Settings writes from another process.
	CFPreferencesAppSynchronize((__bridge CFStringRef)MZSettingsDomain);
	return MZSettingBool(MZSettingPrivacy, NO);
}

- (void)setSelected:(BOOL)selected {
	CFPreferencesSetAppValue((__bridge CFStringRef)MZSettingPrivacy, (__bridge CFPropertyListRef) @(selected), (__bridge CFStringRef)MZSettingsDomain);
	CFPreferencesAppSynchronize((__bridge CFStringRef)MZSettingsDomain);
	CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFSTR(MZSettingsChangedNotification), NULL, NULL, true);
	[super refreshState];
}

@end
