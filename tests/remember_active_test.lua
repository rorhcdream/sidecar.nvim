-- Regression check: the selected tool is remembered per working directory,
-- using a hashed filename that does not expose the directory path.
-- Run: nvim --headless -l tests/remember_active_test.lua
package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path
local cc = require("sidecar")

local state_dir = vim.fn.tempname()
local project_dir = vim.fn.tempname()
vim.fn.mkdir(project_dir, "p")
vim.cmd.cd(vim.fn.fnameescape(project_dir))

local opts = {
  tools = { a = { cmd = "a" }, b = { cmd = "b" } },
  active = "a",
  remember_active = true,
  state_dir = state_dir,
  keymaps = { toggle = false, switch = false, toggles = {}, add_buffer = false, send = false },
}
cc.setup(opts)
assert(cc.switch() == "b", "switch did not select the tool to remember")

cc.setup(opts)
assert(cc.config.active == "b", "setup did not restore the remembered tool")

local other_project = vim.fn.tempname()
vim.fn.mkdir(other_project, "p")
vim.cmd.cd(vim.fn.fnameescape(other_project))
cc.setup(opts)
assert(cc.config.active == "a", "remembered tool leaked into a different directory")

local files = vim.fn.globpath(state_dir, "*.active", false, true)
assert(#files == 1, "expected one per-directory active-tool state file")
local filename = vim.fn.fnamemodify(files[1], ":t")
assert(#filename == 71 and filename:match("^[0-9a-f]+%.active$"), "state filename is not a directory hash")
assert(vim.fn.readfile(files[1])[1] == "b", "state file did not contain the remembered tool")
print("ok")
