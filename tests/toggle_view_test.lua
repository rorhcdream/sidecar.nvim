-- Regression check: scroll up in terminal-normal mode, toggle the terminal off
-- and back on, and assert the scroll + cursor position are preserved (and we are
-- NOT snapped into terminal-insert at the bottom / input line).
-- Run: nvim --headless -l tests/toggle_view_test.lua
package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path
local cc = require("sidecar")
cc.setup({ tools = { t = { cmd = { "sh", "-c", "seq 1 500; sleep 30" } } }, active = "t" })

cc.toggle("t") -- open + focus
vim.wait(3000, function() return vim.fn.line("$") > 200 end, 50)
vim.cmd("stopinsert")
vim.cmd("normal! gg") -- scroll to top, cursor on line 1

local top_before = vim.fn.line("w0")
local lnum_before = vim.fn.line(".")

cc.toggle("t") -- toggle OFF (window hidden, view captured)
cc.toggle("t") -- toggle ON  (window rebuilt, view restored)

local top_after = vim.fn.line("w0")
local lnum_after = vim.fn.line(".")
local mode_after = vim.fn.mode()
print(("top %d->%d  lnum %d->%d  mode=%q")
  :format(top_before, top_after, lnum_before, lnum_after, mode_after))
assert(top_after == top_before, "scroll position not preserved across toggle")
assert(lnum_after == lnum_before, "cursor line not preserved across toggle")
assert(mode_after ~= "t", "toggle-back snapped into terminal-insert (input line)")
print("ok")
