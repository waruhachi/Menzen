#import <objc/runtime.h>

#import "MenzenResponses.h"

typedef void (^MenzenCompletionHandler)(NSData *, NSURLResponse *, NSError *);
typedef NSURLRequest * (^MenzenRequestModifier)(NSURLRequest *);

@interface NSURLSession (Private)
- (NSURLSessionDataTask *)_dataTaskWithRequest:(NSURLRequest *)request delegate:(id)delegate completionHandler:(MenzenCompletionHandler)completionHandler;
@end

@interface MenzenResponseObserver : NSObject
@property (nonatomic, copy) BOOL (^matches)(NSURL *);
@property (nonatomic, copy) void (^handler)(NSURL *, NSData *);
@property (nonatomic, strong) dispatch_queue_t queue;
@end

@implementation MenzenResponseObserver
@end

static const NSUInteger MenzenMaxBody = 8 * 1024 * 1024;

// Guarded by @synchronized(delegateClasses).
static NSArray<MenzenResponseObserver *> *observers;
static NSArray<MenzenRequestModifier> *modifiers;
static NSMutableSet<Class> *delegateClasses;

// Weak keys, so finished tasks drop out.
static NSMapTable<NSURLSessionTask *, NSMutableData *> *bodies;

// Set while a hooked method runs on this thread, so the ones it calls
// through to (or a superclass's, called by an override) pass straight
// through.
static __thread BOOL insideSession;
static __thread BOOL insideDelegate;

static NSArray<MenzenResponseObserver *> *MenzenObserversFor(NSURL *url) {
	if (![url.scheme isEqualToString:@"https"]) return nil;

	NSArray<MenzenResponseObserver *> *all;
	@synchronized(delegateClasses) {
		all = observers;
	}

	NSMutableArray *matching = nil;
	for (MenzenResponseObserver *observer in all) {
		if (!observer.matches(url)) continue;
		if (!matching) matching = [NSMutableArray array];
		[matching addObject:observer];
	}

	return matching;
}

static NSURLRequest *MenzenModified(NSURLRequest *request) {
	NSArray *all;
	@synchronized(delegateClasses) {
		all = modifiers;
	}

	for (MenzenRequestModifier modify in all) {
		request = modify(request) ?: request;
	}

	return request;
}

static void MenzenDeliver(NSArray<MenzenResponseObserver *> *matching, NSURL *url, NSData *body, NSURLResponse *response, NSError *error) {
	NSInteger status = [response isKindOfClass:NSHTTPURLResponse.class] ? ((NSHTTPURLResponse *)response).statusCode : 0;
	if (error || status != 200 || ![body isKindOfClass:NSData.class] || !body.length || body.length > MenzenMaxBody) return;

	NSData *copy = [body copy];
	for (MenzenResponseObserver *observer in matching) {
		dispatch_async(observer.queue, ^{
			observer.handler(url, copy);
		});
	}
}

static void MenzenObserveDelegateClass(Class cls);

static void MenzenObserveTask(NSURLSession *session, NSURLSessionTask *task) {
	if (![task isKindOfClass:NSURLSessionDataTask.class] || !session.delegate) return;
	MenzenObserveDelegateClass(object_getClass(session.delegate));
	@synchronized(bodies) {
		[bodies setObject:[NSMutableData data] forKey:task];
	}
}

static MenzenCompletionHandler MenzenObservingHandler(NSURL *url, NSArray<MenzenResponseObserver *> *matching, MenzenCompletionHandler handler) {
	return ^(NSData *data, NSURLResponse *response, NSError *error) {
		MenzenDeliver(matching, url, data, response, error);
		handler(data, response, error);
	};
}

%group Session

%hook NSURLSession

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request completionHandler:(MenzenCompletionHandler)handler {
	if (!insideSession) request = MenzenModified(request);
	NSArray *matching = insideSession ? nil : MenzenObserversFor(request.URL);

	BOOL wasInside = insideSession;
	insideSession = YES;
	NSURLSessionDataTask *task = %orig(request, matching && handler ? MenzenObservingHandler(request.URL, matching, handler) : handler);
	insideSession = wasInside;

	if (matching && !handler) MenzenObserveTask(self, task);
	return task;
}

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request {
	if (!insideSession) request = MenzenModified(request);
	NSArray *matching = insideSession ? nil : MenzenObserversFor(request.URL);

	BOOL wasInside = insideSession;
	insideSession = YES;
	NSURLSessionDataTask *task = %orig(request);
	insideSession = wasInside;

	if (matching) MenzenObserveTask(self, task);
	return task;
}

%end

%end

// What Swift's async data(for:delegate:) calls, from iOS 15.
%group AsyncSession

%hook NSURLSession

- (NSURLSessionDataTask *)_dataTaskWithRequest:(NSURLRequest *)request delegate:(id)delegate completionHandler:(MenzenCompletionHandler)handler {
	if (!insideSession) request = MenzenModified(request);
	NSArray *matching = insideSession || !handler ? nil : MenzenObserversFor(request.URL);

	BOOL wasInside = insideSession;
	insideSession = YES;
	NSURLSessionDataTask *task = %orig(request, delegate, matching ? MenzenObservingHandler(request.URL, matching, handler) : handler);
	insideSession = wasInside;

	return task;
}

%end

%end

// Delegate classes are only known once a session uses them, one hook per
// class, which Logos can't express.
static void MenzenObserveDelegateClass(Class cls) {
	@synchronized(delegateClasses) {
		if (!cls || [delegateClasses containsObject:cls]) return;
		[delegateClasses addObject:cls];
	}

	SEL didReceiveData = @selector(URLSession:dataTask:didReceiveData:);
	SEL didComplete = @selector(URLSession:task:didCompleteWithError:);
	// Without both, the app gets its data some other way.
	if (![cls instancesRespondToSelector:didReceiveData] || ![cls instancesRespondToSelector:didComplete]) return;

	__block void (*origDidReceiveData)(id, SEL, NSURLSession *, NSURLSessionDataTask *, NSData *);
	IMP newDidReceiveData = imp_implementationWithBlock(^(id delegate, NSURLSession *session, NSURLSessionDataTask *task, NSData *data) {
		if (!insideDelegate) {
			@synchronized(bodies) {
				NSMutableData *body = [bodies objectForKey:task];
				if (body && body.length + data.length <= MenzenMaxBody) [body appendData:data];
				else if (body) [bodies removeObjectForKey:task];
			}
		}
		BOOL wasInside = insideDelegate;
		insideDelegate = YES;
		origDidReceiveData(delegate, didReceiveData, session, task, data);
		insideDelegate = wasInside;
	});
	// After the block's copy, so this is the address the block reads.
	MSHookMessageEx(cls, didReceiveData, newDidReceiveData, (IMP *)&origDidReceiveData);

	__block void (*origDidComplete)(id, SEL, NSURLSession *, NSURLSessionTask *, NSError *);
	IMP newDidComplete = imp_implementationWithBlock(^(id delegate, NSURLSession *session, NSURLSessionTask *task, NSError *error) {
		if (!insideDelegate) {
			NSMutableData *body;
			@synchronized(bodies) {
				body = [bodies objectForKey:task];
				[bodies removeObjectForKey:task];
			}
			NSURL *url = task.originalRequest.URL;
			if (body) MenzenDeliver(MenzenObserversFor(url), url, body, task.response, error);
		}
		BOOL wasInside = insideDelegate;
		insideDelegate = YES;
		origDidComplete(delegate, didComplete, session, task, error);
		insideDelegate = wasInside;
	});
	MSHookMessageEx(cls, didComplete, newDidComplete, (IMP *)&origDidComplete);
}

static void MenzenStart(void) {
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		observers = @[];
		modifiers = @[];
		delegateClasses = [NSMutableSet set];
		bodies = [NSMapTable weakToStrongObjectsMapTable];
		%init(Session);
		if ([NSURLSession instancesRespondToSelector:@selector(_dataTaskWithRequest:delegate:completionHandler:)]) %init(AsyncSession);
	});
}

void MenzenObserveResponses(BOOL (^matches)(NSURL *url), void (^handler)(NSURL *url, NSData *body)) {
	MenzenResponseObserver *observer = [MenzenResponseObserver new];
	observer.matches = matches;
	observer.handler = handler;
	observer.queue = dispatch_queue_create("moe.waru.menzen.responses", DISPATCH_QUEUE_SERIAL);

	MenzenStart();
	@synchronized(delegateClasses) {
		observers = [observers arrayByAddingObject:observer];
	}
}

void MenzenModifyRequests(NSURLRequest * (^modify)(NSURLRequest *request)) {
	MenzenStart();
	@synchronized(delegateClasses) {
		modifiers = [modifiers arrayByAddingObject:[modify copy]];
	}
}
