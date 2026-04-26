// AntiDarkSwordTF/Tweak.x
// TrollFools / TrollStore variant — single dylib, direct per-app injection.
// No MobileSubstrate dependency; no tier matching; no JSEvaluateScript hook (needs MSHookFunction).
// Settings via three-finger double-tap overlay (biometric-gated). Master switch defaults OFF.

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#import <JavaScriptCore/JavaScriptCore.h>
#import <CoreFoundation/CoreFoundation.h>
#import <LocalAuthentication/LocalAuthentication.h>
#include <unistd.h>
#include <stdatomic.h>
#include <objc/runtime.h>

#import "../ADSLogging.h"

// lockdownModeEnabled became public in iOS 16 (SDK 160000+); forward-declare only for older SDKs.
#if __IPHONE_OS_VERSION_MAX_ALLOWED < 160000
@interface WKWebpagePreferences (Private)
@property (nonatomic, assign) BOOL lockdownModeEnabled;
@end
#endif

@interface _WKProcessPoolConfiguration : NSObject
@property (nonatomic, assign) BOOL JITEnabled;
@end

@interface WKProcessPool (Private)
@property (nonatomic, readonly) _WKProcessPoolConfiguration *_configuration;
@end

// CKAttachmentMessagePartChatItem is in ChatKit, loaded by Messages and related apps.
@interface CKAttachmentMessagePartChatItem : NSObject
- (NSURL *)fullSizeImageURL;
@end

// Shares prefs domain with the jailbreak tweak so the PreferenceLoader bundle is interoperable.
static BOOL isRootlessJB = NO;

static NSString *ads_prefs_path(void) {
    return isRootlessJB
        ? @"/var/jb/var/mobile/Library/Preferences/com.eolnmsuk.antidarkswordprefs.plist"
        : @"/var/mobile/Library/Preferences/com.eolnmsuk.antidarkswordprefs.plist";
}

static _Atomic BOOL prefsLoaded              = NO;
static _Atomic BOOL shouldSpoofUA            = NO;
static _Atomic BOOL applyDisableJIT          = NO;
static _Atomic BOOL applyDisableJIT15        = NO;
static _Atomic BOOL applyDisableJS           = NO;
static _Atomic BOOL applyDisableMedia        = NO;
static _Atomic BOOL applyDisableRTC          = NO;
static _Atomic BOOL applyDisableFileAccess   = NO;
static _Atomic BOOL applyBlockRemoteContent  = NO;
static _Atomic BOOL applyBlockRiskyAttachments = NO;

static NSString *customUAString = nil;

// Compiled once in %ctor; blocks external http/https resource loads — the primary zero-click
// attack surface in HTML email rendering (Mail.app). Applied when applyBlockRemoteContent=YES.
// Written on the main queue (see %ctor completion handler); read from WebKit hooks (main thread).
static WKContentRuleList *adsContentBlocker = nil;

// Per-UCC injection guard — same rationale as AntiDarkSwordUI (see kADSUCCInjectedKey comment there).
static const char kADSUCCInjectedKey = 0;

static NSString *adsJSONStringLiteral(NSString *str);

// Derives navigator.userAgentData.brands JSON array from a UA string,
// keeping engine/browser tokens consistent with userAgent.
static NSString *adsBrandsFromUA(NSString *ua) {
    if (!ua) return @"[{\"brand\":\"Safari\",\"version\":\"18\"}]";

    NSString *(^majorAfter)(NSString *) = ^NSString *(NSString *token) {
        NSRange r = [ua rangeOfString:token];
        if (r.location == NSNotFound) return @"120";
        NSString *after = [ua substringFromIndex:NSMaxRange(r)];
        NSRange stop = [after rangeOfCharacterFromSet:[[NSCharacterSet decimalDigitCharacterSet] invertedSet]];
        NSString *ver = stop.location > 0 ? [after substringToIndex:stop.location] : after;
        return (ver.length > 0 && ver.length <= 6) ? ver : @"120";
    };

    if ([ua containsString:@"Edg/"] || [ua containsString:@"EdgA/"] || [ua containsString:@"EdgiOS/"]) {
        NSString *token = [ua containsString:@"Edg/"] ? @"Edg/" : ([ua containsString:@"EdgA/"] ? @"EdgA/" : @"EdgiOS/");
        NSString *ver = majorAfter(token);
        return [NSString stringWithFormat:
            @"[{\"brand\":\"Not(A:Brand\",\"version\":\"24\"},"
             "{\"brand\":\"Chromium\",\"version\":\"%@\"},"
             "{\"brand\":\"Microsoft Edge\",\"version\":\"%@\"}]", ver, ver];
    }

    NSString *chromeToken = [ua containsString:@"Chrome/"] ? @"Chrome/" : ([ua containsString:@"CriOS/"] ? @"CriOS/" : nil);
    if (chromeToken) {
        NSString *ver = majorAfter(chromeToken);
        return [NSString stringWithFormat:
            @"[{\"brand\":\"Not(A:Brand\",\"version\":\"24\"},"
             "{\"brand\":\"Chromium\",\"version\":\"%@\"},"
             "{\"brand\":\"Google Chrome\",\"version\":\"%@\"}]", ver, ver];
    }

    NSString *ffToken = [ua containsString:@"Firefox/"] ? @"Firefox/" : ([ua containsString:@"FxiOS/"] ? @"FxiOS/" : nil);
    if (ffToken) {
        NSString *ver = majorAfter(ffToken);
        return [NSString stringWithFormat:@"[{\"brand\":\"Firefox\",\"version\":\"%@\"}]", ver];
    }

    return @"[{\"brand\":\"Safari\",\"version\":\"18\"}]";
}

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
    if (objc_getAssociatedObject(ucc, &kADSUCCInjectedKey)) return;
    objc_setAssociatedObject(ucc, &kADSUCCInjectedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
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

    // UA Client Hints (navigator.userAgentData) — iOS 16+ Safari 16+.
    BOOL isMobileUA = [customUAString containsString:@"iPhone"] ||
                      [customUAString containsString:@"iPad"]   ||
                      [customUAString containsString:@"Android"];
    NSString *uadMobile   = isMobileUA ? @"true" : @"false";

    NSString *uadPlatform = @"\"iOS\"";
    if ([customUAString containsString:@"Macintosh"])    uadPlatform = @"\"macOS\"";
    else if ([customUAString containsString:@"Windows"]) uadPlatform = @"\"Windows\"";
    else if ([customUAString containsString:@"Android"]) uadPlatform = @"\"Android\"";
    NSString *uadBrands = adsBrandsFromUA(customUAString);

    NSString *jsSource = [NSString stringWithFormat:
        @"(function(){"
         "var d=Object.defineProperty,n=navigator;"
         "d(n,'userAgent',  {get:function(){return %@},configurable:true});"
         "d(n,'appVersion', {get:function(){return %@},configurable:true});"
         "d(n,'platform',   {get:function(){return %@},configurable:true});"
         "d(n,'vendor',     {get:function(){return %@},configurable:true});"
         "try{var ud={brands:%@,mobile:%@,platform:%@,"
         "getHighEntropyValues:function(h){return Promise.resolve({});}};"
         "d(n,'userAgentData',{get:function(){return ud;},configurable:true});}catch(e){}"
         "})();",
        jsonUA, jsonAppVersion, platform, vendor, uadBrands, uadMobile, uadPlatform];

    WKUserScript *script = [[WKUserScript alloc]
        initWithSource:jsSource
         injectionTime:WKUserScriptInjectionTimeAtDocumentStart
      forMainFrameOnly:NO];
    [ucc addUserScript:script];
}

// Sandboxed TrollStore devices cannot write to /var/mobile/Library/Preferences/.
// ads_write_prefs tries the system path first; falls back to NSUserDefaults suite
// (app's own container) which always succeeds.
static NSString * const kADSTFSuite = @"com.eolnmsuk.antidarkswordprefs";

// Priority: system plist → CFPreferences (jailbreak bundle writes) → NSUserDefaults suite (sandboxed fallback).
static NSDictionary *ads_read_prefs(void) {
    NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:ads_prefs_path()];
    if (d) return d;

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

    NSUserDefaults *ud = [[NSUserDefaults alloc] initWithSuiteName:kADSTFSuite];
    NSDictionary *all  = [ud dictionaryRepresentation];
    return (all && all.count > 0) ? all : nil;
}

static void ads_write_prefs(NSDictionary *prefs) {
    NSString *path = ads_prefs_path();
    NSString *dir  = [path stringByDeletingLastPathComponent];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    if ([prefs writeToFile:path atomically:YES]) return;

    // Sandboxed fallback: wipe then rewrite so deleted keys don't linger.
    NSUserDefaults *ud = [[NSUserDefaults alloc] initWithSuiteName:kADSTFSuite];
    for (NSString *existing in [[ud dictionaryRepresentation] allKeys]) {
        if (!prefs[existing]) [ud removeObjectForKey:existing];
    }
    [prefs enumerateKeysAndObjectsUsingBlock:^(NSString *key, id obj, BOOL *stop) {
        [ud setObject:obj forKey:key];
    }];
    [ud synchronize];
}

// Reads a BOOL: per-app rules → global prefs key → hardcoded default (first present wins).
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
    BOOL expected = NO;
    if (!atomic_compare_exchange_strong(&prefsLoaded, &expected, YES)) return;

    NSDictionary *prefs = ads_read_prefs();

    // Master switch defaults OFF — dylib is dormant until user opts in via overlay.
    BOOL masterEnabled = NO;
    id enabledVal = prefs[@"enabled"];
    if (enabledVal && [enabledVal respondsToSelector:@selector(boolValue)])
        masterEnabled = [enabledVal boolValue];
        
    if (!masterEnabled) {
        shouldSpoofUA = applyDisableJIT = applyDisableJIT15 = applyDisableJS =
            applyDisableMedia = applyDisableRTC = applyDisableFileAccess =
            applyBlockRemoteContent = applyBlockRiskyAttachments = NO;
        ADSLog(@"[STATUS] Tweak disabled via prefs.");
        return;
    }

    BOOL isIOS16 = [[NSProcessInfo processInfo] operatingSystemVersion].majorVersion >= 16;

    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier] ?: @"";
    NSString *dictKey  = [NSString stringWithFormat:@"TargetRules_%@", bundleID];
    NSDictionary *rules = ([prefs isKindOfClass:[NSDictionary class]]) ? prefs[dictKey] : nil;
    if (![rules isKindOfClass:[NSDictionary class]]) rules = nil;

    // Defaults on first use: UA spoof ON (non-breaking), JIT ON (low breakage),
    // JS/Media/WebRTC/FileAccess OFF (user opts in explicitly — these break most apps).
    applyDisableJIT        = isIOS16  ? ads_read_bool(rules, prefs, @"disableJIT",        @"globalDisableJIT",        YES) : NO;
    applyDisableJIT15      = !isIOS16 ? ads_read_bool(rules, prefs, @"disableJIT15",      @"globalDisableJIT15",      YES) : NO;
    applyDisableJS         =            ads_read_bool(rules, prefs, @"disableJS",         @"globalDisableJS",         NO);
    applyDisableMedia      =            ads_read_bool(rules, prefs, @"disableMedia",      @"globalDisableMedia",      NO);
    applyDisableRTC        =            ads_read_bool(rules, prefs, @"disableRTC",        @"globalDisableRTC",        NO);
    applyDisableFileAccess  =           ads_read_bool(rules, prefs, @"disableFileAccess",  @"globalDisableFileAccess",  NO);
    applyBlockRemoteContent   =          ads_read_bool(rules, prefs, @"blockRemoteContent",    @"globalBlockRemoteContent",    NO);
    applyBlockRiskyAttachments =         ads_read_bool(rules, prefs, @"blockRiskyAttachments", @"globalBlockRiskyAttachments", NO);

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

    // TrollFools default: UA spoof ON (user opted in by injecting the dylib explicitly).
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
           "JIT:%d Media:%d RTC:%d FileAccess:%d UA:%d RemoteBlock:%d RiskyAttach:%d",
           bundleID,
           (int)applyDisableJIT, (int)applyDisableMedia, (int)applyDisableRTC,
           (int)applyDisableFileAccess, (int)shouldSpoofUA,
           (int)applyBlockRemoteContent, (int)applyBlockRiskyAttachments);
}

static void reloadPrefsNotification(CFNotificationCenterRef center __unused,
                                    void *observer __unused,
                                    CFStringRef name __unused,
                                    const void *object __unused,
                                    CFDictionaryRef userInfo __unused) {
    prefsLoaded = NO;
    loadPrefs();
}

static void applyWebKitMitigations(WKWebViewConfiguration *configuration) {
    if (!configuration) return;
    
    if (applyDisableJS) {
        if ([configuration respondsToSelector:@selector(defaultWebpagePreferences)]) {
            WKWebpagePreferences *pagePrefs = configuration.defaultWebpagePreferences;
            if ([pagePrefs respondsToSelector:@selector(setAllowsContentJavaScript:)])
                pagePrefs.allowsContentJavaScript = NO;
        }
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

    WKContentRuleList *localBlocker = adsContentBlocker;
    if (applyBlockRemoteContent && localBlocker)
        [configuration.userContentController addContentRuleList:localBlocker];

    if (shouldSpoofUA) injectUAScript(configuration.userContentController);
}

%hook WKWebViewConfiguration

- (void)setUserContentController:(WKUserContentController *)userContentController {
    %orig;
    if (shouldSpoofUA && userContentController) injectUAScript(userContentController);
    WKContentRuleList *localBlocker = adsContentBlocker;
    if (applyBlockRemoteContent && localBlocker && userContentController)
        [userContentController addContentRuleList:localBlocker];
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
        if ([self.configuration respondsToSelector:@selector(defaultWebpagePreferences)]) {
            WKWebpagePreferences *pagePrefs = self.configuration.defaultWebpagePreferences;
            if ([pagePrefs respondsToSelector:@selector(setAllowsContentJavaScript:)])
                pagePrefs.allowsContentJavaScript = NO;
        }
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
        if ([self.configuration respondsToSelector:@selector(defaultWebpagePreferences)]) {
            WKWebpagePreferences *pagePrefs = self.configuration.defaultWebpagePreferences;
            if ([pagePrefs respondsToSelector:@selector(setAllowsContentJavaScript:)])
                pagePrefs.allowsContentJavaScript = NO;
        }
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

- (void)callAsyncJavaScript:(NSString *)functionBody arguments:(NSDictionary<NSString *, id> *)arguments inFrame:(WKFrameInfo *)frame inContentWorld:(WKContentWorld *)contentWorld completionHandler:(void (^)(id, NSError *))completionHandler {
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
// Prevent apps (or exploits) from disabling lockdown mode after we've enabled it.
- (void)setLockdownModeEnabled:(BOOL)enabled {
    if (applyDisableJIT && !enabled) return;
    %orig;
}
%end

%hook WKPreferences
- (void)setJavaScriptEnabled:(BOOL)enabled {
    if (applyDisableJS && enabled) return %orig(NO);
    %orig;
}
%end

// Prevent code from re-enabling JIT after we've disabled it via the pool configuration.
%hook _WKProcessPoolConfiguration
- (void)setJITEnabled:(BOOL)enabled {
    if (enabled && (applyDisableJIT || applyDisableJIT15)) return;
    %orig;
}
%end

%hook UIWebView
- (NSString *)stringByEvaluatingJavaScriptFromString:(NSString *)script {
    if (applyDisableJS) return @"";
    return %orig;
}
%end

// Intercepts the URL used to fetch attachment previews. Returns nil for high-risk
// image/document formats to prevent ImageIO/CoreGraphics parsing of exploit-bearing files.
%hook CKAttachmentMessagePartChatItem
- (NSURL *)fullSizeImageURL {
    NSURL *url = %orig;
    if (!applyBlockRiskyAttachments || !url) return url;
    static NSSet *riskyExts;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        riskyExts = [NSSet setWithObjects:@"heic", @"heif", @"webp", @"pdf", nil];
    });
    NSString *ext = url.pathExtension.lowercaseString;
    if ([riskyExts containsObject:ext]) {
        ADSLog(@"[MITIGATION] Blocked risky attachment preview (%@): %@", ext, url.lastPathComponent);
        return nil;
    }
    return url;
}
%end

static BOOL ads_gesture_installed = NO;

static UIWindow *ads_key_window(void) {
    if (@available(iOS 13, *)) {
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if (![scene isKindOfClass:[UIWindowScene class]]) continue;
            UIWindowScene *windowScene = (UIWindowScene *)scene;
            if (windowScene.activationState == UISceneActivationStateForegroundActive) {
                for (UIWindow *window in windowScene.windows) {
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

static UIViewController *ads_top_vc(UIViewController *root) {
    while (root.presentedViewController) root = root.presentedViewController;
    return root;
}

// Builds the row model for the settings overlay. "enabled"=NO rows are shown
// grayed-out when the underlying API is unavailable on this iOS version.
static NSArray<NSDictionary *> *ads_tf_setting_rows(void) {
    NSInteger major = [[NSProcessInfo processInfo] operatingSystemVersion].majorVersion;
    NSMutableArray *rows = [NSMutableArray array];

    [rows addObject:@{@"title":   @"Spoof User Agent",
                      @"detail":  @"Masks the real browser fingerprint",
                      @"key":     @"spoofUA",
                      @"enabled": @YES}];

    // iOS 16+: lockdownModeEnabled (reliable). iOS 15: _WKProcessPoolConfiguration.JITEnabled (private, best-effort).
    // iOS 14-: neither API available; row shown grayed.
    if (major >= 16) {
        [rows addObject:@{@"title":   @"Block JIT / Lockdown Mode",
                          @"detail":  @"Enables WebKit lockdown mode (iOS 16, 17+)",
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

    [rows addObject:@{@"title":   @"Block Remote Content",
                      @"detail":  @"Blocks external resource loads — recommended for Mail",
                      @"key":     @"blockRemoteContent",
                      @"enabled": @YES}];

    [rows addObject:@{@"title":   @"Block Risky Attachment Previews",
                      @"detail":  @"Suppresses HEIC/WebP/PDF previews (zero-click attack surface)",
                      @"key":     @"blockRiskyAttachments",
                      @"enabled": @YES}];

    return rows;
}

// Must stay in sync with the hardcoded defaults in loadPrefs().
static BOOL ads_default_value_for_key(NSString *key) {
    if ([key isEqualToString:@"spoofUA"])           return YES;
    if ([key isEqualToString:@"disableJIT"])        return YES;
    if ([key isEqualToString:@"disableJIT15"])      return YES;
    // JS, media, RTC, file access, remote content block, risky attachment block all off — user opts in.
    return NO;
}


@interface ADSTFSettingsViewController : UIViewController <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UITableView             *tableView;
@property (nonatomic, strong) NSMutableDictionary     *pendingRules;
@property (nonatomic, strong) NSMutableDictionary     *pendingPrefs;
@property (nonatomic, copy)   NSString                *bundleID;
@property (nonatomic, strong) NSArray<NSDictionary *> *rows;
// YES while JS blocking is ON — keeps the JIT row locked and forced-on (JIT must be off when JS is off).
@property (nonatomic)         BOOL                     jsLocked;
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
                             
    id savedJS     = self.pendingRules[@"disableJS"];
    self.jsLocked  = savedJS ? [savedJS boolValue] : ads_default_value_for_key(@"disableJS");
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    UIBlurEffect *blur        = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterialDark];
    UIVisualEffectView *bgView = [[UIVisualEffectView alloc] initWithEffect:blur];
    bgView.frame              = self.view.bounds;
    bgView.autoresizingMask   = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:bgView];

    UITapGestureRecognizer *dismissTap = [[UITapGestureRecognizer alloc]
        initWithTarget:self action:@selector(tappedBackground:)];
    dismissTap.numberOfTouchesRequired = 1;
    [bgView addGestureRecognizer:dismissTap];

    UIView *shadowWrapper = [[UIView alloc] init];
    shadowWrapper.translatesAutoresizingMaskIntoConstraints = NO;
    shadowWrapper.backgroundColor       = [UIColor clearColor];
    shadowWrapper.layer.cornerRadius    = 18;
    shadowWrapper.layer.shadowColor     = [UIColor blackColor].CGColor;
    shadowWrapper.layer.shadowOpacity   = 0.45;
    shadowWrapper.layer.shadowRadius    = 16;
    shadowWrapper.layer.shadowOffset    = CGSizeMake(0, 6);
    [self.view addSubview:shadowWrapper];

    UIView *card                = [[UIView alloc] init];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    card.backgroundColor        = [UIColor colorWithRed:0.11 green:0.11 blue:0.13 alpha:0.97];
    card.layer.cornerRadius     = 18;
    card.layer.masksToBounds    = YES;
    [shadowWrapper addSubview:card];
    
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
    
    UIView *masterRow               = [[UIView alloc] init];
    masterRow.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:masterRow];
    
    UIView *separator = [[UIView alloc] init];
    separator.translatesAutoresizingMaskIntoConstraints = NO;
    separator.backgroundColor = [UIColor colorWithWhite:0.25 alpha:1];
    [masterRow addSubview:separator];
    
    UILabel *masterLabel            = [[UILabel alloc] init];
    masterLabel.translatesAutoresizingMaskIntoConstraints = NO;
    masterLabel.text                = @"Enable Protection";
    masterLabel.font                = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    masterLabel.textColor           = [UIColor whiteColor];
    [masterRow addSubview:masterLabel];
    
    UISwitch *masterSwitch          = [[UISwitch alloc] init];
    masterSwitch.translatesAutoresizingMaskIntoConstraints = NO;
    masterSwitch.onTintColor        = [UIColor systemGreenColor];
    masterSwitch.tag                = NSIntegerMax; // sentinel distinguishes master from feature rows
    
    id masterVal                    = self.pendingPrefs[@"enabled"];
    BOOL isMasterEnabled            = masterVal ? [masterVal boolValue] : NO;
    masterSwitch.on                 = isMasterEnabled;
    masterRow.backgroundColor = isMasterEnabled
        ? [UIColor colorWithRed:0.08 green:0.25 blue:0.12 alpha:1.0] 
        : [UIColor colorWithRed:0.25 green:0.08 blue:0.08 alpha:1.0];
        
    [masterSwitch addTarget:self action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];
    [masterRow addSubview:masterSwitch];
    
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
    
    UIView *btnDivider              = [[UIView alloc] init];
    btnDivider.translatesAutoresizingMaskIntoConstraints = NO;
    btnDivider.backgroundColor      = [UIColor colorWithWhite:0.28 alpha:1];
    [buttonBar addSubview:btnDivider];
    
    CGFloat rowH  = 52.0;
    CGFloat maxTH = rowH * (CGFloat)self.rows.count; // table height, scrolls if needed

    [NSLayoutConstraint activateConstraints:@[
        [shadowWrapper.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [shadowWrapper.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
        [shadowWrapper.widthAnchor   constraintEqualToAnchor:self.view.widthAnchor multiplier:0.88],
        [shadowWrapper.heightAnchor  constraintLessThanOrEqualToAnchor:self.view.heightAnchor multiplier:0.84],
        [card.topAnchor      constraintEqualToAnchor:shadowWrapper.topAnchor],
        [card.leadingAnchor  constraintEqualToAnchor:shadowWrapper.leadingAnchor],
        [card.trailingAnchor constraintEqualToAnchor:shadowWrapper.trailingAnchor],
        [card.bottomAnchor   constraintEqualToAnchor:shadowWrapper.bottomAnchor],

        [titleLabel.topAnchor     constraintEqualToAnchor:card.topAnchor constant:18],
        [titleLabel.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16],
        [titleLabel.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16],

        [subLabel.topAnchor      constraintEqualToAnchor:titleLabel.bottomAnchor constant:3],
        [subLabel.leadingAnchor  constraintEqualToAnchor:card.leadingAnchor constant:16],
        [subLabel.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16],

        [masterRow.topAnchor      constraintEqualToAnchor:subLabel.bottomAnchor constant:14],
        [masterRow.leadingAnchor  constraintEqualToAnchor:card.leadingAnchor],
        [masterRow.trailingAnchor constraintEqualToAnchor:card.trailingAnchor],
        [masterRow.heightAnchor   constraintEqualToConstant:52],
        
        [masterLabel.leadingAnchor  constraintEqualToAnchor:masterRow.leadingAnchor constant:16],
        [masterLabel.centerYAnchor  constraintEqualToAnchor:masterRow.centerYAnchor],
        
        [masterSwitch.trailingAnchor constraintEqualToAnchor:masterRow.trailingAnchor constant:-16],
        [masterSwitch.centerYAnchor  constraintEqualToAnchor:masterRow.centerYAnchor],
        
        [separator.leadingAnchor  constraintEqualToAnchor:masterRow.leadingAnchor],
        [separator.trailingAnchor constraintEqualToAnchor:masterRow.trailingAnchor],
        [separator.bottomAnchor   constraintEqualToAnchor:masterRow.bottomAnchor],
        [separator.heightAnchor   constraintEqualToConstant:0.5],

        [self.tableView.topAnchor      constraintEqualToAnchor:masterRow.bottomAnchor constant:16],
        [self.tableView.leadingAnchor  constraintEqualToAnchor:card.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:card.trailingAnchor],
        [self.tableView.heightAnchor   constraintEqualToConstant:maxTH],

        [buttonBar.topAnchor      constraintEqualToAnchor:self.tableView.bottomAnchor],
        [buttonBar.leadingAnchor  constraintEqualToAnchor:card.leadingAnchor],
        [buttonBar.trailingAnchor constraintEqualToAnchor:card.trailingAnchor],
        [buttonBar.bottomAnchor   constraintEqualToAnchor:card.bottomAnchor],
        [buttonBar.heightAnchor   constraintEqualToConstant:54],
        
        [btnSep.topAnchor    constraintEqualToAnchor:buttonBar.topAnchor],
        [btnSep.leadingAnchor constraintEqualToAnchor:buttonBar.leadingAnchor],
        [btnSep.trailingAnchor constraintEqualToAnchor:buttonBar.trailingAnchor],
        [btnSep.heightAnchor  constraintEqualToConstant:0.5],

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

    // Use saved value, not live state: when master is OFF all live values are NO,
    // which would make the overlay look blank even though JIT/UA default to ON.
    id saved = self.pendingRules[key];
    sw.on = saved ? [saved boolValue] : ads_default_value_for_key(key);

    return cell;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return 52;
}

- (void)switchChanged:(UISwitch *)sender {
    if (sender.tag == NSIntegerMax) {
        self.pendingPrefs[@"enabled"] = @(sender.on);
        [UIView animateWithDuration:0.25 animations:^{
            sender.superview.backgroundColor = sender.on 
                ? [UIColor colorWithRed:0.08 green:0.25 blue:0.12 alpha:1.0] 
                : [UIColor colorWithRed:0.25 green:0.08 blue:0.08 alpha:1.0];
        }];
        return;
    }

    NSString *key = self.rows[(NSUInteger)sender.tag][@"key"];
    self.pendingRules[key] = @(sender.on);
    
    // JS cascade: JS ON → lock JIT on (JIT must be off when JS is disabled).
    //             JS OFF → unlock JIT (user decides independently).
    if ([key isEqualToString:@"disableJS"]) {
        self.jsLocked = sender.on;
        NSInteger jitIdx = -1;
        for (NSUInteger i = 0; i < self.rows.count; i++) {
            NSString *k = self.rows[i][@"key"];
            if ([k isEqualToString:@"disableJIT"] || [k isEqualToString:@"disableJIT15"]) {
                jitIdx = (NSInteger)i;
                break;
            }
        }

        if (jitIdx >= 0) {
            NSString *jitKey       = self.rows[(NSUInteger)jitIdx][@"key"];
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
    NSString *rulesKey       = [NSString stringWithFormat:@"TargetRules_%@", self.bundleID];
    self.pendingPrefs[rulesKey] = [self.pendingRules copy];
    ads_write_prefs(self.pendingPrefs);

    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         CFSTR("com.eolnmsuk.antidarkswordprefs/saved"),
                                         NULL, NULL, YES);
                                         
    [self dismissViewControllerAnimated:YES completion:^{
        UIAlertController *alert = [UIAlertController
            alertControllerWithTitle:@"Settings Saved"
            message:@"Restart app now to save?"
            preferredStyle:UIAlertControllerStyleAlert];

        [alert addAction:[UIAlertAction actionWithTitle:@"Restart App Now"
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

static void ads_present_overlay_on_main(void) {
    UIWindow *win = ads_key_window();
    UIViewController *top = win ? ads_top_vc(win.rootViewController) : nil;
    if (!top || [top isKindOfClass:[ADSTFSettingsViewController class]]) return;
    ADSTFSettingsViewController *vc = [[ADSTFSettingsViewController alloc] init];
    vc.modalPresentationStyle = UIModalPresentationOverFullScreen;
    vc.modalTransitionStyle   = UIModalTransitionStyleCrossDissolve;
    [top presentViewController:vc animated:YES completion:nil];
}

static void ads_show_settings_overlay(void) {
    UIWindow *win = ads_key_window();
    UIViewController *top = win ? ads_top_vc(win.rootViewController) : nil;
    if (!top) return;
    if ([top isKindOfClass:[ADSTFSettingsViewController class]]) return;

    // Gate the settings overlay behind device owner authentication (Face ID / Touch ID /
    // passcode fallback) so a malicious app cannot synthesise the gesture to disable mitigations.
    LAContext *ctx = [[LAContext alloc] init];
    NSError *biometryError = nil;
    // LAPolicyDeviceOwnerAuthentication includes biometrics with automatic passcode fallback.
    if ([ctx canEvaluatePolicy:LAPolicyDeviceOwnerAuthentication error:&biometryError]) {
        [ctx evaluatePolicy:LAPolicyDeviceOwnerAuthentication
            localizedReason:@"Authenticate to access AntiDarkSword settings"
                      reply:^(BOOL success, NSError *authError) {
            if (success) {
                dispatch_async(dispatch_get_main_queue(), ^{ ads_present_overlay_on_main(); });
            } else {
                ADSLog(@"[AUTH] Settings overlay auth failed: %@", authError.localizedDescription);
            }
        }];
    } else {
        // No passcode set — fall through directly (device is already unlocked if reachable here).
        ads_present_overlay_on_main();
    }
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

    // Pre-compile the remote content blocker used by "Block Remote Content".
    // Blocks external http/https resource loads in WKWebViews — the main attack
    // surface for zero-click exploits delivered via HTML email in Mail.app.
    // Compilation is async and WebKit caches the result; subsequent launches
    // reuse the cached build. The completion handler stores the result in
    // adsContentBlocker; applyWebKitMitigations applies it when the flag is ON.
    NSString *blockRules =
        @"[{\"trigger\":{\"url-filter\":\"^https?://\","
         "\"resource-type\":[\"image\",\"style-sheet\",\"script\","
         "\"font\",\"media\",\"svg-document\",\"raw\"]},"
         "\"action\":{\"type\":\"block\"}}]";
    // completionHandler fires on an arbitrary queue; adsContentBlocker is read
    // from WebKit hooks on the main thread, so the assignment must be main-queue.
    [WKContentRuleListStore.defaultStore
        compileContentRuleListForIdentifier:@"com.eolnmsuk.ads.remoteblock"
        encodedContentRuleList:blockRules
        completionHandler:^(WKContentRuleList *list, NSError *err) {
            if (list) dispatch_async(dispatch_get_main_queue(), ^{ adsContentBlocker = list; });
            else ADSLog(@"[WARN] Remote content blocker compile failed: %@", err);
        }];

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
