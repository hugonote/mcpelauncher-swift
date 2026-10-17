#include "gles_compat.hpp"

#include <array>
#include <atomic>
#include <string>
#include <string_view>
#include <vector>

#include "log.hpp"

namespace macos_fixes::gles_compat {
namespace {

constexpr unsigned kVersion = 0x1F02;
constexpr unsigned kExtensions = 0x1F03;
constexpr unsigned kShadingLanguageVersion = 0x8B8C;
constexpr unsigned kMajorVersion = 0x821B;
constexpr unsigned kMinorVersion = 0x821C;
constexpr unsigned kExtensionCount = 0x821D;
constexpr unsigned kCompileStatus = 0x8B81;
constexpr unsigned kLinkStatus = 0x8B82;
constexpr unsigned kQueryResultAvailable = 0x8867;
constexpr int kPendingQueryPollLimit = 64;
constexpr int kReportedFailureLimit = 32;
constexpr int kInfoLogCapacity = 1024;
constexpr std::string_view kEs30Context = "OpenGL ES 3.0";
constexpr std::string_view kEssl310 = "#version 310 es";
constexpr std::string_view kEssl300 = "#version 300 es";
constexpr std::string_view kHiddenExtension = "GL_EXT_disjoint_timer_query";
constexpr const char *kAnnouncedShadingLanguage = "OpenGL ES GLSL ES 3.10";

using GetStringFunction = const unsigned char *(*)(unsigned name);
using GetIndexedStringFunction = const unsigned char *(*)(unsigned name, unsigned index);
using GetIntegerFunction = void (*)(unsigned name, int *value);
using ShaderSourceFunction = void (*)(unsigned shader, int count, const char *const *sources, const int *lengths);
using ObjectFunction = void (*)(unsigned object);
using GetObjectFunction = void (*)(unsigned object, unsigned name, int *value);
using GetInfoLogFunction = void (*)(unsigned object, int capacity, int *length, char *log);
using GetQueryObjectFunction = void (*)(unsigned query, unsigned name, int *value);
using FlushFunction = void (*)();
using GetProcAddressFunction = void *(*)(const char *name);

enum class ContextMode { Unknown, Emulated31, Native };

GetStringFunction realGetString;
GetObjectFunction getShader;
GetObjectFunction getProgram;
GetInfoLogFunction getShaderInfoLog;
GetInfoLogFunction getProgramInfoLog;
FlushFunction flush;
GetProcAddressFunction originalGetProcAddress;
GetStringFunction originalGetString;
GetIndexedStringFunction originalGetIndexedString;
GetIntegerFunction originalGetInteger;
ShaderSourceFunction originalShaderSource;
ObjectFunction originalCompileShader;
ObjectFunction originalLinkProgram;
GetQueryObjectFunction originalGetQueryObjectEXT;
GetQueryObjectFunction originalGetQueryObjectNV;

std::atomic<ContextMode> contextMode{ContextMode::Unknown};
std::string announcedVersion;
std::vector<std::string> announcedExtensionList;
std::string announcedExtensions;
std::atomic<int> reportedFailures;
std::atomic<int> forcedQueries;
unsigned pendingQuery;
int pendingQueryPolls;

void announceExtensions() {
    const auto *extensions = reinterpret_cast<const char *>(realGetString(kExtensions));
    std::string_view remaining = extensions != nullptr ? extensions : "";
    while (!remaining.empty()) {
        size_t end = remaining.find(' ');
        std::string_view extension = remaining.substr(0, end);
        if (!extension.empty() && extension != kHiddenExtension) {
            announcedExtensionList.emplace_back(extension);
            announcedExtensions.append(announcedExtensions.empty() ? "" : " ").append(extension);
        }
        remaining.remove_prefix(end == std::string_view::npos ? remaining.size() : end + 1);
    }
}

bool emulating31() {
    ContextMode mode = contextMode.load();
    if (mode == ContextMode::Unknown) {
        const auto *version = reinterpret_cast<const char *>(realGetString(kVersion));
        std::string_view real = version != nullptr ? version : "";
        bool es30 = real.starts_with(kEs30Context);
        if (es30) {
            announcedVersion = "OpenGL ES 3.1";
            announcedVersion.append(real.substr(kEs30Context.size()));
            announceExtensions();
        }
        mode = es30 ? ContextMode::Emulated31 : ContextMode::Native;
        contextMode.store(mode);
        log::info("context \"%.*s\", %s", static_cast<int>(real.size()), real.data(),
                  es30 ? "announcing ES 3.1 and lowering ESSL 310 shaders" : "unchanged");
    }
    return mode == ContextMode::Emulated31;
}

const unsigned char *hookedGetString(unsigned name) {
    if (emulating31()) {
        if (name == kVersion) {
            return reinterpret_cast<const unsigned char *>(announcedVersion.c_str());
        }
        if (name == kShadingLanguageVersion) {
            return reinterpret_cast<const unsigned char *>(kAnnouncedShadingLanguage);
        }
        if (name == kExtensions) {
            return reinterpret_cast<const unsigned char *>(announcedExtensions.c_str());
        }
    }
    return originalGetString(name);
}

const unsigned char *hookedGetIndexedString(unsigned name, unsigned index) {
    if (name != kExtensions || !emulating31()) {
        return originalGetIndexedString(name, index);
    }
    if (index >= announcedExtensionList.size()) {
        return nullptr;
    }
    return reinterpret_cast<const unsigned char *>(announcedExtensionList[index].c_str());
}

void hookedGetInteger(unsigned name, int *value) {
    originalGetInteger(name, value);
    if (value == nullptr || !emulating31()) {
        return;
    }
    if (name == kMajorVersion) {
        *value = 3;
    } else if (name == kMinorVersion) {
        *value = 1;
    } else if (name == kExtensionCount) {
        *value = static_cast<int>(announcedExtensionList.size());
    }
}

std::string joinSources(int count, const char *const *sources, const int *lengths) {
    std::string source;
    for (int index = 0; index < count; index++) {
        if (lengths != nullptr && lengths[index] >= 0) {
            source.append(sources[index], static_cast<size_t>(lengths[index]));
        } else {
            source.append(sources[index]);
        }
    }
    return source;
}

void hookedShaderSource(unsigned shader, int count, const char *const *sources, const int *lengths) {
    if (count <= 0 || sources == nullptr || !emulating31()) {
        originalShaderSource(shader, count, sources, lengths);
        return;
    }
    std::string source = joinSources(count, sources, lengths);
    size_t position = source.find(kEssl310);
    if (position == std::string::npos || source.find_first_not_of(" \t\r\n") != position) {
        originalShaderSource(shader, count, sources, lengths);
        return;
    }
    source.replace(position, kEssl310.size(), kEssl300);
    const char *text = source.c_str();
    originalShaderSource(shader, 1, &text, nullptr);
}

void reportFailure(const char *kind, unsigned object, GetInfoLogFunction getInfoLog) {
    int index = reportedFailures.fetch_add(1);
    if (index >= kReportedFailureLimit) {
        return;
    }
    std::array<char, kInfoLogCapacity> infoLog{};
    int length = 0;
    getInfoLog(object, static_cast<int>(infoLog.size()), &length, infoLog.data());
    log::error("%s %u failed (%d/%d): %.*s", kind, object, index + 1, kReportedFailureLimit, length, infoLog.data());
}

void hookedCompileShader(unsigned shader) {
    originalCompileShader(shader);
    if (!emulating31()) {
        return;
    }
    int status = 1;
    getShader(shader, kCompileStatus, &status);
    if (status == 0) {
        reportFailure("shader", shader, getShaderInfoLog);
    }
}

void hookedLinkProgram(unsigned program) {
    originalLinkProgram(program);
    if (!emulating31()) {
        return;
    }
    int status = 1;
    getProgram(program, kLinkStatus, &status);
    if (status == 0) {
        reportFailure("program", program, getProgramInfoLog);
    }
}

void settleQueryAvailability(unsigned query, int *value) {
    if (*value != 0) {
        pendingQuery = 0;
        return;
    }
    if (query != pendingQuery) {
        pendingQuery = query;
        pendingQueryPolls = 0;
        flush();
        return;
    }
    if (++pendingQueryPolls < kPendingQueryPollLimit) {
        return;
    }
    *value = 1;
    pendingQuery = 0;
    if (forcedQueries.fetch_add(1) == 0) {
        log::info("query %u never became available, reported as available", query);
    }
}

void getQueryObject(GetQueryObjectFunction original, unsigned query, unsigned name, int *value) {
    original(query, name, value);
    if (name == kQueryResultAvailable && value != nullptr && emulating31()) {
        settleQueryAvailability(query, value);
    }
}

void hookedGetQueryObjectEXT(unsigned query, unsigned name, int *value) {
    getQueryObject(originalGetQueryObjectEXT, query, name, value);
}

void hookedGetQueryObjectNV(unsigned query, unsigned name, int *value) {
    getQueryObject(originalGetQueryObjectNV, query, name, value);
}

template <typename Function>
void *intercept(void *function, Function replacement, Function &original) {
    original = reinterpret_cast<Function>(function);
    return reinterpret_cast<void *>(replacement);
}

void *interceptor(std::string_view name, void *function) {
    if (name == "glGetString") {
        return intercept(function, &hookedGetString, originalGetString);
    }
    if (name == "glGetStringi") {
        return intercept(function, &hookedGetIndexedString, originalGetIndexedString);
    }
    if (name == "glGetIntegerv") {
        return intercept(function, &hookedGetInteger, originalGetInteger);
    }
    if (name == "glShaderSource") {
        return intercept(function, &hookedShaderSource, originalShaderSource);
    }
    if (name == "glCompileShader") {
        return intercept(function, &hookedCompileShader, originalCompileShader);
    }
    if (name == "glLinkProgram") {
        return intercept(function, &hookedLinkProgram, originalLinkProgram);
    }
    if (name == "glGetQueryObjectivEXT") {
        return intercept(function, &hookedGetQueryObjectEXT, originalGetQueryObjectEXT);
    }
    if (name == "glGetQueryObjectivNV") {
        return intercept(function, &hookedGetQueryObjectNV, originalGetQueryObjectNV);
    }
    return function;
}

void *hookedGetProcAddress(const char *name) {
    void *function = originalGetProcAddress(name);
    return function != nullptr && name != nullptr ? interceptor(name, function) : function;
}

template <typename Function>
bool resolve(const ImportTable &game, const char *symbol, Function &function) {
    function = reinterpret_cast<Function>(game.resolved(symbol));
    return function != nullptr;
}

void interceptImport(const ImportTable &game, const char *symbol) {
    void *function = game.resolved(symbol);
    if (function == nullptr) {
        return;
    }
    void *replacement = interceptor(symbol, function);
    if (replacement != function && !game.rebind(symbol, replacement)) {
        log::error("import %s not rebound", symbol);
    }
}

}

bool install(const ImportTable &game) {
    bool resolved = resolve(game, "glGetString", realGetString) && resolve(game, "glGetShaderiv", getShader)
        && resolve(game, "glGetProgramiv", getProgram) && resolve(game, "glGetShaderInfoLog", getShaderInfoLog)
        && resolve(game, "glGetProgramInfoLog", getProgramInfoLog) && resolve(game, "glFlush", flush)
        && resolve(game, "eglGetProcAddress", originalGetProcAddress);
    if (!resolved) {
        log::error("GL imports unavailable, ES 3.0 compatibility not installed");
        return false;
    }
    for (const char *symbol : {"glGetString", "glGetStringi", "glGetIntegerv", "glShaderSource", "glCompileShader",
                               "glLinkProgram"}) {
        interceptImport(game, symbol);
    }
    return game.rebind("eglGetProcAddress", reinterpret_cast<void *>(&hookedGetProcAddress));
}

}
