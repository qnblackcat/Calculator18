#import "Calculator18.h"

__weak UIView *c18Keypad;       // the populated keypad view (Calculator builds a second, empty one)
static __weak id<C18CalculatorModel> c18Model;      // the CalculatorModel, to send keys to
static BOOL c18Updating;        // we are changing the clear key's label ourselves
static BOOL c18Replaying;       // we are sending keys ourselves, so they must not be remapped

// Each keypad view has its own clear key, with its own font and colour: the stock ones are kept on its label.
static const void *c18StockFontKey = &c18StockFontKey;
static const void *c18StockColorKey = &c18StockColorKey;

#pragma mark - Sending keys

static void C18SendKey(NSInteger key) {
	[c18Model buttonPressed:key];
}

// With an operator pending, the first AC only clears the entry and keeps the operator; the second clears all.
static void C18SendAllClear(void) {
	C18SendKey(C18ButtonAllClear);
	C18SendKey(C18ButtonAllClear);
}

static void C18ClearEverything(void) {
	c18Replaying = YES;
	C18SendAllClear();
	c18Replaying = NO;
	C18UpdateClearKey();
}

// Calculator cannot delete a trailing operator (or an open parenthesis), so clear and press the keys that built
// the expression again, without the last one.
static void C18RetypeWithoutLastOperator(void) {
	NSArray<NSNumber *> *keys = C18KeysWithoutLast();
	c18Replaying = YES;
	C18SendAllClear();
	for (NSNumber *key in keys) C18SendKey(key.integerValue);
	c18Replaying = NO;
	C18UpdateClearKey();
}

#pragma mark - Clear key

// The clear key reports id 1 while it reads "C" and 51 while it reads "AC", the value buttonPressed: gets.
static BOOL C18IsClearKey(UIView *view) {
	NSInteger identifier = C18KeyID(view);
	return identifier == C18ButtonClear || identifier == C18ButtonAllClear;
}

static UIView *C18FindClearKey(UIView *view) {
	if (C18IsClearKey(view)) return view;
	for (UIView *subview in view.subviews) {
		UIView *found = C18FindClearKey(subview);
		if (found) return found;
	}
	return nil;
}

// The clear key of a keypad view, remembered so that every key press does not search the keypad again.
static UIView *C18ClearKeyOf(UIView *keypad) {
	static NSMapTable<UIView *, UIView *> *clearKeys;
	if (!clearKeys) clearKeys = [NSMapTable weakToWeakObjectsMapTable];
	UIView *key = [clearKeys objectForKey:keypad];
	if (key && C18IsClearKey(key) && [key isDescendantOfView:keypad]) return key;
	key = C18FindClearKey(keypad);
	if (key) [clearKeys setObject:key forKey:keypad];
	return key;
}

// Holding the delete key clears everything, like AC. The recogniser must not take the touch from the key: on
// "C" / "AC" a long press is just a slow tap, and the key has to act on it. After a hold that cleared everything
// the tap the key still sends when the finger lifts is swallowed.
static BOOL c18SwallowClearTap;

@interface C18LongPressTarget : NSObject
+ (void)handle:(UILongPressGestureRecognizer *)recognizer;
@end

@implementation C18LongPressTarget
+ (void)handle:(UILongPressGestureRecognizer *)recognizer {
	if (recognizer.state == UIGestureRecognizerStateBegan) {
		if (C18DeleteMode() && c18Model) {
			c18SwallowClearTap = YES;
			C18ClearEverything();
		}
	} else if (recognizer.state == UIGestureRecognizerStateEnded || recognizer.state == UIGestureRecognizerStateCancelled) {
		// The key's own press arrives with the lift of the finger, just after this.
		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ c18SwallowClearTap = NO; });
	}
}
@end

static void C18InstallLongPress(UIView *key) {
	static const void *gestureKey = &gestureKey;
	if (objc_getAssociatedObject(key, gestureKey)) return;
	UILongPressGestureRecognizer *press = [[UILongPressGestureRecognizer alloc] initWithTarget:[C18LongPressTarget class] action:@selector(handle:)];
	press.minimumPressDuration = 0.4;
	press.cancelsTouchesInView = NO;
	[key addGestureRecognizer:press];
	objc_setAssociatedObject(key, gestureKey, press, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static NSAttributedString *C18DeleteIcon(UIFont *font, UIColor *color) {
	UIImageSymbolConfiguration *configuration = [UIImageSymbolConfiguration configurationWithPointSize:font.pointSize * 0.85 weight:UIImageSymbolWeightMedium];
	UIImage *image = [[UIImage systemImageNamed:@"delete.left" withConfiguration:configuration] imageWithTintColor:color renderingMode:UIImageRenderingModeAlwaysOriginal];
	NSTextAttachment *attachment = [[NSTextAttachment alloc] init];
	attachment.image = image;
	attachment.bounds = CGRectMake(0, (font.capHeight - image.size.height) / 2, image.size.width, image.size.height);
	NSMutableAttributedString *icon = [[NSAttributedString attributedStringWithAttachment:attachment] mutableCopy];
	[icon addAttributes:@{NSFontAttributeName: font, NSForegroundColorAttributeName: color} range:NSMakeRange(0, icon.length)];
	return icon;
}

// The labels of the clear keys seen so far. UILabel's setters are hooked for every label in the app, so they
// only compare against these: the pointers are never messaged, and a stale one costs at most one extra update.
static __unsafe_unretained UILabel *c18ClearLabels[4];
static NSUInteger c18NextClearLabel;

static BOOL C18IsClearLabel(UILabel *label) {
	for (NSUInteger i = 0; i < 4; i++) {
		if (c18ClearLabels[i] == label) return YES;
	}
	return NO;
}

static void C18RememberClearLabel(UILabel *label) {
	if (C18IsClearLabel(label)) return;
	c18ClearLabels[c18NextClearLabel] = label;
	c18NextClearLabel = (c18NextClearLabel + 1) % 4;
}

// Shows the delete icon or the stock "C"/"AC" text on the clear key of one keypad view, whichever the state calls for.
static void C18UpdateClearKeyIn(UIView *keypad) {
	UIView *key = C18ClearKeyOf(keypad);
	UILabel *label = nil;
	for (UIView *subview in key.subviews) {
		if ([subview isKindOfClass:[UILabel class]]) label = (UILabel *)subview;
	}
	if (!label) return;
	C18RememberClearLabel(label);
	C18InstallLongPress(key);

	NSAttributedString *current = label.attributedText;
	BOOL showingIcon = current.length && [current attribute:NSAttachmentAttributeName atIndex:0 effectiveRange:NULL];
	if (C18DeleteMode() == showingIcon) return;

	c18Updating = YES;
	if (showingIcon) {
		label.attributedText = nil;
		UIFont *font = objc_getAssociatedObject(label, c18StockFontKey);
		UIColor *color = objc_getAssociatedObject(label, c18StockColorKey);
		if (font) label.font = font;
		if (color) label.textColor = color;
		label.text = C18KeyID(key) == C18ButtonAllClear ? @"AC" : @"C";
	} else {
		// Setting attributedText replaces the label's font and colour, so keep the stock ones to restore later.
		objc_setAssociatedObject(label, c18StockFontKey, label.font, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
		objc_setAssociatedObject(label, c18StockColorKey, label.textColor, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
		label.attributedText = C18DeleteIcon(label.font, label.textColor);
	}
	c18Updating = NO;
}

// Both keypad views (Calculator tells both of every key, and either may be the one on screen) are kept current.
static void C18UpdateClearKeyNow(void) {
	NSArray<UIView *> *keypads = C18AllKeypads(c18DisplayView ?: c18Keypad);
	if (!keypads.count && c18Keypad) keypads = @[c18Keypad];
	for (UIView *keypad in keypads) {
		if (keypad.subviews.count) C18UpdateClearKeyIn(keypad);
	}
}

// A key press asks for the clear key several times (the model, the display, the keypad): it is brought up to
// date once, after all of them, on the main queue (before the screen is drawn again).
void C18UpdateClearKey(void) {
	static BOOL scheduled;
	if (scheduled) return;
	scheduled = YES;
	dispatch_async(dispatch_get_main_queue(), ^{
		scheduled = NO;
		C18UpdateClearKeyNow();
	});
}

// Calculator rewrites the clear key's text on its own schedule (after our update), which wipes the icon,
// so re-apply once it has finished.
void C18ClearLabelChanged(UILabel *label) {
	if (!c18Updating && C18IsClearLabel(label)) C18UpdateClearKey();
}

// Called for every key the model gets, before it handles it. Turns the clear key into a delete key while
// that is what it shows (or, with only an operator left, drops the operator); YES: the key is handled.
BOOL C18InterceptKey(id model, NSInteger *button) {
	c18Model = model;
	if (c18Replaying) return NO;
	BOOL clear = *button == C18ButtonClear || *button == C18ButtonAllClear;
	// The finger lifting after a hold that cleared everything: the key's own press is not wanted.
	if (c18SwallowClearTap && (clear || *button == C18ButtonDelete)) return YES;
	if (clear && C18DeleteMode()) {
		if (C18CanDropLastOperator()) {
			C18RetypeWithoutLastOperator();
			return YES;
		}
		*button = C18ButtonDelete;
	}
	return NO;
}
