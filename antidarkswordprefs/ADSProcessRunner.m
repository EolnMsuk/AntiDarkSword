#import "ADSProcessRunner.h"
#import "../ADSPaths.h"
#include <spawn.h>
#include <sys/wait.h>
#include <sys/stat.h>
#include <signal.h>
#include <errno.h>
#include <fcntl.h>
#include <time.h>
#include <unistd.h>
#include <stdlib.h>
#include <string.h>

@interface ADSCommandResult ()
@property (nonatomic) ADSCommandOutcome outcome;
@property (nonatomic) int errorCode;
@property (nonatomic) int exitCode;
@property (nonatomic) int terminationSignal;
@property (nonatomic, copy) NSString *operation;
@property (nonatomic, copy) NSString *executable;
@property (nonatomic, copy) NSString *argumentZero;
@property (nonatomic, copy) NSArray<NSString *> *arguments;
@property (nonatomic, copy) NSString *standardError;
@property (nonatomic, copy) NSString *standardOutput;
@property (nonatomic) BOOL outputTruncated;
@property (nonatomic, copy) NSString *context;
@end

@implementation ADSCommandResult
- (BOOL)isSuccessful {
    return self.outcome == ADSCommandAlreadySatisfied ||
        (self.outcome == ADSCommandExited && self.exitCode == 0);
}
- (NSString *)diagnosticDescription {
    NSString *reason;
    switch (self.outcome) {
        case ADSCommandExited: reason = [NSString stringWithFormat:@"Exit status %d.", self.exitCode]; break;
        case ADSCommandSignaled: reason = [NSString stringWithFormat:@"Child terminated by signal %d.", self.terminationSignal]; break;
        case ADSCommandTimedOut: reason = @"Command timed out; termination was requested."; break;
        case ADSCommandAlreadySatisfied: reason = @"Job registered in the caller's bootstrap context (successful launchctl label query)."; break;
        default: {
            NSString *stage = self.outcome == ADSCommandSpawnFailed ? @"Spawn" :
                (self.outcome == ADSCommandWaitFailed ? @"Wait" : @"Validation/setup");
            reason = [NSString stringWithFormat:@"%@ failed: %s (%d).", stage, strerror(self.errorCode), self.errorCode];
            break;
        }
    }
    return [NSString stringWithFormat:@"%@\n%@\n%@\nstderr: %@\nstdout: %@%@",
        self.operation, reason, self.context, self.standardError.length ? self.standardError : @"(empty)",
        self.standardOutput.length ? self.standardOutput : @"(empty)",
        self.outputTruncated ? @"\n[diagnostics truncated]" : @""];
}
@end

static NSString *ADSPackageEnvironment(void) {
#if defined(THEOS_PACKAGE_SCHEME_ROOTHIDE)
    return @"native Roothide";
#elif defined(THEOS_PACKAGE_SCHEME_ROOTLESS)
    return @"rootless";
#elif __IPHONE_OS_VERSION_MIN_REQUIRED < 150000
    return @"legacy rootful";
#else
    return @"modern rootful";
#endif
}

static ADSCommandResult *ADSNewResult(NSString *program, NSArray<NSString *> *arguments, NSString *operation) {
    ADSCommandResult *result = [ADSCommandResult new];
    result.executable = [program copy] ?: @"";
    result.argumentZero = result.executable.lastPathComponent;
    result.arguments = [[NSArray alloc] initWithArray:arguments ?: @[] copyItems:YES];
    result.operation = [operation copy] ?: @"Process control";
    result.exitCode = -1;
    result.standardError = @"";
    result.standardOutput = @"";
    result.context = [NSString stringWithFormat:@"Package target: %@; iOS %@; caller uid=%u euid=%u gid=%u egid=%u; envp: NULL\nExecutable: %@\nargv[0]: %@\nArguments: %@",
        ADSPackageEnvironment(), NSProcessInfo.processInfo.operatingSystemVersionString,
        getuid(), geteuid(), getgid(), getegid(), result.executable, result.argumentZero, result.arguments];
    return result;
}

static void ADSComplete(ADSCommandResult *result, ADSCommandCompletion completion) {
    // Successful list output can include the job's environment; do not log it.
    NSLog(@"[AntiDarkSword process] %@", result.isSuccessful ?
        [NSString stringWithFormat:@"%@ succeeded. %@", result.operation, result.context] : result.diagnosticDescription);
    dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(result); });
}

static double ADSMonotonicTime(void) {
    struct timespec time;
    clock_gettime(CLOCK_MONOTONIC, &time);
    return time.tv_sec + time.tv_nsec / 1e9;
}

static void ADSDrain(int fd, NSMutableData *data, BOOL *truncated) {
    char buffer[2048];
    // Bound each pass so a continuously writing child cannot defeat deadlines.
    for (NSUInteger drained = 0; fd >= 0 && drained < 65536;) {
        ssize_t count = read(fd, buffer, sizeof(buffer));
        if (count < 0 && errno == EINTR) continue;
        if (count <= 0) break;
        drained += (NSUInteger)count;
        NSUInteger keep = MIN((NSUInteger)count, 8192 - data.length);
        if (keep) [data appendBytes:buffer length:keep];
        if (keep < (NSUInteger)count) *truncated = YES;
    }
}

static BOOL ADSWaitUntil(pid_t pid, double deadline, int *status, int *failure,
                         int outFD, NSMutableData *outData, int errFD, NSMutableData *errData, BOOL *truncated) {
    while (ADSMonotonicTime() < deadline) {
        ADSDrain(outFD, outData, truncated);
        ADSDrain(errFD, errData, truncated);
        pid_t waited = waitpid(pid, status, WNOHANG);
        if (waited == pid) return YES;
        if (waited < 0 && errno != EINTR) { *failure = errno; return NO; }
        struct timespec pause = {0, 20 * 1000 * 1000};
        nanosleep(&pause, NULL);
    }
    return NO;
}

void ADSRunCommand(NSString *executable, NSArray<NSString *> *arguments,
                   NSString *operation, ADSCommandCompletion completion) {
    ADSCommandResult *result = ADSNewResult(executable, arguments, operation);
    static dispatch_queue_t commands;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ commands = dispatch_queue_create("com.eolnmsuk.antidarksword.process-controls", DISPATCH_QUEUE_SERIAL); });
    dispatch_async(commands, ^{
        @autoreleasepool {
            int failure = 0, status = 0;
            int outPipe[2] = {-1, -1}, errPipe[2] = {-1, -1};
            posix_spawn_file_actions_t actions;
            BOOL actionsReady = NO;
            char **argv = NULL;
            pid_t pid = 0;
            NSMutableData *outData = [NSMutableData data], *errData = [NSMutableData data];
            BOOL truncated = NO;
            result.outcome = ADSCommandValidationFailed;
            if (!result.executable.length) failure = EINVAL;
            else if (access(result.executable.fileSystemRepresentation, X_OK) != 0) failure = errno;
            for (id argument in result.arguments) {
                if (![argument isKindOfClass:NSString.class]) { failure = EINVAL; break; }
                const char *utf8 = [argument UTF8String];
                if (!utf8 || [argument lengthOfBytesUsingEncoding:NSUTF8StringEncoding] != strlen(utf8)) failure = EINVAL;
            }
            if (!failure && (pipe(outPipe) != 0 || pipe(errPipe) != 0)) failure = errno;
            if (!failure) {
                // Do not let a closed inherited stdio descriptor make an action
                // close one of the child's newly redirected streams.
                int *fds[] = {&outPipe[0], &outPipe[1], &errPipe[0], &errPipe[1]};
                for (NSUInteger i = 0; i < 4 && !failure; i++) {
                    if (*fds[i] > STDERR_FILENO) continue;
                    int duplicated = fcntl(*fds[i], F_DUPFD, STDERR_FILENO + 1);
                    if (duplicated < 0) failure = errno;
                    else { close(*fds[i]); *fds[i] = duplicated; }
                }
            }
            if (!failure) {
                int fds[] = {outPipe[0], outPipe[1], errPipe[0], errPipe[1]};
                for (NSUInteger i = 0; i < 4 && !failure; i++)
                    if (fcntl(fds[i], F_SETFD, FD_CLOEXEC) == -1) failure = errno;
                if (!failure && (fcntl(outPipe[0], F_SETFL, O_NONBLOCK) == -1 ||
                                 fcntl(errPipe[0], F_SETFL, O_NONBLOCK) == -1)) failure = errno;
            }
            if (!failure) {
                failure = posix_spawn_file_actions_init(&actions);
                actionsReady = !failure;
            }
            if (!failure) failure = posix_spawn_file_actions_adddup2(&actions, outPipe[1], STDOUT_FILENO);
            if (!failure) failure = posix_spawn_file_actions_adddup2(&actions, errPipe[1], STDERR_FILENO);
            if (!failure) failure = posix_spawn_file_actions_addclose(&actions, outPipe[0]);
            if (!failure) failure = posix_spawn_file_actions_addclose(&actions, errPipe[0]);
            if (!failure) failure = posix_spawn_file_actions_addclose(&actions, outPipe[1]);
            if (!failure) failure = posix_spawn_file_actions_addclose(&actions, errPipe[1]);
            if (!failure) {
                argv = calloc(result.arguments.count + 2, sizeof(char *));
                if (!argv) failure = ENOMEM;
            }
            if (!failure) {
                // Match the working reference's launchctl/killall call convention.
                // The absolute executable still selects the compile-time target;
                // neither argv[0] nor NULL envp establishes post-exec privileges.
                argv[0] = (char *)result.argumentZero.UTF8String;
                for (NSUInteger i = 0; i < result.arguments.count; i++) argv[i + 1] = (char *)result.arguments[i].UTF8String;
                result.outcome = ADSCommandSpawnFailed;
                failure = posix_spawn(&pid, result.executable.fileSystemRepresentation, &actions, NULL, argv, NULL);
            }
            free(argv);
            if (actionsReady) posix_spawn_file_actions_destroy(&actions);
            if (outPipe[1] >= 0) close(outPipe[1]);
            if (errPipe[1] >= 0) close(errPipe[1]);
            if (pid > 0 && !failure) {
                BOOL exited = ADSWaitUntil(pid, ADSMonotonicTime() + 5, &status, &failure,
                    outPipe[0], outData, errPipe[0], errData, &truncated);
                if (!exited && !failure) {
                    result.outcome = ADSCommandTimedOut;
                    kill(pid, SIGTERM);
                    exited = ADSWaitUntil(pid, ADSMonotonicTime() + 1, &status, &failure,
                        outPipe[0], outData, errPipe[0], errData, &truncated);
                    if (!exited && !failure) {
                        kill(pid, SIGKILL);
                        exited = ADSWaitUntil(pid, ADSMonotonicTime() + 1, &status, &failure,
                            outPipe[0], outData, errPipe[0], errData, &truncated);
                    }
                    if (!exited && !failure) {
                        // Reap a delayed kernel exit without blocking the worker.
                        dispatch_source_t reaper = dispatch_source_create(DISPATCH_SOURCE_TYPE_PROC, (uintptr_t)pid, DISPATCH_PROC_EXIT, commands);
                        if (reaper) {
                            dispatch_source_set_event_handler(reaper, ^{
                                waitpid(pid, NULL, WNOHANG);
                                dispatch_source_set_event_handler(reaper, nil);
                                dispatch_source_cancel(reaper);
                            });
                            dispatch_resume(reaper);
                        }
                    }
                    failure = ETIMEDOUT;
                } else if (failure) result.outcome = ADSCommandWaitFailed;
                else if (WIFSIGNALED(status)) {
                    result.outcome = ADSCommandSignaled;
                    result.terminationSignal = WTERMSIG(status);
                } else if (WIFEXITED(status)) {
                    result.outcome = ADSCommandExited;
                    result.exitCode = WEXITSTATUS(status);
                } else {
                    result.outcome = ADSCommandWaitFailed;
                    failure = EIO;
                }
            }
            ADSDrain(outPipe[0], outData, &truncated);
            ADSDrain(errPipe[0], errData, &truncated);
            if (outPipe[0] >= 0) close(outPipe[0]);
            if (errPipe[0] >= 0) close(errPipe[0]);
            result.errorCode = failure;
            result.outputTruncated = truncated;
            result.standardOutput = [[NSString alloc] initWithData:outData encoding:NSUTF8StringEncoding] ?:
                [[NSString alloc] initWithData:outData encoding:NSISOLatin1StringEncoding] ?: @"";
            result.standardError = [[NSString alloc] initWithData:errData encoding:NSUTF8StringEncoding] ?:
                [[NSString alloc] initWithData:errData encoding:NSISOLatin1StringEncoding] ?: @"";
            ADSComplete(result, completion);
        }
    });
}

void ADSSetDecoyActive(BOOL active, ADSCommandCompletion completion) {
    NSString *launchctl = ADSLaunchctlPath();
    NSString *plist = ADSJailbreakPath(@"/Library/LaunchDaemons/c.eolnmsuk.corelliumdecoy.plist");
    NSString *argument = ADSBootstrapArgument(plist);
    NSString *operation = active ? @"Enable Corellium Honeypot" : @"Stop Corellium Honeypot";
    NSArray *arguments = @[active ? @"load" : @"unload", argument];
    struct stat info;
    int failure = 0;
    if (stat(plist.fileSystemRepresentation, &info) != 0) failure = errno;
    else if (!S_ISREG(info.st_mode)) failure = EINVAL;
    else if (access(plist.fileSystemRepresentation, R_OK) != 0) failure = errno;
    if (!failure && active && access(ADSJailbreakPath(@"/usr/libexec/corelliumd").fileSystemRepresentation, X_OK) != 0) failure = errno;
    if (failure) {
        ADSCommandResult *result = ADSNewResult(launchctl, arguments, operation);
        result.outcome = ADSCommandValidationFailed;
        result.errorCode = failure;
        result.standardError = [NSString stringWithFormat:@"Check installed plist %@%@.", plist,
            active ? [@" and executable " stringByAppendingString:ADSJailbreakPath(@"/usr/libexec/corelliumd")] : @""];
        ADSComplete(result, completion);
        return;
    }
    if (!active) {
        ADSRunCommand(launchctl, arguments, operation, completion);
        return;
    }
    // A successful query proves registration only in this caller's bootstrap context.
    // A failed query does not establish absence or a harmless numeric exit code.
    ADSRunCommand(launchctl, @[@"list", @"c.eolnmsuk.corelliumdecoy"], @"Check Corellium Honeypot registration", ^(ADSCommandResult *query) {
        if (query.isSuccessful) {
            query.outcome = ADSCommandAlreadySatisfied;
            if (completion) completion(query);
        } else if (query.outcome == ADSCommandExited) {
            ADSRunCommand(launchctl, arguments, operation, completion);
        } else if (completion) completion(query);
    });
}
