// ADSLogging.h
#import <Foundation/Foundation.h>

// Always log file, function, and line number (Debug + Release)
#define ADSLog(fmt, ...) NSLog(@"[AntiDarkSword] %s [Line %d] " fmt, __PRETTY_FUNCTION__, __LINE__, ##__VA_ARGS__)
