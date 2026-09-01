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
    # pkg-config's .pc files generally aren't available on Windows, so require
    # the invoker to point us at a Lua build directly.
    set(LUA_INCLUDE_DIR "" CACHE PATH "Path to the directory containing lua.h")
    set(LUA_LIBRARY "" CACHE FILEPATH "Path to the Lua import/static library (e.g. lua53.lib / liblua5.3.a)")
    if(NOT LUA_INCLUDE_DIR OR NOT LUA_LIBRARY)
        message(FATAL_ERROR "On Windows, set -DLUA_INCLUDE_DIR=<path to lua.h> and -DLUA_LIBRARY=<path to the Lua import/static library>")
    endif()
    set(LUA_INCLUDE_DIRS "${LUA_INCLUDE_DIR}")
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
