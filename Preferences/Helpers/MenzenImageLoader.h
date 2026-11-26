#import <UIKit/UIKit.h>

FOUNDATION_EXPORT void MenzenLoadImage(NSString *urlString, void (^completion)(UIImage *image));

FOUNDATION_EXPORT void MenzenSetImage(UIImageView *imageView, NSString *urlString);
