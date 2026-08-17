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
  prompt_delay_ms = 0,
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

-- Active b is visible while running a is hidden. Context is sent only to b;
-- a remains untouched and focus moves to the active agent for review.
vim.api.nvim_set_current_win(source_win)
local sent = {}
local chan_send = vim.api.nvim_chan_send
vim.api.nvim_chan_send = function(jobid, payload)
  sent[#sent + 1] = { jobid = jobid, payload = payload }
end
cc.add_buffer()
vim.api.nvim_chan_send = chan_send
assert(#sent == 1, "buffer reference was sent to more than the active tool")
assert(sent[1].jobid == vim.bo[b_buf].channel, "buffer reference was not sent to the active tool")
assert(vim.api.nvim_get_current_buf() == b_buf, "context send focused a non-active terminal")
print("ok")
