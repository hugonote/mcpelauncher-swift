#include <stdlib.h>
#include <string.h>

static const char *const kAnglePlatformVariable = "ANGLE_DEFAULT_PLATFORM";
static const char *const kRequestedPlatformVariable = "MCPELAUNCHER_ANGLE_PLATFORM";

static int override_setenv(const char *name, const char *value, int overwrite) {
    const char *requested = getenv(kRequestedPlatformVariable);
    if (name != NULL && requested != NULL && requested[0] != '\0' && strcmp(name, kAnglePlatformVariable) == 0) {
        return setenv(name, requested, 1);
    }
    return setenv(name, value, overwrite);
}

__attribute__((used, section("__DATA,__interpose"))) static const struct {
    const void *replacement;
    const void *original;
} interposers[] = {
    {(const void *)override_setenv, (const void *)setenv},
};
