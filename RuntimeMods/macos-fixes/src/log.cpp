#include "log.hpp"

#include <android/log.h>

#include <cstdarg>

namespace macos_fixes::log {
namespace {

constexpr const char *kTag = "macos-fixes";

}

void info(const char *format, ...) {
    va_list arguments;
    va_start(arguments, format);
    __android_log_vprint(ANDROID_LOG_INFO, kTag, format, arguments);
    va_end(arguments);
}

void error(const char *format, ...) {
    va_list arguments;
    va_start(arguments, format);
    __android_log_vprint(ANDROID_LOG_ERROR, kTag, format, arguments);
    va_end(arguments);
}

}
