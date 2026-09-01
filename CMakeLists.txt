cmake_minimum_required(VERSION 3.16)
project(pixel-lettering C)

set(CMAKE_C_STANDARD 99)
set(CMAKE_C_STANDARD_REQUIRED ON)
add_compile_options(-Wall -Wextra)

find_package(PkgConfig REQUIRED)
pkg_check_modules(LUA REQUIRED lua5.3)
pkg_check_modules(GD  REQUIRED gdlib)

add_library(wrap_gdlib MODULE src/wrap_gdlib.c)

target_include_directories(wrap_gdlib PRIVATE ${LUA_INCLUDE_DIRS} ${GD_INCLUDE_DIRS})
target_link_directories(wrap_gdlib    PRIVATE ${GD_LIBRARY_DIRS})

# gd only.  ${LUA_LIBRARIES} is deliberately unused: a loadable module leaves the
# lua_* symbols undefined for the host interpreter to resolve, so don't link them
# and don't add -Wl,--no-undefined.
target_link_libraries(wrap_gdlib PRIVATE ${GD_LIBRARIES})

set_target_properties(wrap_gdlib PROPERTIES
    PREFIX ""                       # require() wants wrap_gdlib.so
    SUFFIX ".so"
    LIBRARY_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}"
    # ldconfig resolves libgd.so.3 to the distro's 2.3.0 in /usr/lib, so pin the
    # pkg-config libdir or we load the wrong libgd at runtime.
    BUILD_RPATH   "${GD_LIBRARY_DIRS}"
    INSTALL_RPATH "${GD_LIBRARY_DIRS}")
