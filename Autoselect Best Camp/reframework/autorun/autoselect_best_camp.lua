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
-- Target monster locations are encoded only as area numbers (e.g. Uth Duna usually spawns in area 17);
-- in order to convert this to a position, we need to then retrieve the map data for the quest stage,
-- which contains area icon positions (which are presumably used to draw the actual monster icon on the map).
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
    log.debug("ERROR: No starting area found for target")
    return nil
  end

  ---@class app.cGUIMapController : REManagedObject
  ---@field _MapStageDrawData app.user_data.MapStageDrawData
  local map_controller = sdk.get_managed_singleton('app.GUIManager'):get_MAP3D()
  ---@class app.user_data.MapStageDrawData : REManagedObject
  local map_stage_draw_data = map_controller._MapStageDrawData

  ---@alias app.FieldDef.STAGE number
  local quest_stage = quest_view_data:get_Stage()

  ---@class app.user_data.MapStageDrawData.cDrawData : REManagedObject
  ---@field _AreaIconPosList System.Collections.Generic.List<app.user_data.MapStageDrawData.cAreaIconData>
  local quest_stage_draw_data = map_stage_draw_data:call('getDrawData(app.FieldDef.STAGE)', quest_stage)
  if quest_stage_draw_data == nil then
    log.debug("[ERROR] Couldn't find cDrawData for stage " .. tostring(quest_stage))
    return nil
  end

  local area_icon_pos_list = quest_stage_draw_data._AreaIconPosList
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
---@param start_points app.cStartPointInfo[]
---@return integer
local function get_index_of_nearest_start_point(target_pos, start_points)
  local shortest_distance = math.huge
  local nearest_index = 0
  local target_x, target_y, target_z = target_pos.x, target_pos.y, target_pos.z

  for index, start_point in ipairs(start_points) do
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

  local nearest_start_point_index = get_index_of_nearest_start_point(target_pos, start_point_list._items)
  if nearest_start_point_index ~= nil and nearest_start_point_index > 0 then
    -- TODO: This isn't sufficient for updating the highlighted camp in the map preview.
    -- Interacting with GUI elements will trigger that refresh, but it won't happen on its own.
    -- See notes below.
    quest_accept_ui:call('setCurrentSelectStartPointIndex(System.Int32)', nearest_start_point_index)
  end
end

-- Grab the quest_accept_ui instance on open and store it in the ephemeral hook storage for access in the `post` hook:
-- https://cursey.github.io/reframework-book/api/thread.html#threadget_hook_storage
local function on_pre_open(args)
  local hook_storage = thread.get_hook_storage()
  hook_storage['quest_accept_ui'] = sdk.to_managed_object(args[2])

  return sdk.PreHookResult.CALL_ORIGINAL
end

local function on_post_open(retval)
  local ok, error = pcall(auto_select_nearest_camp)
  if not ok then log.debug('[ERROR] ' .. tostring(error)) end
  return retval
end

local quest_accept_ui_t = sdk.find_type_definition('app.GUI050001')
sdk.hook(quest_accept_ui_t:get_method('onOpen()'), on_pre_open, on_post_open)

--[[
NOTES:

Everything works as expected, except the highlighted camp won't update automatically.
There's something connecting app.GUI050001 to the map (app.GUI060008), but I can't figure it out.
Ideally it's just a state in something type or singleton I haven't found yet (plausible), but it's
also possible that there's something low-level deep in the GUI architecture that I can't parse.

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
    - Toggles the start point list submenu, which doesn't update the camp highlight programmatically,
    - even though toggling it with any user input does.
  - setFocusStartPointIcon(System.Int32)
    - setSelectFloorFastTravelGmLocated(app.cGUIBeaconBase)
  - updateStartPointText()
- app.GUI050001_AcceptList
  - _InputCtrl: ace.cGUIInputCtrl_FluentItemsControlLink`2<app.GUIID.ID,app.GUIFunc.TYPE>
    - 
  - _OptionalDisplayItem_StartPoint: via.gui.SelectItem
    - decide()
- app.GUI050001_StartPointList

- app.GUI060008 (accessible via app.cGUIMapController:get_GUIGround())
  - applyColorSummary()
  - clearColorSummary()
  - updateSummary()
  - updateRequestQuestEmArea(app.GUI060008.cRequestQuestEmArea)
  - _FloorController: app.cGUI3DMapStageModelController

- app.cGUI3DMapStageModelController
  - _FloorListCtrl: app.cGUI3DMapFloorListController

- app.cGUIMapController (accessible via app.GUIManager singleton)
  - clearQuestBoardDummyIcon()
  - forceInteractBeacon(app.cGUIBeaconBase)
  - mapForceSelectFloor(System.Func`1<System.Int32>)
  - setImmediateSelectFloor(System.Int32)
  - setQuestBoardDummyIcon(app.cGUIQuestViewData)
  - setSelectFloor(System.Int32)
]]--

-- -- local delay = tonumber(os.clock() + 0.1)
-- -- while os.clock() < delay do end

-- _FloorListCtrl
-- app.cGUI3DMapStageModelController - app.GUI060008._FloorController

-- ace.cGUIInputCtrl`2<app.GUIID.ID,app.GUIFunc.TYPE>.onMouseDecide
-- input_ctrl:call('onMouseDecide(via.gui.SelectItem)', input_ctrl:getSelectedItem())
-- getItemFromListIndex(System.Int32, System.Int32)
-- funcMouseDecideEvent()
-- funcCancelEvent()

-- local fic_link = input_ctrl._FicLink
-- inspect(fic_link)
-- input_ctrl:call('changeItemIndexToFicIndex(System.UInt32)', nearest_start_point_index)
-- input_ctrl:call('<mouseEvent>g__selectItem|9_0(ace.cGUIInputCtrl_FluentItemsControlLink`2.<>c__DisplayClass9_0<app.GUIID.ID,app.GUIFunc.TYPE>)', fic_link, 0)
-- <mouseEvent>g__selectItem|9_0(ace.cGUIInputCtrl_FluentItemsControlLink`2.<>c__DisplayClass9_0<app.GUIID.ID,app.GUIFunc.TYPE>)

-- fic_link:funcDecideEvent()


-- fic_link:call('executeCallback()')
-- onMouseDecide(via.gui.SelectItem)
-- requestCallDecide()
--

-- inspect(input_ctrl)
-- input_ctrl:call('selectNextItem()')
-- local fls_list = input_ctrl._FlsList
-- inspect(fls_list)

-- accept_list:call('<callbackDecide>b__44_0(ace.GUIBaseCore)', sdk.typeof('ace.GUIBaseCore'))

-- local start_point_list_ui = quest_accept_ui._StartPointList
-- local input_ctrl = start_point_list_ui._InputCtrl
-- inspect(input_ctrl)
-- -- set_SelectedIndex(System.UInt32)
-- local fls_list = input_ctrl:get_FlsList()
-- local item = fls_list:call('getItemByGlobalIndex(System.Int32)', nearest_start_point_index)
-- inspect(item)
-- input_ctrl:selectItemOnMouseEvent(item)
-- input_ctrl:call('selectItemOnMouseEvent(via.gui.SelectItem)', item)
-- selectItemOnMouseEvent(via.gui.SelectItem)
-- fls_list:set_SelectedIndex(nearest_start_point_index)
-- input_ctrl:selectNextItem()

-- get_FlsList()
-- ace.cGUIInputCtrl_FluentScrollList`2<app.GUIID.ID,app.GUIFunc.TYPE>.ctrlSelectionChanged
-- input_ctrl:executeCallback()
-- ace.cGUIInputCtrl_FluentScrollList`2<app.GUIID.ID,app.GUIFunc.TYPE>.requestSelectIndexCore
-- local ref_window = start_point_list_ui._RefWindowPanel
-- -- inspect(ref_window) -- via.gui.Panel
-- input_ctrl:call('selectNextItem()')
-- input_ctrl:call('setInOutState()')
-- inspect(input_ctrl) -- ace.cGUIInputCtrl_FluentScrollList`2<app.GUIID.ID,app.GUIFunc.TYPE>
-- local fls_list = input_ctrl._FlsList
-- inspect(fls_list)

-- input_ctrl:changeItemNumFluent(nearest_start_point_index)
-- changeItemNumFluent(System.UInt32, System.Boolean)

-- input_ctrl:funcMouseDecideEvent()
-- input_ctrl:executeCallback()
-- input_ctrl:requestCallDecide()
-- input_ctrl:funcDecideEvent()

-- via.gui.FluentItemsControlLink

-- callbackDecide(via.gui.Control, via.gui.SelectItem, System.UInt32)

-- local start_point_item = accept_list._OptionalDisplayItem_StartPoint
-- inspect(start_point_item)
-- local inputCtrl = accept_list._InputCtrl
-- inspect(inputCtrl)
