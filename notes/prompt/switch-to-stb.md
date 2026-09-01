Currently this project uses libgd to perform image decoding and encoding. I
would like to switch to using the STB single file headers found in
`lib/stb/stb_image.h` and `lib/stb/stb_image_write.h`.

This will involve

* Replace `src/wrap_gdlib.c` with `src/wrap_stb_image.c`.
* Replace `src/gdlib.lua` with `src/stb_image.lua`.
* Modify `src/lettering.lua` to use the interface provided by
  `src/stb_image.lua`.

The original specification for the project is found in
`notes/prompt/pixel-lettering.md`. Other than the change from `libgd` to
`stb_image`, the rest should remain the same.
