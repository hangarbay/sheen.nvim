local M = {}

local ansi = require("sheen.ansi")

local defaults = {
  cmd = vim.fn.exepath("sheen") ~= "" and vim.fn.exepath("sheen") or "sheen",
  direction = "float",
  width_ratio = 0.8,
  height_ratio = 0.85,
  auto_open = true,
  style = nil, -- sheen style: "dark", "light", "notty", "ascii"; nil follows &background
  keymaps = {
    preview = "<leader>ch",
    close = "q",
  },
}

M.config = {}
local preview_win = nil
local preview_buf = nil
local last_file = nil
local job_id = nil
local resize_pending = false
local focus_restore_pending = false

local function is_html(file)
  return vim.bo.filetype == "html" or file:match("%.html$") or file:match("%.htm$")
end

local function close_preview()
  if job_id then
    pcall(vim.fn.jobstop, job_id)
    job_id = nil
  end
  if preview_win and vim.api.nvim_win_is_valid(preview_win) then
    vim.api.nvim_win_close(preview_win, true)
  end
  preview_win = nil
  preview_buf = nil
end

local function render_width()
  if not (preview_win and vim.api.nvim_win_is_valid(preview_win)) then
    return 80
  end
  return math.max(vim.api.nvim_win_get_width(preview_win) - 4, 20)
end

local function run_sheen(file)
  if job_id then
    pcall(vim.fn.jobstop, job_id)
    job_id = nil
  end
  if not (preview_buf and vim.api.nvim_buf_is_valid(preview_buf)) then
    return
  end
  last_file = file
  local style = M.config.style or (vim.o.background == "light" and "light" or "dark")
  local args = { M.config.cmd, "-s", style, "-w", tostring(render_width()), file }
  local opts = {
    stdout_buffered = true,
    on_stdout = function(_, data)
      ansi.render(preview_buf, data)
    end,
    on_exit = function()
      job_id = nil
    end,
  }
  -- sheen treats a piped stdin as the document; detach it so the file argument wins
  local ok, job = pcall(vim.fn.jobstart, args, vim.tbl_extend("force", opts, { stdin = "null" }))
  if not ok then
    job = vim.fn.jobstart(args, opts)
  end
  job_id = job
end

local function open_window()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
  vim.keymap.set("n", M.config.keymaps.close, close_preview, { buffer = buf, silent = true })

  if M.config.direction == "vertical" then
    local width = math.floor(vim.o.columns * M.config.width_ratio)
    vim.cmd("botright vsplit")
    vim.cmd("vertical resize " .. width)
    vim.api.nvim_win_set_buf(0, buf)
  else
    local width = math.floor(vim.o.columns * M.config.width_ratio)
    local height = math.floor(vim.o.lines * M.config.height_ratio)
    vim.api.nvim_open_win(buf, true, {
      relative = "editor",
      width = width,
      height = height,
      col = math.floor((vim.o.columns - width) / 2),
      row = math.floor((vim.o.lines - height) / 2),
      border = "rounded",
      style = "minimal",
    })
  end

  return buf
end

local function schedule_rerender()
  if resize_pending then return end
  resize_pending = true
  vim.defer_fn(function()
    resize_pending = false
    if preview_win and vim.api.nvim_win_is_valid(preview_win) and preview_buf and last_file then
      run_sheen(last_file)
    end
  end, 200)
end

function M.preview(path, o)
  local popts = o or {}
  local file = path and vim.fn.expand(path) or vim.fn.expand("%:p")
  if file == "" then
    vim.notify("sheen.nvim: no file to preview", vim.log.levels.WARN)
    return
  end
  if not is_html(file) then
    vim.notify("sheen.nvim: not an HTML file: " .. file, vim.log.levels.WARN)
    return
  end

  close_preview()

  local prev_win = vim.api.nvim_get_current_win()
  local buf = open_window()
  preview_buf = buf
  preview_win = vim.api.nvim_get_current_win()
  vim.api.nvim_create_autocmd("WinClosed", {
    pattern = tostring(preview_win),
    once = true,
    callback = function()
      if job_id then
        pcall(vim.fn.jobstop, job_id)
        job_id = nil
      end
      preview_win = nil
      preview_buf = nil
    end,
  })
  run_sheen(file)
  if vim.fn.has("nvim-0.9") == 1 then
    vim.api.nvim_create_autocmd("WinResized", {
      group = vim.api.nvim_create_augroup("sheen_nvim_resize", { clear = false }),
      callback = function(args)
        if preview_win and vim.tbl_contains(args.data.windows or {}, preview_win) then
          schedule_rerender()
        end
      end,
    })
  end

  if popts.keep_focus and vim.api.nvim_win_is_valid(prev_win) then
    focus_restore_pending = true
    vim.api.nvim_set_current_win(prev_win)
  end

  vim.api.nvim_create_autocmd("WinLeave", {
    buffer = buf,
    callback = function()
      if focus_restore_pending then
        return
      end
      vim.schedule(close_preview)
    end,
  })

  if focus_restore_pending then
    vim.schedule(function()
      focus_restore_pending = false
    end)
  end
end

function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", defaults, opts or {})
  local config = M.config

  vim.keymap.set("n", config.keymaps.preview, function() M.preview() end, {
    desc = "Preview HTML in sheen",
    silent = true,
  })
  vim.api.nvim_create_user_command("Sheen", function(o)
    M.preview(o.args ~= "" and o.args or nil)
  end, { nargs = "?", desc = "Preview HTML in sheen" })

  if config.auto_open then
    local group = vim.api.nvim_create_augroup("sheen_nvim_auto", { clear = true })
    vim.api.nvim_create_autocmd("FileType", {
      group = group,
      pattern = "html",
      callback = function()
        M.preview(nil, { keep_focus = true })
      end,
    })
    if vim.bo.filetype == "html" and vim.fn.expand("%:p") ~= "" then
      vim.schedule(function() M.preview(nil, { keep_focus = true }) end)
    end
  end
end

return M
