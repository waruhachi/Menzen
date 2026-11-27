#import <UIKit/UIKit.h>

#import "../../Shared/MenzenCustomActivity.h"
#import "../../Shared/MenzenLocalization/MenzenLocalization.h"
#import "MenzenImageCheck.h"

static NSTimeInterval const MenzenImageCheckTimeout = 15;

// A button's link only has to load; an image's has to be one Discord shows.
static void MenzenCheckLinkFor(NSString *link, BOOL image, void (^completion)(NSString *problem)) {
	void (^finish)(NSString *) = ^(NSString *problem) {
		dispatch_async(dispatch_get_main_queue(), ^{
			completion(problem);
		});
	};

	if (!MenzenCustomURLIsAllowed(link)) {
		finish(MenzenLocalizedString(@"image.the_link_has_to_start_with", @"The link has to start with https:// and can't contain a token, key or password."));
		return;
	}

	NSURLSessionConfiguration *configuration = NSURLSessionConfiguration.ephemeralSessionConfiguration;
	configuration.timeoutIntervalForRequest = MenzenImageCheckTimeout;
	configuration.timeoutIntervalForResource = MenzenImageCheckTimeout;
	NSURLSession *session = [NSURLSession sessionWithConfiguration:configuration];
	[[session dataTaskWithURL:[NSURL URLWithString:link] completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
		[session finishTasksAndInvalidate];

		if (error) {
			finish([NSString stringWithFormat:MenzenLocalizedString(@"image.it_couldn_t_be_loaded_x", @"It couldn't be loaded: %@"), error.localizedDescription]);
			return;
		}

		NSInteger status = [response isKindOfClass:NSHTTPURLResponse.class] ? ((NSHTTPURLResponse *)response).statusCode : 0;

		if (status < 200 || status >= 300) {
			finish([NSString stringWithFormat:MenzenLocalizedString(@"image.the_server_answered_with_error_x", @"The server answered with error %ld."), (long)status]);
			return;
		}

		if (!image) {
			finish(nil);
			return;
		}

		NSString *type = response.MIMEType.lowercaseString ?: @"";

		if (![type hasPrefix:@"image/"]) {
			finish(MenzenLocalizedString(@"image.the_link_isn_t_an_image", @"The link isn't an image. Use the image's own link, not the page it's on."));
			return;
		}

		if (![@[@"image/png", @"image/jpeg", @"image/jpg", @"image/gif", @"image/webp", @"image/avif"] containsObject:type]) {
			finish(MenzenLocalizedString(@"image.discord_only_shows_png_jpeg_gif", @"Discord only shows PNG, JPEG, GIF, WebP and AVIF images."));
			return;
		}

		// WebP decodes on iOS 14 and later, AVIF only from iOS 16; before
		// that, Discord can still show it.
		BOOL decodable = ![type isEqualToString:@"image/avif"];
		if (@available(iOS 16, *)) decodable = YES;

		finish(!decodable || [UIImage imageWithData:data] ? nil : MenzenLocalizedString(@"image.the_image_couldn_t_be_read", @"The image couldn't be read."));
	}] resume];
}

void MenzenCheckImageLink(NSString *link, void (^completion)(NSString *problem)) {
	MenzenCheckLinkFor(link, YES, completion);
}

void MenzenCheckButtonLink(NSString *link, void (^completion)(NSString *problem)) {
	MenzenCheckLinkFor(link, NO, completion);
}

void MenzenCheckPresetLinks(NSDictionary *preset, void (^completion)(NSArray<NSString *> *problems, BOOL onlyImages)) {
	NSArray<NSArray<NSString *> *> *links = @[
		@[MenzenPresetLargeImageKey, MenzenLocalizedString(@"image.big_picture", @"Big picture")],
		@[MenzenPresetSmallImageKey, MenzenLocalizedString(@"image.small_picture", @"Small picture")],
		@[MenzenPresetButton1LinkKey, MenzenLocalizedString(@"custom.button_1", @"Button 1")],
		@[MenzenPresetButton2LinkKey, MenzenLocalizedString(@"custom.button_2", @"Button 2")],
	];
	NSMutableArray<NSString *> *problems = [NSMutableArray array];
	__block BOOL onlyImages = YES;
	dispatch_group_t group = dispatch_group_create();

	for (NSArray<NSString *> *link in links) {
		NSString *value = MenzenPresetString(preset, link.firstObject);
		if (!value) continue;

		BOOL image = [link.firstObject isEqualToString:MenzenPresetLargeImageKey] || [link.firstObject isEqualToString:MenzenPresetSmallImageKey];

		dispatch_group_enter(group);
		MenzenCheckLinkFor(value, image, ^(NSString *problem) {
			if (problem) {
				[problems addObject:[NSString stringWithFormat:@"%@: %@", link[1], problem]];
				if (!image) onlyImages = NO;
			}

			dispatch_group_leave(group);
		});
	}

	dispatch_group_notify(group, dispatch_get_main_queue(), ^{
		[problems sortUsingSelector:@selector(compare:)];
		completion(problems, onlyImages);
	});
}
