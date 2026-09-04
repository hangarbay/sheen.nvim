-- Parses ANSI-styled text into plain lines plus buffer highlights,
-- so sheen's terminal rendering can live in a normal, scrollable buffer.
local M = {}

M.ns = vim.api.nvim_create_namespace("sheen.nvim")

local base_colors = {
  [0] = "#000000",
  [1] = "#cd0000",
  [2] = "#00cd00",
  [3] = "#cdcd00",
  [4] = "#0000ee",
  [5] = "#cd00cd",
  [6] = "#00cdcd",
  [7] = "#e5e5e5",
  [8] = "#7f7f7f",
  [9] = "#ff0000",
  [10] = "#00ff00",
  [11] = "#ffff00",
  [12] = "#5c5cff",
  [13] = "#ff00ff",
  [14] = "#00ffff",
  [15] = "#ffffff",
}

local cube_levels = { 0, 95, 135, 175, 215, 255 }

local function ansi_hex(code)
  if code < 16 then
    return base_colors[code]
  elseif code < 232 then
    local n = code - 16
    local r = math.floor(n / 36)
    local g = math.floor((n % 36) / 6)
    local b = n % 6
    return string.format("#%02x%02x%02x", cube_levels[r + 1], cube_levels[g + 1], cube_levels[b + 1])
  else
    local gray = math.min(8 + (code - 232) * 10, 238)
    return string.format("#%02x%02x%02x", gray, gray, gray)
  end
end

local hl_cache = {}
local hl_count = 0

local function hl_group(fg, bg, attrs)
  local key = string.format("%s|%s|%s", fg or "", bg or "", attrs)
  if hl_cache[key] then
    return hl_cache[key]
  end
  hl_count = hl_count + 1
  local group = "SheenHl" .. hl_count
  local spec = {}
  if fg then spec.fg = fg end
  if bg then spec.bg = bg end
  if attrs:find("b") then spec.bold = true end
  if attrs:find("i") then spec.italic = true end
  if attrs:find("u") then spec.underline = true end
  pcall(vim.api.nvim_set_hl, 0, group, spec)
  hl_cache[key] = group
  return group
end

local SGR = "\027%[([0-9;]*)m"

local function apply_sgr(codes, state)
  local nums = {}
  for num in codes:gmatch("[0-9]+") do
    nums[#nums + 1] = tonumber(num)
  end
  if #nums == 0 then
    nums = { 0 }
  end
  local i = 1
  while i <= #nums do
    local n = nums[i]
    if n == 0 then
      state.fg, state.bg = nil, nil
      state.bold, state.italic, state.underline = false, false, false
    elseif n == 1 then
      state.bold = true
    elseif n == 3 then
      state.italic = true
    elseif n == 4 then
      state.underline = true
    elseif n == 22 then
      state.bold = false
    elseif n == 23 then
      state.italic = false
    elseif n == 24 then
      state.underline = false
    elseif n >= 30 and n <= 37 then
      state.fg = base_colors[n - 30]
    elseif n == 38 or n == 48 then
      local kind = nums[i + 1]
      local color
      if kind == 5 and nums[i + 2] then
        color = ansi_hex(nums[i + 2])
        i = i + 2
      elseif kind == 2 and nums[i + 4] then
        color = string.format("#%02x%02x%02x", nums[i + 2], nums[i + 3], nums[i + 4])
        i = i + 4
      else
        i = i + 1
      end
      if color then
        if n == 38 then
          state.fg = color
        else
          state.bg = color
        end
      end
    elseif n == 39 then
      state.fg = nil
    elseif n >= 40 and n <= 47 then
      state.bg = base_colors[n - 40]
    elseif n == 49 then
      state.bg = nil
    elseif n >= 90 and n <= 97 then
      state.fg = base_colors[n - 90 + 8]
    elseif n >= 100 and n <= 107 then
      state.bg = base_colors[n - 100 + 8]
    end
    i = i + 1
  end
end

local function attrs_key(state)
  return (state.bold and "b" or "") .. (state.italic and "i" or "") .. (state.underline and "u" or "")
end

-- Returns { lines = {...}, marks = { {line, col0, col1, hl} } }
function M.parse(data)
  local lines = {}
  local marks = {}
  local pending = data or {}

  -- A trailing empty element is just the final newline
  if #pending > 1 and pending[#pending] == "" then
    pending[#pending] = nil
  end

  for _, raw in ipairs(pending) do
    raw = raw:gsub("\r", "")
      :gsub("\027%][^\007]*\007", "")
      :gsub("\027%][^\027]*\027\\", "")
      -- strip every CSI sequence except SGR (ending in 'm')
      :gsub("\027%[[0-9;:%?]*%a", function(seq)
        return seq:match("m$") and seq or ""
      end)
      :gsub("\027[^%[%]]", "")
      :gsub("\027$", "")

    local line_no = #lines + 1
    local state = { fg = nil, bg = nil, bold = false, italic = false, underline = false }
    local segs = {}
    local attrs = attrs_key(state)
    local seg0 = nil
    local vis_len = 0

    local function add_chunk(text)
      if #text == 0 then
        return
      end
      if seg0 ~= nil and (state.fg or state.bg or attrs ~= "") then
        marks[#marks + 1] = {
          line = line_no,
          col0 = seg0,
          col1 = vis_len + #text,
          hl = hl_group(state.fg, state.bg, attrs),
        }
      end
      segs[#segs + 1] = text
      vis_len = vis_len + #text
    end

    local pos = 1
    while pos <= #raw do
      local s, e, codes = raw:find(SGR, pos)
      if s then
        add_chunk(raw:sub(pos, s - 1))
        apply_sgr(codes, state)
        attrs = attrs_key(state)
        seg0 = vis_len
        pos = e + 1
      else
        add_chunk(raw:sub(pos))
        break
      end
    end

    lines[line_no] = table.concat(segs)
  end

  return lines, marks
end

function M.render(buf, data)
  if not (buf and vim.api.nvim_buf_is_valid(buf)) then
    return
  end
  local lines, marks = M.parse(data)
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_buf_clear_namespace(buf, M.ns, 0, -1)
  for _, m in ipairs(marks) do
    pcall(vim.api.nvim_buf_add_highlight, buf, M.ns, m.hl, m.line - 1, m.col0, m.col1)
  end
  vim.bo[buf].modifiable = false
end

return M
