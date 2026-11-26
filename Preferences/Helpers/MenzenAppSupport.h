#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, MenzenSupportState) {
	MenzenSupportStateNotHooked,
	MenzenSupportStateNotChecked,
	// Checked in the background, which found something missing that may
	// only load once the app is open.
	MenzenSupportStateNotFullyChecked,
	MenzenSupportStateWorks,
	MenzenSupportStateMayNotWork,
};

FOUNDATION_EXPORT MenzenSupportState MenzenSupportStateFor(NSDictionary *provider, NSDictionary *status, NSSet<NSString *> *hooked);
FOUNDATION_EXPORT NSString *MenzenInstalledVersion(NSDictionary *provider);
FOUNDATION_EXPORT NSArray<NSString *> *MenzenMissingParts(NSDictionary *status);
