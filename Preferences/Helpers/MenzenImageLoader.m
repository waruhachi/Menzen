#import <objc/runtime.h>

#import "../../Shared/MenzenCustomActivity.h"
#import "../../Shared/MenzenService.h"
#import "MenzenImageLoader.h"

// The CDN URL of the Discord application's art asset named key (Apelin's
// logo), from the application's public asset list. Main thread only.
static void MenzenLoadAssetURL(NSString *key, void (^completion)(NSString *urlString)) {
	static NSDictionary<NSString *, NSString *> *assets;
	if (assets) {
		completion(assets[key]);
		return;
	}

	NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"https://discord.com/api/v10/oauth2/applications/%llu/assets", MenzenApplicationId]];
	[[NSURLSession.sharedSession dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
		id list = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
		NSMutableDictionary *found = [NSMutableDictionary dictionary];
		NSCharacterSet *nonDigits = NSCharacterSet.decimalDigitCharacterSet.invertedSet;
		for (NSDictionary *asset in [list isKindOfClass:NSArray.class] ? list : nil) {
			if (![asset isKindOfClass:NSDictionary.class]) continue;
			NSString *name = asset[@"name"];
			NSString *identifier = asset[@"id"];
			if (![name isKindOfClass:NSString.class] || ![identifier isKindOfClass:NSString.class] || !identifier.length || [identifier rangeOfCharacterFromSet:nonDigits].location != NSNotFound) continue;
			found[name] = [NSString stringWithFormat:@"https://cdn.discordapp.com/app-assets/%llu/%@.png", MenzenApplicationId, identifier];
		}
		dispatch_async(dispatch_get_main_queue(), ^{
			if (found.count) assets = found;
			completion(found[key]);
		});
	}] resume];
}

void MenzenLoadImage(NSString *urlString, void (^completion)(UIImage *image)) {
	// Anything but a URL is an art asset's key.
	if (urlString && ![urlString containsString:@":"]) {
		MenzenLoadAssetURL(urlString, ^(NSString *assetURL) {
			if (assetURL) MenzenLoadImage(assetURL, completion);
			else completion(nil);
		});
		return;
	}

	static NSCache<NSString *, UIImage *> *cache;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		cache = [NSCache new];
	});

	NSURL *url = MenzenCustomImageURLIsAllowed(urlString) ? [NSURL URLWithString:urlString] : nil;
	if (!url) {
		completion(nil);
		return;
	}

	UIImage *cached = [cache objectForKey:urlString];
	if (cached) {
		completion(cached);
		return;
	}

	[[NSURLSession.sharedSession dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
		UIImage *image = data ? [UIImage imageWithData:data] : nil;
		if (image) [cache setObject:image forKey:urlString];
		dispatch_async(dispatch_get_main_queue(), ^{
			completion(image);
		});
	}] resume];
}

void MenzenSetImage(UIImageView *imageView, NSString *urlString) {
	static char key;
	if ([objc_getAssociatedObject(imageView, &key) isEqual:urlString] && (imageView.image || !urlString)) return;
	objc_setAssociatedObject(imageView, &key, urlString, OBJC_ASSOCIATION_COPY_NONATOMIC);
	imageView.image = nil;
	__weak UIImageView *weakImageView = imageView;
	MenzenLoadImage(urlString, ^(UIImage *image) {
		UIImageView *strongImageView = weakImageView;
		if (strongImageView && [objc_getAssociatedObject(strongImageView, &key) isEqual:urlString]) strongImageView.image = image;
	});
}
