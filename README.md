# Afterimage Reaper Labs

A Reaper-based proving ground for Afterimage field engines, modulation ideas, video routing experiments, and controllable generative motion before they graduate into the standalone Afterimage roadmap.

This is not the product.
This is the lab.

## Purpose

Afterimage Reaper Labs exists to reduce risk for Afterimage M7 and beyond.

The lab should prove, disprove, or refine future Afterimage ideas using Reaper's timeline, automation, JSFX, Lua scripting, MIDI/OSC control, video processing, and FFmpeg rendering.

Every experiment should answer a question:

- Is this effect actually interesting?
- Can the artist control it without killing the magic?
- Which parameters matter?
- Which controls should be exposed?
- Does this belong in Afterimage core, a plugin, or the bin?

## Non-goals

This repository is not:

- A standalone video application.
- A Reaper clone of Afterimage.
- A polished commercial product.
- A place for vague feature accumulation.
- An AI video generation system.

The core model is signal, field, motion, modulation, routing, compositing, and controlled chaos.

## Working principle

Field -> Automation -> Video behaviour -> Rendered evidence -> Decision.

If an experiment does not produce a decision, it is unfinished.

## Initial repository layout

```text
afterimage-reaper-labs/
├── AGENTS.md
├── README.md
├── docs/
│   ├── experiment-template.md
│   ├── roadmap-alignment.md
│   └── reaper-api-notes.md
├── experiments/
│   └── 000-field-to-automation-bridge/
│       └── experiment.md
├── jsfx/
│   └── README.md
├── scripts/
│   └── README.md
└── templates/
    └── README.md
```

## Experiment lifecycle

Each experiment should move through this shape:

1. Hypothesis
2. Prototype
3. Render or captured evidence
4. Notes on control feel
5. Decision
6. Graduation target

Valid decisions:

- Promote to Afterimage core
- Promote to Afterimage plugin
- Keep as Reaper-only lab tool
- Revisit later
- Reject

## First target

The first useful capability is the Field -> Automation Bridge.

Given N generated values over time, write them to Reaper automation envelopes so that field generators can drive video parameters.

Once that exists, the lab can test:

- Boids-driven movement
- Cellular automata masks
- FFT-driven crop/zoom/opacity
- Cloud brightness tracking
- External data modulation
- Pseudo-warping via controllable video parameters

## Relationship to Afterimage

This repository should support Afterimage M7+ decisions.

The standalone Afterimage repo remains the product.
This repo is the messy visual synthesis breadboard.
