#import "MenzenListController.h"

@interface MenzenPreviewListController : MenzenListController
@property (nonatomic, readonly) NSDictionary<NSString *, id> *status;
- (PSSpecifier *)previewSpecifier;
@end

@interface MenzenCardListController : MenzenPreviewListController
@end

@interface MenzenMemberListController : MenzenPreviewListController
@end
