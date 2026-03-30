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

static void loadPrefs() {
    NSDictionary *prefs = nil;
    if ([[NSFileManager defaultManager] fileExistsAtPath:PREFS_PATH]) {
        prefs = [NSDictionary dictionaryWithContentsOfFile:PREFS_PATH];
    } else if ([[NSFileManager defaultManager] fileExistsAtPath:ROOTFUL_PREFS_PATH]) {
        prefs = [NSDictionary dictionaryWithContentsOfFile:ROOTFUL_PREFS_PATH];
    }

    BOOL tweakEnabled = NO;
    BOOL autoProtectEnabled = NO;
    NSInteger autoProtectLevel = 1;
    NSArray *restrictedApps = @[];
    
    if (prefs) {
        tweakEnabled = prefs[@"enabled"] ? [prefs[@"enabled"] boolValue] : NO;
        autoProtectEnabled = prefs[@"autoProtectEnabled"] ? [prefs[@"autoProtectEnabled"] boolValue] : NO;
        autoProtectLevel = prefs[@"autoProtectLevel"] ? [prefs[@"autoProtectLevel"] integerValue] : 1;
        restrictedApps = prefs[@"restrictedApps"] ?: @[];
    }
    
    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
    NSString *processName = [[NSProcessInfo processInfo] processName];
    BOOL isTargetRestricted = NO;
    
    // 1. Evaluate Auto Protect Tiers
    if (autoProtectEnabled) {
        // Level 1: All Native Apple Apps
        NSArray *tier1 = @[
            @"com.apple.mobilesafari", @"com.apple.MobileSMS", @"com.apple.mobilemail",
            @"com.apple.mobilecal", @"com.apple.mobilenotes", @"com.apple.iBooks",
            @"com.apple.news", @"com.apple.podcasts", @"com.apple.stocks", 
            @"com.apple.Maps", @"com.apple.weather"
        ];
        
        // Level 2: All Major 3rd Party Browsers, Social Media, and Package Managers
        NSArray *tier2 = @[
            @"com.google.chrome.ios", @"org.mozilla.ios.Firefox", @"com.brave.ios.browser", @"com.duckduckgo.mobile.ios",
            @"net.whatsapp.WhatsApp", @"ph.telegra.Telegraph", @"com.facebook.Facebook", @"com.atebits.Tweetie2", 
            @"com.burbn.instagram", @"com.zhiliaoapp.musically", @"com.linkedin.LinkedIn",
            @"org.coolstar.sileo", @"xyz.willy.Zebra", @"com.tigisoftware.Filza"
        ];
        
        // Level 3: Extreme Lockdown (System Daemons & Exploit Vectors)
        NSArray *tier3 = @[
            @"com.apple.imagent", @"imagent", 
            @"mediaserverd", 
            @"networkd"
        ];
        
        // Check Bundle ID
        if (bundleID) {
            if ([tier1 containsObject:bundleID]) isTargetRestricted = YES;
            if (autoProtectLevel >= 2 && [tier2 containsObject:bundleID]) isTargetRestricted = YES;
            if (autoProtectLevel >= 3 && [tier3 containsObject:bundleID]) isTargetRestricted = YES;
        }
        
        // Check Process Name (Critical for Level 3 Daemons)
        if (processName && !isTargetRestricted) {
            if ([tier1 containsObject:processName]) isTargetRestricted = YES;
            if (autoProtectLevel >= 2 && [tier2 containsObject:processName]) isTargetRestricted = YES;
            if (autoProtectLevel >= 3 && [tier3 containsObject:processName]) isTargetRestricted = YES;
        }
    }
    
    // 2. Evaluate Manual / Custom Array 
    // (This runs if AutoProtect is OFF, OR to catch manually added Custom Daemons when AutoProtect is ON)
    if (!isTargetRestricted) {
        if (bundleID && [restrictedApps containsObject:bundleID]) {
            isTargetRestricted = YES;
        } else if (processName && [restrictedApps containsObject:processName]) {
            isTargetRestricted = YES;
        }
    }
    
    currentProcessRestricted = (tweakEnabled && isTargetRestricted);
}

static BOOL isAppRestricted() {
    return currentProcessRestricted;
}

%ctor {
    loadPrefs();
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, (CFNotificationCallback)loadPrefs, CFSTR("com.eolnmsuk.antidarkswordprefs/saved"), NULL, CFNotificationSuspensionBehaviorCoalesce);
}

// =========================================================
// WEBKIT EXPLOIT MITIGATIONS
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
    return %orig(frame, configuration);
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
