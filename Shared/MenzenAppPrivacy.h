#import <Foundation/Foundation.h>

#import "MenzenApps.h"
#import "MenzenProviders.h"
#import "MenzenSettings.h"

// The app the Control Center module switches Privacy Mode for; empty or
// missing for every app.
#define MenzenSettingPrivacyModuleApp @"privacyModuleApp"

static inline NSArray<NSArray<NSString *> *> *MenzenInstalledProviderApps(void) {
	NSMutableArray<NSArray<NSString *> *> *apps = [NSMutableArray array];
	LSApplicationWorkspace *workspace = MenzenWorkspace();

	for (NSDictionary *provider in MenzenProviders()) {
		NSString *bundleIdentifier = provider[MenzenProviderBundleIdentifierKey];
		if ([workspace applicationIsInstalled:bundleIdentifier]) [apps addObject:@[bundleIdentifier, provider[MenzenProviderNameKey]]];
	}

	[apps sortUsingComparator:^NSComparisonResult(NSArray<NSString *> *a, NSArray<NSString *> *b) {
		return [a[1] localizedCaseInsensitiveCompare:b[1]];
	}];

	return apps;
}

static inline NSString *MenzenPrivacyModuleApp(void) {
	NSString *app = MenzenSettingString(MenzenSettingPrivacyModuleApp, nil);
	return app.length ? app : nil;
}

static inline NSString *MenzenPrivacyModuleKey(void) {
	NSString *app = MenzenPrivacyModuleApp();
	return app ? [MenzenSettingPrivatePrefix stringByAppendingString:app] : MenzenSettingPrivacy;
}
