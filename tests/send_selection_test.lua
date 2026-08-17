-- Regression check: context sends insert file references and reopen + focus a
-- terminal that was toggled closed.
-- Run: nvim --headless -l tests/send_selection_test.lua
package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path
local cc = require("sidecar")

local source_win = vim.api.nvim_get_current_win()
local source_buf = vim.api.nvim_get_current_buf()
vim.api.nvim_buf_set_name(source_buf, vim.fn.getcwd() .. "/tests/example.lua")
vim.api.nvim_buf_set_lines(source_buf, 0, -1, false, { "one", "two", "three", "four", "five" })

cc.setup({
  tools = { t = { cmd = { "sh", "-c", "sleep 30" } } },
  active = "t",
  remember_active = false,
  prompt_delay_ms = 0,
})
cc.toggle("t") -- open + focus
cc.toggle("t") -- hide, returning to the source window
assert(vim.api.nvim_get_current_win() == source_win, "toggle did not return to source window")

local sent = {}
local chan_send = vim.api.nvim_chan_send
vim.api.nvim_chan_send = function(jobid, payload)
  sent[#sent + 1] = { jobid = jobid, payload = payload }
end

vim.cmd("normal! 2GV4G")
cc.send_selection()
vim.api.nvim_chan_send = chan_send

assert(#sent == 1, "selection reference was not sent exactly once")
assert(sent[1].payload == "@tests/example.lua#2-4 ", "unexpected selection payload: " .. vim.inspect(sent[1].payload))
assert(vim.bo.buftype == "terminal", "hidden terminal was not reopened and focused")

cc.toggle("t") -- hide again, returning to the source buffer
sent = {}
vim.api.nvim_chan_send = function(jobid, payload)
  sent[#sent + 1] = { jobid = jobid, payload = payload }
end
cc.add_buffer()
vim.api.nvim_chan_send = chan_send

assert(#sent == 1, "buffer reference was not sent exactly once")
assert(sent[1].payload == "@tests/example.lua ", "unexpected buffer payload: " .. vim.inspect(sent[1].payload))
assert(vim.bo.buftype == "terminal", "buffer send did not reopen and focus the hidden terminal")
print("ok")
