#!/usr/bin/env lua5.3

local lfs = require "lfs"
local json = require "dkjson"

-- dkjson.encode's keyorder applies to every object it emits, and the
-- top-level and per-glyph key sets are disjoint, so one flat list orders both.
-- Any key not named here is emitted after these, in unspecified order.
local KEY_ORDER = {
    "cols", "rows", "tile_w", "tile_h", "baseline", "line_gap", "space_w",
    "glyphs", "chr", "lsb", "adv", "tile_x", "tile_y",
}

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
        io.stderr:write(string.format("%s: %s: not a directory\n", PROG, root))
        os.exit(1)
    end

    for _, fn in ipairs(find_json_files(root, {})) do
        -- Skip the ones we've written ourselves.
        if fn:sub(-13) == "-metrics.json" then goto continue end

        local out_fn = fn:sub(1, -6) .. "-metrics.json"
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

        local encoded = json.encode(metrics, { indent = true, keyorder = KEY_ORDER })
        f = io.open(out_fn, "wb")
        f:write(encoded)
        f:close();

        print("Wrote " .. out_fn)
        ::continue::
    end  -- end for _, fn
end

main()
