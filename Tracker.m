#import "Calculator18.h"

static NSMutableArray<NSString *> *c18Tokens;   // finished numbers (raw, "." decimal) and operator symbols
static NSString *c18LastText = @"0";            // raw text the display showed before the current key press
static BOOL c18AwaitingOperand;                 // an operator was just pressed
BOOL c18ShowingResult;                          // "=" was just pressed
static int c18Transient;                        // the first digit after an operator makes Calculator update twice: "0", then the digit
static NSString *c18ResultExpression;           // the expression "=" evaluated, raw tokens joined
static NSString *c18RepeatOperator;             // last operator and its operand, reapplied by every further "="
static NSString *c18RepeatOperand;
static NSString *c18Operand;                    // how the operand being entered reads when a function made it ("9²", "sin(30)"), else nil
static BOOL c18ResultFromFunction;              // the result on show came from a function key, not "="
static NSString *c18Expression;                 // what C18CurrentExpression last gave, while c18ExpressionStale is NO
static BOOL c18ExpressionStale = YES;           // the state it was built from has changed since
static NSMutableArray<NSNumber *> *c18KeySeq;   // keys that built the expression, to type it again without its last operator

// Binary operators: + - x / and the scientific keys that take a second number (x^y, y^x, y-th root, log base y).
static NSString *C18OperatorSymbol(NSInteger button) {
	switch (button) {
		case C18ButtonAdd: return @"+";
		case C18ButtonSubtract: return @"−";
		case C18ButtonMultiply: return @"×";
		case C18ButtonDivide: return @"÷";
		case C18ButtonPower: case C18ButtonPowerSwapped: return @"^";
		case C18ButtonRoot: return @"ʸ√";
		case C18ButtonLogY: return @"logᵧ";
	}
	return nil;
}

// The symbols C18OperatorSymbol gives.
static BOOL C18IsOperator(NSString *token) {
	static NSSet<NSString *> *operators;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ operators = [NSSet setWithObjects:@"+", @"−", @"×", @"÷", @"^", @"ʸ√", @"logᵧ", nil]; });
	return token && [operators containsObject:token];
}

// Functions of the number being entered, by the id Calculator's model gets (the 2nd ids differ from the stock ones).
// The format wraps the operand; `group` says the operand gets parentheses when it is not a plain number.
static NSString *C18UnaryFormat(NSInteger button, BOOL *group) {
	*group = YES;
	switch (button) {
		case C18ButtonSquare: return @"%@²";
		case C18ButtonCube: return @"%@³";
		case C18ButtonExp: return @"e^%@";
		case C18ButtonTenPower: return @"10^%@";
		case C18ButtonTwoPower: return @"2^%@";
		case C18ButtonReciprocal: return @"1/%@";
		case C18ButtonSquareRoot: return @"√%@";
		case C18ButtonCubeRoot: return @"∛%@";
		case C18ButtonFactorial: return @"%@!";
		case C18ButtonPercent: return @"%@%%";
	}
	*group = NO;
	switch (button) {
		case C18ButtonLn: return @"ln(%@)";
		case C18ButtonLog10: return @"log₁₀(%@)";
		case C18ButtonLog2: return @"log₂(%@)";
		case C18ButtonSin: return @"sin(%@)";
		case C18ButtonCos: return @"cos(%@)";
		case C18ButtonTan: return @"tan(%@)";
		case C18ButtonAsin: return @"sin⁻¹(%@)";
		case C18ButtonAcos: return @"cos⁻¹(%@)";
		case C18ButtonAtan: return @"tan⁻¹(%@)";
		case C18ButtonSinh: return @"sinh(%@)";
		case C18ButtonCosh: return @"cosh(%@)";
		case C18ButtonTanh: return @"tanh(%@)";
		case C18ButtonAsinh: return @"sinh⁻¹(%@)";
		case C18ButtonAcosh: return @"cosh⁻¹(%@)";
		case C18ButtonAtanh: return @"tanh⁻¹(%@)";
	}
	return nil;
}

// "1234567.5" -> "1,234,567.5" using the current locale's separators. Raw text that is not a plain
// decimal number (scientific notation, "Error") is returned untouched.
static NSString *C18FormatNumber(NSString *raw) {
	BOOL negative = [raw hasPrefix:@"-"];
	NSString *body = negative ? [raw substringFromIndex:1] : raw;
	NSRange dot = [body rangeOfString:@"."];
	NSString *integer = dot.location == NSNotFound ? body : [body substringToIndex:dot.location];
	NSString *fraction = dot.location == NSNotFound ? nil : [body substringFromIndex:dot.location + 1];
	NSCharacterSet *nonDigits = [[NSCharacterSet decimalDigitCharacterSet] invertedSet];
	if (!integer.length || [integer rangeOfCharacterFromSet:nonDigits].location != NSNotFound) return raw;
	if (fraction && [fraction rangeOfCharacterFromSet:nonDigits].location != NSNotFound) return raw;

	// The separators are read once, and again when the region settings change.
	static NSString *group, *decimal;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		[[NSNotificationCenter defaultCenter] addObserverForName:NSCurrentLocaleDidChangeNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *notification) {
			group = decimal = nil;
			c18ExpressionStale = YES;
		}];
	});
	if (!group || !decimal) {
		NSLocale *locale = [NSLocale currentLocale];
		group = [locale objectForKey:NSLocaleGroupingSeparator] ?: @",";
		decimal = [locale objectForKey:NSLocaleDecimalSeparator] ?: @".";
	}

	NSMutableString *grouped = [NSMutableString string];
	for (NSUInteger i = 0; i < integer.length; i++) {
		if (i > 0 && (integer.length - i) % 3 == 0) [grouped appendString:group];
		[grouped appendString:[integer substringWithRange:NSMakeRange(i, 1)]];
	}
	NSMutableString *result = [NSMutableString string];
	if (negative) [result appendString:@"-"];
	[result appendString:grouped];
	if (fraction) [result appendFormat:@"%@%@", decimal, fraction];
	return result;
}

static BOOL C18IsCloseParen(NSString *token) {
	return [token isEqualToString:@")"];
}

static NSUInteger C18OpenParens(void) {
	NSInteger open = 0;
	for (NSString *token in c18Tokens) {
		if ([token isEqualToString:@"("]) open++;
		else if (C18IsCloseParen(token)) open--;
	}
	return MAX(open, 0);
}

static NSString *C18Join(NSArray<NSString *> *tokens, NSString *tail) {
	NSMutableString *string = [NSMutableString string];
	for (NSString *token in tokens) [string appendString:C18IsOperator(token) ? token : C18FormatNumber(token)];
	if (tail) [string appendString:C18FormatNumber(tail)];
	return string;
}

static BOOL c18Typing; // the number on the display was typed (not a result or a percentage), so it can be deleted from

static void C18Reset(void) {
	c18Typing = NO;
	c18Tokens = [NSMutableArray array];
	c18AwaitingOperand = NO;
	c18ShowingResult = NO;
	c18ResultExpression = nil;
	c18ResultFromFunction = NO;
	c18Operand = nil;
	c18KeySeq = [NSMutableArray array];
	c18Transient = 0;
}

// A plain number (or a constant), which needs no parentheses around it.
static BOOL C18IsPlainOperand(NSString *operand) {
	static NSCharacterSet *plain;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ plain = [NSCharacterSet characterSetWithCharactersInString:@"0123456789,.' −-πe"]; });
	return [operand rangeOfCharacterFromSet:[plain invertedSet]].location == NSNotFound;
}

// The decimal key Calculator has: 52 ("," key) where the region's separator is a comma, else 10 ("." key).
static NSInteger C18DecimalKeyForRegion(void) {
	return [[NSLocale currentLocale].decimalSeparator isEqualToString:@","] ? C18ButtonDecimal : C18ButtonPoint;
}

// The key presses that type `text` (a result, raw: "." is its decimal point), so an expression that continues from it
// can be typed again.
static void C18SeedKeys(NSString *text) {
	c18KeySeq = [NSMutableArray array];
	BOOL negative = [text hasPrefix:@"-"];
	for (NSUInteger i = negative ? 1 : 0; i < text.length; i++) {
		unichar character = [text characterAtIndex:i];
		if (character >= '0' && character <= '9') [c18KeySeq addObject:@(C18ButtonDigit0 + (character - '0'))];
		else if (character == '.') [c18KeySeq addObject:@(C18DecimalKeyForRegion())];
		else { c18KeySeq = [NSMutableArray array]; return; }   // "Error", an exponent: cannot be typed
	}
	if (negative) [c18KeySeq addObject:@(C18ButtonNegate)];
}

static BOOL C18IsEntryKey(NSInteger key) {
	return (key >= C18ButtonDigit0 && key <= C18ButtonDigit9) || C18IsDecimalKey(key) || key == C18ButtonNegate;
}

// Called before the model handles the key, while c18LastText is still the previous display text.
void C18Track(NSInteger button) {
	c18ExpressionStale = YES;
	if (!c18Tokens) C18Reset();

	// The digit already arrived but no second update followed, so it is now the operand.
	if (c18Transient) {
		c18Transient = 0;
		c18AwaitingOperand = NO;
	}

	BOOL group;
	NSString *unary = C18UnaryFormat(button, &group);

	if (button == C18ButtonAllClear) {
		C18Reset();
		c18RepeatOperator = c18RepeatOperand = nil;
	} else if ((button >= C18ButtonDigit0 && button <= C18ButtonDigit9) || C18IsDecimalKey(button)) {
		if (c18ShowingResult) C18Reset();
		c18Operand = nil;
		c18Typing = YES;
		[c18KeySeq addObject:@(button)];
		// Keep showing "17+" until the digit itself arrives, so "17+0" never flashes.
		if (c18AwaitingOperand) c18Transient = 1;
	} else if (C18OperatorSymbol(button)) {
		if (c18ShowingResult) {
			c18Tokens = [NSMutableArray arrayWithObject:c18Operand ?: c18LastText];
			c18ShowingResult = NO;
			c18ResultFromFunction = NO;
			C18SeedKeys(c18LastText);
		} else if (c18AwaitingOperand && C18IsOperator(c18Tokens.lastObject)) {
			[c18Tokens removeLastObject];
			if (c18KeySeq.count) [c18KeySeq removeLastObject];
		} else if (!C18IsCloseParen(c18Tokens.lastObject)) {
			// (After ")" the group is the operand, already in the tokens.)
			[c18Tokens addObject:c18Operand ?: c18LastText];
		}
		c18Operand = nil;
		[c18Tokens addObject:C18OperatorSymbol(button)];
		[c18KeySeq addObject:@(button)];
		c18AwaitingOperand = YES;
		c18Typing = NO;
	} else if (button == C18ButtonEquals) {
		if (c18Tokens.count) {
			// With a pending operator and no second number, Calculator reuses the display as the operand.
			for (NSString *token in [c18Tokens reverseObjectEnumerator]) {
				if (C18IsOperator(token)) {
					c18RepeatOperator = token;
					break;
				}
			}
			NSString *tail = c18Operand ?: c18LastText;
			c18RepeatOperand = tail;
			c18ResultExpression = C18Join(c18Tokens, C18IsCloseParen(c18Tokens.lastObject) ? nil : tail);
			c18ResultFromFunction = NO;
		} else if (c18RepeatOperator && !c18ResultFromFunction) {
			// Another "=": the last operation is applied again to the number on the display.
			c18ResultExpression = C18Join(@[c18LastText, c18RepeatOperator], c18RepeatOperand);
		} else if (!c18ShowingResult) {
			c18ResultExpression = nil;
		}
		c18Tokens = [NSMutableArray array];
		c18Operand = nil;
		c18KeySeq = [NSMutableArray array];
		c18AwaitingOperand = NO;
		c18ShowingResult = YES;
		c18Typing = NO;
	} else if (button == C18ButtonOpenParen) {
		if (c18ShowingResult) C18Reset();
		[c18Tokens addObject:@"("];
		[c18KeySeq addObject:@(button)];
		c18AwaitingOperand = YES;
		c18Typing = NO;
	} else if (button == C18ButtonCloseParen) {
		if (C18OpenParens() && !c18AwaitingOperand) {
			if (!C18IsCloseParen(c18Tokens.lastObject)) [c18Tokens addObject:c18Operand ?: c18LastText];
			[c18Tokens addObject:@")"];
			[c18KeySeq addObject:@(button)];
			c18Operand = nil;
			c18Typing = NO;
		}
	} else if (unary) {
		// A function of the number on the display: "9" and x² read "9²". With nothing pending the expression
		// goes above the result, like "=" does; in the middle of a sum it is the operand.
		NSString *base = c18ShowingResult && c18ResultFromFunction && c18ResultExpression ? c18ResultExpression : (c18Operand ?: C18FormatNumber(c18LastText));
		if (group && !C18IsPlainOperand(base)) base = [NSString stringWithFormat:@"(%@)", base];
		NSString *wrapped = [NSString stringWithFormat:unary, base];
		if (c18Tokens.count) {
			c18Operand = wrapped;
		} else {
			c18ResultExpression = wrapped;
			c18ShowingResult = YES;
			c18ResultFromFunction = YES;
			c18Operand = nil;
		}
		[c18KeySeq addObject:@(button)];
		c18AwaitingOperand = NO;
		c18Typing = NO;
	} else if (button == C18ButtonPi || button == C18ButtonE) {
		// pi and e: the number being entered (the display shows the value).
		if (c18ShowingResult) C18Reset();
		c18Operand = button == C18ButtonPi ? @"π" : @"e";
		[c18KeySeq addObject:@(button)];
		c18AwaitingOperand = NO;
		c18Typing = NO;
	} else if (button == C18ButtonRand || button == C18ButtonMemoryRecall) {
		// Rand and mr: a number the keypad produced.
		if (c18ShowingResult) C18Reset();
		c18Operand = nil;
		[c18KeySeq addObject:@(button)];
		c18AwaitingOperand = NO;
		c18Typing = NO;
	} else if (button == C18ButtonNegate) {
		if (c18ShowingResult) C18Reset();
		if (c18Operand) {
			// "-(...)" again takes the sign off.
			c18Operand = [c18Operand hasPrefix:@"−("] && [c18Operand hasSuffix:@")"] ? [c18Operand substringWithRange:NSMakeRange(2, c18Operand.length - 3)] : [NSString stringWithFormat:@"−(%@)", c18Operand];
		}
		[c18KeySeq addObject:@(button)];
		c18AwaitingOperand = NO;
	} else if (button == C18ButtonDelete) {
		// Deleting the only digit of the second number leaves the display at 0 with the operator still pending.
		NSString *digits = [c18LastText stringByReplacingOccurrencesOfString:@"-" withString:@""];
		if (c18Tokens.count && !c18AwaitingOperand && !c18ShowingResult && digits.length == 1) c18AwaitingOperand = YES;
		c18Operand = nil;
		if (C18IsEntryKey(c18KeySeq.lastObject.integerValue)) [c18KeySeq removeLastObject];
	} else if (button == C18ButtonClear) {
		c18Typing = NO;
		c18Operand = nil;
		while (c18KeySeq.count && !C18OperatorSymbol(c18KeySeq.lastObject.integerValue) && c18KeySeq.lastObject.integerValue != C18ButtonOpenParen) [c18KeySeq removeLastObject];
		if (c18ShowingResult) C18Reset();
		else if (c18Tokens.count) c18AwaitingOperand = YES;
	}
}

// The expression to show instead of the plain number, or nil to leave the display alone.
// Asked several times per key press (every display layout), so it is only built again after the state changes.
NSString *C18CurrentExpression(void) {
	if (!c18ExpressionStale) return c18Expression;
	if (c18ShowingResult) c18Expression = c18ResultExpression;
	else if (!c18Tokens.count) c18Expression = nil;
	else c18Expression = C18Join(c18Tokens, c18AwaitingOperand || C18IsCloseParen(c18Tokens.lastObject) ? nil : (c18Operand ?: c18LastText));
	c18ExpressionStale = NO;
	return c18Expression;
}

// iOS 18 turns the clear key into a delete key for as long as there is something to delete. It keeps its
// normal clear behaviour after "=" and when the display is 0 with nothing pending.
BOOL C18DeleteMode(void) {
	if (c18ShowingResult || c18Transient) return NO;
	if (c18Tokens.count && c18AwaitingOperand) return YES;
	return c18Typing && ![c18LastText isEqualToString:@"0"];
}

// The display has changed to `text` (nil: it is not text).
void C18SetDisplayText(NSString *text) {
	if (!text || [text isEqualToString:c18LastText]) return;
	c18LastText = text;
	c18ExpressionStale = YES;
}

BOOL C18InTransient(void) {
	return c18Transient > 0;
}

// The "0" before the first digit of an operand has been shown: what follows is the operand.
void C18EndTransient(void) {
	c18ExpressionStale = YES;
	c18Transient = 0;
	c18AwaitingOperand = NO;
}

// An operator (or an open parenthesis) ends the expression, and the keys that typed it are known.
BOOL C18CanDropLastOperator(void) {
	return c18AwaitingOperand && c18Tokens.count && c18KeySeq.count;
}

// The keys that typed the expression, without the last one.
NSArray<NSNumber *> *C18KeysWithoutLast(void) {
	NSMutableArray<NSNumber *> *keys = [c18KeySeq mutableCopy];
	[keys removeLastObject];
	return keys;
}
