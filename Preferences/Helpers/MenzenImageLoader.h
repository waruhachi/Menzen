#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

// Loads and caches images over https, only from Discord's CDN and the cover
// art servers of the apps menzen supports. The URLs come from the daemon, but
// there's no reason for this pane to load anything else. urlString can
// also be the key of one of the Discord application's art assets.
FOUNDATION_EXPORT void MenzenLoadImage(NSString *_Nullable urlString, void (^completion)(UIImage *_Nullable image));

// Shows urlString in imageView once loaded, unless it was asked for
// something else since. nil clears it.
FOUNDATION_EXPORT void MenzenSetImage(UIImageView *imageView, NSString *_Nullable urlString);

NS_ASSUME_NONNULL_END
