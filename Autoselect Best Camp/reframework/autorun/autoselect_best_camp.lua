--- @class System.Collections.Generic.List<T>: { _items: T[], _size: integer }

--- @class Vector3f: { x: number, y: number, z: number }

--- @class REManagedObject
--- @field call fun(REManagedObject, ...): any
--- @field get_field fun(REManagedObject, string): any

--- @class app.cGUIBeaconGimmick : REManagedObject
--- @field getPos fun(): Vector3f

--- @class app.cStartPointInfo : REManagedObject
--- @field get_BeaconGimmick fun(): app.cGUIBeaconGimmick

--- @class app.GUI050001 : REManagedObject
--- @field get_CurrentStartPointList fun(): System.Collections.Generic.List<app.cStartPointInfo>
--- @field get_QuestOrderParam fun(): { QuestViewData: app.cGUIQuestViewData }

--- Returns the approximate position of the first target monster for a quest.
--- Target monster locations are encoded only as area numbers (e.g. Uth Duna usually spawns in area 17);
--- in order to convert this to a position, we need to then retrieve the map data for the quest stage,
--- which contains area icon positions (which are presumably used to draw the actual monster icon on the map).
--- @param quest_accept_ui app.GUI050001
--- @return Vector3f | nil
local function get_target_pos(quest_accept_ui)
  --- @class app.cGUIQuestViewData : REManagedObject
  --- @field get_Stage fun(): number app.FieldDef.STAGE
  --- @field get_TargetEmStartArea fun(): { m_value: integer }[]
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

  local quest_stage = quest_view_data:get_Stage()

  --- @class app.cGUIMapController : REManagedObject
  --- @field _MapStageDrawData app.user_data.MapStageDrawData
  local map_controller = sdk.get_managed_singleton('app.GUIManager'):get_MAP3D()
  --- @class app.user_data.MapStageDrawData : REManagedObject
  local map_stage_draw_data = map_controller._MapStageDrawData

  --- @class app.user_data.MapStageDrawData.cDrawData : REManagedObject
  --- @field _AreaIconPosList System.Collections.Generic.List<app.user_data.MapStageDrawData.cAreaIconData>
  local quest_stage_draw_data = map_stage_draw_data:call('getDrawData(app.FieldDef.STAGE)', quest_stage)
  if quest_stage_draw_data == nil then
    log.debug("ERROR: Couldn't find draw data for quest stage " .. tostring(quest_stage))
    return nil
  end

  local area_icon_pos_list = quest_stage_draw_data._AreaIconPosList
  --- @class app.user_data.MapStageDrawData.cAreaIconData : REManagedObject
  --- @field _AreaIconPos Vector3f
  --- @field _AreaNum integer
  for _, area_icon_data in pairs(area_icon_pos_list._items) do
    if area_icon_data._AreaNum == target_em_start_area then
      return area_icon_data._AreaIconPos
    end
  end
end

--- Find the closest start point to the target position and return its index in its list.
--- @param target_pos Vector3f
--- @param start_points app.cStartPointInfo[]
--- @return integer
local function get_closest_start_point_index(target_pos, start_points)
  local closest_distance = math.huge
  local closest_index = 0
  local target_x, target_y, target_z = target_pos.x, target_pos.y, target_pos.z

  for index, start_point in ipairs(start_points) do
    local beacon_gimmick = start_point:get_BeaconGimmick()
    local beacon_pos = beacon_gimmick:getPos()
    local dx, dy, dz = beacon_pos.x - target_x, beacon_pos.y - target_y, beacon_pos.z - target_z
    local d2 = dx * dx + dy * dy + dz * dz
    if d2 < closest_distance then
      closest_distance = d2
      closest_index = index
    end
  end

  return closest_index
end

-- Grab the quest_accept_ui instance on open and store it in the ephemeral hook storage for access in the `post` hook:
-- https://cursey.github.io/reframework-book/api/thread.html#threadget_hook_storage
local function on_pre_open(args)
  log.debug('on_pre_open')

  local storage = thread.get_hook_storage()
  storage['quest_accept_ui'] = sdk.to_managed_object(args[2])

  return sdk.PreHookResult.CALL_ORIGINAL
end

local function on_post_open(retval)
  log.debug('on_post_open')

  --- @type app.GUI050001
  local quest_accept_ui = thread.get_hook_storage()['quest_accept_ui']
  if quest_accept_ui == nil then
    log.debug('ERROR: quest_accept_ui is nil')
    return retval
  end

  local start_point_list = quest_accept_ui:get_CurrentStartPointList()
  -- Exit early if the list only has 1 item:
  if start_point_list == nil or start_point_list._size <= 1 then
    return retval
  end

  local target_pos = get_target_pos(quest_accept_ui)
  if target_pos == nil then
    return retval
  end

  local closest_start_point_index = get_closest_start_point_index(target_pos, start_point_list._items)
  if closest_start_point_index ~= nil and closest_start_point_index > 0 then
    quest_accept_ui:call('setCurrentSelectStartPointIndex(System.Int32)', closest_start_point_index)
  end
  return retval
end

local quest_accept_ui_t = sdk.find_type_definition('app.GUI050001')
sdk.hook(quest_accept_ui_t:get_method('onOpen()'), on_pre_open, on_post_open)

log.debug('Initialized ABC')

-- NOTES:

-- quest_accept_ui:incrementSelectStartPointIndex()

-- local sp = quest_accept_ui:getCurrentSelectStartPoint()
-- log.debug(tostring(sp == closest_start_point))
-- -- local delay = tonumber(os.clock() + 0.1)
-- -- while os.clock() < delay do end
-- -- quest_accept_ui:setSelectFloorFastTravelGmLocated(closest_start_point:get_BeaconGimmick())
-- local floor = quest_accept_ui:mapForceSelectFloor()
-- log.debug('maybe floor num: ' .. floor)

-- log.debug('closest start point:')
-- inspect(closest_start_point)

-- local ok, result = pcall(function() quest_accept_ui:call('setSelectFloorFastTravelGmLocated(app.cGUIBeaconBase)', closest_start_point:get_BeaconGimmick()) end)
-- if not ok then
--   log.debug('result ' .. tostring(result))
-- end

-- quest_accept_ui:mapForceSelectFloor()
-- quest_accept_ui:call('setActiveStartPointList(System.Boolean)', true)
-- local accept_list = quest_accept_ui._AcceptList
-- local input_ctrl = accept_list._InputCtrl
-- ace.cGUIInputCtrl_FluentItemsControlLink`2<app.GUIID.ID,app.GUIFunc.TYPE>
-- inspect(input_ctrl)
-- log.debug('currently selecting item at index ' .. tostring(input_ctrl:getSelectedIndex()))

-- ace.cGUIInputCtrl_FluentItemsControlLink`2<app.GUIID.ID,app.GUIFunc.TYPE>.mouseEvent(via.gui.MouseEventArgs)

-- app.GUI060008
-- get_GUIGround()

-- app.cGUIMapController.forceInteractBeacon(app.cGUIBeaconBase)

-- mapForceSelectFloor(System.Func`1<System.Int32>)


-- local quest_view_data = quest_accept_ui:get_QuestOrderParam().QuestViewData
-- --- @class app.cGUIMapController : REManagedObject
-- local map_controller = sdk.get_managed_singleton('app.GUIManager'):get_MAP3D()
-- map_controller:clearQuestBoardDummyIcon()
-- map_controller:setQuestBoardDummyIcon(quest_view_data)


-- quest_accept_ui:call('setActiveStartPointList(System.Boolean)', true)
-- local delay = tonumber(os.clock() + 0.1)
-- while os.clock() < delay do
--   -- log.debug('DELAYING')
-- end
-- quest_accept_ui:call('setActiveStartPointList(System.Boolean)', false)

-- quest_accept_ui:changeDarwSegmentDefault()
-- quest_accept_ui:call('clearStartPointGimmickDraw()')
-- quest_accept_ui:call('clearFocusStartPointIcon()')
-- quest_accept_ui:call('mapForceSelectFloor()')
-- quest_accept_ui:call('setActiveStartPointList(System.Boolean)', false)
-- quest_accept_ui:call('changeDrawSegmentForStartPointList()')
-- quest_accept_ui:setActiveStartPointList()
-- quest_accept_ui:updateState()
-- local accept_list = sdk.to_managed_object(quest_accept_ui:get_field('_AcceptList'))
-- accept_list._OptionalDisplayItem_StartPoint:decide()
-- updateStartPointText()
-- local gui_manager = sdk.get_managed_singleton('app.GUIManager')
-- gui_manager:call('requestMoveInputAcceptList()')
-- local ok, result = pcall(function()
--   -- quest_accept_ui:call('setActiveStartPointList(System.Boolean)', true)
--   -- quest_accept_ui:call('initStartPoint()')
--   -- quest_accept_ui:call('setFocusStartPointIcon(System.Int32)', index)
--   -- log.debug('SETTING FOCUS START POINT ICON')
--   -- quest_accept_ui:call('updateStartPointText()')
-- end)
-- if not ok then
--   log.debug('ERROR: Failed to set start point index. ' .. tostring(result))
-- end


-- local current_floor_num = map_controller:getCurrentStageFloorNum()
-- log.debug('current floor num: ' .. tostring(current_floor_num))
-- map_controller:setSelectFloor(floor)

-- current_floor_num = map_controller:getCurrentStageFloorNum()
-- log.debug('current floor num: ' .. tostring(current_floor_num))

-- map_controller:setSelectFloor(System.Int32)
-- setImmediateSelectFloor(System.Int32)
-- -- map_controller:call('forceInteractBeacon(app.cGUIBeaconBase)', closest_start_point:get_BeaconGimmick())
-- local map_ground = map_controller:get_GUIGround()
-- inspect(map_ground)

-- local floor_list = map_ground._FloorController._FloorListCtrl
-- inspect(floor_list)
-- floor_list:call('update()')

-- map_ground:clearColorSummary()
-- map_ground:applyColorSummary()
-- map_ground:updateSummary()
-- setSelectFloorFastTravelGmLocated(app.cGUIBeaconBase)
-- app.GUI050001.<>c__DisplayClass23_0.<setSelectFloorFastTravelGmLocated>b__0(System.Object, ace.GUIBaseCore)
-- updateRequestQuestEmArea(app.GUI060008.cRequestQuestEmArea)

-- app.cGUI3DMapFloorListController update()

-- _FloorListCtrl
-- app.cGUI3DMapStageModelController - app.GUI060008._FloorController

-- ace.cGUIInputCtrl`2<app.GUIID.ID,app.GUIFunc.TYPE>.onMouseDecide
-- input_ctrl:call('onMouseDecide(via.gui.SelectItem)', input_ctrl:getSelectedItem())
-- getItemFromListIndex(System.Int32, System.Int32)
-- funcMouseDecideEvent()
-- funcCancelEvent()

-- local fic_link = input_ctrl._FicLink
-- inspect(fic_link)
-- input_ctrl:call('changeItemIndexToFicIndex(System.UInt32)', closest_start_point_index)
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
-- local item = fls_list:call('getItemByGlobalIndex(System.Int32)', closest_start_point_index)
-- inspect(item)
-- input_ctrl:selectItemOnMouseEvent(item)
-- input_ctrl:call('selectItemOnMouseEvent(via.gui.SelectItem)', item)
-- selectItemOnMouseEvent(via.gui.SelectItem)
-- fls_list:set_SelectedIndex(closest_start_point_index)
-- input_ctrl:selectNextItem()

-- inspect(fls_list)
-- for k, v in pairs(fls_list) do
--   log.debug(tostring(k) .. ': ' .. tostring(v))
-- end

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

-- mapForceSelectFloor()
-- app.cGUIMapController.mapForceSelectFloor(System.Func`1<System.Int32>)

-- input_ctrl:changeItemNumFluent(closest_start_point_index)
-- changeItemNumFluent(System.UInt32, System.Boolean)

-- input_ctrl:funcMouseDecideEvent()
-- input_ctrl:executeCallback()
-- input_ctrl:requestCallDecide()
-- input_ctrl:funcDecideEvent()

-- via.gui.FluentItemsControlLink

-- callbackDecide(via.gui.Control, via.gui.SelectItem, System.UInt32)


-- _OptionalDisplayItem_StartPoint


-- local accept_list_panel = accept_list._RefWindowPanel
-- inspect(accept_list_panel)
-- ace.cSafeEvent`3.cElement<via.gui.Control,via.gui.SelectItem,System.UInt32>.execute(via.gui.Control, via.gui.SelectItem, System.UInt32)

-- local start_point_item = accept_list._OptionalDisplayItem_StartPoint
-- inspect(start_point_item)
-- local inputCtrl = accept_list._InputCtrl
-- inspect(inputCtrl)

-- local start_point_list = sdk.to_managed_object(quest_accept_ui:get_field('_StartPointList'))
-- accept_list:call('updateStartPointText()')
-- start_point_list:call('setActive(System.Boolean)', true)
