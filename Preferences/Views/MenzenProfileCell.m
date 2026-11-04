#import <Preferences/PSSpecifier.h>

#import "../../Shared/MenzenLocalization/MenzenLocalization.h"
#import "../../Shared/MenzenService.h"
#import "../Helpers/MenzenDiscordColors.h"
#import "../Helpers/MenzenImageLoader.h"
#import "MenzenActivityView.h"
#import "MenzenProfileCell.h"

static CGFloat const MenzenBannerHeight = 100;
static CGFloat const MenzenAvatarSize = 80;
static CGFloat const MenzenAvatarBorder = 4;
static CGFloat const MenzenStatusSize = 24;

// Symbols stand in for Discord's own badge art.
static NSArray<NSArray<NSString *> *> *MenzenBadgeDescriptions(NSDictionary *profile) {
	static NSDictionary<NSString *, NSArray<NSString *> *> *descriptions;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		descriptions = @{
			@"staff": @[MenzenLocalizedString(@"profile.discord_staff", @"Discord Staff"), @"star.circle.fill"],
			@"partner": @[MenzenLocalizedString(@"profile.partner", @"Partner"), @"infinity.circle.fill"],
			@"moderatorAlumni": @[MenzenLocalizedString(@"profile.moderator_alumni", @"Moderator Alumni"), @"shield.fill"],
			@"hypesquad": @[MenzenLocalizedString(@"profile.hypesquad_events", @"HypeSquad Events"), @"house.fill"],
			@"hypesquadBravery": @[MenzenLocalizedString(@"profile.hypesquad_bravery", @"HypeSquad Bravery"), @"shield.lefthalf.filled"],
			@"hypesquadBrilliance": @[MenzenLocalizedString(@"profile.hypesquad_brilliance", @"HypeSquad Brilliance"), @"diamond.fill"],
			@"hypesquadBalance": @[MenzenLocalizedString(@"profile.hypesquad_balance", @"HypeSquad Balance"), @"scalemass.fill"],
			@"bugHunter": @[MenzenLocalizedString(@"profile.bug_hunter", @"Bug Hunter"), @"ladybug.fill"],
			@"bugHunterGold": @[MenzenLocalizedString(@"profile.gold_bug_hunter", @"Gold Bug Hunter"), @"ladybug.fill"],
			@"activeDeveloper": @[MenzenLocalizedString(@"profile.active_developer", @"Active Developer"), @"chevron.left.forwardslash.chevron.right"],
			@"earlyVerifiedBotDeveloper": @[MenzenLocalizedString(@"profile.early_verified_bot_developer", @"Early Verified Bot Developer"), @"checkmark.seal.fill"],
			@"earlySupporter": @[MenzenLocalizedString(@"profile.early_supporter", @"Early Supporter"), @"heart.fill"],
		};
	});

	NSMutableArray *result = [NSMutableArray array];
	NSInteger premiumType = [profile[MenzenProfilePremiumTypeKey] integerValue];
	if (premiumType == 1) [result addObject:@[MenzenLocalizedString(@"profile.nitro_classic", @"Nitro Classic"), @"bolt.circle.fill"]];
	if (premiumType == 2) [result addObject:@[MenzenLocalizedString(@"profile.nitro", @"Nitro"), @"bolt.circle.fill"]];
	if (premiumType == 3) [result addObject:@[MenzenLocalizedString(@"profile.nitro_basic", @"Nitro Basic"), @"bolt.circle.fill"]];
	for (NSString *badge in profile[MenzenProfileBadgesKey]) {
		NSArray *description = descriptions[badge];
		if (description) [result addObject:description];
	}

	return result;
}

static NSAttributedString *MenzenBadgesText(NSArray<NSArray<NSString *> *> *badges) {
	NSMutableAttributedString *text = [NSMutableAttributedString new];
	UIFont *font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
	NSDictionary *attributes = @{NSFontAttributeName: font, NSForegroundColorAttributeName: UIColor.secondaryLabelColor};
	UIImageSymbolConfiguration *configuration = [UIImageSymbolConfiguration configurationWithFont:font];
	for (NSArray<NSString *> *badge in badges) {
		if (text.length) [text appendAttributedString:[[NSAttributedString alloc] initWithString:@"    " attributes:attributes]];
		UIImage *symbol = [UIImage systemImageNamed:badge[1] withConfiguration:configuration];
		if (symbol) {
			NSTextAttachment *attachment = [NSTextAttachment new];
			attachment.image = [symbol imageWithTintColor:MenzenBlurple() renderingMode:UIImageRenderingModeAlwaysOriginal];
			[text appendAttributedString:[NSAttributedString attributedStringWithAttachment:attachment]];
			[text appendAttributedString:[[NSAttributedString alloc] initWithString:@" " attributes:attributes]];
		}
		// No-break spaces keep a badge's name on one line.
		NSString *name = [badge[0] stringByReplacingOccurrencesOfString:@" " withString:@" "];
		[text appendAttributedString:[[NSAttributedString alloc] initWithString:name attributes:attributes]];
	}

	return text;
}

static UIImageView *MenzenRoundImageView(CGFloat size) {
	UIImageView *imageView = [UIImageView new];
	imageView.contentMode = UIViewContentModeScaleAspectFill;
	imageView.clipsToBounds = YES;
	imageView.layer.cornerRadius = size / 2;
	imageView.backgroundColor = UIColor.tertiarySystemFillColor;
	imageView.translatesAutoresizingMaskIntoConstraints = NO;
	[NSLayoutConstraint activateConstraints:@[
		[imageView.widthAnchor constraintEqualToConstant:size],
		[imageView.heightAnchor constraintEqualToConstant:size],
	]];
	return imageView;
}

@implementation MenzenProfileCell {
	UIImageView *_bannerView;
	UIView *_avatarBorder;
	UIImageView *_avatarView;
	UIImageView *_decorationView;
	UILabel *_nameLabel;
	UILabel *_usernameLabel;
	UIView *_tagChip;
	UIImageView *_tagBadgeView;
	UILabel *_tagLabel;
	UILabel *_badgesLabel;
	UIView *_statusView;
	MenzenActivityView *_activityView;
	// Over everything, for errors and while connecting.
	UIVisualEffectView *_overlay;
	UIActivityIndicatorView *_overlaySpinner;
	UIImageView *_overlayIcon;
	UILabel *_overlayLabel;
	NSArray<NSNumber *> *_nameColors;
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier specifier:(PSSpecifier *)specifier {
	if ((self = [super initWithStyle:style reuseIdentifier:reuseIdentifier specifier:specifier])) {
		self.selectionStyle = UITableViewCellSelectionStyleNone;
		self.clipsToBounds = YES;
		UIView *content = self.contentView;

		_bannerView = [UIImageView new];
		_bannerView.contentMode = UIViewContentModeScaleAspectFill;
		_bannerView.clipsToBounds = YES;

		_avatarBorder = [UIView new];
		_avatarBorder.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
		_avatarBorder.layer.cornerRadius = MenzenAvatarSize / 2 + MenzenAvatarBorder;

		_avatarView = MenzenRoundImageView(MenzenAvatarSize);

		_decorationView = [UIImageView new];
		_decorationView.contentMode = UIViewContentModeScaleAspectFit;

		_statusView = [UIView new];
		_statusView.layer.cornerRadius = MenzenStatusSize / 2;
		_statusView.layer.borderWidth = MenzenAvatarBorder;
		_statusView.layer.borderColor = UIColor.secondarySystemGroupedBackgroundColor.CGColor;

		for (UIView *view in @[_bannerView, _avatarBorder, _avatarView, _decorationView, _statusView]) {
			view.translatesAutoresizingMaskIntoConstraints = NO;
			[content addSubview:view];
		}

		_nameLabel = [UILabel new];
		UIFontDescriptor *title = [UIFontDescriptor preferredFontDescriptorWithTextStyle:UIFontTextStyleTitle2];
		_nameLabel.font = [UIFont fontWithDescriptor:[title fontDescriptorWithSymbolicTraits:UIFontDescriptorTraitBold] size:0];

		_usernameLabel = [UILabel new];
		_usernameLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
		_usernameLabel.textColor = UIColor.secondaryLabelColor;
		[_usernameLabel setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];

		_tagBadgeView = [UIImageView new];
		_tagBadgeView.contentMode = UIViewContentModeScaleAspectFit;
		_tagLabel = [UILabel new];
		_tagLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
		_tagLabel.font = [UIFont fontWithDescriptor:[_tagLabel.font.fontDescriptor fontDescriptorWithSymbolicTraits:UIFontDescriptorTraitBold] size:0];
		UIStackView *tagStack = [[UIStackView alloc] initWithArrangedSubviews:@[_tagBadgeView, _tagLabel]];
		tagStack.spacing = 4;
		tagStack.alignment = UIStackViewAlignmentCenter;
		tagStack.translatesAutoresizingMaskIntoConstraints = NO;
		_tagChip = [UIView new];
		_tagChip.backgroundColor = UIColor.tertiarySystemFillColor;
		_tagChip.layer.cornerRadius = 6;
		[_tagChip addSubview:tagStack];
		[_tagChip setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];

		UIStackView *usernameRow = [[UIStackView alloc] initWithArrangedSubviews:@[_usernameLabel, _tagChip]];
		usernameRow.spacing = 8;
		usernameRow.alignment = UIStackViewAlignmentCenter;

		_badgesLabel = [UILabel new];
		_badgesLabel.numberOfLines = 0;

		UIStackView *info = [[UIStackView alloc] initWithArrangedSubviews:@[_nameLabel, usernameRow, _badgesLabel]];
		info.axis = UILayoutConstraintAxisVertical;
		info.alignment = UIStackViewAlignmentLeading;
		info.spacing = 12;
		[info setCustomSpacing:2 afterView:_nameLabel];
		info.translatesAutoresizingMaskIntoConstraints = NO;
		[content addSubview:info];

		_activityView = [MenzenActivityView new];
		_activityView.translatesAutoresizingMaskIntoConstraints = NO;
		[content addSubview:_activityView];

		_overlay = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterial]];
		_overlay.translatesAutoresizingMaskIntoConstraints = NO;
		[content addSubview:_overlay];
		_overlaySpinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
		_overlayLabel = [UILabel new];
		_overlayLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
		_overlayLabel.textColor = UIColor.secondaryLabelColor;
		_overlayLabel.textAlignment = NSTextAlignmentCenter;
		_overlayLabel.numberOfLines = 0;
		UIImageSymbolConfiguration *iconConfiguration = [UIImageSymbolConfiguration configurationWithTextStyle:UIFontTextStyleTitle2];
		_overlayIcon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"exclamationmark.triangle.fill" withConfiguration:iconConfiguration]];
		_overlayIcon.tintColor = UIColor.secondaryLabelColor;
		UIStackView *overlayStack = [[UIStackView alloc] initWithArrangedSubviews:@[_overlaySpinner, _overlayIcon, _overlayLabel]];
		overlayStack.axis = UILayoutConstraintAxisVertical;
		overlayStack.alignment = UIStackViewAlignmentCenter;
		overlayStack.spacing = 8;
		overlayStack.translatesAutoresizingMaskIntoConstraints = NO;
		[_overlay.contentView addSubview:overlayStack];

		UILayoutGuide *margins = content.layoutMarginsGuide;
		NSLayoutConstraint *bottom = [_activityView.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-16];
		// Lets the cell size itself without fighting the table's first guess.
		bottom.priority = UILayoutPriorityDefaultHigh;
		[NSLayoutConstraint activateConstraints:@[
			[_bannerView.topAnchor constraintEqualToAnchor:content.topAnchor],
			[_bannerView.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
			[_bannerView.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],
			[_bannerView.heightAnchor constraintEqualToConstant:MenzenBannerHeight],

			[_avatarView.leadingAnchor constraintEqualToAnchor:margins.leadingAnchor constant:MenzenAvatarSize * 0.1],
			[_avatarView.centerYAnchor constraintEqualToAnchor:_bannerView.bottomAnchor],

			[_avatarBorder.centerXAnchor constraintEqualToAnchor:_avatarView.centerXAnchor],
			[_avatarBorder.centerYAnchor constraintEqualToAnchor:_avatarView.centerYAnchor],
			[_avatarBorder.widthAnchor constraintEqualToConstant:MenzenAvatarSize + 2 * MenzenAvatarBorder],
			[_avatarBorder.heightAnchor constraintEqualToConstant:MenzenAvatarSize + 2 * MenzenAvatarBorder],

			[_decorationView.centerXAnchor constraintEqualToAnchor:_avatarView.centerXAnchor],
			[_decorationView.centerYAnchor constraintEqualToAnchor:_avatarView.centerYAnchor],
			[_decorationView.widthAnchor constraintEqualToConstant:MenzenAvatarSize * 1.2],
			[_decorationView.heightAnchor constraintEqualToConstant:MenzenAvatarSize * 1.2],

			[tagStack.topAnchor constraintEqualToAnchor:_tagChip.topAnchor constant:3],
			[tagStack.bottomAnchor constraintEqualToAnchor:_tagChip.bottomAnchor constant:-3],
			[tagStack.leadingAnchor constraintEqualToAnchor:_tagChip.leadingAnchor constant:6],
			[tagStack.trailingAnchor constraintEqualToAnchor:_tagChip.trailingAnchor constant:-6],
			[_tagBadgeView.widthAnchor constraintEqualToConstant:16],
			[_tagBadgeView.heightAnchor constraintEqualToConstant:16],

			// At the avatar's lower right, like Discord's.
			[_statusView.centerXAnchor constraintEqualToAnchor:_avatarView.centerXAnchor constant:MenzenAvatarSize / 2 * M_SQRT1_2],
			[_statusView.centerYAnchor constraintEqualToAnchor:_avatarView.centerYAnchor constant:MenzenAvatarSize / 2 * M_SQRT1_2],
			[_statusView.widthAnchor constraintEqualToConstant:MenzenStatusSize],
			[_statusView.heightAnchor constraintEqualToConstant:MenzenStatusSize],

			// Room for the decoration, which reaches past the avatar.
			[info.topAnchor constraintEqualToAnchor:_avatarView.bottomAnchor constant:MenzenAvatarSize * 0.1 + 8],
			[info.leadingAnchor constraintEqualToAnchor:margins.leadingAnchor],
			[info.trailingAnchor constraintEqualToAnchor:margins.trailingAnchor],
			[usernameRow.trailingAnchor constraintLessThanOrEqualToAnchor:info.trailingAnchor],

			[_activityView.topAnchor constraintEqualToAnchor:info.bottomAnchor constant:16],
			[_activityView.leadingAnchor constraintEqualToAnchor:margins.leadingAnchor],
			[_activityView.trailingAnchor constraintEqualToAnchor:margins.trailingAnchor],
			bottom,

			[_overlay.topAnchor constraintEqualToAnchor:content.topAnchor],
			[_overlay.bottomAnchor constraintEqualToAnchor:content.bottomAnchor],
			[_overlay.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
			[_overlay.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],
			[overlayStack.centerYAnchor constraintEqualToAnchor:_overlay.contentView.centerYAnchor],
			[overlayStack.leadingAnchor constraintEqualToAnchor:_overlay.contentView.layoutMarginsGuide.leadingAnchor constant:16],
			[overlayStack.trailingAnchor constraintEqualToAnchor:_overlay.contentView.layoutMarginsGuide.trailingAnchor constant:-16],
		]];
	}

	return self;
}

- (void)refreshCellContentsWithSpecifier:(PSSpecifier *)specifier {
	[super refreshCellContentsWithSpecifier:specifier];
	self.textLabel.text = nil;

	NSDictionary *profile = [specifier propertyForKey:@"profile"];
	NSString *username = profile[MenzenProfileUsernameKey];
	NSString *globalName = profile[MenzenProfileGlobalNameKey];
	_nameLabel.text = globalName.length ? globalName : username;
	_usernameLabel.text = username ? [@"@" stringByAppendingString:username] : nil;

	NSString *tag = profile[MenzenProfileGuildTagKey];
	_tagChip.hidden = !tag.length;
	_tagLabel.text = tag;
	_tagBadgeView.hidden = !profile[MenzenProfileGuildTagBadgeURLKey];
	MenzenSetImage(_tagBadgeView, profile[MenzenProfileGuildTagBadgeURLKey]);

	NSArray *badges = MenzenBadgeDescriptions(profile);
	_badgesLabel.hidden = !badges.count;
	_badgesLabel.attributedText = badges.count ? MenzenBadgesText(badges) : nil;

	NSNumber *accentColor = profile[MenzenProfileAccentColorKey];
	// Without a banner or accent color, Discord shows its own color.
	_bannerView.backgroundColor = accentColor ? MenzenColorFromRGB(accentColor.unsignedIntValue) : MenzenBlurple();
	MenzenSetImage(_bannerView, profile[MenzenProfileBannerURLKey]);
	MenzenSetImage(_avatarView, profile[MenzenProfileAvatarURLKey]);
	MenzenSetImage(_decorationView, profile[MenzenProfileAvatarDecorationURLKey]);

	UIColor *statusColor = MenzenStatusColor(profile[MenzenProfileStatusKey]);
	_statusView.hidden = !statusColor;
	_statusView.backgroundColor = statusColor;

	_nameColors = profile[MenzenProfileNameColorsKey];
	[self updateNameColor];

	_activityView.activity = [specifier propertyForKey:@"activity"];

	NSString *overlay = [specifier propertyForKey:@"overlay"];
	_overlay.hidden = !overlay;
	_overlayLabel.text = overlay;
	BOOL busy = [[specifier propertyForKey:@"overlayBusy"] boolValue];
	_overlayIcon.hidden = busy;
	if (busy) {
		_overlaySpinner.hidden = NO;
		[_overlaySpinner startAnimating];
	} else {
		[_overlaySpinner stopAnimating];
		_overlaySpinner.hidden = YES;
	}
}

- (void)updateNameColor {
	_nameLabel.textColor = MenzenNameColor(_nameColors, _nameLabel.bounds.size);
}

- (void)layoutSubviews {
	[super layoutSubviews];
	if (_nameColors.count > 1) [self updateNameColor];
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
	[super traitCollectionDidChange:previousTraitCollection];
	_statusView.layer.borderColor = UIColor.secondarySystemGroupedBackgroundColor.CGColor;
}

@end
