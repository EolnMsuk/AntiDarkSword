#import <Foundation/Foundation.h>

#ifdef DEBUG
    #define ADSLog(fmt, ...) NSLog(@"[AntiDarkSword] %s [Line %d] " fmt, __PRETTY_FUNCTION__, __LINE__, ##__VA_ARGS__)
#else
    #define ADSLog(fmt, ...) ((void)0)
#endif
