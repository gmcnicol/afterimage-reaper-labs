# Scripts

ReaScripts and supporting Lua modules live here.

## Import Afterimage Archive

Run `scripts/import_afterimage_archive.lua` from REAPER's Action List.

The script prompts for an archive folder containing `manifest.lua`, validates source files, creates LAB-001-owned lab tracks, inserts the primary source plus optional overlay/mask/reference media, and adds scene/grid-cut markers.

If `analysis.cuts_file` is omitted, the importer shells out to `ffprobe` for source duration and `ffmpeg` for scene detection. Generated analysis is written to `analysis/generated-lab001.lua` inside the archive folder.

Reruns only delete material previously marked as LAB-001-generated: owned tracks via Reaper track ext state, and prefixed scene/grid-cut markers when the project ext state records generated markers.

Run local validation outside REAPER with:

```sh
lua scripts/test_afterimage_archive.lua
```
