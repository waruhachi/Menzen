#import <Preferences/PSSpecifier.h>

#import "MenzenSegmentCell.h"

@implementation MenzenSegmentCell {
	UISegmentedControl *_control;
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier specifier:(PSSpecifier *)specifier {
	if ((self = [super initWithStyle:style reuseIdentifier:reuseIdentifier specifier:specifier])) {
		self.selectionStyle = UITableViewCellSelectionStyleNone;
		self.backgroundColor = UIColor.clearColor;
		_control = [UISegmentedControl new];
		_control.translatesAutoresizingMaskIntoConstraints = NO;
		[_control addTarget:self action:@selector(selectionChanged) forControlEvents:UIControlEventValueChanged];
		[self.contentView addSubview:_control];
		UILayoutGuide *margins = self.contentView.layoutMarginsGuide;
		[NSLayoutConstraint activateConstraints:@[
			[_control.leadingAnchor constraintEqualToAnchor:margins.leadingAnchor],
			[_control.trailingAnchor constraintEqualToAnchor:margins.trailingAnchor],
			[_control.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
		]];
	}

	return self;
}

- (void)refreshCellContentsWithSpecifier:(PSSpecifier *)specifier {
	[super refreshCellContentsWithSpecifier:specifier];
	self.textLabel.text = nil;
	[_control removeAllSegments];
	NSArray<NSString *> *titles = [specifier propertyForKey:@"titles"];
	for (NSString *title in titles) [_control insertSegmentWithTitle:title atIndex:_control.numberOfSegments animated:NO];
	_control.selectedSegmentIndex = [[specifier propertyForKey:@"selectedIndex"] integerValue];
}

- (void)selectionChanged {
	id target = self.specifier.target;
	if ([target conformsToProtocol:@protocol(MenzenSegmentCellTarget)]) [target segmentCell:self didSelectIndex:_control.selectedSegmentIndex];
}

@end
