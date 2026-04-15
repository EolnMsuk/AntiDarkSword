// AntiDarkSwordTF/Tweak.x
// TrollFools / TrollStore variant — single dylib, direct per-app injection.
//
// Key differences from the jailbreak tweak:
//   • No MobileSubstrate dependency — %hook compiles to pure ObjC runtime calls.
//   • No PreferenceLoader UI — settings are accessed via three-finger double-tap
//     overlay that writes directly to the shared prefs plist.
//   • No tier matching or process filtering — TrollFools puts the dylib in the
//     app the user chose; protections apply unconditionally.
//   • No daemon-layer hooks — injecting into imagent/apsd requires a jailbreak.
//   • JSEvaluateScript C-function hook is omitted (needs MSHookFunction / fishhook).
//     The WKWebpagePreferences and WKPreferences %hooks cover JS blocking at the
//     ObjC level, which is sufficient for attack-surface reduction.

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#import <JavaScriptCore/JavaScriptCore.h>
#import <CoreFoundation/CoreFoundation.h>
#include <unistd.h>
#include <stdatomic.h>

#import "../ADSLogging.h"

// =========================================================
// PRIVATE WEBKIT INTERFACES (JIT & LOCKDOWN MODE)
// =========================================================
@interface WKWebpagePreferences (Private)
@property (nonatomic, assign) BOOL lockdownModeEnabled;
@end

@interface _WKProcessPoolConfiguration : NSObject
@property (nonatomic, assign) BOOL JITEnabled;
@end

@interface WKProcessPool (Private)
@property (nonatomic, readonly) _WKProcessPoolConfiguration *_configuration;
@end

// =========================================================
// PREFERENCES
// Shares the same domain as the jailbreak tweak so settings
// written by the prefs bundle (if also installed) are honoured
// here without any extra plumbing.
// =========================================================
static BOOL isRootlessJB = NO;

static NSString *ads_prefs_path(void) {
    return isRootlessJB
        ? @"/var/jb/var/mobile/Library/Preferences/com.eolnmsuk.antidarkswordprefs.plist"
        : @"/var/mobile/Library/Preferences/com.eolnmsuk.antidarkswordprefs.plist";
}

// All mutable state is _Atomic: hooks can fire on any thread.
static _Atomic BOOL prefsLoaded            = NO;
static _Atomic BOOL shouldSpoofUA          = NO;
static _Atomic BOOL applyDisableJIT        = NO;
static _Atomic BOOL applyDisableJIT15      = NO;
static _Atomic BOOL applyDisableJS         = NO;
static _Atomic BOOL applyDisableMedia      = NO;
static _Atomic BOOL applyDisableRTC        = NO;
static _Atomic BOOL applyDisableFileAccess = NO;
// Written once per loadPrefs call, read from hooks on any thread.
// Safe under the prefsLoaded CAS gate — only one writer at a time.
static NSString *customUAString = nil;

// =========================================================
// HELPERS (identical to AntiDarkSwordUI)
// =========================================================

// Returns a properly JSON-encoded string literal including surrounding double quotes.
static NSString *adsJSONStringLiteral(NSString *str) {
    if (!str || str.length == 0) return @"\"\"";
    NSArray *wrapper = @[str];
    NSData  *data    = [NSJSONSerialization dataWithJSONObject:wrapper options:0 error:nil];
    if (!data) return @"\"\"";
    NSString *json = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (json.length >= 2)
        return [json substringWithRange:NSMakeRange(1, json.length - 2)];
    return @"\"\"";
}

static void injectUAScript(WKUserContentController *ucc) {
    if (!ucc || !shouldSpoofUA || !customUAString || customUAString.length == 0) return;
    ADSLog(@"[MITIGATION] Injecting UA spoof script. UA: %@", customUAString);

    NSString *jsonUA = adsJSONStringLiteral(customUAString);

    NSString *platform = @"\"iPhone\"";
    if ([customUAString containsString:@"iPad"])          platform = @"\"iPad\"";
    else if ([customUAString containsString:@"Macintosh"]) platform = @"\"MacIntel\"";
    else if ([customUAString containsString:@"Windows"])   platform = @"\"Win32\"";
    else if ([customUAString containsString:@"Android"])   platform = @"\"Linux aarch64\"";

    NSString *vendor = @"\"Apple Computer, Inc.\"";
    if ([customUAString containsString:@"Chrome"] || [customUAString containsString:@"Android"])
        vendor = @"\"Google Inc.\"";

    NSString *appVersion = customUAString;
    if ([customUAString hasPrefix:@"Mozilla/"]) appVersion = [customUAString substringFromIndex:8];
    NSString *jsonAppVersion = adsJSONStringLiteral(appVersion);

    NSString *jsSource = [NSString stringWithFormat:
        @"(function(){"
         "var d=Object.defineProperty,n=navigator;"
         "d(n,'userAgent',  {get:function(){return %@},configurable:true});"
         "d(n,'appVersion', {get:function(){return %@},configurable:true});"
         "d(n,'platform',   {get:function(){return %@},configurable:true});"
         "d(n,'vendor',     {get:function(){return %@},configurable:true});"
         "})();",
        jsonUA, jsonAppVersion, platform, vendor];

    WKUserScript *script = [[WKUserScript alloc]
        initWithSource:jsSource
         injectionTime:WKUserScriptInjectionTimeAtDocumentStart
      forMainFrameOnly:NO];
    [ucc addUserScript:script];
}

// =========================================================
// PREFERENCES I/O
// On a non-jailbroken TrollStore device the injected app is sandboxed and
// cannot write to /var/mobile/Library/Preferences/.  We try that path first
// (works for jailbroken users), then fall back to NSUserDefaults with a suite
// name, which always succeeds because it writes to the app's own container.
// =========================================================

// Suite name used as the NSUserDefaults fallback.
// NOT an app-group ID — NSUserDefaults writes it to the app's own container.
static NSString * const kADSTFSuite = @"com.eolnmsuk.antidarkswordprefs";

static NSDictionary *ads_read_prefs(void) {
    // 1. Try the shared system plist (jailbreak / unsandboxed TrollStore).
    NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:ads_prefs_path()];
    if (d) return d;

    // 2. Try CFPreferences (picks up prefs written by the jailbreak bundle).
    CFArrayRef keyList = CFPreferencesCopyKeyList((__bridge CFStringRef)kADSTFSuite,
                                                  kCFPreferencesCurrentUser,
                                                  kCFPreferencesAnyHost);
    if (keyList) {
        CFDictionaryRef dict = CFPreferencesCopyMultiple(keyList,
                                                         (__bridge CFStringRef)kADSTFSuite,
                                                         kCFPreferencesCurrentUser,
                                                         kCFPreferencesAnyHost);
        CFRelease(keyList);
        if (dict) return (__bridge_transfer NSDictionary *)dict;
    }

    // 3. Fall back to NSUserDefaults suite (sandboxed TrollFools app container).
    NSUserDefaults *ud = [[NSUserDefaults alloc] initWithSuiteName:kADSTFSuite];
    NSDictionary *all  = [ud dictionaryRepresentation];
    return (all && all.count > 0) ? all : nil;
}

static void ads_write_prefs(NSDictionary *prefs) {
    // 1. Try the shared system plist first.
    NSString *path = ads_prefs_path();
    NSString *dir  = [path stringByDeletingLastPathComponent];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir
                                withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    if ([prefs writeToFile:path atomically:YES]) return;

    // 2. Sandboxed fallback: NSUserDefaults suite in the app's own container.
    //    Wipes then rewrites so deleted keys don't linger.
    NSUserDefaults *ud = [[NSUserDefaults alloc] initWithSuiteName:kADSTFSuite];
    // Remove any keys not in the new dict (handles deletions / master disable).
    for (NSString *existing in [[ud dictionaryRepresentation] allKeys]) {
        if (!prefs[existing]) [ud removeObjectForKey:existing];
    }
    [prefs enumerateKeysAndObjectsUsingBlock:^(NSString *key, id obj, BOOL *stop) {
        [ud setObject:obj forKey:key];
    }];
    [ud synchronize];
}

// =========================================================
// PREFERENCES LOADING
// =========================================================

// Helper: read a BOOL from per-app rules → global prefs key → hardcoded default.
// All three layers are optional; the first one present wins.
static BOOL ads_read_bool(NSDictionary *rules,
                          NSDictionary *prefs,
                          NSString     *ruleKey,
                          NSString     *globalKey,
                          BOOL          defaultValue) {
    id ruleVal = rules[ruleKey];
    if (ruleVal && [ruleVal respondsToSelector:@selector(boolValue)])
        return [ruleVal boolValue];
    id globalVal = prefs[globalKey];
    if (globalVal && [globalVal respondsToSelector:@selector(boolValue)])
        return [globalVal boolValue];
    return defaultValue;
}

static void loadPrefs() {
    // Atomic compare-and-swap: only one caller loads at a time.
    // reloadPrefsNotification resets the flag before calling back in.
    BOOL expected = NO;
    if (!atomic_compare_exchange_strong(&prefsLoaded, &expected, YES)) return;

    // Read from whichever storage backend has data (system plist → CFPrefs → NSUserDefaults suite).
    NSDictionary *prefs = ads_read_prefs();

    // Master enable — default OFF so the dylib is dormant until the user
    // opts in via the three-finger overlay.
    BOOL masterEnabled = NO;
    id enabledVal = prefs[@"enabled"];
    if (enabledVal && [enabledVal respondsToSelector:@selector(boolValue)])
        masterEnabled = [enabledVal boolValue];

    if (!masterEnabled) {
        shouldSpoofUA = applyDisableJIT = applyDisableJIT15 = applyDisableJS =
            applyDisableMedia = applyDisableRTC = applyDisableFileAccess = NO;
        ADSLog(@"[STATUS] Tweak disabled via prefs.");
        return;
    }

    BOOL isIOS16 = [[NSProcessInfo processInfo] operatingSystemVersion].majorVersion >= 16;

    // Per-app rules from TargetRules_<bundleID> take priority over global keys.
    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier] ?: @"";
    NSString *dictKey  = [NSString stringWithFormat:@"TargetRules_%@", bundleID];
    NSDictionary *rules = ([prefs isKindOfClass:[NSDictionary class]]) ? prefs[dictKey] : nil;
    if (![rules isKindOfClass:[NSDictionary class]]) rules = nil;

    // Defaults when no prefs have been saved yet (first use after injection):
    //   UA spoof  → ON   (non-breaking, immediate privacy benefit)
    //   JIT       → ON   (low breakage, meaningful exploit-surface reduction)
    //   JS        → OFF  (breaks most apps; user must opt in)
    //   Media     → OFF  (user must opt in)
    //   WebRTC    → OFF  (breaks video/audio calls; user must opt in)
    //   File acc. → OFF  (user must opt in)
    applyDisableJIT        = isIOS16  ? ads_read_bool(rules, prefs, @"disableJIT",        @"globalDisableJIT",        YES) : NO;
    applyDisableJIT15      = !isIOS16 ? ads_read_bool(rules, prefs, @"disableJIT15",      @"globalDisableJIT15",      YES) : NO;
    applyDisableJS         =            ads_read_bool(rules, prefs, @"disableJS",         @"globalDisableJS",         NO);
    applyDisableMedia      =            ads_read_bool(rules, prefs, @"disableMedia",      @"globalDisableMedia",      NO);
    applyDisableRTC        =            ads_read_bool(rules, prefs, @"disableRTC",        @"globalDisableRTC",        NO);
    applyDisableFileAccess =            ads_read_bool(rules, prefs, @"disableFileAccess", @"globalDisableFileAccess", NO);

    // ---- User Agent Spoofing ----
    NSString *defaultUA = @"Mozilla/5.0 (iPhone; CPU iPhone OS 18_1 like Mac OS X) "
                           "AppleWebKit/605.1.15 (KHTML, like Gecko) "
                           "Version/18.0 Mobile/15E148 Safari/604.1";

    id presetRaw = prefs[@"selectedUAPreset"];
    NSString *selectedUA = [presetRaw isKindOfClass:[NSString class]] ? presetRaw : nil;
    if (!selectedUA || [selectedUA isEqualToString:@"NONE"]) selectedUA = defaultUA;

    if ([selectedUA isEqualToString:@"CUSTOM"]) {
        id manualRaw = prefs[@"customUAString"];
        NSString *manual = [manualRaw isKindOfClass:[NSString class]]
            ? [manualRaw stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]
            : @"";
        customUAString = manual.length > 0 ? manual : defaultUA;
    } else {
        customUAString = selectedUA;
    }

    // UA spoof active if: global override ON, or per-app rule ON, or no rule at all
    // (TrollFools users opted in explicitly — default ON is the right call).
    BOOL globalUA = NO;
    id globalUAVal = prefs[@"globalUASpoofingEnabled"];
    if (globalUAVal && [globalUAVal respondsToSelector:@selector(boolValue)])
        globalUA = [globalUAVal boolValue];

    BOOL uaRule = YES; // TrollFools default
    id uaRuleVal = rules[@"spoofUA"];
    if (uaRuleVal && [uaRuleVal respondsToSelector:@selector(boolValue)])
        uaRule = [uaRuleVal boolValue];

    shouldSpoofUA = (globalUA || uaRule) && customUAString.length > 0;

    ADSLog(@"[STATUS] TrollFools protection ACTIVE in %@. "
           "JIT:%d Media:%d RTC:%d FileAccess:%d UA:%d",
           bundleID,
           (int)applyDisableJIT, (int)applyDisableMedia, (int)applyDisableRTC,
           (int)applyDisableFileAccess, (int)shouldSpoofUA);
}

static void reloadPrefsNotification(void) {
    prefsLoaded = NO;
    loadPrefs();
}

// =========================================================
// WEBKIT EXPLOIT MITIGATIONS
// =========================================================

static void applyWebKitMitigations(WKWebViewConfiguration *configuration) {
    if (!configuration) return;

    if (applyDisableJS) {
        if ([configuration respondsToSelector:@selector(defaultWebpagePreferences)])
            configuration.defaultWebpagePreferences.allowsContentJavaScript = NO;
        if ([configuration.preferences respondsToSelector:@selector(setJavaScriptEnabled:)])
            configuration.preferences.javaScriptEnabled = NO;
        if ([configuration.preferences respondsToSelector:@selector(setJavaScriptCanOpenWindowsAutomatically:)])
            configuration.preferences.javaScriptCanOpenWindowsAutomatically = NO;
    }

    if (applyDisableJIT && [configuration respondsToSelector:@selector(defaultWebpagePreferences)]) {
        if ([configuration.defaultWebpagePreferences respondsToSelector:@selector(setLockdownModeEnabled:)])
            [(id)configuration.defaultWebpagePreferences setLockdownModeEnabled:YES];
    }

    if ((applyDisableJIT15 || applyDisableJIT) && [configuration respondsToSelector:@selector(processPool)]) {
        if ([configuration.processPool respondsToSelector:@selector(_configuration)]) {
            id poolConfig = [(id)configuration.processPool _configuration];
            if ([poolConfig respondsToSelector:@selector(setJITEnabled:)])
                [(id)poolConfig setJITEnabled:NO];
        }
    }

    if (applyDisableMedia) {
        if ([configuration respondsToSelector:@selector(setAllowsInlineMediaPlayback:)])
            configuration.allowsInlineMediaPlayback = NO;
        if ([configuration respondsToSelector:@selector(setMediaTypesRequiringUserActionForPlayback:)])
            configuration.mediaTypesRequiringUserActionForPlayback = WKAudiovisualMediaTypeAll;
        if ([configuration respondsToSelector:@selector(setAllowsPictureInPictureMediaPlayback:)])
            configuration.allowsPictureInPictureMediaPlayback = NO;
    }

    if ([configuration.preferences respondsToSelector:@selector(setValue:forKey:)]) {
        @try {
            if (applyDisableFileAccess) {
                [configuration.preferences setValue:@NO forKey:@"allowFileAccessFromFileURLs"];
                [configuration.preferences setValue:@NO forKey:@"allowUniversalAccessFromFileURLs"];
            }
            if (applyDisableRTC) {
                [configuration.preferences setValue:@NO forKey:@"webGLEnabled"];
                [configuration.preferences setValue:@NO forKey:@"mediaStreamEnabled"];
                [configuration.preferences setValue:@NO forKey:@"peerConnectionEnabled"];
            }
        } @catch (NSException *e) {}
    }

    if (shouldSpoofUA) injectUAScript(configuration.userContentController);
}

// =========================================================
// WEBKIT HOOKS
// =========================================================

%hook WKWebViewConfiguration

- (void)setUserContentController:(WKUserContentController *)userContentController {
    %orig;
    if (shouldSpoofUA && userContentController) injectUAScript(userContentController);
}

- (void)setApplicationNameForUserAgent:(NSString *)applicationNameForUserAgent {
    if (shouldSpoofUA) return %orig(@"");
    %orig;
}

%end

%hook WKWebView

- (instancetype)initWithFrame:(CGRect)frame configuration:(WKWebViewConfiguration *)configuration {
    applyWebKitMitigations(configuration);
    WKWebView *webView = %orig(frame, configuration);
    if (webView && shouldSpoofUA && [webView respondsToSelector:@selector(setCustomUserAgent:)])
        webView.customUserAgent = customUAString;
    return webView;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    WKWebView *webView = %orig(coder);
    if (!webView) return nil;
    applyWebKitMitigations(webView.configuration);
    if (shouldSpoofUA && [webView respondsToSelector:@selector(setCustomUserAgent:)])
        webView.customUserAgent = customUAString;
    return webView;
}

- (WKNavigation *)loadRequest:(NSURLRequest *)request {
    if (applyDisableJS) {
        if ([self.configuration respondsToSelector:@selector(defaultWebpagePreferences)])
            self.configuration.defaultWebpagePreferences.allowsContentJavaScript = NO;
        if ([self.configuration.preferences respondsToSelector:@selector(setJavaScriptEnabled:)])
            self.configuration.preferences.javaScriptEnabled = NO;
    }
    if (shouldSpoofUA) {
        if ([self respondsToSelector:@selector(setCustomUserAgent:)]) self.customUserAgent = customUAString;
        if ([request respondsToSelector:@selector(valueForHTTPHeaderField:)]) {
            NSString *existingUA = [request valueForHTTPHeaderField:@"User-Agent"];
            if (existingUA && ![existingUA isEqualToString:customUAString]) {
                NSMutableURLRequest *mutableReq = [request mutableCopy];
                [mutableReq setValue:customUAString forHTTPHeaderField:@"User-Agent"];
                return %orig(mutableReq);
            }
        }
    }
    return %orig;
}

- (WKNavigation *)loadHTMLString:(NSString *)string baseURL:(NSURL *)baseURL {
    if (applyDisableJS) {
        if ([self.configuration respondsToSelector:@selector(defaultWebpagePreferences)])
            self.configuration.defaultWebpagePreferences.allowsContentJavaScript = NO;
        if ([self.configuration.preferences respondsToSelector:@selector(setJavaScriptEnabled:)])
            self.configuration.preferences.javaScriptEnabled = NO;
    }
    if (shouldSpoofUA && [self respondsToSelector:@selector(setCustomUserAgent:)])
        self.customUserAgent = customUAString;
    return %orig;
}

- (void)evaluateJavaScript:(NSString *)javaScriptString completionHandler:(void (^)(id, NSError *))completionHandler {
    if (applyDisableJS) {
        if (completionHandler) {
            NSError *err = [NSError errorWithDomain:@"AntiDarkSword" code:1
                                           userInfo:@{NSLocalizedDescriptionKey: @"JS execution blocked"}];
            completionHandler(nil, err);
        }
        return;
    }
    %orig;
}

- (void)evaluateJavaScript:(NSString *)javaScriptString inFrame:(WKFrameInfo *)frame inContentWorld:(WKContentWorld *)contentWorld completionHandler:(void (^)(id, NSError *))completionHandler {
    if (applyDisableJS) {
        if (completionHandler) {
            NSError *err = [NSError errorWithDomain:@"AntiDarkSword" code:1
                                           userInfo:@{NSLocalizedDescriptionKey: @"JS execution blocked"}];
            completionHandler(nil, err);
        }
        return;
    }
    %orig;
}

- (void)setCustomUserAgent:(NSString *)customUserAgent {
    if (shouldSpoofUA) %orig(customUAString);
    else %orig;
}

%end

%hook WKWebpagePreferences
- (void)setAllowsContentJavaScript:(BOOL)allowed {
    if (applyDisableJS && allowed) return %orig(NO);
    %orig;
}
%end

%hook WKPreferences
- (void)setJavaScriptEnabled:(BOOL)enabled {
    if (applyDisableJS && enabled) return %orig(NO);
    %orig;
}
%end

// =========================================================
// LEGACY UIWebView NEUTRALIZATION
// =========================================================

%hook UIWebView
- (NSString *)stringByEvaluatingJavaScriptFromString:(NSString *)script {
    if (applyDisableJS) return @"";
    return %orig;
}
%end

// =========================================================
// IN-APP SETTINGS OVERLAY
// Three-finger double-tap on any screen → modal settings panel
// where the user can toggle per-app protections and save.
// =========================================================

static BOOL ads_gesture_installed = NO;

// Returns the current key window across UIWindowScene (iOS 13+) and legacy API.
static UIWindow *ads_key_window(void) {
    if (@available(iOS 13, *)) {
        for (UIWindowScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if (scene.activationState == UISceneActivationStateForegroundActive) {
                for (UIWindow *window in ((UIWindowScene *)scene).windows) {
                    if (window.isKeyWindow) return window;
                }
            }
        }
    }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    return [UIApplication sharedApplication].keyWindow;
#pragma clang diagnostic pop
}

// Returns the top-most presented view controller from a root.
static UIViewController *ads_top_vc(UIViewController *root) {
    while (root.presentedViewController) root = root.presentedViewController;
    return root;
}

// ---- Row model ----
// Each entry drives one table row.  The "enabled" key controls whether the row
// is interactive — grayed-out rows are shown but not actionable because the
// underlying API doesn't exist on this iOS version.
static NSArray<NSDictionary *> *ads_tf_setting_rows(void) {
    NSInteger major = [[NSProcessInfo processInfo] operatingSystemVersion].majorVersion;
    NSMutableArray *rows = [NSMutableArray array];

    // 1. Spoof User Agent — works on all versions.
    [rows addObject:@{@"title":   @"Spoof User Agent",
                      @"detail":  @"Masks the real browser fingerprint",
                      @"key":     @"spoofUA",
                      @"enabled": @YES}];

    // 2. Block JIT — mechanism differs by iOS version:
    //      iOS 16+  → WKWebpagePreferences lockdownModeEnabled  (reliable)
    //      iOS 15   → _WKProcessPoolConfiguration.JITEnabled    (private API, best-effort)
    //      iOS 14-  → neither API is available; show grayed row so the user
    //                 knows the option exists but can't be enabled here.
    if (major >= 16) {
        [rows addObject:@{@"title":   @"Block JIT / Lockdown Mode",
                          @"detail":  @"Enables WebKit lockdown mode (iOS 16+)",
                          @"key":     @"disableJIT",
                          @"enabled": @YES}];
    } else if (major >= 15) {
        [rows addObject:@{@"title":   @"Block JIT",
                          @"detail":  @"Disables JIT via pool config (iOS 15)",
                          @"key":     @"disableJIT15",
                          @"enabled": @YES}];
    } else {
        [rows addObject:@{@"title":   @"Block JIT",
                          @"detail":  @"Not available on iOS 14 and below",
                          @"key":     @"disableJIT15",
                          @"enabled": @NO}];
    }

    // 3–6. Features that work on all supported iOS versions.
    [rows addObject:@{@"title":   @"Block JavaScript",
                      @"detail":  @"Prevents JS execution in WebViews",
                      @"key":     @"disableJS",
                      @"enabled": @YES}];
    [rows addObject:@{@"title":   @"Block Media Autoplay",
                      @"detail":  @"Stops drive-by audio/video loading",
                      @"key":     @"disableMedia",
                      @"enabled": @YES}];
    [rows addObject:@{@"title":   @"Block WebGL / WebRTC",
                      @"detail":  @"Disables GPU and peer-connection APIs",
                      @"key":     @"disableRTC",
                      @"enabled": @YES}];
    [rows addObject:@{@"title":   @"Block file:// Access",
                      @"detail":  @"Prevents local file exfiltration",
                      @"key":     @"disableFileAccess",
                      @"enabled": @YES}];

    return rows;
}

// Returns the intended out-of-the-box default for each toggle.
// Used by the overlay when no saved value exists for a key yet.
// Must stay in sync with the hardcoded defaults in loadPrefs().
static BOOL ads_default_value_for_key(NSString *key) {
    if ([key isEqualToString:@"spoofUA"])           return YES;
    if ([key isEqualToString:@"disableJIT"])        return YES;
    if ([key isEqualToString:@"disableJIT15"])      return YES;
    // JS, media, RTC, file access all off — user opts in explicitly.
    return NO;
}

// Returns the current live value for a key so the UI reflects actual state.
static BOOL ads_live_value_for_key(NSString *key) {
    if ([key isEqualToString:@"disableJIT"])        return applyDisableJIT;
    if ([key isEqualToString:@"disableJIT15"])      return applyDisableJIT15;
    if ([key isEqualToString:@"disableJS"])         return applyDisableJS;
    if ([key isEqualToString:@"disableMedia"])      return applyDisableMedia;
    if ([key isEqualToString:@"disableRTC"])        return applyDisableRTC;
    if ([key isEqualToString:@"disableFileAccess"]) return applyDisableFileAccess;
    if ([key isEqualToString:@"spoofUA"])           return shouldSpoofUA;
    return NO;
}

// ---- Settings view controller ----

@interface ADSTFSettingsViewController : UIViewController <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UITableView           *tableView;
@property (nonatomic, strong) NSMutableDictionary   *pendingRules;   // TargetRules_<bundleID> working copy
@property (nonatomic, strong) NSMutableDictionary   *pendingPrefs;   // full prefs working copy
@property (nonatomic, copy)   NSString              *bundleID;
@property (nonatomic, strong) NSArray<NSDictionary *> *rows;
// YES while "Block JavaScript" is ON — keeps the JIT row locked and forced-on.
@property (nonatomic)         BOOL                    jsLocked;
@end

@implementation ADSTFSettingsViewController

- (instancetype)init {
    if (!(self = [super init])) return nil;

    self.bundleID = [[NSBundle mainBundle] bundleIdentifier] ?: @"unknown";
    self.rows     = ads_tf_setting_rows();

    NSDictionary *prefs   = ads_read_prefs();
    self.pendingPrefs      = prefs ? [prefs mutableCopy] : [NSMutableDictionary dictionary];

    NSString *rulesKey    = [NSString stringWithFormat:@"TargetRules_%@", self.bundleID];
    NSDictionary *existing = self.pendingPrefs[rulesKey];
    self.pendingRules      = [existing isKindOfClass:[NSDictionary class]]
                             ? [existing mutableCopy]
                             : [NSMutableDictionary dictionary];

    // Mirror the current JS state so the JIT row opens in the right locked/unlocked state.
    id savedJS     = self.pendingRules[@"disableJS"];
    self.jsLocked  = savedJS ? [savedJS boolValue] : ads_default_value_for_key(@"disableJS");
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    // --- Dimmed / blurred backdrop ---
    UIBlurEffect *blur        = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterialDark];
    UIVisualEffectView *bgView = [[UIVisualEffectView alloc] initWithEffect:blur];
    bgView.frame              = self.view.bounds;
    bgView.autoresizingMask   = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:bgView];

    // Tap outside card to dismiss
    UITapGestureRecognizer *dismissTap = [[UITapGestureRecognizer alloc]
        initWithTarget:self action:@selector(tappedBackground:)];
    dismissTap.numberOfTouchesRequired = 1;
    [bgView addGestureRecognizer:dismissTap];

    // --- Card ---
    UIView *card                = [[UIView alloc] init];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    card.backgroundColor        = [UIColor colorWithRed:0.11 green:0.11 blue:0.13 alpha:0.97];
    card.layer.cornerRadius     = 18;
    card.layer.masksToBounds    = YES;
    // Subtle drop shadow on the card's parent so it punches through the blur.
    card.layer.shadowColor      = [UIColor blackColor].CGColor;
    card.layer.shadowOpacity    = 0.45;
    card.layer.shadowRadius     = 16;
    card.layer.shadowOffset     = CGSizeMake(0, 6);
    [self.view addSubview:card];

    // --- Header ---
    UILabel *titleLabel                 = [[UILabel alloc] init];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    titleLabel.text                     = @"AntiDarkSword";
    titleLabel.font                     = [UIFont systemFontOfSize:17 weight:UIFontWeightBold];
    titleLabel.textColor                = [UIColor whiteColor];
    titleLabel.textAlignment            = NSTextAlignmentCenter;
    [card addSubview:titleLabel];

    UILabel *subLabel                   = [[UILabel alloc] init];
    subLabel.translatesAutoresizingMaskIntoConstraints = NO;
    subLabel.text                       = self.bundleID;
    subLabel.font                       = [UIFont monospacedSystemFontOfSize:10 weight:UIFontWeightRegular];
    subLabel.textColor                  = [UIColor colorWithWhite:0.5 alpha:1];
    subLabel.textAlignment              = NSTextAlignmentCenter;
    subLabel.adjustsFontSizeToFitWidth  = YES;
    subLabel.minimumScaleFactor         = 0.7;
    [card addSubview:subLabel];

    // --- Master enabled row ---
    UIView *masterRow               = [[UIView alloc] init];
    masterRow.translatesAutoresizingMaskIntoConstraints = NO;
    masterRow.backgroundColor       = [UIColor colorWithWhite:0.17 alpha:1];
    [card addSubview:masterRow];

    UIView *separator = [[UIView alloc] init];
    separator.translatesAutoresizingMaskIntoConstraints = NO;
    separator.backgroundColor = [UIColor colorWithWhite:0.25 alpha:1];
    [masterRow addSubview:separator];

    UILabel *masterLabel            = [[UILabel alloc] init];
    masterLabel.translatesAutoresizingMaskIntoConstraints = NO;
    masterLabel.text                = @"Protection Enabled";
    masterLabel.font                = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    masterLabel.textColor           = [UIColor whiteColor];
    [masterRow addSubview:masterLabel];

    UISwitch *masterSwitch          = [[UISwitch alloc] init];
    masterSwitch.translatesAutoresizingMaskIntoConstraints = NO;
    masterSwitch.onTintColor        = [UIColor systemGreenColor];
    masterSwitch.tag                = NSIntegerMax; // sentinel for master switch
    id masterVal                    = self.pendingPrefs[@"enabled"];
    masterSwitch.on                 = masterVal ? [masterVal boolValue] : NO;
    [masterSwitch addTarget:self action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];
    [masterRow addSubview:masterSwitch];

    // --- Table view for per-feature toggles ---
    self.tableView                       = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.dataSource            = self;
    self.tableView.delegate              = self;
    self.tableView.backgroundColor       = [UIColor clearColor];
    self.tableView.separatorColor        = [UIColor colorWithWhite:0.22 alpha:1];
    self.tableView.separatorInset        = UIEdgeInsetsMake(0, 16, 0, 0);
    self.tableView.scrollEnabled         = YES;
    self.tableView.bounces               = NO;
    self.tableView.tableFooterView       = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 0, 1)];
    [card addSubview:self.tableView];

    // --- Buttons ---
    UIView *buttonBar               = [[UIView alloc] init];
    buttonBar.translatesAutoresizingMaskIntoConstraints = NO;
    buttonBar.backgroundColor       = [UIColor colorWithWhite:0.15 alpha:1];
    [card addSubview:buttonBar];

    UIView *btnSep                  = [[UIView alloc] init];
    btnSep.translatesAutoresizingMaskIntoConstraints = NO;
    btnSep.backgroundColor          = [UIColor colorWithWhite:0.25 alpha:1];
    [buttonBar addSubview:btnSep];

    UIButton *cancelBtn             = [UIButton buttonWithType:UIButtonTypeSystem];
    cancelBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [cancelBtn setTitle:@"Cancel" forState:UIControlStateNormal];
    [cancelBtn setTitleColor:[UIColor colorWithWhite:0.55 alpha:1] forState:UIControlStateNormal];
    cancelBtn.titleLabel.font       = [UIFont systemFontOfSize:15];
    [cancelBtn addTarget:self action:@selector(cancel) forControlEvents:UIControlEventTouchUpInside];
    [buttonBar addSubview:cancelBtn];

    UIButton *saveBtn               = [UIButton buttonWithType:UIButtonTypeSystem];
    saveBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [saveBtn setTitle:@"Save & Restart" forState:UIControlStateNormal];
    [saveBtn setTitleColor:[UIColor systemBlueColor] forState:UIControlStateNormal];
    saveBtn.titleLabel.font         = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    [saveBtn addTarget:self action:@selector(saveAndRestart) forControlEvents:UIControlEventTouchUpInside];
    [buttonBar addSubview:saveBtn];

    // --- Divider between cancel/save ---
    UIView *btnDivider              = [[UIView alloc] init];
    btnDivider.translatesAutoresizingMaskIntoConstraints = NO;
    btnDivider.backgroundColor      = [UIColor colorWithWhite:0.28 alpha:1];
    [buttonBar addSubview:btnDivider];

    // --- Auto Layout ---
    CGFloat rowH  = 52.0;
    CGFloat maxTH = rowH * (CGFloat)self.rows.count; // table height, scrolls if needed

    [NSLayoutConstraint activateConstraints:@[
        // Card: centered, 88% wide, max 84% tall
        [card.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [card.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
        [card.widthAnchor   constraintEqualToAnchor:self.view.widthAnchor multiplier:0.88],
        [card.heightAnchor  constraintLessThanOrEqualToAnchor:self.view.heightAnchor multiplier:0.84],

        // Title
        [titleLabel.topAnchor     constraintEqualToAnchor:card.topAnchor constant:18],
        [titleLabel.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16],
        [titleLabel.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16],

        // Subtitle
        [subLabel.topAnchor      constraintEqualToAnchor:titleLabel.bottomAnchor constant:3],
        [subLabel.leadingAnchor  constraintEqualToAnchor:card.leadingAnchor constant:16],
        [subLabel.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16],

        // Master row
        [masterRow.topAnchor      constraintEqualToAnchor:subLabel.bottomAnchor constant:14],
        [masterRow.leadingAnchor  constraintEqualToAnchor:card.leadingAnchor],
        [masterRow.trailingAnchor constraintEqualToAnchor:card.trailingAnchor],
        [masterRow.heightAnchor   constraintEqualToConstant:52],
        [masterLabel.leadingAnchor  constraintEqualToAnchor:masterRow.leadingAnchor constant:16],
        [masterLabel.centerYAnchor  constraintEqualToAnchor:masterRow.centerYAnchor],
        [masterSwitch.trailingAnchor constraintEqualToAnchor:masterRow.trailingAnchor constant:-16],
        [masterSwitch.centerYAnchor  constraintEqualToAnchor:masterRow.centerYAnchor],
        // Bottom separator line on master row
        [separator.leadingAnchor  constraintEqualToAnchor:masterRow.leadingAnchor],
        [separator.trailingAnchor constraintEqualToAnchor:masterRow.trailingAnchor],
        [separator.bottomAnchor   constraintEqualToAnchor:masterRow.bottomAnchor],
        [separator.heightAnchor   constraintEqualToConstant:0.5],

        // Table view
        [self.tableView.topAnchor      constraintEqualToAnchor:masterRow.bottomAnchor],
        [self.tableView.leadingAnchor  constraintEqualToAnchor:card.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:card.trailingAnchor],
        [self.tableView.heightAnchor   constraintEqualToConstant:MIN(maxTH, 330)],

        // Button bar
        [buttonBar.topAnchor      constraintEqualToAnchor:self.tableView.bottomAnchor],
        [buttonBar.leadingAnchor  constraintEqualToAnchor:card.leadingAnchor],
        [buttonBar.trailingAnchor constraintEqualToAnchor:card.trailingAnchor],
        [buttonBar.bottomAnchor   constraintEqualToAnchor:card.bottomAnchor],
        [buttonBar.heightAnchor   constraintEqualToConstant:54],
        // Top separator on button bar
        [btnSep.topAnchor    constraintEqualToAnchor:buttonBar.topAnchor],
        [btnSep.leadingAnchor constraintEqualToAnchor:buttonBar.leadingAnchor],
        [btnSep.trailingAnchor constraintEqualToAnchor:buttonBar.trailingAnchor],
        [btnSep.heightAnchor  constraintEqualToConstant:0.5],
        // Cancel left, Save right, vertical divider between
        [cancelBtn.leadingAnchor  constraintEqualToAnchor:buttonBar.leadingAnchor],
        [cancelBtn.topAnchor      constraintEqualToAnchor:buttonBar.topAnchor constant:0.5],
        [cancelBtn.bottomAnchor   constraintEqualToAnchor:buttonBar.bottomAnchor],
        [cancelBtn.widthAnchor    constraintEqualToAnchor:buttonBar.widthAnchor multiplier:0.5],
        [saveBtn.trailingAnchor   constraintEqualToAnchor:buttonBar.trailingAnchor],
        [saveBtn.topAnchor        constraintEqualToAnchor:buttonBar.topAnchor constant:0.5],
        [saveBtn.bottomAnchor     constraintEqualToAnchor:buttonBar.bottomAnchor],
        [saveBtn.widthAnchor      constraintEqualToAnchor:buttonBar.widthAnchor multiplier:0.5],
        [btnDivider.centerXAnchor constraintEqualToAnchor:buttonBar.centerXAnchor],
        [btnDivider.topAnchor     constraintEqualToAnchor:buttonBar.topAnchor constant:10],
        [btnDivider.bottomAnchor  constraintEqualToAnchor:buttonBar.bottomAnchor constant:-10],
        [btnDivider.widthAnchor   constraintEqualToConstant:0.5],
    ]];
}

// ---- UITableViewDataSource ----

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 1; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)self.rows.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"ads_cell"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"ads_cell"];
    }

    NSDictionary *row = self.rows[(NSUInteger)indexPath.row];
    NSString     *key = row[@"key"];

    // A row is interactive if the iOS API exists AND it isn't locked by JS being on.
    BOOL isJITRow    = [key isEqualToString:@"disableJIT"] || [key isEqualToString:@"disableJIT15"];
    BOOL rowEnabled  = [row[@"enabled"] boolValue] && !(isJITRow && self.jsLocked);

    cell.textLabel.text            = row[@"title"];
    cell.textLabel.font            = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    cell.detailTextLabel.text      = row[@"detail"];
    cell.detailTextLabel.font      = [UIFont systemFontOfSize:11];
    cell.backgroundColor           = [UIColor colorWithWhite:0.13 alpha:1];
    cell.selectionStyle            = UITableViewCellSelectionStyleNone;

    if (rowEnabled) {
        cell.textLabel.textColor        = [UIColor whiteColor];
        cell.detailTextLabel.textColor  = [UIColor colorWithWhite:0.48 alpha:1];
        cell.userInteractionEnabled     = YES;
    } else {
        // Gray out rows whose underlying API is not available on this iOS version.
        cell.textLabel.textColor        = [UIColor colorWithWhite:0.35 alpha:1];
        cell.detailTextLabel.textColor  = [UIColor colorWithWhite:0.30 alpha:1];
        cell.userInteractionEnabled     = NO;
    }

    UISwitch *sw;
    if ([cell.accessoryView isKindOfClass:[UISwitch class]]) {
        sw = (UISwitch *)cell.accessoryView;
    } else {
        sw = [[UISwitch alloc] init];
        [sw addTarget:self action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = sw;
    }
    sw.tag     = indexPath.row;
    sw.enabled = rowEnabled;
    sw.onTintColor = rowEnabled ? [UIColor systemBlueColor] : [UIColor colorWithWhite:0.25 alpha:1];

    // Saved value takes priority; fall back to intended out-of-the-box default.
    // (Live state is not used here — if master is off all live values are NO,
    //  which would make the overlay look blank even though JIT and UA are
    //  intended to be pre-enabled on first use.)
    id saved = self.pendingRules[key];
    sw.on = saved ? [saved boolValue] : ads_default_value_for_key(key);

    return cell;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return 52;
}

// ---- Actions ----

- (void)switchChanged:(UISwitch *)sender {
    if (sender.tag == NSIntegerMax) {
        // Master toggle
        self.pendingPrefs[@"enabled"] = @(sender.on);
        return;
    }

    NSString *key = self.rows[(NSUInteger)sender.tag][@"key"];
    self.pendingRules[key] = @(sender.on);

    // When JS is toggled, cascade to the JIT row:
    //   JS ON  → lock JIT on (JIT is meaningless without JS; force it enabled, grey it out)
    //   JS OFF → unlock JIT and turn it off (let the user decide independently)
    if ([key isEqualToString:@"disableJS"]) {
        self.jsLocked = sender.on;

        // Find the JIT row regardless of which key name it uses.
        NSUInteger jitIdx = NSNotFound;
        for (NSUInteger i = 0; i < self.rows.count; i++) {
            NSString *k = self.rows[i][@"key"];
            if ([k isEqualToString:@"disableJIT"] || [k isEqualToString:@"disableJIT15"]) {
                jitIdx = i;
                break;
            }
        }

        if (jitIdx != NSNotFound) {
            NSString *jitKey       = self.rows[jitIdx][@"key"];
            // Force JIT ON when JS is disabled; turn it OFF when JS is re-enabled.
            self.pendingRules[jitKey] = @(sender.on);

            NSIndexPath *jitPath = [NSIndexPath indexPathForRow:(NSInteger)jitIdx inSection:0];
            [self.tableView reloadRowsAtIndexPaths:@[jitPath]
                                  withRowAnimation:UITableViewRowAnimationNone];
        }
    }
}

- (void)tappedBackground:(UITapGestureRecognizer *)tap {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)cancel {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)saveAndRestart {
    // Write TargetRules back, then flush the full plist.
    NSString *rulesKey       = [NSString stringWithFormat:@"TargetRules_%@", self.bundleID];
    self.pendingPrefs[rulesKey] = [self.pendingRules copy];

    // ads_write_prefs tries the system path first, falls back to NSUserDefaults
    // suite — the fallback always succeeds on sandboxed TrollStore devices.
    ads_write_prefs(self.pendingPrefs);

    // Notify the live-reload path for settings that take effect immediately.
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         CFSTR("com.eolnmsuk.antidarkswordprefs/saved"),
                                         NULL, NULL, YES);

    [self dismissViewControllerAnimated:YES completion:^{
        UIAlertController *alert = [UIAlertController
            alertControllerWithTitle:@"Settings Saved"
            message:@"Changes to WebKit configuration only take effect after a full restart. Restart now?"
            preferredStyle:UIAlertControllerStyleAlert];

        [alert addAction:[UIAlertAction actionWithTitle:@"Restart Now"
                                                  style:UIAlertActionStyleDestructive
                                                handler:^(UIAlertAction *a) {
            exit(0);
        }]];
        [alert addAction:[UIAlertAction actionWithTitle:@"Later"
                                                  style:UIAlertActionStyleCancel
                                                handler:nil]];

        UIViewController *top = ads_top_vc(ads_key_window().rootViewController);
        if (top) [top presentViewController:alert animated:YES completion:nil];
    }];
}

@end

// ---- Gesture installation ----

static void ads_show_settings_overlay(void) {
    UIWindow       *win  = ads_key_window();
    UIViewController *top = win ? ads_top_vc(win.rootViewController) : nil;
    if (!top) return;

    // Don't stack multiple overlays
    if ([top isKindOfClass:[ADSTFSettingsViewController class]]) return;

    ADSTFSettingsViewController *vc = [[ADSTFSettingsViewController alloc] init];
    vc.modalPresentationStyle = UIModalPresentationOverFullScreen;
    vc.modalTransitionStyle   = UIModalTransitionStyleCrossDissolve;
    [top presentViewController:vc animated:YES completion:nil];
}

// Persistent singleton target for the gesture recognizer.
// UITapGestureRecognizer holds a weak reference to its target, so the target
// must be kept alive independently — NSBlockOperation was being deallocated
// immediately, which is why the gesture never fired.
@interface ADSTFGestureHandler : NSObject
+ (instancetype)shared;
- (void)handleTap:(UITapGestureRecognizer *)sender;
@end

@implementation ADSTFGestureHandler
+ (instancetype)shared {
    static ADSTFGestureHandler *instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ instance = [[self alloc] init]; });
    return instance;
}
- (void)handleTap:(UITapGestureRecognizer *)sender {
    if (sender.state != UIGestureRecognizerStateEnded) return;
    ads_show_settings_overlay();
}
@end

static void ads_install_settings_gesture_on_window(UIWindow *win) {
    if (!win || ads_gesture_installed) return;

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc]
        initWithTarget:[ADSTFGestureHandler shared]
                action:@selector(handleTap:)];
    tap.numberOfTapsRequired    = 2;
    tap.numberOfTouchesRequired = 3;
    tap.cancelsTouchesInView    = NO;
    [win addGestureRecognizer:tap];

    ads_gesture_installed = YES;
    ADSLog(@"[INIT] AntiDarkSword three-finger double-tap gesture installed on %@.", win);
}

// Hook UIWindow so we catch the main window the moment it becomes key,
// regardless of how fast the app starts up.
%hook UIWindow
- (void)makeKeyAndVisible {
    %orig;
    ads_install_settings_gesture_on_window(self);
}
%end

// =========================================================
// CONSTRUCTOR
// =========================================================

%ctor {
    isRootlessJB = (access("/var/jb", F_OK) == 0);
    loadPrefs();

    ADSLog(@"[INIT] AntiDarkSword (TrollFools) loaded into: %@ (%@)",
           [[NSProcessInfo processInfo] processName],
           [[NSBundle mainBundle] bundleIdentifier] ?: @"unknown");

    // Listen for preference changes posted by the jailbreak prefs bundle,
    // or by any tool that writes to the same Darwin notification center.
    CFNotificationCenterAddObserver(
        CFNotificationCenterGetDarwinNotifyCenter(), NULL,
        (CFNotificationCallback)reloadPrefsNotification,
        CFSTR("com.eolnmsuk.antidarkswordprefs/saved"),
        NULL, CFNotificationSuspensionBehaviorCoalesce);

    // Gesture is installed via %hook UIWindow makeKeyAndVisible — no additional
    // setup needed here. The hook fires on the main window before any user
    // interaction can happen, so the gesture is always ready in time.
}
