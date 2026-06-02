return {
  archive = {
    id = "minimal-substrate",
    title = "Minimal Reaper Labs Substrate",
    version = 1,
  },

  source = {
    id = "clip-blue",
    name = "Blue source video",
    file = "media/clips/clip-blue.mp4",
  },

  grid = {
    seconds = 0.5,
  },

  overlays = {
    {
      id = "overlay-grid",
      name = "Grid overlay",
      file = "media/overlays/overlay-grid.mp4",
      start = 0.0,
      duration = 2.0,
    },
  },

  masks = {
    {
      id = "mask-pulse",
      name = "Pulse mask",
      file = "media/masks/mask-pulse.mp4",
      start = 0.0,
      duration = 2.0,
    },
  },

  reference_audio = {
    {
      id = "reference-tone",
      name = "Reference tone",
      file = "media/audio/reference-tone.wav",
      start = 0.0,
      duration = 2.0,
    },
  },
}
