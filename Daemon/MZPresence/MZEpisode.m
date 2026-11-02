#import "MZEpisode.h"

BOOL MZFindEpisode(NSString *title, NSInteger *season, NSInteger *episode, NSString **rest) {
	static NSRegularExpression *seasonEpisode, *episodeOnly;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		seasonEpisode = [NSRegularExpression regularExpressionWithPattern:@"\\bS(?:eason)?\\s*(\\d{1,3})\\s*[:.,·|-]?\\s*E(?:p(?:isode)?\\.?)?\\s*(\\d{1,4})\\b" options:NSRegularExpressionCaseInsensitive error:nil];
		episodeOnly = [NSRegularExpression regularExpressionWithPattern:@"\\b(?:Episode|Ep\\.?)\\s*(\\d{1,4})\\b" options:NSRegularExpressionCaseInsensitive error:nil];
	});

	NSRange all = NSMakeRange(0, title.length);
	NSTextCheckingResult *match = [seasonEpisode firstMatchInString:title options:0 range:all];
	if (match) {
		*season = [title substringWithRange:[match rangeAtIndex:1]].integerValue;
		*episode = [title substringWithRange:[match rangeAtIndex:2]].integerValue;
	} else {
		match = [episodeOnly firstMatchInString:title options:0 range:all];
		if (!match) return NO;
		*season = 0;
		*episode = [title substringWithRange:[match rangeAtIndex:1]].integerValue;
	}

	NSRange range = match.range;
	if (range.location > 0 && NSMaxRange(range) < title.length) {
		unichar before = [title characterAtIndex:range.location - 1], after = [title characterAtIndex:NSMaxRange(range)];
		if ((before == '(' && after == ')') || (before == '[' && after == ']')) range = NSMakeRange(range.location - 1, range.length + 2);
	}

	NSCharacterSet *separators = [NSCharacterSet characterSetWithCharactersInString:@" \t-–—:|·,"];
	NSString *before = [[title substringToIndex:range.location] stringByTrimmingCharactersInSet:separators];
	NSString *after = [[title substringFromIndex:NSMaxRange(range)] stringByTrimmingCharactersInSet:separators];
	*rest = title;
	if (!before.length && after.length) *rest = after;
	else if (!after.length && before.length) *rest = before;
	return YES;
}

NSString *MZEpisodeText(NSInteger season, NSInteger episode) {
	if (season > 0 && episode > 0) return [NSString stringWithFormat:@"Season %ld, Episode %ld", (long)season, (long)episode];
	if (episode > 0) return [NSString stringWithFormat:@"Episode %ld", (long)episode];
	if (season > 0) return [NSString stringWithFormat:@"Season %ld", (long)season];
	return nil;
}
