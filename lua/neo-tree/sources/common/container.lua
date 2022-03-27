local utils = require("neo-tree.utils")

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
      container_width = math.floor(percent * config.available_width)
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
      local rendered_item = item(config, node, state)
      if rendered_item then
        table.insert(zindex_rendered[config.align or "left"], rendered_item)
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

local truncate_layer = function (layer, width)
  
end

local merge_content = function(context)
  local left = {}
  local right = {}
  local keys = utils.keys(context.grouped_by_zindex, true)
  local i = #keys
  while i > 0 do
    local key = keys[i]
    local layer = context.grouped_by_zindex[i]
    i = i - 1
    -- if it's not a list of items, make it one now
    if layer.text then
      layer = { layer }
      context.grouped_by_zindex[i] = layer
    end

    -- truncate or pad as needed, each layer should be exactly the same width
    local width = calc_container_width(layer)
    if width > context.container_width then
      layer = truncate_layer(layer, width)
    elseif layer > context.container_width then
      local pad_length = context.container_width - width
      local align = keys:match("^%d+-(%a+)$") or "left"
      local insert_at = align == "right" and 1 or nil
      table.insert(layer, {
        text = string.rep(" ", pad_length),
      }, insert_at)
    end
  end
end

M.render = function (config, node, state, available_width)
  local context = {
    max_width = 0,
    grouped_by_zindex = {},
    available_width = available_width,
  }

  render_content(config, node, state, context)
  calc_container_width(config, node, state, context)
  merge_content(context)

  return context.merged
end

return M
