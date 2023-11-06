local M = {}

local require = require('lualine_require').require
local utils = require('lualine.utils.utils')

-- vars
local current_hg_branch = ''
local current_hg_dir = ''
local branch_cache = {} -- stores last known branch for a buffer
local active_bufnr = '0'
-- os specific path separator
local sep = package.config:sub(1, 1)

-- event watcher to watch head file
-- Use file watch for non Windows and poll for Windows.
-- Windows doesn't like file watch for some reason.
local file_changed = sep ~= '\\' and vim.loop.new_fs_event() or vim.loop.new_fs_poll()
local hg_dir_cache = {} -- Stores hg paths that we already know of

---sets hg_branch variable to branch name or commit hash if not on branch
---@param branch_file string full path of .hg/branch file
local function get_hg_branch(branch_file)
  local f_branch = io.open(branch_file)
  if f_branch then
    current_hg_branch = f_branch:read()
    f_branch:close()
  end
  return nil
end

---updates the current value of hg_branch and sets up file watch on branch file
local function update_branch()
  active_bufnr = tostring(vim.api.nvim_get_current_buf())
  file_changed:stop()
  local hg_dir = current_hg_dir
  if hg_dir and #hg_dir > 0 then
    local branch_file = hg_dir .. sep .. 'branch'
    get_hg_branch(branch_file)
    file_changed:start(
      branch_file,
      sep ~= '\\' and {} or 1000,
      vim.schedule_wrap(function()
        -- reset file-watch
        update_branch()
      end)
    )
  else
    -- set to '' when hg dir was not found
    current_hg_branch = ''
  end
  branch_cache[vim.api.nvim_get_current_buf()] = current_hg_branch
end

---updates the current value of current_hg_branch and sets up file watch on branch file if value changed
local function update_current_hg_dir(hg_dir)
  if current_hg_dir ~= hg_dir then
    current_hg_dir = hg_dir
    update_branch()
  end
end

---returns full path to hg directory for dir_path or current directory
---@param dir_path string|nil
---@return string|nil
function M.find_hg_dir(dir_path)
  local hg_dir = vim.env.HG_DIR
  if hg_dir then
    update_current_hg_dir(hg_dir)
    return hg_dir
  end

  -- get file dir so we can search from that dir
  local file_dir = dir_path or vim.fn.expand('%:p:h')
  local root_dir = file_dir
  -- Search upward for .hg file or folder
  while root_dir do
    if hg_dir_cache[root_dir] then
      hg_dir = hg_dir_cache[root_dir]
      break
    end
    local hg_path = root_dir .. sep .. '.hg'
    local hg_file_stat = vim.loop.fs_stat(hg_path)
    if hg_file_stat then
      if hg_file_stat.type == 'directory' then
        hg_dir = hg_path
      end
      if hg_dir then
        local branch_file_stat = vim.loop.fs_stat(hg_dir .. sep .. 'branch')
        if branch_file_stat and branch_file_stat.type == 'file' then
          break
        else
          hg_dir = nil
        end
      end
    end
    root_dir = root_dir:match('(.*)' .. sep .. '.-')
  end

  hg_dir_cache[file_dir] = hg_dir
  if dir_path == nil then
    update_current_hg_dir(hg_dir)
  end
  return hg_dir
end

---initializes git_branch module
function M.init()
  -- run watch head on load so branch is present when component is loaded
  M.find_hg_dir()
  -- update branch state of BufEnter as different Buffer may be on different repos
  utils.define_autocmd('BufEnter', "lua require'lualine.components.branch.hg_branch'.find_hg_dir()")
end
function M.get_branch(bufnr)
  if vim.g.actual_curbuf ~= nil and active_bufnr ~= vim.g.actual_curbuf then
    -- Workaround for https://github.com/nvim-lualine/lualine.nvim/issues/286
    -- See upstream issue https://github.com/neovim/neovim/issues/15300
    -- Diff is out of sync re sync it.
    M.find_hg_dir()
  end
  if bufnr then
    return branch_cache[bufnr] or ''
  end
  return current_hg_branch
end

return M
