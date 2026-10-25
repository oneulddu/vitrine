#pragma once

#import <Foundation/Foundation.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// A failed GUI check is a normal process exit, not a crash or an exception.
__attribute__((noreturn, format(__NSString__, 3, 4)))
static inline void HarnessFail(const char *file, int line, NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    const char *name = strrchr(file, '/');
    NSString *failure = [NSString stringWithFormat:@"[harness] FAIL %s:%d %@",
                        name ? name + 1 : file, line, message];
    NSLog(@"%@", failure);
    fprintf(stderr, "%s\n", failure.UTF8String);
    fflush(NULL);
    exit(1);
}

#define HARNESS_FAIL(...) HarnessFail(__FILE__, __LINE__, __VA_ARGS__)
// Unlike assert, the condition is evaluated once even when NDEBUG is defined.
#define HARNESS_CHECK(condition) do { \
    if (!(condition)) HARNESS_FAIL(@"%s", #condition); \
} while (0)
