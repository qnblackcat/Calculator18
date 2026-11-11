#import <Foundation/Foundation.h>

#ifdef __cplusplus
extern "C" {
#endif

// C18Log is the only way to log, and it does nothing unless Debug is on (Settings → Calculator18 →
// Troubleshooting). A macro, so the arguments are not even evaluated when Debug is off. While on, each line goes
// to the unified log with the "[Calculator18]" prefix and is appended to this process's log file.
//
// Log files live in the first directory that process may write to, one per process (Calculator.log,
// SpringBoard.log, Preferences.log), each capped at C18LogFileMaxBytes and rotated to <name>.1.

#define C18LogFileMaxBytes (128 * 1024)

#define C18Log(fmt, ...) do { if (C18DebugEnabled()) C18LogWrite(@"" fmt, ##__VA_ARGS__); } while (0)

// What C18Log calls once Debug is known to be on; don't call it directly.
void C18LogWrite(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);

// Read from the notify state SpringBoard publishes (C18_DEBUG_STATE), so it also works in Calculator's sandbox.
BOOL C18DebugEnabled(void);

// All processes' logs merged by time, newest last, limited to the last maxBytes characters.
NSString *C18LogFileRead(NSUInteger maxBytes);
void C18LogFileClear(void);

#ifdef __cplusplus
}
#endif
