#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <UIKit/UIKit.h>
#import <spawn.h>
#import <sys/types.h>
#import <objc/runtime.h>

static void PrefsChangedNotification(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo);

// ==========================================
// Internal iOS APIs for App Names & Icons
// ==========================================
@interface LSApplicationProxy : NSObject
+ (id)applicationProxyForIdentifier:(NSString *)identifier;
- (NSString *)localizedName;
@end

@interface UIImage (Private)
+ (UIImage *)_applicationIconImageForBundleIdentifier:(NSString *)bundleIdentifier format:(int)format scale:(CGFloat)scale;
@end

// Tell the compiler this method exists to prevent ARC errors without redefining PSTableCell
@interface UITableViewCell (PreferencesUI)
- (id)control;
@end

@interface AntiDarkSwordPrefsRootListController : PSListController
- (NSArray *)autoProtectedItemsForLevel:(NSInteger)level;
- (void)populateDefaultRulesForLevel:(NSInteger)level force:(BOOL)force;
- (NSString *)displayNameForTargetID:(NSString *)targetID;
- (UIImage *)iconForTargetID:(NSString *)targetID;
@end

// ==========================================
// App-Specific Feature Drill-Down Controller
// ==========================================
@interface AntiDarkSwordAppController : PSListController
@property (nonatomic, strong) NSString *targetID;
@property (nonatomic, assign) NSInteger ruleType;
@end

// ==========================================
// Custom AltList Controller
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
        
        // Completely hide the native AltList switch
        if ([cell respondsToSelector:@selector(control)]) {
            id control = [cell control];
            if ([control isKindOfClass:[UIView class]]) {
                ((UIView *)control).hidden = YES;
            }
        }
        
        // Replace the right side with a standard navigation chevron
        cell.accessoryView = nil;
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        cell.selectionStyle = UITableViewCellSelectionStyleDefault; // Ensure row highlights when tapped
        
        if ([presetApps containsObject:bundleID]) {
            // Lock and grey out UI for preset apps
            cell.userInteractionEnabled = NO;
            cell.textLabel.alpha = 0.5;
            if (cell.detailTextLabel) cell.detailTextLabel.alpha = 0.5;
        } else {
            // Leave manual apps accessible 
            cell.userInteractionEnabled = YES;
            cell.textLabel.alpha = 1.0;
            if (cell.detailTextLabel) cell.detailTextLabel.alpha = 1.0;
        }
    }
    
    return cell;
}

// Override tap behavior to push detail options screen instead of just toggling switch natively
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

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
        
        // Prevent opening detailed view if preset enforces it (User must manage via Preset Rules UI)
        if ([presetApps containsObject:bundleID]) {
            return; 
        }

        // Forward to the app specific detail controller
        AntiDarkSwordAppController *detailController = [[AntiDarkSwordAppController alloc] init];
        detailController.targetID = bundleID;
        detailController.ruleType = 1; // AltList rule type
        detailController.rootController = self.rootController ?: self;
        detailController.parentController = self;
        
        PSSpecifier *dummySpec = [PSSpecifier preferenceSpecifierNamed:[spec name] ?: bundleID target:self set:nil get:nil detail:[AntiDarkSwordAppController class] cell:PSLinkCell edit:nil];
        [dummySpec setProperty:bundleID forKey:@"targetID"];
        [dummySpec setProperty:@(1) forKey:@"ruleType"];
        [detailController setSpecifier:dummySpec];

        [self pushController:detailController];
    }
}

@end

// ==========================================
// App-Specific Feature Drill-Down Implementation
// ==========================================
@implementation AntiDarkSwordAppController
- (void)setSpecifier:(PSSpecifier *)specifier {
    [super setSpecifier:specifier];
    self.targetID = [specifier propertyForKey:@"targetID"];
    self.ruleType = [[specifier propertyForKey:@"ruleType"] integerValue];
    // Use the localized friendly name passed by the specifier, otherwise fall back to raw ID
    self.title = [specifier name] ?: self.targetID;
}

- (NSArray *)specifiers {
    if (!_specifiers) {
        NSMutableArray *specs = [NSMutableArray array];
        
        PSSpecifier *enableGroup = [PSSpecifier preferenceSpecifierNamed:@"Rule Status" target:self set:nil get:nil detail:nil cell:PSGroupCell edit:nil];
        [specs addObject:enableGroup];
        
        PSSpecifier *enableSpec = [PSSpecifier preferenceSpecifierNamed:@"Enable Rule" target:self set:@selector(setMasterEnable:specifier:) get:@selector(getMasterEnable:) detail:nil cell:PSSwitchCell edit:nil];
        [specs addObject:enableSpec];
        
        // Check state to properly grey out options if the rule is off
        BOOL isRuleEnabled = [[self getMasterEnable:enableSpec] boolValue];
        
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
            // PreferenceLoader will automatically grey out the cell visually when passed @NO
            [spec setProperty:@(isRuleEnabled) forKey:@"enabled"];
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
    
    // Smoothly reload the specifiers asynchronously so the greyed-out options apply visually right away 
    dispatch_async(dispatch_get_main_queue(), ^{
        self->_specifiers = nil;
        [self reloadSpecifiers];
    });
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
                @"com.apple.imagent", @"imagent", @"com.apple.mediaserverd",
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

- (NSString *)displayNameForTargetID:(NSString *)targetID {
    if (![targetID containsString:@"."]) return targetID; // Leave literal string processes alone
    
    // Explicitly exclude system services that lack a clean localized name
    NSArray *daemons = @[
        @"com.apple.imagent", @"com.apple.mediaserverd",
        @"com.apple.networkd", @"com.apple.apsd", @"com.apple.identityservicesd",
        @"com.apple.SafariViewService", @"com.apple.MailCompositionService",
        @"com.apple.iMessageAppsViewService", @"com.apple.ActivityMessagesApp",
        @"com.apple.quicklook.QuickLookUIService", @"com.apple.QuickLookDaemon",
        @"com.apple.appstored", @"com.apple.itunesstored", @"com.apple.nsurlsessiond",
        @"com.apple.cfnetwork"
    ];
    
    if ([daemons containsObject:targetID]) {
        return targetID;
    }

    @try {
        Class LSAppProxy = NSClassFromString(@"LSApplicationProxy");
        if (LSAppProxy) {
            id proxy = [LSAppProxy applicationProxyForIdentifier:targetID];
            if (proxy && [proxy respondsToSelector:@selector(localizedName)]) {
                NSString *name = [proxy localizedName];
                if (name && name.length > 0) {
                    return name;
                }
            }
        }
    } @catch (NSException *e) {}
    
    return targetID;
}

- (UIImage *)iconForTargetID:(NSString *)targetID {
    UIImage *icon = nil;
    
    // Try to fetch real application icon
    if ([targetID containsString:@"."]) {
        NSArray *daemons = @[
            @"com.apple.imagent", @"com.apple.mediaserverd",
            @"com.apple.networkd", @"com.apple.apsd", @"com.apple.identityservicesd",
            @"com.apple.SafariViewService", @"com.apple.MailCompositionService",
            @"com.apple.iMessageAppsViewService", @"com.apple.ActivityMessagesApp",
            @"com.apple.quicklook.QuickLookUIService", @"com.apple.QuickLookDaemon",
            @"com.apple.appstored", @"com.apple.itunesstored", @"com.apple.nsurlsessiond",
            @"com.apple.cfnetwork"
        ];
        
        if (![daemons containsObject:targetID]) {
            @try {
                if ([UIImage respondsToSelector:@selector(_applicationIconImageForBundleIdentifier:format:scale:)]) {
                    // Format 29 gets the standard iOS small settings icon
                    icon = [UIImage _applicationIconImageForBundleIdentifier:targetID format:29 scale:[UIScreen mainScreen].scale];
                }
            } @catch (NSException *e) {}
        }
    }
    
    // Fallback: Default gear icon for daemons or missing icons
    if (!icon) {
        if (@available(iOS 13.0, *)) {
            icon = [UIImage systemImageNamed:@"gearshape.fill"];
            icon = [icon imageWithTintColor:[UIColor systemGrayColor] renderingMode:UIImageRenderingModeAlwaysOriginal];
        }
    }
    
    // Resize the icon to be ~20% smaller (23x23 instead of standard 29x29)
    if (icon) {
        CGSize newSize = CGSizeMake(23, 23);
        UIGraphicsBeginImageContextWithOptions(newSize, NO, [UIScreen mainScreen].scale);
        [icon drawInRect:CGRectMake(0, 0, newSize.width, newSize.height)];
        UIImage *resizedIcon = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
        return resizedIcon;
    }
    
    return nil;
}

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
        @"com.apple.imagent", @"imagent", @"com.apple.mediaserverd",
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
        @"com.google.Gmail", @"com.microsoft.Office.Outlook", @"com.yahoo.Aerogram", @"ch.protonmail.protonmail",
        @"org.whispersystems.signal", @"ph.telegra.Telegraph", @"com.facebook.Messenger", 
        @"com.toyopagroup.picaboo", @"com.tinyspeck.chatlyio", @"com.microsoft.skype.teams", 
        @"com.tencent.xin", @"com.viber", @"jp.naver.line", @"net.whatsapp.WhatsApp", 
        @"com.hammerandchisel.discord",
        @"com.google.GoogleMobile", @"com.google.chrome.ios", @"org.mozilla.ios.Firefox", 
        @"com.brave.ios.browser", @"com.duckduckgo.mobile.ios",
        @"pinterest", @"com.tumblr.tumblr", @"com.facebook.Facebook", @"com.atebits.Tweetie2", 
        @"com.burbn.instagram", @"com.zhiliaoapp.musically", @"com.linkedin.LinkedIn", 
        @"com.reddit.Reddit", @"com.google.ios.youtube", @"tv.twitch",
        @"com.google.gemini", @"com.openai.chat", @"com.deepseek.chat", @"com.github.stormbreaker.prod",
        @"org.coolstar.SileoStore", @"xyz.willy.Zebra", @"com.tigisoftware.Filza"
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
            // Automatically inject our custom AltList controller
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

        // Current Preset Rules Menu Render
        NSUInteger insertIndexAuto = [specs indexOfObjectPassingTest:^BOOL(PSSpecifier *obj, NSUInteger idx, BOOL *stop) {
            return [[obj propertyForKey:@"id"] isEqualToString:@"AutoProtectLevelSegment"];
        }];
        
        if (insertIndexAuto != NSNotFound) {
            insertIndexAuto++;
            PSSpecifier *groupSpec = [PSSpecifier preferenceSpecifierNamed:@"Current Preset Rules" target:self set:nil get:nil detail:nil cell:PSGroupCell edit:nil];
            [specs insertObject:groupSpec atIndex:insertIndexAuto++];
            
            NSArray *autoItems = [self autoProtectedItemsForLevel:autoProtectLevel];
            for (NSString *item in autoItems) {
                NSString *displayName = [self displayNameForTargetID:item];
                PSSpecifier *spec = [PSSpecifier preferenceSpecifierNamed:displayName target:self set:nil get:nil detail:[AntiDarkSwordAppController class] cell:PSLinkCell edit:nil];
                [spec setProperty:item forKey:@"targetID"];
                [spec setProperty:@(0) forKey:@"ruleType"]; // Preset rule
                
                // Add Native App Icon
                UIImage *icon = [self iconForTargetID:item];
                if (icon) {
                    [spec setProperty:icon forKey:@"iconImage"];
                }
                
                [specs insertObject:spec atIndex:insertIndexAuto++];
            }
        }
        
        // Advanced Custom Rules Menu Render (Strictly Custom Process Strings Now)
        NSUInteger insertIndexCustom = [specs indexOfObjectPassingTest:^BOOL(PSSpecifier *obj, NSUInteger idx, BOOL *stop) {
            return [[obj propertyForKey:@"id"] isEqualToString:@"AddCustomIDButton"];
        }];
        
        if (insertIndexCustom != NSNotFound) {
            insertIndexCustom++;
            for (NSString *daemonID in customIDs) {
                NSString *displayName = [self displayNameForTargetID:daemonID];
                PSSpecifier *spec = [PSSpecifier preferenceSpecifierNamed:displayName target:self set:nil get:nil detail:[AntiDarkSwordAppController class] cell:PSLinkCell edit:nil];
                [spec setProperty:daemonID forKey:@"targetID"];
                [spec setProperty:daemonID forKey:@"daemonID"]; // Keep for swipe-to-delete
                [spec setProperty:@(2) forKey:@"ruleType"]; // Custom rule
                [spec setProperty:@YES forKey:@"isCustomDaemon"];
                
                // Native App Icon 
                UIImage *icon = [self iconForTargetID:daemonID];
                if (icon) {
                    [spec setProperty:icon forKey:@"iconImage"];
                }
                
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

// Cleaned up for custom IDs only
- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle == UITableViewCellEditingStyleDelete) {
        PSSpecifier *spec = [self specifierAtIndexPath:indexPath];
        NSString *daemonID = [spec propertyForKey:@"daemonID"];
        
        NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"com.eolnmsuk.antidarkswordprefs"];
        NSMutableArray *customIDs = [[defaults objectForKey:@"customDaemonIDs"] ?: @[] mutableCopy];
        NSMutableArray *activeCustom = [[defaults objectForKey:@"activeCustomDaemonIDs"] ?: customIDs mutableCopy];
        
        [customIDs removeObject:daemonID];
        [activeCustom removeObject:daemonID];
        
        NSString *dictKey = [NSString stringWithFormat:@"TargetRules_%@", daemonID];
        [defaults removeObjectForKey:dictKey];
        
        [defaults setObject:customIDs forKey:@"customDaemonIDs"];
        [defaults setObject:activeCustom forKey:@"activeCustomDaemonIDs"];
        [defaults setBool:YES forKey:@"ADSPendingDaemonChanges"];
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
            [defaults removeObjectForKey:key];
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
