local M = {}

M.default_manifest_name = "manifest.lua"
M.generated_analysis_file = "analysis/generated-lab001.lua"
M.ffmpeg_scene_threshold = 0.30

local asset_roles = {
  overlays = "AfImg Overlays",
  masks = "AfImg Masks",
  reference_audio = "AfImg Reference Audio",
}

local asset_role_order = {
  "overlays",
  "masks",
  "reference_audio",
}

local function is_windows_absolute(path)
  return type(path) == "string" and path:match("^%a:[/\\]")
end

local function is_absolute(path)
  return type(path) == "string" and (path:sub(1, 1) == "/" or is_windows_absolute(path))
end

local function trim_trailing_slash(path)
  return (path:gsub("[/\\]+$", ""))
end

function M.join_path(root, child)
  if is_absolute(child) then
    return child
  end

  return trim_trailing_slash(root) .. "/" .. child
end

local function dirname(path)
  return path:match("^(.*)[/\\][^/\\]+$") or "."
end

local function shell_quote(value)
  local text = tostring(value)
  if package.config:sub(1, 1) == "\\" then
    return '"' .. text:gsub('"', '\\"') .. '"'
  end

  return "'" .. text:gsub("'", "'\\''") .. "'"
end

local function ensure_dir(path)
  local command
  if package.config:sub(1, 1) == "\\" then
    command = "mkdir " .. shell_quote(path)
  else
    command = "mkdir -p " .. shell_quote(path)
  end

  os.execute(command)
end

function M.file_exists(path)
  local file = io.open(path, "rb")
  if file then
    file:close()
    return true
  end

  return false
end

local function push_error(errors, message)
  errors[#errors + 1] = message
end

local function validate_number(errors, value, field, minimum)
  if type(value) ~= "number" then
    push_error(errors, field .. " must be a number")
    return false
  end

  if minimum and value < minimum then
    push_error(errors, field .. " must be >= " .. tostring(minimum))
    return false
  end

  return true
end

local function validate_optional_number(errors, value, field, minimum)
  if value == nil then
    return true
  end

  return validate_number(errors, value, field, minimum)
end

local function load_lua_table(path, description)
  local chunk, load_error = loadfile(path)

  if not chunk then
    return nil, { "Could not load " .. description .. " " .. path .. ": " .. tostring(load_error) }
  end

  local ok, value = pcall(chunk)
  if not ok then
    return nil, { "Could not evaluate " .. description .. " " .. path .. ": " .. tostring(value) }
  end

  if type(value) ~= "table" then
    return nil, { description .. " " .. path .. " must return a table" }
  end

  return value, {}
end

function M.load_manifest(archive_root)
  return load_lua_table(M.join_path(archive_root, M.default_manifest_name), "manifest")
end

local function copy_archive(manifest, errors)
  if type(manifest.archive) ~= "table" then
    push_error(errors, "archive must be a table")
    return {}
  end

  if type(manifest.archive.id) ~= "string" or manifest.archive.id == "" then
    push_error(errors, "archive.id must be a non-empty string")
  end

  if manifest.archive.version ~= nil then
    validate_number(errors, manifest.archive.version, "archive.version", 1)
  end

  return {
    id = manifest.archive.id,
    title = manifest.archive.title or manifest.archive.id,
    version = manifest.archive.version,
  }
end

local function copy_source(manifest, archive_root, errors)
  if type(manifest.source) ~= "table" then
    push_error(errors, "source must be a table")
    return nil
  end

  if type(manifest.source.file) ~= "string" or manifest.source.file == "" then
    push_error(errors, "source.file must be a non-empty string")
    return nil
  end

  local absolute_file = M.join_path(archive_root, manifest.source.file)
  if not M.file_exists(absolute_file) then
    push_error(errors, "source.file missing: " .. absolute_file)
  end

  return {
    id = manifest.source.id or "source",
    name = manifest.source.name or "Source video",
    file = manifest.source.file,
    absolute_file = absolute_file,
  }
end

local function copy_asset(role, asset, index, archive_root, errors)
  local prefix = role .. "[" .. tostring(index) .. "]"

  if type(asset) ~= "table" then
    push_error(errors, prefix .. " must be a table")
    return nil
  end

  if type(asset.id) ~= "string" or asset.id == "" then
    push_error(errors, prefix .. ".id must be a non-empty string")
  end

  if type(asset.file) ~= "string" or asset.file == "" then
    push_error(errors, prefix .. ".file must be a non-empty string")
  end

  validate_optional_number(errors, asset.start, prefix .. ".start", 0)
  validate_optional_number(errors, asset.duration, prefix .. ".duration", 0.001)

  local absolute_file = ""
  if type(asset.file) == "string" and asset.file ~= "" then
    absolute_file = M.join_path(archive_root, asset.file)
    if not M.file_exists(absolute_file) then
      push_error(errors, prefix .. ".file missing: " .. absolute_file)
    end
  end

  return {
    id = asset.id,
    name = asset.name or asset.id,
    file = asset.file,
    absolute_file = absolute_file,
    start = asset.start or 0,
    duration = asset.duration,
    role = role,
  }
end

local function copy_assets(manifest, archive_root, errors)
  local assets = {}

  for _, role in ipairs(asset_role_order) do
    local role_assets = manifest[role]
    assets[role] = {}

    if role_assets ~= nil then
      if type(role_assets) ~= "table" then
        push_error(errors, role .. " must be a list")
      else
        for index, asset in ipairs(role_assets) do
          local copied = copy_asset(role, asset, index, archive_root, errors)
          if copied then
            assets[role][#assets[role] + 1] = copied
          end
        end
      end
    end
  end

  return assets
end

local function copy_grid_override(manifest, errors)
  if manifest.grid == nil then
    return nil
  end

  if type(manifest.grid) ~= "table" then
    push_error(errors, "grid must be a table")
    return nil
  end

  if manifest.grid.seconds ~= nil then
    if validate_number(errors, manifest.grid.seconds, "grid.seconds", 0.001) then
      return {
        kind = "seconds",
        seconds = manifest.grid.seconds,
        source = "manifest",
      }
    end

    return nil
  end

  push_error(errors, "grid must set seconds, or be omitted to use the current REAPER project grid")
  return nil
end

local function project_grid_from_options(options, errors)
  if not options or not options.project_grid then
    push_error(errors, "grid is omitted, but no current REAPER project grid context was provided")
    return nil
  end

  local grid = options.project_grid
  if type(grid) ~= "table" then
    push_error(errors, "project_grid must be a table")
    return nil
  end

  if grid.seconds ~= nil then
    if not validate_number(errors, grid.seconds, "project_grid.seconds", 0.001) then
      return nil
    end

    return {
      kind = grid.kind or "project",
      seconds = grid.seconds,
      bpm = grid.bpm,
      division = grid.division,
      source = "reaper-project",
    }
  end

  if validate_number(errors, grid.bpm, "project_grid.bpm", 1)
    and validate_number(errors, grid.division, "project_grid.division", 0.001)
  then
    return {
      kind = "project",
      seconds = (60 / grid.bpm) * grid.division,
      bpm = grid.bpm,
      division = grid.division,
      source = "reaper-project",
    }
  end

  return nil
end

local function resolve_grid(manifest, options, errors)
  if manifest.grid ~= nil then
    return copy_grid_override(manifest, errors)
  end

  return project_grid_from_options(options, errors)
end

local function run_capture(command)
  local pipe = io.popen(command .. " 2>&1")
  if not pipe then
    return nil, "could not start command"
  end

  local output = pipe:read("*a")
  local ok, reason, code = pipe:close()

  if ok or code == 0 then
    return output, nil
  end

  return nil, (output or "") .. "\ncommand failed: " .. tostring(reason) .. " " .. tostring(code)
end

function M.probe_duration(path)
  local command = table.concat({
    "ffprobe",
    "-v error",
    "-show_entries format=duration",
    "-of default=noprint_wrappers=1:nokey=1",
    shell_quote(path),
  }, " ")

  local output, err = run_capture(command)
  if not output then
    return nil, err
  end

  local duration = tonumber(output:match("([%d%.]+)"))
  if not duration or duration <= 0 then
    return nil, "ffprobe did not return a positive duration for " .. path
  end

  return duration, nil
end

local function unique_sorted_boundaries(boundaries, duration)
  table.sort(boundaries)

  local result = {}
  local previous
  for _, boundary in ipairs(boundaries) do
    if boundary > 0.001 and boundary < duration - 0.001 then
      if not previous or math.abs(boundary - previous) > 0.001 then
        result[#result + 1] = boundary
        previous = boundary
      end
    end
  end

  return result
end

function M.detect_scene_boundaries(path, threshold)
  local filter = "select='gt(scene," .. string.format("%.2f", threshold) .. ")',showinfo"
  local command = table.concat({
    "ffmpeg",
    "-hide_banner",
    "-nostats",
    "-i",
    shell_quote(path),
    "-vf",
    shell_quote(filter),
    "-f null -",
  }, " ")

  local output, err = run_capture(command)
  if not output then
    return nil, err
  end

  local boundaries = {}
  for value in output:gmatch("pts_time:([%d%.]+)") do
    boundaries[#boundaries + 1] = tonumber(value)
  end

  return boundaries, nil
end

local function make_grid_cuts(scene, grid)
  local cuts = {}
  local cursor = scene.source_start
  local cut_index = 1

  while cursor < scene.source_end - 0.000001 do
    local next_cut = math.min(scene.source_end, cursor + grid.seconds)
    cuts[#cuts + 1] = {
      id = scene.id .. "-cut-" .. string.format("%03d", cut_index),
      source_start = cursor,
      source_end = next_cut,
      duration = next_cut - cursor,
      project_start = cursor,
      project_end = next_cut,
    }

    cursor = next_cut
    cut_index = cut_index + 1
  end

  return cuts
end

local function build_scenes_from_boundaries(boundaries, duration, grid)
  local scenes = {}
  local points = { 0 }

  for _, boundary in ipairs(unique_sorted_boundaries(boundaries, duration)) do
    points[#points + 1] = boundary
  end
  points[#points + 1] = duration

  for index = 1, #points - 1 do
    local scene = {
      id = "scene-" .. string.format("%03d", index),
      source_start = points[index],
      source_end = points[index + 1],
    }
    scene.duration = scene.source_end - scene.source_start
    scene.cuts = make_grid_cuts(scene, grid)
    scenes[#scenes + 1] = scene
  end

  return scenes
end

local function analysis_header(method, source, duration, grid)
  return {
    version = 1,
    method = method,
    source = {
      id = source.id,
      file = source.file,
      duration = duration,
    },
    scene_threshold = method == "ffmpeg-scene" and M.ffmpeg_scene_threshold or nil,
    grid = {
      kind = grid.kind,
      seconds = grid.seconds,
      bpm = grid.bpm,
      division = grid.division,
      source = grid.source,
    },
  }
end

local function encode_value(value, indent)
  if type(value) == "table" then
    local prefix = string.rep(" ", indent)
    local child_prefix = string.rep(" ", indent + 2)
    local lines = { "{\n" }
    local array = #value > 0
    if array then
      for _, item in ipairs(value) do
        lines[#lines + 1] = child_prefix .. encode_value(item, indent + 2) .. ",\n"
      end
    else
      local keys = {}
      for key in pairs(value) do
        if value[key] ~= nil then
          keys[#keys + 1] = key
        end
      end
      table.sort(keys)
      for _, key in ipairs(keys) do
        lines[#lines + 1] = child_prefix .. tostring(key) .. " = " .. encode_value(value[key], indent + 2) .. ",\n"
      end
    end

    lines[#lines + 1] = prefix .. "}"
    return table.concat(lines)
  elseif type(value) == "string" then
    return string.format("%q", value)
  else
    return tostring(value)
  end
end

local function serialize_table(value)
  return "return " .. encode_value(value, 0) .. "\n"
end

function M.write_analysis(path, analysis)
  ensure_dir(dirname(path))

  local file, err = io.open(path, "wb")
  if not file then
    return false, err
  end

  file:write(serialize_table(analysis))
  file:close()
  return true, nil
end

local function validate_scene(scene, index, errors)
  local prefix = "analysis.scenes[" .. tostring(index) .. "]"

  if type(scene) ~= "table" then
    push_error(errors, prefix .. " must be a table")
    return nil
  end

  validate_number(errors, scene.source_start, prefix .. ".source_start", 0)
  validate_number(errors, scene.source_end, prefix .. ".source_end", 0.001)

  if type(scene.source_start) == "number"
    and type(scene.source_end) == "number"
    and scene.source_end <= scene.source_start
  then
    push_error(errors, prefix .. ".source_end must be greater than source_start")
  end

  local duration = scene.duration
  if duration == nil and type(scene.source_start) == "number" and type(scene.source_end) == "number" then
    duration = scene.source_end - scene.source_start
  end

  return {
    id = scene.id or ("scene-" .. string.format("%03d", index)),
    source_start = scene.source_start,
    source_end = scene.source_end,
    duration = duration,
    cuts = scene.cuts,
  }
end

local function validate_cut(cut, scene_index, cut_index, errors)
  local prefix = "analysis.scenes[" .. tostring(scene_index) .. "].cuts[" .. tostring(cut_index) .. "]"

  if type(cut) ~= "table" then
    push_error(errors, prefix .. " must be a table")
    return nil
  end

  validate_number(errors, cut.source_start, prefix .. ".source_start", 0)
  validate_number(errors, cut.source_end, prefix .. ".source_end", 0.001)
  validate_number(errors, cut.project_start, prefix .. ".project_start", 0)
  validate_number(errors, cut.project_end, prefix .. ".project_end", 0.001)

  if type(cut.source_start) == "number"
    and type(cut.source_end) == "number"
    and cut.source_end <= cut.source_start
  then
    push_error(errors, prefix .. ".source_end must be greater than source_start")
  end

  if type(cut.project_start) == "number"
    and type(cut.project_end) == "number"
    and cut.project_end <= cut.project_start
  then
    push_error(errors, prefix .. ".project_end must be greater than project_start")
  end

  local duration = cut.duration
  if duration == nil and type(cut.source_start) == "number" and type(cut.source_end) == "number" then
    duration = cut.source_end - cut.source_start
  end

  return {
    id = cut.id or ("cut-" .. string.format("%03d", cut_index)),
    source_start = cut.source_start,
    source_end = cut.source_end,
    duration = duration,
    project_start = cut.project_start,
    project_end = cut.project_end,
  }
end

local function normalize_analysis(raw_analysis, source, grid, default_method, errors)
  if type(raw_analysis.scenes) ~= "table" or #raw_analysis.scenes == 0 then
    push_error(errors, "analysis.scenes must contain at least one scene")
    return nil
  end

  local analysis = analysis_header(raw_analysis.method or default_method, source, raw_analysis.source and raw_analysis.source.duration or nil, grid)
  analysis.scenes = {}

  for scene_index, raw_scene in ipairs(raw_analysis.scenes) do
    local scene = validate_scene(raw_scene, scene_index, errors)
    if scene then
      if type(scene.cuts) == "table" and #scene.cuts > 0 then
        local raw_cuts = scene.cuts
        scene.cuts = {}
        for cut_index, raw_cut in ipairs(raw_cuts) do
          local cut = validate_cut(raw_cut, scene_index, cut_index, errors)
          if cut then
            scene.cuts[#scene.cuts + 1] = cut
          end
        end
      else
        scene.cuts = make_grid_cuts(scene, grid)
      end

      analysis.scenes[#analysis.scenes + 1] = scene
    end
  end

  if #errors > 0 then
    return nil
  end

  analysis.source.duration = analysis.source.duration or analysis.scenes[#analysis.scenes].source_end
  return analysis
end

local function load_provided_analysis(archive_root, manifest, source, grid, errors)
  if type(manifest.analysis) ~= "table" or type(manifest.analysis.cuts_file) ~= "string" or manifest.analysis.cuts_file == "" then
    return nil
  end

  local path = M.join_path(archive_root, manifest.analysis.cuts_file)
  local raw_analysis, load_errors = load_lua_table(path, "analysis")
  if not raw_analysis then
    for _, err in ipairs(load_errors) do
      push_error(errors, err)
    end
    return nil
  end

  return normalize_analysis(raw_analysis, source, grid, "provided", errors)
end

local function generate_analysis(archive_root, source, grid, errors)
  local duration, duration_error = M.probe_duration(source.absolute_file)
  if not duration then
    push_error(errors, "Could not determine source duration: " .. tostring(duration_error))
    return nil
  end

  local boundaries, scene_error = M.detect_scene_boundaries(source.absolute_file, M.ffmpeg_scene_threshold)
  if not boundaries then
    push_error(errors, "Could not run FFmpeg scene detection: " .. tostring(scene_error))
    return nil
  end

  local method = #boundaries > 0 and "ffmpeg-scene" or "single-scene"
  local analysis = analysis_header(method, source, duration, grid)
  analysis.scene_threshold = M.ffmpeg_scene_threshold
  analysis.scenes = build_scenes_from_boundaries(boundaries, duration, grid)

  local output_path = M.join_path(archive_root, M.generated_analysis_file)
  local ok, write_error = M.write_analysis(output_path, analysis)
  if not ok then
    push_error(errors, "Could not write generated analysis " .. output_path .. ": " .. tostring(write_error))
    return nil
  end

  analysis.generated_file = output_path
  return analysis
end

local function media_item(id, name, role, track_name, absolute_file, start, duration)
  return {
    id = id,
    name = name,
    role = role,
    track_name = track_name,
    absolute_file = absolute_file,
    start = start,
    duration = duration,
  }
end

local function build_tracks(source, assets, analysis)
  local tracks = {
    {
      role = "source",
      name = "AfImg Source",
      items = {
        media_item(source.id, source.name, "source", "AfImg Source", source.absolute_file, 0, analysis.source.duration),
      },
    },
  }

  for _, role in ipairs(asset_role_order) do
    local items = {}
    for _, asset in ipairs(assets[role] or {}) do
      items[#items + 1] = media_item(
        asset.id,
        asset.name,
        role,
        asset_roles[role],
        asset.absolute_file,
        asset.start,
        asset.duration or analysis.source.duration
      )
    end

    if #items > 0 then
      tracks[#tracks + 1] = {
        role = role,
        name = asset_roles[role],
        items = items,
      }
    end
  end

  return tracks
end

function M.plan_import(archive_root, options)
  local manifest, load_errors = M.load_manifest(archive_root)
  if not manifest then
    return nil, load_errors
  end

  local errors = {}
  local archive = copy_archive(manifest, errors)
  local source = copy_source(manifest, archive_root, errors)
  local assets = copy_assets(manifest, archive_root, errors)
  local grid = resolve_grid(manifest, options, errors)

  if manifest.tracks ~= nil then
    push_error(errors, "tracks is the old flat prototype contract; LAB-001 requires source-first source/overlays/masks/reference_audio fields")
  end

  if #errors > 0 then
    return nil, errors
  end

  local analysis = load_provided_analysis(archive_root, manifest, source, grid, errors)
  if not analysis and #errors == 0 then
    analysis = generate_analysis(archive_root, source, grid, errors)
  end

  if #errors > 0 then
    return nil, errors
  end

  local plan = {
    archive_root = archive_root,
    archive = archive,
    source = source,
    grid = grid,
    analysis = analysis,
    tracks = build_tracks(source, assets, analysis),
  }

  return plan, {}
end

function M.summarize_plan(plan)
  local scene_count = #(plan.analysis.scenes or {})
  local cut_count = 0
  for _, scene in ipairs(plan.analysis.scenes or {}) do
    cut_count = cut_count + #(scene.cuts or {})
  end

  local lines = {
    "Archive: " .. tostring(plan.archive.id or "(unnamed)"),
    "Source: " .. tostring(plan.source.file),
    "Analysis method: " .. tostring(plan.analysis.method),
    "Scenes: " .. tostring(scene_count),
    "Grid cuts: " .. tostring(cut_count),
    "Grid seconds: " .. tostring(plan.grid.seconds),
  }

  if plan.analysis.generated_file then
    lines[#lines + 1] = "Generated analysis: " .. plan.analysis.generated_file
  end

  for _, track in ipairs(plan.tracks) do
    lines[#lines + 1] = track.name .. " (" .. track.role .. "): " .. tostring(#track.items) .. " item(s)"
  end

  return table.concat(lines, "\n")
end

return M
