---sidecar.nvim — run a CLI coding agent in a terminal split.
---
---One toggle key controls the active tool, and a switch key cycles tools.
---Add-buffer/send-selection broadcast to every running tool at once. Terminal-only:
---no websocket or MCP diff protocol, so it works identically for both CLIs.
---@module 'sidecar'

local M = {}

---@class SidecarToolConfig
---@field cmd string|string[] Command to launch the CLI

M.config = {
  ---@type table<string, SidecarToolConfig>
  tools = {
    claude = { cmd = "claude" },
    codex = { cmd = "codex" },
  },
  active = "claude", -- default tool: opened when a send/toggle happens with none open
  remember_active = true, -- restore the last selected tool for this working directory
  state_dir = nil, -- defaults to stdpath("state")/sidecar.nvim
  history = {
    enabled = true, -- if no Sidecar state exists, infer claude/codex from session activity
    claude_dir = nil, -- defaults to $CLAUDE_CONFIG_DIR/projects or ~/.claude/projects
    codex_dir = nil, -- defaults to $CODEX_HOME/sessions or ~/.codex/sessions
  },
  split_side = "right", -- "right" | "left"
  split_width = 0.40, -- fraction of columns
  file_mention = "@%s ", -- how ,ab/,as reference files and selected line ranges
  keymaps = {
    toggle = "<leader>ac", -- open/focus/collapse the active tool
    switch = "<leader>at", -- cycle the active tool; replace its panel if visible
    toggles = {}, -- optional direct per-tool toggle keys
    add_buffer = "<leader>ab", -- send current file to every running tool
    send = "<leader>as", -- (visual) send selection to every running tool
  },
}
-- Scrolling the CLIs' history: neither Claude nor Codex enables terminal mouse
-- tracking, and (in default, non-fullscreen mode) both commit output to the
-- terminal scrollback. So scroll natively — enter terminal-normal mode and use
-- k/j, <C-u>/<C-d>, gg/G. No injected escape sequences are needed.

-- Per-tool terminal state: terms[tool] = { bufnr, winid, jobid }
local terms = {}

local function active_state_path()
  local dir = M.config.state_dir or (vim.fn.stdpath("state") .. "/sidecar.nvim")
  local cwd = vim.fn.fnamemodify(vim.fn.getcwd(), ":p")
  return dir, dir .. "/" .. vim.fn.sha256(cwd) .. ".active"
end

local function persist_active(tool)
  if not M.config.remember_active then
    return
  end
  local dir, path = active_state_path()
  local ok, result = pcall(vim.fn.mkdir, dir, "p")
  if not ok or (result == 0 and vim.fn.isdirectory(dir) ~= 1) then
    vim.notify("sidecar: failed to create the active-tool state directory", vim.log.levels.WARN)
    return
  end
  ok, result = pcall(vim.fn.writefile, { tool }, path)
  if not ok or result ~= 0 then
    vim.notify("sidecar: failed to remember the active tool", vim.log.levels.WARN)
  end
end

local function restore_active()
  if not M.config.remember_active then
    return
  end
  local _, path = active_state_path()
  if vim.fn.filereadable(path) ~= 1 then
    return
  end
  local ok, lines = pcall(vim.fn.readfile, path, "", 1)
  local tool = ok and lines[1] or nil
  if tool and M.config.tools[tool] then
    M.config.active = tool
    return true
  end
  return false
end

local function normalized_path(path)
  local absolute = vim.fn.fnamemodify(path, ":p")
  return vim.fs.normalize(vim.uv.fs_realpath(absolute) or absolute)
end

local function jsonl_files(root)
  local files = {}
  if vim.fn.isdirectory(root) ~= 1 then
    return files
  end

  local function walk(dir)
    local ok, iterator = pcall(vim.fs.dir, dir)
    if not ok or not iterator then
      return
    end
    for name, kind in iterator do
      local path = dir .. "/" .. name
      if kind == "directory" then
        walk(path)
      elseif kind == "file" and name:sub(-6) == ".jsonl" then
        files[#files + 1] = path
      end
    end
  end

  walk(root)
  return files
end

local function file_matches_cwd(path, cwd, format)
  local file = io.open(path, "r")
  if not file then
    return false
  end

  -- Codex writes session_meta first. Claude usually writes cwd on its first user
  -- record, after a small number of metadata/snapshot records. Keep the read
  -- bounded so startup never scans conversation bodies.
  local max_lines = format == "codex" and 8 or 64
  for _ = 1, max_lines do
    local line = file:read("*l")
    if not line then
      break
    end
    local ok, record = pcall(vim.json.decode, line)
    if ok and type(record) == "table" then
      local record_cwd
      if format == "codex" and record.type == "session_meta" and type(record.payload) == "table" then
        record_cwd = record.payload.cwd
      elseif format == "claude" then
        record_cwd = record.cwd
      end
      if type(record_cwd) == "string" and normalized_path(record_cwd) == cwd then
        file:close()
        return true
      end
    end
  end
  file:close()
  return false
end

local function latest_session_mtime(root, cwd, format)
  local candidates = {}
  for _, path in ipairs(jsonl_files(root)) do
    local stat = vim.uv.fs_stat(path)
    if stat and stat.mtime then
      candidates[#candidates + 1] = {
        path = path,
        mtime = stat.mtime.sec + (stat.mtime.nsec or 0) / 1000000000,
      }
    end
  end
  table.sort(candidates, function(a, b) return a.mtime > b.mtime end)
  for _, candidate in ipairs(candidates) do
    if file_matches_cwd(candidate.path, cwd, format) then
      return candidate.mtime
    end
  end
  return nil
end

local function detect_active_from_history()
  local history = M.config.history or {}
  if history.enabled == false or not M.config.tools.claude or not M.config.tools.codex then
    return false
  end

  local home = vim.fn.expand("~")
  local claude_config = vim.env.CLAUDE_CONFIG_DIR or (home .. "/.claude")
  local codex_config = vim.env.CODEX_HOME or (home .. "/.codex")
  local cwd = normalized_path(vim.fn.getcwd())
  local encoded_cwd = cwd:gsub("[^%w]", "-")
  local claude_projects = history.claude_dir or (claude_config .. "/projects")
  local claude_project = claude_projects .. "/" .. encoded_cwd
  -- Verify cwd inside each file because Claude's path encoding can collide.
  local claude_root = vim.fn.isdirectory(claude_project) == 1 and claude_project or claude_projects
  local codex_root = history.codex_dir or (codex_config .. "/sessions")

  local claude_mtime = latest_session_mtime(claude_root, cwd, "claude")
  local codex_mtime = latest_session_mtime(codex_root, cwd, "codex")
  if not claude_mtime and not codex_mtime then
    return false
  end
  if codex_mtime and (not claude_mtime or codex_mtime > claude_mtime) then
    M.config.active = "codex"
  else
    M.config.active = "claude"
  end
  return true
end

local function select_tool(tool)
  if not M.config.tools[tool] then
    return false
  end
  M.config.active = tool
  persist_active(tool)
  return true
end

--- Pure helpers (exposed for tests) --------------------------------------------

--- Strip control characters (newlines, carriage returns, ESC, …) from a path.
--- File mentions are sent unwrapped, so a crafted filename containing a newline
--- or paste escape could otherwise inject a submit.
---@param path string
---@return string
function M._sanitize_path(path)
  return (path:gsub("[%z\1-\31]", ""))
end

---@param path string
---@return string
function M._mention(path)
  return string.format(M.config.file_mention, M._sanitize_path(path))
end

--- Format a file mention for an inclusive line range.
---@param path string
---@param start_line integer
---@param end_line integer
---@return string
function M._line_reference(path, start_line, end_line)
  start_line, end_line = math.min(start_line, end_line), math.max(start_line, end_line)
  local range = start_line == end_line and tostring(start_line) or ("%d-%d"):format(start_line, end_line)
  return M._mention(("%s#%s"):format(path, range))
end

--- Terminal plumbing -----------------------------------------------------------

local function win_showing(bufnr)
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(win) == bufnr then
      return win
    end
  end
  return nil
end

local function new_split()
  local width = math.floor(vim.o.columns * M.config.split_width)
  local mod = M.config.split_side == "left" and "topleft " or "botright "
  vim.cmd(mod .. width .. "vsplit")
  return vim.api.nvim_get_current_win()
end

--- Focus a terminal window, resuming the live input when requested.
---
--- Root cause of the "scroll jumps to bottom on focus regain" bug: entering
--- terminal-insert mode (`startinsert`) always scrolls a terminal to its newest
--- output — that is a hard Neovim invariant. A terminal hidden from insert mode
--- should do exactly that so new agent output does not leave its old input cursor
--- in the middle of the restored view. Otherwise, only start insert mode when the
--- view is already at the bottom; a deliberately scrolled-up normal-mode view is
--- preserved.
---@param winid integer
---@param resume_insert boolean|nil
local function focus_win(winid, resume_insert)
  if resume_insert then
    local bufnr = vim.api.nvim_win_get_buf(winid)
    vim.api.nvim_win_set_cursor(winid, { vim.api.nvim_buf_line_count(bufnr), 0 })
  end
  local at_bottom = resume_insert or vim.api.nvim_win_call(winid, function()
    return vim.fn.line("w$") >= vim.fn.line("$")
  end)
  vim.api.nvim_set_current_win(winid)
  if at_bottom then
    vim.cmd("startinsert")
  end
end

local function hide(t)
  if t.winid and vim.api.nvim_win_is_valid(t.winid) then
    -- Remember whether this terminal was actively accepting input. If output
    -- arrives while hidden, that intent is more important than the now-stale
    -- cursor/view coordinates captured below.
    t.resume_insert = vim.api.nvim_get_current_win() == t.winid and vim.fn.mode() == "t"
    -- Remember scroll + cursor before dropping the window. winsaveview()
    -- captures topline, lnum and col, so re-showing can land on the exact same
    -- view instead of snapping to the bottom/input line when reading scrollback.
    t.view = vim.api.nvim_win_call(t.winid, vim.fn.winsaveview)
    vim.api.nvim_win_close(t.winid, false) -- keep buffer + job alive
  end
  t.winid = nil
end

--- Ensure the tool's terminal exists and is shown. Returns the state table.
---@param tool string
---@param focus boolean
---@return table|nil
local function open(tool, focus)
  local spec = M.config.tools[tool]
  if not spec then
    vim.notify("sidecar: unknown tool '" .. tostring(tool) .. "'", vim.log.levels.ERROR)
    return nil
  end

  local t = terms[tool]
  local orig = vim.api.nvim_get_current_win()

  -- Existing process: reuse the buffer.
  if t and vim.api.nvim_buf_is_valid(t.bufnr) then
    local win = win_showing(t.bufnr)
    local was_hidden = not win
    if win then
      t.winid = win
    else
      t.winid = new_split()
      vim.api.nvim_win_set_buf(t.winid, t.bufnr)
      -- Restore a deliberately scrolled-up terminal-normal view. For a terminal
      -- hidden from insert mode, the saved cursor is stale once new output
      -- arrives, so focus_win() resumes at the live input instead.
      if t.view and not t.resume_insert then
        vim.api.nvim_win_call(t.winid, function()
          vim.fn.winrestview(t.view)
        end)
      end
    end
    if focus then
      focus_win(t.winid, was_hidden and t.resume_insert)
    else
      vim.api.nvim_set_current_win(orig)
    end
    return t
  end

  -- Fresh terminal.
  local winid = new_split()
  vim.cmd("enew")
  local jobid = vim.fn.termopen(spec.cmd, {
    on_exit = function(_, code)
      vim.schedule(function()
        local cur = terms[tool]
        if not cur then
          return
        end
        terms[tool] = nil
        -- Non-zero exit usually means the CLI errored (bad auth, crash, …).
        -- Keep the terminal buffer + window so its error output stays on
        -- screen instead of the window vanishing with no message.
        if code ~= 0 then
          vim.notify(
            ("sidecar: %s exited (code %d) — see the terminal for the message"):format(tool, code),
            vim.log.levels.WARN
          )
          return
        end
        hide(cur)
        if cur.bufnr and vim.api.nvim_buf_is_valid(cur.bufnr) then
          pcall(vim.api.nvim_buf_delete, cur.bufnr, { force = true })
        end
      end)
    end,
  })
  if not jobid or jobid <= 0 then
    vim.notify("sidecar: failed to launch " .. tool, vim.log.levels.ERROR)
    vim.api.nvim_win_close(winid, true)
    vim.api.nvim_set_current_win(orig)
    return nil
  end

  local bufnr = vim.api.nvim_get_current_buf()
  vim.bo[bufnr].bufhidden = "hide"
  -- Unlisted, like other terminal toggles: keeps the agent out of bufferlines
  -- and out of "delete all buffers" sweeps, which only walk listed buffers.
  vim.bo[bufnr].buflisted = false
  t = { bufnr = bufnr, winid = winid, jobid = jobid }
  terms[tool] = t

  if focus then
    vim.cmd("startinsert")
  else
    vim.api.nvim_set_current_win(orig)
  end
  return t
end

--- Get a file-and-line reference for the current visual selection.
---@return string|nil reference
---@return string|nil error_message
local function visual_reference()
  local mode = vim.fn.mode()
  if mode ~= "v" and mode ~= "V" and mode ~= "\22" then
    return nil
  end

  local path = vim.fn.expand("%:.")
  if not path or path == "" then
    return nil, "sidecar: current buffer has no file"
  end
  path = vim.fn.fnamemodify(path, ":.")

  local visual_line = vim.fn.getpos("v")[2]
  local cursor_line = vim.fn.getpos(".")[2]
  return M._line_reference(path, visual_line, cursor_line)
end

--- Public API -----------------------------------------------------------------

---@param tool string|nil defaults to the active tool
function M.toggle(tool)
  if tool then
    select_tool(tool)
  elseif M.config.tools[M.config.active] then
    persist_active(M.config.active)
  end
  tool = tool or M.config.active
  local t = terms[tool]
  if t and vim.api.nvim_buf_is_valid(t.bufnr) then
    local win = win_showing(t.bufnr)
    if win then
      if win == vim.api.nvim_get_current_win() then
        hide(t) -- we're in it -> hide
      else
        t.winid = win
        focus_win(win) -- visible elsewhere -> focus
      end
      return
    end
  end
  open(tool, true) -- hidden or nonexistent -> show + focus
end

---@param tool string|nil
function M.focus(tool)
  if tool then
    select_tool(tool)
  elseif M.config.tools[M.config.active] then
    persist_active(M.config.active)
  end
  open(tool or M.config.active, true)
end

--- Select the next configured tool. If the active tool's panel is visible,
--- replace it with the newly-selected tool; otherwise keep the panel collapsed.
---@return string|nil tool
function M.switch()
  local tools = {}
  for name in pairs(M.config.tools) do
    tools[#tools + 1] = name
  end
  table.sort(tools)

  if #tools == 0 then
    vim.notify("sidecar: no tools configured", vim.log.levels.WARN)
    return nil
  end
  if #tools == 1 then
    select_tool(tools[1])
    vim.notify("sidecar: only one tool configured (" .. tools[1] .. ")", vim.log.levels.INFO)
    return tools[1]
  end

  local current_index = 0
  for i, name in ipairs(tools) do
    if name == M.config.active then
      current_index = i
      break
    end
  end
  local next_tool = tools[(current_index % #tools) + 1]

  local current = terms[M.config.active]
  local current_win = current and win_showing(current.bufnr)
  if current_win then
    current.winid = current_win
    hide(current)
  end

  select_tool(next_tool)
  if current_win then
    open(next_tool, true)
  end
  vim.notify("sidecar: active tool: " .. next_tool, vim.log.levels.INFO)
  return next_tool
end

--- If the cursor is in a supported file-tree buffer, return the path under it.
---@return string|nil
local function tree_file()
  local ft = vim.bo.filetype
  if ft == "NvimTree" then
    local ok, api = pcall(require, "nvim-tree.api")
    if not ok then return nil end
    local node = api.tree.get_node_under_cursor()
    if node and node.absolute_path and node.absolute_path ~= "" then
      return node.absolute_path
    end
  elseif ft == "oil" then
    local ok, oil = pcall(require, "oil")
    if not ok then return nil end
    local entry = oil.get_cursor_entry()
    local dir = oil.get_current_dir()
    if entry and dir and entry.name ~= ".." and entry.name ~= "." then
      return dir .. entry.name
    end
  end
  return nil
end

--- Tools with a live terminal (running job), regardless of whether their window
--- is currently visible. Sorted for deterministic ordering.
---@return string[]
local function running_tools()
  local out = {}
  for name in pairs(M.config.tools) do
    local t = terms[name]
    if t and t.jobid and vim.api.nvim_buf_is_valid(t.bufnr) then
      out[#out + 1] = name
    end
  end
  table.sort(out)
  return out
end

--- Send a payload to every running tool. If none are running, open the default
--- tool and send to just that one, so the shortcut is never a no-op. Optionally
--- reopen hidden terminals and focus the active (or first) reopened tool.
---@param payload string
---@param reveal_hidden boolean|nil
local function broadcast(payload, reveal_hidden)
  local targets = running_tools()
  if #targets == 0 then
    persist_active(M.config.active)
    local t = open(M.config.active, true) -- nothing open -> start the default tool
    if t then
      vim.api.nvim_chan_send(t.jobid, payload)
    end
    return
  end

  local reopened = {}
  if reveal_hidden then
    for _, name in ipairs(targets) do
      local t = terms[name]
      if not win_showing(t.bufnr) and open(name, false) then
        reopened[#reopened + 1] = name
      end
    end
  end

  for _, name in ipairs(targets) do
    vim.api.nvim_chan_send(terms[name].jobid, payload) -- send without stealing focus
  end

  if #reopened > 0 then
    local t = terms[M.config.active]
    local win = t and win_showing(t.bufnr)
    if not win then
      t = terms[reopened[1]]
      win = win_showing(t.bufnr)
    end
    if win then
      t.winid = win
      focus_win(win, t.resume_insert)
    end
  end
end

--- Send a file mention (`@path`) to every running tool. Uses the node under the
--- cursor in nvim-tree/oil, otherwise the current buffer's file. Hidden terminals
--- are reopened so the inserted reference is visible for review.
function M.add_buffer()
  local path = tree_file() or vim.fn.expand("%:.")
  if not path or path == "" then
    vim.notify("sidecar: no file under cursor", vim.log.levels.WARN)
    return
  end
  path = vim.fn.fnamemodify(path, ":.") -- relative to cwd
  broadcast(M._mention(path), true)
end

--- Send the selected file and inclusive line range to every running tool. Hidden
--- terminals are reopened so the inserted reference is visible for review.
function M.send_selection()
  local reference, err = visual_reference()
  if not reference then
    if err then
      vim.notify(err, vim.log.levels.WARN)
    end
    return
  end
  broadcast(reference, true)
end

---@param opts table|nil
function M.setup(opts)
  opts = opts or {}
  M.config = vim.tbl_deep_extend("force", M.config, opts)
  -- `tools` replaces rather than deep-merges: the table you pass is the exact set
  -- of agents, so `tools = { aider = ... }` drops the claude/codex defaults
  -- instead of adding a third agent alongside them.
  if opts.tools then
    M.config.tools = opts.tools
  end
  if not restore_active() then
    detect_active_from_history()
  end

  vim.api.nvim_create_user_command("Sidecar", function(a)
    M.toggle(a.args ~= "" and a.args or nil)
  end, { nargs = "?", desc = "Toggle Claude/Codex terminal", force = true })
  vim.api.nvim_create_user_command("SidecarSwitch", M.switch, { desc = "Switch active tool", force = true })
  vim.api.nvim_create_user_command("SidecarAdd", M.add_buffer, { desc = "Add current buffer", force = true })

  local k = M.config.keymaps
  local map = vim.keymap.set
  -- Per-tool toggles: each key opens/focuses its own tool and makes it active.
  for tool, lhs in pairs(k.toggles or {}) do
    if lhs then
      local function fn()
        M.toggle(tool)
      end
      map("n", lhs, fn, { desc = "Toggle " .. tool })
      map("t", lhs, fn, { desc = "Toggle " .. tool })
    end
  end
  -- Shared keys toggle whichever tool is active and cycle the active selection.
  if k.toggle then
    map("n", k.toggle, function() M.toggle() end, { desc = "Toggle active tool" })
    map("t", k.toggle, function() M.toggle() end, { desc = "Toggle active tool" })
  end
  if k.switch then
    map("n", k.switch, M.switch, { desc = "Switch active tool" })
    map("t", k.switch, M.switch, { desc = "Switch active tool" })
  end
  if k.add_buffer then
    map("n", k.add_buffer, M.add_buffer, { desc = "Add buffer to open tools" })
  end
  if k.send then
    map("v", k.send, M.send_selection, { desc = "Send selection to open tools" })
  end
end

return M
