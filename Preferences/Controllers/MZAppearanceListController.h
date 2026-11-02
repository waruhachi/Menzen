#import <Preferences/PSListController.h>

// A page with a preview at the top (identifier "preview") that follows
// menzend's status and the page's settings.
@interface MZPreviewListController : PSListController
@property (nonatomic, readonly, nullable) NSDictionary<NSString *, id> *status;
- (nonnull PSSpecifier *)previewSpecifier;
@end

// The activity card's settings, under a preview of the card.
@interface MZCardListController : MZPreviewListController
@end

// What shows next to the name in member lists, under a preview of the row.
@interface MZMemberListController : MZPreviewListController
@end
