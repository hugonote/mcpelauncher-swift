#pragma once

#include <cstdint>
#include <optional>

namespace macos_fixes {

/**
 * The PLT import table of a library loaded by the mcpelauncher linker, whose
 * imports are bound at load time.
 */
class ImportTable {
public:
    /**
     * @param library File name, for example "libminecraftpe.so".
     * @param exportedSymbol Any symbol the library exports, used to find its base.
     * @return The table, or nothing when the library is not loaded.
     */
    static std::optional<ImportTable> open(const char *library, const char *exportedSymbol);

    /**
     * @param symbol Imported function name.
     * @return The address the import is bound to, or nullptr.
     */
    void *resolved(const char *symbol) const;

    /**
     * Rebinds an import. The page holding the slot is left writable, since it
     * can share a 16 KiB host page with writable data.
     *
     * @param symbol Imported function name.
     * @param replacement New target.
     * @return true when the import exists and now points to the replacement.
     */
    bool rebind(const char *symbol, void *replacement) const;

private:
    void **slot(const char *symbol) const;

    uintptr_t base_ = 0;
    const void *relocations_ = nullptr;
    size_t relocationCount_ = 0;
    const void *symbols_ = nullptr;
    const char *strings_ = nullptr;
};

}
