cmake_minimum_required(VERSION 3.16)
project(pixel-lettering C)

set(CMAKE_C_STANDARD 99)
set(CMAKE_C_STANDARD_REQUIRED ON)
if(CMAKE_C_COMPILER_ID MATCHES "GNU|Clang")
    add_compile_options(-Wall -Wextra)
endif()

if(WIN32)
    # pkg-config's .pc files generally aren't available on Windows, so require
    # the invoker to point us at a Lua build directly. Its library isn't linked
    # (see the comment above target_link_libraries below), only its headers.
    set(LUA_INCLUDE_DIR "" CACHE PATH "Path to the directory containing lua.h")
    if(NOT LUA_INCLUDE_DIR)
        message(FATAL_ERROR "On Windows, set -DLUA_INCLUDE_DIR=<path to lua.h>")
    endif()
    set(LUA_INCLUDE_DIRS "${LUA_INCLUDE_DIR}")

    # Likewise for libgd: point us at its headers and import library directly.
    set(GD_INCLUDE_DIR "" CACHE PATH "Path to the directory containing gd.h")
    set(GD_LIBRARY "" CACHE FILEPATH "Path to the libgd import library (e.g. gd.lib / libgd.dll.a)")
    if(NOT GD_INCLUDE_DIR OR NOT GD_LIBRARY)
        message(FATAL_ERROR "On Windows, set -DGD_INCLUDE_DIR=<path to gd.h> and -DGD_LIBRARY=<path to the libgd import library>")
    endif()
    set(GD_INCLUDE_DIRS "${GD_INCLUDE_DIR}")
    set(GD_LIBRARIES "${GD_LIBRARY}")
    set(GD_LIBRARY_DIRS "")
else()
    find_package(PkgConfig REQUIRED)
    pkg_check_modules(LUA REQUIRED lua5.3)
    pkg_check_modules(GD  REQUIRED gdlib)
endif()

add_library(wrap_gdlib MODULE src/wrap_gdlib.c)

target_include_directories(wrap_gdlib PRIVATE ${LUA_INCLUDE_DIRS} ${GD_INCLUDE_DIRS})
target_link_directories(wrap_gdlib    PRIVATE ${GD_LIBRARY_DIRS})

# gd only.  ${LUA_LIBRARIES} is deliberately unused: a loadable module leaves the
# lua_* symbols undefined for the host interpreter to resolve, so don't link them
# and don't add -Wl,--no-undefined.
target_link_libraries(wrap_gdlib PRIVATE ${GD_LIBRARIES})

# require() wants wrap_gdlib.so on POSIX and wrap_gdlib.dll on Windows
set_target_properties(wrap_gdlib PROPERTIES
    PREFIX ""
    SUFFIX "${CMAKE_SHARED_MODULE_SUFFIX}"
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}"
    LIBRARY_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}")

if(NOT WIN32)
    # ldconfig resolves libgd.so.3 to the distro's 2.3.0 in /usr/lib, so pin the
    # pkg-config libdir or we load the wrong libgd at runtime. Windows has no
    # RPATH equivalent; DLL search order is handled via PATH instead.
    set_target_properties(wrap_gdlib PROPERTIES
        BUILD_RPATH   "${GD_LIBRARY_DIRS}"
        INSTALL_RPATH "${GD_LIBRARY_DIRS}")
endif()
