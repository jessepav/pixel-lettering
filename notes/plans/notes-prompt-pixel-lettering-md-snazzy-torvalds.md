# pixel-lettering: implement the renderer

## Context

`notes/prompt/pixel-lettering.md` specifies a Lua 5.3 tool that renders a passage
of text into a transparent PNG from a pixel-font glyph sprite sheet plus Lua
metrics files. **None of the program exists yet** — the repo holds only the spec,
`samples/text-definition.lua`, `utils/fix-metrics.lua` (which produced the 175
`-metrics.lua` files), and the `bin/*.sh` tagging scripts.

The font collection is in place: 113 families / 175 sheets under the
`pixel-lettering-font-sheets` symlink, each an 8-bit **grayscale+alpha** PNG
(color type 4) whose pixels are strictly bilevel — I decoded `summit.png` and it
contains exactly two values, `(gray 0, alpha 0)` and `(gray 255, alpha 255)`.
White-on-transparent masks, no anti-aliasing. That property is what makes
arbitrary text color cheap and makes alpha blending lossless, and it underpins
several decisions below.

Outcome: `./bin/lettering samples/text-definition.lua` writes `samples/passage1.png`
(400×337) and `samples/passage2.png` (800×28).

## Decisions settled with the user

Fixed requirements, not open questions.

1. **Color.** Passages take an optional `color` — `"#rrggbb"` or `{r,g,b}` —
   defaulting to white, overridable per font definition (font wins). Sheets are
   alpha masks, so a rendered pixel takes RGB from `color`, alpha from the sheet.
2. **Paths.** Font `metrics`/`sheet` paths *and* passage `filename` all resolve
   against the directory containing the text-definition file.
3. **Markdown.** Hand-rolled parser for the documented subset only. Not `cmark`,
   not `lpeg`.
4. **Overlong word.** Hard-broken at the last glyph that fits; never overflows.
5. **Missing glyph.** Substitute the sheet's notdef (the `chr = "\0"` first
   glyph, whose `adv` is the full `tile_w`); warn once per distinct character.
6. **Bold+italic nesting.** No such sheet exists, so the innermost span wins —
   `**bold _and italic_**` renders the inner run italic. Same fallback path as a
   missing bold/italic font.
7. **Trailing gap trimmed.** Height = sum of line heights + gaps *between* them.
   A paragraph break counts as one blank line.
8. **`line_gap` override replaces the `tile_h` override.** May be negative.
   Valid at both font and passage level, but the two levels work differently —
   see decision 9. A font-level `line_gap` overrides that font's metrics value and
   then *participates* in the max; a passage-level `line_gap` is used *exactly as
   given* and does not participate in anything.
9. **Uniform vertical metrics** over *every* font in the `fonts` table, whether a
   given line uses it or not:
   `ascent = max(baseline)`, `descent = max(tile_h - baseline)`,
   `line_height = ascent + descent`.

   The gap resolves in **two tiers**, and this distinction matters:

   ```lua
   font_gap = max over all defined fonts of (fdef.line_gap or metrics.line_gap)
   gap      = passage.line_gap or font_gap        -- outright override, NOT a max
   ```

   So `passage.line_gap` is an exact value, never folded into the maximum. With
   the sample's `bold.line_gap = 5`, a passage asking for `line_gap = -2` gets
   **-2**, not `max(-2, 5) = 5`. Getting this wrong would silently defeat the
   entire point of allowing negative gaps, and it would do so only for passages
   whose override is smaller than some font's — a nasty partial failure.
10. **Build layout.** Out-of-source CMake build into `build/`; a `bin/lettering`
    wrapper sets the Lua path vars and execs `lua5.3 src/lettering.lua`. The Lua
    sources contain no `package.path`/`cpath` manipulation.
11. **Lean error handling.** No schema validation, no existence checks, no
    `pcall`; bad input raises a Lua error with a traceback. Argument checking
    only in the C binding, where a bad type would segfault. Matches commits
    `03d6d4b` / `7489d65`.

The user has already applied the decision-8 edits to **both**
`samples/text-definition.lua` (bold now carries `line_gap = 5`) and the font-override
paragraph of `notes/prompt/pixel-lettering.md`.

## Three findings that change the obvious implementation

I verified each of these directly rather than taking them on faith.

### A. A naive "each marker toggles" parser fails on the sample itself

Passage 1 contains the prose `A backslash before * or _ removes its special meaning,`
— **bare, unescaped** markers. Toggling on each one opens italic spans that never
close, swallowing both characters and italicizing the rest of the passage.

I implemented both parsers and ran them against the real sample:

```
FLANKING-rule parser: passage1.png 18 lines 400x337   <- correct
NAIVE  toggle parser: passage1.png 19 lines 400x356   <- wrong
```

So the sample file *is* the regression test, and 337 vs 356 is the discriminator.
Two CommonMark-style flanking rules plus a two-pass match fix it, at a cost of
~20 extra lines:

- a delimiter run **can open** only if the character after it is not whitespace
- a delimiter run **can close** only if the character before it is not whitespace

The second pass also makes unpaired openers fall back to literal rather than
leaking style to end-of-passage. Verified classification on the sample: the six
markers in `*word*`, `_word_`, `**word**` pair correctly, and the bare `*` and
`_` are both emitted as literal characters.

### B. `gdImageScale`'s nearest-neighbour is exact only for powers of two

From `reference/libgd-gd-2.3.3/src/gd_interpolation.c`: `gd_ftofx(x)` is
`(long)((x) * 256)` and `gd_fxtoi(x)` is `(x) >> 8`, so the column index is
`n = (j * f_dx) >> 8` in 8.8 fixed point. For scale 3 on width 400,
`f_dx = (long)(0.33333 * 256) = 85`, not 85.333. Simulating it: source column 0
is sampled at `j = 0,1,2,3` — four times — and by `j = 1199` it samples column 398
where it should sample 399. About 1.5 columns of drift, i.e. visibly duplicated
and dropped columns. Factors 2, 4, 8 give exact `f_dx` (128, 64, 32) and are fine.

Fix: **write our own integer block-replication scaler in C.** ~12 lines,
unconditionally exact for every factor, and it removes the need to expose
`gdImageSetInterpolationMethod` or to remember the mandatory `gdImageSaveAlpha`
on `gdImageScale`'s result.

### C. Use alpha blending for glyph blits — but not for the reason you'd guess

`adv` can be less than `tile_w` (summit: `adv` 3–12, `tile_w` 11), so consecutive
glyph tiles overlap by up to 8 columns. The tempting conclusion is that
`gdEffectReplace` would let the next tile's transparent padding erase the previous
glyph's ink.

I measured it: **0 of 531 glyphs** across `summit`, `summit_bold`, and
`summit_italic` have ink extending past their advance. So that erasure cannot
happen with these sheets, and `gdEffectReplace` would in fact work today.

Adopt `gdEffectAlphaBlend` anyway, for the accurate reasons: it costs nothing and
it is robust to a sheet that *does* have overhang. Because the sheets are strictly
bilevel, every pixel hits a short-circuit in `gdAlphaBlend` (`gd.c:4065` —
`src_alpha == gdAlphaOpaque` returns src, `src_alpha == gdAlphaTransparent`
returns dst), so blending is byte-for-byte identical to a copy. Blending off is
needed only for the initial transparent clear.

## Expected output (precomputed, from the real metrics)

```
ascent=12  descent=2  line_height=14  gap=5
passage1.png   18 lines ->  400x337     (18*14 + 17*5 = 337)
passage2.png    1 line  ->  400x14  ->  800x28  (scale 2)
```

`gap = 5` comes from bold's font-level override winning the font-tier max —
neither sample passage sets its own `line_gap`, so the passage tier never engages.
It applies to *every* line, including the many with no bold on them, and to
passage 2, which has no bold at all. Direct consequence of decision 9; intended,
but worth saying out loud.

Also measured: the three summit variants do **not** share advances (145/177
glyphs differ between regular and bold, 115/177 for italic), so measurement must
use each run's own font. And no character in either sample passage is missing
from summit's 177-glyph charset, so the samples never exercise notdef.

## Environment (verified, no action needed)

- `lua5.3` 5.3.6; headers `/usr/include/lua5.3`; `pkg-config lua5.3` works.
- libgd **2.3.3 built from source at `/usr/local`** — `/usr/local/include/gd.h`
  is byte-identical in the relevant declarations to `reference/libgd-gd-2.3.3/src/gd.h`.
  PNG support confirmed compiled in (real `gdImagePng*` symbols, not `_noPng`
  stubs; `libpng16` linked).
- **A different distro libgd 2.3.0 sits at `/usr/lib/x86_64-linux-gnu/libgd.so.3`,
  and `ldconfig -p` resolves `libgd.so.3` there.** The module needs an explicit
  RPATH to `/usr/local/lib` or it silently loads 2.3.0. Most likely build surprise.
- `gd_png.c` loads `PNG_COLOR_TYPE_GRAY_ALPHA` via `gdImageCreateTrueColor` +
  `png_set_gray_to_rgb` with `transparent = -1`, so the sheets arrive as truecolor
  with no palette and no tRNS.
- cmake 3.31.8 at `/opt/cmake/bin/cmake`, gcc. Lua 5.3's built-in `utf8` covers
  the multi-byte charset; no rock needed.

## Files

### `src/wrap_gdlib.c`

Design principle: every libgd trap is a consequence of an exposed knob, so the
binding **does not expose the knobs**. `create`, `recolor`, `scale`, and
`png_string` each bake in the correct flag settings internally, making it
structurally impossible to emit a 24-bit PNG or perform a no-op clear.
Deliberately not exported: `alpha_blending`, `save_alpha`, `set_pixel`,
`filled_rectangle`, `set_interpolation_method`, `gdImageScale`, `gdImageCopyMerge`,
and the `gdEffect*`/`gdAlpha*` constants.

Userdata `typedef struct { gdImagePtr im; } Image;` (`im == NULL` means
destroyed), metatable `"gd.image"` with `__name` set for good error messages,
`__index` → method table, `__tostring`, and an idempotent `__gc`.
**Lua 5.3 trap:** `__gc` must already be in the metatable when `setmetatable` is
called, or the finalizer is never registered — build the metatable completely in
`luaopen_wrap_gdlib` before any image can exist.

Functions:

- `create(w, h)` — `gdImageCreateTrueColor` → `gdImageAlphaBlending(im, gdEffectReplace)`
  → `gdImageFilledRectangle(..., gdTrueColorAlpha(0,0,0,gdAlphaTransparent))` →
  `gdImageAlphaBlending(im, gdEffectAlphaBlend)` → `gdImageSaveAlpha(im, 1)`.
  The canvas is calloc'd to *opaque black*, so the clear is mandatory, and it must
  happen with blending off or `gdAlphaBlend` short-circuits and the fill is a
  silent no-op. Leaving blending on afterwards is finding C.
- `load(filename)` — explicit `fopen` + `gdImageCreateFromPng` so "missing file"
  and "corrupt PNG" get distinct messages; then `gdImagePaletteToTrueColor` as a
  safety net for foreign sheets, re-asserting both flags afterwards since it
  clobbers them.
- `size(im)` → w, h
- `copy(dst, src, dst_x, dst_y, src_x, src_y, w, h)` — plain `gdImageCopy` with
  blending on. The hot path, once per glyph.
- `recolor(im, r, g, b)` → **new** image; alpha copied verbatim, RGB replaced.
- `scale(im, factor)` → new image by integer block replication (finding B).
- `png_string(im [, level])` → Lua string via `gdImagePngPtrEx` + `lua_pushlstring`
  + **`gdFree`** (not `free`). The `FILE*` writers return `void` and cannot report
  failure, so this is the only form that can detect an error.
- `get_pixel(im, x, y)` → r, g, b, a with `a` in 0–255, 255 = opaque, using the
  same `255 - ((a<<1) + (a>>6))` conversion `gd_png.c` uses on write, so it
  reports exactly what the PNG will contain. A verification helper.
- `destroy(im)` — deterministic free; `__gc` then no-ops.

**Recolor the whole sheet once per `(font, color)` pair and cache it**, rather
than masking per glyph. Then every glyph blit is a plain `gdImageCopy` with no
per-pixel work, there is exactly one per-pixel loop in the program, and the module
needn't export `get_pixel`/`set_pixel` for drawing. It also eliminates the
`gdImageCopy`-skips-`src->transparent` trap outright: `recolor` returns a fresh
`gdImageCreateTrueColor` whose `transparent` is `-1`, which no packed pixel equals.

Guards — the only place decision 11 permits them, because the alternative is a
segfault or silent corruption: `luaL_checkudata` on image arguments;
`luaL_checkinteger` on every numeric argument (`lua_tointeger` yields 0 on a
non-number, and `create(0,0)` returns a live image with an empty `tpixels`);
`r,g,b` clamped to 0–255; `factor >= 1`; `w,h >= 1`; NULL checks on load/create/
png results; and the **source rect** validated against `gdImageSX/SY` — neither
`gdImageCopy` nor `gdImageGetPixel` validates it, and the latter returns 0 out of
bounds, so an out-of-range tile would silently paint opaque black rectangles. The
destination side needs no check: `gdImageSetPixel` clips via
`gdImageBoundsSafeMacro`, and we rely on that for the right margin.

### `src/gdlib.lua` (~40 lines)

`local C = require "wrap_gdlib"` then `setmetatable({}, { __index = C })` so new C
functions need no edit here. Adds the three things that genuinely belong in Lua:

1. `parse_color(v)` → r, g, b — handles `"#rrggbb"`, `"#rgb"`, `{r,g,b}`, and
   `nil` → white. String work, so not C; image-domain, so not `lettering.lua`.
2. `write_png(im, path, level)` = `png_string` + `assert(io.open(path,"wb"))`.
   The `assert` *is* the error strategy per decision 11.
3. The single place the C module name appears, so `lettering.lua` only ever does
   `require "gdlib"`.

**Do not name the shared object `gdlib.so`.** `require "gdlib"` would match both
it and `src/gdlib.lua`; the Lua searcher happens to try `.lua` first, but that is
a fragile coincidence and would leave the `.so` unreachable. `wrap_gdlib.so`
(matching the spec's source filename) has no ambiguity.

### `src/lettering.lua`

Shebang `#!/usr/bin/env lua5.3`, 4-space indent, `local function name (args)`
with the space before the paren, `-----` 80-column dividers, aligned `local`
requires, lowercase "why" comments, no header block — matching
`utils/fix-metrics.lua`.

```
dirname / resolve                       -- paths, relative to the definition file
load_font / load_fonts                  -- fonts, plus vertical_metrics
vertical_metrics(fonts)                 -- ascent/descent/line_height + font_gap
sheet_for(font, r, g, b)                -- memoized recolor
preprocess(text)                        -- normalization, \1 = line break
scan_delims / match_delims / parse_inline
shape(atoms, fonts, warned)             -- atoms -> word/space/break tokens
wrap(tokens, width)                     -- greedy, with mid-word hard break
render(lines, width, vm, gap, sheets)
do_passage / main
```

**Fonts.** `load_font` returns `{ image, metrics, index, notdef, line_gap, color, sheets }`,
where `index` maps `chr` → glyph skipping entry 1 (the `"\0"` notdef slot, kept as
`notdef`). Iterate `{"regular","bold","italic"}` in fixed order, not `pairs`, for
reproducible warning order. A missing `regular` raises naturally on first access —
intended lean behavior.

Two consequences of decision 9's max formulation, each worth a comment:
`ascent >= font.baseline` for every font, so the top-of-tile offset is never
negative and line 1 is never clipped; and `dst_y + tile_h <= line_top + line_height`,
so every tile fits its line box. Only a *negative* gap makes lines overlap, which
is the point of allowing it.

**Preprocessing**, in this exact order — the hard-break sentinel must be lifted
out *before* single newlines become spaces, or the preceding rule has already
stripped the surrounding spaces and `\`+newline degrades to backslash-space:

```lua
t = t:gsub("\r\n", "\n"):gsub("^%s+", ""):gsub("%s+$", "")
t = t:gsub("[ \t]*\n[ \t]*", "\n")
t = t:gsub("\\\n", "\1")                                    -- before the next line
t = t:gsub("\n+", function (nl)
        return #nl == 1 and " " or "\1\1"                   -- 2+ -> blank line
    end)
t = t:gsub("  +", " ")
```

`\1` is safe as a sentinel: every sheet's charset starts at 0x21.

**Inline parsing**, three passes (finding A). `scan_delims` walks bytes skipping
`\`+`*`/`_` pairs, and records each delimiter *run* with `can_open`/`can_close`
from the flanking rules, taking `**` before `*` by longest match. `match_delims`
pairs them with a stack, requiring `mk` equality, and leaves unmatched entries out
of the map so `parse_inline` emits them as literals. `parse_inline` emits
`{c=<utf8 char>, st=...}`, `{sp=true, st=...}`, `{brk=true}`, with style from a
stack of open markers: `STYLE = { ["**"]="bold", ["*"]="italic", ["_"]="italic" }`
and current style `STYLE[stack[#stack]] or "regular"`. **Innermost wins for free**
(decision 6) — inside `**bold _and italic_**` the stack top is `_`, so no
bold+italic combination is ever requested. Tracking `*` and `_` as distinct
markers makes `*a_b*` and `_a*b_` both work. Every marker, escape, space, and `\1`
is single-byte ASCII, so the general case is `utf8.offset(s, 2, i)`, O(1) per char.

**Shaping.** `font = fonts[atom.st] or fonts.regular` — one line covers both the
missing-variant fallback and decision 6. Missing glyph → `font.notdef` plus a
warning gated on a `warned` table created once in `main` and threaded through, so
a character warns once per invocation across all passages. Consecutive character
atoms coalesce into one word *regardless of style changes inside it*, so
`**bold**word` is correctly unbreakable. `space_w` comes from the space atom's own
resolved font — note the corollary that in `**a** **b**` the space is regular.

**Wrapping.** Measurement is in advances: a glyph is blitted at `pen + lsb` and
the pen moves by `adv` (`lsb` is 0 in all summit files but is honored). Greedy:
place the first word unconditionally, else extend if
`cur.w + pending_space + word.w <= width`. The fit test runs *before* the overlong
test, so `emit()` has already reset the line and the hard-break loop always starts
fresh. Inside that loop the `cur.w > 0` guard is also the infinite-loop guard — a
single glyph wider than `width` is placed anyway and clipped by the canvas.
Final flush uses `cur.w > 0 or #lines == 0` so an empty or markup-only passage
yields one blank line rather than `create(w, 0)`.

**Render.** `height = math.max(1, n * line_height + (n-1) * gap)` (decision 7,
and the clamp handles a large negative gap). Per line `top = (i-1) * (line_height + gap)`;
per glyph blit `(tile_x, tile_y, tile_w, tile_h)` to
`(x, top + ascent - font.metrics.baseline)`, putting each glyph's own baseline row
on the line's shared baseline. Colors resolve per passage before the loop, font
`color` beating passage `color`, with `sheet_for` memoizing on `"r,g,b"` and keyed
by the font table so fallbacks share a sheet.

`vertical_metrics` computes `ascent`, `descent`, `line_height`, and **`font_gap`
only** — the max over all defined fonts of `fdef.line_gap or metrics.line_gap`. It
never sees a passage. The passage tier is applied later, once per passage, as a
plain `or`:

```lua
local gap = passage.line_gap or vm.font_gap    -- exact value, never max()ed
```

Keep these in separate places precisely so the two tiers cannot get merged; a
comment at the `or` should record why (decision 9).

`main`: no arguments → usage on stderr and `exit(1)` (CLI usage, not input
validation). Otherwise loop over `arg`; per file `base = dirname(path)` and
`def = dofile(path)`, with a single `warned` table for the whole invocation.

### `CMakeLists.txt`

```cmake
cmake_minimum_required(VERSION 3.16)
project(pixel-lettering C)
set(CMAKE_C_STANDARD 99)
add_compile_options(-Wall -Wextra)

find_package(PkgConfig REQUIRED)
pkg_check_modules(LUA REQUIRED lua5.3)
pkg_check_modules(GD  REQUIRED gdlib)

add_library(wrap_gdlib MODULE src/wrap_gdlib.c)
target_include_directories(wrap_gdlib PRIVATE ${LUA_INCLUDE_DIRS} ${GD_INCLUDE_DIRS})
target_link_directories(wrap_gdlib    PRIVATE ${GD_LIBRARY_DIRS})
target_link_libraries(wrap_gdlib      PRIVATE ${GD_LIBRARIES})   # gd only, never lua

set_target_properties(wrap_gdlib PROPERTIES
    PREFIX "" SUFFIX ".so"
    LIBRARY_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}"
    BUILD_RPATH   "${GD_LIBRARY_DIRS}"
    INSTALL_RPATH "${GD_LIBRARY_DIRS}")
```

`MODULE` not `SHARED` (no SONAME); `PREFIX ""` because CMake prefixes `lib` even
on modules. `${LUA_LIBRARIES}` is deliberately unused — `pkg-config --libs lua5.3`
does emit `-llua5.3`, and it must be dropped: a loadable module leaves `lua_*`
undefined for the host to resolve. Do not add `-Wl,--no-undefined`, and do not set
`C_VISIBILITY_PRESET hidden` (it would hide `luaopen_wrap_gdlib`).
`BUILD_RPATH` is the one that matters since we run from `build/` and never install.

### `bin/lettering`

Follows the existing `bin/*.sh` idiom but **without** `cd $PROJDIR`, so relative
arguments still resolve against the caller's CWD:

```bash
#!/bin/bash

PROJDIR=$(realpath "$(dirname "$0")/..")

# lua 5.3 checks LUA_PATH_5_3 before LUA_PATH, and /opt/luarocks may well have
# set it, so pin both.  trailing ";;" appends lua's own defaults.
export LUA_PATH_5_3="$PROJDIR/src/?.lua;;"
export LUA_CPATH_5_3="$PROJDIR/build/?.so;;"
export LUA_PATH="$LUA_PATH_5_3"
export LUA_CPATH="$LUA_CPATH_5_3"

exec lua5.3 "$PROJDIR/src/lettering.lua" "$@"
```

### Also update

- **`notes/prompt/pixel-lettering.md`** — the font-override paragraph is already
  done, but these are still stale: line 37–38 says *"draw text with line height of
  `tile_h`"*, which contradicts decision 9's max-based `line_height`; there is no
  mention of passage-level `line_gap`, of its being allowed to go negative, of the
  max-over-all-defined-fonts rule, or of `color` at all; and line 45 reads *"`lsb`
  is the Life Sidebearing"* → **Left Side Bearing**.
- **`bin/gen-filelist.sh`** — currently `fd -g '*.lua'`, so `src/wrap_gdlib.c`
  would never be tagged; add `-g '*.c'`.
- `.gitignore` already covers `build/`.

## Verification

Available: `identify`/`convert` (ImageMagick 6.9.11), `readelf`, `nm`, `ldd`,
`od`, `python3`. No `pngcheck`, no PIL, no valgrind.

1. **Right libgd, no Lua linked.**
   `readelf -d build/wrap_gdlib.so | grep -E 'RUNPATH|RPATH'` → `/usr/local/lib`;
   `ldd build/wrap_gdlib.so | grep libgd` → **`/usr/local/lib/libgd.so.3`**. If it
   shows `/usr/lib/x86_64-linux-gnu`, everything downstream is testing 2.3.0.
   `nm -D --undefined-only ... | grep -c ' lua'` → nonzero;
   `nm -D --defined-only ... | grep luaopen` → `luaopen_wrap_gdlib`.
2. **Binding smoke test**, isolating the clear/alpha traps from the rest:
   `create(4,4)` then `get_pixel(im,0,0)` → `0 0 0 0` (proves the clear worked);
   `load` summit → `154 182`; `recolor(s,255,0,0)` then find a pixel with `a==255`
   → `255 0 0 255` (alpha kept, RGB replaced).
3. **Run from a different CWD** — the only real test of decision 2:
   `cd /tmp && /home/.../bin/lettering /home/.../samples/text-definition.lua`.
   Outputs must land in `samples/`, not `/tmp`, with nothing on stderr.
4. **Genuinely RGBA.** Byte 25 of a PNG is the color type:
   `od -An -tu1 -j25 -N1 samples/passage1.png` → **6**. A 4 means `saveAlpha` was
   missed somewhere and alpha was silently dropped.
   `identify -format '%m %wx%h %[channels]\n'` → `PNG 400x337 rgba`, `PNG 800x28 rgba`.
5. **Exactly two pixel values**, since the sheets are bilevel, the default color
   is white, and blending short-circuits both ways:
   `convert samples/passage1.png -depth 8 txt: | awk 'NR>1{print $3}' | sort -u`
   → `#00000000` and `#FFFFFFFF`, nothing else. Plus
   `convert ... -channel A -separate -format '%[fx:mean]\n' info:` → positive, to
   prove the image isn't blank.
6. **Geometry, and the two-tier gap rule (decision 9).** `400x337` = `18*14 + 17*5`
   simultaneously checks ascent/descent, the font-tier max of 5, and the
   no-dangling-gap rule. Then vary one input at a time, height = `18*14 + 17*gap`:

   | change | expected gap | height |
   |---|---|---|
   | none (bold's `line_gap = 5` wins the font-tier max) | 5 | **337** |
   | passage `line_gap = 0` | 0 | **252** |
   | passage `line_gap = -3` | **-3**, not `max(-3,5)` | **201** |
   | passage `line_gap = 2` | **2**, not `max(2,5)` | **286** |
   | delete bold's `line_gap = 5` | `max(1,1,1)` = 1 | **269** |

   The two middle rows are the ones that matter: both ask for a gap *smaller* than
   bold's 5, so a "max everything" implementation would return 5 and yield 337 for
   all three. Any of these coming back 337 means the passage tier was folded into
   the maximum instead of overriding it.
7. **The parser discriminator (finding A).** `passage1.png` at **400x337**. If it
   comes out **400x356** (19 lines), the flanking rules regressed to naive
   toggling. Also confirm the literal `*` and `_` actually render in line 3.
8. **Scale exactness (finding B).** Add a temporary unscaled twin of passage 2;
   `convert passage2.png -sample 50% miff:- | compare -metric AE - passage2_1x.png null:`
   → 0, and the point-resize forward direction → 0. Then **repeat at scale 3 and 5** —
   these are precisely where `gdImageScale` would give nonzero AE and our own
   scaler gives 0. Re-run step 4's `od` check on a scaled output too, since
   scaling is where the dropped-alpha trap would strike.
9. **Features**, each a small purpose-built definition file: overlong word at
   `width = 40` (assert line count `ceil(total_adv/40)`, since a 40px canvas makes
   overflow unobservable); `**b** *i*` differs from unmarked (`AE` nonzero);
   `**bold _and italic_**` vs `**bold** *and italic*` → `AE` 0 on the second half
   (decision 6); bold font commented out → `**word**` identical to `word`;
   `Ж` ×3 plus `→` ×1 → **exactly two** stderr lines and notdef ink (both confirmed
   absent from summit, unlike `é`/`—` which are present and should render);
   `color = "#ff0000"` → values become `#FF000000`/`#FF0000FF`, then also give bold
   `color = {0,255,0}` and expect **three** distinct RGB values, proving the
   per-font override beats the passage's.
10. **Determinism and leaks.** Run twice and `cmp` → byte-identical. With no
    valgrind, render ~200 passages in a loop and watch RSS via `/proc/self/status`:
    linear growth would indicate `free` instead of `gdFree` in `png_string`, or a
    never-registered `__gc` from the Lua 5.3 metatable-ordering trap.
11. `./bin/retag-project.sh`, then confirm `src/wrap_gdlib.c` is in `gtags.files`.

## Known limitations to flag, not fix

- **Kerning is not implemented.** `summit.json` carries 3995 `{left,right,kern}`
  pairs, but `fix-metrics.lua` drops them and the `-metrics.lua` files have none.
  Adding it would change the metrics format. Worth a separate decision.
- The `chr = "\0"` slot is documented as U+000A in
  `pixel-lettering-font-sheets/ordered_unicode_chars.txt`; treating it as notdef
  is our interpretation, not something the data states.
- **`space_w` across a style boundary** is unspecified; I chose the space's own
  resolved font. Always using `regular` is equally defensible — comment the choice.
- **`adv` vs `tile_w` at the right margin.** Wrapping measures advances, so a line
  summing exactly to `width` has its last tile's padding clipped. Harmless for all
  175 summit-family sheets (measured: no glyph has ink past `adv`), but a sheet
  with overhang would lose its last glyph's right edge.
- **A blank line costs `line_height + 2*gap`** = 24px in the sample, a gap on each
  side. Consistent with decision 7 but chunkier than "one blank line" suggests —
  worth eyeballing `passage1.png` before calling it final.
- **Decision 9's surprise:** adding an unused font to the `fonts` table changes
  every passage's line spacing. Specified, but a memorable support question.
- A sufficiently negative `line_gap` is clamped by `math.max(1, ...)` rather than
  erroring.
- gd quantizes alpha to 7 bits. Exact for these bilevel sheets (255→0→255 and
  0→127→0 both round-trip), but an anti-aliased sheet would lose precision.
- Invalid UTF-8 makes `utf8.offset` return nil; per decision 11 let it raise, but
  ensure the `or (#s + 1)` fallback can't spin.
