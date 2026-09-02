return {
  -- with a config.onefile table, the passage filenames below are ignored and
  -- every passage image instead becomes a row of one image, written here.  the
  -- rows are as wide as the widest of them, each placed according to its own
  -- `align`, and `margin` pixels separate the rows and surround the whole
  -- image.  that surround is transparent unless `bgcolor` is given, which fills
  -- it (and any space beside a narrower row) instead.  remove this table to get
  -- one file per passage again.
  config = {
    onefile = {
      filename = "joined.png",
      margin = 20,
      -- bgcolor = "#000",
    }
  },

  fonts = {
    regular = { metrics = "../pixel-lettering-font-sheets/summit/summit-metrics.lua",
                sheet   = "../pixel-lettering-font-sheets/summit/summit.png" },
    bold = { metrics = "../pixel-lettering-font-sheets/summit/summit_bold-metrics.lua",
             sheet   = "../pixel-lettering-font-sheets/summit/summit_bold.png",
             line_gap = 5 },
    italic = { metrics = "../pixel-lettering-font-sheets/summit/summit_italic-metrics.lua",
               sheet   = "../pixel-lettering-font-sheets/summit/summit_italic.png",
               color   = "#3333FF" },
  },

  passages = {
    {
      width = 400,
      filename = "passage1.png",
      scale = 2,
      bgcolor = "#eeeeee",  -- if not given, background will be transparent
      padding = 5,  -- pixels padding on all sides,
      align = "left",  -- "left" (default), "center", or "right"
      text = [[
        Passage text is written in a small subset of Markdown. The only 
        supported formatting is *word* or _word_ for italic, and **word**
        for bold. A backslash before *, _, or another backslash removes
        its special meaning, and may be used to insert the \_literal\_
        \*characters\*. Two backslashes, \\\\, yield a single \\.

        A blank line, as above, separates paragraphs (i.e. represents two
        newlines in the output).

        A backslash at the end of a line\
        represents one newline in the output.

        Before processing passage text, whitespace is trimmed from the start and
        end of the passage; then spaces following or preceding a newline are
        removed; then single newlines (that is, not the 2+ newlines that
        represent a paragraph break) are converted to spaces; then multiple
        spaces are collapsed to a single space.
      ]]
    },
    {
      width = 400,
      filename = "passage2.png",
      scale = 1,
      color = { 0x12, 0xFF, 0x12 },
      text = [[
        Another passage. What happens if text is *italic* here?
      ]]
    },
    {
      width = 600,
      -- filename = "earthbound.png",
      scale = 1,
      bgcolor = "#000000",
      color = "#FFF",
      padding = 20,
      text = [[
I started investigating Earthbound in earnest after completing Undertale and finding
great inspiration in its simple aesthetic, contemplative mood, melancholy music, and
quirky humor---basically, its artistic vision. I thought of it as a game of a type that I
could indeed create.

Toby Fox was a huge Earthbound fan in his youth:

*"EarthBound dominated my childhold (sic), shaped my preteen years, and played a large role
in molding me into the offbeat pseudohippie I am today. It gave me a sense of humor. It
helped me learn how to read. Its lessons served as a basis for my sense of justice and
courage."*

This quote was taken from a retrospective of his prominent ROM-hack ("Radiation's
Halloween Hack").

From the above page, I see that his ROM hack was a **serious** project: he created
assets, planned and wrote the story, and drew on significant previous experience with
ROM-editing tools to hack everything together. Writing that Earthbound hack prepared him
for Undertale.
      ]]
    }
  }
}
