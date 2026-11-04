#import <Preferences/PSListController.h>

// Custom Activity: its switch and the presets, each opening its page
// (MenzenPresetListController), plus a way to add one.
@interface MenzenCustomListController : PSListController
@end

// One preset's fields, from the specifier's "presetIdentifier" property.
@interface MenzenPresetListController : PSListController
@end
