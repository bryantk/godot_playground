class_name FadeConstants

## Project-wide defaults for every fade-driven command - [code]fade[/code],
## [code]fade_in[/code], [code]fade_out[/code] (events/commands/presentation_execs.gd),
## and [code]change_map[/code]/[code]change_map_marker[/code]'s own optional fade legs
## (events/commands/map_execs.gd). One place to retune the game's overall fade feel
## rather than a magic number repeated in every command that can fade.

## Seconds a fade takes when a node omits its own - long enough to read as a
## transition, short enough not to stall a map change an author left un-authored.
const DEFAULT_SECONDS := 0.4
