#import <UIKit/UIKit.h>

FOUNDATION_EXPORT UIColor *MenzenColorFromRGB(uint32_t rgb);
FOUNDATION_EXPORT UIColor *MenzenBlurple(void);
FOUNDATION_EXPORT UIColor *MenzenStatusColor(NSString *status);
FOUNDATION_EXPORT UIColor *MenzenNameColor(NSArray<NSNumber *> *colors, CGSize size);
FOUNDATION_EXPORT NSString *MenzenActivitySymbolName(NSString *kind);
