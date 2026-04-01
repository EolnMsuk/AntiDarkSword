#import <Foundation/Foundation.h>
#import <WebKit/WebKit.h>
#import <JavaScriptCore/JavaScriptCore.h>

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

static void loadPrefs() {
    NSDictionary *prefs = nil;
    if ([[NSFileManager defaultManager] fileExistsAtPath:PREFS_PATH]) {
        prefs = [NSDictionary dictionaryWithContentsOfFile:PREFS_PATH];
    } else if ([[NSFileManager defaultManager] fileExistsAtPath:ROOTFUL_PREFS_PATH]) {
        prefs = [NSDictionary dictionaryWithContentsOfFile:ROOTFUL_PREFS_PATH];
    }

    BOOL autoProtectEnabled = NO;
    NSInteger autoProtectLevel = 1;
    NSArray *restrictedApps = @[];
    NSArray *activeCustomDaemonIDs = @[];

    if (prefs) {
        globalTweakEnabled = prefs[@"enabled"] ? [prefs[@"enabled"] boolValue] : NO;
        autoProtectEnabled = prefs[@"autoProtectEnabled"] ? [prefs[@"autoProtectEnabled"] boolValue] : NO;
        autoProtectLevel = prefs[@"autoProtectLevel"] ? [prefs[@"autoProtectLevel"] integerValue] : 1;
        
        // Isolate AltList from Custom Daemons to prevent overriding
        restrictedApps = prefs[@"restrictedApps"] ?: @[];
        activeCustomDaemonIDs = prefs[@"activeCustomDaemonIDs"] ?: prefs[@"customDaemonIDs"] ?: @[];
        
        // Load User Agent Settings
        NSString *presetUA = prefs[@"selectedUAPreset"];
        NSString *manualUA = prefs[@"customUAString"];
        
        // If Custom is selected in the dropdown (or nothing is selected yet), use the text box string
        if (!presetUA || [presetUA isEqualToString:@"CUSTOM"]) {
            customUAString = manualUA ?: @"";
        } else {
            customUAString = presetUA;
        }
    }
    
    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
    NSString *processName = [[NSProcessInfo processInfo] processName];
    BOOL isTargetRestricted = NO;

    // 1. ALWAYS Evaluate Manual / Custom Array (Applies regardless of Preset Rules state)
    if (bundleID && [activeCustomDaemonIDs containsObject:bundleID]) {
        isTargetRestricted = YES;
    } else if (processName && [activeCustomDaemonIDs containsObject:processName]) {
        isTargetRestricted = YES;
    }

    // 2. Evaluate Preset Rules OR "Select Apps..." 
    if (!isTargetRestricted) {
        if (autoProtectEnabled) {
            NSArray *tier1 = @[
                @"com.apple.mobilesafari", @"com.apple.MobileSMS", @"com.apple.mobilemail",
                @"com.apple.mobilecal", @"com.apple.mobilenotes", @"com.apple.iBooks",
                @"com.apple.news", @"com.apple.podcasts", @"com.apple.stocks", 
                @"com.apple.Maps", @"com.apple.weather",
                @"com.apple.SafariViewService", @"com.apple.MailCompositionService",
                @"com.apple.iMessageAppsViewService", @"com.apple.ActivityMessagesApp"
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

%hook WKWebView
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
    
    // ANTI-FINGERPRINTING LOGIC
    if (globalTweakEnabled && customUAString && customUAString.length > 0) {
        
        // 1. Dynamic Platform & Vendor Derivation based on the UA string
        NSString *platform = @"iPhone";
        if ([customUAString containsString:@"iPad"]) platform = @"iPad";
        else if ([customUAString containsString:@"Macintosh"]) platform = @"MacIntel";
        else if ([customUAString containsString:@"Windows"]) platform = @"Win32";
        else if ([customUAString containsString:@"Android"]) platform = @"Linux aarch64";

        NSString *vendor = @"Apple Computer, Inc.";
        if ([customUAString containsString:@"Chrome"] || [customUAString containsString:@"Android"]) {
            vendor = @"Google Inc.";
        }

        // appVersion is standardly the UA string stripped of the "Mozilla/" prefix
        NSString *appVersion = customUAString;
        if ([customUAString hasPrefix:@"Mozilla/"]) {
            appVersion = [customUAString substringFromIndex:8];
        }

        // Escape single quotes just in case a custom string has them
        NSString *safeUA = [customUAString stringByReplacingOccurrencesOfString:@"'" withString:@"\\'"];
        NSString *safeAppVersion = [appVersion stringByReplacingOccurrencesOfString:@"'" withString:@"\\'"];

        // 2. Build the JS Injection to override the Navigator object
        NSString *jsSource = [NSString stringWithFormat:@"\
            Object.defineProperty(navigator, 'userAgent', { get: () => '%@' });\n\
            Object.defineProperty(navigator, 'appVersion', { get: () => '%@' });\n\
            Object.defineProperty(navigator, 'platform', { get: () => '%@' });\n\
            Object.defineProperty(navigator, 'vendor', { get: () => '%@' });\n\
        ", safeUA, safeAppVersion, platform, vendor];

        WKUserScript *antiFingerprintScript = [[WKUserScript alloc] initWithSource:jsSource 
                                                                     injectionTime:WKUserScriptInjectionTimeAtDocumentStart 
                                                                  forMainFrameOnly:NO];
        
        // Ensure userContentController exists
        if (!configuration.userContentController) {
            configuration.userContentController = [[WKUserContentController alloc] init];
        }
        [configuration.userContentController addUserScript:antiFingerprintScript];
    }
    
    WKWebView *webView = %orig(frame, configuration);
    
    // 3. Set the native property (handles the HTTP headers)
    if (globalTweakEnabled && customUAString && customUAString.length > 0) {
        if ([webView respondsToSelector:@selector(setCustomUserAgent:)]) {
            webView.customUserAgent = customUAString;
        }
    }
    
    return webView;
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
