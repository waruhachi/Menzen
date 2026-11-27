#import <ControlCenterUIKit/CCUIContentModule-Protocol.h>
#import <UIKit/UIKit.h>

@interface CCUIButtonModuleViewController : UIViewController
@property (nonatomic, strong) UIImage *glyphImage;
@property (nonatomic, strong) UIImage *selectedGlyphImage;
@property (nonatomic, getter=isSelected) BOOL selected;
@property (nonatomic, getter=isExpanded) BOOL expanded;
- (UIControl *)buttonView;
- (void)buttonTapped:(id)button forEvent:(UIEvent *)event;
@end

@interface CCUIMenuModuleViewController : CCUIButtonModuleViewController
- (void)addActionWithTitle:(NSString *)title glyph:(UIImage *)glyph handler:(BOOL (^)(void))handler;
- (void)removeAllActions;
@end

@interface MenzenAppPrivacyViewController : CCUIMenuModuleViewController
// The chosen app's icon is the glyph, drawn in its own colors.
@property (nonatomic, readonly) BOOL showsAppIcon;
@end

@interface MenzenAppPrivacyModule : NSObject <CCUIContentModule>
@end
