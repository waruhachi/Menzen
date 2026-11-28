#import <roothide.h>

#import "../Shared/MenzenConnectedApps.h"
#import "../Shared/MenzenLocalization/MenzenLocalization.h"

@interface BBSectionIconVariant : NSObject
+ (instancetype)variantWithFormat:(NSInteger)format imageData:(NSData *)imageData;
@end

@interface BBSectionIcon : NSObject
- (void)addVariant:(BBSectionIconVariant *)variant;
@end

@interface BBAction : NSObject
+ (instancetype)actionWithLaunchURL:(NSURL *)url;
@end

@interface BBBulletin : NSObject
@property (nonatomic, copy) NSString *header;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *message;
@property (nonatomic, copy) NSString *sectionID;
@property (nonatomic, copy) NSString *bulletinID;
@property (nonatomic, copy) NSString *recordID;
@property (nonatomic, copy) NSString *publisherBulletinID;
@property (nonatomic, copy) NSString *threadID;
@property (nonatomic, retain) NSDate *date;
@property (nonatomic, copy) BBSectionIcon *icon;
@property (nonatomic, copy) BBAction *defaultAction;
@property (nonatomic) BOOL clearable;
@property (nonatomic) BOOL showsMessagePreview;
@end

@interface BBServer : NSObject
- (void)publishBulletin:(BBBulletin *)bulletin destinations:(NSUInteger)destinations;
- (void)_sendRemoveBulletin:(BBBulletin *)bulletin toFeeds:(NSUInteger)feeds shouldSync:(BOOL)shouldSync;
@end

// Shown under Settings, whose notifications are on by default, with Menzen's
// name and icon.
static NSString *const MenzenRequestSection = @"com.apple.Preferences";
static NSString *const MenzenRequestPrefix = @"moe.waru.menzen.connected.";
// Lock screen, Notification Center, banner and sound.
static NSUInteger const MenzenRequestDestinations = 15;
// Every feed, as BBServer removes its own bulletins.
static NSUInteger const MenzenRequestFeeds = 0x3dff;

static BBServer *MenzenBulletinServer;
static dispatch_queue_t MenzenBulletinQueue;
// The bulletin ID of the request shown for each app, used only on
// MenzenBulletinQueue. Lost on a respring, while Notification Center keeps
// the request.
static NSMutableDictionary<NSString *, NSString *> *MenzenRequestBulletinIDs;
static NSDate *MenzenRequestsShownUntil;
// Set once SpringBoard has launched: before then, BulletinBoard drops what's
// published.
static BOOL MenzenRequestsReady;

// Shuffle moves tweak panes into its own Tweaks page and turns root=Menzen
// into root=Tweaks&path=Menzen, so there the page has to go in the root.
static NSURL *MenzenConnectedPageURL(void) {
	BOOL shuffle = [NSFileManager.defaultManager fileExistsAtPath:jbroot(@"/Library/MobileSubstrate/DynamicLibraries/shuffle.dylib")];
	return [NSURL URLWithString:shuffle ? @"prefs:root=Menzen/connected" : @"prefs:root=Menzen&path=connected"];
}

static BBSectionIcon *MenzenIcon(void) {
	static BBSectionIcon *icon;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		NSData *data = [NSData dataWithContentsOfFile:jbroot(@"/Library/PreferenceBundles/MenzenPreferences.bundle/icon@3x.png")];
		if (!data) return;

		icon = [%c(BBSectionIcon) new];
		[icon addVariant:[%c(BBSectionIconVariant) variantWithFormat:0 imageData:data]];
	});

	return icon;
}

// BBServer lets go of a bulletin once it's shown, so the removal is a new
// one with the same IDs.
static void MenzenRemoveRequestBulletin(NSString *identifier, NSString *bulletinID) {
	if ([MenzenRequestBulletinIDs[identifier] isEqualToString:bulletinID]) [MenzenRequestBulletinIDs removeObjectForKey:identifier];
	BBBulletin *bulletin = [%c(BBBulletin) new];
	bulletin.sectionID = MenzenRequestSection;
	bulletin.bulletinID = bulletinID;
	bulletin.recordID = [MenzenRequestPrefix stringByAppendingString:identifier];
	bulletin.publisherBulletinID = bulletinID;

	[MenzenBulletinServer _sendRemoveBulletin:bulletin toFeeds:MenzenRequestFeeds shouldSync:NO];
}

static void MenzenWithdrawRequest(NSString *identifier) {
	dispatch_async(MenzenBulletinQueue, ^{
		NSString *bulletinID = MenzenRequestBulletinIDs[identifier];
		if (bulletinID) MenzenRemoveRequestBulletin(identifier, bulletinID);
	});
}

static void MenzenShowRequest(NSString *identifier, NSString *name) {
	BBBulletin *bulletin = [%c(BBBulletin) new];
	NSString *recordID = [MenzenRequestPrefix stringByAppendingString:identifier];
	// A new ID each time, so a request shown again opens Connected Apps again;
	// the app's identifier comes before the slash.
	NSString *bulletinID = [NSString stringWithFormat:@"%@/%@", recordID, NSUUID.UUID.UUIDString];

	bulletin.sectionID = MenzenRequestSection;
	bulletin.bulletinID = bulletinID;
	bulletin.recordID = recordID;
	bulletin.publisherBulletinID = bulletinID;
	bulletin.threadID = @"moe.waru.menzen.connected";
	bulletin.header = @"Menzen";
	bulletin.title = [NSString stringWithFormat:MenzenLocalizedString(@"connected.x_wants_to_show_activity", @"%@ wants to show activity"), name];
	bulletin.message = MenzenLocalizedString(@"connected.tap_to_allow_it_in_connected_apps", @"Tap to allow it in Connected Apps.");
	bulletin.date = NSDate.date;
	bulletin.icon = MenzenIcon();
	bulletin.clearable = YES;
	bulletin.showsMessagePreview = YES;
	bulletin.defaultAction = [%c(BBAction) actionWithLaunchURL:MenzenConnectedPageURL()];

	dispatch_async(MenzenBulletinQueue, ^{
		NSString *previous = MenzenRequestBulletinIDs[identifier];
		if (previous) MenzenRemoveRequestBulletin(identifier, previous);
		MenzenRequestBulletinIDs[identifier] = bulletinID;
		[MenzenBulletinServer publishBulletin:bulletin destinations:MenzenRequestDestinations];
	});
}

static void MenzenShowRequests(void) {
	if (!MenzenRequestsReady || !MenzenBulletinServer) return;

	MenzenSettingsSynchronize();
	NSArray *requests = MenzenSettingValue(MenzenSettingConnectedRequests);
	if (![requests isKindOfClass:NSArray.class]) return;

	NSArray *allowed = MenzenConnectedAllowed();
	NSDate *latest = MenzenRequestsShownUntil;

	for (NSDictionary *request in requests) {
		if (![request isKindOfClass:NSDictionary.class]) continue;

		NSString *identifier = request[MenzenConnectedRequestIdentifierKey];
		NSString *appName = MenzenConnectedName(request[MenzenConnectedRequestNameKey]);
		NSDate *date = request[MenzenConnectedRequestDateKey];
		if (![date isKindOfClass:NSDate.class] || [date compare:MenzenRequestsShownUntil] != NSOrderedDescending) continue;

		latest = [date laterDate:latest];
		if (!MenzenConnectedIdentifierIsValid(identifier) || !appName || [allowed containsObject:identifier]) continue;

		MenzenShowRequest(identifier, appName);
	}

	MenzenRequestsShownUntil = latest;
}

static void MenzenRequestsChanged(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef info) {
	MenzenShowRequests();
}

static void MenzenSettingsChanged(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef info) {
	if (!MenzenBulletinServer) return;

	MenzenSettingsSynchronize();
	for (NSString *identifier in MenzenConnectedAllowed()) MenzenWithdrawRequest(identifier);
}

%hook BBServer

- (id)initWithQueue:(dispatch_queue_t)queue dataProviderManager:(id)dataProviderManager syncService:(id)syncService dismissalSyncCache:(id)dismissalSyncCache observerListener:(id)observerListener conduitListener:(id)conduitListener settingsListener:(id)settingsListener {
	self = %orig;

	if (self) {
		MenzenBulletinServer = self;
		MenzenBulletinQueue = queue;
	}

	return self;
}

%end

%hook SpringBoard

- (void)applicationDidFinishLaunching:(id)application {
	%orig;
	MenzenRequestsReady = YES;
	MenzenShowRequests();
}

%end

%ctor {
	MenzenRequestsShownUntil = NSDate.date;
	MenzenRequestBulletinIDs = [NSMutableDictionary dictionary];
	CFNotificationCenterRef center = CFNotificationCenterGetDarwinNotifyCenter();
	CFNotificationCenterAddObserver(center, NULL, MenzenRequestsChanged, CFSTR(MenzenConnectedRequestNotification), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
	CFNotificationCenterAddObserver(center, NULL, MenzenSettingsChanged, CFSTR(MenzenSettingsChangedNotification), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
	// menzend changes the allowed list.
	CFNotificationCenterAddObserver(center, NULL, MenzenSettingsChanged, CFSTR(MenzenConnectedAppsChangedNotification), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
}
