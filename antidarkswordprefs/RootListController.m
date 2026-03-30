#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <spawn.h>

#define PREFS_PATH @"/var/jb/var/mobile/Library/Preferences/com.eolnmsuk.antidarkswordprefs.plist"

// -------------------------------------------------------------------------
// Subclass AltList to inject a persistent "Save" button in the App List view
// -------------------------------------------------------------------------
@interface ATLApplicationListMultiSelectionController : PSListController
@end

@interface AntiDarkSwordAppListController : ATLApplicationListMultiSelectionController
@end

@implementation AntiDarkSwordAppListController
- (void)viewDidLoad {
    [super viewDidLoad];
    UIBarButtonItem *saveButton = [[UIBarButtonItem alloc] initWithTitle:@"Save" 
                                                                   style:UIBarButtonItemStyleDone 
                                                                  target:self 
                                                                  action:@selector(savePrompt)];
    self.navigationItem.rightBarButtonItem = saveButton;
}

- (void)savePrompt {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Save" message:@"Apply changes now?" preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Later" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Respring" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        pid_t pid;
        const char* args[] = {"sbreload", NULL};
        posix_spawn(&pid, "/var/jb/usr/bin/sbreload", NULL, NULL, (char* const*)args, NULL);
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}
@end

// -------------------------------------------------------------------------
// Main Preferences Controller
// -------------------------------------------------------------------------
@interface AntiDarkSwordPrefsRootListController : PSListController
@end

@implementation AntiDarkSwordPrefsRootListController

- (NSArray *)specifiers {
    if (!_specifiers) {
        // Dynamically load AltList
        NSBundle *altListBundle = [NSBundle bundleWithPath:@"/var/jb/Library/Frameworks/AltList.framework"];
        if (![altListBundle isLoaded]) {
            [altListBundle load];
        }
        
        NSMutableArray *specs = [[self loadSpecifiersFromPlistName:@"Root" target:self] mutableCopy];
        
        // Find index to insert dynamic custom ID switches
        NSUInteger insertIndex = NSNotFound;
        for (NSUInteger i = 0; i < specs.count; i++) {
            PSSpecifier *s = specs[i];
            if ([s.identifier isEqualToString:@"AddCustomIDButton"]) {
                insertIndex = i + 1;
                break;
            }
        }
        
        NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:PREFS_PATH];
        NSArray *customIDs = prefs[@"customDaemonIDs"] ?: @[];
        
        if (insertIndex != NSNotFound) {
            for (NSString *daemonID in customIDs) {
                PSSpecifier *spec = [PSSpecifier preferenceSpecifierNamed:daemonID
                                                                   target:self
                                                                      set:@selector(setCustomIDValue:specifier:)
                                                                      get:@selector(readCustomIDValue:)
                                                                   detail:nil
                                                                     cell:PSSwitchCell
                                                                     edit:nil];
                [spec setProperty:daemonID forKey:@"daemonID"];
                [specs insertObject:spec atIndex:insertIndex++];
            }
        }
        
        _specifiers = [specs copy];
    }
    return _specifiers;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    UIBarButtonItem *saveButton = [[UIBarButtonItem alloc] initWithTitle:@"Save" 
                                                                   style:UIBarButtonItemStyleDone 
                                                                  target:self 
                                                                  action:@selector(savePrompt)];
    self.navigationItem.rightBarButtonItem = saveButton;
}

// Dynamic getter syncing Custom IDs with AltList's array
- (id)readCustomIDValue:(PSSpecifier*)specifier {
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:PREFS_PATH];
    NSArray *restricted = prefs[@"restrictedApps"] ?: @[];
    NSString *daemonID = [specifier propertyForKey:@"daemonID"];
    return @([restricted containsObject:daemonID]);
}

// Dynamic setter syncing Custom IDs with AltList's array
- (void)setCustomIDValue:(id)value specifier:(PSSpecifier*)specifier {
    NSMutableDictionary *prefs = [NSMutableDictionary dictionaryWithContentsOfFile:PREFS_PATH] ?: [NSMutableDictionary dictionary];
    NSMutableArray *restricted = [NSMutableArray arrayWithArray:prefs[@"restrictedApps"] ?: @[]];
    NSString *daemonID = [specifier propertyForKey:@"daemonID"];
    BOOL enabled = [value boolValue];
    
    if (enabled && ![restricted containsObject:daemonID]) {
        [restricted addObject:daemonID];
    } else if (!enabled && [restricted containsObject:daemonID]) {
        [restricted removeObject:daemonID];
    }
    
    prefs[@"restrictedApps"] = restricted;
    [prefs writeToFile:PREFS_PATH atomically:YES];
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFSTR("com.eolnmsuk.antidarkswordprefs/saved"), NULL, NULL, YES);
}

- (void)addCustomID {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Add Custom ID" message:@"Enter bundle ID or process name" preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
        textField.placeholder = @"com.apple.imagent";
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Add" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        NSString *newID = alert.textFields.firstObject.text;
        if (newID.length > 0) {
            NSMutableDictionary *prefs = [NSMutableDictionary dictionaryWithContentsOfFile:PREFS_PATH] ?: [NSMutableDictionary dictionary];
            NSMutableArray *customIDs = [NSMutableArray arrayWithArray:prefs[@"customDaemonIDs"] ?: @[]];
            if (![customIDs containsObject:newID]) {
                [customIDs addObject:newID];
                prefs[@"customDaemonIDs"] = customIDs;
                
                // Also default to ON and sync with restrictions when added
                NSMutableArray *restricted = [NSMutableArray arrayWithArray:prefs[@"restrictedApps"] ?: @[]];
                if (![restricted containsObject:newID]) {
                    [restricted addObject:newID];
                    prefs[@"restrictedApps"] = restricted;
                }
                
                [prefs writeToFile:PREFS_PATH atomically:YES];
                
                // Fully reload UI to render new switch
                [self reloadSpecifiers];
                CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFSTR("com.eolnmsuk.antidarkswordprefs/saved"), NULL, NULL, YES);
            }
        }
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)resetToDefaults {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Reset to Defaults" message:@"Respring required to apply changes." preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Respring" style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
        [[NSFileManager defaultManager] removeItemAtPath:PREFS_PATH error:nil];
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFSTR("com.eolnmsuk.antidarkswordprefs/saved"), NULL, NULL, YES);
        [self respring];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)savePrompt {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Save" message:@"Apply changes with respring?" preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Respring" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        [self respring];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)respring {
    pid_t pid;
    const char* args[] = {"sbreload", NULL};
    posix_spawn(&pid, "/var/jb/usr/bin/sbreload", NULL, NULL, (char* const*)args, NULL);
}

@end
