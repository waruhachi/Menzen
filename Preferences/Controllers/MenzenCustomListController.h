#import "MenzenListController.h"

// Custom Activity: its switch and the presets, each opening its page
// (MenzenPresetListController), plus a way to add one.
@interface MenzenCustomListController : MenzenListController
@end

// One preset's fields, from the specifier's "presetIdentifier" property.
@interface MenzenPresetListController : MenzenListController
@end
