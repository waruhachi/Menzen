#import "../../Shared/MenzenAppPrivacy.h"
#import "../../Shared/MenzenLocalization/MenzenLocalization.h"
#import "MenzenAppPrivacyModule.h"

@interface MenzenAppPrivacyViewController ()
- (void)refresh;
@end

static void MenzenAppPrivacySettingsChanged(CFNotificationCenterRef center, void *observer, CFNotificationName name, const void *object, CFDictionaryRef userInfo) {
	MenzenAppPrivacyViewController *controller = (__bridge MenzenAppPrivacyViewController *)observer;
	dispatch_async(dispatch_get_main_queue(), ^{
		[controller refresh];
	});
}

@implementation MenzenAppPrivacyViewController

- (instancetype)initWithNibName:(NSString *)nibName bundle:(NSBundle *)bundle {
	if ((self = [super initWithNibName:nibName bundle:bundle])) {
		NSBundle *resources = [NSBundle bundleForClass:self.class];
		self.glyphImage = [[UIImage imageNamed:@"Glyph" inBundle:resources compatibleWithTraitCollection:nil] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
		self.selectedGlyphImage = [[UIImage imageNamed:@"GlyphSelected" inBundle:resources compatibleWithTraitCollection:nil] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
		CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge void *)self, MenzenAppPrivacySettingsChanged, CFSTR(MenzenSettingsChangedNotification), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
		[self refresh];
	}

	return self;
}

- (void)dealloc {
	CFNotificationCenterRemoveObserver(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge void *)self, CFSTR(MenzenSettingsChangedNotification), NULL);
}

- (void)refresh {
	// Settings writes from another process.
	MenzenSettingsSynchronize();
	NSArray<NSString *> *choice = MenzenPrivacyModuleChoice();
	self.title = choice[1] ?: MenzenLocalizedString(@"root.privacy_mode", @"Privacy Mode");

	self.selected = MenzenSettingBool(MenzenPrivacyModuleKey(), NO);
	[self reloadActions];
}

- (void)reloadActions {
	[self removeAllActions];

	NSString *current = MenzenPrivacyModuleApp();
	UIImage *checkmark = [UIImage systemImageNamed:@"checkmark"];

	__weak typeof(self) weakSelf = self;
	for (NSArray<NSString *> *choice in MenzenInstalledProviderApps()) {
		NSString *value = choice[0];
		[self addActionWithTitle:choice[1] glyph:[value isEqualToString:current] ? checkmark : [UIImage new] handler:^BOOL {
			MenzenWriteSetting(MenzenSettingPrivacyModuleApp, value);
			MenzenPostDarwinNotification(CFSTR(MenzenSettingsChangedNotification));
			[weakSelf refresh];
			return YES;
		}];
	}
}

// A tap switches Privacy Mode for the chosen app; holding opens the list.
- (void)buttonTapped:(id)button forEvent:(UIEvent *)event {
	BOOL selected = !MenzenSettingBool(MenzenPrivacyModuleKey(), NO);
	MenzenWriteSetting(MenzenPrivacyModuleKey(), @(selected));
	MenzenPostDarwinNotification(CFSTR(MenzenSettingsChangedNotification));
	self.selected = selected;
}

- (BOOL)shouldBeginTransitionToExpandedContentModule {
	return YES;
}

@end

@implementation MenzenAppPrivacyModule {
	MenzenAppPrivacyViewController *_contentViewController;
}

- (UIViewController<CCUIContentModuleContentViewController> *)contentViewController {
	if (!_contentViewController) _contentViewController = [[MenzenAppPrivacyViewController alloc] initWithNibName:nil bundle:nil];
	return (UIViewController<CCUIContentModuleContentViewController> *)_contentViewController;
}

- (UIViewController *)backgroundViewController {
	return nil;
}

@end
