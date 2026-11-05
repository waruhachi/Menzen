#import <UIKit/UIKit.h>

@interface CCUIButtonModuleViewController : UIViewController
- (UIControl *)buttonView;
@end

@interface CCUIToggleViewController : CCUIButtonModuleViewController
@end

// Keeps the selected glyph's colors. The module turns the plain
// CCUIToggleViewController it gets into this subclass, which adds no storage.
@interface MenzenToggleViewController : CCUIToggleViewController
@end
