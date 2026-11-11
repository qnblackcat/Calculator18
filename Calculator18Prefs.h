#import <Foundation/Foundation.h>

#ifdef __cplusplus
extern "C" {
#endif

// Settings live in one plist inside jbroot instead of going through cfprefsd, which would deny our domain to
// sandboxed processes (same trick as FlicksForAll). Calculator is sandboxed and may not reach the plist, so
// SpringBoard (which always can) publishes the settings as notify states and Calculator reads those.

#define C18_PREFS_DOMAIN @"com.qn.calculator18"
#define C18_PREFS_CHANGED "com.qn.calculator18/ReloadPrefs"

// Keys in the plist
#define C18_KEY_ENABLED @"enabled"
#define C18_KEY_STARTUP_MODE @"startupMode"     // "basic" or "scientific"
#define C18_KEY_QUICK_SWITCH @"quickSwitch"
#define C18_KEY_HAPTIC @"haptic"
#define C18_KEY_HAPTIC_STRENGTH @"hapticStrength"   // "selection", "soft", "light", "medium" or "heavy"
#define C18_KEY_DEBUG @"debug"

// Defaults, also in prefs/Resources/Root.plist: keep both in step
#define C18_DEFAULT_ENABLED YES
#define C18_DEFAULT_STARTUP_MODE @"basic"
#define C18_DEFAULT_QUICK_SWITCH NO
#define C18_DEFAULT_HAPTIC NO
#define C18_DEFAULT_HAPTIC_STRENGTH @"light"
#define C18_DEFAULT_DEBUG NO

// Notify states published by SpringBoard. 0 means "not published (yet)", which counts as the default.
#define C18_ENABLED_STATE "com.qn.calculator18/Enabled"
typedef NS_ENUM(uint64_t, C18EnabledState) {
	C18EnabledStateUnknown = 0,
	C18EnabledStateOn = 1,
	C18EnabledStateOff = 2,
};
#define C18_STARTUP_MODE_STATE "com.qn.calculator18/StartupMode"
typedef NS_ENUM(uint64_t, C18StartupModeState) {
	C18StartupModeStateBasic = 1,   // also what 0 (unknown) means
	C18StartupModeStateScientific = 2,
};
// 1 while the calculator key switches keypads on tap
#define C18_QUICK_SWITCH_STATE "com.qn.calculator18/QuickSwitch"
// 0 while haptic feedback is off, else its strength
#define C18_HAPTIC_STATE "com.qn.calculator18/Haptic"
typedef NS_ENUM(uint64_t, C18HapticState) {
	C18HapticStateOff = 0,
	C18HapticStateSelection = 1,   // UISelectionFeedbackGenerator, the lightest
	C18HapticStateSoft = 2,        // 2...5 are UIImpactFeedbackStyleSoft, Light, Medium and Heavy
	C18HapticStateLight = 3,
	C18HapticStateMedium = 4,
	C18HapticStateHeavy = 5,
};
// 1 while Debug is on
#define C18_DEBUG_STATE "com.qn.calculator18/Debug"

// A notify state, registering name into *token (NOTIFY_TOKEN_INVALID at first) on the first call; 0 if it can't
// be read.
uint64_t C18ReadState(const char *name, int *token);

// What the processes that cannot read the plist ask.
BOOL C18PrefEnabled(void);
BOOL C18PrefStartupScientific(void);
BOOL C18PrefQuickSwitch(void);
C18HapticState C18PrefHaptic(void);

// A stored switch, or fallback when it is missing or not a number.
BOOL C18PrefBool(NSDictionary *prefs, NSString *key, BOOL fallback);

@interface C18Prefs : NSObject
+ (NSString *)path;
+ (NSDictionary *)load;
// Posts C18_PREFS_CHANGED after writing; a nil value removes the key.
+ (void)setObject:(id)value forKey:(NSString *)key;
@end

// SpringBoard: publishes the settings now and every time they change.
void C18PublishPrefs(void);

#ifdef __cplusplus
}
#endif
