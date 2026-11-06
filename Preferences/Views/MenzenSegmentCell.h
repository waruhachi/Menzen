#import <Preferences/PSTableCell.h>

@protocol MenzenSegmentCellTarget
- (void)segmentCell:(PSTableCell *)cell didSelectIndex:(NSInteger)index;
@end

// A segmented control filling the row, with the specifier's "titles" and the
// "selectedIndex" selected. Picking one tells the specifier's target.
@interface MenzenSegmentCell : PSTableCell
@end
