local script_path = debug.getinfo(1, "S").source:gsub("^@", "")
local script_dir = script_path:match("^(.*)[/\\]") or "."
package.path = script_dir .. "/?.lua;" .. package.path

local archive = require("afterimage_archive")

local function shell_quote(value)
  return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

local function mkdir(path)
  os.execute("mkdir -p " .. shell_quote(path))
end

local function write_file(path, contents)
  mkdir(path:match("^(.*)[/\\][^/\\]+$") or ".")
  local file, err = io.open(path, "wb")
  assert(file, err)
  file:write(contents)
  file:close()
end

local function assert_contains(errors, needle)
  local text = table.concat(errors, "\n")
  assert(text:find(needle, 1, true), "expected error containing " .. needle .. "\nactual:\n" .. text)
end

local function plan_or_fail(root, options)
  local plan, errors = archive.plan_import(root, options)
  assert(plan, errors and table.concat(errors, "\n") or "plan_import failed")
  return plan
end

local function make_root(name)
  local root = "/tmp/afterimage-reaper-labs-" .. name .. "-" .. tostring(os.time())
  mkdir(root)
  return root
end

local repo_root = os.getenv("PWD") or (script_dir .. "/..")
local fixture_root = repo_root .. "/fixtures/archives/minimal-substrate"
local source_file = repo_root .. "/fixtures/archives/minimal-substrate/media/clips/clip-blue.mp4"

local fixture_plan = plan_or_fail(fixture_root)
assert(fixture_plan.analysis.method == "single-scene", "expected no-scene fallback")
assert(#fixture_plan.analysis.scenes == 1, "expected one fallback scene")
assert(#fixture_plan.analysis.scenes[1].cuts == 4, "expected 0.5s grid cuts")
assert(archive.file_exists(fixture_root .. "/" .. archive.generated_analysis_file), "expected generated analysis file")

local provided_root = make_root("provided")
write_file(provided_root .. "/manifest.lua", [[
return {
  archive = { id = "provided", version = 1 },
  source = { file = "]] .. source_file .. [[" },
  grid = { seconds = 1.0 },
  analysis = { cuts_file = "analysis/cuts.lua" },
}
]])
write_file(provided_root .. "/analysis/cuts.lua", [[
return {
  version = 1,
  source = { duration = 2.0 },
  scenes = {
    {
      id = "scene-001",
      source_start = 0,
      source_end = 2.0,
      cuts = {
        {
          id = "scene-001-cut-001",
          source_start = 0,
          source_end = 2.0,
          project_start = 0,
          project_end = 2.0,
        },
      },
    },
  },
}
]])
local provided_plan = plan_or_fail(provided_root)
assert(provided_plan.analysis.method == "provided", "expected provided analysis method")
assert(#provided_plan.analysis.scenes[1].cuts == 1, "expected provided cuts to be preserved")

local project_grid_root = make_root("project-grid")
write_file(project_grid_root .. "/manifest.lua", [[
return {
  archive = { id = "project-grid", version = 1 },
  source = { file = "]] .. source_file .. [[" },
}
]])
local project_grid_plan = plan_or_fail(project_grid_root, {
  project_grid = {
    bpm = 120,
    division = 0.5,
  },
})
assert(project_grid_plan.grid.kind == "project", "expected project grid fallback")
assert(project_grid_plan.grid.seconds == 0.25, "expected 120bpm eighth-note grid to be 0.25s")
assert(#project_grid_plan.analysis.scenes[1].cuts == 8, "expected project grid cuts")

local invalid_grid_root = make_root("invalid-grid")
write_file(invalid_grid_root .. "/manifest.lua", [[
return {
  archive = { id = "invalid-grid", version = 1 },
  source = { file = "]] .. source_file .. [[" },
  grid = { seconds = 0 },
}
]])
local invalid_grid_plan, invalid_grid_errors = archive.plan_import(invalid_grid_root, {
  project_grid = {
    bpm = 120,
    division = 1,
  },
})
assert(not invalid_grid_plan, "expected invalid manifest grid to fail instead of falling back")
assert_contains(invalid_grid_errors, "grid.seconds must be >= 0.001")

local missing_root = make_root("missing-source")
write_file(missing_root .. "/manifest.lua", [[
return {
  archive = { id = "missing-source", version = 1 },
  source = { file = "media/missing.mp4" },
  grid = { seconds = 1.0 },
}
]])
local missing_plan, missing_errors = archive.plan_import(missing_root)
assert(not missing_plan, "expected missing source to fail")
assert_contains(missing_errors, "source.file missing")

local malformed_root = make_root("malformed-analysis")
write_file(malformed_root .. "/manifest.lua", [[
return {
  archive = { id = "malformed-analysis", version = 1 },
  source = { file = "]] .. source_file .. [[" },
  grid = { seconds = 1.0 },
  analysis = { cuts_file = "analysis/cuts.lua" },
}
]])
write_file(malformed_root .. "/analysis/cuts.lua", [[
return {
  scenes = {
    { source_start = 2.0, source_end = 1.0 },
  },
}
]])
local malformed_plan, malformed_errors = archive.plan_import(malformed_root)
assert(not malformed_plan, "expected malformed analysis to fail")
assert_contains(malformed_errors, "source_end must be greater than source_start")

print("afterimage_archive tests passed")
