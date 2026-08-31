I want to convert `utils/fix-metrics.mjs` from JavaScript to Lua 5.3. Through
LuaRocks, our Lua 5.3 environment has these packages installed and available for
use:

* cmark
* dkjson
* inspect
* ldoc
* lpeg
* lrexlib-pcre2
* lsqlite3
* lua-cjson
* luaexpat
* luafilesystem
* luaposix
* lustache
* markdown
* penlight
* serpent

The `**` glob syntax used in `utils/fix-metrics.mjs` is not available through
the listed Lua packages, so please implement your own recursive discovery of
JSON files using the features available through `luafilesystem`.

Write the converted script to `utils/fix-metrics.lua`.

If there are any ambiguities you need to resolve, ask me first.
