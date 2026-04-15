// AntiDarkSwordDaemon/Tweak.x
#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#include <sys/stat.h>
#include <unistd.h>
#include <substrate.h>

#import "../ADSLogging.h"

@interface IMFileTransfer : NSObject
- (BOOL)isAutoDownloadable;
- (BOOL)canAutoDownload;
@end

@interface CKAttachmentMessagePartChatItem : NSObject
- (BOOL)_needsPreviewGeneration;
@end

#define PREFS_PATH ([[NSFileManager defaultManager] fileExistsAtPath:@"/var/jb/"] ? \
    @"/var/jb/var/mobile/Library/Preferences/com.eolnmsuk.antidarkswordprefs.plist" : \
    @"/var/mobile/Library/Preferences/com.eolnmsuk.antidarkswordprefs.plist")

// Whether daemon-level protection is active (Level 3 only).
static _Atomic BOOL daemonProtectionActive = NO;
static _Atomic BOOL applyDisableIMessageDL  = NO;
static _Atomic BOOL globalDecoyEnabled      = NO;
static BOOL         isRootlessJB            = NO;

// ---------------------------------------------------------------------------
// PREFERENCE PARSING
// Only fields actually used by the daemon tweak are read. UA / per-app
// feature state is the UI tweak's domain and must not be touched here.
// ---------------------------------------------------------------------------
static void loadPrefs(void) {
    NSDictionary *prefs = nil;

    if ([[NSFileManager defaultManager] fileExistsAtPath:PREFS_PATH]) {
        prefs = [NSDictionary dictionaryWithContentsOfFile:PREFS_PATH];
    }

    if (!prefs || ![prefs isKindOfClass:[NSDictionary class]]) {
        CFArrayRef keyList = CFPreferencesCopyKeyList(
            CFSTR("com.eolnmsuk.antidarkswordprefs"),
            kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
        if (keyList) {
            CFDictionaryRef dict = CFPreferencesCopyMultiple(
                keyList,
                CFSTR("com.eolnmsuk.antidarkswordprefs"),
                kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
            if (dict) prefs = (__bridge_transfer NSDictionary *)dict;
            CFRelease(keyList);
        }
    }

    BOOL tweakEnabled    = NO;
    NSInteger level      = 1;
    BOOL globalIMDL      = NO;
    BOOL decoyPref       = NO;

    if (prefs && [prefs isKindOfClass:[NSDictionary class]]) {
        tweakEnabled = [prefs[@"enabled"] respondsToSelector:@selector(boolValue)]
            ? [prefs[@"enabled"] boolValue] : NO;
        level = [prefs[@"autoProtectLevel"] respondsToSelector:@selector(integerValue)]
            ? [prefs[@"autoProtectLevel"] integerValue] : 1;
        globalIMDL = [prefs[@"globalDisableIMessageDL"] respondsToSelector:@selector(boolValue)]
            ? [prefs[@"globalDisableIMessageDL"] boolValue] : NO;
        decoyPref = [prefs[@"corelliumDecoyEnabled"] respondsToSelector:@selector(boolValue)]
            ? [prefs[@"corelliumDecoyEnabled"] boolValue] : NO;
    }

    // Daemon protection is ONLY active at Level 3.
    BOOL level3Active = (tweakEnabled && level >= 3);

    // Per-process iMessage DL disable: respect disabledPresetRules.
    NSString *processName = [[NSProcessInfo processInfo] processName];
    BOOL imDLProcess = (
        [processName isEqualToString:@"imagent"]          ||
        [processName isEqualToString:@"IMDPersistenceAgent"] ||
        [processName isEqualToString:@"IMTransferAgent"]
    );

    BOOL ruleDisabled = NO;
    if (prefs && [prefs isKindOfClass:[NSDictionary class]]) {
        id disabledRaw = prefs[@"disabledPresetRules"];
        if ([disabledRaw isKindOfClass:[NSArray class]]) {
            NSArray *disabled = disabledRaw;
            if ([disabled containsObject:processName] ||
                ([processName isEqualToString:@"imagent"] &&
                 [disabled containsObject:@"com.apple.imagent"])) {
                ruleDisabled = YES;
            }
        }
    }

    daemonProtectionActive = level3Active && !ruleDisabled;

    // iMessage DL blocking: active if protection is on for this process,
    // OR if the global kill-switch is on (independent of level).
    applyDisableIMessageDL = (tweakEnabled && globalIMDL) ||
                             (daemonProtectionActive && imDLProcess);

    // Corellium file-path spoofing is gated on the pref only (not level),
    // identical to the UI tweak — file checks can come from any injected process.
    globalDecoyEnabled = (tweakEnabled && decoyPref);

    ADSLog(@"[PREFS] process=%@ level=%ld daemonActive=%d iMessageDL=%d decoy=%d",
           processName, (long)level,
           (int)daemonProtectionActive, (int)applyDisableIMessageDL, (int)globalDecoyEnabled);
}

static void reloadDaemonPrefsNotification(
    CFNotificationCenterRef center, void *observer, CFStringRef name,
    const void *object, CFDictionaryRef userInfo)
{
    loadPrefs();
}

// ---------------------------------------------------------------------------
// IMESSAGE 0-CLICK MITIGATIONS
// ---------------------------------------------------------------------------
%hook IMFileTransfer
- (BOOL)isAutoDownloadable {
    if (applyDisableIMessageDL) {
        ADSLog(@"[MITIGATION] Blocked isAutoDownloadable on IMFileTransfer.");
        return NO;
    }
    return %orig;
}

- (BOOL)canAutoDownload {
    if (applyDisableIMessageDL) {
        ADSLog(@"[MITIGATION] Blocked canAutoDownload on IMFileTransfer.");
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

// ---------------------------------------------------------------------------
// CORELLIUM FILE PATH SPOOFING — rootless only.
// On rootless the binary lives under the jbroot prefix; spoof the canonical
// path so exploit chains checking /usr/libexec/corelliumd find a "real"
// file and abort. On rootful the binary is at that path; guard prevents
// double-spoofing. Hooks are static to avoid symbol collision with the UI
// dylib when both are loaded into the same process by Substrate.
// ---------------------------------------------------------------------------
static int (*orig_access)(const char *path, int amode);
static int hook_access(const char *path, int amode) {
    if (globalDecoyEnabled && isRootlessJB &&
        path && strcmp(path, "/usr/libexec/corelliumd") == 0) return 0;
    return orig_access(path, amode);
}

static int (*orig_stat)(const char *path, struct stat *buf);
static int hook_stat(const char *path, struct stat *buf) {
    if (globalDecoyEnabled && isRootlessJB &&
        path && strcmp(path, "/usr/libexec/corelliumd") == 0) {
        if (buf) {
            memset(buf, 0, sizeof(struct stat));
            buf->st_mode = S_IFREG | 0755;
            buf->st_uid  = 0;
            buf->st_gid  = 0;
            buf->st_size = 34520;
        }
        return 0;
    }
    return orig_stat(path, buf);
}

static int (*orig_lstat)(const char *path, struct stat *buf);
static int hook_lstat(const char *path, struct stat *buf) {
    if (globalDecoyEnabled && isRootlessJB &&
        path && strcmp(path, "/usr/libexec/corelliumd") == 0) {
        if (buf) {
            memset(buf, 0, sizeof(struct stat));
            buf->st_mode = S_IFREG | 0755;
            buf->st_uid  = 0;
            buf->st_gid  = 0;
            buf->st_size = 34520;
        }
        return 0;
    }
    return orig_lstat(path, buf);
}

%hook NSFileManager
- (BOOL)fileExistsAtPath:(NSString *)path {
    if (globalDecoyEnabled && isRootlessJB &&
        [path isEqualToString:@"/usr/libexec/corelliumd"]) return YES;
    return %orig;
}
- (BOOL)fileExistsAtPath:(NSString *)path isDirectory:(BOOL *)isDirectory {
    if (globalDecoyEnabled && isRootlessJB &&
        [path isEqualToString:@"/usr/libexec/corelliumd"]) {
        if (isDirectory) *isDirectory = NO;
        return YES;
    }
    return %orig;
}
%end

// ---------------------------------------------------------------------------
// CONSTRUCTOR
// ---------------------------------------------------------------------------
%ctor {
    %init;

    isRootlessJB = (access("/var/jb", F_OK) == 0);

    ADSLog(@"[INIT] AntiDarkSwordDaemon loaded into: %@",
           [[NSProcessInfo processInfo] processName]);

    loadPrefs();

    ADSLog(@"[STATUS] daemonProtection=%d iMessageDL=%d decoy=%d",
           (int)daemonProtectionActive, (int)applyDisableIMessageDL,
           (int)globalDecoyEnabled);

    CFNotificationCenterAddObserver(
        CFNotificationCenterGetDarwinNotifyCenter(), NULL,
        (CFNotificationCallback)reloadDaemonPrefsNotification,
        CFSTR("com.eolnmsuk.antidarkswordprefs/saved"),
        NULL, CFNotificationSuspensionBehaviorCoalesce);

    MSHookFunction((void *)access, (void *)hook_access, (void **)&orig_access);
    MSHookFunction((void *)stat,   (void *)hook_stat,   (void **)&orig_stat);
    MSHookFunction((void *)lstat,  (void *)hook_lstat,  (void **)&orig_lstat);
}
