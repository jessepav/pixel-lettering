#!/usr/bin/env lua5.3

local gdlib = require "gdlib"

local STYLES = { "regular", "bold", "italic" }
local MARKER = { ["**"] = "bold", ["*"] = "italic", ["_"] = "italic" }

-- line-break sentinel.  safe because no sheet has a glyph below 0x21.
local BREAK = "\1"
local BLANK = "[%s" .. BREAK .. "]"

--------------------------------------------------------------------------------
-- Paths -- everything in a definition file is relative to the file itself
--------------------------------------------------------------------------------

local function dirname (path)
    return path:match("^(.*)/[^/]*$") or "."
end

local function resolve (base, path)
    if path:sub(1, 1) == "/" then return path end
    return base .. "/" .. path
end

--------------------------------------------------------------------------------
-- Fonts
--------------------------------------------------------------------------------

local function load_font (base, fdef)
    local metrics = dofile(resolve(base, fdef.metrics))

    -- glyph 1 is the notdef slot (its chr is "\0"), so it never goes in the index
    local index = {}
    for i = 2, #metrics.glyphs do
        local g = metrics.glyphs[i]
        index[g.chr] = g
    end

    return { image    = gdlib.load(resolve(base, fdef.sheet)),
             metrics  = metrics,
             index    = index,
             notdef   = metrics.glyphs[1],
             line_gap = fdef.line_gap or metrics.line_gap,
             color    = fdef.color,
             sheets   = {} }
end

local function load_fonts (base, fdefs)
    local fonts = {}
    for _, style in ipairs(STYLES) do
        if fdefs[style] then fonts[style] = load_font(base, fdefs[style]) end
    end
    return fonts
end

-- one set of line metrics for the whole passage, taken over every font defined
-- rather than the ones a line happens to use.  because ascent is the max of the
-- baselines, ascent - font.baseline is never negative, so nothing is pushed off
-- the top; and each tile's bottom lands exactly on ascent + descent.
--
-- font_gap only maxes the font-level gaps.  the passage-level one is applied in
-- do_passage as an outright override, never folded in here.
local function vertical_metrics (fonts)
    local ascent, descent, font_gap = 0, 0, -math.huge

    for _, style in ipairs(STYLES) do
        local f = fonts[style]
        if f then
            local m = f.metrics
            ascent   = math.max(ascent,   m.baseline)
            descent  = math.max(descent,  m.tile_h - m.baseline)
            font_gap = math.max(font_gap, f.line_gap)
        end
    end

    return { ascent      = ascent,
             descent     = descent,
             line_height = ascent + descent,
             font_gap    = font_gap }
end

-- recolor per sheet, not per glyph: one pass over the whole sheet beats masking
-- every tile, and it leaves the glyph blits as plain copies
local function sheet_for (font, r, g, b)
    local key = ("%d,%d,%d"):format(r, g, b)
    local sheet = font.sheets[key]

    if not sheet then
        sheet = font.image:recolor(r, g, b)
        font.sheets[key] = sheet
    end
    return sheet
end

--------------------------------------------------------------------------------
-- The markdown subset
--------------------------------------------------------------------------------

local function preprocess (text)
    local t = text:gsub("\r\n", "\n")
    t = t:gsub("^%s+", ""):gsub("%s+$", "")
    t = t:gsub("[ \t]*\n[ \t]*", "\n")

    -- must come before lone newlines turn into spaces: the rule above already
    -- ate the surrounding spaces, so a surviving \<newline> would collapse to
    -- backslash-space and the break would be lost
    t = t:gsub("\\\n", BREAK)

    t = t:gsub("\n+", function (nl)
        return #nl == 1 and " " or BREAK .. BREAK   -- 2+ means a blank line
    end)

    return (t:gsub("  +", " "))
end

-- flanking rules, commonmark style.  they're not optional: the sample's own
-- prose ("a backslash before * or _ removes its special meaning") would
-- otherwise open two italic spans that never close, swallowing both characters
-- and italicizing everything after them.
local function scan_delims (s)
    local delims, i = {}, 1

    while i <= #s do
        local c = s:sub(i, i)

        if c == "\\" and s:sub(i + 1, i + 1):match("^[%*_]") then
            i = i + 2                       -- escaped, so not a delimiter at all
        elseif c == "*" or c == "_" then
            local run = s:match(c == "*" and "^%*+" or "^_+", i)
            local mk = (c == "*" and #run >= 2) and "**" or c
            local before = i > 1 and s:sub(i - 1, i - 1) or " "
            local after = s:sub(i + #mk, i + #mk)
            if after == "" then after = " " end

            delims[#delims + 1] = {
                pos       = i,
                mk        = mk,
                can_open  = not after:match(BLANK),
                can_close = not before:match(BLANK),
            }
            i = i + #mk
        else
            i = i + 1
        end
    end

    return delims
end

-- second pass, so an opener that never finds a partner stays out of the map and
-- gets emitted as a literal instead of leaking its style to end of passage
local function match_delims (delims)
    local span, stack = {}, {}

    for k, d in ipairs(delims) do
        local top = stack[#stack]

        if d.can_close and top and delims[top].mk == d.mk then
            span[delims[top].pos] = { mk = d.mk, open = true }
            span[d.pos] = { mk = d.mk, open = false }
            stack[#stack] = nil
        elseif d.can_open then
            stack[#stack + 1] = k
        end
    end

    return span
end

local function parse_inline (s)
    local span = match_delims(scan_delims(s))
    local atoms, stack, i = {}, {}, 1

    -- the innermost open marker wins, which is what makes **bold _and italic_**
    -- resolve to italic -- there's no sheet for the combination
    local function style ()
        return MARKER[stack[#stack]] or "regular"
    end

    while i <= #s do
        local c = s:sub(i, i)
        local d = span[i]

        if c == "\\" and s:sub(i + 1, i + 1):match("^[%*_]") then
            atoms[#atoms + 1] = { c = s:sub(i + 1, i + 1), st = style() }
            i = i + 2
        elseif d then
            if d.open then stack[#stack + 1] = d.mk else stack[#stack] = nil end
            i = i + #d.mk
        elseif c == BREAK then
            atoms[#atoms + 1] = { brk = true }
            i = i + 1
        elseif c == " " then
            atoms[#atoms + 1] = { sp = true, st = style() }
            i = i + 1
        else
            local j = utf8.offset(s, 2, i) or (#s + 1)
            atoms[#atoms + 1] = { c = s:sub(i, j - 1), st = style() }
            i = j
        end
    end

    return atoms
end

--------------------------------------------------------------------------------
-- Shaping and wrapping
--------------------------------------------------------------------------------

local function shape (atoms, fonts, warned)
    local tokens, word = {}, nil

    local function flush ()
        if word then
            tokens[#tokens + 1] = word
            word = nil
        end
    end

    for _, a in ipairs(atoms) do
        -- one lookup covers both a missing bold/italic sheet and the
        -- bold-inside-italic case, which has no sheet of its own either
        local font = fonts[a.st] or fonts.regular

        if a.brk then
            flush()
            tokens[#tokens + 1] = { brk = true }
        elseif a.sp then
            flush()
            tokens[#tokens + 1] = { sp = true, w = font.metrics.space_w }
        else
            local glyph = font.index[a.c]
            if not glyph then
                if not warned[a.c] then
                    warned[a.c] = true
                    io.stderr:write(("lettering: no glyph for %q\n"):format(a.c))
                end
                glyph = font.notdef
            end

            -- characters coalesce into a word across style changes, so
            -- **bold**word stays one unbreakable unit
            word = word or { glyphs = {}, w = 0 }
            word.glyphs[#word.glyphs + 1] = { g = glyph, f = font }
            word.w = word.w + glyph.adv
        end
    end

    flush()
    return tokens
end

local function wrap (tokens, width)
    local lines, cur, pending = {}, { p = {}, w = 0 }, 0

    local function emit ()
        lines[#lines + 1] = cur
        cur, pending = { p = {}, w = 0 }, 0
    end

    -- lsb shifts the tile within the advance; only adv moves the pen
    local function place (gg)
        cur.p[#cur.p + 1] = { x = cur.w + gg.g.lsb, gg = gg }
        cur.w = cur.w + gg.g.adv
    end

    for _, t in ipairs(tokens) do
        if t.brk then
            emit()          -- fires on an empty line too, which is how a
                            -- paragraph's two breaks produce a blank line
        elseif t.sp then
            -- a leading space is dropped, a trailing one dies with the emit
            if cur.w > 0 then pending = t.w end
        else
            if cur.w > 0 and cur.w + pending + t.w > width then emit() end

            if t.w > width then
                -- wider than the column however we break it, so break at the
                -- last glyph that fits.  the cur.w > 0 test doubles as the
                -- infinite-loop guard: a single oversized glyph is placed and
                -- clipped rather than retried forever.
                for _, gg in ipairs(t.glyphs) do
                    if cur.w > 0 and cur.w + gg.g.adv > width then emit() end
                    place(gg)
                end
            else
                cur.w = cur.w + pending
                pending = 0
                for _, gg in ipairs(t.glyphs) do place(gg) end
            end
        end
    end

    -- the #lines test keeps an empty passage from asking for a zero-high canvas
    if cur.w > 0 or #lines == 0 then emit() end
    return lines
end

--------------------------------------------------------------------------------
-- Output
--------------------------------------------------------------------------------

local function render (lines, width, vm, gap, sheets)
    local n = #lines
    local height = math.max(1, n * vm.line_height + (n - 1) * gap)
    local canvas = gdlib.create(width, height)

    for i, line in ipairs(lines) do
        local top = (i - 1) * (vm.line_height + gap)

        for _, pl in ipairs(line.p) do
            local g, f = pl.gg.g, pl.gg.f
            local m = f.metrics

            -- ascent - baseline puts each glyph's own baseline row on the
            -- line's shared baseline, whatever font it came from
            canvas:copy(sheets[f], pl.x, top + vm.ascent - m.baseline,
                        g.tile_x, g.tile_y, m.tile_w, m.tile_h)
        end
    end

    return canvas
end

local function do_passage (passage, base, fonts, vm, warned)
    local sheets = {}
    for _, style in ipairs(STYLES) do
        local f = fonts[style]
        if f then
            -- a font's color is only a default; the passage overrides it, the
            -- same way it overrides line_gap
            sheets[f] = sheet_for(f, gdlib.parse_color(passage.color or f.color))
        end
    end

    local tokens = shape(parse_inline(preprocess(passage.text)), fonts, warned)
    local lines = wrap(tokens, passage.width)

    -- used exactly as given; only the font-level gaps went through the max
    local gap = passage.line_gap or vm.font_gap

    local im = render(lines, passage.width, vm, gap, sheets)
    if passage.scale and passage.scale > 1 then im = im:scale(passage.scale) end

    gdlib.write_png(im, resolve(base, passage.filename))
end

local function main ()
    if #arg == 0 then
        io.stderr:write("usage: lettering DEFINITION.lua ...\n")
        os.exit(1)
    end

    for _, path in ipairs(arg) do
        local base = dirname(path)
        local def = dofile(path)
        local fonts = load_fonts(base, def.fonts)
        local vm = vertical_metrics(fonts)
        local warned = {}   -- one table per run, so each miss warns just once

        for _, passage in ipairs(def.passages) do
            do_passage(passage, base, fonts, vm, warned)
        end
    end
end

main()
