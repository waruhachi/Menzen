#import <UIKit/UIKit.h>

#import "MZDestructiveButtonCell.h"

@implementation MZDestructiveButtonCell

- (void)layoutSubviews {
	[super layoutSubviews];
	self.textLabel.textColor = self.isUserInteractionEnabled ? UIColor.systemRedColor : UIColor.tertiaryLabelColor;
}

@end
