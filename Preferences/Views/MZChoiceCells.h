#import <Preferences/PSTableCell.h>

// The system's row height on iOS 26, like the switches'.
FOUNDATION_EXPORT CGFloat const MZChoiceRowHeight;

// A choice with a checkmark when the specifier's "checked" is set, greyed out
// when its "enabled" is NO.
@interface MZCheckCell : PSTableCell
@end

// A setting picked from a menu. The specifier's "choices" are [value, title]
// pairs and "choice" the current one (not "value", which Preferences sets
// itself when the setting is written); values in "disabledValues" are greyed
// out. Picking one sets the specifier's setting through its target.
@interface MZChoiceCell : PSTableCell
@end
