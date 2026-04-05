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
- (NSURL *)bundleURL;
@end

@interface LSApplicationWorkspace : NSObject
+ (id)defaultWorkspace;
- (BOOL)applicationIsInstalled:(NSString *)appIdentifier;
@end

@interface UIImage (Private)
+ (UIImage *)_applicationIconImageForBundleIdentifier:(NSString *)bundleIdentifier format:(int)format scale:(CGFloat)scale;
@end

@interface UITableViewCell (PreferencesUI)
- (id)control;
@end

@interface AntiDarkSwordPrefsRootListController : PSListController
- (NSArray *)autoProtectedItemsForLevel:(NSInteger)level;
- (void)populateDefaultRulesForLevel:(NSInteger)level force:(BOOL)force;
- (NSString *)displayNameForTargetID:(NSString *)targetID;
- (UIImage *)iconForTargetID:(NSString *)targetID;
- (BOOL)isTargetInstalled:(NSString *)targetID;
@end

// ==========================================
// App-Specific Feature Drill-Down Controller
// ==========================================
@interface AntiDarkSwordAppController : PSListController
@property (nonatomic, strong) NSString *targetID;
@property (nonatomic, assign) NSInteger ruleType;
+ (BOOL)isDaemonTarget:(NSString *)targetID;
+ (BOOL)isApplicableFeature:(NSString *)featureKey forTarget:(NSString *)targetID;
- (BOOL)isGlobalOverrideActiveForFeature:(NSString *)featureKey;
@end

// ==========================================
// System Daemon Consolidated List
// ==========================================
@interface AntiDarkSwordDaemonListController : PSListController
@end

@implementation AntiDarkSwordDaemonListController

- (NSArray *)specifiers {
    if (!_specifiers) {
        NSMutableArray *specs = [NSMutableArray array];
        AntiDarkSwordPrefsRootListController *rootCtrl = [[AntiDarkSwordPrefsRootListController alloc] init];

        PSSpecifier *group = [PSSpecifier preferenceSpecifierNamed:@"System Daemons" target:self set:nil get:nil detail:nil cell:PSGroupCell edit:nil];
        [group setProperty:@"Disabling a daemon bypasses all zero-click mitigations for that process. It is highly recommended to leave these enabled on Level 3." forKey:@"footerText"];
        [specs addObject:group];

        NSArray *daemons = @[@"imagent", @"mediaserverd", @"networkd", @"apsd", @"identityservicesd"];
        for (NSString *daemon in daemons) {
            PSSpecifier *spec = [PSSpecifier preferenceSpecifierNamed:[rootCtrl displayNameForTargetID:daemon] target:self set:@selector(setDaemonEnabled:specifier:) get:@selector(getDaemonEnabled:) detail:nil cell:PSSwitchCell edit:nil];
            [spec setProperty:daemon forKey:@"targetID"];
            [specs addObject:spec];
        }
        _specifiers = [specs copy];
    }
    return _specifiers;
}

- (id)getDaemonEnabled:(PSSpecifier *)spec {
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"com.eolnmsuk.antidarkswordprefs"];
    NSArray *disabled = [defaults arrayForKey:@"disabledPresetRules"] ?: @[];
    return @(![disabled containsObject:[spec propertyForKey:@"targetID"]]);
}

- (void)setDaemonEnabled:(id)value specifier:(PSSpecifier *)spec {
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"com.eolnmsuk.antidarkswordprefs"];
    NSMutableArray *disabled = [[defaults arrayForKey:@"disabledPresetRules"] mutableCopy] ?: [NSMutableArray array];
    NSString *targetID = [spec propertyForKey:@"targetID"];

    if ([value boolValue]) {
        [disabled removeObject:targetID];
        if ([targetID isEqualToString:@"imagent"]) [disabled removeObject:@"com.apple.imagent"];
    } else {
        if (![disabled containsObject:targetID]) [disabled addObject:targetID];
        if ([targetID isEqualToString:@"imagent"] && ![disabled containsObject:@"com.apple.imagent"]) [disabled addObject:@"com.apple.imagent"];
    }

    [defaults setObject:disabled forKey:@"disabledPresetRules"];
    [defaults setBool:YES forKey:@"ADSNeedsRespring"];
    [defaults setBool:YES forKey:@"ADSPendingDaemonChanges"];
    [defaults synchronize];
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFSTR("com.eolnmsuk.antidarkswordprefs/saved"), NULL, NULL, YES);
}
@end

// ==========================================
// Custom AltList Controller
// ==========================================
@interface ATLApplicationListMultiSelectionController : PSListController
@end

@interface AntiDarkSwordAltListController : ATLApplicationListMultiSelectionController
@end

@implementation AntiDarkSwordAltListController

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reloadSpecifiers];
}

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
        
        if ([cell respondsToSelector:@selector(control)]) {
            id control = [cell control];
            if ([control isKindOfClass:[UIView class]]) {
                ((UIView *)control).hidden = YES;
            }
        }
        
        cell.accessoryView = nil;
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
        
        BOOL isManualRuleActive = NO;
        NSString *prefKey = [NSString stringWithFormat:@"restrictedApps-%@", bundleID];
        if ([defaults objectForKey:prefKey]) {
            isManualRuleActive = [defaults boolForKey:prefKey];
        } else {
            NSDictionary *apps = [defaults dictionaryForKey:@"restrictedApps"];
            isManualRuleActive = [apps[bundleID] boolValue];
        }

        if ([presetApps containsObject:bundleID]) {
            cell.userInteractionEnabled = NO;
            cell.textLabel.alpha = 0.5;
            if (cell.detailTextLabel) cell.detailTextLabel.alpha = 0.5;
            cell.backgroundColor = [UIColor clearColor];
        } else {
            cell.userInteractionEnabled = YES;
            cell.textLabel.alpha = 1.0;
            if (cell.detailTextLabel) cell.detailTextLabel.alpha = 1.0;
            
            if (isManualRuleActive) {
                if (@available(iOS 13.0, *)) {
                    cell.backgroundColor = [[UIColor systemGreenColor] colorWithAlphaComponent:0.15];
                } else {
                    cell.backgroundColor = [UIColor colorWithRed:0.2 green:0.8 blue:0.2 alpha:0.15];
                }
            } else {
                if (@available(iOS 13.0, *)) {
                    cell.backgroundColor = [[UIColor systemRedColor] colorWithAlphaComponent:0.15];
                } else {
                    cell.backgroundColor = [UIColor colorWithRed:0.8 green:0.2 blue:0.2 alpha:0.15];
                }
            }
        }
    }
    
    return cell;
}

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
        
        if ([presetApps containsObject:bundleID]) {
            return; 
        }

        AntiDarkSwordAppController *detailController = [[AntiDarkSwordAppController alloc] init];
        detailController.targetID = bundleID;
        detailController.ruleType = 1; 
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

+ (BOOL)isDaemonTarget:(NSString *)targetID {
    if (!targetID) return NO;
    NSArray *daemons = @[
        @"com.apple.imagent", @"imagent", @"com.apple.mediaserverd", @"mediaserverd",
        @"com.apple.networkd", @"networkd", @"com.apple.apsd", @"apsd",
        @"com.apple.identityservicesd", @"identityservicesd", @"com.apple.appstored", 
        @"com.apple.itunesstored", @"com.apple.nsurlsessiond", @"com.apple.cfnetwork"
    ];
    if ([daemons containsObject:targetID]) return YES;
    
    if (![targetID containsString:@"."] && ![targetID isEqualToString:@"pinterest"]) return YES;
    if ([targetID containsString:@"daemon"]) return YES;
    if ([targetID hasPrefix:@"com.apple."] && [targetID hasSuffix:@"d"]) {
        return YES;
    }
    
    return NO;
}

+ (BOOL)isApplicableFeature:(NSString *)featureKey forTarget:(NSString *)targetID {
    BOOL isDaemon = [self isDaemonTarget:targetID];
    
    BOOL isMessageApp = [targetID isEqualToString:@"com.apple.MobileSMS"] || 
                        [targetID isEqualToString:@"com.apple.ActivityMessagesApp"] || 
                        [targetID isEqualToString:@"com.apple.iMessageAppsViewService"];

    if ([featureKey isEqualToString:@"disableIMessageDL"]) {
        return isMessageApp;
    }
    
    BOOL isIOS16OrGreater = [[NSProcessInfo processInfo] operatingSystemVersion].majorVersion >= 16;
    
    if ([featureKey isEqualToString:@"disableJIT"]) {
        return isIOS16OrGreater && !isDaemon;
    }
    if ([featureKey isEqualToString:@"disableJIT15"]) {
        return !isIOS16OrGreater && !isDaemon;
    }

    if ([featureKey isEqualToString:@"disableJS"] || 
        [featureKey isEqualToString:@"disableRTC"] || 
        [featureKey isEqualToString:@"disableMedia"] || 
        [featureKey isEqualToString:@"disableFileAccess"]) {
        return !isDaemon; 
    }

    if ([featureKey isEqualToString:@"spoofUA"]) {
        return YES; 
    }

    return YES;
}

- (void)setSpecifier:(PSSpecifier *)specifier {
    [super setSpecifier:specifier];
    self.targetID = [specifier propertyForKey:@"targetID"];
    self.ruleType = [[specifier propertyForKey:@"ruleType"] integerValue];
    self.title = [specifier name] ?: self.targetID;
}

- (BOOL)isGlobalOverrideActiveForFeature:(NSString *)featureKey {
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"com.eolnmsuk.antidarkswordprefs"];
    if ([featureKey isEqualToString:@"spoofUA"]) return [defaults boolForKey:@"globalUASpoofingEnabled"];
    if ([featureKey isEqualToString:@"disableJIT"]) return [defaults boolForKey:@"globalDisableJIT"];
    if ([featureKey isEqualToString:@"disableJIT15"]) return [defaults boolForKey:@"globalDisableJIT15"];
    if ([featureKey isEqualToString:@"disableJS"]) return [defaults boolForKey:@"globalDisableJS"];
    if ([featureKey isEqualToString:@"disableRTC"]) return [defaults boolForKey:@"globalDisableRTC"];
    if ([featureKey isEqualToString:@"disableMedia"]) return [defaults boolForKey:@"globalDisableMedia"];
    if ([featureKey isEqualToString:@"disableIMessageDL"]) return [defaults boolForKey:@"globalDisableIMessageDL"];
    if ([featureKey isEqualToString:@"disableFileAccess"]) return [defaults boolForKey:@"globalDisableFileAccess"];
    return NO;
}

- (NSArray *)specifiers {
    if (!_specifiers) {
        NSMutableArray *specs = [NSMutableArray array];
        NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"com.eolnmsuk.antidarkswordprefs"];
        [defaults synchronize];
        
        PSSpecifier *enableGroup = [PSSpecifier preferenceSpecifierNamed:@"Rule Status" target:self set:nil get:nil detail:nil cell:PSGroupCell edit:nil];
        [specs addObject:enableGroup];
        
        PSSpecifier *enableSpec = [PSSpecifier preferenceSpecifierNamed:@"Enable Rule" target:self set:@selector(setMasterEnable:specifier:) get:@selector(getMasterEnable:) detail:nil cell:PSSwitchCell edit:nil];
        [specs addObject:enableSpec];
        
        BOOL isRuleEnabled = [[self getMasterEnable:enableSpec] boolValue];
        
        PSSpecifier *featGroup = [PSSpecifier preferenceSpecifierNamed:@"Mitigation Features" target:self set:nil get:nil detail:nil cell:PSGroupCell edit:nil];
        [featGroup setProperty:@"Features not applicable to this target type, or currently enforced by a Global Rule, are locked." forKey:@"footerText"];
        [specs addObject:featGroup];
        
        NSArray *features = @[
            @{@"key": @"spoofUA", @"label": @"Spoof User Agent"},
            @{@"key": @"disableJIT", @"label": @"Disable iOS 16+ JIT"},
            @{@"key": @"disableJIT15", @"label": @"Disable iOS 15 JIT"},
            @{@"key": @"disableJS", @"label": @"Disable JavaScript ⚠︎"},
            @{@"key": @"disableRTC", @"label": @"Disable WebGL & WebRTC"},
            @{@"key": @"disableMedia", @"label": @"Disable Media Auto-Play"},
            @{@"key": @"disableIMessageDL", @"label": @"Disable Msg Auto-Download"},
            @{@"key": @"disableFileAccess", @"label": @"Disable Local File Access"}
        ];
        
        NSString *dictKey = [NSString stringWithFormat:@"TargetRules_%@", self.targetID];
        NSDictionary *rules = [defaults dictionaryForKey:dictKey];
        BOOL isIOS16OrGreater = [[NSProcessInfo processInfo] operatingSystemVersion].majorVersion >= 16;
        BOOL isJSTurnedOn = NO;
        if (rules && rules[@"disableJS"] != nil) {
            isJSTurnedOn = [rules[@"disableJS"] boolValue];
        } else {
            isJSTurnedOn = (!isIOS16OrGreater && [AntiDarkSwordAppController isApplicableFeature:@"disableJS" forTarget:self.targetID]);
        }
        
        for (NSDictionary *feat in features) {
            NSString *featKey = feat[@"key"];
            BOOL isApplicable = [AntiDarkSwordAppController isApplicableFeature:featKey forTarget:self.targetID];
            BOOL isGlobalOverride = [self isGlobalOverrideActiveForFeature:featKey];
            
            PSSpecifier *spec = [PSSpecifier preferenceSpecifierNamed:feat[@"label"] target:self set:@selector(setFeatureValue:specifier:) get:@selector(getFeatureValue:) detail:nil cell:PSSwitchCell edit:nil];
            [spec setProperty:featKey forKey:@"featureKey"];
            
            if (isApplicable) {
                if (isGlobalOverride) {
                    [spec setProperty:@NO forKey:@"enabled"];
                } else if (isIOS16OrGreater && isJSTurnedOn && [featKey isEqualToString:@"disableJIT"]) {
                    [spec setProperty:@NO forKey:@"enabled"];
                } else if (!isIOS16OrGreater && isJSTurnedOn && [featKey isEqualToString:@"disableJIT15"]) {
                    [spec setProperty:@NO forKey:@"enabled"];
                } else {
                    [spec setProperty:@(isRuleEnabled) forKey:@"enabled"];
                }
            } else {
                [spec setProperty:@NO forKey:@"enabled"];
            }
            
            [specs addObject:spec];
        }
        
        _specifiers = [specs copy];
    }
    return _specifiers;
}

- (id)getMasterEnable:(PSSpecifier *)specifier {
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"com.eolnmsuk.antidarkswordprefs"];
    [defaults synchronize]; 
    
    if (self.ruleType == 0) { 
        NSArray *disabled = [defaults arrayForKey:@"disabledPresetRules"] ?: @[];
        return @(![disabled containsObject:self.targetID]);
    } else if (self.ruleType == 1) { 
        NSString *prefKey = [NSString stringWithFormat:@"restrictedApps-%@", self.targetID];
        if ([defaults objectForKey:prefKey]) {
            return @([defaults boolForKey:prefKey]);
        }
        NSDictionary *apps = [defaults dictionaryForKey:@"restrictedApps"];
        return apps[self.targetID] ?: @NO;
    } else { 
        NSArray *active = [defaults arrayForKey:@"activeCustomDaemonIDs"] ?: [defaults arrayForKey:@"customDaemonIDs"] ?: @[];
        return @([active containsObject:self.targetID]);
    }
}

- (void)setMasterEnable:(id)value specifier:(PSSpecifier *)specifier {
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"com.eolnmsuk.antidarkswordprefs"];
    BOOL enabled = [value boolValue];
    
    if (self.ruleType == 0) { 
        NSMutableArray *disabled = [[defaults arrayForKey:@"disabledPresetRules"] mutableCopy] ?: [NSMutableArray array];
        if (enabled) [disabled removeObject:self.targetID];
        else if (![disabled containsObject:self.targetID]) [disabled addObject:self.targetID];
        [defaults setObject:disabled forKey:@"disabledPresetRules"];
    } else if (self.ruleType == 1) { 
        NSString *prefKey = [NSString stringWithFormat:@"restrictedApps-%@", self.targetID];
        [defaults setBool:enabled forKey:prefKey];
        
        NSMutableDictionary *apps = [[defaults dictionaryForKey:@"restrictedApps"] mutableCopy];
        if (apps && apps[self.targetID]) {
            [apps removeObjectForKey:self.targetID];
            [defaults setObject:apps forKey:@"restrictedApps"];
        }
    } else { 
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
    
    dispatch_async(dispatch_get_main_queue(), ^{
        self->_specifiers = nil;
        [self reloadSpecifiers];
    });
}

- (id)getFeatureValue:(PSSpecifier *)specifier {
    NSString *featureKey = [specifier propertyForKey:@"featureKey"];
    
    if (![AntiDarkSwordAppController isApplicableFeature:featureKey forTarget:self.targetID]) {
        return @NO;
    }

    if ([self isGlobalOverrideActiveForFeature:featureKey]) {
        return @YES;
    }

    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"com.eolnmsuk.antidarkswordprefs"];
    [defaults synchronize]; 
    NSString *dictKey = [NSString stringWithFormat:@"TargetRules_%@", self.targetID];
    NSDictionary *rules = [defaults dictionaryForKey:dictKey];
    
    if (!rules || rules[featureKey] == nil) { 
        
        AntiDarkSwordPrefsRootListController *rootCtrl = [[AntiDarkSwordPrefsRootListController alloc] init];
        NSArray *allProtected = [rootCtrl autoProtectedItemsForLevel:3];
        if (![allProtected containsObject:self.targetID]) {
            return @NO;
        }

        NSInteger level = [defaults integerForKey:@"autoProtectLevel"];
        if (level == 0) level = 1;
        BOOL isIOS16OrGreater = [[NSProcessInfo processInfo] operatingSystemVersion].majorVersion >= 16;

        if ([featureKey isEqualToString:@"disableJIT"]) return isIOS16OrGreater ? @YES : @NO; 
        if ([featureKey isEqualToString:@"disableJIT15"]) return !isIOS16OrGreater ? @YES : @NO; 
        if ([featureKey isEqualToString:@"disableJS"]) return isIOS16OrGreater ? @NO : @YES; 
        
        if ([featureKey isEqualToString:@"spoofUA"]) {
            if ([AntiDarkSwordAppController isDaemonTarget:self.targetID]) return @NO;
            if ([self.targetID hasPrefix:@"com.apple."]) return @NO; 
            return (level >= 2) ? @YES : @NO; 
        }
        
        NSArray *msgAndMail = @[
            @"com.apple.MobileSMS", @"com.apple.mobilemail", @"com.apple.MailCompositionService", 
            @"com.apple.iMessageAppsViewService", @"com.apple.ActivityMessagesApp", 
            @"com.google.Gmail", @"com.microsoft.Office.Outlook", @"com.yahoo.Aerogram", 
            @"ch.protonmail.protonmail", @"org.whispersystems.signal", @"ph.telegra.Telegraph", 
            @"com.facebook.Messenger", @"net.whatsapp.WhatsApp", @"com.hammerandchisel.discord", 
            @"com.apple.Passbook"
        ];
        
        if ([msgAndMail containsObject:self.targetID]) return @YES;
        
        if (level >= 3 && ([featureKey isEqualToString:@"disableRTC"] || [featureKey isEqualToString:@"disableMedia"])) {
            NSArray *browsers = @[
                @"com.apple.mobilesafari", @"com.apple.SafariViewService",
                @"com.google.chrome.ios", @"org.mozilla.ios.Firefox", 
                @"com.brave.ios.browser", @"com.duckduckgo.mobile.ios"
            ];
            if ([browsers containsObject:self.targetID]) return @YES;
        }
        
        return @NO; 
    }
    
    return rules[featureKey];
}

- (void)setFeatureValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *featureKey = [specifier propertyForKey:@"featureKey"];
    
    if (![AntiDarkSwordAppController isApplicableFeature:featureKey forTarget:self.targetID]) {
        return; 
    }

    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"com.eolnmsuk.antidarkswordprefs"];
    NSString *dictKey = [NSString stringWithFormat:@"TargetRules_%@", self.targetID];
    NSMutableDictionary *rules = [[defaults dictionaryForKey:dictKey] mutableCopy] ?: [NSMutableDictionary dictionary];
    
    rules[featureKey] = value;
    
    if ([featureKey isEqualToString:@"disableJS"]) {
        BOOL isIOS16OrGreater = [[NSProcessInfo processInfo] operatingSystemVersion].majorVersion >= 16;
        if ([value boolValue]) {
            if (isIOS16OrGreater && [AntiDarkSwordAppController isApplicableFeature:@"disableJIT" forTarget:self.targetID]) {
                rules[@"disableJIT"] = @YES;
            } else if (!isIOS16OrGreater && [AntiDarkSwordAppController isApplicableFeature:@"disableJIT15" forTarget:self.targetID]) {
                rules[@"disableJIT15"] = @YES;
            }
        }
        
        [defaults setObject:rules forKey:dictKey];
        [defaults setBool:YES forKey:@"ADSNeedsRespring"];
        [defaults synchronize];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            self->_specifiers = nil;
            [self reloadSpecifiers];
        });
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFSTR("com.eolnmsuk.antidarkswordprefs/saved"), NULL, NULL, YES);
        return;
    }
    
    [defaults setObject:rules forKey:dictKey];
    [defaults setBool:YES forKey:@"ADSNeedsRespring"];
    [defaults synchronize];
    
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFSTR("com.eolnmsuk.antidarkswordprefs/saved"), NULL, NULL, YES);
}
@end
// ==========================================

@implementation AntiDarkSwordPrefsRootListController

- (BOOL)isTargetInstalled:(NSString *)targetID {
    NSArray *coreServices = @[
        @"com.apple.imagent", @"com.apple.mediaserverd", @"com.apple.networkd",
        @"com.apple.apsd", @"com.apple.identityservicesd", @"com.apple.SafariViewService",
        @"com.apple.MailCompositionService", @"com.apple.iMessageAppsViewService",
        @"com.apple.ActivityMessagesApp", @"com.apple.quicklook.QuickLookUIService",
        @"com.apple.QuickLookDaemon", @"com.apple.appstored", @"com.apple.itunesstored",
        @"com.apple.nsurlsessiond", @"com.apple.cfnetwork",
        @"imagent", @"mediaserverd", @"networkd", @"apsd", @"identityservicesd"
    ];
    
    if ([coreServices containsObject:targetID]) {
        return YES;
    }
    
    if (![targetID containsString:@"."] && ![targetID isEqualToString:@"pinterest"]) {
        return YES; 
    }

    @try {
        Class LSAppWorkspace = NSClassFromString(@"LSApplicationWorkspace");
        if (LSAppWorkspace) {
            LSApplicationWorkspace *workspace = [LSAppWorkspace defaultWorkspace];
            if (workspace && [workspace respondsToSelector:@selector(applicationIsInstalled:)]) {
                if ([workspace applicationIsInstalled:targetID]) {
                    return YES;
                }
            }
        }
    } @catch (NSException *e) {}

    @try {
        Class LSAppProxy = NSClassFromString(@"LSApplicationProxy");
        if (LSAppProxy) {
            LSApplicationProxy *proxy = [LSAppProxy applicationProxyForIdentifier:targetID];
            if (proxy && [proxy respondsToSelector:@selector(bundleURL)]) {
                NSURL *bundleURL = [proxy bundleURL];
                if (bundleURL && [[NSFileManager defaultManager] fileExistsAtPath:bundleURL.path]) {
                    return YES;
                }
            }
        }
    } @catch (NSException *e) {}

    return NO;
}

- (NSString *)displayNameForTargetID:(NSString *)targetID {
    NSDictionary *knownNames = @{
        @"com.google.Gmail": @"Gmail",
        @"com.microsoft.Office.Outlook": @"Outlook",
        @"com.tinyspeck.chatlyio": @"Slack",
        @"com.microsoft.skype.teams": @"Microsoft Teams",
        @"com.google.chrome.ios": @"Chrome",
        @"com.brave.ios.browser": @"Brave",
        @"com.tumblr.tumblr": @"Tumblr",
        @"com.yahoo.Aerogram": @"Yahoo Mail",
        @"ch.protonmail.protonmail": @"Proton Mail",
        @"org.whispersystems.signal": @"Signal",
        @"ph.telegra.Telegraph": @"Telegram",
        @"com.facebook.Messenger": @"Messenger",
        @"com.toyopagroup.picaboo": @"Snapchat",
        @"com.tencent.xin": @"WeChat",
        @"com.viber": @"Viber",
        @"jp.naver.line": @"LINE",
        @"net.whatsapp.WhatsApp": @"WhatsApp",
        @"com.hammerandchisel.discord": @"Discord",
        @"com.google.GoogleMobile": @"Google",
        @"org.mozilla.ios.Firefox": @"Firefox",
        @"com.duckduckgo.mobile.ios": @"DuckDuckGo",
        @"pinterest": @"Pinterest",
        @"com.facebook.Facebook": @"Facebook",
        @"com.atebits.Tweetie2": @"X (Twitter)",
        @"com.burbn.instagram": @"Instagram",
        @"com.zhiliaoapp.musically": @"TikTok",
        @"com.linkedin.LinkedIn": @"LinkedIn",
        @"com.reddit.Reddit": @"Reddit",
        @"com.google.ios.youtube": @"YouTube",
        @"tv.twitch": @"Twitch",
        @"com.google.gemini": @"Google Gemini",
        @"com.openai.chat": @"ChatGPT",
        @"com.deepseek.chat": @"DeepSeek",
        @"com.github.stormbreaker.prod": @"GitHub",
        @"org.coolstar.SileoStore": @"Sileo",
        @"xyz.willy.Zebra": @"Zebra",
        @"com.tigisoftware.Filza": @"Filza",
        @"com.apple.Passbook": @"Apple Wallet",
        @"com.squareup.cash": @"Cash App",
        @"net.kortina.labs.Venmo": @"Venmo",
        @"com.yourcompany.PPClient": @"PayPal",
        @"com.robinhood.release.Robinhood": @"Robinhood",
        @"com.vilcsak.bitcoin2": @"Coinbase",
        @"com.sixdays.trust": @"Trust Wallet",
        @"io.metamask.MetaMask": @"MetaMask",
        @"app.phantom.phantom": @"Phantom",
        @"com.chase": @"Chase",
        @"com.bankofamerica.BofAMobileBanking": @"Bank of America",
        @"com.wellsfargo.net.mobilebanking": @"Wells Fargo",
        @"com.citi.citimobile": @"Citi",
        @"com.capitalone.enterprisemobilebanking": @"Capital One",
        @"com.americanexpress.amelia": @"Amex",
        @"com.fidelity.iphone": @"Fidelity",
        @"com.schwab.mobile": @"Charles Schwab",
        @"com.etrade.mobilepro.iphone": @"E*TRADE",
        @"com.discoverfinancial.mobile": @"Discover",
        @"com.usbank.mobilebanking": @"U.S. Bank",
        @"com.monzo.ios": @"Monzo",
        @"com.revolut.iphone": @"Revolut",
        @"com.binance.dev": @"Binance",
        @"com.kraken.invest": @"Kraken",
        @"com.barclays.ios.bmb": @"Barclays",
        @"com.ally.auto": @"Ally",
        @"com.navyfederal.navyfederal.mydata": @"Navy Federal"
    };

    if (knownNames[targetID]) return knownNames[targetID];
    if (![targetID containsString:@"."] && ![targetID isEqualToString:@"pinterest"]) return targetID; 
    
    NSArray *daemons = @[
        @"com.apple.imagent", @"com.apple.mediaserverd",
        @"com.apple.networkd", @"com.apple.apsd", @"com.apple.identityservicesd",
        @"com.apple.SafariViewService", @"com.apple.MailCompositionService",
        @"com.apple.iMessageAppsViewService", @"com.apple.ActivityMessagesApp",
        @"com.apple.quicklook.QuickLookUIService", @"com.apple.QuickLookDaemon",
        @"com.apple.appstored", @"com.apple.itunesstored", @"com.apple.nsurlsessiond",
        @"com.apple.cfnetwork"
    ];
    
    if ([daemons containsObject:targetID]) return targetID;

    @try {
        Class LSAppProxy = NSClassFromString(@"LSApplicationProxy");
        if (LSAppProxy) {
            id proxy = [LSAppProxy applicationProxyForIdentifier:targetID];
            if (proxy && [proxy respondsToSelector:@selector(localizedName)]) {
                NSString *name = [proxy localizedName];
                if (name && name.length > 0) return name;
            }
        }
    } @catch (NSException *e) {}
    
    return targetID;
}

- (UIImage *)iconForTargetID:(NSString *)targetID {
    UIImage *icon = nil;
    
    if ([targetID containsString:@"."] || [targetID isEqualToString:@"pinterest"]) {
        NSArray *daemons = @[
            @"com.apple.imagent", @"com.apple.mediaserverd",
            @"com.apple.networkd", @"com.apple.apsd", @"com.apple.identityservicesd",
            @"com.apple.SafariViewService", @"com.apple.MailCompositionService",
            @"com.apple.iMessageAppsViewService", @"com.apple.ActivityMessagesApp",
            @"com.apple.quicklook.QuickLookUIService", @"com.apple.QuickLookDaemon",
            @"com.apple.appstored", @"com.apple.itunesstored", @"com.apple.nsurlsessiond",
            @"com.apple.cfnetwork",
            @"imagent", @"mediaserverd", @"networkd", @"apsd", @"identityservicesd"
        ];
        
        if (![daemons containsObject:targetID]) {
            @try {
                if ([UIImage respondsToSelector:@selector(_applicationIconImageForBundleIdentifier:format:scale:)]) {
                    icon = [UIImage _applicationIconImageForBundleIdentifier:targetID format:29 scale:[UIScreen mainScreen].scale];
                }
            } @catch (NSException *e) {}
        }
    }
    
    if (!icon) {
        if (@available(iOS 13.0, *)) {
            icon = [UIImage systemImageNamed:@"gearshape.fill"];
            icon = [icon imageWithTintColor:[UIColor systemGrayColor] renderingMode:UIImageRenderingModeAlwaysOriginal];
        }
    }
    
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
    
    BOOL isIOS16OrGreater = [[NSProcessInfo processInfo] operatingSystemVersion].majorVersion >= 16;

    NSArray *browsers = @[
        @"com.apple.mobilesafari", @"com.apple.SafariViewService",
        @"com.google.chrome.ios", @"org.mozilla.ios.Firefox", 
        @"com.brave.ios.browser", @"com.duckduckgo.mobile.ios"
    ];
    
    NSArray *msgAndMail = @[
        @"com.apple.MobileSMS", @"com.apple.mobilemail", @"com.apple.MailCompositionService", 
        @"com.apple.iMessageAppsViewService", @"com.apple.ActivityMessagesApp", 
        @"com.google.Gmail", @"com.microsoft.Office.Outlook", @"com.yahoo.Aerogram", 
        @"ch.protonmail.protonmail", @"org.whispersystems.signal", @"ph.telegra.Telegraph", 
        @"com.facebook.Messenger", @"com.toyopagroup.picaboo", @"com.tinyspeck.chatlyio", 
        @"com.microsoft.skype.teams", @"com.tencent.xin", @"com.viber", @"jp.naver.line", 
        @"net.whatsapp.WhatsApp", @"com.hammerandchisel.discord", @"com.apple.Passbook"
    ];

    NSArray *allProtected = [self autoProtectedItemsForLevel:3];
    NSMutableArray *expandedTargets = [NSMutableArray arrayWithArray:allProtected];
    [expandedTargets removeObject:@"DAEMONS_GROUP"];
    [expandedTargets addObjectsFromArray:@[@"com.apple.imagent", @"imagent", @"mediaserverd", @"networkd", @"apsd", @"identityservicesd"]];

    for (NSString *targetID in expandedTargets) {
        NSString *dictKey = [NSString stringWithFormat:@"TargetRules_%@", targetID];
        
        if (!force && [defaults objectForKey:dictKey]) {
            continue;
        }

        NSMutableDictionary *rules = [NSMutableDictionary dictionary];
        
        rules[@"disableJIT"] = (isIOS16OrGreater && [AntiDarkSwordAppController isApplicableFeature:@"disableJIT" forTarget:targetID]) ? @YES : @NO; 
        rules[@"disableJIT15"] = (!isIOS16OrGreater && [AntiDarkSwordAppController isApplicableFeature:@"disableJIT15" forTarget:targetID]) ? @YES : @NO; 
        rules[@"disableJS"] = (!isIOS16OrGreater && [AntiDarkSwordAppController isApplicableFeature:@"disableJS" forTarget:targetID]) ? @YES : @NO; 
        
        rules[@"disableMedia"] = @NO;
        rules[@"disableRTC"] = @NO;
        rules[@"disableFileAccess"] = @NO;
        rules[@"disableIMessageDL"] = @NO;
        rules[@"spoofUA"] = @NO;
        
        if ([msgAndMail containsObject:targetID]) {
            rules[@"disableMedia"] = [AntiDarkSwordAppController isApplicableFeature:@"disableMedia" forTarget:targetID] ? @YES : @NO;
            rules[@"disableRTC"] = [AntiDarkSwordAppController isApplicableFeature:@"disableRTC" forTarget:targetID] ? @YES : @NO;
            rules[@"disableFileAccess"] = [AntiDarkSwordAppController isApplicableFeature:@"disableFileAccess" forTarget:targetID] ? @YES : @NO;
            rules[@"disableIMessageDL"] = [AntiDarkSwordAppController isApplicableFeature:@"disableIMessageDL" forTarget:targetID] ? @YES : @NO;
            if (![targetID hasPrefix:@"com.apple."]) {
                rules[@"spoofUA"] = (level >= 2) ? @YES : @NO;
            }
        } else if ([browsers containsObject:targetID]) {
            rules[@"spoofUA"] = (level >= 2) ? @YES : @NO;
            
            if (level >= 3) {
                rules[@"disableRTC"] = @YES;
                rules[@"disableMedia"] = @YES;
            }
        } else if ([AntiDarkSwordAppController isDaemonTarget:targetID]) {
            // WebKit mitigations forcefully skipped.
        } else {
            if (![targetID hasPrefix:@"com.apple."]) {
                rules[@"spoofUA"] = (level >= 2) ? @YES : @NO;
            }
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
        @"com.apple.Maps", @"com.apple.weather", @"com.apple.Passbook",
        @"com.apple.SafariViewService", @"com.apple.MailCompositionService",
        @"com.apple.iMessageAppsViewService", @"com.apple.ActivityMessagesApp",
        @"com.apple.quicklook.QuickLookUIService", @"com.apple.QuickLookDaemon"
    ];
    
    NSArray *tier2ThirdParty = @[
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
        @"com.squareup.cash", @"net.kortina.labs.Venmo", @"com.yourcompany.PPClient", 
        @"com.robinhood.release.Robinhood", @"com.vilcsak.bitcoin2", @"com.sixdays.trust", 
        @"io.metamask.MetaMask", @"app.phantom.phantom", @"com.chase", 
        @"com.bankofamerica.BofAMobileBanking", @"com.wellsfargo.net.mobilebanking", 
        @"com.citi.citimobile", @"com.capitalone.enterprisemobilebanking", 
        @"com.americanexpress.amelia", @"com.fidelity.iphone", @"com.schwab.mobile", 
        @"com.etrade.mobilepro.iphone", @"com.discoverfinancial.mobile", @"com.usbank.mobilebanking", 
        @"com.monzo.ios", @"com.revolut.iphone", @"com.binance.dev", @"com.kraken.invest", 
        @"com.barclays.ios.bmb", @"com.ally.auto", @"com.navyfederal.navyfederal.mydata"
    ];
    
    NSArray *sortedTier2 = [tier2ThirdParty sortedArrayUsingComparator:^NSComparisonResult(id a, id b) {
        NSString *nameA = [self displayNameForTargetID:a];
        NSString *nameB = [self displayNameForTargetID:b];
        return [nameA caseInsensitiveCompare:nameB];
    }];

    NSArray *tier2JB = @[
        @"org.coolstar.SileoStore", @"xyz.willy.Zebra", @"com.tigisoftware.Filza"
    ];
    
    if (level >= 3) {
        [items addObject:@"DAEMONS_GROUP"];
    }

    // Then add Tier 1 (Safari, Messages, etc.) underneath it
    [items addObjectsFromArray:tier1];
    
    // Then add Tier 2 and Jailbreak apps
    if (level >= 2) {
        [items addObjectsFromArray:sortedTier2];
        [items addObjectsFromArray:tier2JB];
    }
    
    return items;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reloadSpecifiers];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [super tableView:tableView cellForRowAtIndexPath:indexPath];
    PSSpecifier *spec = [self specifierAtIndexPath:indexPath];

    id ruleTypeObj = [spec propertyForKey:@"ruleType"];
    if (ruleTypeObj != nil) {
        NSString *targetID = [spec propertyForKey:@"targetID"];
        NSInteger ruleType = [ruleTypeObj integerValue];
        BOOL isEnabled = YES;

        NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"com.eolnmsuk.antidarkswordprefs"];

        if (ruleType == 0) {
            if ([targetID isEqualToString:@"DAEMONS_GROUP"]) {
                NSArray *disabled = [defaults arrayForKey:@"disabledPresetRules"] ?: @[];
                NSArray *daemons = @[@"imagent", @"mediaserverd", @"networkd", @"apsd", @"identityservicesd"];
                BOOL anyActive = NO;
                for (NSString *d in daemons) {
                    if (![disabled containsObject:d]) {
                        anyActive = YES;
                        break;
                    }
                }
                isEnabled = anyActive;
            } else {
                NSArray *disabled = [defaults arrayForKey:@"disabledPresetRules"] ?: @[];
                isEnabled = ![disabled containsObject:targetID];
            }
        } else if (ruleType == 2) {
            NSArray *active = [defaults arrayForKey:@"activeCustomDaemonIDs"] ?: [defaults arrayForKey:@"customDaemonIDs"] ?: @[];
            isEnabled = [active containsObject:targetID];
        }

        if (isEnabled) {
            if (@available(iOS 13.0, *)) {
                cell.backgroundColor = [[UIColor systemGreenColor] colorWithAlphaComponent:0.15];
            } else {
                cell.backgroundColor = [UIColor colorWithRed:0.2 green:0.8 blue:0.2 alpha:0.15];
            }
        } else {
            if (@available(iOS 13.0, *)) {
                cell.backgroundColor = [[UIColor systemRedColor] colorWithAlphaComponent:0.15];
            } else {
                cell.backgroundColor = [UIColor colorWithRed:0.8 green:0.2 blue:0.2 alpha:0.15];
            }
        }
    } else {
        if (@available(iOS 13.0, *)) {
            cell.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];
        } else {
            cell.backgroundColor = [UIColor whiteColor];
        }
    }

    return cell;
}

- (NSArray *)specifiers {
    if (!_specifiers) {
        NSMutableArray *specs = [[self loadSpecifiersFromPlistName:@"Root" target:self] mutableCopy];
        NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"com.eolnmsuk.antidarkswordprefs"];
        [defaults synchronize]; 
        
        BOOL isIOS16OrGreater = [[NSProcessInfo processInfo] operatingSystemVersion].majorVersion >= 16;
        BOOL globalJSEnabled = [defaults boolForKey:@"globalDisableJS"];
        
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
        
        NSArray *desiredOrder = @[
            @"globalUASpoofingEnabled",
            @"globalDisableJIT",
            @"globalDisableJIT15",
            @"globalDisableJS",
            @"globalDisableRTC",
            @"globalDisableMedia",
            @"globalDisableIMessageDL",
            @"globalDisableFileAccess"
        ];
        
        NSMutableDictionary *globalSpecsDict = [NSMutableDictionary dictionary];
        NSMutableArray *nonGlobalSpecs = [NSMutableArray array];
        NSUInteger mitigationsGroupIndex = NSNotFound;

        for (int i = 0; i < specs.count; i++) {
            PSSpecifier *s = specs[i];
            NSString *key = [s propertyForKey:@"key"];
            
            if ([[s propertyForKey:@"id"] isEqualToString:@"GlobalMitigationsGroup"]) {
                mitigationsGroupIndex = i;
            }
            
            if ([desiredOrder containsObject:key]) {
                if ([key isEqualToString:@"globalDisableJIT"]) {
                    if (!isIOS16OrGreater || (isIOS16OrGreater && globalJSEnabled)) {
                        [s setProperty:@NO forKey:@"enabled"];
                    }
                }
                if ([key isEqualToString:@"globalDisableJIT15"]) {
                    if (isIOS16OrGreater || (!isIOS16OrGreater && globalJSEnabled)) {
                        [s setProperty:@NO forKey:@"enabled"];
                    }
                }
                
                globalSpecsDict[key] = s;
            } else {
                [nonGlobalSpecs addObject:s];
            }
        }
        
        if (mitigationsGroupIndex != NSNotFound && globalSpecsDict.count > 0) {
            specs = [nonGlobalSpecs mutableCopy];
            NSUInteger insertPoint = [specs indexOfObjectPassingTest:^BOOL(PSSpecifier *obj, NSUInteger idx, BOOL *stop) {
                return [[obj propertyForKey:@"id"] isEqualToString:@"GlobalMitigationsGroup"];
            }] + 1;
            
            for (NSString *key in desiredOrder) {
                if (globalSpecsDict[key]) {
                    [specs insertObject:globalSpecsDict[key] atIndex:insertPoint++];
                }
            }
        }

        for (PSSpecifier *s in specs) {
            if ([[s propertyForKey:@"id"] isEqualToString:@"SelectApps"]) {
                s.detailControllerClass = [AntiDarkSwordAltListController class];
            }
            
            if ([s.identifier isEqualToString:@"PresetRulesGroup"]) {
                NSString *footerText = @"";
                if (autoProtectLevel == 1) footerText = @"Level 1: Protects all native Apple applications, including Safari, Messages, Mail, Notes, Calendar, Wallet, and other built-in iOS apps.";
                else if (autoProtectLevel == 2) footerText = @"Level 2: Expands protection to major 3rd-party web browsers, email clients, messaging platforms, social media apps, package managers, and finance/crypto apps.";
                else if (autoProtectLevel == 3) footerText = @"Level 3: Maximum lockdown.\n\n⚠️ Warning: Level 3 restricts critical background daemons, lower the level if you have any issues.";
                [s setProperty:footerText forKey:@"footerText"];
            }
        }

        NSUInteger insertIndexAuto = [specs indexOfObjectPassingTest:^BOOL(PSSpecifier *obj, NSUInteger idx, BOOL *stop) {
            return [[obj propertyForKey:@"id"] isEqualToString:@"AutoProtectLevelSegment"];
        }];
        
        if (insertIndexAuto != NSNotFound) {
            insertIndexAuto++;
            PSSpecifier *groupSpec = [PSSpecifier preferenceSpecifierNamed:@"Current Preset Rules" target:self set:nil get:nil detail:nil cell:PSGroupCell edit:nil];
            [specs insertObject:groupSpec atIndex:insertIndexAuto++];
            
            NSArray *autoItems = [self autoProtectedItemsForLevel:autoProtectLevel];
            for (NSString *item in autoItems) {
                
                if ([item isEqualToString:@"DAEMONS_GROUP"]) {
                    PSSpecifier *spec = [PSSpecifier preferenceSpecifierNamed:@"Restrict System Daemons" target:self set:nil get:nil detail:[AntiDarkSwordDaemonListController class] cell:PSLinkCell edit:nil];
                    [spec setProperty:@"DAEMONS_GROUP" forKey:@"targetID"];
                    [spec setProperty:@(0) forKey:@"ruleType"];
                    
                    UIImage *icon = nil;
                    if (@available(iOS 13.0, *)) {
                        icon = [UIImage systemImageNamed:@"bolt.shield.fill"];
                        icon = [icon imageWithTintColor:[UIColor systemGrayColor] renderingMode:UIImageRenderingModeAlwaysOriginal];
                    }
                    if (icon) {
                        CGSize newSize = CGSizeMake(23, 23);
                        UIGraphicsBeginImageContextWithOptions(newSize, NO, [UIScreen mainScreen].scale);
                        [icon drawInRect:CGRectMake(0, 0, newSize.width, newSize.height)];
                        UIImage *resizedIcon = UIGraphicsGetImageFromCurrentImageContext();
                        UIGraphicsEndImageContext();
                        [spec setProperty:resizedIcon forKey:@"iconImage"];
                    }
                    
                    [specs insertObject:spec atIndex:insertIndexAuto++];
                    continue;
                }

                BOOL isInstalled = [self isTargetInstalled:item];
                
                if (!isInstalled) {
                    continue; // HIDES CELL COMPLETELY IF UNINSTALLED
                }

                NSString *displayName = [self displayNameForTargetID:item];
                PSSpecifier *spec = [PSSpecifier preferenceSpecifierNamed:displayName target:self set:nil get:nil detail:[AntiDarkSwordAppController class] cell:PSLinkCell edit:nil];
                [spec setProperty:item forKey:@"targetID"];
                [spec setProperty:@(0) forKey:@"ruleType"];
                
                UIImage *icon = [self iconForTargetID:item];
                if (icon) {
                    [spec setProperty:icon forKey:@"iconImage"];
                }
                
                [specs insertObject:spec atIndex:insertIndexAuto++];
            }
        }
        
        NSUInteger insertIndexCustom = [specs indexOfObjectPassingTest:^BOOL(PSSpecifier *obj, NSUInteger idx, BOOL *stop) {
            return [[obj propertyForKey:@"id"] isEqualToString:@"AddCustomIDButton"];
        }];
        
        if (insertIndexCustom != NSNotFound) {
            insertIndexCustom++;
            for (NSString *daemonID in customIDs) {
                NSString *displayName = [self displayNameForTargetID:daemonID];
                PSSpecifier *spec = [PSSpecifier preferenceSpecifierNamed:displayName target:self set:nil get:nil detail:[AntiDarkSwordAppController class] cell:PSLinkCell edit:nil];
                [spec setProperty:daemonID forKey:@"targetID"];
                [spec setProperty:daemonID forKey:@"daemonID"];
                [spec setProperty:@(2) forKey:@"ruleType"]; 
                [spec setProperty:@YES forKey:@"isCustomDaemon"];
                
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

- (void)setGlobalMitigation:(id)value specifier:(PSSpecifier *)specifier {
    BOOL enabled = [value boolValue];
    NSString *key = [specifier propertyForKey:@"key"];
    
    if (enabled) {
        NSString *featureName = [specifier name];
        NSString *msg = [NSString stringWithFormat:@"Enabling '%@' globally applies this mitigation to ALL processes indiscriminately. This may break core functionality across the system and is intended for testing/emergency lockdown only.", featureName];
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Warning" message:msg preferredStyle:UIAlertControllerStyleAlert];
        
        [alert addAction:[UIAlertAction actionWithTitle:@"Enable Globally" style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
            [self setPreferenceValue:value specifier:specifier];
            
            if ([key isEqualToString:@"globalDisableJS"]) {
                BOOL isIOS16OrGreater = [[NSProcessInfo processInfo] operatingSystemVersion].majorVersion >= 16;
                NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"com.eolnmsuk.antidarkswordprefs"];
                
                if (isIOS16OrGreater) {
                    [defaults setBool:YES forKey:@"globalDisableJIT"];
                } else {
                    [defaults setBool:YES forKey:@"globalDisableJIT15"];
                }
                [defaults synchronize];
            }
            
            dispatch_async(dispatch_get_main_queue(), ^{
                self->_specifiers = nil;
                [self reloadSpecifiers];
            });
        }]];
        
        [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:^(UIAlertAction * _Nonnull action) {
            [self reloadSpecifiers]; 
        }]];
        [self presentViewController:alert animated:YES completion:nil];
    } else {
        [self setPreferenceValue:value specifier:specifier];
        
        if ([key isEqualToString:@"globalDisableJS"]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                self->_specifiers = nil;
                [self reloadSpecifiers];
            });
        } else {
            dispatch_async(dispatch_get_main_queue(), ^{
                self->_specifiers = nil;
                [self reloadSpecifiers];
            });
        }
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
