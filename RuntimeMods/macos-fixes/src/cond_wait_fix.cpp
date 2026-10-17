#include "cond_wait_fix.hpp"

#include <pthread.h>
#include <time.h>

#include "log.hpp"

namespace macos_fixes::cond_wait_fix {
namespace {

constexpr time_t kMonotonicDeadlineCeiling = 1'000'000'000;
constexpr long long kNanosecondsPerSecond = 1'000'000'000;
constexpr long long kProbeWait = 20'000'000;
constexpr long long kProbeEarlyLimit = 10'000'000;

using TimedWaitFunction = int (*)(pthread_cond_t *cond, pthread_mutex_t *mutex, const timespec *deadline);

TimedWaitFunction originalTimedWait;

long long nanoseconds(const timespec &time) {
    return static_cast<long long>(time.tv_sec) * kNanosecondsPerSecond + time.tv_nsec;
}

timespec fromNanoseconds(long long value) {
    return timespec{static_cast<time_t>(value / kNanosecondsPerSecond), static_cast<long>(value % kNanosecondsPerSecond)};
}

long long now(clockid_t clock) {
    timespec time{};
    clock_gettime(clock, &time);
    return nanoseconds(time);
}

bool monotonicWaitReturnsEarly() {
    pthread_condattr_t attributes;
    pthread_condattr_init(&attributes);
    pthread_condattr_setclock(&attributes, CLOCK_MONOTONIC);
    pthread_cond_t cond;
    pthread_cond_init(&cond, &attributes);
    pthread_condattr_destroy(&attributes);
    pthread_mutex_t mutex = PTHREAD_MUTEX_INITIALIZER;
    pthread_mutex_lock(&mutex);
    long long start = now(CLOCK_MONOTONIC);
    timespec deadline = fromNanoseconds(start + kProbeWait);
    int result = 0;
    while (result == 0) {
        result = pthread_cond_timedwait(&cond, &mutex, &deadline);
    }
    long long waited = now(CLOCK_MONOTONIC) - start;
    pthread_mutex_unlock(&mutex);
    pthread_cond_destroy(&cond);
    log::info("monotonic 20 ms timed wait returned after %lld us", waited / 1000);
    return waited < kProbeEarlyLimit;
}

int fixedTimedWait(pthread_cond_t *cond, pthread_mutex_t *mutex, const timespec *deadline) {
    if (deadline == nullptr || deadline->tv_sec >= kMonotonicDeadlineCeiling) {
        return originalTimedWait(cond, mutex, deadline);
    }
    long long remaining = nanoseconds(*deadline) - now(CLOCK_MONOTONIC);
    timespec converted = fromNanoseconds(now(CLOCK_REALTIME) + (remaining > 0 ? remaining : 0));
    return originalTimedWait(cond, mutex, &converted);
}

}

bool install(const ImportTable &game) {
    if (!monotonicWaitReturnsEarly()) {
        log::info("libc shim honors monotonic condition variables, no workaround needed");
        return false;
    }
    originalTimedWait = reinterpret_cast<TimedWaitFunction>(game.resolved("pthread_cond_timedwait"));
    if (originalTimedWait == nullptr || !game.rebind("pthread_cond_timedwait", reinterpret_cast<void *>(&fixedTimedWait))) {
        log::error("pthread_cond_timedwait import not found, monotonic wait workaround not installed");
        return false;
    }
    log::info("monotonic wait workaround installed");
    return true;
}

}
