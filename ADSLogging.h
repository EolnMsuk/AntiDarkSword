// ADSLogging.h
#import <Foundation/Foundation.h>

#ifdef DEBUG
    // In debug builds, log the file name, function name, and line number
    #define ADSLog(fmt, ...) NSLog(@"[AntiDarkSword] %s [Line %d] " fmt, __PRETTY_FUNCTION__, __LINE__, ##__VA_ARGS__)
#else
    // In release builds, keep it clean and minimal
    #define ADSLog(fmt, ...) NSLog(@"[AntiDarkSword] " fmt, ##__VA_ARGS__)
#endif
