// ADSLogging.h
#import <Foundation/Foundation.h>

// Always log file, function, and line number (Debug + Release)
#define ADSLog(fmt, ...) NSLog(@"[AntiDarkSword] %s [Line %d] " fmt, __PRETTY_FUNCTION__, __LINE__, ##__VA_ARGS__)


// ADSLogging.h
//#import <Foundation/Foundation.h>

//#ifdef DEBUG
    // In debug builds, log the file name, function name, and line number
//    #define ADSLog(fmt, ...) NSLog(@"[AntiDarkSword] %s [Line %d] " fmt, __PRETTY_FUNCTION__, __LINE__, ##__VA_ARGS__)
//#else
    // In release builds suppress all logging to avoid leaking operational details
//    #define ADSLog(fmt, ...) ((void)0)
//#endif
