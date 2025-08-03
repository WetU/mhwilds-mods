local function wrapped_pcall(fn)
  local ok, result = pcall(fn)
  if not ok then
    log.debug("ERROR: " .. tostring(result))
  end
  return ok and result or nil
end

local function inspect(thing)
  local managed_object = wrapped_pcall(function() return sdk.to_managed_object(thing) end)
  if not managed_object then
    if type(thing) == 'userdata' then
      log.debug('userdata ' .. tostring(sdk.to_int64(thing)))
    else
      log.debug(tostring(type(thing)))
    end
    return
  end
  local full_name = wrapped_pcall(function()
    return tostring(managed_object:get_type_definition():get_full_name())
  end)
  if full_name then
    log.debug(tostring(full_name))
  end
end

-- local start_point_info_list = quest_menu:call('get_CurrentStartPointList')
-- if start_point_info_list ~= nil then
--   log.debug('start point info list:')
--   inspect(start_point_info_list)
--   local fields = sdk.to_managed_object(start_point_info_list):get_type_definition():get_fields()
--   for i, field in pairs(fields) do
--     log.debug('ITERATING OVER FIELD')
--     log.debug('name: ' .. tostring(field:get_name()))
--     log.debug('type: ' .. tostring(field:get_type():get_full_name()))
--   end
--   -- System.Collections.Generic.List`1<app.cStartPointInfo>
-- end

--- @enum StartPointType
local StartPointType = {
  NONE = -1,
  BASE_CAMP = 0,
  TENT = 1,
  TEMPORARY_CAMP = 2,
}

local function get_start_point_type(start_point_info)
  local type = start_point_info:call('get_Type()')
  for name, enum in pairs(StartPointType) do
    if enum == type then
      return name
    end
  end
end

--
local function get_start_points(quest_menu)
  -- System.Collections.Generic.List`1<app.cStartPointInfo>
  local start_point_list = quest_menu:call('get_CurrentStartPointList()')
  if start_point_list == nil then return end
  return sdk.to_managed_object(start_point_list)._items
end

-- app.cStartPointInfo
-- app.cGUIBeaconGimmick
local function get_beacon_gimmick(start_point_info)
  local ok, result = pcall(function()
    return start_point_info:call('get_BeaconGimmick()')
  end)
  if not ok or result == nil then
    return nil
  end
  return sdk.to_managed_object(result)
end

--- @param quest_menu unknown
--- @param index number
local function set_start_point_index(quest_menu, index)
  log.debug('Setting start point index to ' .. tostring(index))
  local ok, result = pcall(function()
    quest_menu:call('setCurrentSelectStartPointIndex(System.Int32)', index)
    quest_menu:call('updateStartPointText()')
  end)
  if not ok then
    log.debug('ERROR: Failed to set start point index. ' .. tostring(result))
  end
end

-- Grab the quest_menu instance on open and store it in the ephemeral hook storage for access in the `post` hook:
-- https://cursey.github.io/reframework-book/api/thread.html#threadget_hook_storage
local function on_pre_open(args)
  log.debug('on_pre_open')

  local storage = thread.get_hook_storage()
  storage['quest_menu'] = sdk.to_managed_object(args[2])

  return sdk.PreHookResult.CALL_ORIGINAL
end

local function on_post_open(retval)
  log.debug('on_post_open')

  local quest_menu = thread.get_hook_storage()['quest_menu']
  if quest_menu == nil then
    log.debug('ERROR: quest_menu is nil')
    return retval
  end

  local quest_order_param = quest_menu:get_QuestOrderParam()
  local quest_view_data = quest_order_param.QuestViewData -- app.cGUIQuestViewData

  local stage = quest_view_data:call('get_Stage()')
  log.debug('STAGE: ' .. tostring(stage))

  local target_start_area = quest_view_data:call('get_TargetEmStartArea()')

  local first_target_area = nil
  for k, v in pairs(target_start_area) do
    if first_target_area == nil then
      first_target_area = v.m_value
    end
    log.debug(tostring(v.m_value)) -- zone number (e.g. 17 for uth duna)
    -- log.debug(tostring(v))
    -- local fields = v:get_type_definition():get_fields()
    -- for i, field in pairs(fields) do
    --   log.debug('ITERATING OVER FIELD')
    --   log.debug('name: ' .. tostring(field:get_name()))
    --   log.debug('type: ' .. tostring(field:get_type():get_full_name()))
    -- end
  end

  if first_target_area == nil then
    return retval
  end

  -- for k, v in pairs(getmetatable(elements)) do
  --   log.debug(k .. ': ' .. tostring(v))
  -- end
  -- local mission_id = quest_view_data:get_MissionID()
  -- local enemies = mission_manager:call('getQuestDataFromMissionId(app.MissionIDList.ID)', mission_id)
  -- log.debug('ENEMIES?!')
  -- inspect(enemies) -- app.cActiveQuestData

  -- local accept_list = sdk.to_managed_object(quest_menu:get_field('_AcceptList'))
  -- local start_point_list = sdk.to_managed_object(quest_menu:get_field('_StartPointList'))

  local start_points = get_start_points(quest_menu)
  if start_points == nil then
    return retval
  end

  local has_set_index = false

  -- app.cGUIMapEmQuestCounterDummyIconController
  -- app.user_data.MapStageDrawData.cAreaIconData getAreaIconDrawData(app.FieldDef.STAGE, System.Int32)

  -- for index, start_point in pairs(start_points) do
  --   log.debug('ITERATING OVER START POINT ' .. tostring(index))
  --   local start_point_info = sdk.to_managed_object(start_point)
  --   if start_point_info ~= nil then
  --     local beacon_gimmick = get_beacon_gimmick(start_point_info)
  --     if beacon_gimmick ~= nil then
  --       log.debug('beacon_gimmick retrieved for start_point_info')
  --       log.debug('start point ID: ' .. tostring(start_point_info.CampID))
  --       log.debug('start_point type: ' .. get_start_point_type(start_point_info))
  --       if index > 1 and not has_set_index then
  --         has_set_index = true
  --         set_start_point_index(quest_menu, index)
  --       end
  --       -- -- log.debug(beacon_gimmick:get_type_definition():get_full_name())
  --       -- --- @class Vector3f
  --       -- --- @field x number
  --       -- --- @field y number
  --       -- --- @field z number
  --       -- local pos = beacon_gimmick:call('getPos()')
  --       -- local xyz = {
  --       --   x = pos.x,
  --       --   y = pos.y,
  --       --   z = pos.z,
  --       -- }
  --       -- for key, value in pairs(xyz) do
  --       --   log.debug(key .. ': ' .. tostring(value))
  --       -- end
  --     end
  --   end
  -- end

  local gui_manager = sdk.get_managed_singleton('app.GUIManager')
  -- app.cGUIMapController
  local map_controller = gui_manager:get_MAP3D()
  -- app.user_data.MapStageDrawData
  local map_stage_draw_data = map_controller:get_field('_MapStageDrawData')
  local stage_draw_data = map_stage_draw_data:call('getDrawData(app.FieldDef.STAGE)', stage)
  if stage_draw_data == nil then
    return retval
  end

  local area_icon_pos_list = stage_draw_data:get_field('_AreaIconPosList')
  for i, j in pairs(area_icon_pos_list._items) do
    -- app.user_data.MapStageDrawData.cAreaIconData
    local area_icon_data = sdk.to_managed_object(j)
    if (area_icon_data._AreaNum == first_target_area) then
      local pos = area_icon_data._AreaIconPos
      local xyz = {
        x = pos.x,
        y = pos.y,
        z = pos.z,
      }
      for key, value in pairs(xyz) do
        log.debug(key .. ': ' .. tostring(value))
      end
    end
  end

  -- _AreaNum, _AreaIconPos

  -- local area_draw_data = map_stage_draw_data:call('getDrawData(System.Int32)', first_target_area)
  -- inspect(area_draw_data)
  -- inspect(map_stage_draw_data)

  -- for k, v in pairs(map_stage_draw_data._DrawDatas) do
  --   log.debug('ITERATING OVER DRAW DATAS' .. tostring(k))
  --   local area_data = sdk.to_managed_object(v):get_field('_AreaIconPosList')
  --   for i, j in pairs(area_data._items) do
  --     log.debug(tostring(sdk.to_managed_object(j)._DrawAreaNum))
  --   end
  -- end

  -- local mission_target_list = map_controller:call('getMissionTargetListEm()') -- also ...ListEm()
  -- local mission_target_obj = sdk.to_managed_object(mission_target_list)
  -- local mission_targets = mission_target_obj._items
  -- log.debug(mission_target_obj._size)
  -- -- log.debug(mission_target_obj.get_size())

  -- for k, v in pairs(mission_targets) do
  --   log.debug('ITERATING OVER MISSION TARGET' .. tostring(k))
  --   inspect(v)
  -- end

  -- log.debug(map:get_type_definition():get_full_name())
  -- app.cGUIMapNaviPointController.cMapNaviData - gui_manager:getMapNaviData()

  -- local mission_manager = sdk.get_managed_singleton('app.MissionManager')
  -- local enemies = mission_manager:getAcceptQuestTargetBrowsers()
  -- log.debug('ENEMIES???')
  -- inspect(enemies)
  -- notes
  -- app.MissionManager (singleton)
    -- app.MissionBeaconController - getMissionBeaconController
    -- app.cActiveQuestData - getQuestDataFromMissionId(app.MissionIDList.ID)
    -- app.cMapContext_Enemy[] - getExQuest

    -- app.cEnemyBrowser[] - getAcceptQuestTargetBrowsers()

  -- app.cGUIQuestOrderParam.QuestViewData
  -- app.cGUIQuestViewData.get_MissionID

  return retval
end

local quest_menu_t = sdk.find_type_definition('app.GUI050001')
sdk.hook(quest_menu_t:get_method('onOpen'), on_pre_open, on_post_open)

log.debug('Initialized ABC')
