#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <UIKit/UIKit.h>
#import <spawn.h>
#import <sys/types.h>
#import <objc/runtime.h>

static void PrefsChangedNotification(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo);

@interface UITableViewCell (PreferencesUI)
- (id)control;
@end

@interface AntiDarkSwordPrefsRootListController : PSListController
- (NSArray *)autoProtectedItemsForLevel:(NSInteger)level;
- (void)populateDefaultRulesForLevel:(NSInteger)level force:(BOOL)force;
@end

// ==========================================
// Custom AltList Controller to Lock Presets
// ==========================================
@interface ATLApplicationListMultiSelectionController : PSListController
@end

@interface AntiDarkSwordAltListController : ATLApplicationListMultiSelectionController
@end

@implementation AntiDarkSwordAltListController

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [super tableView:tableView cellForRowAtIndexPath:indexPath];
    
    PSSpecifier *spec = [self specifierAtIndexPath:indexPath];
    
    NSString *bundleID = [spec propertyForKey:@"applicationIdentifier"];
    if (!bundleID) {
        NSString *alKey = [spec propertyForKey:@"ALSettingsKey"];
        if ([alKey hasPrefix:@"restrictedApps-"]) {
            bundleID = [alKey substringFromIndex:@"restrictedApps-".length];
        }
    }
    
    if (bundleID) {
        NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"com.eolnmsuk.antidarkswordprefs"];
        NSInteger level = [defaults integerForKey:@"autoProtectLevel"];
        if (level == 0) level = 1;
        
        AntiDarkSwordPrefsRootListController *rootCtrl = [[AntiDarkSwordPrefsRootListController alloc] init];
        NSArray *presetApps = [rootCtrl autoProtectedItemsForLevel:level];
        
        // Fix: Only check the actively selected preset level.
        if ([presetApps containsObject:bundleID]) {
            // Lock and grey out UI for preset apps
            cell.userInteractionEnabled = NO;
            cell.textLabel.alpha = 0.5;
            if (cell.detailTextLabel) cell.detailTextLabel.alpha = 0.5;
            
            // Check if the user bypassed this preset via Master Enable rule
            NSArray *disabledPresetRules = [defaults arrayForKey:@"disabledPresetRules"] ?: @[];
            BOOL isDisabled = [disabledPresetRules containsObject:bundleID];
            
            if ([cell respondsToSelector:@selector(control)]) {
                id control = [cell control];
                if ([control isKindOfClass:[UISwitch class]]) {
                    // Visually display status but DO NOT force write to NSUserDefaults (prevents the loop)
                    [((UISwitch *)control) setOn:!isDisabled animated:NO];
                    ((UISwitch *)control).enabled = NO;
                }
            }
        } else {
            // Leave manual apps accessible 
            cell.userInteractionEnabled = YES;
            cell.textLabel.alpha = 1.0;
            if (cell.detailTextLabel) cell.detailTextLabel.alpha = 1.0;
            
            if ([cell respondsToSelector:@selector(control)]) {
                id control = [cell control];
                if ([control isKindOfClass:[UISwitch class]]) {
                    ((UISwitch *)control).enabled = YES;
                }
            }
        }
    }
    
    return cell;
}

@end

// ==========================================
// App-Specific Feature Drill-Down Controller
// ==========================================
@interface AntiDarkSwordAppController : PSListController
@property (nonatomic, strong) NSString *targetID;
@property (nonatomic, assign) NSInteger ruleType;
@end

@implementation AntiDarkSwordAppController
- (void)setSpecifier:(PSSpecifier *)specifier {
    [super setSpecifier:specifier];
    self.targetID = [specifier propertyForKey:@"targetID"];
    self.ruleType = [[specifier propertyForKey:@"ruleType"] integerValue];
    self.title = self.targetID;
}

- (NSArray *)specifiers {
    if (!_specifiers) {
        NSMutableArray *specs = [NSMutableArray array];
        
        PSSpecifier *enableGroup = [PSSpecifier preferenceSpecifierNamed:@"Rule Status" target:self set:nil get:nil detail:nil cell:PSGroupCell edit:nil];
        [specs addObject:enableGroup];
        
        PSSpecifier *enableSpec = [PSSpecifier preferenceSpecifierNamed:@"Enable Rule" target:self set:@selector(setMasterEnable:specifier:) get:@selector(getMasterEnable:) detail:nil cell:PSSwitchCell edit:nil];
        [specs addObject:enableSpec];
        
        PSSpecifier *featGroup = [PSSpecifier preferenceSpecifierNamed:@"Mitigation Features" target:self set:nil get:nil detail:nil cell:PSGroupCell edit:nil];
        [featGroup setProperty:@"Disabling specific mitigations can improve app compatibility while slightly reducing your security posture." forKey:@"footerText"];
        [specs addObject:featGroup];
        
        NSArray *features = @[
            @{@"key": @"disableJS", @"label": @"Disable JavaScript"},
            @{@"key": @"disableMedia", @"label": @"Disable Media Auto-Play"},
            @{@"key": @"disableRTC", @"label": @"Disable WebGL & WebRTC"},
            @{@"key": @"disableFileAccess", @"label": @"Disable Local File Access"},
            @{@"key": @"disableIMessageDL", @"label": @"Disable Msg Auto-Download"},
            @{@"key": @"spoofUA", @"label": @"Spoof User Agent"}
        ];
        
        for (NSDictionary *feat in features) {
            PSSpecifier *spec = [PSSpecifier preferenceSpecifierNamed:feat[@"label"] target:self set:@selector(setFeatureValue:specifier:) get:@selector(getFeatureValue:) detail:nil cell:PSSwitchCell edit:nil];
            [spec setProperty:feat[@"key"] forKey:@"featureKey"];
            [specs addObject:spec];
        }
        
        _specifiers = [specs copy];
    }
    return _specifiers;
}

- (id)getMasterEnable:(PSSpecifier *)specifier {
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"com.eolnmsuk.antidarkswordprefs"];
    [defaults synchronize]; 
    
    if (self.ruleType == 0) { // Preset
        NSArray *disabled = [defaults arrayForKey:@"disabledPresetRules"] ?: @[];
        return @(![disabled containsObject:self.targetID]);
    } else if (self.ruleType == 1) { // AltList
        NSString *prefKey = [NSString stringWithFormat:@"restrictedApps-%@", self.targetID];
        if ([defaults objectForKey:prefKey]) {
            return @([defaults boolForKey:prefKey]);
        }
        NSDictionary *apps = [defaults dictionaryForKey:@"restrictedApps"];
        return apps[self.targetID] ?: @NO;
    } else { // Custom Daemons
        NSArray *active = [defaults arrayForKey:@"activeCustomDaemonIDs"] ?: [defaults arrayForKey:@"customDaemonIDs"] ?: @[];
        return @([active containsObject:self.targetID]);
    }
}

- (void)setMasterEnable:(id)value specifier:(PSSpecifier *)specifier {
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"com.eolnmsuk.antidarkswordprefs"];
    BOOL enabled = [value boolValue];
    
    if (self.ruleType == 0) { // Preset
        NSMutableArray *disabled = [[defaults arrayForKey:@"disabledPresetRules"] mutableCopy] ?: [NSMutableArray array];
        if (enabled) [disabled removeObject:self.targetID];
        else if (![disabled containsObject:self.targetID]) [disabled addObject:self.targetID];
        [defaults setObject:disabled forKey:@"disabledPresetRules"];
    } else if (self.ruleType == 1) { // AltList
        NSString *prefKey = [NSString stringWithFormat:@"restrictedApps-%@", self.targetID];
        [defaults setBool:enabled forKey:prefKey];
        
        NSMutableDictionary *apps = [[defaults dictionaryForKey:@"restrictedApps"] mutableCopy];
        if (apps && apps[self.targetID]) {
            [apps removeObjectForKey:self.targetID];
            [defaults setObject:apps forKey:@"restrictedApps"];
        }
    } else { // Custom Daemons
        NSMutableArray *active = [[defaults arrayForKey:@"activeCustomDaemonIDs"] mutableCopy] ?: [[defaults arrayForKey:@"customDaemonIDs"] mutableCopy] ?: [NSMutableArray array];
        if (enabled) {
            if (![active containsObject:self.targetID]) [active addObject:self.targetID];
        } else {
            [active removeObject:self.targetID];
        }
        [defaults setObject:active forKey:@"activeCustomDaemonIDs"];
        [defaults setBool:YES forKey:@"ADSPendingDaemonChanges"];
    }
    
    [defaults setBool:YES forKey:@"ADSNeedsRespring"];
    [defaults synchronize];
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFSTR("com.eolnmsuk.antidarkswordprefs/saved"), NULL, NULL, YES);
}

- (id)getFeatureValue:(PSSpecifier *)specifier {
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"com.eolnmsuk.antidarkswordprefs"];
    [defaults synchronize]; 
    NSString *dictKey = [NSString stringWithFormat:@"TargetRules_%@", self.targetID];
    NSDictionary *rules = [defaults dictionaryForKey:dictKey];
    NSString *featureKey = [specifier propertyForKey:@"featureKey"];
    
    if (!rules || rules[featureKey] == nil) { 
        if ([featureKey isEqualToString:@"spoofUA"]) {
            NSArray *daemonDenylist = @[
                @"com.apple.appstored", @"com.apple.itunesstored",
                @"com.apple.imagent", @"com.apple.mediaserverd",
                @"com.apple.networkd", @"com.apple.apsd",
                @"com.apple.identityservicesd", @"com.apple.nsurlsessiond",
                @"com.apple.cfnetwork"
            ];
            if ([daemonDenylist containsObject:self.targetID] || [self.targetID containsString:@"daemon"] || [self.targetID hasSuffix:@"d"]) {
                return @NO;
            }
            return @YES;
        }
        
        if ([featureKey isEqualToString:@"disableJS"]) {
            NSArray *browsers = @[
                @"com.apple.mobilesafari", @"com.apple.SafariViewService",
                @"com.google.chrome.ios", @"org.mozilla.ios.Firefox", 
                @"com.brave.ios.browser", @"com.duckduckgo.mobile.ios"
            ];
            NSInteger level = [defaults integerForKey:@"autoProtectLevel"];
            if (level == 0) level = 1;
            if ([browsers containsObject:self.targetID] && level < 3) {
                return @NO;
            }
        }
        
        return @YES; 
    }
    
    return rules[featureKey];
}

- (void)setFeatureValue:(id)value specifier:(PSSpecifier *)specifier {
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"com.eolnmsuk.antidarkswordprefs"];
    NSString *dictKey = [NSString stringWithFormat:@"TargetRules_%@", self.targetID];
    NSMutableDictionary *rules = [[defaults dictionaryForKey:dictKey] mutableCopy] ?: [NSMutableDictionary dictionary];
    
    NSString *featureKey = [specifier propertyForKey:@"featureKey"];
    rules[featureKey] = value;
    
    [defaults setObject:rules forKey:dictKey];
    [defaults setBool:YES forKey:@"ADSNeedsRespring"];
    [defaults synchronize];
    
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFSTR("com.eolnmsuk.antidarkswordprefs/saved"), NULL, NULL, YES);
}
@end
// ==========================================

@implementation AntiDarkSwordPrefsRootListController

- (void)populateDefaultRulesForLevel:(NSInteger)level force:(BOOL)force {
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"com.eolnmsuk.antidarkswordprefs"];
    if (!force && [defaults boolForKey:@"hasInitializedDefaultRules"]) {
        return;
    }

    NSArray *browsers = @[
        @"com.apple.mobilesafari", @"com.apple.SafariViewService",
        @"com.google.chrome.ios", @"org.mozilla.ios.Firefox", 
        @"com.brave.ios.browser", @"com.duckduckgo.mobile.ios"
    ];
    
    NSArray *daemonDenylist = @[
        @"com.apple.appstored", @"com.apple.itunesstored",
        @"com.apple.imagent", @"com.apple.mediaserverd",
        @"com.apple.networkd", @"com.apple.apsd",
        @"com.apple.identityservicesd", @"com.apple.nsurlsessiond",
        @"com.apple.cfnetwork"
    ];

    NSArray *allProtected = [self autoProtectedItemsForLevel:3];
    for (NSString *targetID in allProtected) {
        NSString *dictKey = [NSString stringWithFormat:@"TargetRules_%@", targetID];
        
        if (!force && [defaults objectForKey:dictKey]) {
            continue;
        }

        NSMutableDictionary *rules = [NSMutableDictionary dictionary];
        
        rules[@"disableMedia"] = @YES;
        rules[@"disableRTC"] = @YES;
        rules[@"disableFileAccess"] = @YES;
        rules[@"disableIMessageDL"] = @YES;
        
        if ([browsers containsObject:targetID] && level < 3) {
            rules[@"disableJS"] = @NO;
        } else {
            rules[@"disableJS"] = @YES;
        }
        
        if ([daemonDenylist containsObject:targetID] || [targetID containsString:@"daemon"] || [targetID hasSuffix:@"d"]) {
            rules[@"spoofUA"] = @NO;
        } else {
            rules[@"spoofUA"] = @YES;
        }
        
        [defaults setObject:rules forKey:dictKey];
    }
    
    [defaults setBool:YES forKey:@"hasInitializedDefaultRules"];
    [defaults synchronize];
}

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

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reloadSpecifiers];
}

- (NSArray *)specifiers {
    if (!_specifiers) {
        NSMutableArray *specs = [[self loadSpecifiersFromPlistName:@"Root" target:self] mutableCopy];
        NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"com.eolnmsuk.antidarkswordprefs"];
        [defaults synchronize]; 
        
        NSString *selectedUA = [defaults stringForKey:@"selectedUAPreset"];
        if (!selectedUA || [selectedUA isEqualToString:@"NONE"]) {
            selectedUA = @"Mozilla/5.0 (iPhone; CPU iPhone OS 18_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1";
            [defaults setObject:selectedUA forKey:@"selectedUAPreset"];
            [defaults synchronize];
        }

        if (![selectedUA isEqualToString:@"CUSTOM"]) {
            for (int i = 0; i < specs.count; i++) {
                PSSpecifier *s = specs[i];
                if ([[s propertyForKey:@"id"] isEqualToString:@"CustomUATextField"]) {
                    [specs removeObjectAtIndex:i];
                    break;
                }
            }
        }
        
        NSInteger autoProtectLevel = [defaults objectForKey:@"autoProtectLevel"] ? [defaults integerForKey:@"autoProtectLevel"] : 1;
        NSArray *customIDs = [defaults objectForKey:@"customDaemonIDs"] ?: @[];
        
        for (PSSpecifier *s in specs) {
            if ([[s propertyForKey:@"id"] isEqualToString:@"SelectApps"]) {
                s.detailControllerClass = [AntiDarkSwordAltListController class];
            }
            
            if ([s.identifier isEqualToString:@"PresetRulesGroup"]) {
                NSString *footerText = @"";
                if (autoProtectLevel == 1) footerText = @"Level 1: Protects all native Apple applications, including Safari, Messages, Mail, Notes, Calendar, and other built-in iOS apps.";
                else if (autoProtectLevel == 2) footerText = @"Level 2: Expands protection to major 3rd-party web browsers, email clients, messaging platforms, social media apps, and package managers.";
                else if (autoProtectLevel == 3) footerText = @"Level 3: Maximum lockdown. Enforces restrictions on critical background system daemons (imagent, mediaserverd, networkd, apsd, identityservicesd).\n\n⚠️ Warning: Level 3 restricts critical background daemons, lower the level if you have any issues.";
                [s setProperty:footerText forKey:@"footerText"];
            }
        }

        // 1) Current Preset Rules Builder
        NSUInteger insertIndexAuto = [specs indexOfObjectPassingTest:^BOOL(PSSpecifier *obj, NSUInteger idx, BOOL *stop) {
            return [[obj propertyForKey:@"id"] isEqualToString:@"AutoProtectLevelSegment"];
        }];
        
        if (insertIndexAuto != NSNotFound) {
            insertIndexAuto++;
            PSSpecifier *groupSpec = [PSSpecifier preferenceSpecifierNamed:@"Current Preset Rules" target:self set:nil get:nil detail:nil cell:PSGroupCell edit:nil];
            [specs insertObject:groupSpec atIndex:insertIndexAuto++];
            
            NSArray *autoItems = [self autoProtectedItemsForLevel:autoProtectLevel];
            for (NSString *item in autoItems) {
                PSSpecifier *spec = [PSSpecifier preferenceSpecifierNamed:item target:self set:nil get:nil detail:[AntiDarkSwordAppController class] cell:PSLinkCell edit:nil];
                [spec setProperty:item forKey:@"targetID"];
                [spec setProperty:@(0) forKey:@"ruleType"]; // Preset rule
                [specs insertObject:spec atIndex:insertIndexAuto++];
            }
        }
        
        // Setup App Collection for Custom / Manual Items
        NSDictionary *allPrefsRaw = [defaults dictionaryRepresentation];
        NSMutableArray *manualAppIDs = [NSMutableArray array];
        
        for (NSString *key in allPrefsRaw) {
            if ([key isKindOfClass:[NSString class]] && [key hasPrefix:@"restrictedApps-"]) {
                if ([defaults boolForKey:key]) {
                    NSString *appID = [key substringFromIndex:@"restrictedApps-".length];
                    [manualAppIDs addObject:appID];
                }
            }
        }
        
        id restrictedAppsDict = allPrefsRaw[@"restrictedApps"];
        if ([restrictedAppsDict isKindOfClass:[NSDictionary class]]) {
            for (NSString *appID in [restrictedAppsDict allKeys]) {
                if ([appID isKindOfClass:[NSString class]]) {
                    if ([restrictedAppsDict[appID] respondsToSelector:@selector(boolValue)] && [restrictedAppsDict[appID] boolValue] && ![manualAppIDs containsObject:appID]) {
                        [manualAppIDs addObject:appID];
                    }
                }
            }
        }
        
        NSArray *autoItems = [self autoProtectedItemsForLevel:autoProtectLevel];
        NSArray *sortedManualKeys = [manualAppIDs sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];

        // 2) Custom ID Bundle List Builder (Combines Manual AltList Selections AND Custom Daemons)
        NSUInteger insertIndexCustom = [specs indexOfObjectPassingTest:^BOOL(PSSpecifier *obj, NSUInteger idx, BOOL *stop) {
            return [[obj propertyForKey:@"id"] isEqualToString:@"AddCustomIDButton"];
        }];
        
        if (insertIndexCustom != NSNotFound) {
            insertIndexCustom++;
            
            // Render manual AltList apps inside the Custom App list
            for (NSString *appID in sortedManualKeys) {
                if ([autoItems containsObject:appID]) continue; // Prevent showing duplicates if already in preset
                
                PSSpecifier *spec = [PSSpecifier preferenceSpecifierNamed:appID target:self set:nil get:nil detail:[AntiDarkSwordAppController class] cell:PSLinkCell edit:nil];
                [spec setProperty:appID forKey:@"targetID"];
                [spec setProperty:appID forKey:@"daemonID"]; // Passed for swipe-to-delete targeting
                [spec setProperty:@(1) forKey:@"ruleType"]; // AltList manual rule
                [spec setProperty:@YES forKey:@"isCustomDaemon"]; // Allows swipe-to-delete flag
                [spec setProperty:@YES forKey:@"isManualApp"]; // Custom flag to delete from correct UserDefaults key
                [specs insertObject:spec atIndex:insertIndexCustom++];
            }
            
            // Render native custom string typed daemons
            for (NSString *daemonID in customIDs) {
                PSSpecifier *spec = [PSSpecifier preferenceSpecifierNamed:daemonID target:self set:nil get:nil detail:[AntiDarkSwordAppController class] cell:PSLinkCell edit:nil];
                [spec setProperty:daemonID forKey:@"targetID"];
                [spec setProperty:daemonID forKey:@"daemonID"];
                [spec setProperty:@(2) forKey:@"ruleType"]; // Custom rule
                [spec setProperty:@YES forKey:@"isCustomDaemon"];
                [spec setProperty:@NO forKey:@"isManualApp"];
                [specs insertObject:spec atIndex:insertIndexCustom++];
            }
        }
        
        _specifiers = [specs copy];
    }
    return _specifiers;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"com.eolnmsuk.antidarkswordprefs"];
    NSInteger currentLevel = [defaults objectForKey:@"autoProtectLevel"] ? [defaults integerForKey:@"autoProtectLevel"] : 1;
    [self populateDefaultRulesForLevel:currentLevel force:NO];
    
    UIBarButtonItem *saveButton = [[UIBarButtonItem alloc] initWithTitle:@"Save" style:UIBarButtonItemStyleDone target:self action:@selector(savePrompt)];
    self.navigationItem.rightBarButtonItem = saveButton;
    
    BOOL isEnabled = [defaults boolForKey:@"enabled"];
    BOOL needsRespring = [defaults boolForKey:@"ADSNeedsRespring"];
    BOOL needsReboot = [defaults boolForKey:@"ADSPendingDaemonChanges"];
    
    saveButton.enabled = needsRespring || (isEnabled && needsReboot);
    
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
        BOOL isEnabled = [defaults boolForKey:@"enabled"];
        BOOL needsRespring = [defaults boolForKey:@"ADSNeedsRespring"];
        BOOL needsReboot = [defaults boolForKey:@"ADSPendingDaemonChanges"];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            controller.navigationItem.rightBarButtonItem.enabled = needsRespring || (isEnabled && needsReboot);
        });
    }
}

- (void)flagSaveRequirement {
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"com.eolnmsuk.antidarkswordprefs"];
    [defaults setBool:YES forKey:@"ADSNeedsRespring"];
    [defaults synchronize];
    
    BOOL isEnabled = [defaults boolForKey:@"enabled"];
    BOOL needsRespring = [defaults boolForKey:@"ADSNeedsRespring"];
    BOOL needsReboot = [defaults boolForKey:@"ADSPendingDaemonChanges"];
    self.navigationItem.rightBarButtonItem.enabled = needsRespring || (isEnabled && needsReboot);
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"com.eolnmsuk.antidarkswordprefs"];

    if ([key isEqualToString:@"customUAString"]) {
        NSString *input = (NSString *)value;
        NSString *trimmed = [input stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        
        if (trimmed.length == 0) {
            NSString *ios18UA = @"Mozilla/5.0 (iPhone; CPU iPhone OS 18_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1";
            value = ios18UA;
            
            [defaults setObject:ios18UA forKey:@"selectedUAPreset"];
            [defaults synchronize];
            
            dispatch_async(dispatch_get_main_queue(), ^{
                self->_specifiers = nil;
                [self reloadSpecifiers];
            });
        }
    }

    [super setPreferenceValue:value specifier:specifier];
    [self flagSaveRequirement];
    
    if ([key isEqualToString:@"selectedUAPreset"]) {
        if (![defaults boolForKey:@"enabled"]) {
            [defaults setBool:YES forKey:@"enabled"];
            [defaults synchronize];
        }
        _specifiers = nil;
        [self reloadSpecifiers];
    }
}

- (void)setAutoProtect:(id)value specifier:(PSSpecifier*)specifier {
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"com.eolnmsuk.antidarkswordprefs"];
    BOOL enabled = [value boolValue];
    [defaults setObject:value forKey:@"autoProtectEnabled"];
    
    if (enabled) {
        if (![defaults boolForKey:@"enabled"]) {
            [defaults setBool:YES forKey:@"enabled"];
        }
    }
    
    if ([defaults integerForKey:@"autoProtectLevel"] >= 3) {
        [defaults setBool:YES forKey:@"ADSPendingDaemonChanges"];
    }
    [defaults synchronize];
    [self flagSaveRequirement];
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFSTR("com.eolnmsuk.antidarkswordprefs/saved"), NULL, NULL, YES);
    
    _specifiers = nil;
    [self reloadSpecifiers];
}

- (void)setAutoProtectLevel:(id)value specifier:(PSSpecifier*)specifier {
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"com.eolnmsuk.antidarkswordprefs"];
    NSInteger oldLevel = [defaults integerForKey:@"autoProtectLevel"];
    NSInteger newLevel = [value integerValue];
    
    [defaults setObject:value forKey:@"autoProtectLevel"];
    
    if (oldLevel != newLevel) {
        [self populateDefaultRulesForLevel:newLevel force:YES];
    }
    
    if (oldLevel >= 3 || newLevel >= 3) {
        [defaults setBool:YES forKey:@"ADSPendingDaemonChanges"];
    }
    [defaults synchronize];
    [self flagSaveRequirement];
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFSTR("com.eolnmsuk.antidarkswordprefs/saved"), NULL, NULL, YES);
    
    _specifiers = nil;
    [self reloadSpecifiers];
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
                    if (![activeCustom containsObject:cleanID]) [activeCustom addObject:cleanID];
                    changesMade = YES;
                }
            }
            
            if (changesMade) {
                [defaults setObject:customIDs forKey:@"customDaemonIDs"];
                [defaults setObject:activeCustom forKey:@"activeCustomDaemonIDs"];
                [defaults setBool:YES forKey:@"ADSPendingDaemonChanges"];
                [defaults synchronize];
                [self flagSaveRequirement];
                
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
    return [[spec propertyForKey:@"isCustomDaemon"] boolValue];
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle == UITableViewCellEditingStyleDelete) {
        PSSpecifier *spec = [self specifierAtIndexPath:indexPath];
        NSString *daemonID = [spec propertyForKey:@"daemonID"];
        BOOL isManualApp = [[spec propertyForKey:@"isManualApp"] boolValue];
        
        NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"com.eolnmsuk.antidarkswordprefs"];
        
        // Target correct backend storage based on the ruleType the cell was mapped to
        if (isManualApp) {
            NSString *key = [NSString stringWithFormat:@"restrictedApps-%@", daemonID];
            [defaults setBool:NO forKey:key];
            
            NSMutableDictionary *apps = [[defaults dictionaryForKey:@"restrictedApps"] mutableCopy];
            if (apps && apps[daemonID]) {
                [apps removeObjectForKey:daemonID];
                [defaults setObject:apps forKey:@"restrictedApps"];
            }
        } else {
            NSMutableArray *customIDs = [[defaults objectForKey:@"customDaemonIDs"] ?: @[] mutableCopy];
            NSMutableArray *activeCustom = [[defaults objectForKey:@"activeCustomDaemonIDs"] ?: customIDs mutableCopy];
            
            [customIDs removeObject:daemonID];
            [activeCustom removeObject:daemonID];
            
            [defaults setObject:customIDs forKey:@"customDaemonIDs"];
            [defaults setObject:activeCustom forKey:@"activeCustomDaemonIDs"];
            [defaults setBool:YES forKey:@"ADSPendingDaemonChanges"];
        }
        
        NSString *dictKey = [NSString stringWithFormat:@"TargetRules_%@", daemonID];
        [defaults removeObjectForKey:dictKey];
        
        [defaults synchronize];
        [self flagSaveRequirement];
        
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
    BOOL needsReboot = [defaults boolForKey:@"ADSPendingDaemonChanges"];
    
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
