#import <objc/runtime.h>

#import "../../Shared/MenzenAppPrivacy.h"
#import "../../Shared/MenzenLocalization/MenzenLocalization.h"
#import "MenzenAppPrivacyModule.h"

@interface UIImage (MenzenPrivate)
+ (UIImage *)_applicationIconImageForBundleIdentifier:(NSString *)bundleIdentifier format:(int)format scale:(CGFloat)scale;
@end

@interface MenzenAppPrivacyViewController ()
@property (nonatomic, readwrite) BOOL showsAppIcon;
- (void)refresh;
@end

// Control Center sets every glyph as a template, tinted in one color. As the
// button view's glyph view, this keeps the app icon's colors.
@interface MenzenAppPrivacyGlyphView : UIImageView
@end

@implementation MenzenAppPrivacyGlyphView

- (void)setImage:(UIImage *)image {
	UIResponder *responder = self;
	while (responder && ![responder isKindOfClass:MenzenAppPrivacyViewController.class]) responder = responder.nextResponder;

	if (((MenzenAppPrivacyViewController *)responder).showsAppIcon) image = [image imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
	[super setImage:image];
}

@end

static CGSize const MenzenAppIconGlyphSize = {32, 32};

static void MenzenStrokeEye(CGPoint center, CGFloat radius, UIColor *color) {
	CGFloat width = 0.74 * radius, height = radius;
	UIBezierPath *outline = [UIBezierPath bezierPath];
	[outline moveToPoint:CGPointMake(center.x - width, center.y)];
	[outline addQuadCurveToPoint:CGPointMake(center.x + width, center.y) controlPoint:CGPointMake(center.x, center.y - height)];
	[outline addQuadCurveToPoint:CGPointMake(center.x - width, center.y) controlPoint:CGPointMake(center.x, center.y + height)];
	[outline closePath];
	outline.lineWidth = 0.15 * radius;
	outline.lineJoinStyle = kCGLineJoinRound;

	[color set];
	[outline stroke];

	CGFloat pupil = 0.26 * radius;
	[[UIBezierPath bezierPathWithOvalInRect:CGRectMake(center.x - pupil, center.y - pupil, pupil * 2, pupil * 2)] fill];
}

static void MenzenStrokeSlash(CGPoint center, CGFloat radius, CGFloat width, UIColor *color) {
	CGFloat offset = 0.62 * radius;
	UIBezierPath *slash = [UIBezierPath bezierPath];
	[slash moveToPoint:CGPointMake(center.x - offset, center.y - offset)];
	[slash addLineToPoint:CGPointMake(center.x + offset, center.y + offset)];
	slash.lineWidth = width;
	slash.lineCapStyle = kCGLineCapRound;

	[color setStroke];
	[slash stroke];
}

// The badge from the global module's glyph, drawn to the same proportions in
// a gap cut out of the icon: an eye when off, a crossed-out eye on red when on.
static void MenzenDrawPrivacyBadge(CGContextRef context, BOOL selected) {
	// The global glyph's badge in points, against the bottom-right corner.
	CGPoint center = CGPointMake(28, 28);
	CGFloat radius = 4;
	CGFloat gap = radius * 114 / 78;

	CGContextSetBlendMode(context, kCGBlendModeClear);
	CGContextFillEllipseInRect(context, CGRectMake(center.x - gap, center.y - gap, gap * 2, gap * 2));
	CGContextSetBlendMode(context, kCGBlendModeNormal);

	if (!selected) {
		MenzenStrokeEye(center, radius * 1.3, UIColor.whiteColor);
		return;
	}

	// The global module's red.
	UIColor *red = [UIColor colorWithRed:242 / 255.0 green:63 / 255.0 blue:67 / 255.0 alpha:1];
	[red setFill];
	CGContextFillEllipseInRect(context, CGRectMake(center.x - radius, center.y - radius, radius * 2, radius * 2));

	MenzenStrokeEye(center, radius, UIColor.whiteColor);
	MenzenStrokeSlash(center, radius, 0.15 * radius * 2.4, red);
	MenzenStrokeSlash(center, radius, 0.15 * radius, UIColor.whiteColor);
}

// Off: the icon in grey and faded. On: in color.
static UIImage *MenzenAppIconGlyph(UIImage *icon, BOOL selected) {
	UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat preferredFormat];
	UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:MenzenAppIconGlyphSize format:format];

	return [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
		CGRect iconRect = CGRectMake(2, 2, 26, 26);
		[icon drawInRect:iconRect];

		if (!selected) {
			[UIColor.grayColor setFill];
			UIRectFillUsingBlendMode(iconRect, kCGBlendModeColor);
			// The fill covers the rounded corners too; the icon's own shape cuts it back.
			[icon drawInRect:iconRect blendMode:kCGBlendModeDestinationIn alpha:0.6];
		}

		MenzenDrawPrivacyBadge(context.CGContext, selected);
	}];
}

static void MenzenAppPrivacySettingsChanged(CFNotificationCenterRef center, void *observer, CFNotificationName name, const void *object, CFDictionaryRef userInfo) {
	MenzenAppPrivacyViewController *controller = (__bridge MenzenAppPrivacyViewController *)observer;
	dispatch_async(dispatch_get_main_queue(), ^{
		[controller refresh];
	});
}

@implementation MenzenAppPrivacyViewController

- (instancetype)initWithNibName:(NSString *)nibName bundle:(NSBundle *)bundle {
	if ((self = [super initWithNibName:nibName bundle:bundle])) {
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

	[self updateGlyphsForApp:choice.firstObject];
	self.selected = MenzenSettingBool(MenzenPrivacyModuleKey(), NO);
	[self reloadActions];
}

- (void)updateGlyphsForApp:(NSString *)bundleIdentifier {
	UIImage *icon = bundleIdentifier ? [UIImage _applicationIconImageForBundleIdentifier:bundleIdentifier format:2 scale:UIScreen.mainScreen.scale] : nil;
	self.showsAppIcon = icon != nil;

	if (icon) {
		self.glyphImage = MenzenAppIconGlyph(icon, NO);
		self.selectedGlyphImage = MenzenAppIconGlyph(icon, YES);
		return;
	}

	NSBundle *resources = [NSBundle bundleForClass:self.class];
	self.glyphImage = [[UIImage imageNamed:@"Glyph" inBundle:resources compatibleWithTraitCollection:nil] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
	self.selectedGlyphImage = [[UIImage imageNamed:@"GlyphSelected" inBundle:resources compatibleWithTraitCollection:nil] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
}

// The button view makes its glyph view before the first layout. It has no
// getter before iOS 26.
- (void)viewDidLayoutSubviews {
	[super viewDidLayoutSubviews];

	UIControl *button = self.buttonView;
	Ivar ivar = button ? class_getInstanceVariable(object_getClass(button), "_glyphImageView") : NULL;
	UIImageView *glyphView = ivar ? object_getIvar(button, ivar) : nil;

	if ([glyphView isMemberOfClass:UIImageView.class]) {
		object_setClass(glyphView, MenzenAppPrivacyGlyphView.class);
		// Through the subclass, for the image already there.
		glyphView.image = glyphView.image;
	}
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
