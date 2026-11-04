#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// How well Menzen fits the installed version of a provider's app, from what
// its provider's check found (Shared/MenzenSupport.h).
typedef NS_ENUM(NSInteger, MenzenSupportState) {
	// No provider hooks it: Menzen shows only what it publishes.
	MenzenSupportStateNotHooked,
	// Its provider hasn't checked this version yet.
	MenzenSupportStateNotChecked,
	// Checked in the background, which found something missing that may
	// only load once the app is open.
	MenzenSupportStateNotFullyChecked,
	MenzenSupportStateWorks,
	// Its provider is missing something it needs in this version.
	MenzenSupportStateMayNotWork,
};

// provider is one of MenzenProviders(); hooked is MenzenHookedBundles().
FOUNDATION_EXPORT MenzenSupportState MenzenSupportStateFor(NSDictionary *provider, NSDictionary *_Nullable status, NSSet<NSString *> *hooked);
// The installed version as the status has it, "?" when it's unknown.
FOUNDATION_EXPORT NSString *MenzenInstalledVersion(NSDictionary *provider);
FOUNDATION_EXPORT NSArray<NSString *> *MenzenMissingParts(NSDictionary *_Nullable status);

NS_ASSUME_NONNULL_END
