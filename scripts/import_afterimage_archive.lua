local script_path = debug.getinfo(1, "S").source:gsub("^@", "")
local script_dir = script_path:match("^(.*)[/\\]") or "."
package.path = script_dir .. "/?.lua;" .. package.path

local archive = require("afterimage_archive")

local EXT_SECTION = "afterimage-reaper-labs"
local OWNER_KEY = "afimg-owner"
local OWNER_VALUE = "source-archive-import"
local NAME_PREFIX = "[AfImg]"
local LEGACY_NAME_PREFIX = "[AfImg LAB-001]"

local function show(message)
  if reaper and reaper.ShowConsoleMsg then
    reaper.ShowConsoleMsg(message .. "\n")
  else
    print(message)
  end
end

local function show_error(title, errors)
  local message = table.concat(errors, "\n")
  if reaper and reaper.ShowMessageBox then
    reaper.ShowMessageBox(message, title, 0)
  else
    show(title .. "\n" .. message)
  end
end

local function choose_archive_root()
  if not reaper or not reaper.GetUserFileName then
    return nil, { "This script must be run inside REAPER." }
  end

  local ok, path = reaper.GetUserFileName(3, "Choose Afterimage archive folder", "", "")
  if not ok or path == "" then
    return nil, { "No archive folder selected." }
  end

  return path, {}
end

local function current_project_grid()
  local division = 1
  if reaper.GetSetProjectGrid then
    local _, current_division = reaper.GetSetProjectGrid(0, false, 0, 0, 0)
    if type(current_division) == "number" and current_division > 0 then
      division = current_division
    end
  end

  local bpm = 120
  if reaper.TimeMap2_GetDividedBpmAtTime then
    local divided_bpm = reaper.TimeMap2_GetDividedBpmAtTime(0, 0)
    if type(divided_bpm) == "number" and divided_bpm > 0 then
      bpm = divided_bpm
    end
  elseif reaper.Master_GetTempo then
    local master_bpm = reaper.Master_GetTempo()
    if type(master_bpm) == "number" and master_bpm > 0 then
      bpm = master_bpm
    end
  end

  return {
    kind = "project",
    bpm = bpm,
    division = division,
    seconds = (60 / bpm) * division,
  }
end

local function starts_with(value, prefix)
  return type(value) == "string" and value:sub(1, #prefix) == prefix
end

local function get_or_create_track(name)
  local index = reaper.CountTracks(0)
  reaper.InsertTrackAtIndex(index, true)

  local track = reaper.GetTrack(0, index)
  reaper.GetSetMediaTrackInfo_String(track, "P_NAME", name, true)

  return track
end

local function mark_track_owned(track)
  reaper.GetSetMediaTrackInfo_String(track, "P_EXT:" .. OWNER_KEY, OWNER_VALUE, true)
end

local function track_is_owned(track)
  local _, owner = reaper.GetSetMediaTrackInfo_String(track, "P_EXT:" .. OWNER_KEY, "", false)
  local _, legacy_owner = reaper.GetSetMediaTrackInfo_String(track, "P_EXT:lab001-owner", "", false)
  return owner == OWNER_VALUE or legacy_owner == "LAB-001"
end

local function delete_owned_tracks()
  for index = reaper.CountTracks(0) - 1, 0, -1 do
    local track = reaper.GetTrack(0, index)
    if track_is_owned(track) then
      reaper.DeleteTrack(track)
    end
  end
end

local function delete_owned_markers()
  local _, generated = reaper.GetProjExtState(0, EXT_SECTION, "afimg-generated-markers")
  local _, legacy_generated = reaper.GetProjExtState(0, EXT_SECTION, "lab001-generated-markers")
  if generated ~= "1" and legacy_generated ~= "1" then
    return
  end

  local _, marker_count, region_count = reaper.CountProjectMarkers(0)
  for index = marker_count + region_count - 1, 0, -1 do
    local ok, _, _, _, name = reaper.EnumProjectMarkers3(0, index)
    if ok ~= 0 and (starts_with(name, NAME_PREFIX) or starts_with(name, LEGACY_NAME_PREFIX)) then
      reaper.DeleteProjectMarkerByIndex(0, index)
    end
  end
end

local function name_inserted_items(track, first_index, item_plan)
  local last_index = reaper.CountTrackMediaItems(track) - 1

  for index = first_index, last_index do
    local item = reaper.GetTrackMediaItem(track, index)
    reaper.SetMediaItemInfo_Value(item, "D_POSITION", item_plan.start)
    reaper.SetMediaItemInfo_Value(item, "D_LENGTH", item_plan.duration)

    local take = reaper.GetActiveTake(item)
    if take then
      reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", item_plan.name, true)
    end
  end
end

local function insert_item(track, item_plan, errors)
  reaper.SetOnlyTrackSelected(track)
  reaper.SetEditCurPos(item_plan.start, false, false)

  local before_count = reaper.CountTrackMediaItems(track)
  local result = reaper.InsertMedia(item_plan.absolute_file, 0)

  if result == 0 then
    errors[#errors + 1] = "REAPER failed to insert " .. item_plan.absolute_file
    return false
  end

  local after_count = reaper.CountTrackMediaItems(track)
  if after_count <= before_count then
    errors[#errors + 1] = "Inserted media did not appear on track " .. item_plan.track_name .. ": " .. item_plan.absolute_file
    return false
  end

  name_inserted_items(track, before_count, item_plan)
  return true
end

local function import_plan(plan)
  local errors = {}
  local imported_count = 0

  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(1)

  delete_owned_tracks()
  delete_owned_markers()

  for _, track_plan in ipairs(plan.tracks) do
    local track = get_or_create_track(track_plan.name)
    mark_track_owned(track)

    for _, item_plan in ipairs(track_plan.items) do
      if insert_item(track, item_plan, errors) then
        imported_count = imported_count + 1
      end
    end
  end

  for _, scene in ipairs(plan.analysis.scenes or {}) do
    reaper.AddProjectMarker2(
      0,
      true,
      scene.source_start,
      scene.source_end,
      NAME_PREFIX .. " " .. scene.id,
      -1,
      0
    )

    for _, cut in ipairs(scene.cuts or {}) do
      reaper.AddProjectMarker2(
        0,
        false,
        cut.project_start,
        0,
        NAME_PREFIX .. " " .. cut.id .. " src " .. string.format("%.3f", cut.source_start),
        -1,
        0
      )
    end
  end

  reaper.SetProjExtState(0, EXT_SECTION, "afimg-owner", OWNER_VALUE)
  reaper.SetProjExtState(0, EXT_SECTION, "afimg-archive-id", tostring(plan.archive.id or ""))
  reaper.SetProjExtState(0, EXT_SECTION, "afimg-generated-markers", "1")
  reaper.SetProjExtState(0, EXT_SECTION, "afimg-marker-prefix", NAME_PREFIX)
  reaper.SetProjExtState(0, EXT_SECTION, "afimg-analysis-method", tostring(plan.analysis.method or ""))

  reaper.PreventUIRefresh(-1)
  reaper.UpdateArrange()
  reaper.Undo_EndBlock("Import AfImg source archive substrate", -1)

  return imported_count, errors
end

local function main()
  local archive_root, choose_errors = choose_archive_root()
  if not archive_root then
    show_error("Afterimage archive import", choose_errors)
    return
  end

  local plan, plan_errors = archive.plan_import(archive_root, {
    project_grid = current_project_grid(),
  })
  if not plan then
    show_error("Afterimage archive validation failed", plan_errors)
    return
  end

  show("Afterimage archive import plan:\n" .. archive.summarize_plan(plan))

  local imported_count, import_errors = import_plan(plan)
  if #import_errors > 0 then
    show_error("Afterimage archive import had errors", import_errors)
    return
  end

  show("Imported " .. tostring(imported_count) .. " media item(s) from " .. archive_root)
end

main()
