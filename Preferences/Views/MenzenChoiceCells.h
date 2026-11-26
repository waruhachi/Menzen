#import <Preferences/PSTableCell.h>

// The system's row height on iOS 26, like the switches'.
FOUNDATION_EXPORT CGFloat const MenzenChoiceRowHeight;

@interface MenzenCheckCell : PSTableCell
@end

// The current choice is in "choice", not "value", which Preferences sets itself
// when the setting is written.
@interface MenzenChoiceCell : PSTableCell
@end
