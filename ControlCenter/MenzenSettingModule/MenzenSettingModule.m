#import <objc/runtime.h>

#import "../../Shared/MenzenSettings.h"
#import "MenzenSettingModule.h"
#import "MenzenToggleViewController.h"

@interface CCUIToggleModule (MenzenContentViewController)
- (UIViewController *)contentViewControllerForContext:(id)context;
@end

static void MenzenSettingsChanged(CFNotificationCenterRef center, void *observer, CFNotificationName name, const void *object, CFDictionaryRef userInfo) {
	MenzenSettingModule *module = (__bridge MenzenSettingModule *)observer;
	dispatch_async(dispatch_get_main_queue(), ^{
		[module refreshState];
	});
}

@implementation MenzenSettingModule

+ (NSString *)settingKey {
	[self doesNotRecognizeSelector:_cmd];
	return nil;
}

+ (BOOL)settingDefault {
	return NO;
}

- (instancetype)init {
	if ((self = [super init])) {
		CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge void *)self, MenzenSettingsChanged, CFSTR(MenzenSettingsChangedNotification), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
	}

	return self;
}

- (void)dealloc {
	CFNotificationCenterRemoveObserver(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge void *)self, CFSTR(MenzenSettingsChangedNotification), NULL);
}

// The glyphs are the mark from Menzen's icon with a badge. Off, it's a
// template so Control Center tints it like its own glyphs; on, it keeps its
// colors (see MenzenToggleViewController).
- (UIImage *)glyphNamed:(NSString *)name renderingMode:(UIImageRenderingMode)mode {
	NSBundle *bundle = [NSBundle bundleForClass:self.class];
	UIImage *glyph = [UIImage imageNamed:name inBundle:bundle compatibleWithTraitCollection:nil];
	return [glyph imageWithRenderingMode:mode];
}

- (UIImage *)iconGlyph {
	return [self glyphNamed:@"Glyph" renderingMode:UIImageRenderingModeAlwaysTemplate];
}

- (UIImage *)selectedIconGlyph {
	return [self glyphNamed:@"GlyphSelected" renderingMode:UIImageRenderingModeAlwaysOriginal];
}

- (UIViewController *)contentViewControllerForContext:(id)context {
	UIViewController *controller = [super contentViewControllerForContext:context];
	if ([controller isMemberOfClass:CCUIToggleViewController.class]) object_setClass(controller, MenzenToggleViewController.class);
	return controller;
}

// The tint where the glyph view can't keep the colors.
- (UIColor *)selectedColor {
	return UIColor.blackColor;
}

- (BOOL)isSelected {
	// Settings writes from another process.
	CFPreferencesAppSynchronize((__bridge CFStringRef)MenzenSettingsDomain);
	return MenzenSettingBool(self.class.settingKey, self.class.settingDefault);
}

- (void)setSelected:(BOOL)selected {
	CFPreferencesSetAppValue((__bridge CFStringRef)self.class.settingKey, (__bridge CFPropertyListRef) @(selected), (__bridge CFStringRef)MenzenSettingsDomain);
	CFPreferencesAppSynchronize((__bridge CFStringRef)MenzenSettingsDomain);
	CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFSTR(MenzenSettingsChangedNotification), NULL, NULL, true);
	[super refreshState];
}

@end
