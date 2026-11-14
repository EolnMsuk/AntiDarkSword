#import <UIKit/UIKit.h>

// This helper is linked into the PreferenceLoader bundle only.
@interface ADSUpdateChecker : NSObject
+ (instancetype)sharedChecker;
- (void)checkForController:(UIViewController *)controller
         installedVersion:(NSString *)version
                   manual:(BOOL)manual
                 finished:(dispatch_block_t)finished;
@end

FOUNDATION_EXPORT NSString *ADSInstalledPreferencesVersion(Class owningClass);
