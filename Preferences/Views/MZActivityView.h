#import <UIKit/UIKit.h>

// The activity card on the user's Discord profile, from an activity
// dictionary (MZActivity*Key in Shared/MZService.h), or a note that nothing
// is showing when there's none.
@interface MZActivityView : UIView
@property (nonatomic, copy, nullable) NSDictionary<NSString *, id> *activity;
@end
