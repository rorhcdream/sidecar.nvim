-- Regression check: a terminal collapsed from terminal-insert mode resumes at
-- the live end after agent output arrives while it is hidden.
-- Run: nvim --headless -l tests/toggle_insert_test.lua
package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path
local cc = require("sidecar")
cc.setup({
  tools = { t = { cmd = { "sh", "-c", "seq 1 200; sleep 0.5; seq 201 500; sleep 30" } } },
  active = "t",
  remember_active = false,
})

cc.toggle("t") -- open + focus
assert(vim.wait(3000, function() return vim.fn.line("$") > 100 end, 20), "initial terminal output timed out")
local term_buf = vim.api.nvim_get_current_buf()

-- Headless Neovim cannot remain in terminal-input mode. Override mode() only
-- while collapsing to exercise the state captured by a real terminal mapping.
local mode = vim.fn.mode
vim.fn.mode = function() return "t" end
cc.toggle("t")
vim.fn.mode = mode

assert(
  vim.wait(3000, function() return vim.api.nvim_buf_line_count(term_buf) > 400 end, 20),
  "hidden terminal output timed out"
)
cc.toggle("t")

local cursor_line = vim.fn.line(".")
local last_line = vim.fn.line("$")
print(("cursor=%d last=%d mode=%q"):format(cursor_line, last_line, vim.fn.mode()))
assert(vim.api.nvim_get_current_buf() == term_buf, "terminal was not reopened")
assert(cursor_line == last_line, "terminal did not resume at the live input")
print("ok")
