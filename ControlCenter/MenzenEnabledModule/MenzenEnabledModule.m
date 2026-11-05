#import "../../Shared/MenzenSettings.h"
#import "MenzenEnabledModule.h"

@implementation MenzenEnabledModule

+ (NSString *)settingKey {
	return MenzenSettingEnabled;
}

+ (BOOL)settingDefault {
	return YES;
}

@end
