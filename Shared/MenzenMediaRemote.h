#import <Foundation/Foundation.h>

// Resolved with dlsym, so a symbol missing on some iOS version doesn't keep
// menzend from loading.
typedef void (*MRMediaRemoteRegisterForNowPlayingNotificationsFn)(dispatch_queue_t queue);
typedef void (*MRMediaRemoteGetNowPlayingInfoFn)(dispatch_queue_t queue, void (^completion)(CFDictionaryRef info));
typedef void (*MRMediaRemoteGetNowPlayingApplicationIsPlayingFn)(dispatch_queue_t queue, void (^completion)(Boolean isPlaying));
typedef void (*MRMediaRemoteGetNowPlayingClientFn)(dispatch_queue_t queue, void (^completion)(id client));
typedef CFStringRef (*MRNowPlayingClientGetStringFn)(id client);

#define MenzenMediaRemotePath "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote"
