#import <UIKit/UIKit.h>

// Copies argv immediately, then spawns/waits on a serial worker. Explicit UI
// process controls only; never called by update or donation helpers.
void ADSRunCommand(NSString *executable, const char * const *arguments, UIViewController *presenter);
