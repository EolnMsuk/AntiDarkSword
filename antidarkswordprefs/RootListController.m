#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <spawn.h>
#import <objc/runtime.h>

#define PREFS_PATH @"/var/jb/var/mobile/Library/Preferences/com.eolnmsuk.antidarkswordprefs.plist"

@interface AntiDarkSwordPrefsRootListController : PSListController
@end

@implementation AntiDarkSwordPrefsRootListController

// We use +initialize so the dynamic class is registered the moment Preferences.app 
// loads our root controller, ensuring it exists before the user taps "Select Apps..."
+ (void)initialize {
    if (self == [AntiDarkSwordPrefsRootListController class]) {
        
        // 1. Ensure AltList is loaded into memory first
        NSBundle *altListBundle = [NSBundle bundleWithPath:@"/var/jb/Library/Frameworks/AltList.framework"];
        if (![altListBundle isLoaded]) {
            [altListBundle load];
        }
        
        // 2. Dynamically create the subclass to avoid compile-time CI linker errors
        Class altListClass = NSClassFromString(@"ATLApplicationListMultiSelectionController");
        if (altListClass && !NSClassFromString(@"AntiDarkSwordAppListController")) {
            
            // Allocate the new class: AntiDarkSwordAppListController : ATLApplicationListMultiSelectionController
            Class newClass = objc_allocateClassPair(altListClass, "AntiDarkSwordAppListController", 0);
            if (newClass) {
                
                // Inject viewWillAppear: to add the persistent Save button
                SEL viewWillAppearSel = @selector(viewWillAppear:);
                Method originalMethod = class_getInstanceMethod(altListClass, viewWillAppearSel);
                
                IMP customViewWillAppearImp = imp_implementationWithBlock(^(id _self, BOOL animated) {
                    // Call the original viewWillAppear: implementation safely
                    if (originalMethod) {
                        void (*originalMsg)(id, SEL, BOOL) = (void (*)(id, SEL, BOOL))method_getImplementation(originalMethod);
                        originalMsg(_self, viewWillAppearSel, animated);
                    }
                    
                    // Inject our Save button into the navigation bar
                    UIBarButtonItem *saveButton = [[UIBarButtonItem alloc] initWithTitle:@"Save" 
                                                                                   style:UIBarButtonItemStyleDone 
                                                                                  target:_self 
                                                                                  action:@selector(savePrompt)];
                    ((UIViewController *)_self).navigationItem.rightBarButtonItem = saveButton;
                });
                
                // If originalMethod is somehow null, default to "v@:B" (void return, id self, SEL cmd, BOOL arg)
                class_addMethod(newClass, viewWillAppearSel, customViewWillAppearImp, originalMethod ? method_getTypeEncoding(originalMethod) : "v@:B");
                
                // Inject the savePrompt action method
                SEL savePromptSel = @selector(savePrompt);
                IMP savePromptImp = imp_implementationWithBlock(^(id _self) {
                    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Save" message:@"Apply changes now?" preferredStyle:UIAlertControllerStyleAlert];
                    [alert addAction:[UIAlertAction actionWithTitle:@"Later" style:UIAlertActionStyleCancel handler:nil]];
                    [alert addAction:[UIAlertAction actionWithTitle:@"Respring" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
                        pid_t pid;
                        const char* args[] = {"sbreload", NULL};
                        posix_spawn(&pid, "/var/jb/usr/bin/sbreload", NULL, NULL, (char* const*)args, NULL);
                    }]];
                    [((UIViewController *)_self) presentViewController:alert animated:YES completion:nil];
                });
                class_addMethod(newClass, savePromptSel, savePromptImp, "v@:");
                
                // Finalize and register the class globally
                objc_registerClassPair(newClass);
            }
        }
    }
}

- (NSArray *)specifiers {
    if (!_specifiers) {
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
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Add Custom ID" message:@"Enter bundle IDs or process names (comma-separated)" preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
        textField.placeholder = @"com.apple.imagent, mediaserverd";
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Add" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        NSString *inputText = alert.textFields.firstObject.text;
        if (inputText.length > 0) {
            // Split the input string by commas
            NSArray *inputIDs = [inputText componentsSeparatedByString:@","];
            
            NSMutableDictionary *prefs = [NSMutableDictionary dictionaryWithContentsOfFile:PREFS_PATH] ?: [NSMutableDictionary dictionary];
            NSMutableArray *customIDs = [NSMutableArray arrayWithArray:prefs[@"customDaemonIDs"] ?: @[]];
            NSMutableArray *restricted = [NSMutableArray arrayWithArray:prefs[@"restrictedApps"] ?: @[]];
            
            BOOL changesMade = NO;
            
            // Loop through each pasted ID, trim whitespace, and add it
            for (NSString *rawID in inputIDs) {
                NSString *cleanID = [rawID stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                
                if (cleanID.length > 0 && ![customIDs containsObject:cleanID]) {
                    [customIDs addObject:cleanID];
                    
                    if (![restricted containsObject:cleanID]) {
                        [restricted addObject:cleanID];
                    }
                    changesMade = YES;
                }
            }
            
            // Save and reload if we actually added valid new IDs
            if (changesMade) {
                prefs[@"customDaemonIDs"] = customIDs;
                prefs[@"restrictedApps"] = restricted;
                [prefs writeToFile:PREFS_PATH atomically:YES];
                
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
        
        // 1. Wipe CFPreferences (Settings App UI cache)
        NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"com.eolnmsuk.antidarkswordprefs"];
        [defaults removePersistentDomainForName:@"com.eolnmsuk.antidarkswordprefs"];
        [defaults synchronize];
        
        // 2. Overwrite the physical plist file to empty (Tweak.x reads this directly)
        [@{} writeToFile:PREFS_PATH atomically:YES];
        
        // 3. Delete the file to ensure a clean slate
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
