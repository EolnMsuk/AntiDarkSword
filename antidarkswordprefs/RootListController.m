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
                
                // --- viewWillAppear Hook ---
                SEL viewWillAppearSel = @selector(viewWillAppear:);
                Method originalViewWillAppear = class_getInstanceMethod(altListClass, viewWillAppearSel);
                
                IMP customViewWillAppearImp = imp_implementationWithBlock(^(id _self, BOOL animated) {
                    if (originalViewWillAppear) {
                        void (*originalMsg)(id, SEL, BOOL) = (void (*)(id, SEL, BOOL))method_getImplementation(originalViewWillAppear);
                        originalMsg(_self, viewWillAppearSel, animated);
                    }
                    UIBarButtonItem *saveButton = [[UIBarButtonItem alloc] initWithTitle:@"Save" 
                                                                                   style:UIBarButtonItemStyleDone 
                                                                                  target:_self 
                                                                                  action:@selector(savePrompt)];
                    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"com.eolnmsuk.antidarkswordprefs"];
                    saveButton.enabled = [defaults boolForKey:@"ADSNeedsRespring"];
                    ((UIViewController *)_self).navigationItem.rightBarButtonItem = saveButton;
                    
                    // Listen for ANY preference changes while the AltList view is open
                    [[NSNotificationCenter defaultCenter] addObserver:_self 
                                                             selector:@selector(altListDefaultsChanged) 
                                                                 name:NSUserDefaultsDidChangeNotification 
                                                               object:nil];
                });
                class_addMethod(newClass, viewWillAppearSel, customViewWillAppearImp, originalViewWillAppear ? method_getTypeEncoding(originalViewWillAppear) : "v@:B");
                
                // --- viewWillDisappear Hook ---
                SEL viewWillDisappearSel = @selector(viewWillDisappear:);
                Method originalViewWillDisappear = class_getInstanceMethod(altListClass, viewWillDisappearSel);
                
                IMP customViewWillDisappearImp = imp_implementationWithBlock(^(id _self, BOOL animated) {
                    if (originalViewWillDisappear) {
                        void (*originalMsg)(id, SEL, BOOL) = (void (*)(id, SEL, BOOL))method_getImplementation(originalViewWillDisappear);
                        originalMsg(_self, viewWillDisappearSel, animated);
                    }
                    // Remove the observer so it doesn't leak or trigger randomly
                    [[NSNotificationCenter defaultCenter] removeObserver:_self 
                                                                    name:NSUserDefaultsDidChangeNotification 
                                                                  object:nil];
                });
                class_addMethod(newClass, viewWillDisappearSel, customViewWillDisappearImp, originalViewWillDisappear ? method_getTypeEncoding(originalViewWillDisappear) : "v@:B");
                
                // --- Custom Method to handle the notification ---
                SEL altListDefaultsChangedSel = @selector(altListDefaultsChanged);
                IMP altListDefaultsChangedImp = imp_implementationWithBlock(^(id _self) {
                    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"com.eolnmsuk.antidarkswordprefs"];
                    [defaults setBool:YES forKey:@"ADSNeedsRespring"];
                    [defaults synchronize];
                    
                    dispatch_async(dispatch_get_main_queue(), ^{
                        ((UIViewController *)_self).navigationItem.rightBarButtonItem.enabled = YES;
                    });
                });
                class_addMethod(newClass, altListDefaultsChangedSel, altListDefaultsChangedImp, "v@:");

                // --- savePrompt Method ---
                SEL savePromptSel = @selector(savePrompt);
                IMP savePromptImp = imp_implementationWithBlock(^(id _self) {
                    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Save" message:@"Apply changes now?" preferredStyle:UIAlertControllerStyleAlert];
                    [alert addAction:[UIAlertAction actionWithTitle:@"Later" style:UIAlertActionStyleCancel handler:nil]];
                    [alert addAction:[UIAlertAction actionWithTitle:@"Respring" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
                        NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"com.eolnmsuk.antidarkswordprefs"];
                        [defaults setBool:NO forKey:@"ADSNeedsRespring"];
                        [defaults synchronize];
                        
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
        @"com.google.Gmail", @"com.microsoft.Office.Outlook", @"com.yahoo.Aerogram", @"ch.protonmail.ios",
        @"org.whispersystems.signal", @"org.telegram.messenger", @"com.facebook.Messenger", 
        @"com.toyopagroup.picaboo", @"com.tinyspeck.chatlyio", @"com.microsoft.skype.teams", 
        @"com.tencent.xin", @"com.viber", @"jp.naver.line", @"net.whatsapp.WhatsApp", 
        @"ph.telegra.Telegraph", @"com.hammerandchisel.discord",
        @"com.google.GoogleMobile", @"com.google.chrome.ios", @"org.mozilla.ios.Firefox", 
        @"com.brave.ios.browser", @"com.duckduckgo.mobile.ios",
        @"com.pinterest", @"com.tumblr.tumblr", @"com.facebook.Facebook", @"com.atebits.Tweetie2", 
        @"com.burbn.instagram", @"com.zhiliaoapp.musically", @"com.linkedin.LinkedIn", 
        @"com.reddit.Reddit", @"com.google.ios.youtube", @"tv.twitch",
        @"com.google.gemini", @"com.openai.chat", @"com.deepseek.chat", @"com.github.ios",
        @"org.coolstar.sileo", @"xyz.willy.Zebra", @"com.tigisoftware.Filza"
    ];
    
    NSArray *tier3 = @[
        @"com.apple.imagent", @"imagent", 
        @"mediaserverd", 
        @"networkd",
        @"apsd",
        @"identityservicesd"
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
        
        // 1. Gray out manual settings if Preset Rules are currently enabled (Except Custom Daemon rules)
        for (PSSpecifier *s in specs) {
            if ([s.identifier isEqualToString:@"SelectApps"]) {
                [s setProperty:@(!autoProtect) forKey:@"enabled"];
            }
        }

        // 2. Inject Custom IDs dynamically (Custom IDs ALWAYS stay enabled)
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
                [spec setProperty:@YES forKey:@"enabled"]; // Custom Daemons always configurable
                [specs insertObject:spec atIndex:insertIndexCustom++];
            }
        }

        // 3. Inject the dynamic "Actively Locked Down" visual list
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
    
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"com.eolnmsuk.antidarkswordprefs"];
    saveButton.enabled = [defaults boolForKey:@"ADSNeedsRespring"];
    
    // Listen for Darwin notification to catch any changes
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge const void *)(self), (CFNotificationCallback)PrefsChangedNotification, CFSTR("com.eolnmsuk.antidarkswordprefs/saved"), NULL, CFNotificationSuspensionBehaviorCoalesce);
    
    if (![defaults boolForKey:@"hasOpenedGitHubBefore"]) {
        [defaults setBool:YES forKey:@"hasOpenedGitHubBefore"];
        [defaults synchronize];
        
        NSURL *githubURL = [NSURL URLWithString:@"https://github.com/EolnMsuk/AntiDarkSword/blob/main/README.md"];
        [[UIApplication sharedApplication] openURL:githubURL options:@{} completionHandler:nil];
    }
}

- (void)dealloc {
    CFNotificationCenterRemoveObserver(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge const void *)(self), CFSTR("com.eolnmsuk.antidarkswordprefs/saved"), NULL);
}

static void PrefsChangedNotification(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    AntiDarkSwordPrefsRootListController *controller = (__bridge AntiDarkSwordPrefsRootListController *)observer;
    if (controller) {
        NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"com.eolnmsuk.antidarkswordprefs"];
        [defaults setBool:YES forKey:@"ADSNeedsRespring"];
        [defaults synchronize];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            controller.navigationItem.rightBarButtonItem.enabled = YES;
        });
    }
}

// Overwrite setting property to ensure changes are always flagged
- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    [super setPreferenceValue:value specifier:specifier];
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"com.eolnmsuk.antidarkswordprefs"];
    [defaults setBool:YES forKey:@"ADSNeedsRespring"];
    [defaults synchronize];
    self.navigationItem.rightBarButtonItem.enabled = YES;
}

- (id)getAlwaysTrue:(PSSpecifier*)specifier {
    return @YES;
}

- (void)setAutoProtect:(id)value specifier:(PSSpecifier*)specifier {
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"com.eolnmsuk.antidarkswordprefs"];
    [defaults setObject:value forKey:@"autoProtectEnabled"];
    [defaults setBool:YES forKey:@"ADSNeedsRespring"];
    [defaults synchronize];
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFSTR("com.eolnmsuk.antidarkswordprefs/saved"), NULL, NULL, YES);
    
    _specifiers = nil;
    [self reloadSpecifiers];
}

- (void)setAutoProtectLevel:(id)value specifier:(PSSpecifier*)specifier {
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"com.eolnmsuk.antidarkswordprefs"];
    [defaults setObject:value forKey:@"autoProtectLevel"];
    [defaults setBool:YES forKey:@"ADSNeedsRespring"];
    [defaults synchronize];
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFSTR("com.eolnmsuk.antidarkswordprefs/saved"), NULL, NULL, YES);
    
    if ([defaults boolForKey:@"autoProtectEnabled"]) {
        _specifiers = nil;
        [self reloadSpecifiers];
    }
}

- (id)readCustomIDValue:(PSSpecifier*)specifier {
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"com.eolnmsuk.antidarkswordprefs"];
    NSArray *activeCustom = [defaults objectForKey:@"activeCustomDaemonIDs"] ?: [defaults objectForKey:@"customDaemonIDs"] ?: @[];
    NSString *daemonID = [specifier propertyForKey:@"daemonID"];
    return @([activeCustom containsObject:daemonID]);
}

- (void)setCustomIDValue:(id)value specifier:(PSSpecifier*)specifier {
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"com.eolnmsuk.antidarkswordprefs"];
    NSMutableArray *activeCustom = [[defaults objectForKey:@"activeCustomDaemonIDs"] ?: [defaults objectForKey:@"customDaemonIDs"] ?: @[] mutableCopy];
    
    NSString *daemonID = [specifier propertyForKey:@"daemonID"];
    BOOL enabled = [value boolValue];
    
    if (enabled && ![activeCustom containsObject:daemonID]) {
        [activeCustom addObject:daemonID];
    } else if (!enabled && [activeCustom containsObject:daemonID]) {
        [activeCustom removeObject:daemonID];
    }
    
    [defaults setObject:activeCustom forKey:@"activeCustomDaemonIDs"];
    [defaults setBool:YES forKey:@"ADSNeedsRespring"];
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
            NSMutableArray *activeCustom = [[defaults objectForKey:@"activeCustomDaemonIDs"] ?: customIDs mutableCopy];
            
            BOOL changesMade = NO;
            
            for (NSString *rawID in inputIDs) {
                NSString *cleanID = [rawID stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                
                if (cleanID.length > 0 && ![customIDs containsObject:cleanID]) {
                    [customIDs addObject:cleanID];
                    if (![activeCustom containsObject:cleanID]) {
                        [activeCustom addObject:cleanID];
                    }
                    changesMade = YES;
                }
            }
            
            if (changesMade) {
                [defaults setObject:customIDs forKey:@"customDaemonIDs"];
                [defaults setObject:activeCustom forKey:@"activeCustomDaemonIDs"];
                [defaults setBool:YES forKey:@"ADSNeedsRespring"];
                [defaults synchronize];
                
                _specifiers = nil;
                [self reloadSpecifiers];
                CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFSTR("com.eolnmsuk.antidarkswordprefs/saved"), NULL, NULL, YES);
            }
        }
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    PSSpecifier *spec = [self specifierAtIndexPath:indexPath];
    if ([[spec propertyForKey:@"isCustomDaemon"] boolValue]) {
        return YES; // Always allow removing Custom Daemons
    }
    return NO;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle == UITableViewCellEditingStyleDelete) {
        PSSpecifier *spec = [self specifierAtIndexPath:indexPath];
        NSString *daemonID = [spec propertyForKey:@"daemonID"];
        
        NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"com.eolnmsuk.antidarkswordprefs"];
        NSMutableArray *customIDs = [[defaults objectForKey:@"customDaemonIDs"] ?: @[] mutableCopy];
        NSMutableArray *activeCustom = [[defaults objectForKey:@"activeCustomDaemonIDs"] ?: customIDs mutableCopy];
        
        [customIDs removeObject:daemonID];
        [activeCustom removeObject:daemonID];
        
        [defaults setObject:customIDs forKey:@"customDaemonIDs"];
        [defaults setObject:activeCustom forKey:@"activeCustomDaemonIDs"];
        [defaults setBool:YES forKey:@"ADSNeedsRespring"];
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
        
        // Use standard NSUserDefaults API to delete keys, avoiding cfprefsd cache corruption
        NSDictionary *dict = [defaults dictionaryRepresentation];
        for (NSString *key in dict) {
            // Keep the GitHub flag so it doesn't pop up again
            if (![key isEqualToString:@"hasOpenedGitHubBefore"]) {
                [defaults removeObjectForKey:key];
            }
        }
        
        // Force the save button grey state
        [defaults setBool:NO forKey:@"ADSNeedsRespring"];
        [defaults synchronize];
        
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFSTR("com.eolnmsuk.antidarkswordprefs/saved"), NULL, NULL, YES);
        
        pid_t pid;
        const char* args[] = {"sbreload", NULL};
        posix_spawn(&pid, "/var/jb/usr/bin/sbreload", NULL, NULL, (char* const*)args, NULL);
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)savePrompt {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Save" message:@"Apply changes with respring?" preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Respring" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"com.eolnmsuk.antidarkswordprefs"];
        [defaults setBool:NO forKey:@"ADSNeedsRespring"];
        [defaults synchronize];
        
        pid_t pid;
        const char* args[] = {"sbreload", NULL};
        posix_spawn(&pid, "/var/jb/usr/bin/sbreload", NULL, NULL, (char* const*)args, NULL);
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)openGitHub {
    [[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"https://github.com/EolnMsuk/AntiDarkSword"] options:@{} completionHandler:nil];
}

- (void)openVenmo {
    [[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"https://venmo.com/user/eolnmsuk"] options:@{} completionHandler:nil];
}

@end
