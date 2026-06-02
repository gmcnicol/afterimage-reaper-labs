# Minimal Substrate Archive

This fixture is the smallest source-first archive shape currently expected by the Reaper lab importer.

## Contract

- `manifest.lua` returns one Lua table.
- `archive.id` identifies the archive.
- `source.file` identifies the one primary source video.
- `grid.seconds` can override the current Reaper project grid for local analysis.
- `overlays`, `masks`, and `reference_audio` are optional supporting media lists.
- Supporting media files are relative to the archive folder unless absolute.
- `analysis.cuts_file` is optional. If omitted, the importer runs FFmpeg scene detection at threshold `0.30`.
- If FFmpeg detects no scene changes, the source is treated as one full-length scene.
- Generated analysis is written to `analysis/generated-lab001.lua`.

## Standard track names

- `AfImg Source`
- `AfImg Overlays`
- `AfImg Masks`
- `AfImg Reference Audio`

The importer places the source once, places optional supporting media at their explicit start times, and mirrors scenes/grid cuts into Reaper regions and markers for inspection.
