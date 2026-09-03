#!/usr/bin/env lua5.3

local lfs     = require "lfs"
local serpent = require "serpent"

-- METRICS_TEMPLATE {{{

local METRICS_TEMPLATE = [==[
return {
    --
    -- Edit the below values to suit your glyph atlas
    --
    cols = 10,  -- the number of columns in your atlas
    rows = 12,  -- the number of rows in your atlas
    tile_w = 8,  -- the width of a tile
    tile_h = 13, -- the height of a tile
    baseline = 12, -- the y-coordinate in a tile of the baseline
    line_gap = 0,  -- gap between adjacent text lines
    space_w = 3,   -- width of the space character

    -- Fill in glyphstr with the characters in your glyph atlas,
    -- in row-major order starting at the *second* tile: the first
    -- tile, at the top-left of the atlas, will have chr == "\0"
    -- and be used to represent characters in the input text that
    -- have no matching glyph in your atlas.
    --
    -- Once you run gen-metrics.lua on this file, it will convert
    -- your glyphstr into a glyphs array, as below.
    --
    -- Here is an example glyphstr with 94 printable ASCII characters.
    -- (the space character is omitted, since it's represented by space_w)
    glyphstr = [[!"#$%&'()*+,-./]] ..
               [[0123456789]] .. [[:;<=>?@]] ..
               [[ABCDEFGHIJKLMNOPQRSTUVWXYZ]] ..
               [[[\]^_`]] ..
               [[abcdefghijklmnopqrstuvwxyz{|}~]],

    --[[
    glyphs = {
        {
            chr = "\0", -- the UTF-8 character represented by this glyph
            lsb = 0,    -- left side bearing
            adv = 8,    -- advance width
            tile_x = 0, -- x-coord of the top-left of the glyph tile
            tile_y = 0  -- y-coord of the top-left of the glyph tile
        }
    }
    ]]
}
]==]

-- }}}

local KEY_ORDER = {
    "cols", "rows", "tile_w", "tile_h", "baseline", "line_gap", "space_w",
    "glyphstr", "glyphs", "chr", "lsb", "adv", "tile_x", "tile_y",
}

local KEY_RANK = {}
for i, k in ipairs(KEY_ORDER) do KEY_RANK[k] = i end

local function sort_keys (keys, tbl)  -- tbl is unused
    table.sort(keys, function (a, b)
        local ra, rb = KEY_RANK[a], KEY_RANK[b]
        if ra and rb then return ra < rb end
        if ra or rb then return ra ~= nil end   -- the named ones come first
        return tostring(a) < tostring(b)        -- the rest, alphabetically
    end)
end

local function main()
    local metrics_file = arg[1]
    if not metrics_file or #metrics_file == 0 or
           metrics_file == "-h" or metrics_file == "--help" then
        print("Usage: gen-metrics.lua metrics-file.lua [output-metrics-file.lua]")
        return
    end

    local filemode = lfs.attributes(metrics_file, "mode")
    if filemode == nil then
        local file = io.open(metrics_file, "wb")
        file:write(METRICS_TEMPLATE)
        file:close()
        print("Created " .. metrics_file)
    elseif filemode ~= "file" then
        print(string.format("%s is not a file!", metrics_file))
        return
    else  -- the file exists: read it
        local out_fn = arg[2] or metrics_file:sub(1, -5) .. "-glyphs.lua"
        local metrics = dofile(metrics_file)
        local glyphstr = metrics.glyphstr
        metrics.glyphstr = nil
        if not glyphstr then
            print(metrics_file .. " has no glyphstr field")
            return
        end
        local cols, rows, tile_w, tile_h = metrics.cols, metrics.rows, metrics.tile_w, metrics.tile_h
        metrics.glyphs = {}
        local glyphs = metrics.glyphs
        table.insert(glyphs, {
            chr = "\0",
            lsb = 0,
            adv = tile_w,
            tile_x = 0,
            tile_y = 0
        })
        local col, row = 1, 0
        for chr in glyphstr:gmatch(utf8.charpattern) do
            if col == cols then col, row = 0, row + 1 end
            table.insert(glyphs, {
                chr = chr,
                lsb = 0,
                adv = tile_w,
                tile_x = col * tile_w,
                tile_y = row * tile_h
            })
            col = col + 1
        end
        if row >= rows then
            print(string.rep("-", 60))
            print(string.format(
                "Warning: the number of rows needed to store glyphs (%d)\n" ..
                "         exceeds the rows given in %s (%d)",
                row, metrics_file, rows
            ))
            print(string.rep("-", 60))
        end

        local encoded = serpent.block(metrics, {
            comment = false, sortkeys = sort_keys, indent = "  ",
        })
        f = io.open(out_fn, "wb")
        f:write("return ", encoded, "\n")
        f:close()
        print(string.format("Wrote %s with %d glyphs", out_fn, #glyphs))
    end
end

main()
