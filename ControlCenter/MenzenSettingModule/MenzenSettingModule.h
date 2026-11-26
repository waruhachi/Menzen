#import <ControlCenterUIKit/CCUIToggleModule.h>

// CCSupport loads each subclass from its own bundle.
@interface MenzenSettingModule : CCUIToggleModule
@property (class, nonatomic, readonly) NSString *settingKey;
@property (class, nonatomic, readonly) BOOL settingDefault;
@end
