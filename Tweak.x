#import "Calculator18.h"

// Calculator.app is Swift, but these classes are @objc-visible (names taken from the 16.3.1 and 17.1.1 binaries).

%group CalculatorApp

%hook UILabel

- (void)setText:(NSString *)text {
	%orig;
	C18ClearLabelChanged(self);
}

- (void)setAttributedText:(NSAttributedString *)text {
	%orig;
	C18ClearLabelChanged(self);
}

%end

%hook _TtC10Calculator15CalculatorModel

- (void)buttonPressed:(NSInteger)button {
	if (C18InterceptKey(self, &button)) return;
	C18Log(@"buttonPressed: %ld", (long)button);
	C18Track(button);
	%orig(button);
	C18UpdateClearKey();

	// Some keys (an operator after a typed number) produce no display update, so refresh the expression here.
	UIView *displayView = c18DisplayView;
	if (displayView) {
		[displayView setNeedsLayout];
		[displayView layoutIfNeeded];
	}
}

%end

%hook _TtC10Calculator20CalculatorController

- (void)viewWillLayoutSubviews {
	C18AdjustDisplayHeight(((UIViewController *)self).view);
	%orig;
}

- (void)calculatorModel:(id)model didUpdateDisplayValue:(id)value shouldFlashDisplay:(BOOL)flash {
	NSString *text = [value respondsToSelector:@selector(accessibilityStringValue)] ? [value performSelector:@selector(accessibilityStringValue)] : nil;
	C18SetDisplayText(text);
	C18Log(@"didUpdateDisplayValue: text=%@ expr=%@", text, C18CurrentExpression());
	BOOL wasTransient = C18InTransient();
	%orig;
	C18UpdateClearKey();

	// Only step in while the tweak is (or was just) changing the display, so Calculator's own
	// layout timing stays untouched for plain numbers.
	UIView *displayView = c18DisplayView;
	if (displayView && (c18Overrode || C18CurrentExpression() || ![displayView viewWithTag:C18ExpressionTag].hidden)) {
		[displayView setNeedsLayout];
		[displayView layoutIfNeeded];
	}
	if (wasTransient) {
		// The "0" that precedes the first digit has been shown without the number; the digit follows.
		// If it does not, the next key press (or this async hop) settles the state.
		C18EndTransient();
		dispatch_async(dispatch_get_main_queue(), ^{
			[c18DisplayView setNeedsLayout];
		});
	}
}

%end

%hook _TtC10Calculator20KeypadViewController

- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator {
	c18Rotating = YES;
	%orig;
	__weak UIViewController *controller = (UIViewController *)self;
	[coordinator animateAlongsideTransition:nil completion:^(id<UIViewControllerTransitionCoordinatorContext> context) {
		c18Rotating = NO;
		C18ForgetDisplayState();
		C18RelayoutWindow(controller.view.window);
	}];
}

%end

%hook _TtC10Calculator11DisplayView

- (void)layoutSubviews {
	%orig;
	c18DisplayView = (UIView *)self;
	C18Apply((UIView *)self);
}

%end

%hook _TtC10Calculator22CalculatorKeypadButton

- (void)layoutSubviews {
	%orig;
	C18CenterZeroLabel((UIView *)self);
	C18AdjustKeyLabels((UIView *)self);
}

%end

%hook _TtC10Calculator20CalculatorKeypadView

- (void)layoutSubviews {
	%orig;
	C18LayoutKeypad((UIView *)self);
	// The scientific keypad only gets its keys on its first layout: bring its clear key up to date then.
	C18UpdateClearKey();
	C18DebugKeypadLayout((UIView *)self);
}

- (void)setShowingAlternate:(BOOL)alternate button:(NSInteger)button {
	%orig;
	// Calculator builds a second keypad view (empty until the scientific keypad is needed) and tells both of
	// every change: only the one on screen counts.
	if (((UIView *)self).subviews.count && ((UIView *)self).window) c18Keypad = (UIView *)self;
	C18UpdateClearKey();
}

%end

%end

#pragma mark - Setup

%ctor {
	if ([[[NSBundle mainBundle] bundleIdentifier] isEqualToString:@"com.apple.springboard"]) {
		C18ListenForNewNote();
	} else {
		%init(CalculatorApp);
	}
}
