/* lua 5.3 bindings to the stb single-file image headers, narrowed to what the
 * lettering renderer needs.
 *
 * an image here is always 8-bit RGBA with straight (non-premultiplied) alpha,
 * row-major and tightly packed, which is both what stb_image hands back for
 * desired_channels = 4 and what stb_image_write wants for comp = 4.  keeping
 * exactly one pixel format means there are no flags to get wrong: nothing in
 * this module can hand back a palette image, a canvas whose alpha won't be
 * written, or a surface that composites differently from the others.
 *
 * the stb implementations are compiled into this translation unit, so there is
 * no library to find, link, or resolve at runtime.
 */

#include <stdlib.h>
#include <string.h>

/* pinned rather than left to the defaults so that one allocator owns every
 * buffer here: a decoded image can then be adopted as-is and released by the
 * same free() as one we allocated ourselves.
 */
#define STBI_MALLOC(sz)         malloc(sz)
#define STBI_REALLOC(p, sz)     realloc(p, sz)
#define STBI_FREE(p)            free(p)

#define STBI_ONLY_PNG               /* the sheets are pngs, as they were under gd */
#define STBI_NO_LINEAR
#define STBI_NO_HDR
#define STB_IMAGE_IMPLEMENTATION
#include "stb/stb_image.h"

#define STBIW_MALLOC(sz)        malloc(sz)
#define STBIW_REALLOC(p, sz)    realloc(p, sz)
#define STBIW_FREE(p)           free(p)

#define STBI_WRITE_NO_STDIO         /* encoded bytes go to lua, never to a FILE* */
#define STB_IMAGE_WRITE_IMPLEMENTATION
#include "stb/stb_image_write.h"

#include <lua.h>
#include <lauxlib.h>

#if defined(_WIN32)
#  if defined(WRAP_STB_IMAGE_BUILD_DLL)
#    define WRAP_STB_IMAGE_API __declspec(dllexport)
#  else
#    define WRAP_STB_IMAGE_API __declspec(dllimport)
#  endif
#else
#  define WRAP_STB_IMAGE_API
#endif

#define IMAGE_MT "stb.image"

/* png itself allows 2^31-1 per side, but nothing here needs a sheet or a page
 * anywhere near that, and a bound this low keeps w * h * 4 from overflowing a
 * 32-bit size_t.
 */
#define MAX_DIM 65535

/* px == NULL means explicitly destroyed, so __gc after destroy() is harmless */
typedef struct {
    unsigned char *px;
    int w, h;
} Image;

static Image *check_image (lua_State *L, int idx)
{
    Image *im = luaL_checkudata(L, idx, IMAGE_MT);
    if (!im->px) luaL_error(L, "stb.image has been destroyed");
    return im;
}

static int check_byte (lua_State *L, int idx)
{
    int v = (int) luaL_checkinteger(L, idx);
    luaL_argcheck(L, v >= 0 && v <= 255, idx, "expected 0..255");
    return v;
}

/* takes ownership of px, which must be w * h * 4 bytes from the allocator above */
static Image *push_image (lua_State *L, unsigned char *px, int w, int h)
{
    Image *im = lua_newuserdata(L, sizeof(Image));

    im->px = px;
    im->w = w;
    im->h = h;
    luaL_setmetatable(L, IMAGE_MT);
    return im;
}

/* pushes the userdata, then allocates: the metatable has to be in place before
 * the malloc can fail, or a failed allocation leaves an unfinalizable object --
 * and with no buffer in flight there is nothing for the raise to leak.
 * the pixels are left uninitialized, so every caller fills all w * h of them.
 */
static Image *new_image (lua_State *L, int w, int h)
{
    Image *im;

    if (w < 1 || h < 1 || w > MAX_DIM || h > MAX_DIM)
        luaL_error(L, "unreasonable image size %dx%d", w, h);

    im = push_image(L, NULL, w, h);
    im->px = malloc((size_t) w * (size_t) h * 4);
    if (!im->px) luaL_error(L, "cannot allocate a %dx%d image", w, h);

    return im;
}

/* create(w, h) clears to transparent; create(w, h, r, g, b) clears to that
 * color, fully opaque.
 */
static int l_create (lua_State *L)
{
    int w = (int) luaL_checkinteger(L, 1);
    int h = (int) luaL_checkinteger(L, 2);
    unsigned char fill[4] = { 0, 0, 0, 0 };
    Image *im;
    size_t i, n;

    luaL_argcheck(L, w >= 1, 1, "width must be >= 1");
    luaL_argcheck(L, h >= 1, 2, "height must be >= 1");

    if (!lua_isnoneornil(L, 3)) {
        fill[0] = (unsigned char) check_byte(L, 3);
        fill[1] = (unsigned char) check_byte(L, 4);
        fill[2] = (unsigned char) check_byte(L, 5);
        fill[3] = 255;
    }

    im = new_image(L, w, h);
    n = (size_t) w * (size_t) h;
    if (fill[0] == fill[1] && fill[1] == fill[2] && fill[2] == fill[3])
        memset(im->px, fill[0], n * 4);         /* covers the transparent case */
    else
        for (i = 0; i < n; i++) memcpy(im->px + i * 4, fill, 4);

    return 1;
}

static int l_load (lua_State *L)
{
    const char *fn = luaL_checkstring(L, 1);
    int w = 0, h = 0, comp = 0;
    unsigned char *px;

    /* asking for 4 channels is what normalizes the input: the glyph sheets are
       gray+alpha, and stb expands them (gray replicated across rgb, alpha kept)
       so a foreign rgb or palette sheet arrives in the same format. */
    px = stbi_load(fn, &w, &h, &comp, 4);
    if (!px) return luaL_error(L, "cannot load '%s': %s", fn,
                               stbi_failure_reason());

    /* the bound is checked here rather than in new_image because the buffer is
       adopted, not copied, so it has to be released before anything is raised */
    if (w > MAX_DIM || h > MAX_DIM) {
        stbi_image_free(px);
        return luaL_error(L, "'%s' is %dx%d, larger than this module handles",
                          fn, w, h);
    }

    push_image(L, px, w, h);
    return 1;
}

static int l_size (lua_State *L)
{
    Image *im = check_image(L, 1);

    lua_pushinteger(L, im->w);
    lua_pushinteger(L, im->h);
    return 2;
}

/* source-over compositing on straight alpha.  blending rather than replacement
 * is what makes overlapping glyph tiles combine instead of erasing each other,
 * and the two short-circuits mean the bilevel sheets never reach the arithmetic.
 */
static void blend (unsigned char *d, const unsigned char *s)
{
    unsigned sa = s[3], da, ra;
    int i;

    if (sa == 0) return;                            /* nothing to draw */
    if (sa == 255 || d[3] == 0) { memcpy(d, s, 4); return; }

    da = d[3];
    /* out_alpha * 255, i.e. 255 * (sa + da * (1 - sa)) with alpha in 0..1 */
    ra = sa * 255u + da * (255u - sa);

    for (i = 0; i < 3; i++)
        d[i] = (unsigned char) ((s[i] * sa * 255u
                                 + d[i] * da * (255u - sa)
                                 + ra / 2) / ra);
    d[3] = (unsigned char) ((ra + 127u) / 255u);
}

static int l_copy (lua_State *L)
{
    Image *dst = check_image(L, 1);
    Image *src = check_image(L, 2);
    int dx = (int) luaL_checkinteger(L, 3);
    int dy = (int) luaL_checkinteger(L, 4);
    int sx = (int) luaL_checkinteger(L, 5);
    int sy = (int) luaL_checkinteger(L, 6);
    int w  = (int) luaL_checkinteger(L, 7);
    int h  = (int) luaL_checkinteger(L, 8);
    int y, x;

    luaL_argcheck(L, w >= 0 && h >= 0, 7, "negative size");

    /* checked before the clipping below, so a tile that names pixels outside the
       sheet is reported rather than silently trimmed */
    luaL_argcheck(L, sx >= 0 && sy >= 0
                  && sx + w <= src->w && sy + h <= src->h,
                  5, "source rect out of bounds");

    /* the destination is clipped instead, which is how a glyph running past the
       right margin is handled */
    if (dx < 0) { sx -= dx; w += dx; dx = 0; }
    if (dy < 0) { sy -= dy; h += dy; dy = 0; }
    if (dx + w > dst->w) w = dst->w - dx;
    if (dy + h > dst->h) h = dst->h - dy;
    if (w <= 0 || h <= 0) return 0;

    for (y = 0; y < h; y++) {
        const unsigned char *sp = src->px + ((size_t) (sy + y) * src->w + sx) * 4;
        unsigned char *dp = dst->px + ((size_t) (dy + y) * dst->w + dx) * 4;

        for (x = 0; x < w; x++, sp += 4, dp += 4) blend(dp, sp);
    }
    return 0;
}

/* out-of-place: alpha comes from the source, rgb from the arguments.  the sheets
 * are white-on-transparent masks, so this is how text gets its color.  doing it
 * once per (sheet, color) beats masking every glyph and leaves the glyph blits
 * as ordinary composites.
 */
static int l_recolor (lua_State *L)
{
    Image *src = check_image(L, 1);
    unsigned char r = (unsigned char) check_byte(L, 2);
    unsigned char g = (unsigned char) check_byte(L, 3);
    unsigned char b = (unsigned char) check_byte(L, 4);
    Image *dst = new_image(L, src->w, src->h);
    size_t i, n = (size_t) src->w * (size_t) src->h;

    for (i = 0; i < n; i++) {
        dst->px[i * 4 + 0] = r;
        dst->px[i * 4 + 1] = g;
        dst->px[i * 4 + 2] = b;
        dst->px[i * 4 + 3] = src->px[i * 4 + 3];
    }
    return 1;
}

/* integer block replication -- nearest neighbour, but computed on exact integers
 * rather than a fixed-point step, so a factor of 3 doesn't drift the sampled
 * column across a wide image the way a truncated 256/3 would.
 */
static int l_scale (lua_State *L)
{
    Image *src = check_image(L, 1);
    int f = (int) luaL_checkinteger(L, 2);
    Image *dst;
    int y, x, dy, dx;

    luaL_argcheck(L, f >= 1, 2, "factor must be >= 1");
    luaL_argcheck(L, f <= MAX_DIM / src->w && f <= MAX_DIM / src->h, 2,
                  "factor too large for this image");

    dst = new_image(L, src->w * f, src->h * f);

    for (y = 0; y < src->h; y++)
        for (x = 0; x < src->w; x++) {
            const unsigned char *sp = src->px + ((size_t) y * src->w + x) * 4;

            for (dy = 0; dy < f; dy++) {
                unsigned char *dp = dst->px
                    + ((size_t) (y * f + dy) * dst->w + (size_t) x * f) * 4;

                for (dx = 0; dx < f; dx++, dp += 4) memcpy(dp, sp, 4);
            }
        }
    return 1;
}

static int l_png_string (lua_State *L)
{
    Image *im = check_image(L, 1);
    int level = (int) luaL_optinteger(L, 2, -1);
    int saved = stbi_write_png_compression_level;
    int len = 0;
    unsigned char *png;

    luaL_argcheck(L, level >= -1 && level <= 9, 2, "level must be -1..9");

    /* -1 keeps stb's own default.  the number is a search effort rather than a
       zlib level -- stb clamps anything under 5 up to 5 internally -- so it only
       ever trades encode time for size, never correctness. */
    if (level >= 0) stbi_write_png_compression_level = level;
    png = stbi_write_png_to_mem(im->px, im->w * 4, im->w, im->h, 4, &len);
    stbi_write_png_compression_level = saved;

    if (!png) return luaL_error(L, "png encoding failed");
    lua_pushlstring(L, (const char *) png, (size_t) len);
    STBIW_FREE(png);
    return 1;
}

static int l_get_pixel (lua_State *L)
{
    Image *im = check_image(L, 1);
    int x = (int) luaL_checkinteger(L, 2);
    int y = (int) luaL_checkinteger(L, 3);
    const unsigned char *p;

    luaL_argcheck(L, x >= 0 && x < im->w, 2, "x out of bounds");
    luaL_argcheck(L, y >= 0 && y < im->h, 3, "y out of bounds");

    p = im->px + ((size_t) y * im->w + x) * 4;

    /* 8-bit throughout, 255 opaque -- the same numbers the png will hold */
    lua_pushinteger(L, p[0]);
    lua_pushinteger(L, p[1]);
    lua_pushinteger(L, p[2]);
    lua_pushinteger(L, p[3]);
    return 4;
}

static int l_destroy (lua_State *L)
{
    Image *im = luaL_checkudata(L, 1, IMAGE_MT);

    free(im->px);
    im->px = NULL;
    return 0;
}

static int l_tostring (lua_State *L)
{
    Image *im = luaL_checkudata(L, 1, IMAGE_MT);

    if (im->px) lua_pushfstring(L, IMAGE_MT ": %dx%d", im->w, im->h);
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

WRAP_STB_IMAGE_API int luaopen_wrap_stb_image (lua_State *L)
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
