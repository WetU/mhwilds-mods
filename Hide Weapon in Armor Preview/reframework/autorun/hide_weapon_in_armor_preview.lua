local CONFIG_PATH = 'hide_weapon_in_armor_preview.json'

--- @class Config
--- @field isEnabled boolean
local config = {
  isEnabled = true,
}

local function save_config()
  json.dump_file(CONFIG_PATH, config)
end

--- @param input Config
--- @return boolean
local function is_valid_config(input)
  if not input then return false end
  if type(input.isEnabled) == 'boolean' then return false end
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

local PLAYER_MANAGER = sdk.get_managed_singleton('app.PlayerManager')

--- @param is_visible boolean
local function toggle_weapon_visibility(is_visible)
  log.info('[HideWeaponInArmorPreview] Toggling weapon visibility to ' .. tostring(is_visible))

  local player = PLAYER_MANAGER:getMasterPlayer()
  local hunter = player:get_Character()

  local weapons = {
    hunter:get_Weapon(),
    hunter:get_SubWeapon(),
    hunter:get_Wp10Insect(),
  }

  for _, weapon in pairs(weapons) do
    if weapon ~= nil then
      local game_object = weapon:get_GameObject()
      game_object:set_DrawSelf(is_visible)
    end
  end
end

local ARMOR_PREVIEW = sdk.find_type_definition('app.GUI080100')

local is_armor_preview_open = false

local function on_open_armor_preview()
  is_armor_preview_open = true
  if config.isEnabled then
    toggle_weapon_visibility(false)
  end
  return sdk.PreHookResult.CALL_ORIGINAL
end

local function on_close_armor_preview()
  is_armor_preview_open = false
  if config.isEnabled then
    toggle_weapon_visibility(true)
  end
  return sdk.PreHookResult.CALL_ORIGINAL
end

sdk.hook(ARMOR_PREVIEW:get_method('onOpenCore'), on_open_armor_preview, nil)
sdk.hook(ARMOR_PREVIEW:get_method('onCloseCore'), nil, on_close_armor_preview)

re.on_config_save(save_config)

re.on_draw_ui(function()
  if imgui.tree_node('Hide Weapon in Armor Preview') then
    local changed, isEnabled = imgui.checkbox('Enabled', config.isEnabled)
    if changed then
      if is_armor_preview_open then
        toggle_weapon_visibility(not isEnabled)
      end

      config.isEnabled = isEnabled
      save_config()
    end

    imgui.tree_pop()
  end
end)

log.info('[HideWeaponInArmorPreview] Initialized')
