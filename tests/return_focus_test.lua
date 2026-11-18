-- Regression check: collapsing Sidecar returns to the window that opened or
-- focused it, even when Neovim would select another split by default.
-- Run: nvim --headless -l tests/return_focus_test.lua
package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path
local cc = require("sidecar")
cc.setup({
  tools = {
    a = { cmd = { "sh", "-c", "sleep 30" } },
    b = { cmd = { "sh", "-c", "sleep 30" } },
  },
  active = "a",
  remember_active = false,
  history = { enabled = false },
  prompt_delay_ms = 0,
})

local source = vim.api.nvim_get_current_win()
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "first", "second line", "third" })
vim.api.nvim_win_set_cursor(source, { 2, 3 })
vim.cmd("vsplit")
local other = vim.api.nvim_get_current_win()

local function assert_source(message)
  assert(vim.api.nvim_get_current_win() == source, message)
  assert(vim.deep_equal(vim.api.nvim_win_get_cursor(source), { 2, 3 }), "source cursor moved")
end

for _, side in ipairs({ "right", "left" }) do
  cc.config.split_side = side
  vim.api.nvim_set_current_win(source)
  cc.toggle("a")
  cc.toggle("a")
  assert_source(side .. " panel did not return to its opener")

  -- Reopening a hidden terminal records the new originating window.
  vim.api.nvim_set_current_win(other)
  cc.toggle("a")
  cc.toggle("a")
  assert(vim.api.nvim_get_current_win() == other, "reopen retained a stale origin")

  cc.toggle("a")
  vim.api.nvim_set_current_win(source)
  cc.toggle("a") -- focus the already-visible panel from source
  cc.focus("a") -- focusing from inside the panel must retain source
  cc.toggle("a")
  assert_source("visible-panel toggle did not remember its caller")

  cc.toggle("a")
  vim.api.nvim_set_current_win(source)
  cc.prompt("hello", { tool = "a" })
  cc.toggle("a")
  assert_source("prompt focus did not remember its caller")

  cc.toggle("a")
  cc.switch()
  cc.toggle()
  assert_source("agent switch lost the originating window")

  cc.toggle("a")
  cc.refresh("a")
  cc.toggle("a")
  assert_source("refresh lost the originating window")
end

-- A terminal exiting while the user is elsewhere must not steal focus.
vim.api.nvim_set_current_win(other)
-- Use a clean shell exit rather than a signal so Sidecar actually hides it.
cc.config.tools.c = { cmd = { "sh", "-c", "read line; exit 0" } }
cc.toggle("c")
local channel = vim.bo.channel
local terminal = vim.api.nvim_get_current_win()
vim.api.nvim_set_current_win(source)
vim.fn.chansend(channel, "done\n")
assert(vim.wait(3000, function() return not vim.api.nvim_win_is_valid(terminal) end, 20), "terminal did not exit")
assert_source("background exit stole focus")

-- Closing the originating window leaves Neovim's normal fallback intact.
cc.toggle("a")
vim.api.nvim_win_close(source, false)
cc.toggle("a")
assert(vim.api.nvim_win_is_valid(vim.api.nvim_get_current_win()), "closed origin caused an invalid focus")
assert(vim.bo.buftype ~= "terminal", "panel was not hidden after its origin closed")
print("ok")
