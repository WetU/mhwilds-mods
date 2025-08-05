local CONFIG_PATH = 'auto_select_nearest_camp.json'

---@class Config
---@field isEnabled boolean
local config = {
  isEnabled = true,
}

local function save_config()
  json.dump_file(CONFIG_PATH, config)
end

---@param input Config
---@return boolean
local function is_valid_config(input)
  if not input then return false end
  if type(input.isEnabled) ~= 'boolean' then return false end
  return true
end

local function load_config()
  local loaded_config = json.load_file(CONFIG_PATH)
  if is_valid_config(loaded_config) then
    config = loaded_config
  else
    -- Overwrite an invalid or missing config with default values:
    save_config()
  end
end

load_config()

---@class REManagedObject
---@field call fun(REManagedObject, ...): any
---@field get_field fun(REManagedObject, string): any

---@class Vector3f: { x: number, y: number, z: number }

---@class app.cGUIBeaconGimmick : REManagedObject
---@field getPos fun(): Vector3f

---@class app.cStartPointInfo : REManagedObject
---@field get_BeaconGimmick fun(): app.cGUIBeaconGimmick

---@class System.Collections.Generic.List<T>: { _items: T[], _size: integer }

---@class app.GUI050001 : REManagedObject
---@field get_CurrentStartPointList fun(): System.Collections.Generic.List<app.cStartPointInfo>
---@field get_QuestOrderParam fun(): { QuestViewData: app.cGUIQuestViewData }

-- Returns the approximate position of the first target monster for a quest.
-- Target locations are encoded only as area numbers (e.g. Uth Duna usually spawns in area 17);
-- in order to convert this to a position, we need to retrieve the map data for the quest stage,
-- which contains icon positions associated with each area.
---@param quest_accept_ui app.GUI050001
---@return Vector3f?
local function get_target_pos(quest_accept_ui)
  ---@class app.cGUIQuestViewData : REManagedObject
  ---@field get_Stage fun(): app.FieldDef.STAGE
  ---@field get_TargetEmStartArea fun(): { m_value: integer }[]
  local quest_view_data = quest_accept_ui:get_QuestOrderParam().QuestViewData

  local target_em_start_areas = quest_view_data:get_TargetEmStartArea()
  local target_em_start_area = nil
  for _, start_area in pairs(target_em_start_areas) do
    target_em_start_area = start_area.m_value
    break
  end

  if target_em_start_area == nil then
    log.debug("[Auto-Select Nearest Camp] ERROR: No starting area found for target")
    return nil
  end

  ---@class app.cGUIMapController : REManagedObject
  ---@field _MapStageDrawData app.user_data.MapStageDrawData
  local map_controller = sdk.get_managed_singleton('app.GUIManager'):get_MAP3D()
  ---@class app.user_data.MapStageDrawData : REManagedObject
  local map_stage_draw_data = map_controller._MapStageDrawData

  ---@alias app.FieldDef.STAGE number
  local stage = quest_view_data:get_Stage()

  ---@class app.user_data.MapStageDrawData.cDrawData : REManagedObject
  ---@field _AreaIconPosList System.Collections.Generic.List<app.user_data.MapStageDrawData.cAreaIconData>
  local stage_draw_data = map_stage_draw_data:call('getDrawData(app.FieldDef.STAGE)', stage)
  if stage_draw_data == nil then
    log.debug("[Auto-Select Nearest Camp] ERROR: Couldn't find cDrawData for stage " .. tostring(stage))
    return nil
  end

  local area_icon_pos_list = stage_draw_data._AreaIconPosList
  ---@class app.user_data.MapStageDrawData.cAreaIconData : REManagedObject
  ---@field _AreaIconPos Vector3f
  ---@field _AreaNum integer
  for _, area_icon_data in pairs(area_icon_pos_list._items) do
    if area_icon_data._AreaNum == target_em_start_area then
      return area_icon_data._AreaIconPos
    end
  end
end

-- Find the nearest start point to the target position and return its index in its list.
---@param target_pos Vector3f
---@param start_point_list System.Collections.Generic.List<app.cStartPointInfo>
---@return integer
local function get_index_of_nearest_start_point(target_pos, start_point_list)
  local shortest_distance = math.huge
  local nearest_index = 0
  local target_x, target_y, target_z = target_pos.x, target_pos.y, target_pos.z

  for index, start_point in ipairs(start_point_list._items) do
    local beacon_gimmick = start_point:get_BeaconGimmick()
    local beacon_pos = beacon_gimmick:getPos()
    local dx, dy, dz = beacon_pos.x - target_x, beacon_pos.y - target_y, beacon_pos.z - target_z
    local d2 = dx * dx + dy * dy + dz * dz
    if d2 < shortest_distance then
      shortest_distance = d2
      nearest_index = index
    end
  end

  return nearest_index
end

local function auto_select_nearest_camp()
  ---@type app.GUI050001
  local quest_accept_ui = thread.get_hook_storage()['quest_accept_ui']
  if quest_accept_ui == nil then return end

  local start_point_list = quest_accept_ui:get_CurrentStartPointList()
  -- Exit early if the list only has 1 item:
  if start_point_list == nil or start_point_list._size <= 1 then return end

  local target_pos = get_target_pos(quest_accept_ui)
  if target_pos == nil then return end

  local nearest_start_point_index = get_index_of_nearest_start_point(target_pos, start_point_list)
  if nearest_start_point_index ~= nil and nearest_start_point_index > 0 then
    -- TODO: This isn't sufficient for updating the highlighted camp in the map preview.
    -- Interacting with GUI elements, but it won't happen on its own. See notes below.
    quest_accept_ui:call('setCurrentSelectStartPointIndex(System.Int32)', nearest_start_point_index)
  end
end

-- Grab the quest_accept_ui instance and store it in the ephemeral hook storage:
-- https://cursey.github.io/reframework-book/api/thread.html#threadget_hook_storage
local function on_pre_open(args)
  local hook_storage = thread.get_hook_storage()
  hook_storage['quest_accept_ui'] = sdk.to_managed_object(args[2])

  return sdk.PreHookResult.CALL_ORIGINAL
end

local function on_post_open(retval)
  if not config.isEnabled then return retval end

  local ok, error = pcall(auto_select_nearest_camp)
  if not ok then log.debug('[Auto-Select Nearest Camp] ERROR: ' .. tostring(error)) end
  return retval
end

local quest_accept_ui_t = sdk.find_type_definition('app.GUI050001')
sdk.hook(quest_accept_ui_t:get_method('onOpen()'), on_pre_open, on_post_open)

re.on_config_save(save_config)

re.on_draw_ui(function()
  if imgui.tree_node('Auto-Select Nearest Camp') then
    local changed, isEnabled = imgui.checkbox('Enabled', config.isEnabled)
    if changed then
      config.isEnabled = isEnabled
      save_config()
    end

    imgui.tree_pop()
  end
end)

log.info('[Auto-Select Nearest Camp] Initialized')

--[[
NOTES:

Everything works as expected, except the highlighted camp won't update automatically.
There's something connecting app.GUI050001 to the map (app.GUI060008), but I can't figure it out.
Ideally it's just a state in something type or singleton I haven't found yet (plausible), but it's
also possible that there's something low-level deep in the GUI architecture that's harder to parse.

Loose notes on types and methods I've tried:

- app.GUI050001
  - changeDarwSegmentDefault() [sic]
  - changeDrawSegmentForStartPointList()
  - clearStartPointGimmickDraw()
  - clearFocusStartPointIcon()
  - decrementSelectStartPointIndex()
  - incrementSelectStartPointIndex()
  - initStartPoint()
  - mapForceSelectFloor()
  - setActiveStartPointList(System.Boolean)
    - Toggles the start point list submenu, which doesn't update the highlight programmatically,
      even though toggling it with any user input does.
  - setFocusStartPointIcon(System.Int32)
    - setSelectFloorFastTravelGmLocated(app.cGUIBeaconBase)
  - updateStartPointText()
  - _AcceptList: app.GUI050001_AcceptList
    - callbackDecide(via.gui.Control, via.gui.SelectItem, System.UInt32)
    - _InputCtrl: ace.cGUIInputCtrl_FluentItemsControlLink`2<app.GUIID.ID,app.GUIFunc.TYPE>
      - I started to get pretty deep into the GUI stuff here; it's weird that clicking these works,
        but invoking their observable callbacks programmatically doesn't.
      - changeItemIndexToFicIndex(System.UInt32)
      - changeItemNumFluent(System.UInt32, System.Boolean)
      - executeCallback()
      - onMouseDecide(via.gui.SelectItem)
      - funcDecideEvent()
      - funcMouseDecideEvent()
      - requestCallDecide()
      - selectItemOnMouseEvent(via.gui.SelectItem)
      - _FicLink: via.gui.FluentItemsControlLink
      - _FlsList: ace.cGUIInputCtrl_FluentScrollList`2<app.GUIID.ID,app.GUIFunc.TYPE>
      - _SelectedIndex: System.UInt32
    - _OptionalDisplayItem_StartPoint: via.gui.SelectItem
      - decide()
  - _StartPointList: app.GUI050001_StartPointList

- app.GUI060008 (accessible via app.cGUIMapController:get_GUIGround())
  - applyColorSummary()
  - clearColorSummary()
  - updateSummary()
  - updateRequestQuestEmArea(app.GUI060008.cRequestQuestEmArea)
  - _FloorController: app.cGUI3DMapStageModelController
    - _FloorListCtrl: app.cGUI3DMapFloorListController

- app.cGUIMapController (accessible via app.GUIManager singleton)
  - clearQuestBoardDummyIcon()
  - forceInteractBeacon(app.cGUIBeaconBase)
  - mapForceSelectFloor(System.Func`1<System.Int32>)
  - setImmediateSelectFloor(System.Int32)
  - setQuestBoardDummyIcon(app.cGUIQuestViewData)
  - setSelectFloor(System.Int32)
]] --