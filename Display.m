#import "Calculator18.h"

static const CGFloat C18ExpressionGap = 12;     // extra space between the expression line and the result
static const CGFloat C18ExpressionShare = 0.4;  // the expression line's font size, as a share of the result's
static const CGFloat C18ExpressionShareMin = 0.25;  // how small it may get when the display is short,
static const CGFloat C18ResultShareMin = 0.5;   // and the result after it
static const CGFloat C18SideMargin = 34;        // distance of the stock label from the screen edge (iPhone 12 Pro, 16.3.1),
static const CGFloat C18SideMarginLandscape = 30;   // until the stock label has been seen on this device
static const CGFloat C18LandscapeTextLift = 7;   // iOS 18 leaves more room between the result and the keypad in landscape
static const CGFloat C18SettledShare = 0.7;     // once it has settled the display is at least this share of the window's width (safe area)
BOOL c18Rotating;                              // the device is turning: the display is half in the old orientation
static CGFloat c18BaseFontSizes[2];             // largest size the stock label has used, in portrait and in landscape
static CGFloat c18SideMargins[2];               // distance of the stock label from the display's right edge, likewise
BOOL c18Overrode;                        // the main label currently carries our font (and, while typing, our expression)
static CGFloat c18OverrideSize;                 // the font size we gave it
__weak UIView *c18DisplayView;

static UILabel *C18MainLabel(UIView *displayView) {
	UILabel *best = nil;
	for (UIView *subview in displayView.subviews) {
		if (subview.tag == C18ExpressionTag || ![subview isKindOfClass:[UILabel class]]) continue;
		UILabel *label = (UILabel *)subview;
		if (!best || label.font.pointSize > best.font.pointSize) best = label;
	}
	return best;
}

// Largest size up to `size` at which `text` fits in `width`.
static CGFloat C18FittingSize(UIFont *font, NSString *text, CGFloat size, CGFloat width) {
	CGFloat textWidth = [text sizeWithAttributes:@{NSFontAttributeName: [font fontWithSize:size]}].width;
	return textWidth > width ? floor(size * width / textWidth) : size;
}

// Calculator does not restore the size we shrank the label to when its own text takes over again.
static void C18RestoreFont(UIView *displayView, UILabel *main, CGFloat baseFontSize, CGFloat sideMargin, CGFloat available) {
	if (!c18Overrode) return;
	c18Overrode = NO;
	if (fabs(main.font.pointSize - c18OverrideSize) < 0.01 && c18OverrideSize < baseFontSize) {
		CGFloat bottom = CGRectGetMaxY(main.frame);
		main.font = [main.font fontWithSize:baseFontSize];
		[main sizeToFit];
		CGFloat width = MIN(main.bounds.size.width, available);
		main.frame = CGRectMake(displayView.bounds.size.width - sideMargin - width, bottom - main.bounds.size.height, width, main.bounds.size.height);
	}
}

// The font sizes learnt so far and the text we put in the label belong to the orientation that is gone.
void C18ForgetDisplayState(void) {
	c18BaseFontSizes[0] = c18BaseFontSizes[1] = 0;
	c18SideMargins[0] = c18SideMargins[1] = 0;
	c18Overrode = NO;
}

void C18Apply(UIView *displayView) {
	UILabel *main = C18MainLabel(displayView);
	if (!main) return;
	// While the device turns the window already has its new size but the display (and its label font) still
	// has the old one: leave it alone, or the old font would be taken for the new orientation's.
	if (c18Rotating || displayView.bounds.size.width < displayView.window.bounds.size.width * C18SettledShare) return;
	BOOL landscape = C18IsLandscape(displayView);
	// A layer transform, so the frames Calculator and this file set are untouched.
	displayView.layer.sublayerTransform = landscape ? CATransform3DMakeTranslation(0, -C18LandscapeTextLift, 0) : CATransform3DIdentity;
	CGFloat *baseSize = &c18BaseFontSizes[landscape];
	// While the label carries Calculator's own text it is where Calculator put it: its distance from the edge is
	// what this device uses, and what the expression is placed by.
	CGFloat displayWidth = displayView.bounds.size.width;
	CGFloat stockMargin = displayWidth - CGRectGetMaxX(main.frame);
	if (!c18Overrode && main.bounds.size.width > 0 && stockMargin > 0 && stockMargin < displayWidth / 4) c18SideMargins[landscape] = stockMargin;
	CGFloat sideMargin = c18SideMargins[landscape] ?: (landscape ? C18SideMarginLandscape : C18SideMargin);
	if (main.font.pointSize > *baseSize) *baseSize = main.font.pointSize;
	CGFloat baseFontSize = *baseSize;
	C18Log(@"apply: landscape=%d font=%.1f base=%.1f overrode=%d expr=%@", landscape, main.font.pointSize, baseFontSize, c18Overrode, C18CurrentExpression());

	NSString *expression = C18CurrentExpression();
	CGFloat available = displayView.bounds.size.width - 2 * sideMargin;

	UILabel *small = (UILabel *)[displayView viewWithTag:C18ExpressionTag];
	if (!small) {
		small = [[UILabel alloc] init];
		small.tag = C18ExpressionTag;
		small.textAlignment = NSTextAlignmentRight;
		small.textColor = [UIColor colorWithWhite:1 alpha:0.5];
		small.userInteractionEnabled = NO;
		small.isAccessibilityElement = NO;
		[displayView addSubview:small];
	}

	if (!expression.length) {
		small.hidden = YES;
		C18RestoreFont(displayView, main, baseFontSize, sideMargin, available);
		return;
	}

	if (c18ShowingResult) {
		// Result stays big (even after a long expression shrank the label); the expression sits above it, small and grey.
		C18RestoreFont(displayView, main, baseFontSize, sideMargin, available);
		UIFont *font = [UIFont systemFontOfSize:baseFontSize * C18ExpressionShare weight:UIFontWeightLight];
		CGFloat size = C18FittingSize(font, expression, font.pointSize, available);
		CGFloat lineRatio = font.lineHeight / font.pointSize;   // a line's height per point of font size
		CGFloat smallest = floor(baseFontSize * C18ExpressionShareMin);

		// A short display (the portrait scientific keypad, a zoomed or small screen) may not have room above the
		// result: the expression gets smaller, down to `smallest`, and then the result does too.
		CGFloat room = CGRectGetMinY(main.frame) + 10 - C18ExpressionGap;
		if (size * lineRatio > floor(room)) size = MAX(floor(floor(room) / lineRatio), MIN(size, smallest));
		CGFloat need = ceil(size * lineRatio) - room;
		if (need > 1 && main.bounds.size.height > 0) {
			CGFloat bottom = CGRectGetMaxY(main.frame);
			CGFloat mainSize = floor(main.font.pointSize * (main.bounds.size.height - need) / main.bounds.size.height);
			if (mainSize >= baseFontSize * C18ResultShareMin) {
				main.font = [main.font fontWithSize:mainSize];
				c18Overrode = YES;
				c18OverrideSize = mainSize;
				[main sizeToFit];
				CGFloat width = MIN(main.bounds.size.width, available);
				main.frame = CGRectMake(displayView.bounds.size.width - sideMargin - width, bottom - main.bounds.size.height, width, main.bounds.size.height);
			}
		}

		small.font = [font fontWithSize:size];
		small.text = expression;
		[small sizeToFit];
		CGFloat top = CGRectGetMinY(main.frame) + 10 - C18ExpressionGap - small.bounds.size.height;
		small.frame = CGRectMake(displayView.bounds.size.width - sideMargin - small.bounds.size.width, top, small.bounds.size.width, small.bounds.size.height);
		// Still no room (the result would have to get too small): leave the result alone.
		small.hidden = top < -1;
	} else {
		// Typing: the expression replaces the number and shrinks to fit, like iOS 18.
		small.hidden = YES;
		CGFloat bottom = CGRectGetMaxY(main.frame);
		CGFloat size = C18FittingSize(main.font, expression, MAX(main.font.pointSize, baseFontSize), available);
		main.font = [main.font fontWithSize:size];
		c18Overrode = YES;
		c18OverrideSize = size;
		main.text = expression;
		[main sizeToFit];
		CGFloat width = MIN(main.bounds.size.width, available);
		main.frame = CGRectMake(displayView.bounds.size.width - sideMargin - width, bottom - main.bounds.size.height, width, main.bounds.size.height);
	}
}
