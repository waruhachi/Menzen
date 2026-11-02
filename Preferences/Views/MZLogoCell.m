#import <Preferences/PSSpecifier.h>

#import "../Helpers/MZImageLoader.h"
#import "MZLogoCell.h"

static CGFloat const MZLogoSize = 44;
static CGFloat const MZLogoPadding = 8;

CGFloat const MZLogoCellHeight = MZLogoSize + 2 * MZLogoPadding;

@implementation MZLogoCell {
	UIImageView *_logoView;
	UILabel *_titleLabel;
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier specifier:(PSSpecifier *)specifier {
	if ((self = [super initWithStyle:style reuseIdentifier:reuseIdentifier specifier:specifier])) {
		_logoView = [UIImageView new];
		_logoView.contentMode = UIViewContentModeScaleAspectFill;
		_logoView.clipsToBounds = YES;
		_logoView.layer.cornerRadius = 8;
		_logoView.backgroundColor = UIColor.tertiarySystemFillColor;
		_titleLabel = [UILabel new];
		_titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
		UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[_logoView, _titleLabel]];
		row.spacing = 12;
		row.alignment = UIStackViewAlignmentCenter;
		row.translatesAutoresizingMaskIntoConstraints = NO;
		[self.contentView addSubview:row];
		UILayoutGuide *margins = self.contentView.layoutMarginsGuide;
		[NSLayoutConstraint activateConstraints:@[
			[_logoView.widthAnchor constraintEqualToConstant:MZLogoSize],
			[_logoView.heightAnchor constraintEqualToConstant:MZLogoSize],
			[row.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:MZLogoPadding],
			[row.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-MZLogoPadding],
			[row.leadingAnchor constraintEqualToAnchor:margins.leadingAnchor],
			[row.trailingAnchor constraintLessThanOrEqualToAnchor:margins.trailingAnchor],
		]];
	}

	return self;
}

- (void)refreshCellContentsWithSpecifier:(PSSpecifier *)specifier {
	[super refreshCellContentsWithSpecifier:specifier];
	self.textLabel.text = nil;
	_titleLabel.text = specifier.name;
	_titleLabel.textColor = UIColor.labelColor;
	MZSetImage(_logoView, [specifier propertyForKey:@"logo"]);
}

@end
