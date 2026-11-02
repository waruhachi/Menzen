#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>

#import "MZChoiceCells.h"

@implementation MZCheckCell

- (UIColor *)titleColor {
	BOOL enabled = [self.specifier propertyForKey:@"enabled"] ? [[self.specifier propertyForKey:@"enabled"] boolValue] : YES;
	return enabled ? UIColor.labelColor : UIColor.tertiaryLabelColor;
}

- (void)refreshCellContentsWithSpecifier:(PSSpecifier *)specifier {
	[super refreshCellContentsWithSpecifier:specifier];
	self.textLabel.textColor = self.titleColor;
	self.textLabel.textAlignment = NSTextAlignmentNatural;
	self.accessoryType = [[specifier propertyForKey:@"checked"] boolValue] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
}

- (void)layoutSubviews {
	[super layoutSubviews];
	// PSButtonCell colors its title as a button whenever it lays out.
	self.textLabel.textColor = self.titleColor;
}

@end

// iOS 17.4; the project builds against an older SDK.
@interface UIButton (MZPrimaryAction)
- (void)performPrimaryAction;
@end

CGFloat const MZChoiceRowHeight = 52;

@implementation MZChoiceCell {
	UIButton *_button;
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier specifier:(PSSpecifier *)specifier {
	if ((self = [super initWithStyle:style reuseIdentifier:reuseIdentifier specifier:specifier])) {
		self.selectionStyle = UITableViewCellSelectionStyleNone;
		// Just the value, so the menu opens next to it.
		_button = [UIButton buttonWithType:UIButtonTypeSystem];
		_button.showsMenuAsPrimaryAction = YES;
		// The chevron after the title, on the right.
		_button.contentHorizontalAlignment = UIControlContentHorizontalAlignmentRight;
		_button.semanticContentAttribute = UISemanticContentAttributeForceRightToLeft;
		// A gap between the title and the chevron, with room for it.
		_button.contentEdgeInsets = UIEdgeInsetsMake(0, 6, 0, 0);
		_button.titleEdgeInsets = UIEdgeInsetsMake(0, -6, 0, 6);
		_button.titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
		_button.tintColor = UIColor.secondaryLabelColor;
		[_button setImage:[UIImage systemImageNamed:@"chevron.down" withConfiguration:[UIImageSymbolConfiguration configurationWithTextStyle:UIFontTextStyleFootnote]] forState:UIControlStateNormal];
		_button.translatesAutoresizingMaskIntoConstraints = NO;
		[self.contentView addSubview:_button];
		UILayoutGuide *margins = self.contentView.layoutMarginsGuide;
		[NSLayoutConstraint activateConstraints:@[
			[_button.topAnchor constraintEqualToAnchor:self.contentView.topAnchor],
			[_button.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor],
			[_button.trailingAnchor constraintEqualToAnchor:margins.trailingAnchor],
			[self.contentView.heightAnchor constraintGreaterThanOrEqualToConstant:MZChoiceRowHeight],
		]];
		// The rest of the row opens the same menu, where iOS can (17.4).
		[self.contentView addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(openMenu)]];
	}

	return self;
}

- (void)openMenu {
	if (_button.enabled && [_button respondsToSelector:@selector(performPrimaryAction)]) [_button performPrimaryAction];
}

- (void)refreshCellContentsWithSpecifier:(PSSpecifier *)specifier {
	[super refreshCellContentsWithSpecifier:specifier];
	self.detailTextLabel.text = nil;
	BOOL enabled = [specifier propertyForKey:@"enabled"] ? [[specifier propertyForKey:@"enabled"] boolValue] : YES;
	self.textLabel.textColor = enabled ? UIColor.labelColor : UIColor.tertiaryLabelColor;
	_button.enabled = enabled;

	id current = [specifier propertyForKey:@"choice"];
	NSMutableArray *actions = [NSMutableArray array];
	NSString *title;
	__weak PSSpecifier *weakSpecifier = specifier;
	NSArray *disabled = [specifier propertyForKey:@"disabledValues"];
	for (NSArray *choice in [specifier propertyForKey:@"choices"]) {
		id value = choice.firstObject;
		BOOL chosen = [value isEqual:current];
		if (chosen) title = choice[1];
		UIAction *action = [UIAction actionWithTitle:choice[1] image:nil identifier:nil handler:^(UIAction *action) {
			PSSpecifier *strongSpecifier = weakSpecifier;
			[(PSListController *)strongSpecifier.target setPreferenceValue:value specifier:strongSpecifier];
		}];
		action.state = chosen ? UIMenuElementStateOn : UIMenuElementStateOff;
		if ([disabled containsObject:value]) action.attributes = UIMenuElementAttributesDisabled;
		[actions addObject:action];
	}

	_button.menu = [UIMenu menuWithTitle:@"" children:actions];
	// A system button fades a new title in; rows that didn't change shouldn't move.
	[UIView performWithoutAnimation:^{
		[self->_button setTitle:title forState:UIControlStateNormal];
		[self->_button layoutIfNeeded];
	}];
}

@end
