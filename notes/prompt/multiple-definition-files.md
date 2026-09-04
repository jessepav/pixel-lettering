I want to make this change to `src/lettering.lua`:

Instead of only one text definition file provided on the command-line, the user
may provide two. From the first file, the program loads the `config` and `fonts`
tables of the configuration, and from the second it loads the `passages`. If the
first file has `passages` defined, they are ignored; and if the second has
`config` or `fonts` defined, they are ignored.

Ask any questions needed to resolve ambiguities before beginning.
