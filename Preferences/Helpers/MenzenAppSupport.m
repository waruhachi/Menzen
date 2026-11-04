#import "../../Shared/MenzenApps.h"
#import "../../Shared/MenzenProviders.h"
#import "MenzenAppSupport.h"

NSString *MenzenInstalledVersion(NSDictionary *provider) {
	return MenzenInstalledAppVersion(provider[MenzenProviderBundleIdentifierKey]) ?: @"?";
}

NSArray<NSString *> *MenzenMissingParts(NSDictionary *status) {
	NSArray *list = status[MenzenSupportMissingKey];
	if (![list isKindOfClass:NSArray.class]) return @[];
	return [list filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"self isKindOfClass: %@", NSString.class]];
}

MenzenSupportState MenzenSupportStateFor(NSDictionary *provider, NSDictionary *status, NSSet<NSString *> *hooked) {
	if (![hooked containsObject:provider[MenzenProviderBundleIdentifierKey]]) return MenzenSupportStateNotHooked;
	if (!MenzenStatusIsCurrent(status, MenzenInstalledVersion(provider))) return MenzenSupportStateNotChecked;
	if (!MenzenMissingParts(status).count) return MenzenSupportStateWorks;
	return [status[MenzenSupportBackgroundKey] boolValue] ? MenzenSupportStateNotFullyChecked : MenzenSupportStateMayNotWork;
}
