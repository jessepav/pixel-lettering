## Overview

This project is a Lua program that generates text as a transparent PNG from a
sprite sheet of glyphs provided as a PNG file along with relevant metadata
provided as Lua files.

## Definition Files

In @samples/text-definition.lua you find an example of a text-definition file
that will be passed to the program. In the `fonts` table, you find the paths to
the metrics and sprite sheet files used for each of three variants: regular,
bold, and italic. Only regular is required. If bold or italic variants are not
defined, and passage text uses a bold or italic font, it will be replaced with
the regular font. The format of the metrics file and the layout of the PNG
sprite sheet will be described below. If a font definition has a `line_gap` field,
it overrides the `line_gap` field in the font metrics file, described below. A
font definition may also carry a `color` field, which supplies the color for
that font unless the passage specifies one of its own.

The `passages` array contains tables defining individual output files. The
`width` field, in pixels, gives the width of the text column; text is wrapped to
it. The height of the resulting image is determined by the rendering of the
passage text. The format of passage text is described in
@samples/text-definition.lua itself. The `filename` indicates the name of the
PNG file to which to write the rendered image. If `scale` is given, it is an
integer >= 1 indicating the factor by which the resulting image should be scaled
(using a simple nearest neighbor algorithm) before being written. Thus the width
of the resulting PNG file will be `(width + 2 * padding) * scale`.

A passage may also specify `color`, either as `"#rrggbb"` (or `"#rgb"`) or as a
table `{r, g, b}`. The glyph sheets are masks, so the color supplies the RGB and
the sheet supplies the alpha. A passage's `color` overrides the `color` of every
font it uses; a font-level `color` therefore acts as a default for passages that
don't set one. Absent both, text is black.

A passage may specify `bgcolor`, in the same forms `color` accepts. Given one,
the image is filled with that color, fully opaque, instead of being left
transparent; the text is then drawn over it. Absent it, the background is
transparent.

A passage may specify `padding`, a number of pixels added on all four sides of
the rendered text. It is additive rather than an inset: text still wraps to
`width`, and the image becomes `width + 2 * padding` wide and
`2 * padding` taller than the text. The padding takes the background, so it is
transparent unless `bgcolor` is set. Padding is applied before `scale`, so it
scales along with everything else.

A passage may specify `line_gap`, which is used exactly as given and overrides
every font's gap for that passage. It may be negative, to pull lines closer
together than the fonts ask for. This is not the same as the font-level override:
a font-level `line_gap` participates in the maximum described below, whereas a
passage-level one replaces the result of that maximum outright.

Note that all paths in the text-definition file are relative to the file itself,
not the CWD.

In @pixel-lettering-font-sheets/summit/summit-metrics.lua you can find an
example font metrics definition. Here is what the fields indicate:

`cols` and `rows` are the number of columns and rows in the associated sprite
sheet. Each glyph is contained in a tile, and `tile_w` and `tile_h` indicate the
size of that tile. `baseline` is the y-value within each tile at which the
glyph's baseline is located. `line_gap` is the amount of vertical space, in
pixels, that should be added between lines of text. `space_w` indicates the
number of pixels that should be left blank for a space character; note that the
sheets contain no glyph for a space.

Line metrics are computed once for a whole passage, from every font named in the
`fonts` table rather than from the fonts a given line happens to use, so that
line pitch is even throughout:

    ascent      = max over all defined fonts of `baseline`
    descent     = max over all defined fonts of (`tile_h` - `baseline`)
    line_height = ascent + descent
    gap         = max over all defined fonts of the font's resolved `line_gap`

Every glyph is drawn with its own baseline row on the line's shared baseline, at
`ascent` pixels below the top of the line. A passage's own `line_gap`, if it has
one, replaces `gap` rather than joining that maximum. The total image height is
`n * line_height + (n - 1) * gap`, so there is no dangling gap after the last
line. A paragraph break counts as one blank line.

Then we have an array of glyphs. The `chr` is the Unicode character defined by
the glyph table. `lsb` is the Left Side Bearing, `adv` is the advance width.
`tile_x` and `tile_y` indicate the top-left corner in the sprite sheet where the
glyph tile may be found.

## Implementation

### Image Library

I want to use `libgd` as the image manipulation library. We will need to write
Lua 5.3 C bindings to this library. Write the C binding source to
`src/wrap_gdlib.c`. Create a CMakeLists.txt file in the project root that will
be used to build the Lua C module shared object.

### Lua Source

The Lua source code should be divided into two files: `src/gdlib.lua` that
provides ergonomic wrappers around the C functions exposed by `src/wrap_gdlib.c`
(if necessary), and `src/lettering.lua` that is the main script.

## Reference Material

* In `reference/libgd-gd-2.3.3` I've provided the full source of `libgd`.
* In `reference/refman-lua-5.3` is the reference manual to Lua 5.3.
* In `reference/lua-5.3` is the source code to Lua 5.3.

If you need to study any of the above references, spawn a subagent so you don't
use too much context in the search.

-----

Ask any questions needed to resolve ambiguities before beginning.
