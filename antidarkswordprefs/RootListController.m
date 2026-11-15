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
#import <sys/sysctl.h>
#import <signal.h>

#import "../ADSLogging.h"
#import "ADSGames.h"
#import "ADSUpdateChecker.h"
#import "ADSDonationController.h"
#import "ADSProcessRunner.h"
#import "../ADSPaths.h"
#import <notify.h>

#define ADS_NOTIF_SAVED CFSTR("com.eolnmsuk.antidarkswordprefs/saved")
#define PROC_PIDPATHINFO_MAXSIZE 1024

extern int proc_pidpath(int pid, void *buffer, uint32_t buffersize);

static NSString * const kADSDaemonsGroupSentinel = @"DAEMONS_GROUP";

static NSArray *ads_msg_and_mail_apps(void) {
    static NSArray *list;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        list = @[ @"com.apple.MobileSMS", @"com.apple.mobilemail", @"com.apple.MailCompositionService", @"com.apple.iMessageAppsViewService", @"com.apple.ActivityMessagesApp", @"com.google.Gmail", @"com.microsoft.Office.Outlook", @"com.yahoo.Aerogram", @"ch.protonmail.protonmail", @"org.whispersystems.signal", @"ph.telegra.Telegraph", @"com.facebook.Messenger", @"com.toyopagroup.picaboo", @"com.tinyspeck.chatlyio", @"com.microsoft.skype.teams", @"com.tencent.xin", @"com.viber", @"jp.naver.line", @"net.whatsapp.WhatsApp", @"com.hammerandchisel.discord", @"com.apple.Passbook" ];
    });
    return list;
}

static inline NSUserDefaults *ads_defaults(void) {
    static NSUserDefaults *sharedDefaults = nil; static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ sharedDefaults = [[NSUserDefaults alloc] initWithSuiteName:ADS_PREFS_SUITE]; }); return sharedDefaults;
}

// Writes related keys together using the existing AnyHost scope. Callers post
// saved only after both stores contain the complete configuration.
static void ads_cfwrite_values(NSDictionary *values) {
    NSMutableDictionary *saved = [NSMutableDictionary dictionary];
    NSMutableArray *removed = [NSMutableArray array];
    for (NSString *key in values) {
        if (values[key] == NSNull.null) [removed addObject:key];
        else saved[key] = values[key];
    }
    CFStringRef appID = (__bridge CFStringRef)ADS_PREFS_SUITE;
    CFPreferencesSetMultiple((__bridge CFDictionaryRef)saved, (__bridge CFArrayRef)removed,
                             appID, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    CFPreferencesSynchronize(appID, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
}

// Writes a single key directly via CFPreferences using kCFPreferencesAnyHost — the same
// host scope the tweaks read from. NSUserDefaults may use kCFPreferencesCurrentHost on
// supervised/Roothide devices, causing a read-miss in the tweaks for up to ~30 s.
static inline void ads_cfwrite(NSString *key, id value) {
    ads_cfwrite_values(@{key: value ?: NSNull.null});
}

static void ads_write_preferences(NSDictionary *values) {
    NSUserDefaults *defaults = ads_defaults();
    for (NSString *key in values) {
        if (values[key] == NSNull.null) [defaults removeObjectForKey:key];
        else [defaults setObject:values[key] forKey:key];
    }
    [defaults synchronize];
    ads_cfwrite_values(values);
}

static void ads_flag_pending_changes(BOOL daemonChanges) {
    // Configuration edits while off require no restart. Preserve any pending
    // apply left by a previous live change or failed restart.
    if (![ads_defaults() boolForKey:@"enabled"]) return;
    NSMutableDictionary *flags = [@{@"ADSNeedsRespring": @YES} mutableCopy];
    if (daemonChanges) flags[@"ADSPendingDaemonChanges"] = @YES;
    ads_write_preferences(flags);
}

// One-time migration: re-writes all known preference keys through CFPreferences so that
// values previously saved under the NSUserDefaults host scope become visible to the tweaks.
static void ads_migrate_prefs_if_needed(void) {
    NSUserDefaults *ud = ads_defaults();
    if ([ud boolForKey:@"ADSPrefsMigrated_v2"]) return;
    NSArray *knownKeys = @[
        @"enabled", @"autoProtectLevel", @"selectedUAPreset", @"customUAString",
        @"globalUASpoofingEnabled", @"globalDisableJIT", @"globalDisableJIT15",
        @"globalDisableJS", @"globalDisableRTC", @"globalDisableMedia",
        @"globalDisableIMessageDL", @"globalDisableFileAccess",
        @"globalBlockRemoteContent", @"globalBlockRiskyAttachments",
        @"corelliumDecoyEnabled", @"countersEnabled", @"disabledPresetRules",
        @"activeCustomDaemonIDs", @"customDaemonIDs", @"restrictedApps",
        @"hasInitializedDefaultRules"
    ];
    for (NSString *key in knownKeys) {
        id val = [ud objectForKey:key];
        if (val) ads_cfwrite(key, val);
    }
    NSDictionary *all = [ud dictionaryRepresentation];
    for (NSString *key in all) {
        if ([key hasPrefix:@"TargetRules_"] || [key hasPrefix:@"restrictedApps-"])
            ads_cfwrite(key, all[key]);
    }
    ads_cfwrite(@"ADSPrefsMigrated_v2", @YES);
    [ud setBool:YES forKey:@"ADSPrefsMigrated_v2"];
    [ud synchronize];
}

static inline void ads_post_notification(void) { CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), ADS_NOTIF_SAVED, NULL, NULL, YES); }
static inline BOOL ads_is_ios16(void) { return [[NSProcessInfo processInfo] operatingSystemVersion].majorVersion >= 16; }

static inline UIColor *ads_color_green(void) {
    if (@available(iOS 13.0, *)) {
        return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traitCollection) {
            if (traitCollection.userInterfaceStyle == UIUserInterfaceStyleLight)
                return [UIColor colorWithRed:0.0 green:0.50 blue:0.0 alpha:0.25];
            return [[UIColor systemGreenColor] colorWithAlphaComponent:0.15];
        }];
    }
    return [UIColor colorWithRed:0.2 green:0.8 blue:0.2 alpha:0.15];
}

static inline UIColor *ads_color_red(void) {
    if (@available(iOS 13.0, *)) {
        return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traitCollection) {
            if (traitCollection.userInterfaceStyle == UIUserInterfaceStyleLight)
                return [UIColor colorWithRed:0.70 green:0.0 blue:0.0 alpha:0.25];
            return [[UIColor systemRedColor] colorWithAlphaComponent:0.15];
        }];
    }
    return [UIColor colorWithRed:0.8 green:0.2 blue:0.2 alpha:0.15];
}

@interface LSApplicationProxy : NSObject
+ (id)applicationProxyForIdentifier:(NSString *)identifier;
- (NSString *)localizedName; - (NSURL *)bundleURL;
@end

@interface LSApplicationWorkspace : NSObject
+ (id)defaultWorkspace;
- (BOOL)applicationIsInstalled:(NSString *)appIdentifier;
@end

@interface LSPlugInKitProxy : NSObject
+ (NSArray *)pluginKitProxiesForHostBundleIdentifier:(NSString *)identifier;
- (NSString *)pluginIdentifier;
- (NSString *)pluginCategory;
- (NSString *)localizedName;
@end

@interface UIImage (Private)
+ (UIImage *)_applicationIconImageForBundleIdentifier:(NSString *)bundleIdentifier format:(int)format scale:(CGFloat)scale;
@end

@interface UITableViewCell (PreferencesUI)
- (id)control;
@end

@interface AntiDarkSwordPrefsRootListController : PSListController
@property (nonatomic, assign) BOOL updateCheckInProgress;
@property (nonatomic, strong) NSArray *cachedDisabledPresetRules;
@property (nonatomic, strong) NSArray *cachedActiveCustomDaemons;
- (NSArray *)autoProtectedItemsForLevel:(NSInteger)level;
- (void)populateDefaultRulesForLevel:(NSInteger)level force:(BOOL)force;
- (void)populateDefaultRulesForLevel:(NSInteger)level force:(BOOL)force changes:(NSMutableDictionary *)changes;
- (NSString *)displayNameForTargetID:(NSString *)targetID;
- (UIImage *)iconForTargetID:(NSString *)targetID;
- (BOOL)isTargetInstalled:(NSString *)targetID;
@end

@interface AntiDarkSwordAppController : PSListController
@property (nonatomic, strong) NSString *targetID;
@property (nonatomic, assign) NSInteger ruleType;
@property (nonatomic, assign) BOOL isPlugin;
+ (BOOL)isDaemonTarget:(NSString *)targetID;
+ (BOOL)isApplicableFeature:(NSString *)featureKey forTarget:(NSString *)targetID;
- (BOOL)isGlobalOverrideActiveForFeature:(NSString *)featureKey;
@end

@interface AntiDarkSwordDaemonListController : PSListController
@end

static NSDictionary *ads_daemon_alias_map(void) {
    static NSDictionary *map; static dispatch_once_t once;
    dispatch_once(&once, ^{ map = @{ @"imagent": @"com.apple.imagent", @"IMDPersistenceAgent": @"com.apple.IMDPersistenceAgent", @"apsd": @"com.apple.apsd", @"identityservicesd": @"com.apple.identityservicesd" }; });
    return map;
}

// Security-relevant extension point categories.
// NSEs and notification content extensions receive attachment payloads before user interaction.
// Share extensions accept arbitrary content from the share sheet.
// iMessage app extensions run in the Messages compose/view context.
static NSSet *ads_relevant_plugin_categories(void) {
    static NSSet *s; static dispatch_once_t once;
    dispatch_once(&once, ^{
        s = [NSSet setWithObjects:
            @"com.apple.usernotifications.service",
            @"com.apple.usernotifications.content-extension",
            @"com.apple.share-services",
            @"com.apple.message-payload-provider",
            nil];
    });
    return s;
}

// Returns an array of @{bundleID, category, name} dicts for security-relevant plugins of parentID.
// Strategy 1: LSPlugInKitProxy (PlugInKit daemon-backed, fast).
// Strategy 2: direct PlugIns/ bundle scan — fallback when PlugInKit returns empty (e.g. daemon
//   hasn't indexed yet, system-partition extension DB is separate, or fresh restore).
static NSArray<NSDictionary *> *ads_plugins_for_bundle_id(NSString *parentID) {
    if (!parentID.length) return @[];
    NSMutableArray *result = [NSMutableArray array];
    NSSet *relevant = ads_relevant_plugin_categories();

    // --- Strategy 1: LSPlugInKitProxy ---
    @try {
        Class cls = NSClassFromString(@"LSPlugInKitProxy");
        if (cls && [cls respondsToSelector:@selector(pluginKitProxiesForHostBundleIdentifier:)]) {
            NSArray *proxies = [cls pluginKitProxiesForHostBundleIdentifier:parentID];
            for (LSPlugInKitProxy *proxy in proxies) {
                @try {
                    NSString *category   = [proxy pluginCategory];
                    if (![relevant containsObject:category]) continue;
                    NSString *identifier = [proxy pluginIdentifier];
                    if (!identifier.length) continue;
                    NSString *name = nil;
                    @try { name = [proxy localizedName]; } @catch (__unused id) {}
                    if (!name.length) name = identifier;
                    [result addObject:@{@"bundleID": identifier, @"category": category, @"name": name}];
                } @catch (__unused NSException *e) {}
            }
        }
    } @catch (__unused NSException *e) {}

    if (result.count > 0) return [result copy];

    // --- Strategy 2: PlugIns/ directory scan ---
    // Reads NSExtensionPointIdentifier and CFBundleIdentifier directly from each .appex Info.plist.
    // Reliable regardless of PlugInKit daemon state or extension registration partition.
    @try {
        Class LSAppProxy = NSClassFromString(@"LSApplicationProxy");
        if (!LSAppProxy) return @[];
        id proxy = [LSAppProxy applicationProxyForIdentifier:parentID];
        if (!proxy || ![proxy respondsToSelector:@selector(bundleURL)]) return @[];
        NSURL *bundleURL = [proxy bundleURL];
        if (!bundleURL) return @[];

        NSURL *pluginsURL = [bundleURL URLByAppendingPathComponent:@"PlugIns"];
        NSArray *contents = [[NSFileManager defaultManager]
            contentsOfDirectoryAtURL:pluginsURL
            includingPropertiesForKeys:nil
            options:NSDirectoryEnumerationSkipsHiddenFiles
            error:nil];
        if (!contents.count) return @[];

        for (NSURL *extURL in contents) {
            if (![[extURL pathExtension] isEqualToString:@"appex"]) continue;
            NSDictionary *infoPlist = [NSDictionary dictionaryWithContentsOfURL:
                [extURL URLByAppendingPathComponent:@"Info.plist"]];
            if (!infoPlist) continue;
            NSDictionary *nsExt = infoPlist[@"NSExtension"];
            if (!nsExt) continue;
            NSString *category = nsExt[@"NSExtensionPointIdentifier"];
            if (!category || ![relevant containsObject:category]) continue;
            NSString *identifier = infoPlist[@"CFBundleIdentifier"];
            if (!identifier.length) continue;
            NSString *name = infoPlist[@"CFBundleDisplayName"]
                          ?: infoPlist[@"CFBundleName"]
                          ?: identifier;
            [result addObject:@{@"bundleID": identifier, @"category": category, @"name": name}];
        }
    } @catch (__unused NSException *e) {}

    return [result copy];
}


static char ads_observer_tokens_key;

static void ads_observe(PSListController *controller, const char *name, BOOL counter) {
    __weak PSListController *weakController = controller;
    int token = 0;
    int result = notify_register_dispatch(name, &token, dispatch_get_main_queue(), ^(int unused) {
        PSListController *live = weakController;
        if (!live) return;
        if (counter) [live reloadSpecifiers];
        else {
            NSUserDefaults *defaults = ads_defaults();
            live.navigationItem.rightBarButtonItem.enabled = [defaults boolForKey:@"ADSNeedsRespring"] ||
                [defaults boolForKey:@"ADSPendingDaemonChanges"];
        }
    });
    if (result != NOTIFY_STATUS_OK) return;
    NSMutableArray *tokens = objc_getAssociatedObject(controller, &ads_observer_tokens_key);
    if (!tokens) {
        tokens = [NSMutableArray array];
        objc_setAssociatedObject(controller, &ads_observer_tokens_key, tokens, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    [tokens addObject:@(token)];
}

static void ads_remove_observers(id controller) {
    for (NSNumber *token in objc_getAssociatedObject(controller, &ads_observer_tokens_key)) notify_cancel(token.intValue);
}

// One main-queue transaction spans confirmation, service control and restart.
// Staged dictionaries include every preset/plugin rule changed by a level edit;
// failure before commit therefore leaves both preference stores and Save flags intact.
@interface ADSSettingsTransaction : NSObject
@property (nonatomic, weak) PSListController *presenter;
@property (nonatomic, weak) UIView *interactionView;
@property (nonatomic) BOOL wasInteractive;
@property (nonatomic) BOOL locked;
@end
@implementation ADSSettingsTransaction
@end

static ADSSettingsTransaction *ads_settings_transaction;
static NSString *ads_pending_process_error;

static void ads_present_pending_error(UIViewController *controller) {
    if (!ads_pending_process_error || ads_settings_transaction || !controller.viewIfLoaded.window ||
        controller.presentedViewController || controller.isBeingDismissed ||
        UIApplication.sharedApplication.applicationState != UIApplicationStateActive) return;
    if (controller.navigationController && controller.navigationController.topViewController != controller) return;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Process Control Failed"
        message:ads_pending_process_error preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
    ads_pending_process_error = nil;
    [controller presentViewController:alert animated:YES completion:nil];
}

static ADSSettingsTransaction *ads_begin_transaction(PSListController *controller) {
    NSCAssert(NSThread.isMainThread, @"Settings transactions must start on the UI thread");
    if (ads_settings_transaction && !ads_settings_transaction.presenter && !ads_settings_transaction.locked)
        ads_settings_transaction = nil; // an unconfirmed page disappeared; nothing was submitted
    if (ads_settings_transaction || controller.presentedViewController) {
        [controller reloadSpecifiers];
        return nil;
    }
    ADSSettingsTransaction *transaction = [ADSSettingsTransaction new];
    transaction.presenter = controller;
    ads_settings_transaction = transaction;
    ads_pending_process_error = nil; // a new explicit request supersedes an older deferred alert
    return transaction;
}

static void ads_lock_transaction(ADSSettingsTransaction *transaction) {
    if (transaction.locked) return;
    UIView *view = transaction.presenter.navigationController.view ?: transaction.presenter.view;
    transaction.interactionView = view;
    transaction.wasInteractive = view.userInteractionEnabled;
    transaction.locked = YES;
    view.userInteractionEnabled = NO;
}

static void ads_end_transaction(ADSSettingsTransaction *transaction) {
    if (ads_settings_transaction != transaction) return;
    if (transaction.locked) transaction.interactionView.userInteractionEnabled = transaction.wasInteractive;
    ads_settings_transaction = nil;
    [transaction.presenter reloadSpecifiers];
    ads_post_notification();
}

static void ads_cancel_unconfirmed(PSListController *controller) {
    ADSSettingsTransaction *transaction = ads_settings_transaction;
    if (transaction.presenter == controller && !transaction.locked &&
        (controller.isMovingFromParentViewController || controller.isBeingDismissed || controller.navigationController.isBeingDismissed))
        ads_end_transaction(transaction);
}

static void ads_fail_transaction(ADSSettingsTransaction *transaction, ADSCommandResult *result, NSString *message) {
    if (ads_settings_transaction != transaction) return;
    __weak PSListController *presenter = transaction.presenter;
    ads_end_transaction(transaction);
    NSString *diagnostics = result.diagnosticDescription;
    if (diagnostics.length > 4500) diagnostics = [[diagnostics substringToIndex:4500] stringByAppendingString:@"\n[see process log for full diagnostics]"];
    ads_pending_process_error = [NSString stringWithFormat:@"%@\n\n%@", message, diagnostics];
    ads_present_pending_error(presenter);
    // A Save/reset alert may still be dismissing when the command completes.
    // Keep the error for the next appearance if this controller is no longer visible.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        ads_present_pending_error(presenter);
    });
}

static BOOL ads_requested_active(NSDictionary *changes) {
    NSUserDefaults *defaults = ads_defaults();
    return [changes[@"enabled"] ?: [defaults objectForKey:@"enabled"] boolValue] &&
        [changes[@"corelliumDecoyEnabled"] ?: [defaults objectForKey:@"corelliumDecoyEnabled"] boolValue];
}

static BOOL ads_restore_daemon_rules(NSMutableDictionary *changes) {
    NSMutableArray *disabled = [changes[@"disabledPresetRules"] ?: [ads_defaults() arrayForKey:@"disabledPresetRules"] mutableCopy] ?: [NSMutableArray array];
    NSArray *before = [disabled copy];
    NSDictionary *aliases = ads_daemon_alias_map();
    for (NSString *shortName in aliases) {
        [disabled removeObject:shortName];
        [disabled removeObject:aliases[shortName]];
    }
    if ([before isEqualToArray:disabled]) return NO;
    changes[@"disabledPresetRules"] = disabled;
    return YES;
}

static void ads_transition_decoy(ADSSettingsTransaction *transaction, BOOL previous, BOOL next,
                                 BOOL reconcile, ADSCommandCompletion completion) {
    if (previous == next && !reconcile) {
        completion(nil); // in particular, OFF configuration edits never spawn or probe
        return;
    }
    ads_lock_transaction(transaction);
    ADSSetDecoyActive(next, ^(ADSCommandResult *result) {
        if (ads_settings_transaction == transaction) completion(result);
    });
}

static void ads_apply_configuration(ADSSettingsTransaction *transaction, NSDictionary *changes) {
    ads_transition_decoy(transaction, ads_requested_active(nil), ads_requested_active(changes), NO, ^(ADSCommandResult *result) {
        if (result && !result.isSuccessful) {
            ads_fail_transaction(transaction, result, @"The change was not fully applied. Previous settings were kept. You can try the change again.");
            return;
        }
        ads_write_preferences(changes);
        ads_end_transaction(transaction);
    });
}

static void ads_restart(ADSSettingsTransaction *transaction, BOOL needsReboot) {
    NSUserDefaults *defaults = ads_defaults();
    NSDictionary *pending = @{
        @"ADSNeedsRespring": @([defaults boolForKey:@"ADSNeedsRespring"]),
        @"ADSPendingDaemonChanges": @([defaults boolForKey:@"ADSPendingDaemonChanges"])
    };
    // Prepare the restart handoff: Settings may terminate before a successful
    // command can call back. Restore the exact pending flags on every failure.
    ads_write_preferences(@{@"ADSNeedsRespring": @NO, @"ADSPendingDaemonChanges": @NO});
    NSString *program = needsReboot ? ADSLaunchctlPath() : ADSJailbreakPath(@"/usr/bin/killall");
    NSArray *arguments = needsReboot ? @[@"reboot", @"userspace"] : @[@"backboardd"];
    ADSRunCommand(program, arguments, needsReboot ? @"Reboot Userspace" : @"Respring", ^(ADSCommandResult *result) {
        if (ads_settings_transaction != transaction) return;
        if (!result.isSuccessful) {
            ads_write_preferences(pending);
            ads_fail_transaction(transaction, result, @"Settings were saved, but the restart failed. Use Save to retry applying them.");
        } else ads_end_transaction(transaction);
    });
}

static void ads_present_save_prompt(PSListController *controller, NSDictionary *proposal) {
    NSUserDefaults *defaults = ads_defaults();
    if (!proposal && ![defaults boolForKey:@"ADSNeedsRespring"] && ![defaults boolForKey:@"ADSPendingDaemonChanges"]) return;
    ADSSettingsTransaction *transaction = ads_begin_transaction(controller);
    if (!transaction) return;
    BOOL needsReboot = [proposal[@"ADSPendingDaemonChanges"] ?: [defaults objectForKey:@"ADSPendingDaemonChanges"] boolValue];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Save"
        message:needsReboot ? @"Apply changes with a userspace reboot? (Required for daemon changes)" : @"Apply changes with respring?"
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
        ads_end_transaction(transaction); // no staged writes or service commands to undo
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:needsReboot ? @"Reboot Userspace" : @"Respring"
        style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        if (ads_settings_transaction != transaction) return;
        // Apply is explicit: installation/reboot may have registered the job even
        // when the saved request is inactive. Do not infer actual state from prefs.
        ads_transition_decoy(transaction, ads_requested_active(nil), ads_requested_active(proposal), YES, ^(ADSCommandResult *result) {
            if (!result.isSuccessful) {
                ads_fail_transaction(transaction, result, proposal ?
                    @"The change was not fully applied. Previous settings and Save flags were kept. You can try again." :
                    @"The saved changes were not fully applied. Use Save to retry.");
                return;
            }
            if (proposal) ads_write_preferences(proposal);
            ads_post_notification();
            ads_restart(transaction, needsReboot);
        });
    }]];
    [controller presentViewController:alert animated:YES completion:nil];
}

@class AntiDarkSwordAltListController;



@implementation AntiDarkSwordDaemonListController
- (void)viewWillDisappear:(BOOL)animated { [super viewWillDisappear:animated]; ads_cancel_unconfirmed(self); }
- (void)viewDidLoad {
    [super viewDidLoad];
    ads_observe(self, "com.eolnmsuk.antidarkswordprefs/counter", YES);
    
    UIBarButtonItem *saveButton = [[UIBarButtonItem alloc] initWithTitle:@"Save" style:UIBarButtonItemStyleDone target:self action:@selector(savePrompt)]; self.navigationItem.rightBarButtonItem = saveButton;
    NSUserDefaults *defaults = ads_defaults(); BOOL needsRespring = [defaults boolForKey:@"ADSNeedsRespring"]; BOOL needsReboot = [defaults boolForKey:@"ADSPendingDaemonChanges"]; saveButton.enabled = needsRespring || needsReboot;
    ads_observe(self, "com.eolnmsuk.antidarkswordprefs/saved", NO);
}
- (void)dealloc {
    ads_remove_observers(self);
}

- (void)savePrompt { ads_present_save_prompt(self, nil); }
- (void)viewDidAppear:(BOOL)animated { [super viewDidAppear:animated]; ads_present_pending_error(self); }

- (NSArray *)specifiers {
    if (!_specifiers) {
        NSMutableArray *specs = [NSMutableArray array];
        AntiDarkSwordPrefsRootListController *rootCtrl = [[AntiDarkSwordPrefsRootListController alloc] init];
        NSUserDefaults *defaults = ads_defaults();
        BOOL corelliumEnabled = [defaults boolForKey:@"corelliumDecoyEnabled"];
        NSInteger autoProtectLevel = [defaults integerForKey:@"autoProtectLevel"] ?: 1;

        PSSpecifier *decoyGroup = [PSSpecifier preferenceSpecifierNamed:@"Corellium Honeypot" target:self set:nil get:nil detail:nil cell:PSGroupCell edit:nil];
        [decoyGroup setProperty:@"Spoofs Corellium environment to cause exploits (like Coruna) to self-abort." forKey:@"footerText"]; [specs addObject:decoyGroup];
        PSSpecifier *decoySpec = [PSSpecifier preferenceSpecifierNamed:@"Enable Corellium Honeypot" target:self set:@selector(setCorelliumEnabled:specifier:) get:@selector(getCorelliumEnabled:) detail:nil cell:PSSwitchCell edit:nil]; [specs addObject:decoySpec];

        BOOL showCounter = [defaults boolForKey:@"countersEnabled"];
        NSInteger probeCount = [defaults integerForKey:@"corelliumProbeCount"];
        PSSpecifier *counterGroup = [PSSpecifier preferenceSpecifierNamed:@"Attack Statistics" target:self set:nil get:nil detail:nil cell:PSGroupCell edit:nil];
        [counterGroup setProperty:@"Counts Corellium environment probe attempts detected by system daemons." forKey:@"footerText"]; [specs addObject:counterGroup];
        PSSpecifier *counterToggle = [PSSpecifier preferenceSpecifierNamed:@"Enable Attack Counter" target:self set:@selector(setCountersEnabled:specifier:) get:@selector(getCountersEnabled:) detail:nil cell:PSSwitchCell edit:nil];
        if (!corelliumEnabled) [counterToggle setProperty:@NO forKey:@"enabled"];
        [specs addObject:counterToggle];

        if (showCounter && corelliumEnabled) {
            NSString *countLabel = (probeCount == 0) ? @"Corellium Probes Detected: None" : [NSString stringWithFormat:@"Corellium Probes Detected: %ld", (long)probeCount];
            PSSpecifier *countCell = [PSSpecifier preferenceSpecifierNamed:countLabel target:self set:nil get:nil detail:nil cell:PSStaticTextCell edit:nil]; [specs addObject:countCell];
            PSSpecifier *resetBtn = [PSSpecifier preferenceSpecifierNamed:@"Reset Counter" target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
            resetBtn->action = @selector(resetProbeCounter); [specs addObject:resetBtn];
        }

        PSSpecifier *group = [PSSpecifier preferenceSpecifierNamed:@"System Daemons" target:self set:nil get:nil detail:nil cell:PSGroupCell edit:nil];
        [group setProperty:@"With Protection on, enabled daemons receive exploit mitigations. Turning a row off bypasses its preset protection; custom and global rules still apply." forKey:@"footerText"]; [specs addObject:group];

        NSArray *daemons = @[@"imagent", @"apsd", @"identityservicesd", @"IMDPersistenceAgent"];
        for (NSString *daemon in daemons) {
            PSSpecifier *spec = [PSSpecifier preferenceSpecifierNamed:[rootCtrl displayNameForTargetID:daemon] target:self set:@selector(setDaemonEnabled:specifier:) get:@selector(getDaemonEnabled:) detail:nil cell:PSSwitchCell edit:nil];
            [spec setProperty:daemon forKey:@"targetID"]; if (corelliumEnabled) [spec setProperty:@NO forKey:@"enabled"];
            [specs addObject:spec];
        }

        PSSpecifier *globalGroup = [PSSpecifier preferenceSpecifierNamed:@"⚠︎  Global Rules (BETA) ⚠︎ " target:self set:nil get:nil detail:nil cell:PSGroupCell edit:nil];
        [globalGroup setProperty:@"Global rules can break almost anything, for advanced users only." forKey:@"footerText"]; [specs addObject:globalGroup];

        NSArray *globals = @[ @{@"key": @"globalUASpoofingEnabled", @"label": @"Spoof User Agent"}, @{@"key": @"globalDisableJIT", @"label": @"Block JIT (iOS 16+)"}, @{@"key": @"globalDisableJIT15", @"label": @"Block JIT (Legacy)"}, @{@"key": @"globalDisableJS", @"label": @"Block JavaScript ⚠︎"}, @{@"key": @"globalDisableRTC", @"label": @"Block WebGL & WebRTC"}, @{@"key": @"globalDisableMedia", @"label": @"Block Media Auto-Play"}, @{@"key": @"globalDisableIMessageDL", @"label": @"Block Msg Auto-Download"}, @{@"key": @"globalDisableFileAccess", @"label": @"Block Local File Access"}, @{@"key": @"globalBlockRemoteContent", @"label": @"Block Remote Content"}, @{@"key": @"globalBlockRiskyAttachments", @"label": @"Block Attachment Previews"} ];

        BOOL isIOS16 = ads_is_ios16(); BOOL globalJSEnabled = [defaults boolForKey:@"globalDisableJS"];
        for (NSDictionary *g in globals) {
            PSSpecifier *spec = [PSSpecifier preferenceSpecifierNamed:g[@"label"] target:self set:@selector(setGlobalMitigation:specifier:) get:@selector(getGlobalMitigation:) detail:nil cell:PSSwitchCell edit:nil];
            [spec setProperty:g[@"key"] forKey:@"key"];
            if (autoProtectLevel < 3) { [spec setProperty:@NO forKey:@"enabled"]; } else {
                if ([g[@"key"] isEqualToString:@"globalDisableJIT"] && (!isIOS16 || globalJSEnabled)) [spec setProperty:@NO forKey:@"enabled"];
                if ([g[@"key"] isEqualToString:@"globalDisableJIT15"] && (isIOS16 || globalJSEnabled)) [spec setProperty:@NO forKey:@"enabled"];
            }
            [specs addObject:spec];
        }
        _specifiers = [specs copy];
    }
    return _specifiers;
}

- (void)reloadSpecifiers { self->_specifiers = nil; [super reloadSpecifiers]; }

- (id)getDaemonEnabled:(PSSpecifier *)spec {
    NSString *target = [spec propertyForKey:@"targetID"];
    NSArray *disabled = [ads_defaults() arrayForKey:@"disabledPresetRules"] ?: @[];
    return @(![disabled containsObject:target] && ![disabled containsObject:ads_daemon_alias_map()[target]]);
}

- (void)setDaemonEnabled:(id)value specifier:(PSSpecifier *)spec {
    if (ads_settings_transaction) { [self reloadSpecifiers]; return; }
    NSUserDefaults *defaults = ads_defaults(); NSMutableArray *disabled = [[defaults arrayForKey:@"disabledPresetRules"] mutableCopy] ?: [NSMutableArray array];
    NSString *targetID = [spec propertyForKey:@"targetID"]; NSDictionary *aliasMap = ads_daemon_alias_map();

    if ([value boolValue]) {
        [disabled removeObject:targetID]; if (aliasMap[targetID]) [disabled removeObject:aliasMap[targetID]];
    } else {
        if (![disabled containsObject:targetID]) [disabled addObject:targetID];
        if (aliasMap[targetID] && ![disabled containsObject:aliasMap[targetID]]) [disabled addObject:aliasMap[targetID]];
    }
    NSMutableDictionary *changes = [@{@"disabledPresetRules": disabled} mutableCopy];
    if ([defaults boolForKey:@"enabled"]) {
        changes[@"ADSNeedsRespring"] = @YES;
        changes[@"ADSPendingDaemonChanges"] = @YES;
    }
    ads_write_preferences(changes);
    ads_post_notification();
}

- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; [self reloadSpecifiers]; }

- (id)getCorelliumEnabled:(PSSpecifier *)spec { return @([ads_defaults() boolForKey:@"corelliumDecoyEnabled"]); }

- (void)setCorelliumEnabled:(id)value specifier:(PSSpecifier *)spec {
    NSUserDefaults *defaults = ads_defaults();
    BOOL decoyEnabled = [value boolValue];
    if (decoyEnabled == [defaults boolForKey:@"corelliumDecoyEnabled"]) { [self reloadSpecifiers]; return; }
    ADSSettingsTransaction *transaction = ads_begin_transaction(self);
    if (!transaction) return;
    NSMutableDictionary *changes = [@{@"corelliumDecoyEnabled": @(decoyEnabled)} mutableCopy];
    BOOL daemonsChanged = decoyEnabled && ads_restore_daemon_rules(changes);
    if ([defaults boolForKey:@"enabled"]) {
        changes[@"ADSNeedsRespring"] = @YES;
        if (daemonsChanged) changes[@"ADSPendingDaemonChanges"] = @YES;
    }
    ads_apply_configuration(transaction, changes);
}

- (id)getCountersEnabled:(PSSpecifier *)spec { return @([ads_defaults() boolForKey:@"countersEnabled"]); }

- (void)setCountersEnabled:(id)value specifier:(PSSpecifier *)spec {
    NSUserDefaults *defaults = ads_defaults(); [defaults setBool:[value boolValue] forKey:@"countersEnabled"];
    ads_flag_pending_changes(NO); [defaults synchronize];
    ads_post_notification(); dispatch_async(dispatch_get_main_queue(), ^{ [self reloadSpecifiers]; });
}

- (void)resetProbeCounter {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Reset Counter" message:@"Clear the Corellium probe count?" preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Reset" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        NSUserDefaults *defaults = ads_defaults(); [defaults setInteger:0 forKey:@"corelliumProbeCount"]; [defaults synchronize];
        dispatch_async(dispatch_get_main_queue(), ^{ [self reloadSpecifiers]; });
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (id)getGlobalMitigation:(PSSpecifier *)specifier { return @([ads_defaults() boolForKey:[specifier propertyForKey:@"key"]]); }

- (void)setGlobalMitigation:(id)value specifier:(PSSpecifier *)specifier {
    BOOL enabled = [value boolValue]; NSString *key = [specifier propertyForKey:@"key"]; NSUserDefaults *defaults = ads_defaults();
    
    if (enabled) {
        NSString *featureName = [specifier name];
        NSString *msg = [NSString stringWithFormat:@"Enabling '%@' globally applies this mitigation to ALL processes indiscriminately. This may break core functionality across the system and is intended for testing/emergency lockdown only.", featureName];
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Warning" message:msg preferredStyle:UIAlertControllerStyleAlert];
        
        [alert addAction:[UIAlertAction actionWithTitle:@"Enable Globally" style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
            [defaults setBool:YES forKey:key];
            if ([key isEqualToString:@"globalDisableJS"]) { if (ads_is_ios16()) [defaults setBool:YES forKey:@"globalDisableJIT"]; else [defaults setBool:YES forKey:@"globalDisableJIT15"]; }
            ads_flag_pending_changes(NO); [defaults synchronize]; ads_post_notification();
            dispatch_async(dispatch_get_main_queue(), ^{ [self reloadSpecifiers]; });
        }]];
        
        [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:^(UIAlertAction * _Nonnull action) { [self reloadSpecifiers]; }]];
        [self presentViewController:alert animated:YES completion:nil];
    } else {
        [defaults setBool:NO forKey:key];
        if ([key isEqualToString:@"globalDisableJS"]) { [defaults setBool:NO forKey:@"globalDisableJIT"]; [defaults setBool:NO forKey:@"globalDisableJIT15"]; }
        ads_flag_pending_changes(NO); [defaults synchronize]; ads_post_notification();
        dispatch_async(dispatch_get_main_queue(), ^{ [self reloadSpecifiers]; });
    }
}
@end

@interface ATLApplicationListMultiSelectionController : PSListController
@end

@interface AntiDarkSwordAltListController : ATLApplicationListMultiSelectionController
@property (nonatomic, strong) NSArray *cachedPresetApps;
@property (nonatomic, strong) NSDictionary *cachedRestrictedApps;
@property (nonatomic, strong) NSDictionary *cachedRestrictedAppsLegacy;
@end

@implementation AntiDarkSwordAltListController
- (void)viewWillDisappear:(BOOL)animated { [super viewWillDisappear:animated]; ads_cancel_unconfirmed(self); }
- (void)viewDidLoad {
    [super viewDidLoad];
    NSUserDefaults *defaults = ads_defaults(); NSInteger level = [defaults integerForKey:@"autoProtectLevel"] ?: 1;
    AntiDarkSwordPrefsRootListController *rootCtrl = [[AntiDarkSwordPrefsRootListController alloc] init];
    self.cachedPresetApps = [rootCtrl autoProtectedItemsForLevel:level];
    
    UIBarButtonItem *saveButton = [[UIBarButtonItem alloc] initWithTitle:@"Save" style:UIBarButtonItemStyleDone target:self action:@selector(savePrompt)]; self.navigationItem.rightBarButtonItem = saveButton;
    BOOL needsRespring = [defaults boolForKey:@"ADSNeedsRespring"]; BOOL needsReboot = [defaults boolForKey:@"ADSPendingDaemonChanges"]; saveButton.enabled = needsRespring || needsReboot;
    ads_observe(self, "com.eolnmsuk.antidarkswordprefs/saved", NO);
}
- (void)dealloc { ads_remove_observers(self); }
- (void)savePrompt { ads_present_save_prompt(self, nil); }
- (void)viewDidAppear:(BOOL)animated { [super viewDidAppear:animated]; ads_present_pending_error(self); }
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    NSUserDefaults *defaults = ads_defaults(); self.cachedRestrictedAppsLegacy = [defaults dictionaryForKey:@"restrictedApps"] ?: @{};
    self.cachedRestrictedApps = [defaults dictionaryRepresentation]; [self reloadSpecifiers];
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [super tableView:tableView cellForRowAtIndexPath:indexPath];
    PSSpecifier *spec = [self specifierAtIndexPath:indexPath];
    NSString *bundleID = [spec propertyForKey:@"applicationIdentifier"];
    if (!bundleID) { NSString *alKey = [spec propertyForKey:@"ALSettingsKey"]; if ([alKey hasPrefix:@"restrictedApps-"]) bundleID = [alKey substringFromIndex:@"restrictedApps-".length]; }
    
    if (bundleID) {
        NSArray *presetApps = self.cachedPresetApps ?: @[];
        if ([cell respondsToSelector:@selector(control)]) { id control = [cell control]; if ([control isKindOfClass:[UIView class]]) ((UIView *)control).hidden = YES; }
        cell.accessoryView = nil; cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator; cell.selectionStyle = UITableViewCellSelectionStyleDefault;
        
        BOOL isManualRuleActive = NO; NSString *prefKey = [NSString stringWithFormat:@"restrictedApps-%@", bundleID];
        if (self.cachedRestrictedApps[prefKey] != nil) isManualRuleActive = [self.cachedRestrictedApps[prefKey] boolValue];
        else isManualRuleActive = [self.cachedRestrictedAppsLegacy[bundleID] boolValue];

        if ([presetApps containsObject:bundleID]) {
            cell.userInteractionEnabled = NO; cell.textLabel.alpha = 0.5; if (cell.detailTextLabel) cell.detailTextLabel.alpha = 0.5; cell.backgroundColor = [UIColor clearColor];
        } else {
            cell.userInteractionEnabled = YES; cell.textLabel.alpha = 1.0; if (cell.detailTextLabel) cell.detailTextLabel.alpha = 1.0; cell.backgroundColor = isManualRuleActive ? ads_color_green() : ads_color_red();
        }
    }
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    PSSpecifier *spec = [self specifierAtIndexPath:indexPath]; NSString *bundleID = [spec propertyForKey:@"applicationIdentifier"];
    if (!bundleID) { NSString *alKey = [spec propertyForKey:@"ALSettingsKey"]; if ([alKey hasPrefix:@"restrictedApps-"]) bundleID = [alKey substringFromIndex:@"restrictedApps-".length]; }
    if (bundleID) {
        if ([self.cachedPresetApps ?: @[] containsObject:bundleID]) return;
        AntiDarkSwordAppController *detailController = [[AntiDarkSwordAppController alloc] init];
        detailController.targetID = bundleID; detailController.ruleType = 1; detailController.rootController = self.rootController ?: self; detailController.parentController = self;
        PSSpecifier *dummySpec = [PSSpecifier preferenceSpecifierNamed:[spec name] ?: bundleID target:self set:nil get:nil detail:[AntiDarkSwordAppController class] cell:PSLinkCell edit:nil];
        [dummySpec setProperty:bundleID forKey:@"targetID"]; [dummySpec setProperty:@(1) forKey:@"ruleType"];
        [detailController setSpecifier:dummySpec]; [self pushController:detailController];
    }
}
@end


@implementation AntiDarkSwordAppController
- (void)viewWillDisappear:(BOOL)animated { [super viewWillDisappear:animated]; ads_cancel_unconfirmed(self); }
- (void)viewDidLoad {
    [super viewDidLoad];
    UIBarButtonItem *saveButton = [[UIBarButtonItem alloc] initWithTitle:@"Save" style:UIBarButtonItemStyleDone target:self action:@selector(savePrompt)]; self.navigationItem.rightBarButtonItem = saveButton;
    NSUserDefaults *defaults = ads_defaults(); BOOL needsRespring = [defaults boolForKey:@"ADSNeedsRespring"]; BOOL needsReboot = [defaults boolForKey:@"ADSPendingDaemonChanges"]; saveButton.enabled = needsRespring || needsReboot;
    ads_observe(self, "com.eolnmsuk.antidarkswordprefs/saved", NO);
}
- (void)dealloc { ads_remove_observers(self); }
- (void)savePrompt { ads_present_save_prompt(self, nil); }
- (void)viewDidAppear:(BOOL)animated { [super viewDidAppear:animated]; ads_present_pending_error(self); }

+ (BOOL)isDaemonTarget:(NSString *)targetID {
    if (!targetID) return NO;
    NSArray *daemons = @[@"com.apple.imagent", @"imagent", @"com.apple.apsd", @"apsd", @"com.apple.identityservicesd", @"identityservicesd", @"com.apple.IMDPersistenceAgent", @"IMDPersistenceAgent"];
    if ([daemons containsObject:targetID]) return YES; if (![targetID containsString:@"."] && ![targetID isEqualToString:@"pinterest"]) return YES;
    if ([targetID containsString:@"daemon"]) return YES; return NO;
}
+ (BOOL)isApplicableFeature:(NSString *)featureKey forTarget:(NSString *)targetID {
    BOOL isDaemon = [self isDaemonTarget:targetID]; BOOL isMessageApp = [targetID isEqualToString:@"com.apple.MobileSMS"] || [targetID isEqualToString:@"com.apple.ActivityMessagesApp"] || [targetID isEqualToString:@"com.apple.iMessageAppsViewService"];
    if ([featureKey isEqualToString:@"disableIMessageDL"]) return isMessageApp;
    BOOL isIOS16 = ads_is_ios16();
    if ([featureKey isEqualToString:@"disableJIT"]) return isIOS16 && !isDaemon;
    if ([featureKey isEqualToString:@"disableJIT15"]) return !isIOS16 && !isDaemon;
    if ([featureKey isEqualToString:@"disableJS"] || [featureKey isEqualToString:@"disableRTC"] || [featureKey isEqualToString:@"disableMedia"] || [featureKey isEqualToString:@"disableFileAccess"]) return !isDaemon;
    if ([featureKey isEqualToString:@"blockRemoteContent"]) return !isDaemon;
    if ([featureKey isEqualToString:@"blockRiskyAttachments"]) {
        if (isMessageApp || [targetID isEqualToString:@"com.apple.mobilemail"] || [targetID isEqualToString:@"com.apple.MailCompositionService"] || [targetID hasPrefix:@"com.google.Gmail"] || [targetID isEqualToString:@"com.microsoft.Office.Outlook"] || [targetID isEqualToString:@"ch.protonmail.protonmail"]) return YES;
        // Also applicable to extension processes that receive notification payloads or share content.
        if ([targetID containsString:@"NotificationService"] || [targetID containsString:@"ShareExtension"] || [targetID containsString:@".share."]) return YES;
        return NO;
    }
    return YES;
}
- (void)setSpecifier:(PSSpecifier *)specifier {
    [super setSpecifier:specifier]; self.targetID = [specifier propertyForKey:@"targetID"]; self.ruleType = [[specifier propertyForKey:@"ruleType"] integerValue]; self.isPlugin = [[specifier propertyForKey:@"isPlugin"] boolValue]; self.title = [specifier name] ?: self.targetID;
}
- (BOOL)isGlobalOverrideActiveForFeature:(NSString *)featureKey {
    NSUserDefaults *defaults = ads_defaults(); NSInteger level = [defaults integerForKey:@"autoProtectLevel"] ?: 1;
    if (level < 3) return NO;
    if ([featureKey isEqualToString:@"spoofUA"]) return [defaults boolForKey:@"globalUASpoofingEnabled"];
    if ([featureKey isEqualToString:@"disableJIT"]) return [defaults boolForKey:@"globalDisableJIT"];
    if ([featureKey isEqualToString:@"disableJIT15"]) return [defaults boolForKey:@"globalDisableJIT15"];
    if ([featureKey isEqualToString:@"disableJS"]) return [defaults boolForKey:@"globalDisableJS"];
    if ([featureKey isEqualToString:@"disableRTC"]) return [defaults boolForKey:@"globalDisableRTC"];
    if ([featureKey isEqualToString:@"disableMedia"]) return [defaults boolForKey:@"globalDisableMedia"];
    if ([featureKey isEqualToString:@"disableIMessageDL"]) return [defaults boolForKey:@"globalDisableIMessageDL"];
    if ([featureKey isEqualToString:@"disableFileAccess"]) return [defaults boolForKey:@"globalDisableFileAccess"];
    if ([featureKey isEqualToString:@"blockRemoteContent"]) return [defaults boolForKey:@"globalBlockRemoteContent"];
    if ([featureKey isEqualToString:@"blockRiskyAttachments"]) return [defaults boolForKey:@"globalBlockRiskyAttachments"];
    return NO;
}
- (NSArray *)specifiers {
    if (!_specifiers) {
        NSMutableArray *specs = [NSMutableArray array]; NSUserDefaults *defaults = ads_defaults();
        PSSpecifier *enableGroup = [PSSpecifier preferenceSpecifierNamed:@"Rule Status" target:self set:nil get:nil detail:nil cell:PSGroupCell edit:nil]; [specs addObject:enableGroup];
        PSSpecifier *enableSpec = [PSSpecifier preferenceSpecifierNamed:@"Enable Rule" target:self set:@selector(setMasterEnable:specifier:) get:@selector(getMasterEnable:) detail:nil cell:PSSwitchCell edit:nil]; [specs addObject:enableSpec];
        
        BOOL isRuleEnabled = [[self getMasterEnable:enableSpec] boolValue];
        PSSpecifier *featGroup = [PSSpecifier preferenceSpecifierNamed:@"Mitigation Features" target:self set:nil get:nil detail:nil cell:PSGroupCell edit:nil];
        NSString *featFooter = (self.isPlugin && !isRuleEnabled)
            ? @"Inheriting parent app rules. Enable the rule to configure plugin-specific overrides."
            : @"Features not applicable to this target type, or currently enforced by a Global Rule, are locked.";
        [featGroup setProperty:featFooter forKey:@"footerText"]; [specs addObject:featGroup];
        
        NSArray *features = @[ @{@"key": @"spoofUA", @"label": @"Spoof User Agent"}, @{@"key": @"disableJIT", @"label": @"Block JIT (iOS 16+)"}, @{@"key": @"disableJIT15", @"label": @"Block JIT (Legacy)"}, @{@"key": @"disableJS", @"label": @"Block JavaScript ⚠︎"}, @{@"key": @"disableRTC", @"label": @"Block WebGL & WebRTC"}, @{@"key": @"disableMedia", @"label": @"Block Media Auto-Play"}, @{@"key": @"disableIMessageDL", @"label": @"Block Msg Auto-Download"}, @{@"key": @"disableFileAccess", @"label": @"Block Local File Access"}, @{@"key": @"blockRemoteContent", @"label": @"Block Remote Content"}, @{@"key": @"blockRiskyAttachments", @"label": @"Block Attachment Previews"} ];
        
        NSString *dictKey = [NSString stringWithFormat:@"TargetRules_%@", self.targetID]; NSDictionary *rules = [defaults dictionaryForKey:dictKey]; BOOL isIOS16 = ads_is_ios16();
        BOOL isJSTurnedOn = (rules && rules[@"disableJS"] != nil) ? [rules[@"disableJS"] boolValue] : (!isIOS16 && [AntiDarkSwordAppController isApplicableFeature:@"disableJS" forTarget:self.targetID]);
        BOOL isJITOn = (rules && rules[@"disableJIT"] != nil) ? [rules[@"disableJIT"] boolValue] : isIOS16;
        BOOL isJIT15On = (rules && rules[@"disableJIT15"] != nil) ? [rules[@"disableJIT15"] boolValue] : !isIOS16;
        BOOL activeJITOn = isIOS16 ? isJITOn : isJIT15On;
        
        for (NSDictionary *feat in features) {
            NSString *featKey = feat[@"key"]; BOOL isApplicable = [AntiDarkSwordAppController isApplicableFeature:featKey forTarget:self.targetID]; BOOL isGlobalOverride = [self isGlobalOverrideActiveForFeature:featKey];
            PSSpecifier *spec = [PSSpecifier preferenceSpecifierNamed:feat[@"label"] target:self set:@selector(setFeatureValue:specifier:) get:@selector(getFeatureValue:) detail:nil cell:PSSwitchCell edit:nil];
            [spec setProperty:featKey forKey:@"featureKey"];
            if (isApplicable) {
                if (isGlobalOverride) [spec setProperty:@NO forKey:@"enabled"];
                else if (isIOS16 && isJSTurnedOn && [featKey isEqualToString:@"disableJIT"]) [spec setProperty:@NO forKey:@"enabled"];
                else if (!isIOS16 && isJSTurnedOn && [featKey isEqualToString:@"disableJIT15"]) [spec setProperty:@NO forKey:@"enabled"];
                else if ([featKey isEqualToString:@"disableMedia"] && !activeJITOn) [spec setProperty:@NO forKey:@"enabled"];
                else [spec setProperty:@(isRuleEnabled) forKey:@"enabled"];
            } else { [spec setProperty:@NO forKey:@"enabled"]; }
            [specs addObject:spec];
        }

        // App Plugins — enumerate security-relevant extension processes for this app.
        // Each plugin cell pushes a nested AntiDarkSwordAppController for the plugin bundle ID,
        // letting the user configure per-plugin rules independently of the parent app.
        NSArray<NSDictionary *> *plugins = ads_plugins_for_bundle_id(self.targetID);
        if (plugins.count > 0) {
            PSSpecifier *pluginGroup = [PSSpecifier preferenceSpecifierNamed:@"App Plugins"
                target:self set:nil get:nil detail:nil cell:PSGroupCell edit:nil];
            [pluginGroup setProperty:@"Security rules for this app's extension processes. Plugins inherit the parent app's rules unless overridden here."
                             forKey:@"footerText"];
            [specs addObject:pluginGroup];

            static NSDictionary *categoryLabels;
            static dispatch_once_t catOnce;
            dispatch_once(&catOnce, ^{
                categoryLabels = @{
                    @"com.apple.usernotifications.service":          @"Notification Service",
                    @"com.apple.usernotifications.content-extension":@"Notification Content",
                    @"com.apple.share-services":                     @"Share Extension",
                    @"com.apple.message-payload-provider":           @"iMessage App Extension"
                };
            });

            AntiDarkSwordPrefsRootListController *rootCtrl = [[AntiDarkSwordPrefsRootListController alloc] init];
            for (NSDictionary *plugin in plugins) {
                NSString *pluginBundleID = plugin[@"bundleID"];
                NSString *category       = plugin[@"category"];
                NSString *catLabel       = categoryLabels[category] ?: category;
                NSString *displayName    = [NSString stringWithFormat:@"%@ (%@)", plugin[@"name"], catLabel];

                PSSpecifier *pspec = [PSSpecifier preferenceSpecifierNamed:displayName
                    target:self set:nil get:nil detail:[AntiDarkSwordAppController class]
                    cell:PSLinkCell edit:nil];
                [pspec setProperty:pluginBundleID forKey:@"targetID"];
                [pspec setProperty:@(1) forKey:@"ruleType"];
                [pspec setProperty:@YES forKey:@"isPlugin"];
                [pspec setProperty:@(isRuleEnabled) forKey:@"enabled"];
                UIImage *icon = [rootCtrl iconForTargetID:pluginBundleID];
                if (icon) [pspec setProperty:icon forKey:@"iconImage"];
                [specs addObject:pspec];
            }
        }

        _specifiers = [specs copy];
    }
    return _specifiers;
}
- (id)getMasterEnable:(PSSpecifier *)specifier {
    NSUserDefaults *defaults = ads_defaults();
    if (self.ruleType == 0) return @(![[defaults arrayForKey:@"disabledPresetRules"] ?: @[] containsObject:self.targetID]);
    else if (self.ruleType == 1) { 
        NSString *prefKey = [NSString stringWithFormat:@"restrictedApps-%@", self.targetID];
        if ([defaults objectForKey:prefKey]) return @([defaults boolForKey:prefKey]);
        return [defaults dictionaryForKey:@"restrictedApps"][self.targetID] ?: @NO;
    } else return @([[defaults arrayForKey:@"activeCustomDaemonIDs"] ?: [defaults arrayForKey:@"customDaemonIDs"] ?: @[] containsObject:self.targetID]);
}
- (void)setMasterEnable:(id)value specifier:(PSSpecifier *)specifier {
    NSUserDefaults *defaults = ads_defaults(); BOOL enabled = [value boolValue];
    if (self.ruleType == 0) { 
        NSMutableArray *disabled = [[defaults arrayForKey:@"disabledPresetRules"] mutableCopy] ?: [NSMutableArray array];
        if (enabled) [disabled removeObject:self.targetID]; else if (![disabled containsObject:self.targetID]) [disabled addObject:self.targetID];
        [defaults setObject:disabled forKey:@"disabledPresetRules"]; ads_cfwrite(@"disabledPresetRules", disabled);
    } else if (self.ruleType == 1) { 
        [defaults setBool:enabled forKey:[NSString stringWithFormat:@"restrictedApps-%@", self.targetID]];
        NSMutableDictionary *apps = [[defaults dictionaryForKey:@"restrictedApps"] mutableCopy];
        if (apps && apps[self.targetID]) { [apps removeObjectForKey:self.targetID]; [defaults setObject:apps forKey:@"restrictedApps"]; }
    } else { 
        NSMutableArray *active = [[defaults arrayForKey:@"activeCustomDaemonIDs"] mutableCopy] ?: [[defaults arrayForKey:@"customDaemonIDs"] mutableCopy] ?: [NSMutableArray array];
        if (enabled && ![active containsObject:self.targetID]) [active addObject:self.targetID]; else if (!enabled) [active removeObject:self.targetID];
        [defaults setObject:active forKey:@"activeCustomDaemonIDs"]; ads_flag_pending_changes(YES);
    }
    ads_flag_pending_changes(NO); [defaults synchronize]; ads_post_notification(); dispatch_async(dispatch_get_main_queue(), ^{ self->_specifiers = nil; [self reloadSpecifiers]; });
}
- (id)getFeatureValue:(PSSpecifier *)specifier {
    NSString *featureKey = [specifier propertyForKey:@"featureKey"];
    if (![AntiDarkSwordAppController isApplicableFeature:featureKey forTarget:self.targetID]) return @NO;
    if ([self isGlobalOverrideActiveForFeature:featureKey]) return @YES;
    NSUserDefaults *defaults = ads_defaults(); NSString *dictKey = [NSString stringWithFormat:@"TargetRules_%@", self.targetID]; NSDictionary *rules = [defaults dictionaryForKey:dictKey];
    
    if (!rules || rules[featureKey] == nil) { 
        AntiDarkSwordPrefsRootListController *rootCtrl = [[AntiDarkSwordPrefsRootListController alloc] init];
        if (![[rootCtrl autoProtectedItemsForLevel:3] containsObject:self.targetID]) return @NO;
        NSInteger level = [defaults integerForKey:@"autoProtectLevel"] ?: 1; BOOL isIOS16 = ads_is_ios16();
        if ([featureKey isEqualToString:@"disableJIT"]) return @(isIOS16); 
        if ([featureKey isEqualToString:@"disableJIT15"]) return @(!isIOS16); 
        if ([featureKey isEqualToString:@"disableJS"]) return @(!isIOS16); 
        if ([featureKey isEqualToString:@"spoofUA"]) {
            if ([AntiDarkSwordAppController isDaemonTarget:self.targetID]) return @NO;
            if ([self.targetID isEqualToString:@"com.apple.mobilesafari"] || [self.targetID isEqualToString:@"com.apple.SafariViewService"]) return @YES;
            if ([self.targetID hasPrefix:@"com.apple."]) return @NO; return @(level >= 2); 
        }
        if ([ads_msg_and_mail_apps() containsObject:self.targetID]) return @YES;
        if (level >= 3 && ([featureKey isEqualToString:@"disableRTC"] || [featureKey isEqualToString:@"disableMedia"])) {
            NSArray *browsers = @[@"com.apple.mobilesafari", @"com.apple.SafariViewService", @"com.google.chrome.ios", @"org.mozilla.ios.Firefox", @"com.brave.ios.browser", @"com.duckduckgo.mobile.ios"];
            if ([browsers containsObject:self.targetID]) return @YES;
        }
        return @NO; 
    }
    return rules[featureKey];
}
- (void)setFeatureValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *featureKey = [specifier propertyForKey:@"featureKey"];
    if (![AntiDarkSwordAppController isApplicableFeature:featureKey forTarget:self.targetID]) return; 
    NSUserDefaults *defaults = ads_defaults(); NSString *dictKey = [NSString stringWithFormat:@"TargetRules_%@", self.targetID];
    NSMutableDictionary *rules = [[defaults dictionaryForKey:dictKey] mutableCopy] ?: [NSMutableDictionary dictionary]; rules[featureKey] = value;
    
    if ([featureKey isEqualToString:@"disableJS"]) {
        BOOL isIOS16 = ads_is_ios16();
        if ([value boolValue]) {
            // Save pre-lock JIT state so it can be restored when JS is toggled back off.
            if (isIOS16 && [AntiDarkSwordAppController isApplicableFeature:@"disableJIT" forTarget:self.targetID]) {
                if (rules[@"disableJIT_savedBeforeJS"] == nil) rules[@"disableJIT_savedBeforeJS"] = rules[@"disableJIT"] ?: @NO;
                rules[@"disableJIT"] = @YES;
            } else if (!isIOS16 && [AntiDarkSwordAppController isApplicableFeature:@"disableJIT15" forTarget:self.targetID]) {
                if (rules[@"disableJIT15_savedBeforeJS"] == nil) rules[@"disableJIT15_savedBeforeJS"] = rules[@"disableJIT15"] ?: @NO;
                rules[@"disableJIT15"] = @YES;
            }
        } else {
            // Restore saved state rather than blanket-resetting to OFF.
            if (isIOS16) {
                rules[@"disableJIT"] = rules[@"disableJIT_savedBeforeJS"] ?: @NO;
                [rules removeObjectForKey:@"disableJIT_savedBeforeJS"];
                if (![rules[@"disableJIT"] boolValue]) rules[@"disableMedia"] = @NO;
            } else {
                rules[@"disableJIT15"] = rules[@"disableJIT15_savedBeforeJS"] ?: @NO;
                [rules removeObjectForKey:@"disableJIT15_savedBeforeJS"];
                if (![rules[@"disableJIT15"] boolValue]) rules[@"disableMedia"] = @NO;
            }
        }
        [defaults setObject:rules forKey:dictKey]; ads_cfwrite(dictKey, rules); ads_flag_pending_changes(NO); [defaults synchronize];
        dispatch_async(dispatch_get_main_queue(), ^{ self->_specifiers = nil; [self reloadSpecifiers]; }); ads_post_notification(); return;
    }
    [defaults setObject:rules forKey:dictKey]; ads_cfwrite(dictKey, rules); ads_flag_pending_changes(NO); [defaults synchronize]; ads_post_notification();
}
@end


@implementation AntiDarkSwordPrefsRootListController
- (void)viewWillDisappear:(BOOL)animated { [super viewWillDisappear:animated]; ads_cancel_unconfirmed(self); }
- (void)reloadSpecifiers {
    self.cachedDisabledPresetRules = [ads_defaults() arrayForKey:@"disabledPresetRules"] ?: @[];
    self.cachedActiveCustomDaemons = [ads_defaults() arrayForKey:@"activeCustomDaemonIDs"] ?: [ads_defaults() arrayForKey:@"customDaemonIDs"] ?: @[];
    _specifiers = nil;
    [super reloadSpecifiers];
}
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    ads_present_pending_error(self);
    [[ADSUpdateChecker sharedChecker] checkForController:self
        installedVersion:ADSInstalledPreferencesVersion([AntiDarkSwordPrefsRootListController class])
        manual:NO finished:nil];
}

- (void)checkForUpdates {
    if (self.updateCheckInProgress) return;
    self.updateCheckInProgress = YES;
    PSSpecifier *row = [self specifierForID:@"CheckUpdates"];
    [row setProperty:@NO forKey:@"enabled"];
    [self reloadSpecifier:row];
    __weak typeof(self) weakSelf = self;
    [[ADSUpdateChecker sharedChecker] checkForController:self
        installedVersion:ADSInstalledPreferencesVersion([AntiDarkSwordPrefsRootListController class])
        manual:YES finished:^{
            typeof(self) controller = weakSelf;
            controller.updateCheckInProgress = NO;
            PSSpecifier *currentRow = [controller specifierForID:@"CheckUpdates"];
            [currentRow setProperty:@YES forKey:@"enabled"];
            if (currentRow) [controller reloadSpecifier:currentRow];
        }];
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated]; NSUserDefaults *defaults = ads_defaults();
    self.cachedDisabledPresetRules = [defaults arrayForKey:@"disabledPresetRules"] ?: @[]; self.cachedActiveCustomDaemons = [defaults arrayForKey:@"activeCustomDaemonIDs"] ?: [defaults arrayForKey:@"customDaemonIDs"] ?: @[];
    [self reloadSpecifiers];
}
- (BOOL)isTargetInstalled:(NSString *)targetID {
    NSArray *coreServices = @[@"com.apple.imagent", @"com.apple.apsd", @"com.apple.identityservicesd", @"com.apple.IMDPersistenceAgent", @"com.apple.SafariViewService", @"com.apple.MailCompositionService", @"com.apple.iMessageAppsViewService", @"com.apple.ActivityMessagesApp", @"com.apple.quicklook.QuickLookUIService", @"com.apple.QuickLookDaemon", @"imagent", @"apsd", @"identityservicesd", @"IMDPersistenceAgent"];
    if ([coreServices containsObject:targetID]) return YES;
    if (![targetID containsString:@"."] && ![targetID isEqualToString:@"pinterest"]) return YES; 
    @try {
        Class LSAppWorkspace = NSClassFromString(@"LSApplicationWorkspace");
        if (LSAppWorkspace) { LSApplicationWorkspace *workspace = [LSAppWorkspace defaultWorkspace]; if (workspace && [workspace respondsToSelector:@selector(applicationIsInstalled:)]) if ([workspace applicationIsInstalled:targetID]) return YES; }
    } @catch (NSException *e) {}
    @try {
        Class LSAppProxy = NSClassFromString(@"LSApplicationProxy");
        if (LSAppProxy) { LSApplicationProxy *proxy = [LSAppProxy applicationProxyForIdentifier:targetID]; if (proxy && [proxy respondsToSelector:@selector(bundleURL)]) { NSURL *bundleURL = [proxy bundleURL]; if (bundleURL && [[NSFileManager defaultManager] fileExistsAtPath:bundleURL.path]) return YES; } }
    } @catch (NSException *e) {}
    return NO;
}
- (NSString *)displayNameForTargetID:(NSString *)targetID {
    NSDictionary *knownNames = @{ @"imagent": @"iMessage Agent", @"apsd": @"Apple Push Service", @"identityservicesd": @"Identity Services", @"IMDPersistenceAgent": @"iMessage Persistence Agent", @"com.google.Gmail": @"Gmail", @"com.microsoft.Office.Outlook": @"Outlook", @"com.tinyspeck.chatlyio": @"Slack", @"com.microsoft.skype.teams": @"Microsoft Teams", @"com.google.chrome.ios": @"Chrome", @"com.brave.ios.browser": @"Brave", @"com.tumblr.tumblr": @"Tumblr", @"com.yahoo.Aerogram": @"Yahoo Mail", @"ch.protonmail.protonmail": @"Proton Mail", @"org.whispersystems.signal": @"Signal", @"ph.telegra.Telegraph": @"Telegram", @"com.facebook.Messenger": @"Messenger", @"com.toyopagroup.picaboo": @"Snapchat", @"com.tencent.xin": @"WeChat", @"com.viber": @"Viber", @"jp.naver.line": @"LINE", @"net.whatsapp.WhatsApp": @"WhatsApp", @"com.hammerandchisel.discord": @"Discord", @"com.google.GoogleMobile": @"Google", @"org.mozilla.ios.Firefox": @"Firefox", @"com.duckduckgo.mobile.ios": @"DuckDuckGo", @"pinterest": @"Pinterest", @"com.facebook.Facebook": @"Facebook", @"com.atebits.Tweetie2": @"X (Twitter)", @"com.burbn.instagram": @"Instagram", @"com.zhiliaoapp.musically": @"TikTok", @"com.linkedin.LinkedIn": @"LinkedIn", @"com.reddit.Reddit": @"Reddit", @"com.google.ios.youtube": @"YouTube", @"tv.twitch": @"Twitch", @"com.google.gemini": @"Google Gemini", @"com.openai.chat": @"ChatGPT", @"com.deepseek.chat": @"DeepSeek", @"com.github.stormbreaker.prod": @"GitHub", @"org.coolstar.SileoStore": @"Sileo", @"xyz.willy.Zebra": @"Zebra", @"com.tigisoftware.Filza": @"Filza", @"com.apple.Passbook": @"Apple Wallet", @"com.squareup.cash": @"Cash App", @"net.kortina.labs.Venmo": @"Venmo", @"com.yourcompany.PPClient": @"PayPal", @"com.robinhood.release.Robinhood": @"Robinhood", @"com.vilcsak.bitcoin2": @"Coinbase", @"com.sixdays.trust": @"Trust Wallet", @"io.metamask.MetaMask": @"MetaMask", @"app.phantom.phantom": @"Phantom", @"com.chase": @"Chase", @"com.bankofamerica.BofAMobileBanking": @"Bank of America", @"com.wellsfargo.net.mobilebanking": @"Wells Fargo", @"com.citi.citimobile": @"Citi", @"com.capitalone.enterprisemobilebanking": @"Capital One", @"com.americanexpress.amelia": @"Amex", @"com.fidelity.iphone": @"Fidelity", @"com.schwab.mobile": @"Charles Schwab", @"com.etrade.mobilepro.iphone": @"E*TRADE", @"com.discoverfinancial.mobile": @"Discover", @"com.usbank.mobilebanking": @"U.S. Bank", @"com.monzo.ios": @"Monzo", @"com.revolut.iphone": @"Revolut", @"com.binance.dev": @"Binance", @"com.kraken.invest": @"Kraken", @"com.barclays.ios.bmb": @"Barclays", @"com.ally.auto": @"Ally", @"com.navyfederal.navyfederal.mydata": @"Navy Federal", @"com.1debit.ChimeProdApp": @"Chime" };
    if (knownNames[targetID]) return knownNames[targetID];
    if (![targetID containsString:@"."] && ![targetID isEqualToString:@"pinterest"]) return targetID; 
    NSArray *daemons = @[@"com.apple.imagent", @"com.apple.apsd", @"com.apple.identityservicesd", @"com.apple.IMDPersistenceAgent", @"com.apple.SafariViewService", @"com.apple.MailCompositionService", @"com.apple.iMessageAppsViewService", @"com.apple.ActivityMessagesApp", @"com.apple.quicklook.QuickLookUIService", @"com.apple.QuickLookDaemon"];
    if ([daemons containsObject:targetID]) return targetID;
    @try {
        Class LSAppProxy = NSClassFromString(@"LSApplicationProxy");
        if (LSAppProxy) { id proxy = [LSAppProxy applicationProxyForIdentifier:targetID]; if (proxy && [proxy respondsToSelector:@selector(localizedName)]) { NSString *name = [proxy localizedName]; if (name && name.length > 0) return name; } }
    } @catch (NSException *e) {}
    return targetID;
}
- (UIImage *)iconForTargetID:(NSString *)targetID {
    UIImage *icon = nil;
    if ([targetID containsString:@"."] || [targetID isEqualToString:@"pinterest"]) {
        NSArray *daemons = @[@"com.apple.imagent", @"com.apple.apsd", @"com.apple.identityservicesd", @"com.apple.IMDPersistenceAgent", @"com.apple.SafariViewService", @"com.apple.MailCompositionService", @"com.apple.iMessageAppsViewService", @"com.apple.ActivityMessagesApp", @"com.apple.quicklook.QuickLookUIService", @"com.apple.QuickLookDaemon", @"imagent", @"apsd", @"identityservicesd", @"IMDPersistenceAgent"];
        if (![daemons containsObject:targetID]) { @try { if ([UIImage respondsToSelector:@selector(_applicationIconImageForBundleIdentifier:format:scale:)]) icon = [UIImage _applicationIconImageForBundleIdentifier:targetID format:29 scale:[UIScreen mainScreen].scale]; } @catch (NSException *e) {} }
    }
    if (!icon) {
        if (@available(iOS 13.0, *)) { icon = [UIImage systemImageNamed:@"gearshape.fill"]; icon = [icon imageWithTintColor:[UIColor systemGrayColor] renderingMode:UIImageRenderingModeAlwaysOriginal]; }
    }
    if (icon) {
        CGSize newSize = CGSizeMake(23, 23); UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:newSize]; return [renderer imageWithActions:^(UIGraphicsImageRendererContext *ctx) { [icon drawInRect:CGRectMake(0, 0, newSize.width, newSize.height)]; }];
    }
    return nil;
}
- (void)populateDefaultRulesForLevel:(NSInteger)level force:(BOOL)force {
    NSMutableDictionary *changes = [NSMutableDictionary dictionary];
    [self populateDefaultRulesForLevel:level force:force changes:changes];
    if (changes.count) ads_write_preferences(changes);
}
- (void)populateDefaultRulesForLevel:(NSInteger)level force:(BOOL)force changes:(NSMutableDictionary *)changes {
    NSUserDefaults *defaults = ads_defaults();
    if (!force && [defaults boolForKey:@"hasInitializedDefaultRules"]) {
        // One-time migration for existing installs: write restrictedApps-{pluginBundleID}=YES
        // for any plugin that already has non-trivial TargetRules_ entries but is missing
        // its enable key (written by prior builds that predated this logic).
        if (![defaults boolForKey:@"ADSPluginEnablesMigrated_v1"]) {
            NSMutableArray *allTargets = [NSMutableArray arrayWithArray:[self autoProtectedItemsForLevel:3]];
            [allTargets addObjectsFromArray:@[@"com.apple.imagent", @"imagent",
                @"com.apple.apsd", @"apsd", @"com.apple.identityservicesd", @"identityservicesd",
                @"com.apple.IMDPersistenceAgent", @"IMDPersistenceAgent"]];
            for (NSString *parentID in allTargets) {
                for (NSDictionary *plugin in ads_plugins_for_bundle_id(parentID)) {
                    NSString *pluginBundleID = plugin[@"bundleID"];
                    NSDictionary *existingRules = [defaults dictionaryForKey:
                        [NSString stringWithFormat:@"TargetRules_%@", pluginBundleID]];
                    if (!existingRules) continue;
                    BOOL hasNonTrivial = [existingRules[@"blockRemoteContent"] boolValue] ||
                                         [existingRules[@"blockRiskyAttachments"] boolValue] ||
                                         [existingRules[@"disableMedia"] boolValue];
                    if (!hasNonTrivial) continue;
                    NSString *enableKey = [NSString stringWithFormat:@"restrictedApps-%@", pluginBundleID];
                    if ([defaults objectForKey:enableKey]) continue;
                    changes[enableKey] = @YES;
                }
            }
            changes[@"ADSPluginEnablesMigrated_v1"] = @YES;
        }
        return;
    }
    BOOL isIOS16 = ads_is_ios16();
    NSArray *browsers = @[@"com.apple.mobilesafari", @"com.apple.SafariViewService", @"com.google.chrome.ios", @"org.mozilla.ios.Firefox", @"com.brave.ios.browser", @"com.duckduckgo.mobile.ios"];
    NSArray *msgAndMail = ads_msg_and_mail_apps(); NSArray *allProtected = [self autoProtectedItemsForLevel:3];
    NSSet *mailOnlyApps = [NSSet setWithObjects:@"com.apple.mobilemail", @"com.apple.MailCompositionService", @"com.google.Gmail", @"com.microsoft.Office.Outlook", @"com.yahoo.Aerogram", @"ch.protonmail.protonmail", nil];
    NSMutableArray *expandedTargets = [NSMutableArray arrayWithArray:allProtected]; [expandedTargets addObjectsFromArray:@[@"com.apple.imagent", @"imagent", @"com.apple.apsd", @"apsd", @"com.apple.identityservicesd", @"identityservicesd", @"com.apple.IMDPersistenceAgent", @"IMDPersistenceAgent"]];

    for (NSString *targetID in expandedTargets) {
        NSString *dictKey = [NSString stringWithFormat:@"TargetRules_%@", targetID]; if (!force && [defaults objectForKey:dictKey]) continue;
        NSMutableDictionary *rules = [NSMutableDictionary dictionary];
        rules[@"disableJIT"] = (isIOS16 && [AntiDarkSwordAppController isApplicableFeature:@"disableJIT" forTarget:targetID]) ? @YES : @NO; 
        rules[@"disableJIT15"] = (!isIOS16 && [AntiDarkSwordAppController isApplicableFeature:@"disableJIT15" forTarget:targetID]) ? @YES : @NO; 
        rules[@"disableJS"] = (!isIOS16 && [AntiDarkSwordAppController isApplicableFeature:@"disableJS" forTarget:targetID]) ? @YES : @NO; 
        rules[@"disableMedia"] = @NO; rules[@"disableRTC"] = @NO; rules[@"disableFileAccess"] = @NO; rules[@"disableIMessageDL"] = @NO; rules[@"spoofUA"] = @NO; rules[@"blockRemoteContent"] = @NO; rules[@"blockRiskyAttachments"] = @NO;

        if ([msgAndMail containsObject:targetID]) {
            rules[@"disableMedia"] = [AntiDarkSwordAppController isApplicableFeature:@"disableMedia" forTarget:targetID] ? @YES : @NO;
            rules[@"disableRTC"] = [AntiDarkSwordAppController isApplicableFeature:@"disableRTC" forTarget:targetID] ? @YES : @NO;
            rules[@"disableFileAccess"] = [AntiDarkSwordAppController isApplicableFeature:@"disableFileAccess" forTarget:targetID] ? @YES : @NO;
            rules[@"disableIMessageDL"] = [AntiDarkSwordAppController isApplicableFeature:@"disableIMessageDL" forTarget:targetID] ? @YES : @NO;
            // Mail apps at L1/L2: blockRemoteContent=NO (too aggressive for normal email flow).
            // Non-mail messaging apps: YES at all levels. All messaging/mail at L3: YES + risky attachments.
            BOOL isMailApp = [mailOnlyApps containsObject:targetID];
            rules[@"blockRemoteContent"] = (level >= 3 || !isMailApp) ? @YES : @NO;
            rules[@"blockRiskyAttachments"] = (level >= 3) ? @YES : @NO;
            if (![targetID hasPrefix:@"com.apple."]) rules[@"spoofUA"] = (level >= 2) ? @YES : @NO;
        } else if ([browsers containsObject:targetID]) {
            if ([targetID isEqualToString:@"com.apple.mobilesafari"] || [targetID isEqualToString:@"com.apple.SafariViewService"]) rules[@"spoofUA"] = @YES; else rules[@"spoofUA"] = (level >= 2) ? @YES : @NO;
            if (level >= 3) { rules[@"disableRTC"] = @YES; }
        } else if (![AntiDarkSwordAppController isDaemonTarget:targetID]) {
            if (![targetID hasPrefix:@"com.apple."]) rules[@"spoofUA"] = (level >= 2) ? @YES : @NO;
        }
        changes[dictKey] = rules;
    }
    // Populate default rules for security-relevant plugins of all protected parent apps.
    // Plugin defaults follow the parent's risk profile: NSEs and notification content extensions
    // are attachment delivery vectors; share extensions receive arbitrary share-sheet content.
    for (NSString *parentID in expandedTargets) {
        NSArray<NSDictionary *> *plugins = ads_plugins_for_bundle_id(parentID);
        for (NSDictionary *plugin in plugins) {
            NSString *pluginBundleID = plugin[@"bundleID"];
            NSString *category       = plugin[@"category"];
            NSString *pluginKey      = [NSString stringWithFormat:@"TargetRules_%@", pluginBundleID];
            if (!force && [defaults objectForKey:pluginKey]) continue;

            NSMutableDictionary *pluginRules = [NSMutableDictionary dictionary];
            // JIT rules match non-daemon apps; extensions can host WKWebViews.
            pluginRules[@"disableJIT"]        = (isIOS16) ? @YES : @NO;
            pluginRules[@"disableJIT15"]      = (!isIOS16) ? @YES : @NO;
            pluginRules[@"disableJS"]         = (!isIOS16) ? @YES : @NO;
            pluginRules[@"disableMedia"]      = @NO;
            pluginRules[@"disableRTC"]        = @NO;
            pluginRules[@"disableFileAccess"] = @NO;
            // IMFileTransfer hook is Messages UI-layer only; never applicable to extension processes.
            pluginRules[@"disableIMessageDL"] = @NO;
            // UA spoofing is not useful in extension contexts (no visible browser UA surface).
            pluginRules[@"spoofUA"]           = @NO;
            pluginRules[@"blockRemoteContent"]    = @NO;
            pluginRules[@"blockRiskyAttachments"] = @NO;

            BOOL parentIsMessagingOrMail = [msgAndMail containsObject:parentID] ||
                                           [parentID isEqualToString:@"com.apple.mobilemail"];
            BOOL parentIsMailOnly = [mailOnlyApps containsObject:parentID];
            // Level-aware: mail app plugins get blockRemoteContent=NO at L1/L2 (mirrors parent).
            // Non-mail messaging plugins get YES at all levels. All get YES at L3.
            BOOL pluginBlockRC = parentIsMessagingOrMail && (level >= 3 || !parentIsMailOnly);
            BOOL pluginBlockRA = level >= 3 && parentIsMessagingOrMail;

            if ([category isEqualToString:@"com.apple.usernotifications.service"] ||
                [category isEqualToString:@"com.apple.usernotifications.content-extension"]) {
                // NSEs and notification content extensions are the primary silent-delivery surface.
                pluginRules[@"blockRemoteContent"]    = pluginBlockRC ? @YES : @NO;
                pluginRules[@"blockRiskyAttachments"] = pluginBlockRA ? @YES : @NO;
                pluginRules[@"disableMedia"]          = parentIsMessagingOrMail ? @YES : @NO;
            } else if ([category isEqualToString:@"com.apple.share-services"]) {
                // Share extensions for messaging/mail apps receive user-forwarded content.
                pluginRules[@"blockRemoteContent"]    = pluginBlockRC ? @YES : @NO;
                pluginRules[@"blockRiskyAttachments"] = pluginBlockRA ? @YES : @NO;
            } else if ([category isEqualToString:@"com.apple.message-payload-provider"]) {
                // iMessage app extensions run inside the Messages compose/view context.
                pluginRules[@"blockRemoteContent"]    = pluginBlockRC ? @YES : @NO;
                pluginRules[@"blockRiskyAttachments"] = pluginBlockRA ? @YES : @NO;
            }

            changes[pluginKey] = pluginRules;

            // If the plugin has non-trivial category-specific mitigations, initialize
            // Enable Rule = ON so the UI shows an active override rather than contradicting
            // the disabled-toggles state. Plugins without meaningful overrides start with
            // Enable Rule = OFF, meaning pure parent inheritance (tweak falls back to
            // TargetRules_{parentBundleID} when restrictedApps-{pluginID} is absent).
            BOOL hasNonTrivialOverride = [pluginRules[@"blockRemoteContent"] boolValue] ||
                                         [pluginRules[@"blockRiskyAttachments"] boolValue] ||
                                         [pluginRules[@"disableMedia"] boolValue];
            if (hasNonTrivialOverride) {
                NSString *enableKey = [NSString stringWithFormat:@"restrictedApps-%@", pluginBundleID];
                changes[enableKey] = @YES;
            }
        }
    }

    changes[@"hasInitializedDefaultRules"] = @YES;
}
- (NSArray *)autoProtectedItemsForLevel:(NSInteger)level {
    NSMutableArray *items = [NSMutableArray array];
    NSArray *tier1 = @[@"com.apple.mobilesafari", @"com.apple.MobileSMS", @"com.apple.mobilemail", @"com.apple.mobilenotes", @"com.apple.iBooks", @"com.apple.news", @"com.apple.podcasts", @"com.apple.stocks", @"com.apple.SafariViewService", @"com.apple.MailCompositionService", @"com.apple.iMessageAppsViewService", @"com.apple.ActivityMessagesApp", @"com.apple.quicklook.QuickLookUIService", @"com.apple.QuickLookDaemon"];
    NSArray *tier2ThirdParty = @[@"com.google.Gmail", @"com.microsoft.Office.Outlook", @"com.yahoo.Aerogram", @"ch.protonmail.protonmail", @"org.whispersystems.signal", @"ph.telegra.Telegraph", @"com.facebook.Messenger", @"com.toyopagroup.picaboo", @"com.tinyspeck.chatlyio", @"com.microsoft.skype.teams", @"com.tencent.xin", @"com.viber", @"jp.naver.line", @"net.whatsapp.WhatsApp", @"com.hammerandchisel.discord", @"com.google.GoogleMobile", @"com.google.chrome.ios", @"org.mozilla.ios.Firefox", @"com.brave.ios.browser", @"com.duckduckgo.mobile.ios", @"pinterest", @"com.tumblr.tumblr", @"com.facebook.Facebook", @"com.atebits.Tweetie2", @"com.burbn.instagram", @"com.zhiliaoapp.musically", @"com.linkedin.LinkedIn", @"com.reddit.Reddit", @"com.google.ios.youtube", @"tv.twitch", @"com.google.gemini", @"com.openai.chat", @"com.deepseek.chat", @"com.github.stormbreaker.prod", @"com.squareup.cash", @"net.kortina.labs.Venmo", @"com.yourcompany.PPClient", @"com.robinhood.release.Robinhood", @"com.vilcsak.bitcoin2", @"com.sixdays.trust", @"io.metamask.MetaMask", @"app.phantom.phantom", @"com.chase", @"com.bankofamerica.BofAMobileBanking", @"com.wellsfargo.net.mobilebanking", @"com.citi.citimobile", @"com.capitalone.enterprisemobilebanking", @"com.americanexpress.amelia", @"com.fidelity.iphone", @"com.schwab.mobile", @"com.etrade.mobilepro.iphone", @"com.discoverfinancial.mobile", @"com.usbank.mobilebanking", @"com.monzo.ios", @"com.revolut.iphone", @"com.binance.dev", @"com.kraken.invest", @"com.barclays.ios.bmb", @"com.ally.auto", @"com.navyfederal.navyfederal.mydata", @"com.1debit.ChimeProdApp"];
    NSArray *sortedTier2 = [tier2ThirdParty sortedArrayUsingComparator:^NSComparisonResult(id a, id b) { return [[self displayNameForTargetID:a] caseInsensitiveCompare:[self displayNameForTargetID:b]]; }];
    NSArray *tier2JB = @[ @"org.coolstar.SileoStore", @"xyz.willy.Zebra", @"com.tigisoftware.Filza" ];
    
    [items addObjectsFromArray:tier1]; if (level >= 2) { [items addObjectsFromArray:sortedTier2]; [items addObjectsFromArray:tier2JB]; }
    return items;
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [super tableView:tableView cellForRowAtIndexPath:indexPath]; 
    PSSpecifier *spec = [self specifierAtIndexPath:indexPath]; 
    if (spec->action == @selector(resetToDefaults)) { 
        if (@available(iOS 13.0, *)) cell.textLabel.textColor = [UIColor systemRedColor]; 
        else cell.textLabel.textColor = [UIColor redColor]; 
    }
    if (spec->action == @selector(presentDonationMenu)) {
        if (@available(iOS 13.0, *)) cell.textLabel.textColor = [UIColor systemGreenColor]; 
        else cell.textLabel.textColor = [UIColor greenColor];
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
        NSString *targetID = [spec propertyForKey:@"targetID"]; NSInteger ruleType = [ruleTypeObj integerValue]; BOOL isEnabled = YES;
        if (ruleType == 0) { isEnabled = ![(self.cachedDisabledPresetRules ?: @[]) containsObject:targetID]; }
        else if (ruleType == 2) { isEnabled = [(self.cachedActiveCustomDaemons ?: @[]) containsObject:targetID]; }
        cell.backgroundColor = isEnabled ? ads_color_green() : ads_color_red();
    } else { if (@available(iOS 13.0, *)) cell.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor]; else cell.backgroundColor = [UIColor whiteColor]; }
    return cell;
}
- (NSArray *)specifiers {
    if (!_specifiers) {
        NSMutableArray *specs = [[self loadSpecifiersFromPlistName:@"Root" target:self] mutableCopy]; NSUserDefaults *defaults = ads_defaults();
        NSString *selectedUA = [defaults stringForKey:@"selectedUAPreset"];
        if (!selectedUA || [selectedUA isEqualToString:@"NONE"]) { selectedUA = @"Mozilla/5.0 (iPhone; CPU iPhone OS 18_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"; [defaults setObject:selectedUA forKey:@"selectedUAPreset"]; [defaults synchronize]; }
        if (![selectedUA isEqualToString:@"CUSTOM"]) {
            for (int i = 0; i < specs.count; i++) { PSSpecifier *s = specs[i]; if ([[s propertyForKey:@"id"] isEqualToString:@"CustomUATextField"]) { [specs removeObjectAtIndex:i]; break; } }
        }
        NSInteger autoProtectLevel = [defaults objectForKey:@"autoProtectLevel"] ? [defaults integerForKey:@"autoProtectLevel"] : 1; NSArray *customIDs = [defaults objectForKey:@"customDaemonIDs"] ?: @[];
        
        for (PSSpecifier *s in specs) {
            if ([[s propertyForKey:@"id"] isEqualToString:@"CheckUpdates"]) [s setProperty:@(!self.updateCheckInProgress) forKey:@"enabled"];
            if ([[s propertyForKey:@"id"] isEqualToString:@"SelectApps"]) s.detailControllerClass = [AntiDarkSwordAltListController class];
            if ([s.identifier isEqualToString:@"PresetRulesGroup"]) {
                NSString *footerText = @"";
                if (autoProtectLevel == 1) footerText = @"Level 1: Protects native Apple applications, including Safari, Messages, Mail, Notes, Calendar, Wallet, and other built-in iOS apps.";
                else if (autoProtectLevel == 2) footerText = @"Level 2: Expands protection to major 3rd-party web browsers, email clients, messaging platforms, social media apps, package managers, and finance/crypto apps.";
                else if (autoProtectLevel == 3) footerText = @"Level 3: Adds exploit mitigations for selected system daemons. Configure them in Level 3 Settings.";
                [s setProperty:footerText forKey:@"footerText"];
            }
            if ([[s propertyForKey:@"id"] isEqualToString:@"SystemOptionsCell"]) {
                if (autoProtectLevel < 3) { [s setProperty:@NO forKey:@"enabled"]; s.name = @"🔒  Level 3 Settings"; } else { [s setProperty:@YES forKey:@"enabled"]; s.name = @"⚙️  Level 3 Settings"; }
            }
            if ([[s propertyForKey:@"id"] isEqualToString:@"FooterGroup"]) {
                NSString *osVersion = [[UIDevice currentDevice] systemVersion];
                NSString *version = ADSInstalledPreferencesVersion([AntiDarkSwordPrefsRootListController class]) ?: @"Unavailable";
                NSString *jbType = @"Rootful";
#if defined(THEOS_PACKAGE_SCHEME_ROOTHIDE)
                jbType = @"Roothide";
#elif defined(THEOS_PACKAGE_SCHEME_ROOTLESS)
                jbType = @"Rootless";
#endif
                NSString *footerString = [NSString stringWithFormat:@"AntiDarkSword v%@ (iOS %@ %@)", version, osVersion, jbType];
                [s setProperty:footerString forKey:@"footerText"]; [s setProperty:@(1) forKey:@"footerAlignment"]; 
            }
        }
        NSUInteger insertIndexAuto = [specs indexOfObjectPassingTest:^BOOL(PSSpecifier *obj, NSUInteger idx, BOOL *stop) { return [[obj propertyForKey:@"id"] isEqualToString:@"AutoProtectLevelSegment"]; }];
        if (insertIndexAuto != NSNotFound) {
            insertIndexAuto++; PSSpecifier *groupSpec = [PSSpecifier preferenceSpecifierNamed:@"Current Preset Rules" target:self set:nil get:nil detail:nil cell:PSGroupCell edit:nil]; [specs insertObject:groupSpec atIndex:insertIndexAuto++];
            NSArray *autoItems = [self autoProtectedItemsForLevel:autoProtectLevel];
            for (NSString *item in autoItems) {
                if (![self isTargetInstalled:item]) continue; 
                NSString *displayName = [self displayNameForTargetID:item]; PSSpecifier *spec = [PSSpecifier preferenceSpecifierNamed:displayName target:self set:nil get:nil detail:[AntiDarkSwordAppController class] cell:PSLinkCell edit:nil];
                [spec setProperty:item forKey:@"targetID"]; [spec setProperty:@(0) forKey:@"ruleType"]; UIImage *icon = [self iconForTargetID:item]; if (icon) [spec setProperty:icon forKey:@"iconImage"];
                [specs insertObject:spec atIndex:insertIndexAuto++];
            }
        }
        NSUInteger insertIndexCustom = [specs indexOfObjectPassingTest:^BOOL(PSSpecifier *obj, NSUInteger idx, BOOL *stop) { return [[obj propertyForKey:@"id"] isEqualToString:@"AddCustomIDButton"]; }];
        if (insertIndexCustom != NSNotFound) {
            insertIndexCustom++;
            for (NSString *daemonID in customIDs) {
                NSString *displayName = [self displayNameForTargetID:daemonID]; PSSpecifier *spec = [PSSpecifier preferenceSpecifierNamed:displayName target:self set:nil get:nil detail:[AntiDarkSwordAppController class] cell:PSLinkCell edit:nil];
                [spec setProperty:daemonID forKey:@"targetID"]; [spec setProperty:daemonID forKey:@"daemonID"]; [spec setProperty:@(2) forKey:@"ruleType"]; [spec setProperty:@YES forKey:@"isCustomDaemon"];
                UIImage *icon = [self iconForTargetID:daemonID]; if (icon) [spec setProperty:icon forKey:@"iconImage"];
                [specs insertObject:spec atIndex:insertIndexCustom++];
            }
        }
        _specifiers = [specs copy];
    }
    return _specifiers;
}
- (void)viewDidLoad {
    [super viewDidLoad]; NSUserDefaults *defaults = ads_defaults();
    ads_migrate_prefs_if_needed();
    NSInteger currentLevel = [defaults objectForKey:@"autoProtectLevel"] ? [defaults integerForKey:@"autoProtectLevel"] : 1; [self populateDefaultRulesForLevel:currentLevel force:NO];
    UIBarButtonItem *saveButton = [[UIBarButtonItem alloc] initWithTitle:@"Save" style:UIBarButtonItemStyleDone target:self action:@selector(savePrompt)]; self.navigationItem.rightBarButtonItem = saveButton;
    BOOL needsRespring = [defaults boolForKey:@"ADSNeedsRespring"]; BOOL needsReboot = [defaults boolForKey:@"ADSPendingDaemonChanges"]; saveButton.enabled = needsRespring || needsReboot;
    ads_observe(self, "com.eolnmsuk.antidarkswordprefs/saved", NO); [self setupHeaderView];
}
- (void)setupHeaderView {
    NSBundle *bundle = [NSBundle bundleForClass:[self class]];
    NSString *imageName = @"banner";
    if (@available(iOS 13.0, *)) {
        if (self.traitCollection.userInterfaceStyle == UIUserInterfaceStyleLight) {
            NSString *lightPath = [bundle pathForResource:@"banner2" ofType:@"png"];
            if (lightPath) imageName = @"banner2";
        }
    }
    NSString *imagePath = [bundle pathForResource:imageName ofType:@"png"]; UIImage *bannerImage = [UIImage imageWithContentsOfFile:imagePath];
    if (bannerImage) {
        CGFloat screenWidth = [UIScreen mainScreen].bounds.size.width; CGFloat aspect = bannerImage.size.height / bannerImage.size.width; CGFloat height = screenWidth * aspect;
        UIView *headerView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, screenWidth, height)]; UIImageView *imageView = [[UIImageView alloc] initWithFrame:headerView.bounds]; imageView.image = bannerImage; imageView.contentMode = UIViewContentModeScaleAspectFill; imageView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight; imageView.clipsToBounds = YES; [headerView addSubview:imageView]; self.table.tableHeaderView = headerView;
    }
}
- (void)dealloc { ads_remove_observers(self); }
- (void)flagSaveRequirement {
    NSUserDefaults *defaults = ads_defaults(); ads_flag_pending_changes(NO); [defaults synchronize];
    BOOL needsRespring = [defaults boolForKey:@"ADSNeedsRespring"]; BOOL needsReboot = [defaults boolForKey:@"ADSPendingDaemonChanges"]; self.navigationItem.rightBarButtonItem.enabled = needsRespring || needsReboot;
}
- (void)setEnableProtection:(id)value specifier:(PSSpecifier *)specifier {
    NSUserDefaults *defaults = ads_defaults();
    BOOL enabled = [value boolValue];
    if (enabled == [defaults boolForKey:@"enabled"]) { [self reloadSpecifiers]; return; }
    NSArray *customDaemons = [defaults arrayForKey:@"activeCustomDaemonIDs"] ?: [defaults arrayForKey:@"customDaemonIDs"] ?: @[];
    BOOL needsReboot = [defaults boolForKey:@"ADSPendingDaemonChanges"] ||
        [defaults integerForKey:@"autoProtectLevel"] >= 3 || customDaemons.count > 0;
    // The switch's displayed proposal is staged behind Save; Cancel changes neither
    // store, either pending flag, nor the live service request.
    ads_present_save_prompt(self, @{@"enabled": @(enabled), @"ADSNeedsRespring": @YES,
                                  @"ADSPendingDaemonChanges": @(needsReboot)});
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    if (ads_settings_transaction) { [self reloadSpecifiers]; return; }
    NSString *key = [specifier propertyForKey:@"key"]; NSUserDefaults *defaults = ads_defaults();
    if ([key isEqualToString:@"customUAString"]) {
        NSString *input = (NSString *)value; NSString *trimmed = [input stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (trimmed.length == 0) { NSString *ios18UA = @"Mozilla/5.0 (iPhone; CPU iPhone OS 18_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"; value = ios18UA; [defaults setObject:ios18UA forKey:@"selectedUAPreset"]; ads_cfwrite(@"selectedUAPreset", ios18UA); [defaults synchronize]; dispatch_async(dispatch_get_main_queue(), ^{ self->_specifiers = nil; [self reloadSpecifiers]; }); }
    }
    [super setPreferenceValue:value specifier:specifier];
    if (key) ads_cfwrite(key, value);
    [self flagSaveRequirement];
    if ([key isEqualToString:@"selectedUAPreset"]) { _specifiers = nil; [self reloadSpecifiers]; }
}
- (void)setAutoProtectLevel:(id)value specifier:(PSSpecifier*)specifier {
    NSUserDefaults *defaults = ads_defaults();
    NSInteger oldLevel = [defaults integerForKey:@"autoProtectLevel"] ?: 1;
    NSInteger newLevel = [value integerValue];
    if (newLevel == oldLevel || newLevel < 1 || newLevel > 3) { [self reloadSpecifiers]; return; }
    ADSSettingsTransaction *transaction = ads_begin_transaction(self);
    if (!transaction) return;
    NSMutableDictionary *changes = [@{@"autoProtectLevel": @(newLevel)} mutableCopy];
    [self populateDefaultRulesForLevel:newLevel force:YES changes:changes];
    if (newLevel >= 3) {
        changes[@"corelliumDecoyEnabled"] = @YES;
        ads_restore_daemon_rules(changes);
    } else changes[@"corelliumDecoyEnabled"] = @NO;
    if ([defaults boolForKey:@"enabled"]) {
        changes[@"ADSNeedsRespring"] = @YES;
        if (oldLevel >= 3 || newLevel >= 3) changes[@"ADSPendingDaemonChanges"] = @YES;
    }
    ads_apply_configuration(transaction, changes);
}

- (void)addCustomID {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Add Custom ID" message:@"Enter bundle IDs or process names (comma-separated)" preferredStyle:UIAlertControllerStyleAlert]; [alert addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) { textField.placeholder = @"com.apple.imagent, apsd"; }]; [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]]; [alert addAction:[UIAlertAction actionWithTitle:@"Add" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        NSString *inputText = alert.textFields.firstObject.text;
        if (inputText.length > 0) {
            NSArray *inputIDs = [inputText componentsSeparatedByString:@","]; NSUserDefaults *defaults = ads_defaults(); NSMutableArray *customIDs = [[defaults objectForKey:@"customDaemonIDs"] ?: @[] mutableCopy]; NSMutableArray *activeCustom = [[defaults objectForKey:@"activeCustomDaemonIDs"] ?: customIDs mutableCopy]; BOOL changesMade = NO;
            for (NSString *rawID in inputIDs) { NSString *cleanID = [rawID stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]; if (cleanID.length > 0 && ![customIDs containsObject:cleanID]) { [customIDs addObject:cleanID]; if (![activeCustom containsObject:cleanID]) [activeCustom addObject:cleanID]; changesMade = YES; } }
            if (changesMade) { [defaults setObject:customIDs forKey:@"customDaemonIDs"]; [defaults setObject:activeCustom forKey:@"activeCustomDaemonIDs"]; ads_flag_pending_changes(YES); [defaults synchronize]; [self flagSaveRequirement]; _specifiers = nil; [self reloadSpecifiers]; ads_post_notification(); }
        }
    }]]; [self presentViewController:alert animated:YES completion:nil];
}
- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath { PSSpecifier *spec = [self specifierAtIndexPath:indexPath]; return [[spec propertyForKey:@"isCustomDaemon"] boolValue]; }
- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle == UITableViewCellEditingStyleDelete) {
        PSSpecifier *spec = [self specifierAtIndexPath:indexPath]; NSString *daemonID = [spec propertyForKey:@"daemonID"]; NSUserDefaults *defaults = ads_defaults(); NSMutableArray *customIDs = [[defaults objectForKey:@"customDaemonIDs"] ?: @[] mutableCopy]; NSMutableArray *activeCustom = [[defaults objectForKey:@"activeCustomDaemonIDs"] ?: customIDs mutableCopy];
        [customIDs removeObject:daemonID]; [activeCustom removeObject:daemonID]; NSString *dictKey = [NSString stringWithFormat:@"TargetRules_%@", daemonID]; [defaults removeObjectForKey:dictKey]; [defaults setObject:customIDs forKey:@"customDaemonIDs"]; [defaults setObject:activeCustom forKey:@"activeCustomDaemonIDs"]; ads_flag_pending_changes(YES); [defaults synchronize]; [self flagSaveRequirement]; [self removeSpecifier:spec animated:YES]; ads_post_notification();
    }
}
- (void)resetToDefaults {
    ADSSettingsTransaction *transaction = ads_begin_transaction(self);
    if (!transaction) return;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Reset to Defaults"
        message:@"Userspace reboot required to completely flush daemon hooks." preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
        ads_end_transaction(transaction);
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Reboot Userspace" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        if (ads_settings_transaction != transaction) return;
        ads_lock_transaction(transaction);
        ADSSetDecoyActive(NO, ^(ADSCommandResult *result) {
            if (ads_settings_transaction != transaction) return;
            if (!result.isSuccessful) {
                ads_fail_transaction(transaction, result, @"Reset was not applied. Previous settings were kept; no reboot was requested.");
                return;
            }
            NSUserDefaults *defaults = ads_defaults();
            CFStringRef appID = (__bridge CFStringRef)ADS_PREFS_SUITE;
            CFArrayRef keys = CFPreferencesCopyKeyList(appID, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
            [defaults removePersistentDomainForName:ADS_PREFS_SUITE];
            [defaults synchronize];
            if (keys) {
                CFPreferencesSetMultiple(NULL, keys, appID, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
                CFRelease(keys);
            }
            CFPreferencesSynchronize(appID, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
            ads_write_preferences(@{@"ADSNeedsRespring": @YES, @"ADSPendingDaemonChanges": @YES});
            ads_post_notification();
            ads_restart(transaction, YES);
        });
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)savePrompt { ads_present_save_prompt(self, nil); }
- (void)openGitHub { [[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"https://github.com/EolnMsuk/AntiDarkSword"] options:@{} completionHandler:nil]; }
- (void)presentDonationMenu {
    NSIndexPath *selected = self.table.indexPathForSelectedRow;
    UIView *anchor = selected ? [self.table cellForRowAtIndexPath:selected] : nil;
    ADSPresentDonationMenu(self, anchor);
}
@end
