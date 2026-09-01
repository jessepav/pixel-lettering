# pixel-lettering

A tool to generate pixel font lettering from a glyph spritesheet.

Image decoding and encoding use the [stb](https://github.com/nothings/stb)
single-file headers vendored in `lib/stb`, compiled straight into the Lua
module, so Lua 5.3 is the only external dependency.

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
      -DLUA_LIBRARY=C:/path/to/lua/lib/lua53.lib
cmake --build build --config Release
```
