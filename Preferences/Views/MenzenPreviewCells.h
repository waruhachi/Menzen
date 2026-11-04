#import <Preferences/PSTableCell.h>

// The activity card as Discord shows it, from the specifier's "activity"
// (MenzenActivity*Key in Shared/MenzenService.h).
@interface MenzenCardPreviewCell : PSTableCell
@end

// A member list row like Discord's, from the specifier's "profile" and
// "activity": avatar with its decoration and status, the name in its colors
// with the server tag, and the activity under it, all over the nameplate.
@interface MenzenMemberPreviewCell : PSTableCell
@end
