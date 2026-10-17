cmake_minimum_required(VERSION 3.22)

project(macos_fixes LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
set(CMAKE_CXX_VISIBILITY_PRESET hidden)
set(CMAKE_VISIBILITY_INLINES_HIDDEN ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

add_compile_options(-Wall -Wextra -Werror -fno-exceptions -fno-rtti -U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=0)

add_library(macos_fixes SHARED
    src/main.cpp
    src/cond_wait_fix.cpp
    src/gles_compat.cpp
    src/import_table.cpp
    src/log.cpp
)

target_link_libraries(macos_fixes PRIVATE log)
target_link_options(macos_fixes PRIVATE -static-libstdc++ -s -Wl,--exclude-libs,ALL)
set_target_properties(macos_fixes PROPERTIES LIBRARY_OUTPUT_DIRECTORY "${PROJECT_BINARY_DIR}/arm64-v8a")
