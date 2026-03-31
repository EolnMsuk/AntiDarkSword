#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <spawn.h>
#import <objc/runtime.h>

#define PREFS_PATH @"/var/jb/var/mobile/Library/Preferences/com.eolnmsuk.antidarkswordprefs.plist"

@interface AntiDarkSwordPrefsRootListController : PSListController
@end

@implementation AntiDarkSwordPrefsRootListController

+ (void)initialize {
    if (self == [AntiDarkSwordPrefsRootListController class]) {
        NSBundle *altListBundle = [NSBundle bundleWithPath:@"/var/jb/Library/Frameworks/AltList.framework"];
        if (![altListBundle isLoaded]) {
            [altListBundle load];
        }
        
        Class altListClass = NSClassFromString(@"ATLApplicationListMultiSelectionController");
        if (altListClass && !NSClassFromString(@"AntiDarkSwordAppListController")) {
            Class newClass = objc_allocateClassPair(altListClass, "AntiDarkSwordAppListController", 0);
            if (newClass) {
                SEL viewWillAppearSel = @selector(viewWillAppear:);
                Method originalMethod = class_getInstanceMethod(altListClass, viewWillAppearSel);
                
                IMP customViewWillAppearImp = imp_implementationWithBlock(^(id _self, BOOL animated) {
                    if (originalMethod) {
                        void (*originalMsg)(id, SEL, BOOL) = (void (*)(id, SEL, BOOL))method_getImplementation(originalMethod);
                        originalMsg(_self, viewWillAppearSel, animated);
                    }
                    UIBarButtonItem *saveButton = [[UIBarButtonItem alloc] initWithTitle:@"Save" 
                                                                                   style:UIBarButtonItemStyleDone 
                                                                                  target:_self 
                                                                                  action:@selector(savePrompt)];
                    ((UIViewController *)_self).navigationItem.rightBarButtonItem = saveButton;
                });
                
                class_addMethod(newClass, viewWillAppearSel, customViewWillAppearImp, originalMethod ? method_getTypeEncoding(originalMethod) : "v@:B");
                
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
                
                objc_registerClassPair(newClass);
            }
        }
    }
}

// Helper to get the lists for dynamic UI injection
- (NSArray *)autoProtectedItemsForLevel:(NSInteger)level {
    NSMutableArray *items = [NSMutableArray array];
    
    NSArray *tier1 = @[
        @"com.apple.mobilesafari", @"com.apple.MobileSMS", @"com.apple.mobilemail",
        @"com.apple.mobilecal", @"com.apple.mobilenotes", @"com.apple.iBooks",
        @"com.apple.news", @"com.apple.podcasts", @"com.apple.stocks", 
        @"com.apple.Maps", @"com.apple.weather",
        @"com.apple.SafariViewService", @"com.apple.MailCompositionService",
        @"com.apple.iMessageAppsViewService", @"com.apple.ActivityMessagesApp"
    ];
    
    NSArray *tier2 = @[
        @"com.google.chrome.ios", @"org.mozilla.ios.Firefox", @"com.brave.ios.browser", @"com.duckduckgo.mobile.ios",
        @"net.whatsapp.WhatsApp", @"ph.telegra.Telegraph", @"com.facebook.Facebook", @"com.atebits.Tweetie2", 
        @"com.burbn.instagram", @"com.zhiliaoapp.musically", @"com.linkedin.LinkedIn",
        @"org.coolstar.sileo", @"xyz.willy.Zebra", @"com.tigisoftware.Filza"
    ];
    
    NSArray *tier3 = @[
        @"com.apple.imagent", @"imagent", 
        @"mediaserverd", 
        @"networkd"
    ];
    
    [items addObjectsFromArray:tier1];
    if (level >= 2) [items addObjectsFromArray:tier2];
    if (level >= 3) [items addObjectsFromArray:tier3];
    
    return items;
}

- (NSArray *)specifiers {
    if (!_specifiers) {
        NSMutableArray *specs = [[self loadSpecifiersFromPlistName:@"Root" target:self] mutableCopy];
        
        NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"com.eolnmsuk.antidarkswordprefs"];
        BOOL autoProtect = [defaults boolForKey:@"autoProtectEnabled"];
        NSInteger autoProtectLevel = [defaults objectForKey:@"autoProtectLevel"] ? [defaults integerForKey:@"autoProtectLevel"] : 1;
        NSArray *customIDs = [defaults objectForKey:@"customDaemonIDs"] ?: @[];
        
        // 1. Gray out manual settings if Preset Rules are currently enabled
        for (PSSpecifier *s in specs) {
            if ([s.identifier isEqualToString:@"SelectApps"] || [s.identifier isEqualToString:@"AddCustomIDButton"]) {
                [s setProperty:@(!autoProtect) forKey:@"enabled"];
            }
        }
        
        // 2. Inject the dynamic "Actively Locked Down" visual list
        if (autoProtect) {
            NSUInteger insertIndexAuto = NSNotFound;
            for (NSUInteger i = 0; i < specs.count; i++) {
                PSSpecifier *s = specs[i];
                if ([s.identifier isEqualToString:@"AutoProtectLevelSegment"]) {
                    insertIndexAuto = i + 1;
                    break;
                }
            }
            
            if (insertIndexAuto != NSNotFound) {
                PSSpecifier *groupSpec = [PSSpecifier preferenceSpecifierNamed:@"Actively Locked Down by Preset" target:self set:nil get:nil detail:nil cell:PSGroupCell edit:nil];
                [specs insertObject:groupSpec atIndex:insertIndexAuto++];
                
                NSArray *autoItems = [self autoProtectedItemsForLevel:autoProtectLevel];
                for (NSString *item in autoItems) {
                    PSSpecifier *spec = [PSSpecifier preferenceSpecifierNamed:item target:self set:nil get:@selector(getAlwaysTrue:) detail:nil cell:PSSwitchCell edit:nil];
                    [spec setProperty:@NO forKey:@"enabled"]; 
                    [specs insertObject:spec atIndex:insertIndexAuto++];
                }
            }
        }
        
        // 3. Inject Custom IDs dynamically (Keep them visible, but gray them out if Preset Rules are ON)
        NSUInteger insertIndexCustom = NSNotFound;
        for (NSUInteger i = 0; i < specs.count; i++) {
            PSSpecifier *s = specs[i];
            if ([s.identifier isEqualToString:@"AddCustomIDButton"]) {
                insertIndexCustom = i + 1;
                break;
            }
        }
        
        if (insertIndexCustom != NSNotFound) {
            for (NSString *daemonID in customIDs) {
                PSSpecifier *spec = [PSSpecifier preferenceSpecifierNamed:daemonID
                                                                   target:self
                                                                      set:@selector(setCustomIDValue:specifier:)
                                                                      get:@selector(readCustomIDValue:)
                                                                   detail:nil
                                                                     cell:PSSwitchCell
                                                                     edit:nil];
                [spec setProperty:daemonID forKey:@"daemonID"];
                [spec setProperty:@YES forKey:@"isCustomDaemon"]; // Tag for swipe-to-delete
                [spec setProperty:@(!autoProtect) forKey:@"enabled"]; // Gray out existing switches if Preset Rules are ON
                [specs insertObject:spec atIndex:insertIndexCustom++];
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
    
    // Check if it's the first time opening settings to redirect to GitHub
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"com.eolnmsuk.antidarkswordprefs"];
    if (![defaults boolForKey:@"hasOpenedGitHubBefore"]) {
        [defaults setBool:YES forKey:@"hasOpenedGitHubBefore"];
        [defaults synchronize];
        
        NSURL *githubURL = [NSURL URLWithString:@"https://github.com/EolnMsuk/AntiDarkSword"];
        [[UIApplication sharedApplication] openURL:githubURL options:@{} completionHandler:nil];
    }
}

// Dummy getter for the Auto-Protect dynamic list (Forces them to appear as "ON")
- (id)getAlwaysTrue:(PSSpecifier*)specifier {
    return @YES;
}

- (void)setAutoProtect:(id)value specifier:(PSSpecifier*)specifier {
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"com.eolnmsuk.antidarkswordprefs"];
    [defaults setObject:value forKey:@"autoProtectEnabled"];
    [defaults synchronize];
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFSTR("com.eolnmsuk.antidarkswordprefs/saved"), NULL, NULL, YES);
    
    // Wipe cache and rebuild UI to apply the gray-out effect and show/hide the visual list
    _specifiers = nil;
    [self reloadSpecifiers];
}

- (void)setAutoProtectLevel:(id)value specifier:(PSSpecifier*)specifier {
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"com.eolnmsuk.antidarkswordprefs"];
    [defaults setObject:value forKey:@"autoProtectLevel"];
    [defaults synchronize];
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFSTR("com.eolnmsuk.antidarkswordprefs/saved"), NULL, NULL, YES);
    
    // Wipe cache and rebuild UI to refresh the visual list contents
    if ([defaults boolForKey:@"autoProtectEnabled"]) {
        _specifiers = nil;
        [self reloadSpecifiers];
    }
}

- (id)readCustomIDValue:(PSSpecifier*)specifier {
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"com.eolnmsuk.antidarkswordprefs"];
    NSArray *restricted = [defaults objectForKey:@"restrictedApps"] ?: @[];
    NSString *daemonID = [specifier propertyForKey:@"daemonID"];
    return @([restricted containsObject:daemonID]);
}

- (void)setCustomIDValue:(id)value specifier:(PSSpecifier*)specifier {
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"com.eolnmsuk.antidarkswordprefs"];
    NSMutableArray *restricted = [[defaults objectForKey:@"restrictedApps"] ?: @[] mutableCopy];
    
    NSString *daemonID = [specifier propertyForKey:@"daemonID"];
    BOOL enabled = [value boolValue];
    
    if (enabled && ![restricted containsObject:daemonID]) {
        [restricted addObject:daemonID];
    } else if (!enabled && [restricted containsObject:daemonID]) {
        [restricted removeObject:daemonID];
    }
    
    [defaults setObject:restricted forKey:@"restrictedApps"];
    [defaults synchronize]; 
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
            NSArray *inputIDs = [inputText componentsSeparatedByString:@","];
            
            NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"com.eolnmsuk.antidarkswordprefs"];
            NSMutableArray *customIDs = [[defaults objectForKey:@"customDaemonIDs"] ?: @[] mutableCopy];
            NSMutableArray *restricted = [[defaults objectForKey:@"restrictedApps"] ?: @[] mutableCopy];
            
            BOOL changesMade = NO;
            
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
            
            if (changesMade) {
                [defaults setObject:customIDs forKey:@"customDaemonIDs"];
                [defaults setObject:restricted forKey:@"restrictedApps"];
                [defaults synchronize];
                
                _specifiers = nil;
                [self reloadSpecifiers];
                CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFSTR("com.eolnmsuk.antidarkswordprefs/saved"), NULL, NULL, YES);
            }
        }
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

// Swipe-to-Delete Logic
- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    PSSpecifier *spec = [self specifierAtIndexPath:indexPath];
    // Don't allow swipe-to-delete if Preset Rules are turned on and locking the UI
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"com.eolnmsuk.antidarkswordprefs"];
    BOOL autoProtect = [defaults boolForKey:@"autoProtectEnabled"];
    
    if ([[spec propertyForKey:@"isCustomDaemon"] boolValue] && !autoProtect) {
        return YES;
    }
    return NO;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle == UITableViewCellEditingStyleDelete) {
        PSSpecifier *spec = [self specifierAtIndexPath:indexPath];
        NSString *daemonID = [spec propertyForKey:@"daemonID"];
        
        NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"com.eolnmsuk.antidarkswordprefs"];
        NSMutableArray *customIDs = [[defaults objectForKey:@"customDaemonIDs"] ?: @[] mutableCopy];
        NSMutableArray *restricted = [[defaults objectForKey:@"restrictedApps"] ?: @[] mutableCopy];
        
        [customIDs removeObject:daemonID];
        [restricted removeObject:daemonID];
        
        [defaults setObject:customIDs forKey:@"customDaemonIDs"];
        [defaults setObject:restricted forKey:@"restrictedApps"];
        [defaults synchronize];
        
        [self removeSpecifier:spec animated:YES];
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFSTR("com.eolnmsuk.antidarkswordprefs/saved"), NULL, NULL, YES);
    }
}

- (void)resetToDefaults {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Reset to Defaults" message:@"Respring required to apply changes." preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Respring" style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
        NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"com.eolnmsuk.antidarkswordprefs"];
        
        // Preserve the 'hasOpenedGitHubBefore' flag so they aren't forced to open it again
        BOOL hasOpened = [defaults boolForKey:@"hasOpenedGitHubBefore"];
        
        [defaults removePersistentDomainForName:@"com.eolnmsuk.antidarkswordprefs"];
        
        // Restore the flag
        if (hasOpened) {
            [defaults setBool:YES forKey:@"hasOpenedGitHubBefore"];
        }
        [defaults synchronize];
        
        // Write only the flag back to the plist file to clear all other settings safely
        NSDictionary *newDict = hasOpened ? @{@"hasOpenedGitHubBefore": @YES} : @{};
        [newDict writeToFile:PREFS_PATH atomically:YES];
        
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
