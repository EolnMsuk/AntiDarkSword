#import <Preferences/PSListController.h>
#import <spawn.h>

@interface AntiDarkSwordPrefsRootListController : PSListController
@end

@implementation AntiDarkSwordPrefsRootListController

- (NSArray *)specifiers {
    if (!_specifiers) {
        _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    }
    return _specifiers;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    UIBarButtonItem *respringButton = [[UIBarButtonItem alloc] initWithTitle:@"Respring" 
                                                                       style:UIBarButtonItemStyleDone 
                                                                      target:self 
                                                                      action:@selector(respring)];
    self.navigationItem.rightBarButtonItem = respringButton;
}

- (void)respring {
    pid_t pid;
    const char* args[] = {"sbreload", NULL};
    posix_spawn(&pid, "/var/jb/usr/bin/sbreload", NULL, NULL, (char* const*)args, NULL);
}

@end
