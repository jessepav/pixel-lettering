return {
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
    }
  }
}
