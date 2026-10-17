#include "import_table.hpp"

#include <dlfcn.h>
#include <elf.h>
#include <link.h>
#include <sys/mman.h>
#include <unistd.h>

#include <cstring>

namespace macos_fixes {

std::optional<ImportTable> ImportTable::open(const char *library, const char *exportedSymbol) {
    void *handle = dlopen(library, RTLD_NOW);
    void *anchor = handle != nullptr ? dlsym(handle, exportedSymbol) : nullptr;
    Dl_info info{};
    if (anchor == nullptr || dladdr(anchor, &info) == 0) {
        return std::nullopt;
    }
    ImportTable table;
    table.base_ = reinterpret_cast<uintptr_t>(info.dli_fbase);
    const auto *header = reinterpret_cast<const ElfW(Ehdr) *>(table.base_);
    if (memcmp(header->e_ident, ELFMAG, SELFMAG) != 0) {
        return std::nullopt;
    }
    const auto *programHeaders = reinterpret_cast<const ElfW(Phdr) *>(table.base_ + header->e_phoff);
    const ElfW(Dyn) *dynamic = nullptr;
    for (size_t index = 0; index < header->e_phnum; index++) {
        if (programHeaders[index].p_type == PT_DYNAMIC) {
            dynamic = reinterpret_cast<const ElfW(Dyn) *>(table.base_ + programHeaders[index].p_vaddr);
        }
    }
    for (const ElfW(Dyn) *entry = dynamic; entry != nullptr && entry->d_tag != DT_NULL; entry++) {
        uintptr_t address = table.base_ + entry->d_un.d_ptr;
        if (entry->d_tag == DT_JMPREL) {
            table.relocations_ = reinterpret_cast<const void *>(address);
        } else if (entry->d_tag == DT_PLTRELSZ) {
            table.relocationCount_ = entry->d_un.d_val / sizeof(ElfW(Rela));
        } else if (entry->d_tag == DT_SYMTAB) {
            table.symbols_ = reinterpret_cast<const void *>(address);
        } else if (entry->d_tag == DT_STRTAB) {
            table.strings_ = reinterpret_cast<const char *>(address);
        }
    }
    if (table.relocations_ == nullptr || table.symbols_ == nullptr || table.strings_ == nullptr) {
        return std::nullopt;
    }
    return table;
}

void **ImportTable::slot(const char *symbol) const {
    const auto *relocations = static_cast<const ElfW(Rela) *>(relocations_);
    const auto *symbols = static_cast<const ElfW(Sym) *>(symbols_);
    for (size_t index = 0; index < relocationCount_; index++) {
        const char *name = strings_ + symbols[ELF64_R_SYM(relocations[index].r_info)].st_name;
        if (strcmp(name, symbol) == 0) {
            return reinterpret_cast<void **>(base_ + relocations[index].r_offset);
        }
    }
    return nullptr;
}

void *ImportTable::resolved(const char *symbol) const {
    void **entry = slot(symbol);
    return entry != nullptr ? *entry : nullptr;
}

bool ImportTable::rebind(const char *symbol, void *replacement) const {
    void **entry = slot(symbol);
    if (entry == nullptr) {
        return false;
    }
    auto pageSize = static_cast<uintptr_t>(sysconf(_SC_PAGESIZE));
    uintptr_t page = reinterpret_cast<uintptr_t>(entry) & ~(pageSize - 1);
    if (mprotect(reinterpret_cast<void *>(page), pageSize, PROT_READ | PROT_WRITE) != 0) {
        return false;
    }
    __atomic_store_n(entry, replacement, __ATOMIC_RELEASE);
    return true;
}

}
