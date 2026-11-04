#import <Preferences/PSSpecifier.h>

#import "../Helpers/MenzenImageLoader.h"
#import "MenzenLogoCell.h"

static CGFloat const MenzenLogoSize = 44;
static CGFloat const MenzenLogoPadding = 8;

CGFloat const MenzenLogoCellHeight = MenzenLogoSize + 2 * MenzenLogoPadding;

@implementation MenzenLogoCell {
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
			[_logoView.widthAnchor constraintEqualToConstant:MenzenLogoSize],
			[_logoView.heightAnchor constraintEqualToConstant:MenzenLogoSize],
			[row.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:MenzenLogoPadding],
			[row.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-MenzenLogoPadding],
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
	MenzenSetImage(_logoView, [specifier propertyForKey:@"logo"]);
}

@end
