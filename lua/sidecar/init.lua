---sidecar.nvim — run a CLI coding agent in a terminal split.
---
---Each tool has its own toggle key; add-buffer/send-selection broadcast to every
---open tool at once. Terminal-only: no websocket or MCP diff protocol, so it
---works identically for both CLIs.
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
  split_side = "right", -- "right" | "left"
  split_width = 0.40, -- fraction of columns
  file_mention = "@%s ", -- how ,ab references the current file
  keymaps = {
    -- Per-tool toggle: open/focus a specific tool directly. Opening a tool also
    -- makes it active, so the shared add_buffer/send below target whatever you
    -- last opened. Set an entry to false to disable that tool's key.
    toggles = {
      claude = "<leader>ac",
      codex = "<leader>ax",
    },
    toggle = false, -- optional: one key that toggles the default tool (set a lhs to enable)
    add_buffer = "<leader>ab", -- send current file to every open tool
    send = "<leader>as", -- (visual) send selection to every open tool
  },
}
-- Scrolling the CLIs' history: neither Claude nor Codex enables terminal mouse
-- tracking, and (in default, non-fullscreen mode) both commit output to the
-- terminal scrollback. So scroll natively — enter terminal-normal mode and use
-- k/j, <C-u>/<C-d>, gg/G. No injected escape sequences are needed.

-- Per-tool terminal state: terms[tool] = { bufnr, winid, jobid }
local terms = {}

--- Pure helpers (exposed for tests) --------------------------------------------

--- Wrap text in bracketed-paste escapes so multi-line text lands as one block
--- in the CLI prompt instead of each newline submitting the line.
---
--- Any bracketed-paste delimiter already present in `text` is stripped first: a
--- literal ESC[201~ inside the selection would end paste mode early and let the
--- following newline submit, defeating the "never auto-submit" guarantee.
---@param text string
---@return string
function M._wrap_paste(text)
  local clean = text:gsub("\27%[20[01]~", "")
  return "\27[200~" .. clean .. "\27[201~"
end

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

--- Focus a terminal window WITHOUT snapping it to the bottom.
---
--- Root cause of the "scroll jumps to bottom on focus regain" bug: entering
--- terminal-insert mode (`startinsert`) always scrolls a terminal to its newest
--- output — that is a hard Neovim invariant. So we only start insert mode when
--- the view is already at the bottom (i.e. the user was following output). If
--- the user scrolled up in normal mode, we stay in normal mode and keep their
--- view, preserving scrollback across focus-out/focus-in.
local function focus_win(winid)
  local at_bottom = vim.api.nvim_win_call(winid, function()
    return vim.fn.line("w$") >= vim.fn.line("$")
  end)
  vim.api.nvim_set_current_win(winid)
  if at_bottom then
    vim.cmd("startinsert")
  end
end

local function hide(t)
  if t.winid and vim.api.nvim_win_is_valid(t.winid) then
    -- Remember scroll + cursor before dropping the window. winsaveview()
    -- captures topline, lnum and col, so re-showing can land on the exact same
    -- view instead of snapping to the bottom/input line.
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
    if win then
      t.winid = win
    else
      t.winid = new_split()
      vim.api.nvim_win_set_buf(t.winid, t.bufnr)
      -- Restore the view captured on hide() so scroll + cursor survive a
      -- toggle-away/toggle-back. focus_win() then sees the restored (possibly
      -- scrolled-up) position and keeps normal mode instead of snapping to the
      -- input line and starting insert.
      if t.view then
        vim.api.nvim_win_call(t.winid, function()
          vim.fn.winrestview(t.view)
        end)
      end
    end
    if focus then
      focus_win(t.winid)
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
  t = { bufnr = bufnr, winid = winid, jobid = jobid }
  terms[tool] = t

  if focus then
    vim.cmd("startinsert")
  else
    vim.api.nvim_set_current_win(orig)
  end
  return t
end

--- Get the currently-selected visual text (works while still in visual mode).
---@return string
local function visual_selection()
  local mode = vim.fn.mode()
  if mode ~= "v" and mode ~= "V" and mode ~= "\22" then
    return ""
  end
  local lines = vim.fn.getregion(vim.fn.getpos("v"), vim.fn.getpos("."), { type = mode })
  return table.concat(lines, "\n")
end

--- Public API -----------------------------------------------------------------

---@param tool string|nil defaults to the active tool
function M.toggle(tool)
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
  open(tool or M.config.active, true)
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

--- Send a payload to every open tool. If none are open, open the default tool
--- (M.config.active) and send to just that one, so the shortcut is never a no-op.
---@param payload string
local function broadcast(payload)
  local targets = running_tools()
  if #targets == 0 then
    local t = open(M.config.active, true) -- nothing open -> start the default tool
    if t then
      vim.api.nvim_chan_send(t.jobid, payload)
    end
    return
  end
  for _, name in ipairs(targets) do
    vim.api.nvim_chan_send(terms[name].jobid, payload) -- send without stealing focus
  end
end

--- Send a file as a file mention (`@path`) to every open tool. Uses the node
--- under the cursor in nvim-tree/oil, otherwise the current buffer's file.
function M.add_buffer()
  local path = tree_file() or vim.fn.expand("%:.")
  if not path or path == "" then
    vim.notify("sidecar: no file under cursor", vim.log.levels.WARN)
    return
  end
  path = vim.fn.fnamemodify(path, ":.") -- relative to cwd
  broadcast(M._mention(path))
end

--- Send the visual selection as a pasted block (no submit) to every open tool.
function M.send_selection()
  local text = visual_selection()
  if text == "" then
    return
  end
  broadcast(M._wrap_paste(text))
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

  vim.api.nvim_create_user_command("Sidecar", function(a)
    M.toggle(a.args ~= "" and a.args or nil)
  end, { nargs = "?", desc = "Toggle Claude/Codex terminal" })
  vim.api.nvim_create_user_command("SidecarAdd", M.add_buffer, { desc = "Add current buffer" })

  local k = M.config.keymaps
  local map = vim.keymap.set
  -- Per-tool toggles: each key opens/focuses its own tool and makes it active.
  for tool, lhs in pairs(k.toggles or {}) do
    if lhs then
      local function fn()
        M.config.active = tool -- remember last-opened tool as the send fallback default
        M.toggle(tool)
      end
      map("n", lhs, fn, { desc = "Toggle " .. tool })
      map("t", lhs, fn, { desc = "Toggle " .. tool })
    end
  end
  -- Optional single key that toggles whichever tool is currently active.
  if k.toggle then
    map("n", k.toggle, function() M.toggle() end, { desc = "Toggle active tool" })
    map("t", k.toggle, function() M.toggle() end, { desc = "Toggle active tool" })
  end
  if k.add_buffer then
    map("n", k.add_buffer, M.add_buffer, { desc = "Add buffer to open tools" })
  end
  if k.send then
    map("v", k.send, M.send_selection, { desc = "Send selection to open tools" })
  end
end

return M
