#import "Calculator18Prefs.h"
#import "Calculator18Log.h"
#include <roothide.h>
#include <notify.h>

uint64_t C18ReadState(const char *name, int *token) {
	if (*token == NOTIFY_TOKEN_INVALID && notify_register_check(name, token) != NOTIFY_STATUS_OK) return 0;
	uint64_t state = 0;
	notify_get_state(*token, &state);
	return state;
}

BOOL C18PrefEnabled(void) {
	static int token = NOTIFY_TOKEN_INVALID;
	return C18ReadState(C18_ENABLED_STATE, &token) != C18EnabledStateOff;
}

BOOL C18PrefStartupScientific(void) {
	static int token = NOTIFY_TOKEN_INVALID;
	return C18ReadState(C18_STARTUP_MODE_STATE, &token) == C18StartupModeStateScientific;
}

BOOL C18PrefQuickSwitch(void) {
	static int token = NOTIFY_TOKEN_INVALID;
	return C18ReadState(C18_QUICK_SWITCH_STATE, &token) == 1;
}

C18HapticState C18PrefHaptic(void) {
	static int token = NOTIFY_TOKEN_INVALID;
	uint64_t state = C18ReadState(C18_HAPTIC_STATE, &token);
	return state <= C18HapticStateHeavy ? (C18HapticState)state : C18HapticStateOff;
}

// Switch cells store numbers.
BOOL C18PrefBool(NSDictionary *prefs, NSString *key, BOOL fallback) {
	id value = prefs[key];
	return [value isKindOfClass:[NSNumber class]] || [value isKindOfClass:[NSString class]] ? [value boolValue] : fallback;
}

@implementation C18Prefs

+ (NSString *)path {
	return jbroot([NSString stringWithFormat:@"/var/mobile/Library/Preferences/%@.plist", C18_PREFS_DOMAIN]);
}

+ (NSDictionary *)load {
	return [NSDictionary dictionaryWithContentsOfFile:[self path]] ?: @{};
}

+ (void)setObject:(id)value forKey:(NSString *)key {
	NSMutableDictionary *prefs = [[self load] mutableCopy];
	if (value) prefs[key] = value;
	else [prefs removeObjectForKey:key];
	NSString *path = [self path];
	[[NSFileManager defaultManager] createDirectoryAtPath:[path stringByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:nil error:NULL];
	if (![prefs writeToFile:path atomically:YES]) C18Log(@"couldn't write preferences to %@", path);
	notify_post(C18_PREFS_CHANGED);
}

@end

#pragma mark - SpringBoard

// notifyd drops a name's state once nobody is registered for it, so the tokens stay open for SpringBoard's
// lifetime (a Calculator that starts later would read 0).
static void C18PublishState(const char *name, uint64_t value) {
	static NSMutableDictionary<NSString *, NSNumber *> *tokens;
	if (!tokens) tokens = [NSMutableDictionary dictionary];
	NSString *key = @(name);
	NSNumber *token = tokens[key];
	if (!token) {
		int newToken = NOTIFY_TOKEN_INVALID;
		if (notify_register_check(name, &newToken) != NOTIFY_STATUS_OK) return;
		token = @(newToken);
		tokens[key] = token;
	}
	notify_set_state(token.intValue, value);
}

static void C18ReloadSettings(void) {
	NSDictionary *prefs = [C18Prefs load];
	BOOL enabled = C18PrefBool(prefs, C18_KEY_ENABLED, C18_DEFAULT_ENABLED);
	BOOL quickSwitch = C18PrefBool(prefs, C18_KEY_QUICK_SWITCH, C18_DEFAULT_QUICK_SWITCH);
	BOOL haptic = C18PrefBool(prefs, C18_KEY_HAPTIC, C18_DEFAULT_HAPTIC);
	NSString *strength = prefs[C18_KEY_HAPTIC_STRENGTH];
	NSUInteger strengthIndex = [@[@"selection", @"soft", @"light", @"medium", @"heavy"] indexOfObject:[strength isKindOfClass:[NSString class]] ? strength : C18_DEFAULT_HAPTIC_STRENGTH];
	if (strengthIndex == NSNotFound) strengthIndex = C18HapticStateLight - 1;
	BOOL debug = C18PrefBool(prefs, C18_KEY_DEBUG, C18_DEFAULT_DEBUG);
	id mode = prefs[C18_KEY_STARTUP_MODE];
	if (![mode isKindOfClass:[NSString class]]) mode = C18_DEFAULT_STARTUP_MODE;
	BOOL scientific = [mode isEqualToString:@"scientific"];
	C18PublishState(C18_ENABLED_STATE, enabled ? C18EnabledStateOn : C18EnabledStateOff);
	C18PublishState(C18_STARTUP_MODE_STATE, scientific ? C18StartupModeStateScientific : C18StartupModeStateBasic);
	C18PublishState(C18_QUICK_SWITCH_STATE, quickSwitch);
	C18PublishState(C18_HAPTIC_STATE, haptic ? strengthIndex + 1 : C18HapticStateOff);
	C18PublishState(C18_DEBUG_STATE, debug);
	C18Log(@"settings: %s, startup %@, quick switch %s, haptic %llu (0 = off)", enabled ? "enabled" : "disabled", scientific ? @"scientific" : @"basic", quickSwitch ? "on" : "off", haptic ? (unsigned long long)strengthIndex + 1 : 0ULL);
}

void C18PublishPrefs(void) {
	C18ReloadSettings();
	static int token;
	notify_register_dispatch(C18_PREFS_CHANGED, &token, dispatch_get_main_queue(), ^(int t) {
		C18ReloadSettings();
	});
}
