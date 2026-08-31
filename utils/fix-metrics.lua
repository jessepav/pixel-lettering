#!/usr/bin/env lua5.3

local lfs     = require "lfs"
local json    = require "dkjson"   -- the inputs are still JSON
local serpent = require "serpent"

-- serpent sorts keys alphanumerically unless we say otherwise, and the
-- top-level and per-glyph key sets are disjoint, so one flat list orders both.
-- Any key not named here is emitted after these, in alphabetical order.
local KEY_ORDER = {
    "cols", "rows", "tile_w", "tile_h", "baseline", "line_gap", "space_w",
    "glyphs", "chr", "lsb", "adv", "tile_x", "tile_y",
}

local KEY_RANK = {}
for i, k in ipairs(KEY_ORDER) do KEY_RANK[k] = i end

-- serpent hands us (keys, tbl) and wants `keys` sorted in place.  It only
-- bothers for keys outside a table's array part, so `glyphs` keeps its order.
local function sort_keys (keys, tbl)  -- tbl is unused
    table.sort(keys, function (a, b)
        local ra, rb = KEY_RANK[a], KEY_RANK[b]
        if ra and rb then return ra < rb end
        if ra or rb then return ra ~= nil end   -- the named ones come first
        return tostring(a) < tostring(b)        -- the rest, alphabetically
    end)
end

--------------------------------------------------------------------------------
-- find_json_files(): a recursive stand-in for fs.globSync("**/*.json")
--------------------------------------------------------------------------------

local function find_json_files (dir, found)
    local names = {}
    for name in lfs.dir(dir) do
        if name ~= "." and name ~= ".." and name:sub(1, 1) ~= "." then
            names[#names + 1] = name
        end
    end
    table.sort(names)   -- reproducible order, whatever the directory hands us

    for _, name in ipairs(names) do
        local path = dir == "." and name or dir .. "/" .. name
        local mode = lfs.symlinkattributes(path, "mode")
        if mode == "directory" then
            find_json_files(path, found)
        elseif mode == "file" and name:sub(-5) == ".json" then
            found[#found + 1] = path
        end
    end
    return found
end

--------------------------------------------------------------------------------
-- Main
--------------------------------------------------------------------------------

local function main()
    local root = arg[1] or "."
    if root:sub(-1) == "/" then root = root:sub(1, -2) end

    if lfs.attributes(root, "mode") ~= "directory" then
        io.stderr:write(string.format("%s: not a directory\n", root))
        os.exit(1)
    end

    for _, fn in ipairs(find_json_files(root, {})) do
        local out_fn = fn:sub(1, -6) .. "-metrics.lua"
        if lfs.attributes(out_fn, "mode") then goto continue end  -- already done

        local f = io.open(fn, "rb")
        local text = f:read("a")
        f:close()

        local metrics = json.decode(text)
        metrics.kerning = nil   -- we don't need no kerning...do we?
        local col, row = 0, 0
        for _, glyph in ipairs(metrics.glyphs) do
            glyph.tile_x = col * metrics.tile_w
            glyph.tile_y = row * metrics.tile_h
            col = col + 1
            if col == metrics.cols then row, col = row + 1, 0 end
        end

        local encoded = serpent.block(metrics, {
            comment = false, sortkeys = sort_keys, indent = "    ",
        })
        f = io.open(out_fn, "wb")
        f:write(encoded, "\n")
        f:close();

        print("Wrote " .. out_fn)
        ::continue::
    end  -- end for _, fn
end

main()
