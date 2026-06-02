return {
  grid = {
    kind = "seconds",
    seconds = 0.5,
    source = "manifest",
  },
  method = "single-scene",
  scene_threshold = 0.3,
  scenes = {
    {
      cuts = {
        {
          duration = 0.5,
          id = "scene-001-cut-001",
          project_end = 0.5,
          project_start = 0,
          source_end = 0.5,
          source_start = 0,
        },
        {
          duration = 0.5,
          id = "scene-001-cut-002",
          project_end = 1.0,
          project_start = 0.5,
          source_end = 1.0,
          source_start = 0.5,
        },
        {
          duration = 0.5,
          id = "scene-001-cut-003",
          project_end = 1.5,
          project_start = 1.0,
          source_end = 1.5,
          source_start = 1.0,
        },
        {
          duration = 0.5,
          id = "scene-001-cut-004",
          project_end = 2.0,
          project_start = 1.5,
          source_end = 2.0,
          source_start = 1.5,
        },
      },
      duration = 2.0,
      id = "scene-001",
      source_end = 2.0,
      source_start = 0,
    },
  },
  source = {
    duration = 2.0,
    file = "media/clips/clip-blue.mp4",
    id = "clip-blue",
  },
  version = 1,
}
