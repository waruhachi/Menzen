#import <objc/runtime.h>

#import "MenzenToggleViewController.h"

// Control Center sets every glyph as a template, tinted in one color. As the
// button view's glyph view, this sets it as drawn while the button is selected.
@interface MenzenGlyphImageView : UIImageView
@end

@implementation MenzenGlyphImageView

- (void)setImage:(UIImage *)image {
	UIView *button = self.superview;
	if ([button isKindOfClass:UIControl.class] && ((UIControl *)button).selected) image = [image imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
	[super setImage:image];
}

@end

@implementation MenzenToggleViewController

// The button view makes its glyph view with the first image, before the first
// layout. It has no getter before iOS 26.
- (UIImageView *)glyphImageView {
	UIControl *button = self.buttonView;
	Ivar ivar = class_getInstanceVariable(object_getClass(button), "_glyphImageView");
	id view = ivar ? object_getIvar(button, ivar) : nil;
	return [view isKindOfClass:UIImageView.class] ? view : nil;
}

- (void)viewDidLayoutSubviews {
	[super viewDidLayoutSubviews];
	UIImageView *glyphView = self.glyphImageView;
	if ([glyphView isMemberOfClass:UIImageView.class]) {
		object_setClass(glyphView, MenzenGlyphImageView.class);
		// Through the subclass, for the image already there.
		glyphView.image = glyphView.image;
	}
}

@end
