/* lua 5.3 bindings to libgd, narrowed to what the lettering renderer needs.
 *
 * the flag-juggling gd requires for transparent truecolor output is baked into
 * create/recolor/scale/png_string rather than exposed, so a caller can't forget
 * it: there's no way from lua to leave saveAlpha off, or to clear a canvas with
 * blending on (which silently does nothing).
 */

#include <stdio.h>

#include <gd.h>
#include <lua.h>
#include <lauxlib.h>

#if defined(_WIN32)
#  if defined(WRAP_GDLIB_BUILD_DLL)
#    define WRAP_GDLIB_API __declspec(dllexport)
#  else
#    define WRAP_GDLIB_API __declspec(dllimport)
#  endif
#else
#  define WRAP_GDLIB_API
#endif

#define IMAGE_MT "gd.image"

/* im == NULL means explicitly destroyed, so __gc after destroy() is harmless */
typedef struct { gdImagePtr im; } Image;

static void push_image (lua_State *L, gdImagePtr im)
{
    Image *u = lua_newuserdata(L, sizeof(Image));
    u->im = im;
    luaL_setmetatable(L, IMAGE_MT);
}

static gdImagePtr check_image (lua_State *L, int idx)
{
    Image *u = luaL_checkudata(L, idx, IMAGE_MT);
    if (!u->im) luaL_error(L, "gd.image has been destroyed");
    return u->im;
}

static int check_byte (lua_State *L, int idx)
{
    int v = (int) luaL_checkinteger(L, idx);
    luaL_argcheck(L, v >= 0 && v <= 255, idx, "expected 0..255");
    return v;
}

/* every image this module hands out is truecolor, cleared to transparent, with
 * blending on and saveAlpha set.  blending on is what makes overlapping glyph
 * tiles composite instead of erasing each other, and it costs nothing on the
 * bilevel sheets: gdAlphaBlend short-circuits for both fully opaque and fully
 * transparent sources.
 */
static void finish_new (gdImagePtr im)
{
    gdImageAlphaBlending(im, gdEffectAlphaBlend);
    gdImageSaveAlpha(im, 1);
}

/* create(w, h) clears to transparent; create(w, h, r, g, b) clears to that
 * color, fully opaque.
 */
static int l_create (lua_State *L)
{
    int w = (int) luaL_checkinteger(L, 1);
    int h = (int) luaL_checkinteger(L, 2);
    int fill = gdTrueColorAlpha(0, 0, 0, gdAlphaTransparent);
    gdImagePtr im;

    luaL_argcheck(L, w >= 1, 1, "width must be >= 1");
    luaL_argcheck(L, h >= 1, 2, "height must be >= 1");

    if (!lua_isnoneornil(L, 3)) {
        int r = check_byte(L, 3);
        int g = check_byte(L, 4);
        int b = check_byte(L, 5);
        fill = gdTrueColorAlpha(r, g, b, gdAlphaOpaque);
    }

    im = gdImageCreateTrueColor(w, h);
    if (!im) return luaL_error(L, "cannot create a %dx%d image", w, h);

    /* the rows are calloc'd, i.e. opaque black, so the clear is mandatory -- and
       a transparent clear only works with blending off, since gdAlphaBlend
       returns dst untouched for a fully transparent source, making the fill a
       no-op. */
    gdImageAlphaBlending(im, gdEffectReplace);
    gdImageFilledRectangle(im, 0, 0, w - 1, h - 1, fill);
    finish_new(im);

    push_image(L, im);
    return 1;
}

static int l_load (lua_State *L)
{
    const char *fn = luaL_checkstring(L, 1);
    gdImagePtr im;
    FILE *fp = fopen(fn, "rb");

    if (!fp) return luaL_error(L, "cannot open '%s'", fn);
    im = gdImageCreateFromPng(fp);
    fclose(fp);
    if (!im) return luaL_error(L, "not a valid png: '%s'", fn);

    /* the glyph sheets are gray+alpha, which gd already gives us as truecolor;
       this is only here so a foreign palette sheet works too.  it clobbers both
       flags, hence finish_new afterwards. */
    if (!gdImageTrueColor(im)) gdImagePaletteToTrueColor(im);
    finish_new(im);

    push_image(L, im);
    return 1;
}

static int l_size (lua_State *L)
{
    gdImagePtr im = check_image(L, 1);

    lua_pushinteger(L, gdImageSX(im));
    lua_pushinteger(L, gdImageSY(im));
    return 2;
}

static int l_copy (lua_State *L)
{
    gdImagePtr dst = check_image(L, 1);
    gdImagePtr src = check_image(L, 2);
    int dx = (int) luaL_checkinteger(L, 3);
    int dy = (int) luaL_checkinteger(L, 4);
    int sx = (int) luaL_checkinteger(L, 5);
    int sy = (int) luaL_checkinteger(L, 6);
    int w  = (int) luaL_checkinteger(L, 7);
    int h  = (int) luaL_checkinteger(L, 8);

    luaL_argcheck(L, w >= 0 && h >= 0, 7, "negative size");

    /* gdImageCopy doesn't check the source rect, and gdImageGetPixel returns 0
       out of bounds -- opaque black -- so an out-of-range tile would quietly
       paint black boxes rather than fail. */
    luaL_argcheck(L, sx >= 0 && sy >= 0
                  && sx + w <= gdImageSX(src) && sy + h <= gdImageSY(src),
                  5, "source rect out of bounds");

    /* the destination needs no check: gdImageSetPixel clips, which is how a
       glyph running past the right margin is handled. */
    gdImageCopy(dst, src, dx, dy, sx, sy, w, h);
    return 0;
}

/* out-of-place: alpha comes from the source, rgb from the arguments.  the sheets
 * are white-on-transparent masks, so this is how text gets its color.  doing it
 * once per (sheet, color) beats masking every glyph, and because the result is a
 * fresh image its `transparent` is -1, so gdImageCopy's skip-transparent-pixel
 * path can never fire on it.
 */
static int l_recolor (lua_State *L)
{
    gdImagePtr src = check_image(L, 1);
    int r = check_byte(L, 2);
    int g = check_byte(L, 3);
    int b = check_byte(L, 4);
    int w = gdImageSX(src), h = gdImageSY(src);
    int x, y;
    gdImagePtr dst = gdImageCreateTrueColor(w, h);

    if (!dst) return luaL_error(L, "cannot create a %dx%d image", w, h);

    gdImageAlphaBlending(dst, gdEffectReplace);
    for (y = 0; y < h; y++)
        for (x = 0; x < w; x++) {
            int a = gdTrueColorGetAlpha(gdImageGetTrueColorPixel(src, x, y));
            gdImageSetPixel(dst, x, y, gdTrueColorAlpha(r, g, b, a));
        }
    finish_new(dst);

    push_image(L, dst);
    return 1;
}

/* integer block replication.  gdImageScale's nearest-neighbour walks the source
 * in 8.8 fixed point, and the step is truncated -- for factor 3 it uses
 * (long)(256/3) = 85 instead of 85.333 -- so the sampled column drifts by more
 * than a pixel across a wide image.  only powers of two come out exact there.
 */
static int l_scale (lua_State *L)
{
    gdImagePtr src = check_image(L, 1);
    int f = (int) luaL_checkinteger(L, 2);
    int w, h, x, y;
    gdImagePtr dst;

    luaL_argcheck(L, f >= 1, 2, "factor must be >= 1");

    w = gdImageSX(src);
    h = gdImageSY(src);
    dst = gdImageCreateTrueColor(w * f, h * f);
    if (!dst) return luaL_error(L, "cannot create a %dx%d image", w * f, h * f);

    gdImageAlphaBlending(dst, gdEffectReplace);
    for (y = 0; y < h; y++)
        for (x = 0; x < w; x++) {
            int c = gdImageGetTrueColorPixel(src, x, y);
            int dx, dy;
            for (dy = 0; dy < f; dy++)
                for (dx = 0; dx < f; dx++)
                    gdImageSetPixel(dst, x * f + dx, y * f + dy, c);
        }
    finish_new(dst);

    push_image(L, dst);
    return 1;
}

static int l_png_string (lua_State *L)
{
    gdImagePtr im = check_image(L, 1);
    int level = (int) luaL_optinteger(L, 2, -1);
    int size = 0;
    void *p;

    luaL_argcheck(L, level >= -1 && level <= 9, 2, "level must be -1..9");

    /* the FILE* writers return void and can't report failure; only the Ptr form
       can, which is why output goes through a string. */
    p = gdImagePngPtrEx(im, &size, level);
    if (!p) return luaL_error(L, "png encoding failed");
    lua_pushlstring(L, (const char *) p, (size_t) size);
    gdFree(p);      /* gd may not be using our allocator, so not free() */
    return 1;
}

static int l_get_pixel (lua_State *L)
{
    gdImagePtr im = check_image(L, 1);
    int x = (int) luaL_checkinteger(L, 2);
    int y = (int) luaL_checkinteger(L, 3);
    int c, a;

    luaL_argcheck(L, x >= 0 && x < gdImageSX(im), 2, "x out of bounds");
    luaL_argcheck(L, y >= 0 && y < gdImageSY(im), 3, "y out of bounds");

    c = gdImageGetTrueColorPixel(im, x, y);
    a = gdTrueColorGetAlpha(c);

    lua_pushinteger(L, gdTrueColorGetRed(c));
    lua_pushinteger(L, gdTrueColorGetGreen(c));
    lua_pushinteger(L, gdTrueColorGetBlue(c));
    /* gd's alpha is 7-bit and inverted; this is the same conversion gd_png.c
       applies on write, so the number reported is the one the png will hold. */
    lua_pushinteger(L, 255 - ((a << 1) + (a >> 6)));
    return 4;
}

static int l_destroy (lua_State *L)
{
    Image *u = luaL_checkudata(L, 1, IMAGE_MT);

    if (u->im) {
        gdImageDestroy(u->im);
        u->im = NULL;
    }
    return 0;
}

static int l_tostring (lua_State *L)
{
    Image *u = luaL_checkudata(L, 1, IMAGE_MT);

    if (u->im) lua_pushfstring(L, IMAGE_MT ": %dx%d",
                               gdImageSX(u->im), gdImageSY(u->im));
    else lua_pushliteral(L, IMAGE_MT ": destroyed");
    return 1;
}

static const luaL_Reg image_methods[] = {
    { "size",       l_size       },
    { "copy",       l_copy       },
    { "recolor",    l_recolor    },
    { "scale",      l_scale      },
    { "png_string", l_png_string },
    { "get_pixel",  l_get_pixel  },
    { "destroy",    l_destroy    },
    { NULL, NULL }
};

static const luaL_Reg module_funcs[] = {
    { "create",     l_create     },
    { "load",       l_load       },
    { "size",       l_size       },
    { "copy",       l_copy       },
    { "recolor",    l_recolor    },
    { "scale",      l_scale      },
    { "png_string", l_png_string },
    { "get_pixel",  l_get_pixel  },
    { "destroy",    l_destroy    },
    { NULL, NULL }
};

WRAP_GDLIB_API int luaopen_wrap_gdlib (lua_State *L)
{
    /* the metatable has to be complete -- __gc included -- before any userdata
       gets it, or lua 5.3 never marks the object for finalization. */
    luaL_newmetatable(L, IMAGE_MT);

    luaL_newlib(L, image_methods);
    lua_setfield(L, -2, "__index");
    lua_pushcfunction(L, l_destroy);
    lua_setfield(L, -2, "__gc");
    lua_pushcfunction(L, l_tostring);
    lua_setfield(L, -2, "__tostring");
    lua_pop(L, 1);

    luaL_newlib(L, module_funcs);
    return 1;
}
