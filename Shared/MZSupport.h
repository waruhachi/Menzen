#import <Foundation/Foundation.h>

// What MZProviderCheck found, kept in the app's data container for the
// settings pane.

#define MZIssuesURL @"https://github.com/waruhachi/Menzen/issues"

#define MZSupportStatusPath @"Library/Application Support/moe.waru.menzen/status.plist"

// "<version> (<build>)".
#define MZSupportAppVersionKey @"appVersion"
#define MZSupportMenzenVersionKey @"menzenVersion"
#define MZSupportCheckedKey @"checked"
#define MZSupportMissingKey @"missing"
#define MZSupportMissingOptionalKey @"missingOptional"
#define MZSupportWorkedVersionKey @"workedVersion"
#define MZSupportWorkedKey @"worked"
#define MZSupportAlertedVersionKey @"alertedVersion"
// Set when menzend launched the app in the background to check it: some
// parts only load once the app is open, so missing ones aren't final.
#define MZSupportBackgroundKey @"background"

// Followed by the app's bundle ID.
#define MZSupportCheckedNotificationPrefix "moe.waru.menzen.checked."

NS_ASSUME_NONNULL_BEGIN

// Just the version when the build is the same or missing.
static inline NSString *MZSupportVersion(NSString *_Nullable version, NSString *_Nullable build) {
	if (![version isKindOfClass:NSString.class] || !version.length) version = @"?";
	return [build isKindOfClass:NSString.class] && build.length && ![build isEqualToString:version] ? [NSString stringWithFormat:@"%@ (%@)", version, build] : version;
}

static inline NSString *MZSupportDetails(NSString *app, NSString *version, NSString *bundleIdentifier, NSString *menzenVersion, NSString *systemVersion, NSArray<NSString *> *missing) {
	return [NSString stringWithFormat:@"App: %@ %@ (%@)\nMenzen: %@\niOS: %@\nMissing:\n%@", app, version, bundleIdentifier, menzenVersion, systemVersion, [missing componentsJoinedByString:@"\n"]];
}

static inline NSURL *MZSupportReportURL(NSString *app, NSString *version, NSString *details) {
	NSURLComponents *components = [NSURLComponents componentsWithString:[MZIssuesURL stringByAppendingString:@"/new"]];
	components.queryItems = @[
		[NSURLQueryItem queryItemWithName:@"title" value:[NSString stringWithFormat:@"%@ %@: missing parts", app, version]],
		[NSURLQueryItem queryItemWithName:@"body" value:[NSString stringWithFormat:@"```\n%@\n```\n", details]],
	];
	return components.URL ?: [NSURL URLWithString:MZIssuesURL];
}

// The repository's catalog workflow adds the requested app to the list.
static inline NSURL *MZAppRequestURL(NSString *bundleIdentifier) {
	NSURLComponents *components = [NSURLComponents componentsWithString:[MZIssuesURL stringByAppendingString:@"/new"]];
	components.queryItems = @[
		[NSURLQueryItem queryItemWithName:@"template" value:@"app-request.yml"],
		[NSURLQueryItem queryItemWithName:@"app" value:bundleIdentifier],
	];
	return components.URL ?: [NSURL URLWithString:MZIssuesURL];
}

NS_ASSUME_NONNULL_END
