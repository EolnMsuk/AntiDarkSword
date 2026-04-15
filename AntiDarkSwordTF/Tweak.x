// AntiDarkSwordTF/Tweak.x
// TrollFools / TrollStore variant — single dylib, direct per-app injection.
//
// Key differences from the jailbreak tweak:
//   • No MobileSubstrate dependency — %hook compiles to pure ObjC runtime calls.
//   • No PreferenceLoader UI — reads the shared prefs plist (same domain as the
//     jailbreak version) and falls back to safe-default ON for missing keys.
//   • No tier matching or process filtering — TrollFools puts the dylib in the
//     app the user chose; protections apply unconditionally.
//   • No daemon-layer hooks — injecting into imagent/apsd requires a jailbreak.
//   • JSEvaluateScript C-function hook is omitted (needs MSHookFunction / fishhook).
//     The WKWebpagePreferences and WKPreferences %hooks cover JS blocking at the
//     ObjC level, which is sufficient for attack-surface reduction.

#import <Foundation/Foundation.h>
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
// PRIVATE INTERFACES — iMessage transfer / preview blocking
// NOTE: These classes live in IMCore and ChatKit respectively.
//       If the injected app doesn't load those frameworks the
//       hooks simply never fire — safe to include unconditionally.
// =========================================================
@interface IMFileTransfer : NSObject
- (BOOL)isAutoDownloadable;
- (BOOL)canAutoDownload;
@end

@interface CKAttachmentMessagePartChatItem : NSObject
- (BOOL)_needsPreviewGeneration;
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
static _Atomic BOOL applyDisableIMessageDL = NO;
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

    // Read plist; fall back to CFPreferences if not flushed to disk yet.
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:ads_prefs_path()];
    if (!prefs) {
        CFArrayRef keyList = CFPreferencesCopyKeyList(CFSTR("com.eolnmsuk.antidarkswordprefs"),
                                                      kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
        if (keyList) {
            CFDictionaryRef dict = CFPreferencesCopyMultiple(keyList,
                                                             CFSTR("com.eolnmsuk.antidarkswordprefs"),
                                                             kCFPreferencesCurrentUser,
                                                             kCFPreferencesAnyHost);
            if (dict) prefs = (__bridge_transfer NSDictionary *)dict;
            CFRelease(keyList);
        }
    }

    // Master enable — default ON so the dylib is protective immediately after injection.
    // A user who wants it off can write enabled=NO to the shared plist via Filza / Santander.
    BOOL masterEnabled = YES;
    id enabledVal = prefs[@"enabled"];
    if (enabledVal && [enabledVal respondsToSelector:@selector(boolValue)])
        masterEnabled = [enabledVal boolValue];

    if (!masterEnabled) {
        shouldSpoofUA = applyDisableJIT = applyDisableJIT15 = applyDisableJS =
            applyDisableMedia = applyDisableRTC = applyDisableFileAccess =
            applyDisableIMessageDL = NO;
        ADSLog(@"[STATUS] Tweak disabled via prefs.");
        return;
    }

    BOOL isIOS16 = [[NSProcessInfo processInfo] operatingSystemVersion].majorVersion >= 16;

    // Per-app rules from TargetRules_<bundleID> take priority over global keys.
    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier] ?: @"";
    NSString *dictKey  = [NSString stringWithFormat:@"TargetRules_%@", bundleID];
    NSDictionary *rules = ([prefs isKindOfClass:[NSDictionary class]]) ? prefs[dictKey] : nil;
    if (![rules isKindOfClass:[NSDictionary class]]) rules = nil;

    // Safe defaults for TrollFools:
    //   JIT / lockdown mode  → ON  (blocks JIT-based exploits, low app breakage)
    //   Media autoplay       → ON  (blocks drive-by media exploit delivery)
    //   Local file access    → ON  (blocks file:// exfiltration)
    //   iMessage DL          → ON  only when injected into an iMessage-capable app
    //   WebGL / WebRTC       → OFF by default (breaks video-call apps; user can enable)
    //   JavaScript           → OFF by default (breaks most apps; user can enable)
    applyDisableJIT        = isIOS16  ? ads_read_bool(rules, prefs, @"disableJIT",        @"globalDisableJIT",        YES) : NO;
    applyDisableJIT15      = !isIOS16 ? ads_read_bool(rules, prefs, @"disableJIT15",      @"globalDisableJIT15",      YES) : NO;
    applyDisableJS         =            ads_read_bool(rules, prefs, @"disableJS",         @"globalDisableJS",         NO);
    applyDisableMedia      =            ads_read_bool(rules, prefs, @"disableMedia",      @"globalDisableMedia",      YES);
    applyDisableRTC        =            ads_read_bool(rules, prefs, @"disableRTC",        @"globalDisableRTC",        NO);
    applyDisableFileAccess =            ads_read_bool(rules, prefs, @"disableFileAccess", @"globalDisableFileAccess", YES);

    // iMessage download blocking — default ON only in iMessage-capable processes.
    NSArray *iMsgApps = @[
        @"com.apple.MobileSMS", @"com.apple.iMessageAppsViewService",
        @"com.apple.ActivityMessagesApp"
    ];
    BOOL inIMsgApp = [iMsgApps containsObject:bundleID];
    applyDisableIMessageDL = ads_read_bool(rules, prefs, @"disableIMessageDL", @"globalDisableIMessageDL", inIMsgApp);

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
           "JIT:%d Media:%d RTC:%d FileAccess:%d iMsgDL:%d UA:%d",
           bundleID,
           (int)applyDisableJIT, (int)applyDisableMedia, (int)applyDisableRTC,
           (int)applyDisableFileAccess, (int)applyDisableIMessageDL, (int)shouldSpoofUA);
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
// iMESSAGE MITIGATIONS
// These fire only when the injected app loads IMCore / ChatKit.
// =========================================================

%hook IMFileTransfer
- (BOOL)isAutoDownloadable {
    if (applyDisableIMessageDL) {
        ADSLog(@"[MITIGATION] Blocked auto-download of iMessage file transfer.");
        return NO;
    }
    return %orig;
}

- (BOOL)canAutoDownload {
    if (applyDisableIMessageDL) {
        ADSLog(@"[MITIGATION] Denied canAutoDownload for iMessage transfer.");
        return NO;
    }
    return %orig;
}
%end

%hook CKAttachmentMessagePartChatItem
- (BOOL)_needsPreviewGeneration {
    if (applyDisableIMessageDL) return NO;
    return %orig;
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
}
