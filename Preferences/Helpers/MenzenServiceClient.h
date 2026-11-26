#import <Foundation/Foundation.h>

#import "../../Shared/MenzenService.h"

FOUNDATION_EXPORT NSNotificationName const MenzenStatusDidChangeNotification;

FOUNDATION_EXPORT id<MenzenService> MenzenServiceProxy(void (^errorHandler)(void));

FOUNDATION_EXPORT void MenzenFetchStatus(void (^completion)(NSDictionary<NSString *, id> *status));
