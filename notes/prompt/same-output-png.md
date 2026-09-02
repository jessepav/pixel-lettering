In the text definition file (such as `samples/text-definition.lua`) if the
returned table includes a `config` table, and that table contains a `onefile`
table with `filename` and `margin` fields, then the behavior of the program
changes as so:

1. The `filename` field of each entry in the `passages` table is ignored.

2. Instead, the images generated from each passage are queued up, and when all
   passage images are generated, the program generates one image with these
   characteristics:

   * Its width is the max width of each passage image.
   * Its height is the sum of the passage image heights, with a transparent
     margin between each image. The pixel size of this margin is given by
     `config.onefile.margin`.

3. The resulting joined image is written to `config.onefile.filename`.

Resolve any ambiguities with me before beginning work.
