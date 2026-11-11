#import "Calculator18.h"
#import <substrate.h>
#import <unistd.h>

// While Debug is on, logs the keypad and the display each time the orientation changes, to see how Calculator lays them out.

static void C18DumpKey(UIView *view, int depth) {
	NSInteger identifier = C18KeyID(view);
	if (identifier) {
		C18Log(@"key id=%ld class=%@ frame=%@ super=%@ constraints=%lu translates=%d", (long)identifier, NSStringFromClass([view class]), NSStringFromCGRect(view.frame), NSStringFromClass([view.superview class]), (unsigned long)view.superview.constraints.count, view.translatesAutoresizingMaskIntoConstraints);
		return;
	}
	C18Log(@"container depth=%d class=%@ frame=%@ subviews=%lu constraints=%lu", depth, NSStringFromClass([view class]), NSStringFromCGRect(view.frame), (unsigned long)view.subviews.count, (unsigned long)view.constraints.count);
	for (UIView *subview in view.subviews) C18DumpKey(subview, depth + 1);
}

static void C18DumpTree(UIView *view, int depth) {
	NSString *indent = [@"" stringByPaddingToLength:depth * 2 withString:@" " startingAtIndex:0];
	NSString *extra = @"";
	if ([view isKindOfClass:[UILabel class]]) extra = [NSString stringWithFormat:@" text=%@ font=%.1f", ((UILabel *)view).text, ((UILabel *)view).font.pointSize];
	C18Log(@"tree %@%@ frame=%@ hidden=%d alpha=%.2f constraints=%lu translates=%d%@", indent, NSStringFromClass([view class]), NSStringFromCGRect(view.frame), view.hidden, view.alpha, (unsigned long)view.constraints.count, view.translatesAutoresizingMaskIntoConstraints, extra);
	for (UIView *subview in view.subviews) C18DumpTree(subview, depth + 1);
}

static void C18DumpAncestors(NSString *name, UIView *view) {
	for (UIView *ancestor = view; ancestor; ancestor = ancestor.superview) {
		C18Log(@"[%@] ancestor %@ frame=%@ bounds=%@ constraints=%lu translates=%d", name, NSStringFromClass([ancestor class]), NSStringFromCGRect(ancestor.frame), NSStringFromCGRect(ancestor.bounds), (unsigned long)ancestor.constraints.count, ancestor.translatesAutoresizingMaskIntoConstraints);
	}
}

// Logs the keypad and the display as they are laid out in the given orientation, once the layout has settled.
static void C18DumpOrientation(UIView *keypad) {
	__weak UIView *weakKeypad = keypad;
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		UIView *keypad = weakKeypad;
		if (!keypad.window) return;
		CGSize window = keypad.window.bounds.size;
		C18Log(@"==== orientation dump: window=%@ landscape=%d interfaceOrientation=%ld safeArea=%@ ====", NSStringFromCGSize(window), window.width > window.height, (long)keypad.window.windowScene.interfaceOrientation, NSStringFromUIEdgeInsets(keypad.window.safeAreaInsets));
		C18DumpAncestors(@"keypad", keypad);
		UIViewController *root = keypad.window.rootViewController;
		NSMutableArray *classes = [NSMutableArray array];
		for (UIViewController *child in root.childViewControllers) [classes addObject:NSStringFromClass([child class])];
		C18Log(@"rootViewController=%@ children=%@", NSStringFromClass([root class]), [classes componentsJoinedByString:@","]);
		UIViewController *keypadController = C18KeypadController(keypad);
		if (!keypadController) C18Log(@"no keypadController on %@", root);
		for (NSString *name in keypadController ? @[@"basicKeypad", @"scientificKeypad"] : @[]) {
			UIView *view = MSHookIvar<UIView *>(keypadController, name.UTF8String);
			if (![view isKindOfClass:[UIView class]]) { C18Log(@"KeypadViewController %@ = %@", name, view); continue; }
			C18Log(@"KeypadViewController %@ = %@ frame=%@ hidden=%d alpha=%.2f subviews=%lu superview=%@ constraints=%lu translates=%d", name, NSStringFromClass([view class]), NSStringFromCGRect(view.frame), view.hidden, view.alpha, (unsigned long)view.subviews.count, NSStringFromClass([view.superview class]), (unsigned long)view.constraints.count, view.translatesAutoresizingMaskIntoConstraints);
			for (NSLayoutConstraint *constraint in view.superview.constraints) {
				if (constraint.firstItem == view || constraint.secondItem == view) C18Log(@"  constraint: %@", constraint);
			}
		}
		for (NSString *name in @[@"showingScientificKeypad", @"usingCommaForDecimal", @"keypadInteractionEnabled", @"initialLayout"]) {
			C18Log(@"KeypadViewController %@ = %d", name, MSHookIvar<BOOL>(keypadController, name.UTF8String));
		}
		for (UIView *ancestor = keypad; ancestor; ancestor = ancestor.superview) {
			for (NSLayoutConstraint *constraint in ancestor.constraints) C18Log(@"constraint on %@: %@ active=%d", NSStringFromClass([ancestor class]), constraint, constraint.active);
		}
		for (NSLayoutConstraint *constraint in c18DisplayView.constraints) C18Log(@"constraint on DisplayView: %@ active=%d", constraint, constraint.active);
		C18DumpKey(keypad, 0);
		UIView *display = c18DisplayView;
		if (display) {
			C18DumpAncestors(@"display", display);
			C18DumpTree(display, 0);
		}
		C18Log(@"==== end dump ====");
	});
}

// Called from every keypad layout. Dumps again whenever the orientation changes (the populated keypad only;
// Calculator builds a second, empty one).
void C18DebugKeypadLayout(UIView *keypad) {
	static int lastLandscape = -1;
	if (!C18DebugEnabled()) return;
	if (!keypad.subviews.count || keypad.bounds.size.width <= 0 || !keypad.window) return;
	int landscape = keypad.window.bounds.size.width > keypad.window.bounds.size.height;
	if (landscape == lastLandscape) return;
	lastLandscape = landscape;
	C18DumpOrientation(keypad);
}
