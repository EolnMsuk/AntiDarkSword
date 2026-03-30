#import <Foundation/Foundation.h>
#import <WebKit/WebKit.h>
#import <JavaScriptCore/JavaScriptCore.h>

// Forward declarations to avoid compiler warnings
@interface IMFileTransfer : NSObject
- (BOOL)isAutoDownloadable;
- (BOOL)canAutoDownload;
@end

@interface CKAttachmentMessagePartChatItem : NSObject
- (BOOL)_needsPreviewGeneration;
@end

#define PREFS_PATH @"/var/jb/var/mobile/Library/Preferences/com.eolnmsuk.antidarkswordprefs.plist"
#define ROOTFUL_PREFS_PATH @"/var/mobile/Library/Preferences/com.eolnmsuk.antidarkswordprefs.plist"

// Use an atomic boolean to ensure blazing fast, thread-safe O(1) reads for global JS hooks
static _Atomic BOOL currentProcessRestricted = NO;

static void loadPrefs() {
    NSDictionary *prefs = nil;
    if ([[NSFileManager defaultManager] fileExistsAtPath:PREFS_PATH]) {
        prefs = [NSDictionary dictionaryWithContentsOfFile:PREFS_PATH];
    } else if ([[NSFileManager defaultManager] fileExistsAtPath:ROOTFUL_PREFS_PATH]) {
        prefs = [NSDictionary dictionaryWithContentsOfFile:ROOTFUL_PREFS_PATH];
    }

    BOOL tweakEnabled = NO;
    NSArray *restrictedApps = @[];
    
    if (prefs) {
        // Default to NO (Safe/Allowed)
        tweakEnabled = prefs[@"enabled"] ? [prefs[@"enabled"] boolValue] : NO;
        restrictedApps = prefs[@"restrictedApps"] ?: @[];
    }
    
    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
    NSString *processName = [[NSProcessInfo processInfo] processName];
    BOOL isTargetRestricted = NO;
    
    // Check both Bundle ID and Process Name (crucial for daemons without bundles)
    if (bundleID && [restrictedApps containsObject:bundleID]) {
        isTargetRestricted = YES;
    } else if (processName && [restrictedApps containsObject:processName]) {
        isTargetRestricted = YES;
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
        
        // 1. Block JavaScript Execution
        if ([configuration respondsToSelector:@selector(defaultWebpagePreferences)]) {
            configuration.defaultWebpagePreferences.allowsContentJavaScript = NO;
        }
        if ([configuration.preferences respondsToSelector:@selector(setJavaScriptEnabled:)]) {
            configuration.preferences.javaScriptEnabled = NO;
        }
        if ([configuration.preferences respondsToSelector:@selector(setJavaScriptCanOpenWindowsAutomatically:)]) {
            configuration.preferences.javaScriptCanOpenWindowsAutomatically = NO;
        }

        // 2. Block Media Parser Exploits (e.g., ImageIO/Video Decoder Zero-Clicks)
        if ([configuration respondsToSelector:@selector(setAllowsInlineMediaPlayback:)]) {
            configuration.allowsInlineMediaPlayback = NO;
        }
        if ([configuration respondsToSelector:@selector(setMediaTypesRequiringUserActionForPlayback:)]) {
            configuration.mediaTypesRequiringUserActionForPlayback = WKAudiovisualMediaTypeAll;
        }
        if ([configuration respondsToSelector:@selector(setAllowsPictureInPictureMediaPlayback:)]) {
            configuration.allowsPictureInPictureMediaPlayback = NO;
        }

        // 3. Block WebGL, WebRTC, and File Sandbox Escapes via Private APIs
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
