local C = require "wrap_stb_image"

-- anything not defined here falls through to the c module, so adding a binding
-- needs no edit on this side
local M = setmetatable({}, { __index = C })

-- the glyph sheets are white-on-transparent masks, so a color is just the rgb
-- the mask gets stamped with.  accepts "#rrggbb", "#rgb", {r, g, b}, or nil for
-- the default, black.
function M.parse_color (v)
    if v == nil then return 0, 0, 0 end
    if type(v) == "table" then return v[1], v[2], v[3] end

    local hex = v:match("^#(%x%x%x%x%x%x)$")
    if hex then
        return tonumber(hex:sub(1, 2), 16),
               tonumber(hex:sub(3, 4), 16),
               tonumber(hex:sub(5, 6), 16)
    end

    hex = v:match("^#(%x%x%x)$")
    if hex then
        local function dup (i)
            local d = hex:sub(i, i)
            return tonumber(d .. d, 16)
        end
        return dup(1), dup(2), dup(3)
    end

    -- without this you'd get "number expected, got nil" from deep inside the
    -- recolor binding instead of the actual problem
    error(("cannot parse color %q"):format(v))
end

function M.write_png (im, path, level)
    local f = assert(io.open(path, "wb"))
    f:write(im:png_string(level))
    f:close()
end

return M
