cmake_minimum_required(VERSION 3.16)
project(pixel-lettering C)

# Default single-configuration generators to an optimized build, while still
# allowing callers to override it with -DCMAKE_BUILD_TYPE=<type>.
if(NOT CMAKE_CONFIGURATION_TYPES AND NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE Release CACHE STRING "Choose the type of build." FORCE)
    set_property(CACHE CMAKE_BUILD_TYPE PROPERTY STRINGS Debug Release RelWithDebInfo MinSizeRel)
endif()

set(CMAKE_C_STANDARD 99)
set(CMAKE_C_STANDARD_REQUIRED ON)
if(CMAKE_C_COMPILER_ID MATCHES "GNU|Clang")
    add_compile_options(-Wall -Wextra)
endif()

if(WIN32)
    # pkg-config's .pc files generally aren't available on Windows, so we build
    # against the private Lua tree in windows-libs/ instead. It is a vcpkg
    # lua:x64-windows-release install and is gitignored, so a fresh clone has to
    # recreate it -- see the README.
    #
    # That triplet ships release binaries only. Prefer a Release build; with a
    # multi-config generator that means `cmake --build build --config Release`.
    set(WINDOWS_LIBS_DIR "${CMAKE_CURRENT_SOURCE_DIR}/windows-libs")
    set(LUA_INCLUDE_DIRS "${WINDOWS_LIBS_DIR}/include")
    set(LUA_LIBRARY "${WINDOWS_LIBS_DIR}/lib/lua.lib")
    set(LUA_RUNTIME_DLL "${WINDOWS_LIBS_DIR}/bin/lua.dll")

    if(NOT EXISTS "${LUA_INCLUDE_DIRS}/lua.h" OR NOT EXISTS "${LUA_LIBRARY}")
        message(FATAL_ERROR
            "No Lua found in ${WINDOWS_LIBS_DIR}. Populate it with a vcpkg "
            "lua:x64-windows-release install (see README.md).")
    endif()

    # x64-windows-release is 64-bit; a 32-bit generator would otherwise fail at
    # link time with a less obvious message.
    if(NOT CMAKE_SIZEOF_VOID_P EQUAL 8)
        message(FATAL_ERROR
            "windows-libs holds 64-bit Lua; configure a 64-bit generator "
            "(e.g. -A x64).")
    endif()
else()
    find_package(PkgConfig REQUIRED)
    pkg_check_modules(LUA REQUIRED lua5.3)
endif()

# stb is vendored as headers compiled straight into the module, so there is no
# image library to find here and none to resolve at runtime.
add_library(wrap_stb_image MODULE src/wrap_stb_image.c)

target_include_directories(wrap_stb_image PRIVATE ${LUA_INCLUDE_DIRS})

# SYSTEM so that -Wall -Wextra stays pointed at our own source: stb trips
# -Wunused-function and -Wmaybe-uninitialized, and there is nothing to fix in a
# vendored header.
target_include_directories(wrap_stb_image SYSTEM PRIVATE lib)

if(WIN32)
    # Windows DLL linkers require the Lua symbols to be resolved at link time.
    target_link_libraries(wrap_stb_image PRIVATE "${LUA_LIBRARY}")
    target_compile_definitions(wrap_stb_image PRIVATE WRAP_STB_IMAGE_BUILD_DLL)
endif()

# require() wants wrap_stb_image.so on POSIX and wrap_stb_image.dll on Windows
set_target_properties(wrap_stb_image PROPERTIES
    PREFIX ""
    SUFFIX "${CMAKE_SHARED_MODULE_SUFFIX}"
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}"
    LIBRARY_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}")

if(WIN32)
    # lua.lib is an import library, so wrap_stb_image.dll pulls in lua.dll at
    # load time. Lua 5.3 loads C modules with LOAD_WITH_ALTERED_SEARCH_PATH,
    # which searches the module's own directory, so a copy alongside it
    # satisfies the import wherever the build output lands.
    add_custom_command(TARGET wrap_stb_image POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy_if_different
                "${LUA_RUNTIME_DLL}" "$<TARGET_FILE_DIR:wrap_stb_image>"
        COMMENT "Staging lua.dll next to wrap_stb_image")
endif()
