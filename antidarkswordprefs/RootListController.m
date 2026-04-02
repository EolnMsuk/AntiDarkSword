#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <UIKit/UIKit.h>
#import <spawn.h>
#import <sys/types.h>
#import <objc/runtime.h>

#define PREFS_PATH @"/var/jb/var/mobile/Library/Preferences/com.eolnmsuk.antidarkswordprefs.plist"

// Forward declaration to prevent compiler errors
static void PrefsChangedNotification(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo);

@interface AntiDarkSwordPrefsRootListController : PSListController
@end

@implementation AntiDarkSwordPrefsRootListController

+ (void)initialize {
    if (self == [AntiDarkSwordPrefsRootListController class]) {
        
        // Ensure the AltList bundle is loaded safely
        NSBundle *altListBundle = [NSBundle bundleWithPath:@"/var/jb/Library/Frameworks/AltList.framework"];
        if (![altListBundle isLoaded]) {
            [altListBundle load];
        }
        
        Class altListClass = NSClassFromString(@"ATLApplicationListMultiSelectionController");
        if (altListClass && !NSClassFromString(@"AntiDarkSwordAppListController")) {
            Class newClass = objc_allocateClassPair(altListClass, "AntiDarkSwordAppListController", 0);
            if (newClass) {
                
                // --- Safe UI Injection on Open ---
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
                    
                    BOOL isEnabled = [defaults boolForKey:@"enabled"];
                    BOOL needsRespring = [defaults boolForKey:@"ADSNeedsRespring"];
                    BOOL needsReboot = [defaults boolForKey:@"ADSPendingDaemonChanges"];
                    
                    saveButton.enabled = isEnabled && (needsRespring || needsReboot);
                    ((UIViewController *)_self).navigationItem.rightBarButtonItem = saveButton;
                    
                    // SAFE OBSERVER: Listen for toggles, but strictly prevent the infinite loop
                    id observer = [[NSNotificationCenter defaultCenter] addObserverForName:NSUserDefaultsDidChangeNotification 
                                                                                    object:nil 
                                                                                     queue:[NSOperationQueue mainQueue] 
                                                                                usingBlock:^(NSNotification * _Nonnull note) {
                        NSUserDefaults *checkDefaults = [[NSUserDefaults alloc] initWithSuiteName:@"com.eolnmsuk.antidarkswordprefs"];
                        
                        if (![checkDefaults boolForKey:@"ADSNeedsRespring"]) {
                            [checkDefaults setBool:YES forKey:@"ADSNeedsRespring"];
                            [checkDefaults synchronize];
                        }
                        
                        BOOL checkEnabled = [checkDefaults boolForKey:@"enabled"];
                        BOOL checkRespring = [checkDefaults boolForKey:@"ADSNeedsRespring"];
                        BOOL checkReboot = [checkDefaults boolForKey:@"ADSPendingDaemonChanges"];
                        ((UIViewController *)_self).navigationItem.rightBarButtonItem.enabled = checkEnabled && (checkRespring || checkReboot);
                    }];
                    
                    // Store the observer safely attached to this specific view controller instance
                    objc_setAssociatedObject(_self, @selector(savePrompt), observer, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                });
                class_addMethod(newClass, viewWillAppearSel, customViewWillAppearImp, originalViewWillAppear ? method_getTypeEncoding(originalViewWillAppear) : "v@:B");
                
                // --- Safe Observer Removal on Close ---
                SEL viewWillDisappearSel = @selector(viewWillDisappear:);
                Method originalViewWillDisappear = class_getInstanceMethod(altListClass, viewWillDisappearSel);
                
                IMP customViewWillDisappearImp = imp_implementationWithBlock(^(id _self, BOOL animated) {
                    if (originalViewWillDisappear) {
                        void (*originalMsg)(id, SEL, BOOL) = (void (*)(id, SEL, BOOL))method_getImplementation(originalViewWillDisappear);
                        originalMsg(_self, viewWillDisappearSel, animated);
                    }
                    
                    id observer = objc_getAssociatedObject(_self, @selector(savePrompt));
                    if (observer) {
                        [[NSNotificationCenter defaultCenter] removeObserver:observer];
                        objc_setAssociatedObject(_self, @selector(savePrompt), nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                    }
                });
                class_addMethod(newClass, viewWillDisappearSel, customViewWillDisappearImp, originalViewWillDisappear ? method_getTypeEncoding(originalViewWillDisappear) : "v@:B");

                // --- Save Prompt Handler ---
                SEL savePromptSel = @selector(savePrompt);
                IMP savePromptImp = imp_implementationWithBlock(^(id _self) {
                    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"com.eolnmsuk.antidarkswordprefs"];
                    BOOL isEnabled = [defaults boolForKey:@"enabled"];
                    BOOL needsReboot = isEnabled && [defaults boolForKey:@"ADSPendingDaemonChanges"];
                    
                    NSString *title = @"Save";
                    NSString *msg = needsReboot ? @"Apply changes with a userspace reboot? (Required for daemon changes)" : @"Apply changes now?";
                    NSString *btn = needsReboot ? @"Reboot Userspace" : @"Respring";
                    
                    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:msg preferredStyle:UIAlertControllerStyleAlert];
                    [alert addAction:[UIAlertAction actionWithTitle:@"Later" style:UIAlertActionStyleCancel handler:nil]];
                    [alert addAction:[UIAlertAction actionWithTitle:btn style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
                        [defaults setBool:NO forKey:@"ADSNeedsRespring"];
                        [defaults setBool:NO forKey:@"ADSPendingDaemonChanges"];
                        [defaults synchronize];
                        
                        pid_t pid;
                        if (needsReboot) {
                            const char* args[] = {"launchctl", "reboot", "userspace", NULL};
                            posix_spawn(&pid, "/var/jb/usr/bin/launchctl", NULL, NULL, (char* const*)args, NULL);
                        } else {
                            const char* args[] = {"killall", "backboardd", NULL};
                            posix_spawn(&pid, "/var/jb/usr/bin/killall", NULL, NULL, (char* const*)args, NULL);
                        }
                    }]];
                    [((UIViewController *)_self) presentViewController:alert animated:YES completion:nil];
                });
                class_addMethod(newClass, savePromptSel, savePromptImp, "v@:");
                
                objc_registerClassPair(newClass);
            }
        }
    }
}

// Intercept the view appearing to handle cross-syncing and dynamic UI updates
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"com.eolnmsuk.antidarkswordprefs"];
    NSArray *customIDs = [defaults objectForKey:@"customDaemonIDs"] ?: @[];
    NSMutableArray *activeCustom = [[defaults objectForKey:@"activeCustomDaemonIDs"] ?: customIDs mutableCopy];
    NSArray *restricted = [defaults objectForKey:@"restrictedApps"] ?: @[];
    
    BOOL modified = NO;
    
    // 1. Check if AltList toggled any of our Custom IDs ON or OFF and sync them to activeCustomDaemonIDs
    for (NSString *daemon in customIDs) {
        BOOL inRestricted = [restricted containsObject:daemon];
        BOOL inActive = [activeCustom containsObject:daemon];
        
        if (inRestricted && !inActive) {
            [activeCustom addObject:daemon];
            modified = YES;
        } else if (!inRestricted && inActive) {
            [activeCustom removeObject:daemon];
            modified = YES;
        }
    }
    
    // 2. Check if the UA dropdown changed and we need to show/hide the Custom Text Field dynamically
    NSString *selectedUA = [defaults stringForKey:@"selectedUAPreset"] ?: @"CUSTOM";
    BOOL shouldShowCustomText = [selectedUA isEqualToString:@"CUSTOM"];
    BOOL isShowingCustomText = ([self specifierForID:@"CustomUATextField"] != nil);
    
    if (shouldShowCustomText != isShowingCustomText) {
        _specifiers = nil; // Invalidate current specifiers
        modified = YES;
    }
    
    if (modified) {
        [defaults setObject:activeCustom forKey:@"activeCustomDaemonIDs"];
        [defaults setBool:YES forKey:@"ADSNeedsRespring"];
        [defaults setBool:YES forKey:@"ADSPendingDaemonChanges"];
        [defaults synchronize];
    }
    
    // Reload if anything changed (AltList sync or UA text field visibility)
    if (_specifiers == nil || modified) {
        [self reloadSpecifiers];
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
        @"com.apple.iMessageAppsViewService", @"com.apple.ActivityMessagesApp",
        @"com.apple.quicklook.QuickLookUIService", @"com.apple.QuickLookDaemon"
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
        
        // 0. Dynamic UI: Hide Custom UA Text Field if Preset is not "CUSTOM"
        NSString *selectedUA = [defaults stringForKey:@"selectedUAPreset"] ?: @"CUSTOM";
        if (![selectedUA isEqualToString:@"CUSTOM"]) {
            for (int i = 0; i < specs.count; i++) {
                PSSpecifier *s = specs[i];
                if ([[s propertyForKey:@"id"] isEqualToString:@"CustomUATextField"]) {
                    [specs removeObjectAtIndex:i];
                    break;
                }
            }
        }
        
        BOOL autoProtect = [defaults boolForKey:@"autoProtectEnabled"];
        NSInteger autoProtectLevel = [defaults objectForKey:@"autoProtectLevel"] ? [defaults integerForKey:@"autoProtectLevel"] : 1;
        NSArray *customIDs = [defaults objectForKey:@"customDaemonIDs"] ?: @[];
        
        // 1. Gray out manual settings if Preset Rules are currently enabled (Except Custom Daemon rules)
        // Also dynamically set the footer text for the PresetRulesGroup based on the selected level
        for (PSSpecifier *s in specs) {
            if ([s.identifier isEqualToString:@"SelectApps"]) {
                [s setProperty:@(!autoProtect) forKey:@"enabled"];
            } else if ([s.identifier isEqualToString:@"PresetRulesGroup"]) {
                NSString *footerText = @"";
                if (autoProtectLevel == 1) {
                    footerText = @"Level 1: Protects all native Apple applications, including Safari, Messages, Mail, Notes, Calendar, and other built-in iOS apps.";
                } else if (autoProtectLevel == 2) {
                    footerText = @"Level 2: Expands protection to major 3rd-party web browsers, email clients, messaging platforms, social media apps, and package managers.";
                } else if (autoProtectLevel == 3) {
                    footerText = @"Level 3: Maximum lockdown. Enforces restrictions on critical background system daemons (imagent, mediaserverd, networkd, apsd, identityservicesd).\n\n⚠️ Warning: Level 3 restricts critical background daemons, lower the level if you have any issues.";
                }
                [s setProperty:footerText forKey:@"footerText"];
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

        // 3. Inject the dynamic "Current Preset Rules" visual list
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
                PSSpecifier *groupSpec = [PSSpecifier preferenceSpecifierNamed:@"Current Preset Rules" target:self set:nil get:nil detail:nil cell:PSGroupCell edit:nil];
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
    BOOL isEnabled = [defaults boolForKey:@"enabled"];
    BOOL needsRespring = [defaults boolForKey:@"ADSNeedsRespring"];
    BOOL needsReboot = [defaults boolForKey:@"ADSPendingDaemonChanges"];
    
    saveButton.enabled = isEnabled && (needsRespring || needsReboot);
    
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
        
        BOOL isEnabled = [defaults boolForKey:@"enabled"];
        BOOL needsRespring = [defaults boolForKey:@"ADSNeedsRespring"];
        BOOL needsReboot = [defaults boolForKey:@"ADSPendingDaemonChanges"];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            controller.navigationItem.rightBarButtonItem.enabled = isEnabled && (needsRespring || needsReboot);
        });
    }
}

// Overwrite setting property to ensure changes are always flagged
- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    [super setPreferenceValue:value specifier:specifier];
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"com.eolnmsuk.antidarkswordprefs"];
    [defaults setBool:YES forKey:@"ADSNeedsRespring"];
    [defaults synchronize];
    
    BOOL isEnabled = [defaults boolForKey:@"enabled"];
    BOOL needsRespring = [defaults boolForKey:@"ADSNeedsRespring"];
    BOOL needsReboot = [defaults boolForKey:@"ADSPendingDaemonChanges"];
    self.navigationItem.rightBarButtonItem.enabled = isEnabled && (needsRespring || needsReboot);
}

- (id)getAlwaysTrue:(PSSpecifier*)specifier {
    return @YES;
}

- (void)setAutoProtect:(id)value specifier:(PSSpecifier*)specifier {
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"com.eolnmsuk.antidarkswordprefs"];
    [defaults setObject:value forKey:@"autoProtectEnabled"];
    [defaults setBool:YES forKey:@"ADSNeedsRespring"];
    if ([defaults integerForKey:@"autoProtectLevel"] >= 3) {
        [defaults setBool:YES forKey:@"ADSPendingDaemonChanges"];
    }
    [defaults synchronize];
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFSTR("com.eolnmsuk.antidarkswordprefs/saved"), NULL, NULL, YES);
    
    _specifiers = nil;
    [self reloadSpecifiers];
}

- (void)setAutoProtectLevel:(id)value specifier:(PSSpecifier*)specifier {
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"com.eolnmsuk.antidarkswordprefs"];
    NSInteger oldLevel = [defaults integerForKey:@"autoProtectLevel"];
    NSInteger newLevel = [value integerValue];
    
    [defaults setObject:value forKey:@"autoProtectLevel"];
    [defaults setBool:YES forKey:@"ADSNeedsRespring"];
    
    if (oldLevel >= 3 || newLevel >= 3) {
        [defaults setBool:YES forKey:@"ADSPendingDaemonChanges"];
    }
    [defaults synchronize];
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFSTR("com.eolnmsuk.antidarkswordprefs/saved"), NULL, NULL, YES);
    
    // Always clear and reload specifiers so the footer dynamically updates
    _specifiers = nil;
    [self reloadSpecifiers];
}

- (id)readCustomIDValue:(PSSpecifier*)specifier {
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"com.eolnmsuk.antidarkswordprefs"];
    NSArray *activeCustom = [defaults objectForKey:@"activeCustomDaemonIDs"] ?: [defaults objectForKey:@"customDaemonIDs"] ?: @[];
    NSArray *restricted = [defaults objectForKey:@"restrictedApps"] ?: @[];
    NSString *daemonID = [specifier propertyForKey:@"daemonID"];
    
    return @([activeCustom containsObject:daemonID] || [restricted containsObject:daemonID]);
}

- (void)setCustomIDValue:(id)value specifier:(PSSpecifier*)specifier {
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"com.eolnmsuk.antidarkswordprefs"];
    NSMutableArray *activeCustom = [[defaults objectForKey:@"activeCustomDaemonIDs"] ?: [[defaults objectForKey:@"customDaemonIDs"] ?: @[] mutableCopy] mutableCopy];
    NSMutableArray *restricted = [[defaults objectForKey:@"restrictedApps"] ?: @[] mutableCopy];
    
    NSString *daemonID = [specifier propertyForKey:@"daemonID"];
    BOOL enabled = [value boolValue];
    
    // Ensure perfectly synchronized state
    if (enabled) {
        if (![activeCustom containsObject:daemonID]) [activeCustom addObject:daemonID];
        if (![restricted containsObject:daemonID]) [restricted addObject:daemonID];
    } else {
        [activeCustom removeObject:daemonID];
        [restricted removeObject:daemonID];
    }
    
    [defaults setObject:activeCustom forKey:@"activeCustomDaemonIDs"];
    [defaults setObject:restricted forKey:@"restrictedApps"];
    [defaults setBool:YES forKey:@"ADSNeedsRespring"];
    [defaults setBool:YES forKey:@"ADSPendingDaemonChanges"];
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
            NSMutableArray *restricted = [[defaults objectForKey:@"restrictedApps"] ?: @[] mutableCopy];
            
            BOOL changesMade = NO;
            
            for (NSString *rawID in inputIDs) {
                NSString *cleanID = [rawID stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                
                if (cleanID.length > 0 && ![customIDs containsObject:cleanID]) {
                    [customIDs addObject:cleanID];
                    // Also forcibly toggle it ON in both synchronized locations
                    if (![activeCustom containsObject:cleanID]) {
                        [activeCustom addObject:cleanID];
                    }
                    if (![restricted containsObject:cleanID]) {
                        [restricted addObject:cleanID];
                    }
                    changesMade = YES;
                }
            }
            
            if (changesMade) {
                [defaults setObject:customIDs forKey:@"customDaemonIDs"];
                [defaults setObject:activeCustom forKey:@"activeCustomDaemonIDs"];
                [defaults setObject:restricted forKey:@"restrictedApps"];
                [defaults setBool:YES forKey:@"ADSNeedsRespring"];
                [defaults setBool:YES forKey:@"ADSPendingDaemonChanges"];
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
        NSMutableArray *restricted = [[defaults objectForKey:@"restrictedApps"] ?: @[] mutableCopy];
        
        [customIDs removeObject:daemonID];
        [activeCustom removeObject:daemonID];
        [restricted removeObject:daemonID];
        
        [defaults setObject:customIDs forKey:@"customDaemonIDs"];
        [defaults setObject:activeCustom forKey:@"activeCustomDaemonIDs"];
        [defaults setObject:restricted forKey:@"restrictedApps"];
        [defaults setBool:YES forKey:@"ADSNeedsRespring"];
        [defaults setBool:YES forKey:@"ADSPendingDaemonChanges"];
        [defaults synchronize];
        
        [self removeSpecifier:spec animated:YES];
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFSTR("com.eolnmsuk.antidarkswordprefs/saved"), NULL, NULL, YES);
    }
}

- (void)resetToDefaults {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Reset to Defaults" message:@"Userspace reboot required to completely flush daemon hooks." preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Reboot Userspace" style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
        NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"com.eolnmsuk.antidarkswordprefs"];
        
        NSDictionary *dict = [defaults dictionaryRepresentation];
        for (NSString *key in dict) {
            if (![key isEqualToString:@"hasOpenedGitHubBefore"]) {
                [defaults removeObjectForKey:key];
            }
        }
        
        [defaults setBool:NO forKey:@"ADSNeedsRespring"];
        [defaults setBool:NO forKey:@"ADSPendingDaemonChanges"];
        [defaults synchronize];
        
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFSTR("com.eolnmsuk.antidarkswordprefs/saved"), NULL, NULL, YES);
        
        pid_t pid;
        const char* args[] = {"launchctl", "reboot", "userspace", NULL};
        posix_spawn(&pid, "/var/jb/usr/bin/launchctl", NULL, NULL, (char* const*)args, NULL);
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)savePrompt {
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"com.eolnmsuk.antidarkswordprefs"];
    BOOL isEnabled = [defaults boolForKey:@"enabled"];
    BOOL needsReboot = isEnabled && [defaults boolForKey:@"ADSPendingDaemonChanges"];
    
    NSString *title = @"Save";
    NSString *msg = needsReboot ? @"Apply changes with a userspace reboot? (Required for daemon changes)" : @"Apply changes with respring?";
    NSString *btn = needsReboot ? @"Reboot Userspace" : @"Respring";
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:msg preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:btn style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        [defaults setBool:NO forKey:@"ADSNeedsRespring"];
        [defaults setBool:NO forKey:@"ADSPendingDaemonChanges"];
        [defaults synchronize];
        
        pid_t pid;
        if (needsReboot) {
            const char* args[] = {"launchctl", "reboot", "userspace", NULL};
            posix_spawn(&pid, "/var/jb/usr/bin/launchctl", NULL, NULL, (char* const*)args, NULL);
        } else {
            const char* args[] = {"killall", "backboardd", NULL};
            posix_spawn(&pid, "/var/jb/usr/bin/killall", NULL, NULL, (char* const*)args, NULL);
        }
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
