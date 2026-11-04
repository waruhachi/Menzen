#import <UIKit/UIKit.h>

#import "MenzenDestructiveButtonCell.h"

@implementation MenzenDestructiveButtonCell

- (void)layoutSubviews {
	[super layoutSubviews];
	self.textLabel.textColor = self.isUserInteractionEnabled ? UIColor.systemRedColor : UIColor.tertiaryLabelColor;
}

@end
