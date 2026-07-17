-- Integration check for the focus-scroll fix: open a terminal with scrollback,
-- scroll to the top in normal mode, unfocus, refocus, and assert the scroll
-- position is preserved (and we are NOT snapped into terminal-insert at bottom).
-- Run: nvim --headless -l tests/scroll_test.lua
package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path
local cc = require("sidecar")
cc.setup({ tools = { t = { cmd = { "sh", "-c", "seq 1 500; sleep 30" } } }, active = "t" })

cc.toggle("t") -- opens + focuses the terminal
vim.wait(3000, function() return vim.fn.line("$") > 200 end, 50)
vim.cmd("stopinsert")

local term_win = vim.api.nvim_get_current_win()
vim.cmd("normal! gg") -- scroll to top
local top_before = vim.fn.line("w0")

vim.cmd("topleft new") -- move focus to a different window
cc.focus("t") -- refocus terminal — must NOT jump to bottom

local top_after = vim.fn.line("w0")
local mode_after = vim.fn.mode()
print(("top_before=%d top_after=%d mode=%q"):format(top_before, top_after, mode_after))
assert(top_after == top_before, "scroll position not preserved on refocus")
assert(mode_after ~= "t", "refocus snapped into terminal-insert (bottom)")
print("ok")
