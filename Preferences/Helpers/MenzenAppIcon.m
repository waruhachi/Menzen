#import <UIKit/UIKit.h>

#import "MenzenAppIcon.h"

@interface UIImage (MenzenPrivate)
+ (UIImage *)_applicationIconImageForBundleIdentifier:(NSString *)bundleIdentifier format:(int)format scale:(CGFloat)scale;
@end

void MenzenSetAppIcon(PSSpecifier *specifier, NSString *bundleIdentifier) {
	UIImage *icon = [UIImage _applicationIconImageForBundleIdentifier:bundleIdentifier format:0 scale:UIScreen.mainScreen.scale];
	if (icon) [specifier setProperty:icon forKey:@"iconImage"];
}
