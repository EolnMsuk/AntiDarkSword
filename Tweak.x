#import <Foundation/Foundation.h>
#import <WebKit/WebKit.h>
#import <JavaScriptCore/JavaScriptCore.h>
#import <CoreFoundation/CoreFoundation.h>

@interface IMFileTransfer : NSObject
- (BOOL)isAutoDownloadable;
- (BOOL)canAutoDownload;
@end

@interface CKAttachmentMessagePartChatItem : NSObject
- (BOOL)_needsPreviewGeneration;
@end

#define PREFS_PATH @"/var/jb/var/mobile/Library/Preferences/com.eolnmsuk.antidarkswordprefs.plist"
#define ROOTFUL_PREFS_PATH @"/var/mobile/Library/Preferences/com.eolnmsuk.antidarkswordprefs.plist"

static _Atomic BOOL currentProcessRestricted = NO;
static BOOL globalTweakEnabled = NO;
static NSString *customUAString = @"";
static BOOL shouldSpoofUA = NO;

static void loadPrefs() {
    NSDictionary *prefs = nil;
    
    // Attempt standard file read
    if ([[NSFileManager defaultManager] fileExistsAtPath:PREFS_PATH]) {
        prefs = [NSDictionary dictionaryWithContentsOfFile:PREFS_PATH];
    } else if ([[NSFileManager defaultManager] fileExistsAtPath:ROOTFUL_PREFS_PATH]) {
        prefs = [NSDictionary dictionaryWithContentsOfFile:ROOTFUL_PREFS_PATH];
    }
    
    // Fallback: If sandbox blocks direct file access (e.g., WebContent daemons, SafariViewService), use IPC via CFPreferences
    if (!prefs) {
        CFArrayRef keyList = CFPreferencesCopyKeyList(CFSTR("com.eolnmsuk.antidarkswordprefs"), kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
        if (keyList) {
            CFDictionaryRef dict = CFPreferencesCopyMultiple(keyList, CFSTR("com.eolnmsuk.antidarkswordprefs"), kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
            if (dict) {
                prefs = (__bridge_transfer NSDictionary *)dict;
            }
            CFRelease(keyList);
        }
    }

    BOOL autoProtectEnabled = NO;
    NSInteger autoProtectLevel = 1;
    NSArray *restrictedApps = @[];
    NSArray *activeCustomDaemonIDs = @[];
    
    if (prefs) {
        globalTweakEnabled = prefs[@"enabled"] ? [prefs[@"enabled"] boolValue] : NO;
        autoProtectEnabled = prefs[@"autoProtectEnabled"] ? [prefs[@"autoProtectEnabled"] boolValue] : NO;
        autoProtectLevel = prefs[@"autoProtectLevel"] ? [prefs[@"autoProtectLevel"] integerValue] : 1;
        restrictedApps = prefs[@"restrictedApps"] ?: @[];
        activeCustomDaemonIDs = prefs[@"activeCustomDaemonIDs"] ?: prefs[@"customDaemonIDs"] ?: @[];
        
        NSString *presetUA = prefs[@"selectedUAPreset"];
        NSString *manualUA = prefs[@"customUAString"];
        if (!presetUA || [presetUA isEqualToString:@"CUSTOM"]) {
            customUAString = manualUA ?: @"";
        } else {
            customUAString = presetUA;
        }
    }
    
    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
    NSString *processName = [[NSProcessInfo processInfo] processName];
    BOOL isTargetRestricted = NO;
    
    if (bundleID && [activeCustomDaemonIDs containsObject:bundleID]) {
        isTargetRestricted = YES;
    } else if (processName && [activeCustomDaemonIDs containsObject:processName]) {
        isTargetRestricted = YES;
    }

    if (!isTargetRestricted) {
        if (autoProtectEnabled) {
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
            
            if (bundleID) {
                if ([tier1 containsObject:bundleID]) isTargetRestricted = YES;
                if (autoProtectLevel >= 2 && [tier2 containsObject:bundleID]) isTargetRestricted = YES;
                if (autoProtectLevel >= 3 && [tier3 containsObject:bundleID]) isTargetRestricted = YES;
            }
            
            if (processName && !isTargetRestricted) {
                if ([tier1 containsObject:processName]) isTargetRestricted = YES;
                if (autoProtectLevel >= 2 && [tier2 containsObject:processName]) isTargetRestricted = YES;
                if (autoProtectLevel >= 3 && [tier3 containsObject:processName]) isTargetRestricted = YES;
            }
        } else {
            if (bundleID && [restrictedApps containsObject:bundleID]) {
                isTargetRestricted = YES;
            } else if (processName && [restrictedApps containsObject:processName]) {
                isTargetRestricted = YES;
            }
        }
    }
    
    currentProcessRestricted = (globalTweakEnabled && isTargetRestricted);
    
    // Evaluate if we should apply User Agent Spoofing to this specific process
    shouldSpoofUA = NO;
    if (globalTweakEnabled && customUAString && customUAString.length > 0) {
        // Apps that legitimately need UA spoofing for anti-fingerprinting
        NSArray *uaSpoofTargets = @[
            @"com.apple.mobilesafari", @"com.apple.SafariViewService",
            @"com.google.chrome.ios", @"org.mozilla.ios.Firefox",
            @"com.brave.ios.browser", @"com.duckduckgo.mobile.ios",
            @"com.apple.news", @"com.reddit.Reddit", @"com.atebits.Tweetie2",
            @"com.facebook.Facebook", @"com.burbn.instagram", @"com.google.ios.youtube",
            @"com.hammerandchisel.discord", @"com.zhiliaoapp.musically",
            @"org.telegram.messenger", @"net.whatsapp.WhatsApp"
        ];
        
        // Critical daemons that MUST NOT have their UA spoofed
        NSArray *daemonDenylist = @[
            @"com.apple.appstored", @"com.apple.itunesstored",
            @"com.apple.imagent", @"com.apple.mediaserverd",
            @"com.apple.networkd", @"com.apple.apsd",
            @"com.apple.identityservicesd", @"com.apple.nsurlsessiond",
            @"com.apple.cfnetwork"
        ];
        
        if (bundleID && [uaSpoofTargets containsObject:bundleID]) {
            shouldSpoofUA = YES;
        } else if (isTargetRestricted) {
            // Allow user-restricted apps to have spoofed UA, as long as it isn't a known daemon
            if (!bundleID || ![daemonDenylist containsObject:bundleID]) {
                shouldSpoofUA = YES;
            }
        }
        
        // Extra safeguard: catch processes ending in 'd' or 'daemon' explicitly to avoid spoofing background tasks
        if (processName && ([processName containsString:@"daemon"] || [processName hasSuffix:@"d"])) {
            shouldSpoofUA = NO;
        }
    }
}

static BOOL isAppRestricted() {
    return currentProcessRestricted;
}

%ctor {
    loadPrefs();
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, (CFNotificationCallback)loadPrefs, CFSTR("com.eolnmsuk.antidarkswordprefs/saved"), NULL, CFNotificationSuspensionBehaviorCoalesce);
}

// =========================================================
// WEBKIT EXPLOIT MITIGATIONS & ANTI-FINGERPRINTING
// =========================================================

%hook WKWebViewConfiguration

// Intercept dynamic resetting of the content controller (common in Filza/Browsers)
- (void)setUserContentController:(WKUserContentController *)userContentController {
    %orig;
    if (shouldSpoofUA) {
        NSString *platform = @"iPhone";
        if ([customUAString containsString:@"iPad"]) platform = @"iPad";
        else if ([customUAString containsString:@"Macintosh"]) platform = @"MacIntel";
        else if ([customUAString containsString:@"Windows"]) platform = @"Win32";
        else if ([customUAString containsString:@"Android"]) platform = @"Linux aarch64";

        NSString *vendor = @"Apple Computer, Inc.";
        if ([customUAString containsString:@"Chrome"] || [customUAString containsString:@"Android"]) {
            vendor = @"Google Inc.";
        }

        NSString *appVersion = customUAString;
        if ([customUAString hasPrefix:@"Mozilla/"]) {
            appVersion = [customUAString substringFromIndex:8];
        }

        NSString *safeUA = [customUAString stringByReplacingOccurrencesOfString:@"'" withString:@"\\'"];
        NSString *safeAppVersion = [appVersion stringByReplacingOccurrencesOfString:@"'" withString:@"\\'"];
        NSString *jsSource = [NSString stringWithFormat:@"\
            Object.defineProperty(navigator, 'userAgent', { get: () => '%@' });\n\
            Object.defineProperty(navigator, 'appVersion', { get: () => '%@' });\n\
            Object.defineProperty(navigator, 'platform', { get: () => '%@' });\n\
            Object.defineProperty(navigator, 'vendor', { get: () => '%@' });\n\
        ", safeUA, safeAppVersion, platform, vendor];
        WKUserScript *antiFingerprintScript = [[WKUserScript alloc] initWithSource:jsSource 
                                                                     injectionTime:WKUserScriptInjectionTimeAtDocumentStart 
                                                                  forMainFrameOnly:NO];
        [userContentController addUserScript:antiFingerprintScript];
    }
}

// Block apps from modifying the user agent suffix
- (void)setApplicationNameForUserAgent:(NSString *)applicationNameForUserAgent {
    if (shouldSpoofUA) {
        return %orig(@"");
    }
    %orig;
}
%end


%hook WKWebView

// 1. Hook code-based initialization
- (instancetype)initWithFrame:(CGRect)frame configuration:(WKWebViewConfiguration *)configuration {
    if (isAppRestricted()) {
        if ([configuration respondsToSelector:@selector(defaultWebpagePreferences)]) {
            configuration.defaultWebpagePreferences.allowsContentJavaScript = NO;
        }
        if ([configuration.preferences respondsToSelector:@selector(setJavaScriptEnabled:)]) {
            configuration.preferences.javaScriptEnabled = NO;
        }
        if ([configuration.preferences respondsToSelector:@selector(setJavaScriptCanOpenWindowsAutomatically:)]) {
            configuration.preferences.javaScriptCanOpenWindowsAutomatically = NO;
        }
        if ([configuration respondsToSelector:@selector(setAllowsInlineMediaPlayback:)]) {
            configuration.allowsInlineMediaPlayback = NO;
        }
        if ([configuration respondsToSelector:@selector(setMediaTypesRequiringUserActionForPlayback:)]) {
            configuration.mediaTypesRequiringUserActionForPlayback = WKAudiovisualMediaTypeAll;
        }
        if ([configuration respondsToSelector:@selector(setAllowsPictureInPictureMediaPlayback:)]) {
            configuration.allowsPictureInPictureMediaPlayback = NO;
        }
        if ([configuration.preferences respondsToSelector:@selector(setValue:forKey:)]) {
            @try {
                [configuration.preferences setValue:@NO forKey:@"allowFileAccessFromFileURLs"];
                [configuration.preferences setValue:@NO forKey:@"allowUniversalAccessFromFileURLs"];
                [configuration.preferences setValue:@NO forKey:@"webGLEnabled"];
                [configuration.preferences setValue:@NO forKey:@"mediaStreamEnabled"]; 
                [configuration.preferences setValue:@NO forKey:@"peerConnectionEnabled"];
            } @catch (NSException *e) {}
        }
    }
    
    if (shouldSpoofUA) {
        if (!configuration.userContentController) {
            configuration.userContentController = [[WKUserContentController alloc] init];
        }
        // Will be handled by WKWebViewConfiguration hook above!
    }
    
    WKWebView *webView = %orig(frame, configuration);
    if (shouldSpoofUA) {
        if ([webView respondsToSelector:@selector(setCustomUserAgent:)]) {
            webView.customUserAgent = customUAString;
        }
    }
    
    return webView;
}

// 2. Hook Storyboard/Interface Builder initialization
- (instancetype)initWithCoder:(NSCoder *)coder {
    WKWebView *webView = %orig(coder);
    if (!webView) return nil;
    
    if (isAppRestricted()) {
        if ([webView.configuration respondsToSelector:@selector(defaultWebpagePreferences)]) {
            webView.configuration.defaultWebpagePreferences.allowsContentJavaScript = NO;
        }
        if ([webView.configuration.preferences respondsToSelector:@selector(setJavaScriptEnabled:)]) {
            webView.configuration.preferences.javaScriptEnabled = NO;
        }
        if ([webView.configuration.preferences respondsToSelector:@selector(setJavaScriptCanOpenWindowsAutomatically:)]) {
            webView.configuration.preferences.javaScriptCanOpenWindowsAutomatically = NO;
        }
        if ([webView respondsToSelector:@selector(setAllowsInlineMediaPlayback:)]) {
            webView.configuration.allowsInlineMediaPlayback = NO;
        }
        if ([webView respondsToSelector:@selector(setMediaTypesRequiringUserActionForPlayback:)]) {
            webView.configuration.mediaTypesRequiringUserActionForPlayback = WKAudiovisualMediaTypeAll;
        }
        if ([webView respondsToSelector:@selector(setAllowsPictureInPictureMediaPlayback:)]) {
            webView.configuration.allowsPictureInPictureMediaPlayback = NO;
        }
        if ([webView.configuration.preferences respondsToSelector:@selector(setValue:forKey:)]) {
            @try {
                [webView.configuration.preferences setValue:@NO forKey:@"allowFileAccessFromFileURLs"];
                [webView.configuration.preferences setValue:@NO forKey:@"allowUniversalAccessFromFileURLs"];
                [webView.configuration.preferences setValue:@NO forKey:@"webGLEnabled"];
                [webView.configuration.preferences setValue:@NO forKey:@"mediaStreamEnabled"]; 
                [webView.configuration.preferences setValue:@NO forKey:@"peerConnectionEnabled"];
            } @catch (NSException *e) {}
        }
    }
    
    if (shouldSpoofUA) {
        if (!webView.configuration.userContentController) {
            webView.configuration.userContentController = [[WKUserContentController alloc] init];
        }
        if ([webView respondsToSelector:@selector(setCustomUserAgent:)]) {
            webView.customUserAgent = customUAString;
        }
    }
    
    return webView;
}

// 3. Late Binding Hooks: Catch dynamic loads
- (WKNavigation *)loadRequest:(NSURLRequest *)request {
    if (isAppRestricted()) {
        if ([self.configuration respondsToSelector:@selector(defaultWebpagePreferences)]) {
            self.configuration.defaultWebpagePreferences.allowsContentJavaScript = NO;
        }
        if ([self.configuration.preferences respondsToSelector:@selector(setJavaScriptEnabled:)]) {
            self.configuration.preferences.javaScriptEnabled = NO;
        }
    }
    
    if (shouldSpoofUA) {
        if ([self respondsToSelector:@selector(setCustomUserAgent:)]) {
            self.customUserAgent = customUAString;
        }
        
        // Intercept inline NSMutableURLRequest header overrides natively
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
    if (isAppRestricted()) {
        if ([self.configuration respondsToSelector:@selector(defaultWebpagePreferences)]) {
            self.configuration.defaultWebpagePreferences.allowsContentJavaScript = NO;
        }
        if ([self.configuration.preferences respondsToSelector:@selector(setJavaScriptEnabled:)]) {
            self.configuration.preferences.javaScriptEnabled = NO;
        }
    }
    
    if (shouldSpoofUA) {
        if ([self respondsToSelector:@selector(setCustomUserAgent:)]) {
            self.customUserAgent = customUAString;
        }
    }
    
    return %orig;
}

// 4. Forcefully block native JS execution triggers 
- (void)evaluateJavaScript:(NSString *)javaScriptString completionHandler:(void (^)(id, NSError *))completionHandler {
    if (isAppRestricted()) {
        if (completionHandler) {
            NSError *err = [NSError errorWithDomain:@"AntiDarkSword" code:1 userInfo:@{NSLocalizedDescriptionKey: @"JS execution blocked"}];
            completionHandler(nil, err);
        }
        return;
    }
    %orig;
}

// Async API for iOS 14+ 
- (void)evaluateJavaScript:(NSString *)javaScriptString inFrame:(WKFrameInfo *)frame inContentWorld:(WKContentWorld *)contentWorld completionHandler:(void (^)(id, NSError *))completionHandler {
    if (isAppRestricted()) {
        if (completionHandler) {
            NSError *err = [NSError errorWithDomain:@"AntiDarkSword" code:1 userInfo:@{NSLocalizedDescriptionKey: @"JS execution blocked"}];
            completionHandler(nil, err);
        }
        return;
    }
    %orig;
}

// 5. Prevent the app from forcefully overwriting our spoofed agent property
- (void)setCustomUserAgent:(NSString *)customUserAgent {
    if (shouldSpoofUA) {
        %orig(customUAString);
    } else {
        %orig;
    }
}
%end

%hook WKWebpagePreferences
- (void)setAllowsContentJavaScript:(BOOL)allowed {
    if (isAppRestricted() && allowed) {
        return %orig(NO);
    }
    %orig;
}
%end

%hook WKPreferences
- (void)setJavaScriptEnabled:(BOOL)enabled {
    if (isAppRestricted() && enabled) {
        return %orig(NO);
    }
    %orig;
}
%end

%hookf(JSValueRef, JSEvaluateScript, JSContextRef ctx, JSStringRef script, JSObjectRef thisObject, JSStringRef sourceURL, int startingLineNumber, JSValueRef *exception) {
    if (isAppRestricted()) {
        return NULL;
    }
    return %orig(ctx, script, thisObject, sourceURL, startingLineNumber, exception);
}

// =========================================================
// LEGACY UIWEBVIEW NEUTRALIZATION
// =========================================================

%hook UIWebView
- (NSString *)stringByEvaluatingJavaScriptFromString:(NSString *)script {
    if (isAppRestricted()) {
        return @"";
    }
    return %orig;
}
%end

// =========================================================
// NATIVE HTTP HEADER SPOOFING 
// =========================================================

%hook NSMutableURLRequest
- (void)setValue:(NSString *)value forHTTPHeaderField:(NSString *)field {
    if (shouldSpoofUA) {
        if ([field caseInsensitiveCompare:@"User-Agent"] == NSOrderedSame) {
            return %orig(customUAString, field);
        }
    }
    %orig;
}
%end

// =========================================================
// GLOBAL NSUSERDEFAULTS SPOOFING
// =========================================================

%hook NSUserDefaults
- (id)objectForKey:(NSString *)defaultName {
    if (shouldSpoofUA) {
        if ([defaultName isEqualToString:@"UserAgent"] || [defaultName isEqualToString:@"User-Agent"]) {
            return customUAString;
        }
    }
    return %orig;
}

- (NSString *)stringForKey:(NSString *)defaultName {
    if (shouldSpoofUA) {
        if ([defaultName isEqualToString:@"UserAgent"] || [defaultName isEqualToString:@"User-Agent"]) {
            return customUAString;
        }
    }
    return %orig;
}
%end

// =========================================================
// NATIVE IMESSAGE MITIGATIONS (BLASTPASS / FORCEDENTRY)
// =========================================================

%hook IMFileTransfer
- (BOOL)isAutoDownloadable {
    if (isAppRestricted()) {
        return NO;
    }
    return %orig;
}
- (BOOL)canAutoDownload {
    if (isAppRestricted()) {
        return NO;
    }
    return %orig;
}
%end

%hook CKAttachmentMessagePartChatItem
- (BOOL)_needsPreviewGeneration {
    if (isAppRestricted()) {
        return NO;
    }
    return %orig;
}
%end
