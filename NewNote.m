#import "Calculator18.h"

// The calculator key's "Open New Note": Notes' "New Note" quick action.

static NSString *const C18NewNoteNotification = @"com.qn.calculator18.newnote";

@protocol C18ShortcutAction
- (instancetype)initWithSBSShortcutItem:(id)item;   // UISHandleApplicationShortcutAction
@end

@interface FBSOpenApplicationOptions : NSObject
+ (instancetype)optionsWithDictionary:(NSDictionary *)dictionary;
@end
@interface FBSOpenApplicationService : NSObject
+ (instancetype)serviceWithDefaultShellEndpoint;
- (void)openApplication:(NSString *)bundleID withOptions:(FBSOpenApplicationOptions *)options completion:(void (^)(id, NSError *))completion;
@end

static void C18OpenNotes(void) {
	[[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"mobilenotes://"] options:@{} completionHandler:nil];
}

// Runs in SpringBoard, which (unlike Calculator) may open an app with a quick action. This is the request
// SpringBoard makes for Notes' "New Note" quick action: the action travels as a BSAction in the launch options.
static void C18OpenNewNoteDirect(void) {
	Class serviceClass = NSClassFromString(@"FBSOpenApplicationService");
	Class optionsClass = NSClassFromString(@"FBSOpenApplicationOptions");
	Class itemClass = NSClassFromString(@"SBSApplicationShortcutItem");
	Class actionClass = NSClassFromString(@"UISHandleApplicationShortcutAction");
	if (!serviceClass || !optionsClass || !itemClass || !actionClass) {
		C18OpenNotes();
		return;
	}

	id item = [[itemClass alloc] init];
	[item setValue:@"com.apple.notes.newNote" forKey:@"type"];
	[item setValue:@"New Note" forKey:@"localizedTitle"];
	id<C18ShortcutAction> action = [actionClass alloc];
	action = [action initWithSBSShortcutItem:item];
	if (!action) {
		C18OpenNotes();
		return;
	}

	FBSOpenApplicationOptions *options = [optionsClass optionsWithDictionary:@{@"__Actions": [NSSet setWithObject:action]}];
	[[serviceClass serviceWithDefaultShellEndpoint] openApplication:@"com.apple.mobilenotes" withOptions:options completion:^(id result, NSError *error) {
		C18Log(@"open Notes shortcut: error=%@", error);
		if (error) dispatch_async(dispatch_get_main_queue(), ^{ C18OpenNotes(); });
	}];
}

// Calculator cannot do that itself, so it asks SpringBoard.
void C18OpenNewNote(void) {
	CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge CFStringRef)C18NewNoteNotification, NULL, NULL, YES);
}

static void C18NewNoteReceived(CFNotificationCenterRef center, void *observer, CFNotificationName name, const void *object, CFDictionaryRef userInfo) {
	dispatch_async(dispatch_get_main_queue(), ^{ C18OpenNewNoteDirect(); });
}

// SpringBoard: opens the note Calculator asks for.
void C18ListenForNewNote(void) {
	CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, C18NewNoteReceived, (__bridge CFStringRef)C18NewNoteNotification, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
}
