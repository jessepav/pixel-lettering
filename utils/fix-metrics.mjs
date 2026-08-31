import * as fs from 'node:fs';

const jsonFiles = fs.globSync("**/*.json");

for (const fn of jsonFiles) {
    const outFn = fn.slice(0, -5) + "-metrics.json";
    if (fn.includes("-metrics.json") || fs.existsSync(outFn))
        continue;  // we've already done it
    const metrics = JSON.parse(fs.readFileSync(fn, { encoding: 'utf8' }));
    delete metrics.kerning;   // we don't need none of that! Do we?
    const { cols, tile_w, tile_h, glyphs } = metrics;
    let col = 0, row = 0;
    for (const glyph of glyphs) {
        glyph.tile_x = col * tile_w;
        glyph.tile_y = row * tile_h;
        if (++col == cols) {
            row++;
            col = 0;
        }
    }
    fs.writeFileSync(outFn, JSON.stringify(metrics, null, 2));
    console.log(`Wrote ${outFn}`);
}
