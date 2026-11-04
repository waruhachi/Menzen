#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

// 0xRRGGBB, as Discord's API gives colors.
FOUNDATION_EXPORT UIColor *MenzenColorFromRGB(uint32_t rgb);
FOUNDATION_EXPORT UIColor *MenzenBlurple(void);
// Discord's color for an MenzenProfileStatusKey value; nil when there's none.
FOUNDATION_EXPORT UIColor *_Nullable MenzenStatusColor(NSString *_Nullable status);
// A name's color from MenzenProfileNameColorsKey: one is solid, more make a left
// to right gradient the size of the label.
FOUNDATION_EXPORT UIColor *MenzenNameColor(NSArray<NSNumber *> *_Nullable colors, CGSize size);
// The SF Symbol Discord's icon for an activity kind (MenzenActivityKindKey)
// looks like.
FOUNDATION_EXPORT NSString *MenzenActivitySymbolName(NSString *_Nullable kind);

NS_ASSUME_NONNULL_END
