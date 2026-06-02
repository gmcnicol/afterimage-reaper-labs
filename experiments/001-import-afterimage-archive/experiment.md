# 001 Import Afterimage Archive

## Hypothesis

A source-first Lua archive manifest is enough for Reaper Labs to create a useful analysis substrate: one primary source video, optional supporting media, generated or provided scene/cut analysis, and inspectable Reaper tracks/markers that can be rebuilt without touching unrelated project material.

## Prototype

- `fixtures/archives/minimal-substrate/manifest.lua` defines the LAB-001 source-first contract.
- `scripts/afterimage_archive.lua` validates manifests, loads provided analysis, generates FFmpeg scene fallback analysis, subdivides scenes into grid cuts, and produces an import plan.
- `scripts/import_afterimage_archive.lua` runs inside REAPER, reads the current project grid when the manifest has no grid override, creates AfImg-owned tracks, inserts source/supporting media, and mirrors scenes/cuts into regions/markers.
- Generated analysis is written to `analysis/generated-lab001.lua` inside the archive folder.

## Evidence

- Manifest validation checks archive metadata, `source.file`, optional supporting media, grid overrides, missing files, provided analysis, scene ranges, and cut ranges.
- FFmpeg fallback uses scene threshold `0.30`.
- The minimal fixture has no provided cuts; local analysis generated one full-source fallback scene and four 0.5s grid cuts.
- Generated analysis records method, source duration, grid metadata, true source ranges, and suggested project-grid ranges.
- `lua scripts/test_afterimage_archive.lua` passes:
  - source-first fixture loads.
  - provided analysis files validate and preserve cuts.
  - missing source video gives a specific `source.file missing` error.
  - malformed analysis gives a specific source range error.
  - omitted manifest grid can use supplied project tempo/grid context.
- `luac -p` parses the importer, archive module, test harness, fixture manifest, and generated analysis successfully.

## Render or Capture Status

No Reaper render or screen capture yet.

## Control Feel

Not tested yet inside REAPER on this machine. There is no local `reaper` binary available in the shell environment.

## Decision

Keep as Reaper-only lab substrate for now.

The source-first contract is a better fit than the old flat `tracks[].items[]` prototype because it preserves source truth while making scene/grid-cut hypotheses inspectable.

LAB-001 should not graduate into Afterimage core yet. It still needs a manual Reaper acceptance pass to confirm track ownership cleanup, marker/region cleanup, media placement, and grid behavior in a real project.

## Current Contract

- `manifest.lua` returns a Lua table.
- `archive.id` identifies the archive.
- `source.file` points to one primary source video.
- `grid.seconds` is optional; when omitted, the Reaper script uses the current project tempo/grid.
- `analysis.cuts_file` is optional; when omitted, FFmpeg scene detection generates `analysis/generated-lab001.lua`.
- If no scene boundaries are detected, the full source duration becomes one scene.
- `overlays`, `masks`, and `reference_audio` are optional supporting media lists.
- Source timing is preserved; grid ranges are sequencing suggestions only.

## Graduation Target

This informs the future Afterimage archive/export contract and gives later Reaper field experiments a source/cut substrate to target.

## Open Questions

- Should generated analysis remain a Lua table for labs, or should it move toward the eventual product archive format?
- Should source cut regions become actual sliced media items in a later experiment, or are markers enough for early field/automation work?
- How should variable-tempo Reaper projects influence grid suggestions beyond the v1 single-tempo snapshot?
