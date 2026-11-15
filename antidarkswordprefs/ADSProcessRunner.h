#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, ADSCommandOutcome) {
    ADSCommandExited, ADSCommandSignaled, ADSCommandTimedOut,
    ADSCommandSpawnFailed, ADSCommandWaitFailed, ADSCommandValidationFailed,
    ADSCommandAlreadySatisfied
};

@interface ADSCommandResult : NSObject
@property (nonatomic, readonly) ADSCommandOutcome outcome;
@property (nonatomic, readonly) int errorCode;
@property (nonatomic, readonly) int exitCode;
@property (nonatomic, readonly) int terminationSignal;
@property (nonatomic, copy, readonly) NSString *operation;
@property (nonatomic, copy, readonly) NSString *executable;
@property (nonatomic, copy, readonly) NSArray<NSString *> *arguments;
@property (nonatomic, copy, readonly) NSString *standardError;
@property (nonatomic, copy, readonly) NSString *standardOutput;
@property (nonatomic, readonly) BOOL outputTruncated;
@property (nonatomic, readonly, getter=isSuccessful) BOOL successful;
@property (nonatomic, copy, readonly) NSString *diagnosticDescription;
@end

typedef void (^ADSCommandCompletion)(ADSCommandResult *result);

// Existing package launchctl/killall controls use an absolute executable,
// basename argv[0] and NULL envp, matching the 4.9.3 call convention. Copies
// strings immediately, drains bounded diagnostics on a serial worker, then
// completes once on the main queue independently of the controller's lifetime.
void ADSRunCommand(NSString *executable, NSArray<NSString *> *arguments,
                   NSString *operation, ADSCommandCompletion completion);

// Uses load/unload in the compile-selected namespace. Only a successful label
// query establishes registration in the caller's bootstrap context, not process
// health or completed restart work. Unverified nonzero unloads fail.
void ADSSetDecoyActive(BOOL active, ADSCommandCompletion completion);
