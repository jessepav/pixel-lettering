#!/usr/bin/env lua5.3
--
-- fix-metrics.lua -- derive <font>-metrics.json from <font>.json
--
-- Walks a directory tree looking for spritesheet descriptors, drops the
-- kerning table, and gives every glyph the tile_x/tile_y coordinates implied
-- by its position in the sheet grid.  A port of fix-metrics.mjs.
--
-- Usage: fix-metrics.lua [directory]     -- directory defaults to .
--
-- Files that already have a -metrics.json sibling are left alone, so reruns
-- are cheap.  Files that don't parse, or that aren't sheet descriptors at all,
-- are reported on stderr and skipped; the exit status is 1 if any were.

local lfs = require "lfs"
local json = require "dkjson"

local PROG = "fix-metrics"

-- dkjson.encode's keyorder applies to every object it emits, and the
-- top-level and per-glyph key sets are disjoint, so one flat list orders both.
-- Any key not named here is emitted after these, in unspecified order.
local KEY_ORDER = {
    "cols", "rows", "tile_w", "tile_h", "baseline", "line_gap", "space_w",
    "glyphs", "chr", "lsb", "adv", "tile_x", "tile_y",
}

local skipped = 0

local function skip(fmt, ...)
    io.stderr:write(string.format("%s: " .. fmt .. "\n", PROG, ...))
    skipped = skipped + 1
end

--------------------------------------------------------------------------------
-- Discovery: a recursive stand-in for fs.globSync("**/*.json")
--------------------------------------------------------------------------------

-- Paths double as the names we print, so a "." root is elided the way the
-- glob's cwd-relative results were.
local function join (dir, name)
    if dir == "." then return name end
    return dir .. "/" .. name
end

-- Like glob's defaults, dot-entries are ignored (which keeps us out of .git)
-- and symlinked directories are not descended into -- hence symlinkattributes
-- rather than attributes, since a symlink reports a mode of "link".
local function find_json_files (dir, found)
    local names = {}
    for name in lfs.dir(dir) do
        if name ~= "." and name ~= ".." and name:sub(1, 1) ~= "." then
            names[#names + 1] = name
        end
    end
    table.sort(names)   -- reproducible order, whatever the directory hands us

    for _, name in ipairs(names) do
        local path = join(dir, name)
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
-- File I/O
--------------------------------------------------------------------------------

local function read_file (path)
    local f, err = io.open(path, "rb")
    if not f then return nil, err end
    local data = f:read("a")
    f:close()
    if not data then return nil, path .. ": read failed" end
    return data
end

local function write_file (path, data)
    local f, err = io.open(path, "wb")
    if not f then return nil, err end
    local ok, werr = f:write(data)
    if not ok then f:close() return nil, werr end
    return f:close()
end

--------------------------------------------------------------------------------
-- Main
--------------------------------------------------------------------------------

local root = arg[1] or "."
if #root > 1 then root = (root:gsub("/+$", "")) end
if root == "" then root = "/" end

-- attributes, not symlinkattributes: a symlinked root is fine to walk, it's
-- only symlinks found *along the way* that we decline to follow.
if lfs.attributes(root, "mode") ~= "directory" then
    io.stderr:write(string.format("%s: %s: not a directory\n", PROG, root))
    os.exit(1)
end

for _, fn in ipairs(find_json_files(root, {})) do
    -- Skip the ones we've written ourselves.
    if fn:sub(-13) == "-metrics.json" then goto continue end

    local out_fn = fn:sub(1, -6) .. "-metrics.json"
    if lfs.attributes(out_fn, "mode") then goto continue end  -- already done

    local text, read_err = read_file(fn)
    if not text then
        skip("%s", read_err)
        goto continue
    end

    local metrics, _, json_err = json.decode(text)
    if not metrics then
        skip("%s: %s", fn, json_err or "invalid JSON")
        goto continue
    end

    if type(metrics) ~= "table" or type(metrics.glyphs) ~= "table"
        or type(metrics.cols) ~= "number"
        or type(metrics.tile_w) ~= "number"
        or type(metrics.tile_h) ~= "number" then
        skip("%s: not a font sheet descriptor; skipping", fn)
        goto continue
    end

    metrics.kerning = nil   -- we don't need none of that!  Do we?

    local col, row = 0, 0
    for _, glyph in ipairs(metrics.glyphs) do
        glyph.tile_x = col * metrics.tile_w
        glyph.tile_y = row * metrics.tile_h
        col = col + 1
        if col == metrics.cols then row, col = row + 1, 0 end
    end

    local encoded, encode_err =
        json.encode(metrics, { indent = true, keyorder = KEY_ORDER })
    if not encoded then
        skip("%s: %s", fn, encode_err or "could not be encoded")
        goto continue
    end

    local wrote, write_err = write_file(out_fn, encoded)
    if not wrote then
        skip("%s: %s", out_fn, write_err)
        goto continue
    end

    print("Wrote " .. out_fn)
    ::continue::
end

if skipped > 0 then os.exit(1) end
