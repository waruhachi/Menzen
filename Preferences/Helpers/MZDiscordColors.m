#import "MZDiscordColors.h"

UIColor *MZColorFromRGB(uint32_t rgb) {
	return [UIColor colorWithRed:((rgb >> 16) & 0xFF) / 255.0 green:((rgb >> 8) & 0xFF) / 255.0 blue:(rgb & 0xFF) / 255.0 alpha:1];
}

UIColor *MZBlurple(void) {
	return MZColorFromRGB(0x5865F2);
}

UIColor *MZStatusColor(NSString *status) {
	if ([status isEqualToString:@"online"]) return MZColorFromRGB(0x23A55A);
	if ([status isEqualToString:@"idle"]) return MZColorFromRGB(0xF0B232);
	if ([status isEqualToString:@"dnd"]) return MZColorFromRGB(0xF23F43);
	if ([status isEqualToString:@"streaming"]) return MZColorFromRGB(0x593695);
	if ([status isEqualToString:@"invisible"] || [status isEqualToString:@"offline"]) return MZColorFromRGB(0x80848E);
	return nil;
}

NSString *MZActivitySymbolName(NSString *kind) {
	if ([kind isEqualToString:@"watching"]) return @"play.tv.fill";
	if ([kind isEqualToString:@"playing"]) return @"gamecontroller.fill";
	return @"music.note";
}

UIColor *MZNameColor(NSArray<NSNumber *> *colors, CGSize size) {
	if (!colors.count) return UIColor.labelColor;
	if (colors.count < 2 || size.width < 1 || size.height < 1) return MZColorFromRGB(colors.firstObject.unsignedIntValue);
	NSMutableArray *cgColors = [NSMutableArray array];
	for (NSNumber *color in colors) [cgColors addObject:(__bridge id)MZColorFromRGB(color.unsignedIntValue).CGColor];
	UIImage *gradient = [[[UIGraphicsImageRenderer alloc] initWithSize:size] imageWithActions:^(UIGraphicsImageRendererContext *context) {
		CGGradientRef cgGradient = CGGradientCreateWithColors(NULL, (__bridge CFArrayRef)cgColors, NULL);
		CGContextDrawLinearGradient(context.CGContext, cgGradient, CGPointZero, CGPointMake(size.width, 0), 0);
		CGGradientRelease(cgGradient);
	}];
	return [UIColor colorWithPatternImage:gradient];
}
