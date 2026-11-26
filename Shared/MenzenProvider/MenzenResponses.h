#import <Foundation/Foundation.h>

// For apps that keep what they play in Swift values the runtime can't read:
// the same data comes from their API responses.

// matches runs on the app's threads as requests are made, so it should only
// look at the URL.
FOUNDATION_EXPORT void MenzenObserveResponses(BOOL (^matches)(NSURL *url), void (^handler)(NSURL *url, NSData *body));

FOUNDATION_EXPORT void MenzenModifyRequests(NSURLRequest * (^modify)(NSURLRequest *request));

static inline id MenzenJSON(NSData *body) {
	return [NSJSONSerialization JSONObjectWithData:body options:0 error:nil];
}

static inline void MenzenEachDictionaryAt(id object, NSUInteger depth, void (^visit)(NSDictionary *dictionary)) {
	if (depth > 16) return;
	if ([object isKindOfClass:NSDictionary.class]) {
		visit(object);
		for (id child in [object allValues]) {
			if ([child isKindOfClass:NSDictionary.class] || [child isKindOfClass:NSArray.class]) MenzenEachDictionaryAt(child, depth + 1, visit);
		}
	} else if ([object isKindOfClass:NSArray.class]) {
		for (id child in object) MenzenEachDictionaryAt(child, depth + 1, visit);
	}
}

static inline void MenzenEachDictionary(id object, void (^visit)(NSDictionary *dictionary)) {
	MenzenEachDictionaryAt(object, 0, visit);
}
