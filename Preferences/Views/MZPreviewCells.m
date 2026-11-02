#import <Preferences/PSSpecifier.h>

#import "../../Shared/MZService.h"
#import "../Helpers/MZDiscordColors.h"
#import "../Helpers/MZImageLoader.h"
#import "MZActivityView.h"
#import "MZPreviewCells.h"

static CGFloat const MZMemberAvatarSize = 40;
static CGFloat const MZMemberStatusSize = 14;

@implementation MZCardPreviewCell {
	MZActivityView *_activityView;
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier specifier:(PSSpecifier *)specifier {
	if ((self = [super initWithStyle:style reuseIdentifier:reuseIdentifier specifier:specifier])) {
		self.selectionStyle = UITableViewCellSelectionStyleNone;
		_activityView = [MZActivityView new];
		_activityView.translatesAutoresizingMaskIntoConstraints = NO;
		[self.contentView addSubview:_activityView];
		UILayoutGuide *margins = self.contentView.layoutMarginsGuide;
		NSLayoutConstraint *bottom = [_activityView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-16];
		bottom.priority = UILayoutPriorityDefaultHigh;
		[NSLayoutConstraint activateConstraints:@[
			[_activityView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:16],
			[_activityView.leadingAnchor constraintEqualToAnchor:margins.leadingAnchor],
			[_activityView.trailingAnchor constraintEqualToAnchor:margins.trailingAnchor],
			bottom,
		]];
	}

	return self;
}

- (void)refreshCellContentsWithSpecifier:(PSSpecifier *)specifier {
	[super refreshCellContentsWithSpecifier:specifier];
	self.textLabel.text = nil;
	_activityView.activity = [specifier propertyForKey:@"activity"];
}

@end

@implementation MZMemberPreviewCell {
	UIImageView *_nameplateView;
	UIImageView *_avatarView;
	UIImageView *_decorationView;
	UIView *_statusView;
	UILabel *_nameLabel;
	UIView *_tagChip;
	UIImageView *_tagBadgeView;
	UILabel *_tagLabel;
	UILabel *_activityLabel;
	NSArray<NSNumber *> *_nameColors;
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier specifier:(PSSpecifier *)specifier {
	if ((self = [super initWithStyle:style reuseIdentifier:reuseIdentifier specifier:specifier])) {
		self.selectionStyle = UITableViewCellSelectionStyleNone;

		// Static frame, filling the row like Discord's.
		_nameplateView = [UIImageView new];
		_nameplateView.contentMode = UIViewContentModeScaleAspectFill;
		_nameplateView.clipsToBounds = YES;
		_nameplateView.layer.cornerRadius = 8;

		_avatarView = [UIImageView new];
		_avatarView.contentMode = UIViewContentModeScaleAspectFill;
		_avatarView.clipsToBounds = YES;
		_avatarView.layer.cornerRadius = MZMemberAvatarSize / 2;
		_avatarView.backgroundColor = UIColor.tertiarySystemFillColor;

		_decorationView = [UIImageView new];
		_decorationView.contentMode = UIViewContentModeScaleAspectFit;

		_statusView = [UIView new];
		_statusView.layer.cornerRadius = MZMemberStatusSize / 2;
		_statusView.layer.borderWidth = 3;

		_nameLabel = [UILabel new];
		UIFontDescriptor *body = [UIFontDescriptor preferredFontDescriptorWithTextStyle:UIFontTextStyleBody];
		_nameLabel.font = [UIFont fontWithDescriptor:[body fontDescriptorWithSymbolicTraits:UIFontDescriptorTraitBold] size:0];
		[_nameLabel setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];

		_tagBadgeView = [UIImageView new];
		_tagBadgeView.contentMode = UIViewContentModeScaleAspectFit;
		_tagLabel = [UILabel new];
		UIFontDescriptor *caption = [UIFontDescriptor preferredFontDescriptorWithTextStyle:UIFontTextStyleCaption1];
		_tagLabel.font = [UIFont fontWithDescriptor:[caption fontDescriptorWithSymbolicTraits:UIFontDescriptorTraitBold] size:0];
		UIStackView *tagStack = [[UIStackView alloc] initWithArrangedSubviews:@[_tagBadgeView, _tagLabel]];
		tagStack.spacing = 3;
		tagStack.alignment = UIStackViewAlignmentCenter;
		tagStack.translatesAutoresizingMaskIntoConstraints = NO;
		_tagChip = [UIView new];
		_tagChip.backgroundColor = UIColor.tertiarySystemFillColor;
		_tagChip.layer.cornerRadius = 4;
		[_tagChip addSubview:tagStack];
		[_tagChip setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];

		UIStackView *nameRow = [[UIStackView alloc] initWithArrangedSubviews:@[_nameLabel, _tagChip]];
		nameRow.spacing = 6;
		nameRow.alignment = UIStackViewAlignmentCenter;

		_activityLabel = [UILabel new];

		UIStackView *text = [[UIStackView alloc] initWithArrangedSubviews:@[nameRow, _activityLabel]];
		text.axis = UILayoutConstraintAxisVertical;
		text.alignment = UIStackViewAlignmentLeading;
		text.spacing = 1;

		for (UIView *view in @[_nameplateView, _avatarView, _decorationView, _statusView, text]) {
			view.translatesAutoresizingMaskIntoConstraints = NO;
			[self.contentView addSubview:view];
		}
		UILayoutGuide *margins = self.contentView.layoutMarginsGuide;
		[NSLayoutConstraint activateConstraints:@[
			[_nameplateView.leadingAnchor constraintEqualToAnchor:margins.leadingAnchor],
			[_nameplateView.trailingAnchor constraintEqualToAnchor:margins.trailingAnchor],
			[_nameplateView.topAnchor constraintEqualToAnchor:_avatarView.topAnchor constant:-8],
			[_nameplateView.bottomAnchor constraintEqualToAnchor:_avatarView.bottomAnchor constant:8],
			[_avatarView.widthAnchor constraintEqualToConstant:MZMemberAvatarSize],
			[_avatarView.heightAnchor constraintEqualToConstant:MZMemberAvatarSize],
			[_avatarView.leadingAnchor constraintEqualToAnchor:margins.leadingAnchor constant:10],
			[_avatarView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:14],
			[_avatarView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-14],
			[_decorationView.centerXAnchor constraintEqualToAnchor:_avatarView.centerXAnchor],
			[_decorationView.centerYAnchor constraintEqualToAnchor:_avatarView.centerYAnchor],
			[_decorationView.widthAnchor constraintEqualToConstant:MZMemberAvatarSize * 1.2],
			[_decorationView.heightAnchor constraintEqualToConstant:MZMemberAvatarSize * 1.2],
			[_statusView.widthAnchor constraintEqualToConstant:MZMemberStatusSize],
			[_statusView.heightAnchor constraintEqualToConstant:MZMemberStatusSize],
			[_statusView.centerXAnchor constraintEqualToAnchor:_avatarView.centerXAnchor constant:MZMemberAvatarSize / 2 * M_SQRT1_2],
			[_statusView.centerYAnchor constraintEqualToAnchor:_avatarView.centerYAnchor constant:MZMemberAvatarSize / 2 * M_SQRT1_2],
			[tagStack.topAnchor constraintEqualToAnchor:_tagChip.topAnchor constant:2],
			[tagStack.bottomAnchor constraintEqualToAnchor:_tagChip.bottomAnchor constant:-2],
			[tagStack.leadingAnchor constraintEqualToAnchor:_tagChip.leadingAnchor constant:4],
			[tagStack.trailingAnchor constraintEqualToAnchor:_tagChip.trailingAnchor constant:-4],
			[_tagBadgeView.widthAnchor constraintEqualToConstant:14],
			[_tagBadgeView.heightAnchor constraintEqualToConstant:14],
			[text.leadingAnchor constraintEqualToAnchor:_avatarView.trailingAnchor constant:12],
			[text.trailingAnchor constraintLessThanOrEqualToAnchor:margins.trailingAnchor constant:-10],
			[nameRow.trailingAnchor constraintLessThanOrEqualToAnchor:text.trailingAnchor],
			[text.centerYAnchor constraintEqualToAnchor:_avatarView.centerYAnchor],
		]];
	}

	return self;
}

- (void)layoutSubviews {
	[super layoutSubviews];
	// Cuts the status out of the avatar, in the cell's colour.
	UIColor *background = self.backgroundColor ?: UIColor.secondarySystemGroupedBackgroundColor;
	_statusView.layer.borderColor = [background resolvedColorWithTraitCollection:self.traitCollection].CGColor;
	if (_nameColors.count > 1) _nameLabel.textColor = MZNameColor(_nameColors, _nameLabel.bounds.size);
}

- (void)refreshCellContentsWithSpecifier:(PSSpecifier *)specifier {
	[super refreshCellContentsWithSpecifier:specifier];
	self.textLabel.text = nil;

	NSDictionary *profile = [specifier propertyForKey:@"profile"];
	NSString *globalName = profile[MZProfileGlobalNameKey];
	NSString *username = profile[MZProfileUsernameKey];
	_nameLabel.text = globalName.length ? globalName : (username.length ? username : @"You");
	_nameColors = profile[MZProfileNameColorsKey];
	_nameLabel.textColor = MZNameColor(_nameColors, _nameLabel.bounds.size);
	[self setNeedsLayout];

	NSString *tag = profile[MZProfileGuildTagKey];
	_tagChip.hidden = !tag.length;
	_tagLabel.text = tag;
	_tagBadgeView.hidden = !profile[MZProfileGuildTagBadgeURLKey];
	MZSetImage(_tagBadgeView, profile[MZProfileGuildTagBadgeURLKey]);

	MZSetImage(_avatarView, profile[MZProfileAvatarURLKey]);
	MZSetImage(_decorationView, profile[MZProfileAvatarDecorationURLKey]);
	MZSetImage(_nameplateView, profile[MZProfileNameplateURLKey]);
	UIColor *statusColor = MZStatusColor(profile[MZProfileStatusKey]);
	_statusView.hidden = !statusColor;
	_statusView.backgroundColor = statusColor;

	// Discord shows the activity's icon and the line picked by its status
	// display type.
	NSDictionary *activity = [specifier propertyForKey:@"activity"];
	NSString *display = activity[MZActivityStatusDisplayKey];
	NSString *line = activity[MZActivityDetailsKey];
	if ([display isEqualToString:@"state"]) line = activity[MZActivityStateKey];
	if ([display isEqualToString:@"name"]) line = [activity[MZActivityNameKey] length] ? activity[MZActivityNameKey] : @"Menzen";
	UIFont *font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
	UIImage *icon = [UIImage systemImageNamed:MZActivitySymbolName(activity[MZActivityKindKey]) withConfiguration:[UIImageSymbolConfiguration configurationWithFont:font]];
	NSMutableAttributedString *text = [NSMutableAttributedString new];
	if (icon) {
		NSTextAttachment *attachment = [NSTextAttachment new];
		attachment.image = [icon imageWithTintColor:MZStatusColor(@"online") renderingMode:UIImageRenderingModeAlwaysOriginal];
		[text appendAttributedString:[NSAttributedString attributedStringWithAttachment:attachment]];
	}

	[text appendAttributedString:[[NSAttributedString alloc] initWithString:[@" " stringByAppendingString:line ?: @""] attributes:@{NSFontAttributeName: font, NSForegroundColorAttributeName: UIColor.secondaryLabelColor}]];
	_activityLabel.attributedText = text;
}

@end
