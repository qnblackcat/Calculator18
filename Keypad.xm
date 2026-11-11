#import "Calculator18.h"
#import <substrate.h>

static BOOL c18ScientificMode;   // landscape: the scientific keypad is shown instead of the basic one

// Between keys and left of the first column: the stock portrait keypad's, once it has been seen (these on iPhone 12 Pro).
static CGFloat c18KeyGap = 9;
static const CGFloat C18DisplayRatio = 0.38;            // share of the safe height the display gets in landscape

static CGFloat c18PortraitSideMargin = 16;
static const CGFloat C18PortraitKeyHeight = 49;         // ten rows of keys in the portrait scientific keypad
static const CGFloat C18PortraitKeypadShare = 0.75;     // at most this share of the safe height, so small phones keep a display

static NSLayoutConstraint *c18HeightConstraint;         // the display's height constraint (landscape)
static CGFloat c18StockHeight;                          // what Calculator had set it to
static CGFloat c18SetHeight;                            // what we set it to, 0 while it is untouched
static NSLayoutConstraint *c18KeypadHeightConstraint;   // the keypad's height constraint (portrait)
static CGFloat c18StockKeypadHeight;
static CGFloat c18SetKeypadHeight;
static BOOL c18HidKeys;                                 // some scientific keys are hidden by us

BOOL C18IsLandscape(UIView *view) {
	CGSize size = view.window.bounds.size;
	return size.width > size.height;
}

// KeypadViewController, looked up once (it is searched for on every key press and layout).
static Class c18KeypadControllerClass;

UIViewController *C18KeypadController(UIView *anchor) {
	static dispatch_once_t once;
	dispatch_once(&once, ^{ c18KeypadControllerClass = NSClassFromString(@"_TtC10Calculator20KeypadViewController"); });
	if (!c18KeypadControllerClass) return nil;
	for (UIViewController *child in anchor.window.rootViewController.childViewControllers) {
		if ([child isKindOfClass:c18KeypadControllerClass]) return child;
	}
	return nil;
}

// KeypadViewController.basicKeypad / scientificKeypad.
static UIView *C18KeypadView(UIViewController *controller, BOOL scientific) {
	if (!controller) return nil;
	UIView *view = scientific ? MSHookIvar<UIView *>(controller, "scientificKeypad") : MSHookIvar<UIView *>(controller, "basicKeypad");
	return [view isKindOfClass:[UIView class]] ? view : nil;
}

// KeypadViewController.showingScientificKeypad, a Swift Bool.
static BOOL &C18ShowingScientificFlag(UIViewController *controller) {
	return MSHookIvar<BOOL>(controller, "showingScientificKeypad");
}

// Both keypad views of Calculator, the one on screen or not.
NSArray<UIView *> *C18AllKeypads(UIView *anchor) {
	UIViewController *controller = C18KeypadController(anchor);
	NSMutableArray<UIView *> *views = [NSMutableArray array];
	for (int scientific = 0; scientific < 2; scientific++) {
		UIView *view = C18KeypadView(controller, scientific);
		if (view) [views addObject:view];
	}
	return views;
}

// Calculator sets showingScientificKeypad itself when the device turns to landscape.
static BOOL C18ShowingScientificKeypad(UIView *anchor) {
	UIViewController *controller = C18KeypadController(anchor);
	return controller && C18ShowingScientificFlag(controller);
}

// The scientific keypad is shown in portrait (iOS 18 has it; iOS 16 only has it in landscape).
static BOOL C18PortraitScientific(UIView *view) {
	return !C18IsLandscape(view) && C18ShowingScientificKeypad(view);
}

// Whether the keypad currently shown is the scientific one, in either orientation.
BOOL C18ScientificNow(UIView *view) {
	return C18IsLandscape(view) ? c18ScientificMode : C18ShowingScientificKeypad(view);
}

#pragma mark - Display height

static UIView *C18FindDisplay(UIView *root) {
	if (c18DisplayView) return c18DisplayView;
	for (UIView *subview in root.subviews) {
		if ([NSStringFromClass([subview class]) hasSuffix:@"DisplayView"]) return subview;
	}
	return nil;
}

// Sets the height constraint of `view` (kept in *cache) to `target` while `active`, remembering what Calculator
// had set it to (*stock), and gives that back once it is no longer active. *set is what we set, 0 while untouched.
static void C18OverrideHeight(UIView *view, BOOL active, CGFloat target, NSLayoutConstraint *__strong *cache, CGFloat *stock, CGFloat *set) {
	if (!view) return;
	if (!*cache || (*cache).firstItem != view) {
		*cache = nil;
		for (NSLayoutConstraint *constraint in view.constraints) {
			if (constraint.firstItem == view && constraint.firstAttribute == NSLayoutAttributeHeight && !constraint.secondItem) *cache = constraint;
		}
	}
	NSLayoutConstraint *constraint = *cache;
	if (!constraint) return;

	if (active) {
		if (constraint.constant != *set) *stock = constraint.constant;
		if (constraint.constant != target) constraint.constant = target;
		*set = target;
	} else if (*set) {
		if (constraint.constant == *set) constraint.constant = *stock;
		*set = 0;
	}
}

// The clear key's delete icon is set on c18Keypad, which only follows the keypad the model last talked to:
// after a rotation that can be the one that is no longer shown.
static void C18SyncKeypad(UIView *root) {
	UIViewController *controller = C18KeypadController(root);
	UIView *shown = C18KeypadView(controller, C18ShowingScientificKeypad(root));
	if (!shown || !shown.window || !shown.subviews.count || c18Keypad == shown) return;
	c18Keypad = shown;
	C18UpdateClearKey();
}

void C18AdjustDisplayHeight(UIView *root) {
	C18SyncKeypad(root);
	CGFloat safeHeight = root.safeAreaLayoutGuide.layoutFrame.size.height;
	// The display is 71.5pt high in landscape (the stock scientific keypad needs the room). Both keypads here
	// have fewer rows than that, so the display gets taller (two lines: expression and result); the keypad is
	// pinned below it and shrinks to fit.
	C18OverrideHeight(C18FindDisplay(root), C18IsLandscape(root), round(safeHeight * C18DisplayRatio),
		&c18HeightConstraint, &c18StockHeight, &c18SetHeight);
	// In portrait the keypad has a fixed height (490pt, five rows of the basic keypad) and the display takes the
	// rest. The portrait scientific keypad has ten rows, so the keypad gets taller and the display shrinks.
	C18OverrideHeight(C18KeypadController(root).view, C18PortraitScientific(root),
		MIN(10 * C18PortraitKeyHeight + 9 * c18KeyGap, round(safeHeight * C18PortraitKeypadShare)),
		&c18KeypadHeightConstraint, &c18StockKeypadHeight, &c18SetKeypadHeight);
}

#pragma mark - Switching keypads

static void C18SetNeedsLayoutDeep(UIView *view) {
	[view setNeedsLayout];
	for (UIView *subview in view.subviews) C18SetNeedsLayoutDeep(subview);
}

// Every view of the window, laid out again now.
static void C18LayoutWindowNow(UIWindow *window) {
	UIView *root = window.rootViewController.view;
	C18SetNeedsLayoutDeep(root);
	[root layoutIfNeeded];
}

// Lays everything out again: after a rotation Calculator flips showingScientificKeypad only when the
// transition has finished, so what the layout saw during it (window already turned) may have been stale.
void C18RelayoutWindow(UIWindow *window) {
	C18LayoutWindowNow(window);
	C18UpdateClearKey();
}

// Landscape: the scientific keypad view stays, and only shows its basic keys while not in scientific mode.
static void C18SetLandscapeScientific(BOOL scientific, UIView *anchor) {
	c18ScientificMode = scientific;
	C18LayoutWindowNow(anchor.window);
}

// Portrait: does what KeypadViewController does when the device turns to landscape (viewWillLayoutSubviews and
// viewWillTransitionToSize:): show the scientific keypad view instead of the basic one, and tell it so.
static void C18SetPortraitScientific(BOOL scientific, UIView *anchor) {
	UIWindow *window = anchor.window;   // taken first: the key lives in the keypad that is about to leave the window
	UIViewController *controller = C18KeypadController(anchor);
	UIView *basic = C18KeypadView(controller, NO), *sci = C18KeypadView(controller, YES);
	if (!window || !controller || !basic || !sci) return;
	C18ShowingScientificFlag(controller) = scientific;
	UIView *shown = scientific ? sci : basic, *hidden = scientific ? basic : sci;
	[controller.view addSubview:shown];
	[hidden removeFromSuperview];
	shown.frame = controller.view.bounds;
	shown.alpha = 1;   // Calculator cross-fades the two keypads when it rotates and leaves the one it hid at 0
	c18Keypad = shown;
	C18LayoutWindowNow(window);
}

// Calculator just started: shows the keypad chosen in Settings. The landscape flag is set either way, so turning
// the phone keeps the mode; the portrait keypad is only swapped when it differs.
void C18ApplyStartupKeypad(BOOL scientific, UIView *anchor) {
	c18ScientificMode = scientific;
	if (C18IsLandscape(anchor)) C18SetLandscapeScientific(scientific, anchor);
	else if (C18ScientificNow(anchor) != scientific) C18SetPortraitScientific(scientific, anchor);
}

// A tap of the strength chosen in Settings, when Haptic Feedback is on.
void C18Haptic(void) {
	C18HapticState state = C18PrefHaptic();
	if (state == C18HapticStateOff) return;
	static UIFeedbackGenerator *generator;
	static C18HapticState generatorState;
	if (!generator || generatorState != state) {
		generatorState = state;
		static const UIImpactFeedbackStyle styles[] = {UIImpactFeedbackStyleSoft, UIImpactFeedbackStyleLight, UIImpactFeedbackStyleMedium, UIImpactFeedbackStyleHeavy};
		generator = state == C18HapticStateSelection ? [UISelectionFeedbackGenerator new] : [[UIImpactFeedbackGenerator alloc] initWithStyle:styles[state - C18HapticStateSoft]];
	}
	if (state == C18HapticStateSelection) [(UISelectionFeedbackGenerator *)generator selectionChanged];
	else [(UIImpactFeedbackGenerator *)generator impactOccurred];
	[generator prepare];
}

// `anchor` is the key that was used: c18Keypad is only known after the first key press.
void C18SelectKeypad(BOOL scientific, BOOL landscape, UIView *anchor) {
	C18Haptic();
	if (landscape) C18SetLandscapeScientific(scientific, anchor);
	else C18SetPortraitScientific(scientific, anchor);
}

#pragma mark - Layouts

// A key that is not shown must also be out of the way: CalculatorKeypadView follows the fingers by geometry
// (touchesBegan/Moved/Ended), so a merely hidden key would still catch touches that fall inside its old frame.
static void C18ShowKey(UIView *key, BOOL shown) {
	key.hidden = !shown;
	key.userInteractionEnabled = shown;
	if (!shown) key.frame = CGRectZero;
}

// Key ids of the basic keypad, row by row (iOS 18 landscape), as C18BaseKeyID gives them (1 is the clear key, 52 the
// decimal key, whatever they read now). -1 is the mode key.
static const NSInteger C18BasicLayout[4][5] = {
	{C18ButtonDigit0 + 7, C18ButtonDigit0 + 8, C18ButtonDigit0 + 9, C18ButtonClear, C18ButtonDivide},
	{C18ButtonDigit0 + 4, C18ButtonDigit0 + 5, C18ButtonDigit0 + 6, C18ButtonNegate, C18ButtonMultiply},
	{C18ButtonDigit0 + 1, C18ButtonDigit0 + 2, C18ButtonDigit0 + 3, C18ButtonPercent, C18ButtonSubtract},
	{-1, C18ButtonDigit0, C18ButtonDecimal, C18ButtonEquals, C18ButtonAdd},
};

// The scientific keypad in iOS 18's portrait layout: six columns of scientific keys over four columns of basic keys.
static const NSInteger C18PortraitScientificLayout[5][6] = {
	{C18ButtonOpenParen, C18ButtonCloseParen, C18ButtonMemoryClear, C18ButtonMemoryAdd, C18ButtonMemorySubtract, C18ButtonMemoryRecall},
	{C18ButtonSecond, C18ButtonSquare, C18ButtonCube, C18ButtonPower, C18ButtonExp, C18ButtonTenPower},
	{C18ButtonReciprocal, C18ButtonSquareRoot, C18ButtonCubeRoot, C18ButtonRoot, C18ButtonLn, C18ButtonLog10},
	{C18ButtonFactorial, C18ButtonSin, C18ButtonCos, C18ButtonTan, C18ButtonE, C18ButtonEE},
	{C18ButtonRand, C18ButtonSinh, C18ButtonCosh, C18ButtonTanh, C18ButtonPi, C18ButtonRad},   // iOS 16's landscape has Rad first and Rand last
};
static const NSInteger C18PortraitBasicLayout[5][4] = {
	{C18ButtonClear, C18ButtonNegate, C18ButtonPercent, C18ButtonDivide},
	{C18ButtonDigit0 + 7, C18ButtonDigit0 + 8, C18ButtonDigit0 + 9, C18ButtonMultiply},
	{C18ButtonDigit0 + 4, C18ButtonDigit0 + 5, C18ButtonDigit0 + 6, C18ButtonSubtract},
	{C18ButtonDigit0 + 1, C18ButtonDigit0 + 2, C18ButtonDigit0 + 3, C18ButtonAdd},
	{-1, C18ButtonDigit0, C18ButtonDecimal, C18ButtonEquals},
};

// The scientific keypad in iOS 18's landscape layout: ten columns, five rows. Rad/Deg and Rand have moved
// one and two columns to the right of where iOS 16 has them, and the calculator key takes the first column.
static const NSInteger C18LandscapeScientificLayout[5][10] = {
	{C18ButtonOpenParen, C18ButtonCloseParen, C18ButtonMemoryClear, C18ButtonMemoryAdd, C18ButtonMemorySubtract, C18ButtonMemoryRecall,
		C18ButtonClear, C18ButtonNegate, C18ButtonPercent, C18ButtonDivide},
	{C18ButtonSecond, C18ButtonSquare, C18ButtonCube, C18ButtonPower, C18ButtonExp, C18ButtonTenPower,
		C18ButtonDigit0 + 7, C18ButtonDigit0 + 8, C18ButtonDigit0 + 9, C18ButtonMultiply},
	{C18ButtonReciprocal, C18ButtonSquareRoot, C18ButtonCubeRoot, C18ButtonRoot, C18ButtonLn, C18ButtonLog10,
		C18ButtonDigit0 + 4, C18ButtonDigit0 + 5, C18ButtonDigit0 + 6, C18ButtonSubtract},
	{C18ButtonFactorial, C18ButtonSin, C18ButtonCos, C18ButtonTan, C18ButtonE, C18ButtonEE,
		C18ButtonDigit0 + 1, C18ButtonDigit0 + 2, C18ButtonDigit0 + 3, C18ButtonAdd},
	{-1, C18ButtonSinh, C18ButtonCosh, C18ButtonTanh, C18ButtonPi, C18ButtonRad,
		C18ButtonRand, C18ButtonDigit0, C18ButtonDecimal, C18ButtonEquals},
};

// The key's HighlightView draws its rounded rectangle in drawRect: (two fills of the bounds, cheap), and UIKit only
// stretches that picture when the key changes size. These keys have a different size in each layout, so draw it
// again every time the key is placed. (Only redrawing when the size seemed to change missed some: the key passes
// through other sizes on the way, during rotation and while the keypads are swapped.)
static void C18RedrawHighlight(UIView *key) {
	for (UIView *subview in key.subviews) {
		if ([NSStringFromClass([subview class]) hasSuffix:@"HighlightView"]) {
			subview.contentMode = UIViewContentModeRedraw;
			[subview setNeedsDisplay];
		}
	}
}

// Puts the key with `identifier` at `frame` (-1 is the calculator key). `keys` are by C18BaseKeyID.
static void C18PlaceKey(UIView *keypad, NSDictionary<NSNumber *, UIView *> *keys, NSInteger identifier, CGRect frame, NSMutableSet<UIView *> *placed) {
	if (identifier == -1) {
		C18PlaceModeKey(keypad, frame, keys[@(C18ButtonDigit0)]);
		return;
	}
	UIView *key = keys[@(identifier)];
	if (!key) return;
	key.frame = frame;
	C18RedrawHighlight(key);
	[placed addObject:key];
}

// Lays out `layout` (rows x columns key ids, row by row) as a grid of equal keys filling `area`.
static void C18PlaceGrid(UIView *keypad, NSDictionary<NSNumber *, UIView *> *keys, const NSInteger *layout, int rows, int columns, CGRect area, NSMutableSet<UIView *> *placed) {
	CGFloat width = (area.size.width - (columns - 1) * c18KeyGap) / columns;
	CGFloat height = (area.size.height - (rows - 1) * c18KeyGap) / rows;
	for (int row = 0; row < rows; row++) {
		for (int column = 0; column < columns; column++) {
			CGRect frame = CGRectMake(area.origin.x + column * (width + c18KeyGap), area.origin.y + row * (height + c18KeyGap), width, height);
			C18PlaceKey(keypad, keys, layout[row * columns + column], frame, placed);
		}
	}
}

// The portrait basic keypad is left as Calculator lays it out, so its margin and gap are the device's: the other
// layouts use them too.
static void C18LearnSpacing(NSDictionary<NSNumber *, UIView *> *keys) {
	CGRect seven = keys[@(C18ButtonDigit0 + 7)].frame, eight = keys[@(C18ButtonDigit0 + 8)].frame;
	if (seven.size.width <= 0 || eight.size.width <= 0) return;
	CGFloat gap = CGRectGetMinX(eight) - CGRectGetMaxX(seven);
	if (gap > 0 && gap < seven.size.width / 2) c18KeyGap = gap;
	if (seven.origin.x > 0 && seven.origin.x < seven.size.width) c18PortraitSideMargin = seven.origin.x;
}

// Calculator lays the scientific keypad out for landscape: ten columns, five rows. It holds the basic keys as
// well (same views, so they keep working): here they are taken out and laid out the iOS 18 way. In landscape
// that is four rows of basic keys with the scientific keys hidden; in portrait six columns of scientific keys
// over four columns of basic keys. Also keeps the calculator key (menu: basic / scientific / note) in place.
void C18LayoutKeypad(UIView *keypad) {
	BOOL landscape = C18IsLandscape(keypad);

	NSMutableDictionary<NSNumber *, UIView *> *keys = [NSMutableDictionary dictionary];
	for (UIView *subview in keypad.subviews) {
		NSInteger identifier = C18BaseKeyID(C18KeyID(subview));
		if (identifier) keys[@(identifier)] = subview;
	}
	C18LayoutPortraitModeKey(keypad, keys);
	CGSize size = keypad.bounds.size;

	if (!landscape && keys[@(C18ButtonOpenParen)]) {
		// Portrait scientific keypad. (The basic keypad has none of the scientific keys, so this is only it.)
		if (!C18ShowingScientificKeypad(keypad) || size.width <= 0 || size.height <= 0) return;
		c18HidKeys = NO;
		for (UIView *key in keys.allValues) C18ShowKey(key, YES);

		// Five rows of each, all ten rows the same height.
		CGFloat usable = size.width - 2 * c18PortraitSideMargin, half = (size.height - c18KeyGap) / 2;
		C18PlaceGrid(keypad, keys, &C18PortraitScientificLayout[0][0], 5, 6, CGRectMake(c18PortraitSideMargin, 0, usable, half), nil);
		C18PlaceGrid(keypad, keys, &C18PortraitBasicLayout[0][0], 5, 4, CGRectMake(c18PortraitSideMargin, half + c18KeyGap, usable, half), nil);
		return;
	}

	if (!landscape) {
		// The portrait basic keypad: ModeKey.m places its calculator key.
		if (keypad.window && size.width > 0) C18LearnSpacing(keys);
		if (c18HidKeys) {
			for (UIView *key in keys.allValues) C18ShowKey(key, YES);
			c18HidKeys = NO;
		}
		return;
	}

	if (size.width <= 0 || size.height <= 0 || !keys[@(C18ButtonDigit0)]) return;
	CGRect area = CGRectMake(0, 0, size.width, size.height);

	if (c18ScientificMode) {
		c18HidKeys = NO;
		for (UIView *key in keys.allValues) C18ShowKey(key, YES);
		C18PlaceGrid(keypad, keys, &C18LandscapeScientificLayout[0][0], 5, 10, area, nil);
		return;
	}

	NSMutableSet<UIView *> *placed = [NSMutableSet set];
	C18PlaceGrid(keypad, keys, &C18BasicLayout[0][0], 4, 5, area, placed);
	for (UIView *key in keys.allValues) C18ShowKey(key, [placed containsObject:key]);
	c18HidKeys = YES;
}

// The wide 0 key keeps its label at the left; in these layouts the key is one column wide.
void C18CenterZeroLabel(UIView *key) {
	if (C18KeyID(key) != C18ButtonDigit0 || !(C18IsLandscape(key) || C18PortraitScientific(key))) return;
	for (UIView *subview in key.subviews) {
		if ([subview isKindOfClass:[UILabel class]]) subview.center = CGPointMake(CGRectGetMidX(key.bounds), CGRectGetMidY(key.bounds));
	}
}

// iOS 18's landscape scientific keypad has smaller labels on the basic keys (digits, operators, clear, ...)
// than the keys are meant to carry; scale the labels, and put them back for every other layout.
static const CGFloat C18LandscapeLabelRatio = 0.55;             // label font size relative to the key height
static const CGFloat C18LandscapeOperatorLabelRatio = 0.62;     // + - x / = a little larger

static BOOL C18IsBasicKey(NSInteger identifier) {
	return (identifier >= C18ButtonDigit0 && identifier <= C18ButtonDigit9) || identifier == C18ButtonClear ||
		identifier == C18ButtonNegate || identifier == C18ButtonPercent || identifier == C18ButtonDecimal ||
		(identifier >= C18ButtonDivide && identifier <= C18ButtonEquals);
}

void C18AdjustKeyLabels(UIView *key) {
	NSInteger identifier = C18BaseKeyID(C18KeyID(key));
	if (!C18IsBasicKey(identifier)) return;
	BOOL scale = C18IsLandscape(key) && c18ScientificMode;
	BOOL isOperator = identifier >= C18ButtonDivide && identifier <= C18ButtonEquals;
	for (UIView *subview in key.subviews) {
		if (![subview isKindOfClass:[UILabel class]]) continue;
		UILabel *label = (UILabel *)subview;
		CGFloat target = key.bounds.size.height * (isOperator ? C18LandscapeOperatorLabelRatio : C18LandscapeLabelRatio);
		CGFloat factor = scale && label.font.pointSize > target ? target / label.font.pointSize : 1;
		CGAffineTransform transform = CGAffineTransformMakeScale(factor, factor);
		if (!CGAffineTransformEqualToTransform(label.transform, transform)) label.transform = transform;
	}
}
