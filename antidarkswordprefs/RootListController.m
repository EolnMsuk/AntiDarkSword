// antidarkswordprefs/RootListController.m
#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <Preferences/PSTableCell.h>
#import <UIKit/UIKit.h>
#import <spawn.h>
#import <sys/types.h>
#import <sys/wait.h>
#import <objc/runtime.h>
#import <dlfcn.h>

#import "../ADSLogging.h"

// ==========================================
// Preprocessor Macros & Inline Helpers
// ==========================================
#define ADS_PREFS_SUITE @"com.eolnmsuk.antidarkswordprefs"
#define ADS_NOTIF_SAVED CFSTR("com.eolnmsuk.antidarkswordprefs/saved")

// Sentinel value used to represent the system-daemon group entry in preset-rules lists.
static NSString * const kADSDaemonsGroupSentinel = @"DAEMONS_GROUP";

// Canonical list of apps that handle rich messaging content and warrant media/RTC/file-access
// blocking. com.apple.Passbook is included for BLASTPASS (PassKit attachment) mitigation.
static NSArray *ads_msg_and_mail_apps(void) {
    static NSArray *list;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        list = @[
            @"com.apple.MobileSMS", @"com.apple.mobilemail", @"com.apple.MailCompositionService",
            @"com.apple.iMessageAppsViewService", @"com.apple.ActivityMessagesApp",
            @"com.google.Gmail", @"com.microsoft.Office.Outlook", @"com.yahoo.Aerogram",
            @"ch.protonmail.protonmail", @"org.whispersystems.signal", @"ph.telegra.Telegraph",
            @"com.facebook.Messenger", @"com.toyopagroup.picaboo", @"com.tinyspeck.chatlyio",
            @"com.microsoft.skype.teams", @"com.tencent.xin", @"com.viber", @"jp.naver.line",
            @"net.whatsapp.WhatsApp", @"com.hammerandchisel.discord", @"com.apple.Passbook"
        ];
    });
    return list;
}

static inline NSUserDefaults *ads_defaults(void) {
    static NSUserDefaults *sharedDefaults = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedDefaults = [[NSUserDefaults alloc] initWithSuiteName:ADS_PREFS_SUITE];
    });
    return sharedDefaults;
}

static inline void ads_post_notification(void) {
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), ADS_NOTIF_SAVED, NULL, NULL, YES);
}

static inline BOOL ads_is_ios16(void) {
    return [[NSProcessInfo processInfo] operatingSystemVersion].majorVersion >= 16;
}

static inline UIColor *ads_color_green(void) {
    if (@available(iOS 13.0, *)) {
        return [[UIColor systemGreenColor] colorWithAlphaComponent:0.15];
    }
    return [UIColor colorWithRed:0.2 green:0.8 blue:0.2 alpha:0.15];
}

static inline UIColor *ads_color_red(void) {
    if (@available(iOS 13.0, *)) {
        return [[UIColor systemRedColor] colorWithAlphaComponent:0.15];
    }
    return [UIColor colorWithRed:0.8 green:0.2 blue:0.2 alpha:0.15];
}

static inline NSString *ads_root_path(NSString *path) {
    // RootHide: jbroot() remaps paths to a per-process preboot prefix.
    // Guard: verify the symbol actually performs a non-trivial remap (jbroot("/") != "/")
    // to avoid false-positive detection on rootless setups that happen to export jbroot
    // as a no-op shim or compatibility stub.
    static void *jbrootFn = NULL;
    static BOOL jbrootIsReal = NO;
    static dispatch_once_t jbrootOnce;
    dispatch_once(&jbrootOnce, ^{
        jbrootFn = dlsym(RTLD_DEFAULT, "jbroot");
        if (jbrootFn) {
            typedef char *(*jbroot_fn)(const char *);
            char *test = ((jbroot_fn)jbrootFn)("/");
            jbrootIsReal = (test != NULL && strcmp(test, "/") != 0);
        }
    });
    if (jbrootIsReal) {
        typedef char *(*jbroot_fn)(const char *);
        char *resolved = ((jbroot_fn)jbrootFn)(path.UTF8String);
        if (resolved) return @(resolved);
    }
    // Rootless: /var/jb prefix.
    if ([[NSFileManager defaultManager] fileExistsAtPath:@"/var/jb/"])
        return [NSString stringWithFormat:@"/var/jb%@", path];
    // Rootful: no prefix.
    return path;
}

// ==========================================
// Internal iOS APIs
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
@property (nonatomic, strong) NSArray *cachedDisabledPresetRules;
@property (nonatomic, strong) NSArray *cachedActiveCustomDaemons;
- (NSArray *)autoProtectedItemsForLevel:(NSInteger)level;
- (void)populateDefaultRulesForLevel:(NSInteger)level force:(BOOL)force;
- (NSString *)displayNameForTargetID:(NSString *)targetID;
- (UIImage *)iconForTargetID:(NSString *)targetID;
- (BOOL)isTargetInstalled:(NSString *)targetID;
@end

// ==========================================
// Credits Sub-Menu
// ==========================================
@interface AntiDarkSwordCreditsController : PSListController
@end

@implementation AntiDarkSwordCreditsController

- (UIImage *)resizeIcon:(UIImage *)image toSize:(CGSize)size {
    if (!image) return nil;
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:size];
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        [image drawInRect:CGRectMake(0, 0, size.width, size.height)];
    }];
}

- (NSArray *)specifiers {
    if (!_specifiers) {
        NSMutableArray *specs = [NSMutableArray array];
        NSBundle *bundle = [NSBundle bundleForClass:[self class]];
        CGSize iconSize = CGSizeMake(29, 29);
        
        PSSpecifier *group = [PSSpecifier preferenceSpecifierNamed:@"Contributors" target:self set:nil get:nil detail:nil cell:PSGroupCell edit:nil];
        [specs addObject:group];
        
        PSSpecifier *eoln = [PSSpecifier preferenceSpecifierNamed:@"EolnMsuk (AntiDarkSword)" target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
        eoln->action = @selector(openDevLink);
        UIImage *rawEoln = [UIImage imageWithContentsOfFile:[bundle pathForResource:@"eoln" ofType:@"png"]];
        if (rawEoln) [eoln setProperty:[self resizeIcon:rawEoln toSize:iconSize] forKey:@"iconImage"];
        [specs addObject:eoln];
        
        PSSpecifier *ghh = [PSSpecifier preferenceSpecifierNamed:@"ghh-jb (CorelliumDecoy)" target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
        ghh->action = @selector(openDev2Link);
        UIImage *rawGhh = [UIImage imageWithContentsOfFile:[bundle pathForResource:@"ghh-jb" ofType:@"png"]];
        if (rawGhh) [ghh setProperty:[self resizeIcon:rawGhh toSize:iconSize] forKey:@"iconImage"];
        [specs addObject:ghh];
        
        _specifiers = [specs copy];
    }
    return _specifiers;
}

- (void)openDevLink {
    NSURL *url = [NSURL URLWithString:@"https://github.com/EolnMsuk/"];
    if ([[UIApplication sharedApplication] canOpenURL:url]) [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
}

- (void)openDev2Link {
    NSURL *url = [NSURL URLWithString:@"https://github.com/ghh-jb"];
    if ([[UIApplication sharedApplication] canOpenURL:url]) [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
}
@end

// ==========================================
// App-Specific Drill-Down
// ==========================================
@interface AntiDarkSwordAppController : PSListController
@property (nonatomic, strong) NSString *targetID;
@property (nonatomic, assign) NSInteger ruleType;
+ (BOOL)isDaemonTarget:(NSString *)targetID;
+ (BOOL)isApplicableFeature:(NSString *)featureKey forTarget:(NSString *)targetID;
- (BOOL)isGlobalOverrideActiveForFeature:(NSString *)featureKey;
@end

// ==========================================
// System Daemon List
// ==========================================
@interface AntiDarkSwordDaemonListController : PSListController
@end

// Maps short process names to their com.apple.* bundle ID counterparts.
// Used to keep both aliases in sync inside disabledPresetRules.
static NSDictionary *ads_daemon_alias_map(void) {
    static NSDictionary *map;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        map = @{
            @"imagent":             @"com.apple.imagent",
            @"IMDPersistenceAgent": @"com.apple.IMDPersistenceAgent",
            @"apsd":                @"com.apple.apsd",
            @"identityservicesd":   @"com.apple.identityservicesd"
        };
    });
    return map;
}

@implementation AntiDarkSwordDaemonListController

- (NSArray *)specifiers {
    if (!_specifiers) {
        NSMutableArray *specs = [NSMutableArray array];
        AntiDarkSwordPrefsRootListController *rootCtrl = [[AntiDarkSwordPrefsRootListController alloc] init];
        NSUserDefaults *defaults = ads_defaults();
        BOOL corelliumEnabled = [defaults boolForKey:@"corelliumDecoyEnabled"];

        // ---- Corellium Honeypot group (MOVED UP) ----
        PSSpecifier *decoyGroup = [PSSpecifier preferenceSpecifierNamed:@"Corellium Honeypot" target:self set:nil get:nil detail:nil cell:PSGroupCell edit:nil];
        [decoyGroup setProperty:@"Spoofs the Corellium environment to cause exploits (like Coruna) to self-abort. All four daemons are re-enabled and locked when this is on" forKey:@"footerText"];
        [specs addObject:decoyGroup];

        PSSpecifier *decoySpec = [PSSpecifier preferenceSpecifierNamed:@"Enable Corellium Honeypot" target:self set:@selector(setCorelliumEnabled:specifier:) get:@selector(getCorelliumEnabled:) detail:nil cell:PSSwitchCell edit:nil];
        [specs addObject:decoySpec];

        // ---- System Daemons group (MOVED DOWN) ----
        PSSpecifier *group = [PSSpecifier preferenceSpecifierNamed:@"System Daemons" target:self set:nil get:nil detail:nil cell:PSGroupCell edit:nil];
        [group setProperty:@"Restricting a daemon bypasses all zero-click mitigations for that process. Disable Corellium Honeypot to unlock." forKey:@"footerText"];
        [specs addObject:group];

        NSArray *daemons = @[@"imagent", @"apsd", @"identityservicesd", @"IMDPersistenceAgent"];
        for (NSString *daemon in daemons) {
            PSSpecifier *spec = [PSSpecifier preferenceSpecifierNamed:[rootCtrl displayNameForTargetID:daemon] target:self set:@selector(setDaemonEnabled:specifier:) get:@selector(getDaemonEnabled:) detail:nil cell:PSSwitchCell edit:nil];
            [spec setProperty:daemon forKey:@"targetID"];

            // Grey out all daemons while Corellium Honeypot is enabled — each must be active
            // for the POSIX spoofing hooks to fire in that daemon's context.
            if (corelliumEnabled) {
                [spec setProperty:@NO forKey:@"enabled"];
            }

            [specs addObject:spec];
        }

        _specifiers = [specs copy];
    }
    return _specifiers;
}

- (id)getDaemonEnabled:(PSSpecifier *)spec {
    NSUserDefaults *defaults = ads_defaults();
    NSArray *disabled = [defaults arrayForKey:@"disabledPresetRules"] ?: @[];
    return @(![disabled containsObject:[spec propertyForKey:@"targetID"]]);
}

- (void)setDaemonEnabled:(id)value specifier:(PSSpecifier *)spec {
    NSUserDefaults *defaults = ads_defaults();
    NSMutableArray *disabled = [[defaults arrayForKey:@"disabledPresetRules"] mutableCopy] ?: [NSMutableArray array];
    NSString *targetID = [spec propertyForKey:@"targetID"];
    NSDictionary *aliasMap = ads_daemon_alias_map();

    if ([value boolValue]) {
        [disabled removeObject:targetID];
        NSString *bundleAlias = aliasMap[targetID];
        if (bundleAlias) [disabled removeObject:bundleAlias];
    } else {
        if (![disabled containsObject:targetID]) [disabled addObject:targetID];
        NSString *bundleAlias = aliasMap[targetID];
        if (bundleAlias && ![disabled containsObject:bundleAlias]) [disabled addObject:bundleAlias];
    }

    [defaults setObject:disabled forKey:@"disabledPresetRules"];
    [defaults setBool:YES forKey:@"ADSNeedsRespring"];
    [defaults setBool:YES forKey:@"ADSPendingDaemonChanges"];
    [defaults synchronize];
    ads_post_notification();
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reloadSpecifiers];
}

- (id)getCorelliumEnabled:(PSSpecifier *)spec {
    NSUserDefaults *defaults = ads_defaults();
    return @([defaults boolForKey:@"corelliumDecoyEnabled"]);
}

- (void)setCorelliumEnabled:(id)value specifier:(PSSpecifier *)spec {
    NSUserDefaults *defaults = ads_defaults();
    BOOL masterEnabled = [defaults boolForKey:@"enabled"];
    BOOL decoyEnabled = [value boolValue];

    [defaults setBool:decoyEnabled forKey:@"corelliumDecoyEnabled"];
    
    // Auto-enable ALL four daemons when Corellium is toggled on.
    // The POSIX spoofing hooks (access/stat/lstat) fire from within each daemon process
    // where globalDecoyEnabled is YES, which requires currentProcessRestricted = YES for
    // that process.  If imagent is disabled but apsd is not, the spoof only works for
    // calls originating from apsd — not from imagent, which is the primary iMessage attack
    // vector.  Re-enabling all four guarantees full coverage regardless of which daemon
    // the exploit payload executes in.
    if (decoyEnabled) {
        NSMutableArray *disabled = [[defaults arrayForKey:@"disabledPresetRules"] mutableCopy] ?: [NSMutableArray array];
        NSDictionary *aliasMap = ads_daemon_alias_map();
        NSArray *daemonShortNames = @[@"imagent", @"apsd", @"identityservicesd", @"IMDPersistenceAgent"];
        BOOL changed = NO;
        for (NSString *shortName in daemonShortNames) {
            if ([disabled containsObject:shortName]) {
                [disabled removeObject:shortName];
                changed = YES;
            }
            NSString *bundleAlias = aliasMap[shortName];
            if (bundleAlias && [disabled containsObject:bundleAlias]) {
                [disabled removeObject:bundleAlias];
                changed = YES;
            }
        }
        if (changed) {
            [defaults setObject:disabled forKey:@"disabledPresetRules"];
            [defaults setBool:YES forKey:@"ADSPendingDaemonChanges"];
        }
    }

    [defaults setBool:YES forKey:@"ADSNeedsRespring"];
    [defaults synchronize];

    pid_t pid;
    NSString *launchctl = ads_root_path(@"/usr/bin/launchctl");
    NSString *plistPath = ads_root_path(@"/Library/LaunchDaemons/c.eolnmsuk.corelliumdecoy.plist");

    const char* unloadArgs[] = {"launchctl", "unload", plistPath.UTF8String, NULL};
    if (posix_spawn(&pid, launchctl.UTF8String, NULL, NULL, (char* const*)unloadArgs, NULL) == 0)
        waitpid(pid, NULL, 0);

    if (masterEnabled && decoyEnabled) {
        const char* loadArgs[] = {"launchctl", "load", plistPath.UTF8String, NULL};
        if (posix_spawn(&pid, launchctl.UTF8String, NULL, NULL, (char* const*)loadArgs, NULL) == 0)
            waitpid(pid, NULL, 0);
    }

    ads_post_notification();
    
    // Reload UI to reflect the greyed-out state of apsd
    dispatch_async(dispatch_get_main_queue(), ^{
        self->_specifiers = nil;
        [self reloadSpecifiers];
    });
}
@end

// ==========================================
// Custom AltList Controller
// ==========================================
@interface ATLApplicationListMultiSelectionController : PSListController
@end

@interface AntiDarkSwordAltListController : ATLApplicationListMultiSelectionController
@property (nonatomic, strong) NSArray *cachedPresetApps;
@property (nonatomic, strong) NSDictionary *cachedRestrictedApps;
@property (nonatomic, strong) NSDictionary *cachedRestrictedAppsLegacy;
@end

@implementation AntiDarkSwordAltListController

- (void)viewDidLoad {
    [super viewDidLoad];
    NSUserDefaults *defaults = ads_defaults();
    NSInteger level = [defaults integerForKey:@"autoProtectLevel"] ?: 1;
    AntiDarkSwordPrefsRootListController *rootCtrl = [[AntiDarkSwordPrefsRootListController alloc] init];
    self.cachedPresetApps = [rootCtrl autoProtectedItemsForLevel:level];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    NSUserDefaults *defaults = ads_defaults();
    self.cachedRestrictedAppsLegacy = [defaults dictionaryForKey:@"restrictedApps"] ?: @{};
    self.cachedRestrictedApps = [defaults dictionaryRepresentation];
    [self reloadSpecifiers];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [super tableView:tableView cellForRowAtIndexPath:indexPath];
    PSSpecifier *spec = [self specifierAtIndexPath:indexPath];
    
    NSString *bundleID = [spec propertyForKey:@"applicationIdentifier"];
    if (!bundleID) {
        NSString *alKey = [spec propertyForKey:@"ALSettingsKey"];
        if ([alKey hasPrefix:@"restrictedApps-"]) bundleID = [alKey substringFromIndex:@"restrictedApps-".length];
    }
    
    if (bundleID) {
        NSArray *presetApps = self.cachedPresetApps ?: @[];
        
        if ([cell respondsToSelector:@selector(control)]) {
            id control = [cell control];
            if ([control isKindOfClass:[UIView class]]) ((UIView *)control).hidden = YES;
        }
        
        cell.accessoryView = nil;
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
        
        BOOL isManualRuleActive = NO;
        NSString *prefKey = [NSString stringWithFormat:@"restrictedApps-%@", bundleID];
        
        if (self.cachedRestrictedApps[prefKey] != nil) {
            isManualRuleActive = [self.cachedRestrictedApps[prefKey] boolValue];
        } else {
            isManualRuleActive = [self.cachedRestrictedAppsLegacy[bundleID] boolValue];
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
            cell.backgroundColor = isManualRuleActive ? ads_color_green() : ads_color_red();
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
        if ([alKey hasPrefix:@"restrictedApps-"]) bundleID = [alKey substringFromIndex:@"restrictedApps-".length];
    }

    if (bundleID) {
        NSArray *presetApps = self.cachedPresetApps ?: @[];
        
        if ([presetApps containsObject:bundleID]) return;

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
// App-Specific Feature Drill-Down
// ==========================================
@implementation AntiDarkSwordAppController

+ (BOOL)isDaemonTarget:(NSString *)targetID {
    if (!targetID) return NO;
    // Explicit allowlist of known daemon IDs.
    NSArray *daemons = @[
        @"com.apple.imagent", @"imagent",
        @"com.apple.apsd", @"apsd",
        @"com.apple.identityservicesd", @"identityservicesd",
        @"com.apple.IMDPersistenceAgent", @"IMDPersistenceAgent"
    ];
    if ([daemons containsObject:targetID]) return YES;
    // A bare process name (no dots, not the known app-style ID "pinterest") is a daemon/process name.
    if (![targetID containsString:@"."] && ![targetID isEqualToString:@"pinterest"]) return YES;
    // Bundle IDs that explicitly contain "daemon" are daemon processes.
    if ([targetID containsString:@"daemon"]) return YES;
    // Note: we intentionally do NOT use a hasSuffix:@"d" heuristic here — it produces
    // false positives (e.g. any bundle ID that simply ends in the letter "d").
    return NO;
}

+ (BOOL)isApplicableFeature:(NSString *)featureKey forTarget:(NSString *)targetID {
    BOOL isDaemon = [self isDaemonTarget:targetID];
    BOOL isMessageApp = [targetID isEqualToString:@"com.apple.MobileSMS"] || 
                        [targetID isEqualToString:@"com.apple.ActivityMessagesApp"] || 
                        [targetID isEqualToString:@"com.apple.iMessageAppsViewService"];

    if ([featureKey isEqualToString:@"disableIMessageDL"]) return isMessageApp;
    
    BOOL isIOS16 = ads_is_ios16();
    if ([featureKey isEqualToString:@"disableJIT"]) return isIOS16 && !isDaemon;
    if ([featureKey isEqualToString:@"disableJIT15"]) return !isIOS16 && !isDaemon;

    if ([featureKey isEqualToString:@"disableJS"] || [featureKey isEqualToString:@"disableRTC"] || 
        [featureKey isEqualToString:@"disableMedia"] || [featureKey isEqualToString:@"disableFileAccess"]) {
        return !isDaemon; 
    }
    if ([featureKey isEqualToString:@"spoofUA"]) return YES; 
    return YES;
}

- (void)setSpecifier:(PSSpecifier *)specifier {
    [super setSpecifier:specifier];
    self.targetID = [specifier propertyForKey:@"targetID"];
    self.ruleType = [[specifier propertyForKey:@"ruleType"] integerValue];
    self.title = [specifier name] ?: self.targetID;
}

- (BOOL)isGlobalOverrideActiveForFeature:(NSString *)featureKey {
    NSUserDefaults *defaults = ads_defaults();
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
        NSUserDefaults *defaults = ads_defaults();
        
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
            @{@"key": @"disableJIT", @"label": @"Disable JIT (iOS 16+)"},
            @{@"key": @"disableJIT15", @"label": @"Disable JIT (Legacy)"},
            @{@"key": @"disableJS", @"label": @"Disable JavaScript ⚠︎"},
            @{@"key": @"disableRTC", @"label": @"Disable WebGL & WebRTC"},
            @{@"key": @"disableMedia", @"label": @"Disable Media Auto-Play"},
            @{@"key": @"disableIMessageDL", @"label": @"Disable Msg Auto-Download"},
            @{@"key": @"disableFileAccess", @"label": @"Disable Local File Access"}
        ];
        
        NSString *dictKey = [NSString stringWithFormat:@"TargetRules_%@", self.targetID];
        NSDictionary *rules = [defaults dictionaryForKey:dictKey];
        BOOL isIOS16 = ads_is_ios16();
        BOOL isJSTurnedOn = NO;
        
        if (rules && rules[@"disableJS"] != nil) {
            isJSTurnedOn = [rules[@"disableJS"] boolValue];
        } else {
            isJSTurnedOn = (!isIOS16 && [AntiDarkSwordAppController isApplicableFeature:@"disableJS" forTarget:self.targetID]);
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
                } else if (isIOS16 && isJSTurnedOn && [featKey isEqualToString:@"disableJIT"]) {
                    [spec setProperty:@NO forKey:@"enabled"];
                } else if (!isIOS16 && isJSTurnedOn && [featKey isEqualToString:@"disableJIT15"]) {
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
    NSUserDefaults *defaults = ads_defaults();
    
    if (self.ruleType == 0) { 
        NSArray *disabled = [defaults arrayForKey:@"disabledPresetRules"] ?: @[];
        return @(![disabled containsObject:self.targetID]);
    } else if (self.ruleType == 1) { 
        NSString *prefKey = [NSString stringWithFormat:@"restrictedApps-%@", self.targetID];
        if ([defaults objectForKey:prefKey]) return @([defaults boolForKey:prefKey]);
        NSDictionary *apps = [defaults dictionaryForKey:@"restrictedApps"];
        return apps[self.targetID] ?: @NO;
    } else { 
        NSArray *active = [defaults arrayForKey:@"activeCustomDaemonIDs"] ?: [defaults arrayForKey:@"customDaemonIDs"] ?: @[];
        return @([active containsObject:self.targetID]);
    }
}

- (void)setMasterEnable:(id)value specifier:(PSSpecifier *)specifier {
    NSUserDefaults *defaults = ads_defaults();
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
        if (enabled && ![active containsObject:self.targetID]) [active addObject:self.targetID];
        else if (!enabled) [active removeObject:self.targetID];
        
        [defaults setObject:active forKey:@"activeCustomDaemonIDs"];
        [defaults setBool:YES forKey:@"ADSPendingDaemonChanges"];
    }
    
    [defaults setBool:YES forKey:@"ADSNeedsRespring"];
    [defaults synchronize];
    ads_post_notification();
    
    dispatch_async(dispatch_get_main_queue(), ^{
        self->_specifiers = nil;
        [self reloadSpecifiers];
    });
}

- (id)getFeatureValue:(PSSpecifier *)specifier {
    NSString *featureKey = [specifier propertyForKey:@"featureKey"];
    if (![AntiDarkSwordAppController isApplicableFeature:featureKey forTarget:self.targetID]) return @NO;
    if ([self isGlobalOverrideActiveForFeature:featureKey]) return @YES;

    NSUserDefaults *defaults = ads_defaults();
    NSString *dictKey = [NSString stringWithFormat:@"TargetRules_%@", self.targetID];
    NSDictionary *rules = [defaults dictionaryForKey:dictKey];
    
    if (!rules || rules[featureKey] == nil) { 
        AntiDarkSwordPrefsRootListController *rootCtrl = [[AntiDarkSwordPrefsRootListController alloc] init];
        NSArray *allProtected = [rootCtrl autoProtectedItemsForLevel:3];
        if (![allProtected containsObject:self.targetID]) return @NO;

        NSInteger level = [defaults integerForKey:@"autoProtectLevel"] ?: 1;
        BOOL isIOS16 = ads_is_ios16();

        if ([featureKey isEqualToString:@"disableJIT"]) return isIOS16 ? @YES : @NO; 
        if ([featureKey isEqualToString:@"disableJIT15"]) return !isIOS16 ? @YES : @NO; 
        if ([featureKey isEqualToString:@"disableJS"]) return isIOS16 ? @NO : @YES; 
        
        if ([featureKey isEqualToString:@"spoofUA"]) {
            if ([AntiDarkSwordAppController isDaemonTarget:self.targetID]) return @NO;
            if ([self.targetID isEqualToString:@"com.apple.mobilesafari"] || [self.targetID isEqualToString:@"com.apple.SafariViewService"]) return @YES;
            if ([self.targetID hasPrefix:@"com.apple."]) return @NO; 
            return (level >= 2) ? @YES : @NO; 
        }
        
        NSArray *msgAndMail = ads_msg_and_mail_apps();
        
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
    if (![AntiDarkSwordAppController isApplicableFeature:featureKey forTarget:self.targetID]) return; 

    NSUserDefaults *defaults = ads_defaults();
    NSString *dictKey = [NSString stringWithFormat:@"TargetRules_%@", self.targetID];
    NSMutableDictionary *rules = [[defaults dictionaryForKey:dictKey] mutableCopy] ?: [NSMutableDictionary dictionary];
    
    rules[featureKey] = value;
    
    if ([featureKey isEqualToString:@"disableJS"]) {
        BOOL isIOS16 = ads_is_ios16();
        if ([value boolValue]) {
            // Disabling JS implies disabling JIT for maximum mitigation coverage.
            if (isIOS16 && [AntiDarkSwordAppController isApplicableFeature:@"disableJIT" forTarget:self.targetID]) {
                rules[@"disableJIT"] = @YES;
            } else if (!isIOS16 && [AntiDarkSwordAppController isApplicableFeature:@"disableJIT15" forTarget:self.targetID]) {
                rules[@"disableJIT15"] = @YES;
            }
        } else {
            // JS re-enabled — clear the JIT flag that was auto-set when JS was disabled.
            rules[@"disableJIT"]   = @NO;
            rules[@"disableJIT15"] = @NO;
        }
        
        [defaults setObject:rules forKey:dictKey];
        [defaults setBool:YES forKey:@"ADSNeedsRespring"];
        [defaults synchronize];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            self->_specifiers = nil;
            [self reloadSpecifiers];
        });
        ads_post_notification();
        return;
    }
    
    [defaults setObject:rules forKey:dictKey];
    [defaults setBool:YES forKey:@"ADSNeedsRespring"];
    [defaults synchronize];
    ads_post_notification();
}
@end

// ==========================================
// Root Controller
// ==========================================
@implementation AntiDarkSwordPrefsRootListController

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    NSUserDefaults *defaults = ads_defaults();
    self.cachedDisabledPresetRules = [defaults arrayForKey:@"disabledPresetRules"] ?: @[];
    self.cachedActiveCustomDaemons = [defaults arrayForKey:@"activeCustomDaemonIDs"] ?: [defaults arrayForKey:@"customDaemonIDs"] ?: @[];
    [self reloadSpecifiers];
}

- (BOOL)isTargetInstalled:(NSString *)targetID {
    NSArray *coreServices = @[
        @"com.apple.imagent", @"com.apple.apsd", @"com.apple.identityservicesd",
        @"com.apple.IMDPersistenceAgent",
        @"com.apple.SafariViewService", @"com.apple.MailCompositionService",
        @"com.apple.iMessageAppsViewService", @"com.apple.ActivityMessagesApp",
        @"com.apple.quicklook.QuickLookUIService", @"com.apple.QuickLookDaemon",
        @"imagent", @"apsd", @"identityservicesd", @"IMDPersistenceAgent"
    ];
    
    if ([coreServices containsObject:targetID]) return YES;
    if (![targetID containsString:@"."] && ![targetID isEqualToString:@"pinterest"]) return YES; 

    @try {
        Class LSAppWorkspace = NSClassFromString(@"LSApplicationWorkspace");
        if (LSAppWorkspace) {
            LSApplicationWorkspace *workspace = [LSAppWorkspace defaultWorkspace];
            if (workspace && [workspace respondsToSelector:@selector(applicationIsInstalled:)]) {
                if ([workspace applicationIsInstalled:targetID]) return YES;
            }
        }
    } @catch (NSException *e) {}

    @try {
        Class LSAppProxy = NSClassFromString(@"LSApplicationProxy");
        if (LSAppProxy) {
            LSApplicationProxy *proxy = [LSAppProxy applicationProxyForIdentifier:targetID];
            if (proxy && [proxy respondsToSelector:@selector(bundleURL)]) {
                NSURL *bundleURL = [proxy bundleURL];
                if (bundleURL && [[NSFileManager defaultManager] fileExistsAtPath:bundleURL.path]) return YES;
            }
        }
    } @catch (NSException *e) {}

    return NO;
}

- (NSString *)displayNameForTargetID:(NSString *)targetID {
    NSDictionary *knownNames = @{
        @"imagent": @"iMessage Agent",
        @"apsd": @"Apple Push Service",
        @"identityservicesd": @"Identity Services",
        @"IMDPersistenceAgent": @"iMessage Persistence Agent",
        @"com.google.Gmail": @"Gmail", @"com.microsoft.Office.Outlook": @"Outlook",
        @"com.tinyspeck.chatlyio": @"Slack", @"com.microsoft.skype.teams": @"Microsoft Teams",
        @"com.google.chrome.ios": @"Chrome", @"com.brave.ios.browser": @"Brave",
        @"com.tumblr.tumblr": @"Tumblr", @"com.yahoo.Aerogram": @"Yahoo Mail",
        @"ch.protonmail.protonmail": @"Proton Mail", @"org.whispersystems.signal": @"Signal",
        @"ph.telegra.Telegraph": @"Telegram", @"com.facebook.Messenger": @"Messenger",
        @"com.toyopagroup.picaboo": @"Snapchat", @"com.tencent.xin": @"WeChat",
        @"com.viber": @"Viber", @"jp.naver.line": @"LINE", @"net.whatsapp.WhatsApp": @"WhatsApp",
        @"com.hammerandchisel.discord": @"Discord", @"com.google.GoogleMobile": @"Google",
        @"org.mozilla.ios.Firefox": @"Firefox", @"com.duckduckgo.mobile.ios": @"DuckDuckGo",
        @"pinterest": @"Pinterest", @"com.facebook.Facebook": @"Facebook",
        @"com.atebits.Tweetie2": @"X (Twitter)", @"com.burbn.instagram": @"Instagram",
        @"com.zhiliaoapp.musically": @"TikTok", @"com.linkedin.LinkedIn": @"LinkedIn",
        @"com.reddit.Reddit": @"Reddit", @"com.google.ios.youtube": @"YouTube",
        @"tv.twitch": @"Twitch", @"com.google.gemini": @"Google Gemini",
        @"com.openai.chat": @"ChatGPT", @"com.deepseek.chat": @"DeepSeek",
        @"com.github.stormbreaker.prod": @"GitHub", @"org.coolstar.SileoStore": @"Sileo",
        @"xyz.willy.Zebra": @"Zebra", @"com.tigisoftware.Filza": @"Filza",
        @"com.apple.Passbook": @"Apple Wallet", @"com.squareup.cash": @"Cash App",
        @"net.kortina.labs.Venmo": @"Venmo", @"com.yourcompany.PPClient": @"PayPal",
        @"com.robinhood.release.Robinhood": @"Robinhood", @"com.vilcsak.bitcoin2": @"Coinbase",
        @"com.sixdays.trust": @"Trust Wallet", @"io.metamask.MetaMask": @"MetaMask",
        @"app.phantom.phantom": @"Phantom", @"com.chase": @"Chase",
        @"com.bankofamerica.BofAMobileBanking": @"Bank of America", @"com.wellsfargo.net.mobilebanking": @"Wells Fargo",
        @"com.citi.citimobile": @"Citi", @"com.capitalone.enterprisemobilebanking": @"Capital One",
        @"com.americanexpress.amelia": @"Amex", @"com.fidelity.iphone": @"Fidelity",
        @"com.schwab.mobile": @"Charles Schwab", @"com.etrade.mobilepro.iphone": @"E*TRADE",
        @"com.discoverfinancial.mobile": @"Discover", @"com.usbank.mobilebanking": @"U.S. Bank",
        @"com.monzo.ios": @"Monzo", @"com.revolut.iphone": @"Revolut",
        @"com.binance.dev": @"Binance", @"com.kraken.invest": @"Kraken",
        @"com.barclays.ios.bmb": @"Barclays", @"com.ally.auto": @"Ally",
        @"com.navyfederal.navyfederal.mydata": @"Navy Federal", @"com.1debit.ChimeProdApp": @"Chime"
    };

    if (knownNames[targetID]) return knownNames[targetID];
    if (![targetID containsString:@"."] && ![targetID isEqualToString:@"pinterest"]) return targetID; 
    
    NSArray *daemons = @[
        @"com.apple.imagent", @"com.apple.apsd", @"com.apple.identityservicesd",
        @"com.apple.IMDPersistenceAgent",
        @"com.apple.SafariViewService", @"com.apple.MailCompositionService",
        @"com.apple.iMessageAppsViewService", @"com.apple.ActivityMessagesApp",
        @"com.apple.quicklook.QuickLookUIService", @"com.apple.QuickLookDaemon"
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
            @"com.apple.imagent", @"com.apple.apsd", @"com.apple.identityservicesd",
            @"com.apple.IMDPersistenceAgent",
            @"com.apple.SafariViewService", @"com.apple.MailCompositionService",
            @"com.apple.iMessageAppsViewService", @"com.apple.ActivityMessagesApp",
            @"com.apple.quicklook.QuickLookUIService", @"com.apple.QuickLookDaemon",
            @"imagent", @"apsd", @"identityservicesd", @"IMDPersistenceAgent"
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
        UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:newSize];
        return [renderer imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
            [icon drawInRect:CGRectMake(0, 0, newSize.width, newSize.height)];
        }];
    }

    return nil;
}

- (void)populateDefaultRulesForLevel:(NSInteger)level force:(BOOL)force {
    NSUserDefaults *defaults = ads_defaults();
    if (!force && [defaults boolForKey:@"hasInitializedDefaultRules"]) return;
    
    BOOL isIOS16 = ads_is_ios16();

    NSArray *browsers = @[
        @"com.apple.mobilesafari", @"com.apple.SafariViewService",
        @"com.google.chrome.ios", @"org.mozilla.ios.Firefox", 
        @"com.brave.ios.browser", @"com.duckduckgo.mobile.ios"
    ];
    
    NSArray *msgAndMail = ads_msg_and_mail_apps();

    NSArray *allProtected = [self autoProtectedItemsForLevel:3];
    NSMutableArray *expandedTargets = [NSMutableArray arrayWithArray:allProtected];
    [expandedTargets removeObject:kADSDaemonsGroupSentinel];
    [expandedTargets addObjectsFromArray:@[
        @"com.apple.imagent",           @"imagent",
        @"com.apple.apsd",              @"apsd",
        @"com.apple.identityservicesd", @"identityservicesd",
        @"com.apple.IMDPersistenceAgent", @"IMDPersistenceAgent"
    ]];

    for (NSString *targetID in expandedTargets) {
        NSString *dictKey = [NSString stringWithFormat:@"TargetRules_%@", targetID];
        if (!force && [defaults objectForKey:dictKey]) continue;

        NSMutableDictionary *rules = [NSMutableDictionary dictionary];
        
        rules[@"disableJIT"] = (isIOS16 && [AntiDarkSwordAppController isApplicableFeature:@"disableJIT" forTarget:targetID]) ? @YES : @NO; 
        rules[@"disableJIT15"] = (!isIOS16 && [AntiDarkSwordAppController isApplicableFeature:@"disableJIT15" forTarget:targetID]) ? @YES : @NO; 
        rules[@"disableJS"] = (!isIOS16 && [AntiDarkSwordAppController isApplicableFeature:@"disableJS" forTarget:targetID]) ? @YES : @NO; 
        
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
            if (![targetID hasPrefix:@"com.apple."]) rules[@"spoofUA"] = (level >= 2) ? @YES : @NO;
        } else if ([browsers containsObject:targetID]) {
            if ([targetID isEqualToString:@"com.apple.mobilesafari"] || [targetID isEqualToString:@"com.apple.SafariViewService"]) {
                rules[@"spoofUA"] = @YES;
            } else {
                rules[@"spoofUA"] = (level >= 2) ? @YES : @NO;
            }
            if (level >= 3) {
                rules[@"disableRTC"] = @YES;
                rules[@"disableMedia"] = @YES;
            }
        } else if (![AntiDarkSwordAppController isDaemonTarget:targetID]) {
            if (![targetID hasPrefix:@"com.apple."]) rules[@"spoofUA"] = (level >= 2) ? @YES : @NO;
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
        @"com.apple.mobilenotes", @"com.apple.iBooks", @"com.apple.news", 
        @"com.apple.podcasts", @"com.apple.stocks", 
        @"com.apple.SafariViewService", @"com.apple.MailCompositionService",
        @"com.apple.iMessageAppsViewService", @"com.apple.ActivityMessagesApp",
        @"com.apple.quicklook.QuickLookUIService", @"com.apple.QuickLookDaemon"
    ];
    
    NSArray *tier2ThirdParty = @[
        @"com.google.Gmail", @"com.microsoft.Office.Outlook", @"com.yahoo.Aerogram", @"ch.protonmail.protonmail",
        @"org.whispersystems.signal", @"ph.telegra.Telegraph", @"com.facebook.Messenger", 
        @"com.toyopagroup.picaboo", @"com.tinyspeck.chatlyio", @"com.microsoft.skype.teams", 
        @"com.tencent.xin", @"com.viber", @"jp.naver.line", @"net.whatsapp.WhatsApp", 
        @"com.hammerandchisel.discord", @"com.google.GoogleMobile", @"com.google.chrome.ios", 
        @"org.mozilla.ios.Firefox", @"com.brave.ios.browser", @"com.duckduckgo.mobile.ios",
        @"pinterest", @"com.tumblr.tumblr", @"com.facebook.Facebook", @"com.atebits.Tweetie2", 
        @"com.burbn.instagram", @"com.zhiliaoapp.musically", @"com.linkedin.LinkedIn", 
        @"com.reddit.Reddit", @"com.google.ios.youtube", @"tv.twitch", @"com.google.gemini", 
        @"com.openai.chat", @"com.deepseek.chat", @"com.github.stormbreaker.prod",
        @"com.squareup.cash", @"net.kortina.labs.Venmo", @"com.yourcompany.PPClient", 
        @"com.robinhood.release.Robinhood", @"com.vilcsak.bitcoin2", @"com.sixdays.trust", 
        @"io.metamask.MetaMask", @"app.phantom.phantom", @"com.chase", 
        @"com.bankofamerica.BofAMobileBanking", @"com.wellsfargo.net.mobilebanking", 
        @"com.citi.citimobile", @"com.capitalone.enterprisemobilebanking", 
        @"com.americanexpress.amelia", @"com.fidelity.iphone", @"com.schwab.mobile", 
        @"com.etrade.mobilepro.iphone", @"com.discoverfinancial.mobile", @"com.usbank.mobilebanking", 
        @"com.monzo.ios", @"com.revolut.iphone", @"com.binance.dev", @"com.kraken.invest", 
        @"com.barclays.ios.bmb", @"com.ally.auto", @"com.navyfederal.navyfederal.mydata", @"com.1debit.ChimeProdApp"
    ];
    
    NSArray *sortedTier2 = [tier2ThirdParty sortedArrayUsingComparator:^NSComparisonResult(id a, id b) {
        NSString *nameA = [self displayNameForTargetID:a];
        NSString *nameB = [self displayNameForTargetID:b];
        return [nameA caseInsensitiveCompare:nameB];
    }];

    NSArray *tier2JB = @[ @"org.coolstar.SileoStore", @"xyz.willy.Zebra", @"com.tigisoftware.Filza" ];
    
    if (level >= 3) [items addObject:kADSDaemonsGroupSentinel];
    [items addObjectsFromArray:tier1];
    
    if (level >= 2) {
        [items addObjectsFromArray:sortedTier2];
        [items addObjectsFromArray:tier2JB];
    }
    
    return items;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [super tableView:tableView cellForRowAtIndexPath:indexPath];
    PSSpecifier *spec = [self specifierAtIndexPath:indexPath];

    if (spec->action == @selector(resetToDefaults)) {
        if (@available(iOS 13.0, *)) {
            cell.textLabel.textColor = [UIColor systemRedColor];
        } else {
            cell.textLabel.textColor = [UIColor redColor];
        }
    }

    if ([[spec propertyForKey:@"key"] isEqualToString:@"enabled"]) {
        if ([cell respondsToSelector:@selector(control)]) {
            UISwitch *toggle = (UISwitch *)[cell control];
            if ([toggle isKindOfClass:[UISwitch class]]) {
                if (@available(iOS 13.0, *)) toggle.backgroundColor = [UIColor systemRedColor];
                else toggle.backgroundColor = [UIColor redColor];
                toggle.layer.cornerRadius = 15.5; 
            }
        }
    }

    id ruleTypeObj = [spec propertyForKey:@"ruleType"];
    if (ruleTypeObj != nil) {
        NSString *targetID = [spec propertyForKey:@"targetID"];
        NSInteger ruleType = [ruleTypeObj integerValue];
        BOOL isEnabled = YES;

        if (ruleType == 0) {
            if ([targetID isEqualToString:kADSDaemonsGroupSentinel]) {
                NSArray *disabled = self.cachedDisabledPresetRules ?: @[];
                NSArray *daemons = @[@"imagent", @"apsd", @"identityservicesd", @"IMDPersistenceAgent"];
                BOOL anyActive = NO;
                for (NSString *d in daemons) {
                    if (![disabled containsObject:d]) {
                        anyActive = YES;
                        break;
                    }
                }
                isEnabled = anyActive;
            } else {
                NSArray *disabled = self.cachedDisabledPresetRules ?: @[];
                isEnabled = ![disabled containsObject:targetID];
            }
        } else if (ruleType == 2) {
            NSArray *active = self.cachedActiveCustomDaemons ?: @[];
            isEnabled = [active containsObject:targetID];
        }

        cell.backgroundColor = isEnabled ? ads_color_green() : ads_color_red();
    } else {
        if (@available(iOS 13.0, *)) cell.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];
        else cell.backgroundColor = [UIColor whiteColor];
    }

    return cell;
}

- (NSArray *)specifiers {
    if (!_specifiers) {
        NSMutableArray *specs = [[self loadSpecifiersFromPlistName:@"Root" target:self] mutableCopy];
        NSUserDefaults *defaults = ads_defaults();
        
        BOOL isIOS16 = ads_is_ios16();
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
            @"globalUASpoofingEnabled", @"globalDisableJIT", @"globalDisableJIT15",
            @"globalDisableJS", @"globalDisableRTC", @"globalDisableMedia",
            @"globalDisableIMessageDL", @"globalDisableFileAccess"
        ];
        
        NSMutableDictionary *globalSpecsDict = [NSMutableDictionary dictionary];
        NSMutableArray *nonGlobalSpecs = [NSMutableArray array];
        NSUInteger mitigationsGroupIndex = NSNotFound;

        for (int i = 0; i < specs.count; i++) {
            PSSpecifier *s = specs[i];
            NSString *key = [s propertyForKey:@"key"];
            
            if ([[s propertyForKey:@"id"] isEqualToString:@"GlobalMitigationsGroup"]) mitigationsGroupIndex = i;
            
            if ([desiredOrder containsObject:key]) {
                if ([key isEqualToString:@"globalDisableJIT"]) {
                    if (!isIOS16 || (isIOS16 && globalJSEnabled)) [s setProperty:@NO forKey:@"enabled"];
                }
                if ([key isEqualToString:@"globalDisableJIT15"]) {
                    if (isIOS16 || (!isIOS16 && globalJSEnabled)) [s setProperty:@NO forKey:@"enabled"];
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
                if (globalSpecsDict[key]) [specs insertObject:globalSpecsDict[key] atIndex:insertPoint++];
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
                else if (autoProtectLevel == 3) footerText = @"Level 3: ⚠️ Maximum lockdown. Restricts system background daemons.";
                [s setProperty:footerText forKey:@"footerText"];
            }
            
            if ([[s propertyForKey:@"id"] isEqualToString:@"FooterGroup"]) {
                NSString *osVersion = [[UIDevice currentDevice] systemVersion];
                NSBundle *bundle = [NSBundle bundleForClass:[self class]];
                NSString *version = [bundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"4.2.9";
                
                NSString *jbType = @"Rootless";
                if (access("/Library/MobileSubstrate/DynamicLibraries", F_OK) == 0) jbType = @"Rootful";
                if (dlsym(RTLD_DEFAULT, "jbroot")) jbType = @"Roothide";
                
                NSString *footerString = [NSString stringWithFormat:@"AntiDarkSword v%@ (iOS %@ %@)", version, osVersion, jbType];
                [s setProperty:footerString forKey:@"footerText"];
                [s setProperty:@(1) forKey:@"footerAlignment"]; 
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
                if ([item isEqualToString:kADSDaemonsGroupSentinel]) {
                    PSSpecifier *spec = [PSSpecifier preferenceSpecifierNamed:@"Restrict System Daemons" target:self set:nil get:nil detail:[AntiDarkSwordDaemonListController class] cell:PSLinkCell edit:nil];
                    [spec setProperty:kADSDaemonsGroupSentinel forKey:@"targetID"];
                    [spec setProperty:@(0) forKey:@"ruleType"];
                    
                    UIImage *icon = nil;
                    if (@available(iOS 13.0, *)) {
                        icon = [UIImage systemImageNamed:@"bolt.shield.fill"];
                        icon = [icon imageWithTintColor:[UIColor systemGrayColor] renderingMode:UIImageRenderingModeAlwaysOriginal];
                    }
                    if (icon) {
                        CGSize newSize = CGSizeMake(23, 23);
                        UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:newSize];
                        UIImage *resizedIcon = [renderer imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
                            [icon drawInRect:CGRectMake(0, 0, newSize.width, newSize.height)];
                        }];
                        [spec setProperty:resizedIcon forKey:@"iconImage"];
                    }
                    [specs insertObject:spec atIndex:insertIndexAuto++];
                    continue;
                }

                if (![self isTargetInstalled:item]) continue; 

                NSString *displayName = [self displayNameForTargetID:item];
                PSSpecifier *spec = [PSSpecifier preferenceSpecifierNamed:displayName target:self set:nil get:nil detail:[AntiDarkSwordAppController class] cell:PSLinkCell edit:nil];
                [spec setProperty:item forKey:@"targetID"];
                [spec setProperty:@(0) forKey:@"ruleType"];
                
                UIImage *icon = [self iconForTargetID:item];
                if (icon) [spec setProperty:icon forKey:@"iconImage"];
                
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
                if (icon) [spec setProperty:icon forKey:@"iconImage"];
                
                [specs insertObject:spec atIndex:insertIndexCustom++];
            }
        }
        
        // Attack counter section — inserted before InfoGroup
        NSUInteger infoIdx = [specs indexOfObjectPassingTest:^BOOL(PSSpecifier *obj, NSUInteger idx, BOOL *stop) {
            return [[obj propertyForKey:@"id"] isEqualToString:@"InfoGroup"];
        }];

        if (infoIdx != NSNotFound) {
            BOOL showCounter = [defaults boolForKey:@"countersEnabled"];
            NSInteger probeCount = [defaults integerForKey:@"corelliumProbeCount"];

            PSSpecifier *counterGroup = [PSSpecifier preferenceSpecifierNamed:@"Attack Statistics" target:self set:nil get:nil detail:nil cell:PSGroupCell edit:nil];
            [counterGroup setProperty:@"Counts Corellium environment probe attempts detected in system daemons. Requires Level 3 with Corellium Honeypot enabled." forKey:@"footerText"];
            [specs insertObject:counterGroup atIndex:infoIdx++];

            PSSpecifier *counterToggle = [PSSpecifier preferenceSpecifierNamed:@"Enable Attack Counter"
                target:self
                set:@selector(setCountersEnabled:specifier:)
                get:@selector(getCountersEnabled:)
                detail:nil cell:PSSwitchCell edit:nil];
            [specs insertObject:counterToggle atIndex:infoIdx++];

            if (showCounter) {
                NSString *countLabel = (probeCount == 0)
                    ? @"Corellium Probes Detected: None"
                    : [NSString stringWithFormat:@"Corellium Probes Detected: %ld", (long)probeCount];
                PSSpecifier *countCell = [PSSpecifier preferenceSpecifierNamed:countLabel target:self set:nil get:nil detail:nil cell:PSStaticTextCell edit:nil];
                [specs insertObject:countCell atIndex:infoIdx++];

                PSSpecifier *resetBtn = [PSSpecifier preferenceSpecifierNamed:@"Reset Counter" target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
                resetBtn->action = @selector(resetProbeCounter);
                [specs insertObject:resetBtn atIndex:infoIdx++];
            }
        }

        // Mitigation Shortcut section — inserted right after Attack Statistics, before Info.
        if (infoIdx != NSNotFound) {
            PSSpecifier *shortcutGroup = [PSSpecifier preferenceSpecifierNamed:@"Mitigation Shortcut" target:self set:nil get:nil detail:nil cell:PSGroupCell edit:nil];
            [shortcutGroup setProperty:@"Three-finger double-tap to access the in-app protection overlay. Only activates when Enable Protection is also on." forKey:@"footerText"];
            [specs insertObject:shortcutGroup atIndex:infoIdx++];

            PSSpecifier *shortcutToggle = [PSSpecifier preferenceSpecifierNamed:@"Mitigation Shortcut"
                target:self
                set:@selector(setMitigationShortcut:specifier:)
                get:@selector(getMitigationShortcut:)
                detail:nil cell:PSSwitchCell edit:nil];
            [specs insertObject:shortcutToggle atIndex:infoIdx++];
        }

        _specifiers = [specs copy];
    }
    return _specifiers;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    NSUserDefaults *defaults = ads_defaults();
    NSInteger currentLevel = [defaults objectForKey:@"autoProtectLevel"] ? [defaults integerForKey:@"autoProtectLevel"] : 1;
    [self populateDefaultRulesForLevel:currentLevel force:NO];
    
    UIBarButtonItem *saveButton = [[UIBarButtonItem alloc] initWithTitle:@"Save" style:UIBarButtonItemStyleDone target:self action:@selector(savePrompt)];
    self.navigationItem.rightBarButtonItem = saveButton;
    
    BOOL isEnabled = [defaults boolForKey:@"enabled"];
    BOOL needsRespring = [defaults boolForKey:@"ADSNeedsRespring"];
    BOOL needsReboot = [defaults boolForKey:@"ADSPendingDaemonChanges"];
    
    saveButton.enabled = needsRespring || (isEnabled && needsReboot);
    
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge const void *)(self), (CFNotificationCallback)PrefsChangedNotification, ADS_NOTIF_SAVED, NULL, CFNotificationSuspensionBehaviorCoalesce);
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge const void *)(self), (CFNotificationCallback)ProbeCounterNotification, CFSTR("com.eolnmsuk.antidarkswordprefs/counter"), NULL, CFNotificationSuspensionBehaviorCoalesce);

    [self setupHeaderView];
}

- (void)setupHeaderView {
    NSBundle *bundle = [NSBundle bundleForClass:[self class]];
    NSString *imagePath = [bundle pathForResource:@"banner" ofType:@"png"];
    UIImage *bannerImage = [UIImage imageWithContentsOfFile:imagePath];
    
    if (bannerImage) {
        CGFloat screenWidth = [UIScreen mainScreen].bounds.size.width;
        CGFloat aspect = bannerImage.size.height / bannerImage.size.width;
        CGFloat height = screenWidth * aspect;
        
        UIView *headerView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, screenWidth, height)];
        UIImageView *imageView = [[UIImageView alloc] initWithFrame:headerView.bounds];
        imageView.image = bannerImage;
        imageView.contentMode = UIViewContentModeScaleAspectFill;
        imageView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        imageView.clipsToBounds = YES;
        
        [headerView addSubview:imageView];
        self.table.tableHeaderView = headerView;
    }
}

- (void)dealloc {
    CFNotificationCenterRemoveObserver(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge const void *)(self), ADS_NOTIF_SAVED, NULL);
    CFNotificationCenterRemoveObserver(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge const void *)(self), CFSTR("com.eolnmsuk.antidarkswordprefs/counter"), NULL);
}

static void PrefsChangedNotification(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    AntiDarkSwordPrefsRootListController *controller = (__bridge AntiDarkSwordPrefsRootListController *)observer;
    if (controller) {
        NSUserDefaults *defaults = ads_defaults();
        BOOL isEnabled = [defaults boolForKey:@"enabled"];
        BOOL needsRespring = [defaults boolForKey:@"ADSNeedsRespring"];
        BOOL needsReboot = [defaults boolForKey:@"ADSPendingDaemonChanges"];

        dispatch_async(dispatch_get_main_queue(), ^{
            controller.navigationItem.rightBarButtonItem.enabled = needsRespring || (isEnabled && needsReboot);
        });
    }
}

static void ProbeCounterNotification(CFNotificationCenterRef center __unused, void *observer,
                                     CFStringRef name __unused, const void *object __unused,
                                     CFDictionaryRef userInfo __unused) {
    AntiDarkSwordPrefsRootListController *controller = (__bridge AntiDarkSwordPrefsRootListController *)observer;
    if (controller) {
        dispatch_async(dispatch_get_main_queue(), ^{
            controller->_specifiers = nil;
            [controller reloadSpecifiers];
        });
    }
}

- (void)flagSaveRequirement {
    NSUserDefaults *defaults = ads_defaults();
    [defaults setBool:YES forKey:@"ADSNeedsRespring"];
    [defaults synchronize];
    
    BOOL isEnabled = [defaults boolForKey:@"enabled"];
    BOOL needsRespring = [defaults boolForKey:@"ADSNeedsRespring"];
    BOOL needsReboot = [defaults boolForKey:@"ADSPendingDaemonChanges"];
    self.navigationItem.rightBarButtonItem.enabled = needsRespring || (isEnabled && needsReboot);
}


- (void)setEnableProtection:(id)value specifier:(PSSpecifier *)specifier {
    [self setPreferenceValue:value specifier:specifier];
    
    NSUserDefaults *defaults = ads_defaults();
    NSInteger level = [defaults integerForKey:@"autoProtectLevel"];
    NSArray *customDaemons = [defaults arrayForKey:@"activeCustomDaemonIDs"] ?: @[];
    BOOL masterEnabled = [value boolValue];
    BOOL decoyEnabled = [defaults boolForKey:@"corelliumDecoyEnabled"];
    
    pid_t pid;
    NSString *launchctl = ads_root_path(@"/usr/bin/launchctl");
    NSString *plistPath = ads_root_path(@"/Library/LaunchDaemons/c.eolnmsuk.corelliumdecoy.plist");
    
    const char* unloadArgs[] = {"launchctl", "unload", plistPath.UTF8String, NULL};
    if (posix_spawn(&pid, launchctl.UTF8String, NULL, NULL, (char* const*)unloadArgs, NULL) == 0)
        waitpid(pid, NULL, 0);

    if (masterEnabled && decoyEnabled) {
        const char* loadArgs[] = {"launchctl", "load", plistPath.UTF8String, NULL};
        if (posix_spawn(&pid, launchctl.UTF8String, NULL, NULL, (char* const*)loadArgs, NULL) == 0)
            waitpid(pid, NULL, 0);
    }

    if (level >= 3 || customDaemons.count > 0) {
        [defaults setBool:YES forKey:@"ADSPendingDaemonChanges"];
        [defaults synchronize];
    }
    
    [self savePrompt];
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    NSUserDefaults *defaults = ads_defaults();

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
        // Reload UI to show/hide the custom UA text field — do not auto-enable
        // the master switch; the user's enabled/disabled choice is intentional.
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
                BOOL isIOS16 = ads_is_ios16();
                NSUserDefaults *defaults = ads_defaults();
                if (isIOS16) [defaults setBool:YES forKey:@"globalDisableJIT"];
                else [defaults setBool:YES forKey:@"globalDisableJIT15"];
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
        // globalDisableJS turned off — clear the JIT flag that was auto-set when it was enabled.
        if ([key isEqualToString:@"globalDisableJS"]) {
            NSUserDefaults *defaults = ads_defaults();
            [defaults setBool:NO forKey:@"globalDisableJIT"];
            [defaults setBool:NO forKey:@"globalDisableJIT15"];
            [defaults synchronize];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            self->_specifiers = nil;
            [self reloadSpecifiers];
        });
    }
}


- (void)setAutoProtectLevel:(id)value specifier:(PSSpecifier*)specifier {
    NSUserDefaults *defaults = ads_defaults();
    NSInteger oldLevel = [defaults integerForKey:@"autoProtectLevel"];
    NSInteger newLevel = [value integerValue];
    
    [defaults setObject:value forKey:@"autoProtectLevel"];
    if (oldLevel != newLevel) [self populateDefaultRulesForLevel:newLevel force:NO];
    
    if (oldLevel >= 3 || newLevel >= 3) {
        [defaults setBool:YES forKey:@"ADSPendingDaemonChanges"];
    }
    
    if (newLevel >= 3 && ![defaults boolForKey:@"corelliumDecoyEnabled"]) {
        [defaults setBool:YES forKey:@"corelliumDecoyEnabled"];

        // Same logic as setCorelliumEnabled:specifier: — ensure all four daemons are
        // active so the POSIX spoofing hooks fire in every daemon context.  Without this,
        // a user who had previously disabled daemons, dropped to Level 2, then returned
        // to Level 3 would have Corellium re-enabled but the daemons still disabled,
        // leaving the spoofing hooks inactive.
        NSDictionary *aliasMap = ads_daemon_alias_map();
        NSArray *daemonShortNames = @[@"imagent", @"apsd", @"identityservicesd", @"IMDPersistenceAgent"];
        NSMutableArray *disabled = [[defaults arrayForKey:@"disabledPresetRules"] mutableCopy] ?: [NSMutableArray array];
        BOOL daemonsChanged = NO;
        for (NSString *shortName in daemonShortNames) {
            if ([disabled containsObject:shortName]) { [disabled removeObject:shortName]; daemonsChanged = YES; }
            NSString *bundleAlias = aliasMap[shortName];
            if (bundleAlias && [disabled containsObject:bundleAlias]) { [disabled removeObject:bundleAlias]; daemonsChanged = YES; }
        }
        if (daemonsChanged) [defaults setObject:disabled forKey:@"disabledPresetRules"];

        if ([defaults boolForKey:@"enabled"]) {
            pid_t pid;
            NSString *launchctl = ads_root_path(@"/usr/bin/launchctl");
            NSString *plistPath = ads_root_path(@"/Library/LaunchDaemons/c.eolnmsuk.corelliumdecoy.plist");
            const char* loadArgs[] = {"launchctl", "load", plistPath.UTF8String, NULL};
            if (posix_spawn(&pid, launchctl.UTF8String, NULL, NULL, (char* const*)loadArgs, NULL) == 0)
                waitpid(pid, NULL, 0);
        }
    } else if (newLevel < 3 && [defaults boolForKey:@"corelliumDecoyEnabled"]) {
        [defaults setBool:NO forKey:@"corelliumDecoyEnabled"];
        pid_t pid;
        NSString *launchctl = ads_root_path(@"/usr/bin/launchctl");
        NSString *plistPath = ads_root_path(@"/Library/LaunchDaemons/c.eolnmsuk.corelliumdecoy.plist");
        const char *unloadArgs[] = {"launchctl", "unload", plistPath.UTF8String, NULL};
        if (posix_spawn(&pid, launchctl.UTF8String, NULL, NULL, (char* const*)unloadArgs, NULL) == 0)
            waitpid(pid, NULL, 0);
    }

    [defaults synchronize];
    [self flagSaveRequirement];
    ads_post_notification();

    dispatch_async(dispatch_get_main_queue(), ^{
        self->_specifiers = nil;
        [self reloadSpecifiers];
    });
}

- (void)addCustomID {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Add Custom ID" message:@"Enter bundle IDs or process names (comma-separated)" preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
        textField.placeholder = @"com.apple.imagent, apsd";
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Add" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        NSString *inputText = alert.textFields.firstObject.text;
        if (inputText.length > 0) {
            NSArray *inputIDs = [inputText componentsSeparatedByString:@","];
            
            NSUserDefaults *defaults = ads_defaults();
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
                ads_post_notification();
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
        
        NSUserDefaults *defaults = ads_defaults();
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
        ads_post_notification();
    }
}

- (void)resetToDefaults {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Reset to Defaults" message:@"Userspace reboot required to completely flush daemon hooks." preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Reboot Userspace" style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
        
        pid_t pid;
        NSString *launchctl = ads_root_path(@"/usr/bin/launchctl");
        NSString *plistPath = ads_root_path(@"/Library/LaunchDaemons/c.eolnmsuk.corelliumdecoy.plist");
        
        const char* unloadArgs[] = {"launchctl", "unload", plistPath.UTF8String, NULL};
        if (posix_spawn(&pid, launchctl.UTF8String, NULL, NULL, (char* const*)unloadArgs, NULL) == 0)
            waitpid(pid, NULL, 0);

        NSUserDefaults *defaults = ads_defaults();
        [defaults removePersistentDomainForName:ADS_PREFS_SUITE];
        [defaults synchronize];
        
        // Explicitly delete the physical file to catch the UI overlay's fallback writes
        NSString *plistPathOnDisk = ads_root_path(@"/var/mobile/Library/Preferences/com.eolnmsuk.antidarkswordprefs.plist");
        if ([[NSFileManager defaultManager] fileExistsAtPath:plistPathOnDisk]) {
            [[NSFileManager defaultManager] removeItemAtPath:plistPathOnDisk error:nil];
        }

        ads_post_notification();

        const char* rebootArgs[] = {"launchctl", "reboot", "userspace", NULL};
        posix_spawn(&pid, launchctl.UTF8String, NULL, NULL, (char* const*)rebootArgs, NULL);
        // No waitpid — the reboot kills this process.
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)savePrompt {
    NSUserDefaults *defaults = ads_defaults();
    BOOL needsReboot = [defaults boolForKey:@"ADSPendingDaemonChanges"];
    
    NSString *title = @"Save";
    NSString *msg = needsReboot ? @"Apply with userspace reboot? (Required for daemon changes)" : @"Apply changes with respring?";
    NSString *btn = needsReboot ? @"Reboot Userspace" : @"Respring";
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:msg preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    
    [alert addAction:[UIAlertAction actionWithTitle:btn style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
        [defaults setBool:NO forKey:@"ADSNeedsRespring"];
        [defaults setBool:NO forKey:@"ADSPendingDaemonChanges"];
        [defaults synchronize];
        
        pid_t pid;
        NSString *launchctl = ads_root_path(@"/usr/bin/launchctl");
        NSString *killall = ads_root_path(@"/usr/bin/killall");
        
        if (needsReboot) {
            const char* args[] = {"launchctl", "reboot", "userspace", NULL};
            posix_spawn(&pid, launchctl.UTF8String, NULL, NULL, (char* const*)args, NULL);
            // No waitpid — the reboot kills this process.
        } else {
            const char* args[] = {"killall", "backboardd", NULL};
            if (posix_spawn(&pid, killall.UTF8String, NULL, NULL, (char* const*)args, NULL) == 0)
                waitpid(pid, NULL, 0);
        }
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (id)getCountersEnabled:(PSSpecifier *)spec {
    return @([ads_defaults() boolForKey:@"countersEnabled"]);
}

- (void)setCountersEnabled:(id)value specifier:(PSSpecifier *)spec {
    NSUserDefaults *defaults = ads_defaults();
    [defaults setBool:[value boolValue] forKey:@"countersEnabled"];
    [defaults synchronize];
    [self flagSaveRequirement];
    ads_post_notification();
    dispatch_async(dispatch_get_main_queue(), ^{
        self->_specifiers = nil;
        [self reloadSpecifiers];
    });
}

- (void)resetProbeCounter {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Reset Counter"
        message:@"Clear the Corellium probe count?"
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Reset" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        NSUserDefaults *defaults = ads_defaults();
        [defaults setInteger:0 forKey:@"corelliumProbeCount"];
        [defaults synchronize];
        dispatch_async(dispatch_get_main_queue(), ^{
            self->_specifiers = nil;
            [self reloadSpecifiers];
        });
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)openGitHub {
    [[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"https://github.com/EolnMsuk/AntiDarkSword"] options:@{} completionHandler:nil];
}

- (void)openVenmo {
    [[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"https://venmo.com/user/eolnmsuk"] options:@{} completionHandler:nil];
}

- (id)getMitigationShortcut:(PSSpecifier *)spec {
    return @([ads_defaults() boolForKey:@"mitigationShortcutEnabled"]);
}

- (void)setMitigationShortcut:(id)value specifier:(PSSpecifier *)spec {
    NSUserDefaults *defaults = ads_defaults();
    [defaults setBool:[value boolValue] forKey:@"mitigationShortcutEnabled"];
    [defaults synchronize];
    [self flagSaveRequirement];
    ads_post_notification();
}

@end
