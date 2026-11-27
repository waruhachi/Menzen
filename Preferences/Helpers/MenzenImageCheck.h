#import <Foundation/Foundation.h>

FOUNDATION_EXPORT void MenzenCheckImageLink(NSString *link, void (^completion)(NSString *problem));

FOUNDATION_EXPORT void MenzenCheckButtonLink(NSString *link, void (^completion)(NSString *problem));

FOUNDATION_EXPORT void MenzenCheckPresetLinks(NSDictionary *preset, void (^completion)(NSArray<NSString *> *problems, BOOL onlyImages));
