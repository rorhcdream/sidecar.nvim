-- Regression check: the shared toggle controls the selected tool, while switch
-- cycles tools and only replaces the panel when it is already visible.
-- Run: nvim --headless -l tests/switch_test.lua
package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path
local cc = require("sidecar")
local source_buf = vim.api.nvim_get_current_buf()
vim.api.nvim_buf_set_name(source_buf, vim.fn.getcwd() .. "/tests/example.lua")
cc.setup({
  tools = {
    a = { cmd = { "sh", "-c", "sleep 30" } },
    b = { cmd = { "sh", "-c", "sleep 30" } },
  },
  active = "a",
  remember_active = false,
})

local source_win = vim.api.nvim_get_current_win()
assert(cc.switch() == "b", "collapsed switch did not select the next tool")
assert(vim.api.nvim_get_current_win() == source_win, "collapsed switch unexpectedly opened a panel")

cc.toggle()
local b_buf = vim.api.nvim_get_current_buf()
assert(vim.bo.buftype == "terminal", "shared toggle did not open the selected tool")

assert(cc.switch() == "a", "visible switch did not cycle to the next tool")
local a_buf = vim.api.nvim_get_current_buf()
assert(vim.bo.buftype == "terminal", "visible switch did not keep the panel open")
assert(a_buf ~= b_buf, "visible switch did not replace the terminal buffer")

cc.toggle() -- collapse a
assert(vim.api.nvim_get_current_win() == source_win, "shared toggle did not collapse the panel")
assert(cc.switch() == "b", "second switch did not cycle back to the first terminal")
assert(vim.api.nvim_get_current_win() == source_win, "collapsed switch reopened the panel")

cc.toggle()
assert(vim.api.nvim_get_current_buf() == b_buf, "shared toggle did not reopen the selected terminal")

-- Active b is visible while running a is hidden. A context send reopens a, but
-- focus must return to active b rather than whichever terminal was reopened.
vim.api.nvim_set_current_win(source_win)
local sent = 0
local chan_send = vim.api.nvim_chan_send
vim.api.nvim_chan_send = function() sent = sent + 1 end
cc.add_buffer()
vim.api.nvim_chan_send = chan_send
assert(sent == 2, "buffer reference was not broadcast to both running tools")
assert(vim.api.nvim_get_current_buf() == b_buf, "context send focused a non-active terminal")
print("ok")
