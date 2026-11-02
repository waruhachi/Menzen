#import <Foundation/Foundation.h>

// Debug builds append to /var/mobile/Library/Logs/Menzen/menzend.log under
// the jailbreak's root. Release builds (FINALPACKAGE=1) log nothing: the
// calls and their arguments are compiled out. Never pass tokens.
#ifdef DEBUG
FOUNDATION_EXPORT void MZLog(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);
#else
	#define MZLog(...) ((void)0)
#endif
