local utils = require("neo-tree.utils")
local renderer = require("neo-tree.ui.renderer")

local M = {}

local calc_rendered_width = function (rendered_item)
  local width = 0

  if rendered_item.text then
    width = math.max(width, #rendered_item.text)
  elseif type(rendered_item) == "table" then
    for _, item in ipairs(rendered_item) do
      if item.text then
        width = width + #item.text
      end
    end
  end

  return width
end

local calc_container_width = function(config, node, state, context)
  local container_width = 0
  if type(config.width) == "string" then
    if config.width == "fit_content" then
      container_width = context.max_width
    elseif config.width:match("^%d+%%$") then
      local percent = tonumber(config.width:sub(1, -2)) / 100
      container_width = math.floor(percent * context.available_width)
    else
      error("Invalid container width: " .. config.width)
    end
  elseif type(config.width) == "number" then
    container_width = config.width
  elseif type(config.width) == "function" then
    container_width = config.width(node, state)
  else
    error("Invalid container width: " .. config.width)
  end

  context.container_width = container_width
  return container_width
end

local render_content = function (config, node, state, context)
  local max_width = 0

  local grouped_by_zindex = utils.group_by(config.content, "zindex")
  for zindex, items in pairs(grouped_by_zindex) do
    local zindex_rendered = { left = {}, right = {} }
    local rendered_width = 0
    for _, item in ipairs(items) do
      local rendered_item = renderer.render_component(item, node, state, context.available_width)
      if item[1] == "git_status" and node.name == "container.lua" then
        print("git_status", vim.inspect(rendered_item))
      end
      if rendered_item then
        vim.list_extend(zindex_rendered[item.align or "left"], rendered_item)
        rendered_width = rendered_width + calc_rendered_width(rendered_item)
      end
    end
    max_width = math.max(max_width, rendered_width)
    grouped_by_zindex[zindex] = zindex_rendered
  end

  context.max_width = max_width
  context.grouped_by_zindex = grouped_by_zindex
  return context
end

---Takes a list of rendered components and truncates them to fit the container width
---@param layer table The list of rendered components.
---@param skip_count number The number of characters to skip from the begining/left.
---@param max_length number The maximum number of characters to return.
local truncate_layer_keep_left = function (layer, skip_count, max_length)
  local result = {}
  local taken = 0
  local skipped = 0
  for _, item in ipairs(layer) do
    local remaining_to_skip = skip_count - skipped
    if remaining_to_skip > 0 then
      if #item.text <= remaining_to_skip then
        skipped = skipped + #item.text
        item.text = ""
      else
        item.text = item.text:sub(remaining_to_skip + 1)
        if #item.text + taken > max_length then
          item.text = item.text:sub(1, max_length - taken)
        end
        table.insert(result, item)
        taken = taken + #item.text
        skipped = skipped + remaining_to_skip
      end
    elseif taken < max_length then
      if #item.text + taken > max_length then
        item.text = item.text:sub(1, max_length - taken)
      end
      table.insert(result, item)
      taken = taken + #item.text
    end
  end
  return result
end

---Takes a list of rendered components and truncates them to fit the container width
---@param layer table The list of rendered components.
---@param skip_count number The number of characters to skip from the end/right.
---@param max_length number The maximum number of characters to return.
local truncate_layer_keep_right = function (layer, skip_count, max_length)
  local result = {}
  local taken = 0
  local skipped = 0
  local i = #layer
  while i > 0 do
    local item = layer[i]
    i = i - 1
    local remaining_to_skip = skip_count - skipped
    if remaining_to_skip > 0 then
      if #item.text <= remaining_to_skip then
        skipped = skipped + #item.text
        item.text = ""
      else
        item.text = item.text:sub(1, #item.text - remaining_to_skip)
        if #item.text + taken > max_length then
          item.text = item.text:sub(#item.text - (max_length - taken))
        end
        table.insert(result, item)
        taken = taken + #item.text
        skipped = skipped + remaining_to_skip
      end
    elseif taken < max_length then
      if #item.text + taken > max_length then
        item.text = item.text:sub(#item.text - (max_length - taken))
      end
      table.insert(result, item)
      taken = taken + #item.text
    end
  end
  return result
end
local printed_count = 0
local merge_content = function(context)
  -- Heres the idea:
  -- * Starting backwards from the layer with the highest zindex
  --   set the left and right tables to the content of the layer
  -- * If a layer has more content than will fit, the left side will be truncated.
  -- * If the available space is not used up, move on to the next layer
  -- * With each subsequent layer, if the length of that layer is greater then the existing
  --   length for that side (left or right), then clip that layer and append whatver portion is
  --   not covered up to the appropriate side.
  -- * Check again to see if we have used up the available width, short circuit if we have.
  -- * Repeat until all layers have been merged.
  -- * Join the left and right tables together and return.
  --
  local remaining_width = context.container_width
  local left, right = {}, {}
  local left_width, right_width = 0, 0
  local keys = utils.get_keys(context.grouped_by_zindex, true)
  if type(keys) ~= "table" then
    return {}
  end
  local i = #keys
  while i > 0 do
    local key = keys[i]
    local layer = context.grouped_by_zindex[key]
    i = i - 1

    if remaining_width > 0 and utils.truthy(layer.right) then
      local width = calc_rendered_width(layer.right)
      if width > remaining_width then
        local truncated = truncate_layer_keep_right(layer.right, right_width, remaining_width)
        vim.list_extend(right, truncated)
        remaining_width = 0
      else
        remaining_width = remaining_width - width
        vim.list_extend(right, layer.right)
        right_width = right_width + width
      end
    end

    if remaining_width > 0 and utils.truthy(layer.left) then
      local width = calc_rendered_width(layer.left)
      if width > remaining_width then
        local truncated = truncate_layer_keep_left(layer.left, left_width, remaining_width)
        vim.list_extend(left, truncated)
        remaining_width = 0
      else
        remaining_width = remaining_width - width
        vim.list_extend(left, layer.left)
        left_width = left_width + width
      end
    end

    if remaining_width == 0 then
      i = 0
      break
    end
  end

  local result = {}
  vim.list_extend(result, left)
  vim.list_extend(result, right)
  if printed_count < 3 and #right > 0 then
    print(vim.inspect(context.grouped_by_zindex))
    print(vim.inspect(result))
    printed_count = printed_count + 1
  end
  return result
end

M.render = function (config, node, state, available_width)
  local context = {
    max_width = 0,
    grouped_by_zindex = {},
    available_width = available_width,
  }

  render_content(config, node, state, context)
  calc_container_width(config, node, state, context)
  return merge_content(context)
end

return M
