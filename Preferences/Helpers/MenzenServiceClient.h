#import <Foundation/Foundation.h>

#import "../../Shared/MenzenService.h"

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSNotificationName const MenzenStatusDidChangeNotification;

// menzend's MenzenService, over one connection all of the pane's pages share.
// Replies arrive on the connection's queue; errorHandler runs on the main
// queue when menzend can't be reached.
FOUNDATION_EXPORT id<MenzenService> MenzenServiceProxy(void (^_Nullable errorHandler)(void));

// menzend's status (MenzenStatus*Key), on the main queue; nil when it can't be
// reached.
FOUNDATION_EXPORT void MenzenFetchStatus(void (^completion)(NSDictionary<NSString *, id> *_Nullable status));

NS_ASSUME_NONNULL_END
