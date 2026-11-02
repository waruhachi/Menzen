#import <Preferences/PSListController.h>

// Custom Activity: its switch and the presets, each opening its page
// (MZPresetListController), plus a way to add one.
@interface MZCustomListController : PSListController
@end

// One preset's fields, from the specifier's "presetIdentifier" property.
@interface MZPresetListController : PSListController
@end
