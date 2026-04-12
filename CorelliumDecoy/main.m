#include <stdio.h>
#include <unistd.h>
#include <stdlib.h>
#include <stdbool.h>
#include <time.h>
#include <CoreFoundation/CoreFoundation.h>
#include <Foundation/Foundation.h>
#include <signal.h>

void logger(char* str) {
    const char *logPath = access("/var/jb", F_OK) == 0 ? "/var/jb/tmp/corelliumd.log" : "/tmp/corelliumd.log";
    int fd = open(logPath, O_RDWR | O_CREAT | O_APPEND, 0755);
    time_t now = time(NULL);
    struct tm *localtime_t = localtime(&now);
    dprintf(fd, "[%02d:%02d:%02d] %s\n", 
            localtime_t->tm_hour, localtime_t->tm_min, localtime_t->tm_sec, str);
    close(fd);
}

void term(int signum) {
    logger("Protection disabled, the device is now vulnerable");
    int pid = getpid();
    kill(pid, SIGKILL);
}

int main(int argc, char *argv[], char *envp[]) {
    struct sigaction sig;
    sig.sa_handler = term;
    sigemptyset(&sig.sa_mask);
    sig.sa_flags = 0;
    if (sigaction(SIGTERM, &sig, NULL) < 0) {
        logger("[-] Error setting up SIGTERM handler");
    }
    logger("Protection initialized -> hanging");
    CFRunLoopRun();
}
