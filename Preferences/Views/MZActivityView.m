#import "../../Shared/MZLocalization/MZLocalization.h"
#import "../../Shared/MZService.h"
#import "../Helpers/MZDiscordColors.h"
#import "../Helpers/MZImageLoader.h"
#import "MZActivityView.h"

static CGFloat const MZArtworkSize = 80;
static CGFloat const MZSmallImageSize = 28;

// "1:06:40", and under an hour "01:06", or "1:06" without padMinutes.
static NSString *MZTimeText(NSTimeInterval seconds, BOOL padMinutes) {
	long total = (long)MAX(0, floor(seconds));
	if (total >= 3600) return [NSString stringWithFormat:@"%ld:%02ld:%02ld", total / 3600, total / 60 % 60, total % 60];
	return [NSString stringWithFormat:padMinutes ? @"%02ld:%02ld" : @"%ld:%02ld", total / 60, total % 60];
}

// Discord's elapsed time: "1:06", in its positive green with the activity's
// icon.
static NSAttributedString *MZElapsedText(NSTimeInterval seconds, NSString *kind) {
	NSString *time = MZTimeText(seconds, NO);
	UIColor *green = [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
		return MZColorFromRGB(traits.userInterfaceStyle == UIUserInterfaceStyleDark ? 0x2DC770 : 0x248046);
	}];
	UIFont *font = [UIFont monospacedSystemFontOfSize:[UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline].pointSize weight:UIFontWeightRegular];
	NSMutableAttributedString *text = [NSMutableAttributedString new];
	UIImage *icon = [UIImage systemImageNamed:MZActivitySymbolName(kind) withConfiguration:[UIImageSymbolConfiguration configurationWithFont:font]];
	if (icon) {
		NSTextAttachment *attachment = [NSTextAttachment new];
		attachment.image = [icon imageWithTintColor:green renderingMode:UIImageRenderingModeAlwaysOriginal];
		[text appendAttributedString:[NSAttributedString attributedStringWithAttachment:attachment]];
		[text appendAttributedString:[[NSAttributedString alloc] initWithString:@" "]];
	}

	[text appendAttributedString:[[NSAttributedString alloc] initWithString:time attributes:@{NSFontAttributeName: font, NSForegroundColorAttributeName: green}]];
	return text;
}

static UILabel *MZLabel(UIFontTextStyle style, UIFontDescriptorSymbolicTraits traits, UIColor *color) {
	UILabel *label = [UILabel new];
	UIFontDescriptor *descriptor = [UIFontDescriptor preferredFontDescriptorWithTextStyle:style];
	label.font = [UIFont fontWithDescriptor:[descriptor fontDescriptorWithSymbolicTraits:traits] size:0];
	label.textColor = color;
	return label;
}

@implementation MZActivityView {
	UILabel *_headerLabel;
	UIImageView *_artworkView;
	// The artist's picture, in the cover's corner like Discord's small image.
	UIImageView *_smallImageView;
	UILabel *_detailsLabel;
	UILabel *_stateLabel;
	UILabel *_largeTextLabel;
	UIStackView *_progressRow;
	UILabel *_elapsedLabel;
	UIProgressView *_progressView;
	UILabel *_durationLabel;
	UIStackView *_card;
	UILabel *_emptyLabel;
	NSDate *_start;
	NSDate *_end;
	// Previews of a paused song stand still at this date.
	NSDate *_paused;
	NSTimer *_timer;
}

- (instancetype)initWithFrame:(CGRect)frame {
	if ((self = [super initWithFrame:frame])) {
		// A card inside the profile, like Discord's.
		self.backgroundColor = UIColor.systemGroupedBackgroundColor;
		self.layer.cornerRadius = 12;
		self.layer.borderWidth = 1;

		_headerLabel = MZLabel(UIFontTextStyleFootnote, UIFontDescriptorTraitBold, UIColor.secondaryLabelColor);

		_artworkView = [UIImageView new];
		_artworkView.contentMode = UIViewContentModeScaleAspectFill;
		_artworkView.clipsToBounds = YES;
		_artworkView.layer.cornerRadius = 8;
		_artworkView.backgroundColor = UIColor.tertiarySystemFillColor;
		_artworkView.translatesAutoresizingMaskIntoConstraints = NO;

		_smallImageView = [UIImageView new];
		_smallImageView.contentMode = UIViewContentModeScaleAspectFill;
		_smallImageView.clipsToBounds = YES;
		_smallImageView.layer.cornerRadius = MZSmallImageSize / 2;
		_smallImageView.layer.borderWidth = 2;
		_smallImageView.backgroundColor = UIColor.tertiarySystemFillColor;
		_smallImageView.translatesAutoresizingMaskIntoConstraints = NO;

		_detailsLabel = MZLabel(UIFontTextStyleHeadline, 0, UIColor.labelColor);
		_stateLabel = MZLabel(UIFontTextStyleSubheadline, 0, UIColor.labelColor);
		_largeTextLabel = MZLabel(UIFontTextStyleSubheadline, 0, UIColor.secondaryLabelColor);

		UIFont *timeFont = [UIFont monospacedDigitSystemFontOfSize:[UIFont preferredFontForTextStyle:UIFontTextStyleCaption1].pointSize weight:UIFontWeightRegular];
		_elapsedLabel = MZLabel(UIFontTextStyleCaption1, 0, UIColor.secondaryLabelColor);
		_elapsedLabel.font = timeFont;
		_durationLabel = MZLabel(UIFontTextStyleCaption1, 0, UIColor.secondaryLabelColor);
		_durationLabel.font = timeFont;
		_progressView = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
		_progressView.progressTintColor = UIColor.labelColor;
		for (UILabel *label in @[_elapsedLabel, _durationLabel]) {
			[label setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
			[label setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
		}
		_progressRow = [[UIStackView alloc] initWithArrangedSubviews:@[_elapsedLabel, _progressView, _durationLabel]];
		_progressRow.spacing = 8;
		_progressRow.alignment = UIStackViewAlignmentCenter;

		UIStackView *text = [[UIStackView alloc] initWithArrangedSubviews:@[_detailsLabel, _stateLabel, _largeTextLabel, _progressRow]];
		text.axis = UILayoutConstraintAxisVertical;
		text.spacing = 2;
		[text setCustomSpacing:6 afterView:_largeTextLabel];

		UIStackView *body = [[UIStackView alloc] initWithArrangedSubviews:@[_artworkView, text]];
		body.spacing = 12;
		body.alignment = UIStackViewAlignmentCenter;

		_card = [[UIStackView alloc] initWithArrangedSubviews:@[_headerLabel, body]];
		_card.axis = UILayoutConstraintAxisVertical;
		_card.spacing = 10;

		_emptyLabel = MZLabel(UIFontTextStyleSubheadline, 0, UIColor.secondaryLabelColor);
		_emptyLabel.numberOfLines = 0;
		_emptyLabel.text = MZLocalizedString(@"activity.nothing_is_showing_right_now_play", @"Nothing is showing right now. Play something in a supported app and it appears here and on your profile.");

		UIStackView *content = [[UIStackView alloc] initWithArrangedSubviews:@[_card, _emptyLabel]];
		content.axis = UILayoutConstraintAxisVertical;
		content.translatesAutoresizingMaskIntoConstraints = NO;
		[self addSubview:content];
		[self addSubview:_smallImageView];

		[NSLayoutConstraint activateConstraints:@[
			[content.topAnchor constraintEqualToAnchor:self.topAnchor constant:12],
			[content.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:12],
			[content.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-12],
			[content.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-12],
			[_artworkView.widthAnchor constraintEqualToConstant:MZArtworkSize],
			[_artworkView.heightAnchor constraintEqualToConstant:MZArtworkSize],
			[_smallImageView.widthAnchor constraintEqualToConstant:MZSmallImageSize],
			[_smallImageView.heightAnchor constraintEqualToConstant:MZSmallImageSize],
			[_smallImageView.centerXAnchor constraintEqualToAnchor:_artworkView.trailingAnchor constant:-4],
			[_smallImageView.centerYAnchor constraintEqualToAnchor:_artworkView.bottomAnchor constant:-4],
		]];
	}

	return self;
}

- (void)layoutSubviews {
	[super layoutSubviews];
	// Cuts the picture out of the cover, in the card's colour (CGColors don't
	// follow dark mode by themselves).
	_smallImageView.layer.borderColor = [self.backgroundColor resolvedColorWithTraitCollection:self.traitCollection].CGColor;
	self.layer.borderColor = [UIColor.separatorColor resolvedColorWithTraitCollection:self.traitCollection].CGColor;
}

- (void)setActivity:(NSDictionary<NSString *, id> *)activity {
	_activity = [activity copy];
	_card.hidden = !activity;
	_emptyLabel.hidden = !!activity;
	_smallImageView.hidden = YES;
	if (!activity) {
		_start = nil;
		[self updateTimer];
		return;
	}

	// Without a name, Discord uses the application's.
	NSString *name = [activity[MZActivityNameKey] length] ? activity[MZActivityNameKey] : @"Menzen";
	NSString *format = MZLocalizedString(@"activity.listening_to_x", @"Listening to %@");
	if ([activity[MZActivityKindKey] isEqualToString:@"watching"]) format = MZLocalizedString(@"activity.watching_x", @"Watching %@");
	if ([activity[MZActivityKindKey] isEqualToString:@"playing"]) format = MZLocalizedString(@"activity.playing_x", @"Playing %@");
	_headerLabel.text = [NSString stringWithFormat:format, name];
	_detailsLabel.text = activity[MZActivityDetailsKey];
	_stateLabel.text = activity[MZActivityStateKey];
	_stateLabel.hidden = !_stateLabel.text.length;
	_largeTextLabel.text = activity[MZActivityLargeTextKey];
	_largeTextLabel.hidden = !_largeTextLabel.text.length;

	NSString *imageURL = activity[MZActivityImageURLKey];
	_artworkView.hidden = !imageURL;
	MZSetImage(_artworkView, imageURL);
	NSString *smallImageURL = imageURL ? activity[MZActivitySmallImageURLKey] : nil;
	_smallImageView.hidden = !smallImageURL;
	MZSetImage(_smallImageView, smallImageURL);

	NSNumber *start = activity[MZActivityStartKey];
	NSNumber *end = activity[MZActivityEndKey];
	_start = start ? [NSDate dateWithTimeIntervalSince1970:start.doubleValue] : nil;
	_end = end ? [NSDate dateWithTimeIntervalSince1970:end.doubleValue] : nil;
	NSNumber *paused = activity[MZActivityPausedKey];
	_paused = paused ? [NSDate dateWithTimeIntervalSince1970:paused.doubleValue] : nil;
	// Without an end, Discord shows only the time elapsed.
	_progressRow.hidden = !_start;
	_progressView.hidden = !_end;
	_durationLabel.hidden = !_end;
	[self updateProgress];
	[self updateTimer];
}

// Discord counts up from the start date; paused activities have none.
- (void)updateProgress {
	if (!_start) return;
	if (!_end) {
		_elapsedLabel.attributedText = MZElapsedText([_paused ?: NSDate.date timeIntervalSinceDate:_start], _activity[MZActivityKindKey]);
		return;
	}

	NSTimeInterval duration = [_end timeIntervalSinceDate:_start];
	NSTimeInterval elapsed = MIN(MAX([_paused ?: NSDate.date timeIntervalSinceDate:_start], 0), duration);
	_elapsedLabel.text = MZTimeText(elapsed, YES);
	_durationLabel.text = MZTimeText(duration, YES);
	_progressView.progress = duration > 0 ? elapsed / duration : 0;
}

// Ticks only while the card is on screen and something is playing.
- (void)updateTimer {
	BOOL needsTimer = self.window && _start && !_paused;
	if (needsTimer == !!_timer) return;
	[_timer invalidate];
	_timer = nil;
	if (!needsTimer) return;
	__weak typeof(self) weakSelf = self;
	_timer = [NSTimer scheduledTimerWithTimeInterval:1 repeats:YES block:^(NSTimer *timer) {
		[weakSelf updateProgress];
	}];
}

- (void)didMoveToWindow {
	[super didMoveToWindow];
	[self updateTimer];
}

- (void)dealloc {
	[_timer invalidate];
}

@end
