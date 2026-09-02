# pixel-lettering

A tool to generate pixel font lettering from a glyph spritesheet.

Image decoding and encoding use the [stb](https://github.com/nothings/stb)
single-file headers vendored in `lib/stb`.

## Building

### Linux

```sh
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build
```

### Windows

To build and run this program on Windows, you need to fetch
`pixel-lettering-windows-libs.zip` from

https://app.box.com/shared/static/plxvafwjm493yzjh32zhy64k4kfm3jrb.zip

and unpack it in the project folder. It will yield a `windows-libs` folder
that contains a pre-built version of Lua 5.3 used by our build script.

Then, use cmake:

```sh
cmake -S . -B build
cmake --build build --config Release
```

You can then invoke the program via `bin/pixel-lettering.bat`.
