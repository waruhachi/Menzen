#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

// 0xRRGGBB, as Discord's API gives colors.
FOUNDATION_EXPORT UIColor *MZColorFromRGB(uint32_t rgb);
FOUNDATION_EXPORT UIColor *MZBlurple(void);
// Discord's color for an MZProfileStatusKey value; nil when there's none.
FOUNDATION_EXPORT UIColor *_Nullable MZStatusColor(NSString *_Nullable status);
// A name's color from MZProfileNameColorsKey: one is solid, more make a left
// to right gradient the size of the label.
FOUNDATION_EXPORT UIColor *MZNameColor(NSArray<NSNumber *> *_Nullable colors, CGSize size);
// The SF Symbol Discord's icon for an activity kind (MZActivityKindKey)
// looks like.
FOUNDATION_EXPORT NSString *MZActivitySymbolName(NSString *_Nullable kind);

NS_ASSUME_NONNULL_END
