#import <WebKit/WebKit.h>
#import <JavaScriptCore/JavaScriptCore.h>

static BOOL tweakEnabled = YES;
static NSArray *restrictedApps = nil;
static NSString *customRestrictedApps = @"";

// Define preference paths for both rootless and rootful environments
#define PREFS_PATH_ROOTLESS @"/var/jb/var/mobile/Library/Preferences/com.eolnmsuk.antidarkswordprefs.plist"
#define PREFS_PATH_ROOTFUL @"/var/mobile/Library/Preferences/com.eolnmsuk.antidarkswordprefs.plist"

// Read directly from the plist file to bypass NSUserDefaults sandboxing blocks
static void loadPrefs() {
    NSDictionary *prefs = nil;
    
    if ([[NSFileManager defaultManager] fileExistsAtPath:PREFS_PATH_ROOTLESS]) {
        prefs = [NSDictionary dictionaryWithContentsOfFile:PREFS_PATH_ROOTLESS];
    } else if ([[NSFileManager defaultManager] fileExistsAtPath:PREFS_PATH_ROOTFUL]) {
        prefs = [NSDictionary dictionaryWithContentsOfFile:PREFS_PATH_ROOTFUL];
    }

    if (prefs) {
        tweakEnabled = prefs[@"enabled"] ? [prefs[@"enabled"] boolValue] : YES;
        restrictedApps = prefs[@"restrictedApps"] ?: @[];
        customRestrictedApps = prefs[@"customRestrictedApps"] ?: @"";
    } else {
        tweakEnabled = YES;
        restrictedApps = @[];
        customRestrictedApps = @"";
    }
}

static BOOL isAppWhitelisted() {
    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
    if (!bundleID) return YES; 
    
    if (restrictedApps && [restrictedApps containsObject:bundleID]) {
        return NO;
    }
    
    if (customRestrictedApps && customRestrictedApps.length > 0) {
        if ([customRestrictedApps containsString:bundleID]) {
            return NO;
        }
    }
    
    return YES;
}

%ctor {
    loadPrefs();
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, (CFNotificationCallback)loadPrefs, CFSTR("com.eolnmsuk.antidarkswordprefs/saved"), NULL, CFNotificationSuspensionBehaviorCoalesce);
}

// Intercept Initialization and Apply Strict Exploit Mitigations
%hook WKWebView
- (instancetype)initWithFrame:(CGRect)frame configuration:(WKWebViewConfiguration *)configuration {
    if (tweakEnabled && !isAppWhitelisted()) {
        
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
                // Prevent local file access escapes
                [configuration.preferences setValue:@NO forKey:@"allowFileAccessFromFileURLs"];
                [configuration.preferences setValue:@NO forKey:@"allowUniversalAccessFromFileURLs"];
                
                // Disable WebGL (graphics memory corruption vectors)
                [configuration.preferences setValue:@NO forKey:@"webGLEnabled"];
                
                // Disable WebRTC (peer-to-peer data channel exploits)
                [configuration.preferences setValue:@NO forKey:@"mediaStreamEnabled"]; 
                [configuration.preferences setValue:@NO forKey:@"peerConnectionEnabled"]; 
            } @catch (NSException *e) {
                // Silently catch in case Apple alters or removes a private key in newer iOS versions
            }
        }
    }
    return %orig(frame, configuration);
}
%end

// Intercept Late Configuration Changes for JavaScript
%hook WKWebpagePreferences
- (void)setAllowsContentJavaScript:(BOOL)allowed {
    if (tweakEnabled && !isAppWhitelisted() && allowed) {
        return %orig(NO);
    }
    %orig;
}
%end

%hook WKPreferences
- (void)setJavaScriptEnabled:(BOOL)enabled {
    if (tweakEnabled && !isAppWhitelisted() && enabled) {
        return %orig(NO);
    }
    %orig;
}
%end

// Global JavaScriptCore Kill-Switch
%hookf(JSValueRef, JSEvaluateScript, JSContextRef ctx, JSStringRef script, JSObjectRef thisObject, JSStringRef sourceURL, int startingLineNumber, JSValueRef *exception) {
    if (tweakEnabled && !isAppWhitelisted()) {
        return NULL;
    }
    return %orig(ctx, script, thisObject, sourceURL, startingLineNumber, exception);
}
