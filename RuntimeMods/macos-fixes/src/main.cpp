#include <optional>

#include "cond_wait_fix.hpp"
#include "gles_compat.hpp"
#include "import_table.hpp"
#include "log.hpp"

extern "C" __attribute__((visibility("default"))) void mod_init() {
    std::optional<macos_fixes::ImportTable> game =
        macos_fixes::ImportTable::open("libminecraftpe.so", "GameActivity_onCreate");
    if (!game) {
        macos_fixes::log::error("libminecraftpe.so not found, macOS fixes disabled");
        return;
    }
    macos_fixes::cond_wait_fix::install(*game);
    if (macos_fixes::gles_compat::install(*game)) {
        macos_fixes::log::info("ES 3.0 compatibility installed");
    }
}
