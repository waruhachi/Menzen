#import <UIKit/UIKit.h>

#import "../../Shared/MZCustomActivity.h"
#import "MZImageCheck.h"

static NSTimeInterval const MZImageCheckTimeout = 15;

void MZCheckImageLink(NSString *link, void (^completion)(NSString *problem)) {
	void (^finish)(NSString *) = ^(NSString *problem) {
		dispatch_async(dispatch_get_main_queue(), ^{
			completion(problem);
		});
	};
	if (!MZCustomImageURLIsAllowed(link)) {
		finish(@"The link has to start with https:// and can't contain a token, key or password.");
		return;
	}

	NSURLSessionConfiguration *configuration = NSURLSessionConfiguration.ephemeralSessionConfiguration;
	configuration.timeoutIntervalForRequest = MZImageCheckTimeout;
	configuration.timeoutIntervalForResource = MZImageCheckTimeout;
	NSURLSession *session = [NSURLSession sessionWithConfiguration:configuration];
	[[session dataTaskWithURL:[NSURL URLWithString:link] completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
		[session finishTasksAndInvalidate];
		if (error) {
			finish([NSString stringWithFormat:@"It couldn't be loaded: %@", error.localizedDescription]);
			return;
		}
		NSInteger status = [response isKindOfClass:NSHTTPURLResponse.class] ? ((NSHTTPURLResponse *)response).statusCode : 0;
		if (status < 200 || status >= 300) {
			finish([NSString stringWithFormat:@"The server answered with error %ld.", (long)status]);
			return;
		}
		NSString *type = response.MIMEType.lowercaseString ?: @"";
		if (![type hasPrefix:@"image/"]) {
			finish(@"The link isn't an image. Use the image's own link, not the page it's on.");
			return;
		}
		if (![@[@"image/png", @"image/jpeg", @"image/jpg", @"image/gif", @"image/webp"] containsObject:type]) {
			finish(@"Discord only shows PNG, JPEG, GIF and WebP images.");
			return;
		}
		// WebP only decodes on iOS 14 and later, which is all Menzen runs on.
		finish([UIImage imageWithData:data] ? nil : @"The image couldn't be read.");
	}] resume];
}

void MZCheckPresetImages(NSDictionary *preset, void (^completion)(NSArray<NSString *> *problems)) {
	NSArray<NSArray<NSString *> *> *links = @[@[MZPresetLargeImageKey, @"Big picture"], @[MZPresetSmallImageKey, @"Small picture"]];
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
