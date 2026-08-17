-- Regression check: refresh stops and discards the active terminal, then opens
-- a replacement that the old job's delayed exit callback cannot tear down.
-- Run: nvim --headless -l tests/refresh_test.lua
package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path
local cc = require("sidecar")

cc.setup({
  tools = { test = { cmd = { "sh", "-c", "sleep 30" } } },
  active = "test",
  remember_active = false,
  history = { enabled = false, resume = false },
  keymaps = { toggle = false, refresh = false, switch = false, toggles = {}, add_buffer = false, send = false },
})

cc.toggle()
local old_buf = vim.api.nvim_get_current_buf()
local old_job = vim.bo[old_buf].channel
assert(vim.bo[old_buf].buftype == "terminal", "initial terminal did not open")

cc.refresh()
local new_buf = vim.api.nvim_get_current_buf()
local new_job = vim.bo[new_buf].channel
assert(new_buf ~= old_buf, "restart reused the old terminal buffer")
assert(new_job ~= old_job, "restart reused the old terminal job")
assert(not vim.api.nvim_buf_is_valid(old_buf), "restart did not discard the old terminal buffer")
assert(vim.bo[new_buf].buftype == "terminal", "restart did not open a replacement terminal")

vim.wait(100, function() return false end, 10)
assert(vim.api.nvim_buf_is_valid(new_buf), "old exit callback discarded the replacement terminal")
assert(vim.api.nvim_get_current_buf() == new_buf, "replacement terminal lost focus")
assert(vim.fn.jobwait({ new_job }, 0)[1] == -1, "replacement terminal job stopped unexpectedly")
print("ok")
