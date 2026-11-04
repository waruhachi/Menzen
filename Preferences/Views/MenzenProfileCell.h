#import <Preferences/PSTableCell.h>

// The signed-in Discord account like Discord's profile: banner, avatar,
// names, badges and the activity card, from the specifier's "profile" and
// "activity" properties (MenzenProfile*Key and MenzenActivity*Key in
// Shared/MenzenService.h). An "overlay" message covers it, with a spinner when
// "overlayBusy" is set.
@interface MenzenProfileCell : PSTableCell
@end
