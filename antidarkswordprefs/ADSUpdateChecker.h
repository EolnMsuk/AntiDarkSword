#import <UIKit/UIKit.h>

// Manual Updates action only; no automatic checks, timer or persisted cadence.
// This helper is linked into the PreferenceLoader bundle only.
@interface ADSUpdateChecker : NSObject
+ (instancetype)sharedChecker;
- (void)checkForController:(UIViewController *)controller
         installedVersion:(NSString *)version
                 finished:(dispatch_block_t)finished;
@end

FOUNDATION_EXPORT NSString *ADSInstalledPreferencesVersion(Class owningClass);
