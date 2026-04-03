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

// App-Specific Granular Features
static BOOL disableJS = YES;
static BOOL disableMedia = YES;
static BOOL disableRTC = YES;
static BOOL disableFileAccess = YES;
static BOOL disableIMessageDL = YES;

static void loadPrefs() {
    NSDictionary *prefs = nil;

    if ([[NSFileManager defaultManager] fileExistsAtPath:PREFS_PATH]) {
        prefs = [NSDictionary dictionaryWithContentsOfFile:PREFS_PATH];
    } else if ([[NSFileManager defaultManager] fileExistsAtPath:ROOTFUL_PREFS_PATH]) {
        prefs = [NSDictionary dictionaryWithContentsOfFile:ROOTFUL_PREFS_PATH];
    }
    
    // Fallback: If sandbox blocks direct file access, use IPC via CFPreferences
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
    NSArray *activeCustomDaemonIDs = @[];
    NSArray *disabledPresetRules = @[];
    
    // Extract AltList selections properly via prefix scanning
    NSMutableArray *restrictedAppsArray = [NSMutableArray array];
    if (prefs) {
        // Fallback checks for old installations still saving via dictionary
        id restrictedAppsRaw = prefs[@"restrictedApps"];
        if ([restrictedAppsRaw isKindOfClass:[NSDictionary class]]) {
            for (NSString *key in [restrictedAppsRaw allKeys]) {
                if ([restrictedAppsRaw[key] boolValue]) [restrictedAppsArray addObject:key];
            }
        } else if ([restrictedAppsRaw isKindOfClass:[NSArray class]]) {
            [restrictedAppsArray addObjectsFromArray:restrictedAppsRaw];
        }

        // Standard AltList prefix fetching strategy
        for (NSString *key in [prefs allKeys]) {
            if ([key hasPrefix:@"restrictedApps-"] && [prefs[key] boolValue]) {
                NSString *appID = [key substringFromIndex:@"restrictedApps-".length];
                if (![restrictedAppsArray containsObject:appID]) {
                    [restrictedAppsArray addObject:appID];
                }
            }
        }

        globalTweakEnabled = prefs[@"enabled"] ? [prefs[@"enabled"] boolValue] : NO;
        autoProtectEnabled = prefs[@"autoProtectEnabled"] ? [prefs[@"autoProtectEnabled"] boolValue] : NO;
        autoProtectLevel = prefs[@"autoProtectLevel"] ? [prefs[@"autoProtectLevel"] integerValue] : 1;
        activeCustomDaemonIDs = prefs[@"activeCustomDaemonIDs"] ?: prefs[@"customDaemonIDs"] ?: @[];
        disabledPresetRules = prefs[@"disabledPresetRules"] ?: @[];
        
        NSString *presetUA = prefs[@"selectedUAPreset"];
        // Fallback/Upgrade Migration check natively if legacy string left behind or never set.
        if (!presetUA || [presetUA isEqualToString:@"NONE"]) {
            presetUA = @"Mozilla/5.0 (iPhone; CPU iPhone OS 18_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1";
        }
        
        NSString *manualUA = prefs[@"customUAString"];
        if ([presetUA isEqualToString:@"CUSTOM"]) {
            customUAString = manualUA ?: @"";
        } else {
            customUAString = presetUA;
        }
    }
    
    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
    NSString *processName = [[NSProcessInfo processInfo] processName];
    BOOL isTargetRestricted = NO;
    NSString *matchedID = nil;

    // Highest Priority: Custom Daemons Override
    if (bundleID && [activeCustomDaemonIDs containsObject:bundleID]) {
        isTargetRestricted = YES;
        matchedID = bundleID;
    } else if (processName && [activeCustomDaemonIDs containsObject:processName]) {
        isTargetRestricted = YES;
        matchedID = processName;
    }

    if (!isTargetRestricted) {
        // Priority 2: Manual Select Apps
        if (bundleID && [restrictedAppsArray containsObject:bundleID]) {
            isTargetRestricted = YES;
            matchedID = bundleID;
        } else if (processName && [restrictedAppsArray containsObject:processName]) {
            isTargetRestricted = YES;
            matchedID = processName;
        }
        
        // Priority 3: Auto Protect evaluation combined with disable-list tracking
        if (!isTargetRestricted && autoProtectEnabled) {
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
                @"com.apple.imagent", @"imagent", @"mediaserverd", @"networkd", @"apsd", @"identityservicesd"
            ];

            NSString *targetMatch = nil;
            if (bundleID) {
                if ([tier1 containsObject:bundleID]) targetMatch = bundleID;
                else if (autoProtectLevel >= 2 && [tier2 containsObject:bundleID]) targetMatch = bundleID;
                else if (autoProtectLevel >= 3 && [tier3 containsObject:bundleID]) targetMatch = bundleID;
            }
            if (!targetMatch && processName) {
                if ([tier1 containsObject:processName]) targetMatch = processName;
                else if (autoProtectLevel >= 2 && [tier2 containsObject:processName]) targetMatch = processName;
                else if (autoProtectLevel >= 3 && [tier3 containsObject:processName]) targetMatch = processName;
            }
            
            // Only restrict if the matched preset tier item wasn't manually switched off 
            if (targetMatch && ![disabledPresetRules containsObject:targetMatch]) {
                isTargetRestricted = YES;
                matchedID = targetMatch;
            }
        }
    }
    
    currentProcessRestricted = (globalTweakEnabled && isTargetRestricted);

    // Read App-Specific Granular Rules
    disableJS = YES;
    disableMedia = YES;
    disableRTC = YES;
    disableFileAccess = YES;
    disableIMessageDL = YES;
    BOOL spoofUARule = YES; 

    NSArray *daemonDenylist = @[
        @"com.apple.appstored", @"com.apple.itunesstored",
        @"com.apple.imagent", @"com.apple.mediaserverd",
        @"com.apple.networkd", @"com.apple.apsd",
        @"com.apple.identityservicesd", @"com.apple.nsurlsessiond",
        @"com.apple.cfnetwork"
    ];
    if (matchedID && [daemonDenylist containsObject:matchedID]) {
        spoofUARule = NO;
    } else if (processName && ([processName containsString:@"daemon"] || [processName hasSuffix:@"d"])) {
        spoofUARule = NO;
    }

    if (currentProcessRestricted && matchedID && prefs) {
        NSString *dictKey = [NSString stringWithFormat:@"TargetRules_%@", matchedID];
        NSDictionary *appRules = prefs[dictKey];
        if (appRules && [appRules isKindOfClass:[NSDictionary class]]) {
            if (appRules[@"disableJS"] != nil) disableJS = [appRules[@"disableJS"] boolValue];
            if (appRules[@"disableMedia"] != nil) disableMedia = [appRules[@"disableMedia"] boolValue];
            if (appRules[@"disableRTC"] != nil) disableRTC = [appRules[@"disableRTC"] boolValue];
            if (appRules[@"disableFileAccess"] != nil) disableFileAccess = [appRules[@"disableFileAccess"] boolValue];
            if (appRules[@"disableIMessageDL"] != nil) disableIMessageDL = [appRules[@"disableIMessageDL"] boolValue];
            if (appRules[@"spoofUA"] != nil) spoofUARule = [appRules[@"spoofUA"] boolValue];
        }
    }

    // Evaluate App-Specific User Agent Spoofing 
    shouldSpoofUA = NO;
    if (currentProcessRestricted && spoofUARule && globalTweakEnabled && customUAString && customUAString.length > 0 && ![customUAString isEqualToString:@"NONE"]) {
        shouldSpoofUA = YES;
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

- (void)setApplicationNameForUserAgent:(NSString *)applicationNameForUserAgent {
    if (shouldSpoofUA) {
        return %orig(@"");
    }
    %orig;
}
%end


%hook WKWebView

- (instancetype)initWithFrame:(CGRect)frame configuration:(WKWebViewConfiguration *)configuration {
    if (isAppRestricted()) {
        if (disableJS) {
            if ([configuration respondsToSelector:@selector(defaultWebpagePreferences)]) configuration.defaultWebpagePreferences.allowsContentJavaScript = NO;
            if ([configuration.preferences respondsToSelector:@selector(setJavaScriptEnabled:)]) configuration.preferences.javaScriptEnabled = NO;
            if ([configuration.preferences respondsToSelector:@selector(setJavaScriptCanOpenWindowsAutomatically:)]) configuration.preferences.javaScriptCanOpenWindowsAutomatically = NO;
        }
        
        if (disableMedia) {
            if ([configuration respondsToSelector:@selector(setAllowsInlineMediaPlayback:)]) configuration.allowsInlineMediaPlayback = NO;
            if ([configuration respondsToSelector:@selector(setMediaTypesRequiringUserActionForPlayback:)]) configuration.mediaTypesRequiringUserActionForPlayback = WKAudiovisualMediaTypeAll;
            if ([configuration respondsToSelector:@selector(setAllowsPictureInPictureMediaPlayback:)]) configuration.allowsPictureInPictureMediaPlayback = NO;
        }
        
        if ([configuration.preferences respondsToSelector:@selector(setValue:forKey:)]) {
            @try {
                if (disableFileAccess) {
                    [configuration.preferences setValue:@NO forKey:@"allowFileAccessFromFileURLs"];
                    [configuration.preferences setValue:@NO forKey:@"allowUniversalAccessFromFileURLs"];
                }
                if (disableRTC) {
                    [configuration.preferences setValue:@NO forKey:@"webGLEnabled"];
                    [configuration.preferences setValue:@NO forKey:@"mediaStreamEnabled"]; 
                    [configuration.preferences setValue:@NO forKey:@"peerConnectionEnabled"];
                }
            } @catch (NSException *e) {}
        }
    }
    
    if (shouldSpoofUA) {
        if (!configuration.userContentController) {
            configuration.userContentController = [[WKUserContentController alloc] init];
        }
    }
    
    WKWebView *webView = %orig(frame, configuration);
    if (shouldSpoofUA) {
        if ([webView respondsToSelector:@selector(setCustomUserAgent:)]) {
            webView.customUserAgent = customUAString;
        }
    }
    
    return webView;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    WKWebView *webView = %orig(coder);
    if (!webView) return nil;

    if (isAppRestricted()) {
        if (disableJS) {
            if ([webView.configuration respondsToSelector:@selector(defaultWebpagePreferences)]) webView.configuration.defaultWebpagePreferences.allowsContentJavaScript = NO;
            if ([webView.configuration.preferences respondsToSelector:@selector(setJavaScriptEnabled:)]) webView.configuration.preferences.javaScriptEnabled = NO;
            if ([webView.configuration.preferences respondsToSelector:@selector(setJavaScriptCanOpenWindowsAutomatically:)]) webView.configuration.preferences.javaScriptCanOpenWindowsAutomatically = NO;
        }
        
        if (disableMedia) {
            if ([webView.configuration respondsToSelector:@selector(setAllowsInlineMediaPlayback:)]) webView.configuration.allowsInlineMediaPlayback = NO;
            if ([webView.configuration respondsToSelector:@selector(setMediaTypesRequiringUserActionForPlayback:)]) webView.configuration.mediaTypesRequiringUserActionForPlayback = WKAudiovisualMediaTypeAll;
            if ([webView.configuration respondsToSelector:@selector(setAllowsPictureInPictureMediaPlayback:)]) webView.configuration.allowsPictureInPictureMediaPlayback = NO;
        }
        
        if ([webView.configuration.preferences respondsToSelector:@selector(setValue:forKey:)]) {
            @try {
                if (disableFileAccess) {
                    [webView.configuration.preferences setValue:@NO forKey:@"allowFileAccessFromFileURLs"];
                    [webView.configuration.preferences setValue:@NO forKey:@"allowUniversalAccessFromFileURLs"];
                }
                if (disableRTC) {
                    [webView.configuration.preferences setValue:@NO forKey:@"webGLEnabled"];
                    [webView.configuration.preferences setValue:@NO forKey:@"mediaStreamEnabled"]; 
                    [webView.configuration.preferences setValue:@NO forKey:@"peerConnectionEnabled"];
                }
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

- (WKNavigation *)loadRequest:(NSURLRequest *)request {
    if (isAppRestricted() && disableJS) {
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
    if (isAppRestricted() && disableJS) {
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

- (void)evaluateJavaScript:(NSString *)javaScriptString completionHandler:(void (^)(id, NSError *))completionHandler {
    if (isAppRestricted() && disableJS) {
        if (completionHandler) {
            NSError *err = [NSError errorWithDomain:@"AntiDarkSword" code:1 userInfo:@{NSLocalizedDescriptionKey: @"JS execution blocked"}];
            completionHandler(nil, err);
        }
        return;
    }
    %orig;
}

- (void)evaluateJavaScript:(NSString *)javaScriptString inFrame:(WKFrameInfo *)frame inContentWorld:(WKContentWorld *)contentWorld completionHandler:(void (^)(id, NSError *))completionHandler {
    if (isAppRestricted() && disableJS) {
        if (completionHandler) {
            NSError *err = [NSError errorWithDomain:@"AntiDarkSword" code:1 userInfo:@{NSLocalizedDescriptionKey: @"JS execution blocked"}];
            completionHandler(nil, err);
        }
        return;
    }
    %orig;
}

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
    if (isAppRestricted() && disableJS && allowed) {
        return %orig(NO);
    }
    %orig;
}
%end

%hook WKPreferences
- (void)setJavaScriptEnabled:(BOOL)enabled {
    if (isAppRestricted() && disableJS && enabled) {
        return %orig(NO);
    }
    %orig;
}
%end

%hookf(JSValueRef, JSEvaluateScript, JSContextRef ctx, JSStringRef script, JSObjectRef thisObject, JSStringRef sourceURL, int startingLineNumber, JSValueRef *exception) {
    if (isAppRestricted() && disableJS) {
        return NULL;
    }
    return %orig(ctx, script, thisObject, sourceURL, startingLineNumber, exception);
}

// =========================================================
// LEGACY UIWEBVIEW NEUTRALIZATION
// =========================================================

%hook UIWebView
- (NSString *)stringByEvaluatingJavaScriptFromString:(NSString *)script {
    if (isAppRestricted() && disableJS) {
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
    if (isAppRestricted() && disableIMessageDL) {
        return NO;
    }
    return %orig;
}
- (BOOL)canAutoDownload {
    if (isAppRestricted() && disableIMessageDL) {
        return NO;
    }
    return %orig;
}
%end

%hook CKAttachmentMessagePartChatItem
- (BOOL)_needsPreviewGeneration {
    if (isAppRestricted() && disableIMessageDL) {
        return NO;
    }
    return %orig;
}
%end
