#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#ifdef C18_DEBUG
// Debug.xm: appends a line to Calculator18.log (/var/mobile/tmp, and Calculator's own tmp folder).
#ifdef __cplusplus
extern "C"
#endif
void C18WriteLog(NSString *message);
#define C18Log(fmt, ...) do { NSString *c18Message = [NSString stringWithFormat:@"" fmt, ##__VA_ARGS__]; NSLog(@"[Calculator18] %@", c18Message); C18WriteLog(c18Message); } while (0)
#else
#define C18Log(...)
#endif

// Values of CalculatorModel's buttonPressed: argument, read from the debug log on 16.3.1.
enum {
	C18ButtonClear = 1,
	C18ButtonDelete = 2, // swipe on the display
	C18ButtonNegate = 3,
	C18ButtonPercent = 4,
	C18ButtonDivide = 5,
	C18ButtonMultiply = 6,
	C18ButtonSubtract = 7,
	C18ButtonAdd = 8,
	C18ButtonEquals = 9,
	C18ButtonPoint = 10,  // the decimal key where the region's separator is "." (52 where it is ",")
	C18ButtonDigit0 = 11, // 11...20 are 0...9
	C18ButtonDigit9 = 20,
	// Scientific keypad: 21...50 run row by row through iOS 16's landscape layout (the memory keys, 2nd, EE and
	// Rad by their position there), the ids after 53 are the keys 2nd swaps in.
	C18ButtonOpenParen = 21,
	C18ButtonCloseParen = 22,
	C18ButtonMemoryClear = 23,
	C18ButtonMemoryAdd = 24,
	C18ButtonMemorySubtract = 25,
	C18ButtonMemoryRecall = 26,
	C18ButtonSecond = 27,
	C18ButtonSquare = 28,
	C18ButtonCube = 29,
	C18ButtonPower = 30,          // x^y
	C18ButtonExp = 31,            // e^x
	C18ButtonTenPower = 32,
	C18ButtonReciprocal = 33,
	C18ButtonSquareRoot = 34,
	C18ButtonCubeRoot = 35,
	C18ButtonRoot = 36,           // y-th root of x
	C18ButtonLn = 37,
	C18ButtonLog10 = 38,
	C18ButtonFactorial = 39,
	C18ButtonSin = 40,
	C18ButtonCos = 41,
	C18ButtonTan = 42,
	C18ButtonE = 43,
	C18ButtonEE = 44,
	C18ButtonRad = 45,
	C18ButtonSinh = 46,
	C18ButtonCosh = 47,
	C18ButtonTanh = 48,
	C18ButtonPi = 49,
	C18ButtonRand = 50,
	C18ButtonAllClear = 51,
	C18ButtonDecimal = 52,        // the decimal key where the region's separator is "," (10 where it is ".")
	C18ButtonDeg = 53,            // the Rad key while it reads "Deg"
	C18ButtonPowerSwapped = 54,   // y^x
	C18ButtonTwoPower = 55,
	C18ButtonLogY = 56,           // log base y
	C18ButtonLog2 = 57,
	C18ButtonAsin = 58,
	C18ButtonAcos = 59,
	C18ButtonAtan = 60,
	C18ButtonAsinh = 61,
	C18ButtonAcosh = 62,
	C18ButtonAtanh = 63,
};

// Calculator's private API, declared so it can be called with plain messages.
@protocol C18CalculatorModel
- (void)buttonPressed:(NSInteger)button;
@end

@interface UIView (C18CalculatorKey)
- (NSInteger)accessibilityCalculatorButtonID;   // CalculatorKeypadButton
@end

static const NSInteger C18ExpressionTag = 0xC18;   // tag of the small expression label added to the display

// The id of a CalculatorKeypadButton (the value buttonPressed: gets for it), 0 for any other view.
static inline NSInteger C18KeyID(UIView *view) {
	if (![view respondsToSelector:@selector(accessibilityCalculatorButtonID)]) return 0;
	return [view accessibilityCalculatorButtonID];
}

// Calculator changes the id of some keys when they show their other face (CalculatorKeypadView's
// setShowingAlternate:button: and CalculatorButton.shiftedButton in 17.1.1): the decimal key is 10 or 52 depending
// on the region, Rad/Deg 45 or 53, the clear key 1 or 51, and 2nd swaps the keys below for 54...63. One id per key:
// the one the layouts use.
static inline NSInteger C18BaseKeyID(NSInteger identifier) {
	switch (identifier) {
		case C18ButtonPoint: return C18ButtonDecimal;
		case C18ButtonDeg: return C18ButtonRad;
		case C18ButtonAllClear: return C18ButtonClear;
		case C18ButtonPowerSwapped: return C18ButtonExp;
		case C18ButtonTwoPower: return C18ButtonTenPower;
		case C18ButtonLogY: return C18ButtonLn;
		case C18ButtonLog2: return C18ButtonLog10;
		case C18ButtonAsin: return C18ButtonSin;
		case C18ButtonAcos: return C18ButtonCos;
		case C18ButtonAtan: return C18ButtonTan;
		case C18ButtonAsinh: return C18ButtonSinh;
		case C18ButtonAcosh: return C18ButtonCosh;
		case C18ButtonAtanh: return C18ButtonTanh;
	}
	return identifier;
}

static inline BOOL C18IsDecimalKey(NSInteger identifier) {
	return identifier == C18ButtonPoint || identifier == C18ButtonDecimal;
}

#ifdef __cplusplus
extern "C" {
#endif

// Tracker.m: follows the keys and builds the expression.
extern BOOL c18ShowingResult;
void C18Track(NSInteger button);
NSString *C18CurrentExpression(void);
BOOL C18DeleteMode(void);
void C18SetDisplayText(NSString *text);
BOOL C18InTransient(void);
void C18EndTransient(void);
BOOL C18CanDropLastOperator(void);
NSArray<NSNumber *> *C18KeysWithoutLast(void);

// Display.m: shows the expression in the display view.
extern __weak UIView *c18DisplayView;
extern BOOL c18Overrode;
extern BOOL c18Rotating;
void C18Apply(UIView *displayView);
void C18ForgetDisplayState(void);

// ClearKey.m: the clear key that becomes a delete key.
extern __weak UIView *c18Keypad;
void C18UpdateClearKey(void);   // soon: once per pass of the main queue
void C18ClearLabelChanged(UILabel *label);
BOOL C18InterceptKey(id model, NSInteger *button);

// Keypad.m: the keypad views, their heights and iOS 18's layouts (landscape basic and scientific, portrait scientific).
BOOL C18IsLandscape(UIView *view);
UIViewController *C18KeypadController(UIView *anchor);
NSArray<UIView *> *C18AllKeypads(UIView *anchor);
BOOL C18ScientificNow(UIView *view);
void C18SelectKeypad(BOOL scientific, BOOL landscape, UIView *anchor);
void C18AdjustDisplayHeight(UIView *root);
void C18RelayoutWindow(UIWindow *window);
void C18LayoutKeypad(UIView *keypad);   // also places the portrait calculator key
void C18CenterZeroLabel(UIView *key);
void C18AdjustKeyLabels(UIView *key);

// ModeKey.m: the calculator key (its menu switches keypads and opens a new note).
void C18PlaceModeKey(UIView *keypad, CGRect frame, UIView *digitKey);
void C18LayoutPortraitModeKey(UIView *keypad, NSDictionary<NSNumber *, UIView *> *keys);

// NewNote.m: the new note the calculator key opens (through SpringBoard).
void C18OpenNewNote(void);
void C18ListenForNewNote(void);

// Debug.m: layout dumps, in debug builds only.
#ifdef C18_DEBUG
void C18DebugKeypadLayout(UIView *keypad);
#else
#define C18DebugKeypadLayout(keypad)
#endif

#ifdef __cplusplus
}
#endif
