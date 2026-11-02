#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Whether Discord can show the image at link: one it may be sent
// (MZCustomImageURLIsAllowed), that loads, and is a PNG, JPEG, GIF or WebP
// image. problem is nil when it can, else a sentence for the user. Calls
// back on the main queue.
FOUNDATION_EXPORT void MZCheckImageLink(NSString *link, void (^completion)(NSString *_Nullable problem));

// Every filled-in link of the preset, checked together: problems lists one
// line per link that won't work, empty when they all do.
FOUNDATION_EXPORT void MZCheckPresetImages(NSDictionary *preset, void (^completion)(NSArray<NSString *> *problems));

NS_ASSUME_NONNULL_END
