#import "Calculator18RootListController.h"
#import <Preferences/PSSpecifier.h>
#import "../Calculator18Prefs.h"
#import "../Calculator18Log.h"
#include <sys/utsname.h>

#define C18LogCopyMaxBytes (200 * 1024)

@implementation C18RootListController

static BOOL C18IsOurs(PSSpecifier *specifier) {
	return [specifier.properties[@"defaults"] isEqualToString:C18_PREFS_DOMAIN] && specifier.properties[@"key"] != nil;
}

// rows that only matter while the Enabled switch is on
static NSArray<NSString *> *C18DependentRows(void) {
	return @[@"startupMode", @"quickSwitch", @"haptic", @"hapticStrength"];
}

- (void)setRowsEnabled:(BOOL)enabled reload:(BOOL)reload {
	for (NSString *identifier in C18DependentRows()) {
		PSSpecifier *row = [self specifierForID:identifier];
		if (!row) continue;
		// the strength also needs Haptic Feedback itself
		BOOL rowEnabled = enabled;
		if ([identifier isEqualToString:@"hapticStrength"]) rowEnabled = enabled && C18PrefBool([C18Prefs load], C18_KEY_HAPTIC, C18_DEFAULT_HAPTIC);
		[row setProperty:@(rowEnabled) forKey:@"enabled"];
		if (reload) [self reloadSpecifier:row animated:YES];
	}
}

- (NSArray *)specifiers {
	if (!_specifiers) {
		_specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
		[self setRowsEnabled:C18PrefBool([C18Prefs load], C18_KEY_ENABLED, C18_DEFAULT_ENABLED) reload:NO];
	}
	return _specifiers;
}

// Footer notes justified, like the other tweaks. Depending on the iOS version the footer draws through a content
// configuration or the older textLabel, so set both.
- (void)tableView:(UITableView *)tableView willDisplayFooterView:(UIView *)view forSection:(NSInteger)section {
	if ([PSListController instancesRespondToSelector:_cmd]) [super tableView:tableView willDisplayFooterView:view forSection:section];
	if (![view isKindOfClass:[UITableViewHeaderFooterView class]]) return;
	UITableViewHeaderFooterView *footer = (UITableViewHeaderFooterView *)view;
	if ([footer.contentConfiguration isKindOfClass:[UIListContentConfiguration class]]) {
		UIListContentConfiguration *config = [(UIListContentConfiguration *)footer.contentConfiguration copy];
		config.textProperties.alignment = UIListContentTextAlignmentJustified;
		footer.contentConfiguration = config;
	} else {
		footer.textLabel.textAlignment = NSTextAlignmentJustified;
	}
}

- (id)readPreferenceValue:(PSSpecifier *)specifier {
	if (!C18IsOurs(specifier)) return [super readPreferenceValue:specifier];
	return [C18Prefs load][specifier.properties[@"key"]] ?: specifier.properties[@"default"];
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
	if (!C18IsOurs(specifier)) {
		[super setPreferenceValue:value specifier:specifier];
		return;
	}
	NSString *key = specifier.properties[@"key"];
	[C18Prefs setObject:value forKey:key];
	if ([key isEqualToString:C18_KEY_ENABLED]) {
		[self setRowsEnabled:[value boolValue] reload:YES];
	} else if ([key isEqualToString:C18_KEY_HAPTIC]) {
		PSSpecifier *strength = [self specifierForID:@"hapticStrength"];
		[strength setProperty:@([value boolValue] && C18PrefBool([C18Prefs load], C18_KEY_ENABLED, C18_DEFAULT_ENABLED)) forKey:@"enabled"];
		[self reloadSpecifier:strength animated:YES];
	}
}

- (NSString *)tweakVersion:(PSSpecifier *)specifier {
	return @C18_VERSION;
}

- (void)openURLString:(NSString *)string {
	[[UIApplication sharedApplication] openURL:[NSURL URLWithString:string] options:@{} completionHandler:nil];
}

- (void)openSourceCode:(PSSpecifier *)specifier {
	[self openURLString:@"https://github.com/qnblackcat/Calculator18"];
}

- (void)openTwitter:(PSSpecifier *)specifier {
	[self openURLString:@"https://x.com/t70438299"];
}

- (void)showAlertWithTitle:(NSString *)title message:(NSString *)message {
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
	[self presentViewController:alert animated:YES completion:nil];
}

- (void)copyDebugLog {
	NSString *log = C18LogFileRead(C18LogCopyMaxBytes);
	if (!log.length) {
		[self showAlertWithTitle:@"Debug log is empty" message:@"Turn on Debug, then use Calculator."];
		return;
	}
	struct utsname system;
	uname(&system);
	NSString *header = [NSString stringWithFormat:@"Calculator18 debug log, iOS %@, %s\n", [UIDevice currentDevice].systemVersion, system.machine];
	[UIPasteboard generalPasteboard].string = [header stringByAppendingString:log];
	[self showAlertWithTitle:@"Copied" message:[NSString stringWithFormat:@"%lu KB of debug log copied to the clipboard.", (unsigned long)(log.length / 1024 + 1)]];
}

- (void)clearDebugLog {
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Clear debug log?" message:nil preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
	[alert addAction:[UIAlertAction actionWithTitle:@"Clear" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
		C18LogFileClear();
	}]];
	[self presentViewController:alert animated:YES completion:nil];
}

@end
