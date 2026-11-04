#import <CoreImage/CoreImage.h>

#import "../../Shared/MenzenLocalization/MenzenLocalization.h"
#import "../Helpers/MenzenServiceClient.h"
#import "MenzenOtherDeviceSignIn.h"

static CGFloat const MenzenCodeSize = 240;
static CGFloat const MenzenCodeQuietZone = 12;
// How long Copy Link reads Copied.
static NSTimeInterval const MenzenCopiedDuration = 1.5;

static UIImage *MenzenQRCodeImage(NSURL *url) {
	CIFilter *filter = [CIFilter filterWithName:@"CIQRCodeGenerator"];
	[filter setValue:[url.absoluteString dataUsingEncoding:NSUTF8StringEncoding] forKey:@"inputMessage"];
	[filter setValue:@"M" forKey:@"inputCorrectionLevel"];
	CIImage *code = filter.outputImage;
	if (!code) return nil;

	// Scaled here in whole modules, so the image view never blurs them.
	CGFloat scale = ceil(MenzenCodeSize * UIScreen.mainScreen.scale / code.extent.size.width);
	code = [code imageByApplyingTransform:CGAffineTransformMakeScale(scale, scale)];
	CGImageRef image = [[CIContext contextWithOptions:nil] createCGImage:code fromRect:code.extent];
	if (!image) return nil;
	UIImage *result = [UIImage imageWithCGImage:image scale:UIScreen.mainScreen.scale orientation:UIImageOrientationUp];
	CGImageRelease(image);
	return result;
}

static UILabel *MenzenTextLabel(UIFontTextStyle style, UIColor *color) {
	UILabel *label = [UILabel new];
	label.font = [UIFont preferredFontForTextStyle:style];
	label.textColor = color;
	label.textAlignment = NSTextAlignmentCenter;
	label.numberOfLines = 0;
	label.adjustsFontForContentSizeCategory = YES;
	return label;
}

@implementation MenzenOtherDeviceSignInController {
	NSURL *_verificationURL;
	// Bumped by every new code, so replies about an older one are dropped.
	NSUInteger _attempt;
	UIImageView *_codeView;
	UILabel *_userCodeLabel;
	UIButton *_copyButton;
	UIButton *_shareButton;
	UIActivityIndicatorView *_spinner;
	UILabel *_statusLabel;
	UIButton *_retryButton;
	BOOL _finished;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = MenzenLocalizedString(@"signin.another_device", @"Another Device");
	self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;
	self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(cancel)];
	// Closed only through finish, so completion always runs.
	self.modalInPresentation = YES;

	UILabel *intro = MenzenTextLabel(UIFontTextStyleSubheadline, UIColor.secondaryLabelColor);
	intro.text = MenzenLocalizedString(@"signin.scan_this_code_with_another_phone", @"Scan this code with another phone's camera, then sign in to Discord there and approve Menzen.");

	UIView *codeBackground = [UIView new];
	codeBackground.backgroundColor = UIColor.whiteColor;
	codeBackground.layer.cornerRadius = 12;
	_codeView = [UIImageView new];
	_codeView.contentMode = UIViewContentModeScaleAspectFit;
	_codeView.isAccessibilityElement = YES;
	_codeView.accessibilityLabel = MenzenLocalizedString(@"signin.qr_code_for_discord_s_sign", @"QR code for Discord's sign-in page");
	_codeView.translatesAutoresizingMaskIntoConstraints = NO;
	[codeBackground addSubview:_codeView];
	_spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
	_spinner.color = UIColor.grayColor;
	_spinner.hidesWhenStopped = YES;
	_spinner.translatesAutoresizingMaskIntoConstraints = NO;
	[codeBackground addSubview:_spinner];

	UILabel *typeIntro = MenzenTextLabel(UIFontTextStyleSubheadline, UIColor.secondaryLabelColor);
	typeIntro.text = MenzenLocalizedString(@"signin.or_go_to_discord_com_activate", @"Or go to discord.com/activate on any device and enter:");
	_userCodeLabel = MenzenTextLabel(UIFontTextStyleTitle1, UIColor.labelColor);
	_userCodeLabel.font = [UIFont monospacedSystemFontOfSize:[UIFont preferredFontForTextStyle:UIFontTextStyleTitle1].pointSize weight:UIFontWeightSemibold];
	_userCodeLabel.text = @" ";

	_copyButton = [UIButton buttonWithType:UIButtonTypeSystem];
	[_copyButton setTitle:MenzenLocalizedString(@"signin.copy_link", @"Copy Link") forState:UIControlStateNormal];
	[_copyButton addTarget:self action:@selector(copyLink) forControlEvents:UIControlEventTouchUpInside];
	_shareButton = [UIButton buttonWithType:UIButtonTypeSystem];
	[_shareButton setTitle:MenzenLocalizedString(@"signin.share", @"Share") forState:UIControlStateNormal];
	[_shareButton addTarget:self action:@selector(shareLink) forControlEvents:UIControlEventTouchUpInside];
	UIStackView *linkButtons = [[UIStackView alloc] initWithArrangedSubviews:@[_copyButton, _shareButton]];
	linkButtons.spacing = 32;

	_statusLabel = MenzenTextLabel(UIFontTextStyleFootnote, UIColor.secondaryLabelColor);
	_retryButton = [UIButton buttonWithType:UIButtonTypeSystem];
	[_retryButton setTitle:MenzenLocalizedString(@"signin.try_again", @"Try Again") forState:UIControlStateNormal];
	[_retryButton addTarget:self action:@selector(requestCode) forControlEvents:UIControlEventTouchUpInside];
	_retryButton.hidden = YES;

	UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[intro, codeBackground, typeIntro, _userCodeLabel, linkButtons, _statusLabel, _retryButton]];
	stack.axis = UILayoutConstraintAxisVertical;
	stack.alignment = UIStackViewAlignmentCenter;
	stack.spacing = 16;
	[stack setCustomSpacing:4 afterView:typeIntro];
	stack.translatesAutoresizingMaskIntoConstraints = NO;

	UIScrollView *scrollView = [UIScrollView new];
	scrollView.alwaysBounceVertical = YES;
	scrollView.translatesAutoresizingMaskIntoConstraints = NO;
	[scrollView addSubview:stack];
	[self.view addSubview:scrollView];

	UILayoutGuide *content = scrollView.contentLayoutGuide;
	UILayoutGuide *readable = self.view.readableContentGuide;
	[NSLayoutConstraint activateConstraints:@[
		[scrollView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
		[scrollView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
		[scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
		[scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
		[content.widthAnchor constraintEqualToAnchor:scrollView.frameLayoutGuide.widthAnchor],
		[stack.topAnchor constraintEqualToAnchor:content.topAnchor constant:20],
		[stack.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-20],
		[stack.leadingAnchor constraintEqualToAnchor:readable.leadingAnchor],
		[stack.trailingAnchor constraintEqualToAnchor:readable.trailingAnchor],
		[intro.widthAnchor constraintEqualToAnchor:stack.widthAnchor],
		[typeIntro.widthAnchor constraintEqualToAnchor:stack.widthAnchor],
		[_statusLabel.widthAnchor constraintEqualToAnchor:stack.widthAnchor],
		[codeBackground.widthAnchor constraintEqualToConstant:MenzenCodeSize + 2 * MenzenCodeQuietZone],
		[codeBackground.heightAnchor constraintEqualToAnchor:codeBackground.widthAnchor],
		[_codeView.topAnchor constraintEqualToAnchor:codeBackground.topAnchor constant:MenzenCodeQuietZone],
		[_codeView.bottomAnchor constraintEqualToAnchor:codeBackground.bottomAnchor constant:-MenzenCodeQuietZone],
		[_codeView.leadingAnchor constraintEqualToAnchor:codeBackground.leadingAnchor constant:MenzenCodeQuietZone],
		[_codeView.trailingAnchor constraintEqualToAnchor:codeBackground.trailingAnchor constant:-MenzenCodeQuietZone],
		[_spinner.centerXAnchor constraintEqualToAnchor:codeBackground.centerXAnchor],
		[_spinner.centerYAnchor constraintEqualToAnchor:codeBackground.centerYAnchor],
	]];

	[self requestCode];
}

- (void)requestCode {
	[self requestCodeAfterMessage:nil];
}

// message says why the previous code is gone, unless it just expired.
- (void)requestCodeAfterMessage:(NSString *)message {
	NSUInteger attempt = ++_attempt;
	[self showCodeURL:nil userCode:nil];
	[_spinner startAnimating];
	[self showStatus:message];

	__weak typeof(self) weakSelf = self;
	[MenzenServiceProxy(nil) beginSignInOnOtherDeviceWithReply:^(NSURL *verificationURL, NSString *userCode, NSString *error) {
		dispatch_async(dispatch_get_main_queue(), ^{
			typeof(self) strongSelf = weakSelf;
			if (!strongSelf || attempt != strongSelf->_attempt) return;
			[strongSelf->_spinner stopAnimating];
			if (!verificationURL || !userCode) {
				[strongSelf showStatus:error ?: MenzenLocalizedString(@"common.menzen_couldn_t_start_the_sign", @"Menzen couldn't start the sign-in. Try again.")];
				strongSelf->_retryButton.hidden = NO;
				return;
			}
			[strongSelf showCodeURL:verificationURL userCode:userCode];
			if (message) [strongSelf showStatus:[message stringByAppendingString:MenzenLocalizedString(@"signin.here_s_a_new_code", @" Here's a new code.")]];
			[strongSelf waitForApproval:attempt];
		});
	}];
}

- (void)waitForApproval:(NSUInteger)attempt {
	__weak typeof(self) weakSelf = self;
	[MenzenServiceProxy(nil) waitForSignInOnOtherDeviceWithReply:^(BOOL signedIn, NSString *error) {
		dispatch_async(dispatch_get_main_queue(), ^{
			typeof(self) strongSelf = weakSelf;
			if (!strongSelf || attempt != strongSelf->_attempt) return;
			if (signedIn) {
				[strongSelf finish];
			} else {
				// An expired code is just replaced.
				[strongSelf requestCodeAfterMessage:error];
			}
		});
	}];
}

- (void)showCodeURL:(NSURL *)url userCode:(NSString *)userCode {
	_verificationURL = url;
	_codeView.image = url ? MenzenQRCodeImage(url) : nil;
	_userCodeLabel.text = userCode ?: @" ";
	_copyButton.enabled = url != nil;
	_shareButton.enabled = url != nil;
	_retryButton.hidden = YES;
}

- (void)showStatus:(NSString *)status {
	_statusLabel.text = status;
	_statusLabel.hidden = !status;
}

- (void)copyLink {
	if (!_verificationURL) return;
	UIPasteboard.generalPasteboard.URL = _verificationURL;
	[[UIImpactFeedbackGenerator new] impactOccurred];
	[_copyButton setTitle:MenzenLocalizedString(@"signin.copied", @"Copied") forState:UIControlStateNormal];
	__weak UIButton *button = _copyButton;
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(MenzenCopiedDuration * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		[button setTitle:MenzenLocalizedString(@"signin.copy_link", @"Copy Link") forState:UIControlStateNormal];
	});
}

- (void)shareLink {
	if (!_verificationURL) return;
	[[UIImpactFeedbackGenerator new] impactOccurred];
	UIActivityViewController *share = [[UIActivityViewController alloc] initWithActivityItems:@[_verificationURL] applicationActivities:nil];
	share.popoverPresentationController.sourceView = _shareButton;
	share.popoverPresentationController.sourceRect = _shareButton.bounds;
	[self presentViewController:share animated:YES completion:nil];
}

- (void)cancel {
	[MenzenServiceProxy(nil) cancelSignInOnOtherDevice];
	[self finish];
}

- (void)finish {
	if (_finished) return;
	_finished = YES;
	_attempt++;
	[self dismissViewControllerAnimated:YES completion:nil];
	if (self.completion) self.completion();
}

@end
