# pixel-lettering

A tool to generate pixel font lettering from a glyph spritesheet.

## Building

Linux/Unix/etc.:

```sh
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build
```

Windows:

```bat
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release ^
      -DLUA_INCLUDE_DIR=C:/path/to/lua/include ^
      -DLUA_LIBRARY=C:/path/to/lua/lib/lua53.lib ^
      -DGD_INCLUDE_DIR=C:/path/to/gd/include ^
      -DGD_LIBRARY=C:/path/to/gd/lib/gd.lib
cmake --build build --config Release
```
