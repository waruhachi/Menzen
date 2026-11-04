#import <UIKit/UIKit.h>

// The activity card on the user's Discord profile, from an activity
// dictionary (MenzenActivity*Key in Shared/MenzenService.h), or a note that nothing
// is showing when there's none.
@interface MenzenActivityView : UIView
@property (nonatomic, copy, nullable) NSDictionary<NSString *, id> *activity;
@end
