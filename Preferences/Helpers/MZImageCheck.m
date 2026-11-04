#import <UIKit/UIKit.h>

#import "../../Shared/MZCustomActivity.h"
#import "../../Shared/MZLocalization/MZLocalization.h"
#import "MZImageCheck.h"

static NSTimeInterval const MZImageCheckTimeout = 15;

void MZCheckImageLink(NSString *link, void (^completion)(NSString *problem)) {
	void (^finish)(NSString *) = ^(NSString *problem) {
		dispatch_async(dispatch_get_main_queue(), ^{
			completion(problem);
		});
	};
	if (!MZCustomImageURLIsAllowed(link)) {
		finish(MZLocalizedString(@"image.the_link_has_to_start_with", @"The link has to start with https:// and can't contain a token, key or password."));
		return;
	}

	NSURLSessionConfiguration *configuration = NSURLSessionConfiguration.ephemeralSessionConfiguration;
	configuration.timeoutIntervalForRequest = MZImageCheckTimeout;
	configuration.timeoutIntervalForResource = MZImageCheckTimeout;
	NSURLSession *session = [NSURLSession sessionWithConfiguration:configuration];
	[[session dataTaskWithURL:[NSURL URLWithString:link] completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
		[session finishTasksAndInvalidate];
		if (error) {
			finish([NSString stringWithFormat:MZLocalizedString(@"image.it_couldn_t_be_loaded_x", @"It couldn't be loaded: %@"), error.localizedDescription]);
			return;
		}
		NSInteger status = [response isKindOfClass:NSHTTPURLResponse.class] ? ((NSHTTPURLResponse *)response).statusCode : 0;
		if (status < 200 || status >= 300) {
			finish([NSString stringWithFormat:MZLocalizedString(@"image.the_server_answered_with_error_x", @"The server answered with error %ld."), (long)status]);
			return;
		}
		NSString *type = response.MIMEType.lowercaseString ?: @"";
		if (![type hasPrefix:@"image/"]) {
			finish(MZLocalizedString(@"image.the_link_isn_t_an_image", @"The link isn't an image. Use the image's own link, not the page it's on."));
			return;
		}
		if (![@[@"image/png", @"image/jpeg", @"image/jpg", @"image/gif", @"image/webp"] containsObject:type]) {
			finish(MZLocalizedString(@"image.discord_only_shows_png_jpeg_gif", @"Discord only shows PNG, JPEG, GIF and WebP images."));
			return;
		}
		// WebP only decodes on iOS 14 and later, which is all Menzen runs on.
		finish([UIImage imageWithData:data] ? nil : MZLocalizedString(@"image.the_image_couldn_t_be_read", @"The image couldn't be read."));
	}] resume];
}

void MZCheckPresetImages(NSDictionary *preset, void (^completion)(NSArray<NSString *> *problems)) {
	NSArray<NSArray<NSString *> *> *links = @[@[MZPresetLargeImageKey, MZLocalizedString(@"image.big_picture", @"Big picture")], @[MZPresetSmallImageKey, MZLocalizedString(@"image.small_picture", @"Small picture")]];
	NSMutableArray<NSString *> *problems = [NSMutableArray array];
	dispatch_group_t group = dispatch_group_create();
	for (NSArray<NSString *> *link in links) {
		NSString *value = MZPresetString(preset, link.firstObject);
		if (!value) continue;
		dispatch_group_enter(group);
		MZCheckImageLink(value, ^(NSString *problem) {
			if (problem) [problems addObject:[NSString stringWithFormat:@"%@: %@", link[1], problem]];
			dispatch_group_leave(group);
		});
	}

	dispatch_group_notify(group, dispatch_get_main_queue(), ^{
		[problems sortUsingSelector:@selector(compare:)];
		completion(problems);
	});
}
