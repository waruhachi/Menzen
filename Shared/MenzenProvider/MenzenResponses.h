#import <Foundation/Foundation.h>

// For apps that keep what they play in Swift values the runtime can't read:
// the same data comes from their API responses.

NS_ASSUME_NONNULL_BEGIN

// handler gets each HTTP 200 body (at most 8 MB) for requests matches
// accepts, on a serial queue of its own. matches runs on the app's threads as
// requests are made, so it should only look at the URL. Call once, from the
// provider's %ctor.
FOUNDATION_EXPORT void MenzenObserveResponses(BOOL (^matches)(NSURL *url), void (^handler)(NSURL *url, NSData *body));

// The request modify returns is made instead, and is what
// MenzenObserveResponses sees. Runs on the app's threads. Call once, from the
// provider's %ctor.
FOUNDATION_EXPORT void MenzenModifyRequests(NSURLRequest *_Nullable (^modify)(NSURLRequest *request));

static inline id _Nullable MenzenJSON(NSData *body) {
	return [NSJSONSerialization JSONObjectWithData:body options:0 error:nil];
}

static inline void MenzenEachDictionaryAt(id _Nullable object, NSUInteger depth, void (^visit)(NSDictionary *dictionary)) {
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

// Depth first, at most 16 deep.
static inline void MenzenEachDictionary(id _Nullable object, void (^visit)(NSDictionary *dictionary)) {
	MenzenEachDictionaryAt(object, 0, visit);
}

NS_ASSUME_NONNULL_END
