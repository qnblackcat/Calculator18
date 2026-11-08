#import "Calculator18.h"

// iOS 18's calculator key: it takes the first column of the bottom row and its menu switches between the basic
// and the scientific keypad, or opens a new note.

static const NSInteger C18ModeKeyTag = 0xC1A;   // the calculator key, in every keypad layout

// The colour of a key (the digit keys keep it on a subview), for the calculator key to look like them.
static UIColor *C18KeyColor(UIView *key) {
	UIColor *color = key.backgroundColor;
	for (UIView *subview in key.subviews) {
		if (!color || CGColorGetAlpha(color.CGColor) == 0) color = subview.backgroundColor;
	}
	return color;
}

// iOS 18's calculator glyph (SF Symbols' "calculator" does not exist on iOS 16): outlined body, screen, 3x3 keys.
// Drawn once per key height, since the key is styled on every keypad layout.
static UIImage *C18CalculatorIcon(CGFloat keyHeight) {
	static NSMutableDictionary<NSNumber *, UIImage *> *icons;
	if (!icons) icons = [NSMutableDictionary dictionary];
	UIImage *cached = icons[@(keyHeight)];
	if (cached) return cached;

	CGFloat width = keyHeight * 0.40, height = keyHeight * 0.52, line = MAX(1.5, keyHeight * 0.04), dot = width * 0.13;
	UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(width, height)];
	UIImage *image = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
		[[UIColor blackColor] setStroke];
		[[UIColor blackColor] setFill];
		UIBezierPath *body = [UIBezierPath bezierPathWithRoundedRect:CGRectInset(CGRectMake(0, 0, width, height), line / 2, line / 2) cornerRadius:width * 0.2];
		body.lineWidth = line;
		[body stroke];
		[[UIBezierPath bezierPathWithRoundedRect:CGRectMake(width * 0.2, height * 0.14, width * 0.6, height * 0.2) cornerRadius:1] fill];
		for (int row = 0; row < 3; row++) {
			for (int column = 0; column < 3; column++) {
				[[UIBezierPath bezierPathWithOvalInRect:CGRectMake(width * 0.2 + column * width * 0.24, height * 0.46 + row * height * 0.16, dot, dot)] fill];
			}
		}
	}];
	image = [image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
	icons[@(keyHeight)] = image;
	return image;
}

// The menu of the calculator key: the keypads and a new note.
static UIMenu *C18ModeMenu(BOOL landscape, UIView *button) {
	__weak UIView *anchor = button;
	BOOL scientificNow = C18ScientificNow(button);
	UIAction *basic = [UIAction actionWithTitle:@"Basic" image:nil identifier:nil handler:^(UIAction *action) { C18SelectKeypad(NO, landscape, anchor); }];
	basic.state = scientificNow ? UIMenuElementStateOff : UIMenuElementStateOn;
	UIAction *scientific = [UIAction actionWithTitle:@"Scientific" image:nil identifier:nil handler:^(UIAction *action) { C18SelectKeypad(YES, landscape, anchor); }];
	scientific.state = scientificNow ? UIMenuElementStateOn : UIMenuElementStateOff;
	UIAction *note = [UIAction actionWithTitle:@"Open New Note" image:[UIImage systemImageNamed:@"square.and.pencil"] identifier:nil handler:^(UIAction *action) { C18OpenNewNote(); }];
	return [UIMenu menuWithTitle:@"" children:@[[UIMenu menuWithTitle:@"" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:@[basic, scientific]], note]];
}

static UIButton *C18ModeButton(UIView *keypad) {
	UIButton *button = (UIButton *)[keypad viewWithTag:C18ModeKeyTag];
	if (button) return button;
	button = [UIButton buttonWithType:UIButtonTypeCustom];
	button.tag = C18ModeKeyTag;
	button.accessibilityLabel = @"Calculator";
	button.tintColor = [UIColor whiteColor];
	button.showsMenuAsPrimaryAction = YES;
	[keypad addSubview:button];
	return button;
}

static void C18StyleModeButton(UIButton *button, CGRect frame, UIColor *color) {
	button.frame = frame;
	button.backgroundColor = color;
	button.layer.cornerRadius = MIN(frame.size.width, frame.size.height) / 2;
	UIImage *icon = C18CalculatorIcon(frame.size.height);
	if ([button imageForState:UIControlStateNormal] != icon) [button setImage:icon forState:UIControlStateNormal];
	button.hidden = NO;

	// The menu shows which mode is current, so only rebuild it when that changes (not while it may be open).
	static const void *stateKey = &stateKey;
	BOOL landscape = C18IsLandscape(button.superview);
	NSNumber *state = @(landscape * 2 + C18ScientificNow(button));
	if (!button.menu || ![objc_getAssociatedObject(button, stateKey) isEqual:state]) {
		button.menu = C18ModeMenu(landscape, button);
		objc_setAssociatedObject(button, stateKey, state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	}
}

// Puts the calculator key of `keypad` at `frame`, coloured like `digitKey`.
void C18PlaceModeKey(UIView *keypad, CGRect frame, UIView *digitKey) {
	C18StyleModeButton(C18ModeButton(keypad), frame, C18KeyColor(digitKey));
}

// The portrait basic keypad: the stock 0 key is two columns wide here, so shrink it to one and put the calculator
// key in the first column. The scientific keypad view (any orientation) is left to Keypad.m. `keys` are the
// keypad's keys by id.
void C18LayoutPortraitModeKey(UIView *keypad, NSDictionary<NSNumber *, UIView *> *keys) {
	if (keys[@(C18ButtonOpenParen)]) return;
	UIView *zero = keys[@(C18ButtonDigit0)];
	UIButton *note = (UIButton *)[keypad viewWithTag:C18ModeKeyTag];

	CGSize window = keypad.window.bounds.size;   // zero while the keypad is not in a window: not portrait
	BOOL portrait = window.width < window.height;
	BOOL wideZero = zero && zero.frame.size.width > zero.frame.size.height * 1.5;
	if (!portrait || !wideZero) {
		// Only keep the key if the 0 key is still shrunk from an earlier pass in portrait.
		BOOL shrunkZero = zero && !wideZero;
		if (!shrunkZero) note.hidden = YES;
		return;
	}

	CGRect stock = zero.frame;
	CGFloat size = stock.size.height;
	zero.frame = CGRectMake(CGRectGetMaxX(stock) - size, stock.origin.y, size, size);
	C18PlaceModeKey(keypad, CGRectMake(stock.origin.x, stock.origin.y, size, size), zero);
}
