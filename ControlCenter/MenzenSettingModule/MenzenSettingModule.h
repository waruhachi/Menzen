#import <ControlCenterUIKit/CCUIToggleModule.h>

// A Control Center toggle for one of Menzen's BOOL settings. CCSupport loads
// each subclass from its own bundle; the toggle changes the same setting as
// the switch in Settings.
@interface MenzenSettingModule : CCUIToggleModule
// The MenzenSettings.h key and its default; subclasses override both.
@property (class, nonatomic, readonly) NSString *settingKey;
@property (class, nonatomic, readonly) BOOL settingDefault;
@end
