-- Regression check: without Sidecar state, setup selects the agent whose local
-- session for this directory was modified most recently. Sidecar state wins once
-- present. Synthetic metadata keeps the test independent of real CLI history.
-- Run: nvim --headless -l tests/history_detection_test.lua
package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path
local cc = require("sidecar")

local root = vim.fn.tempname()
local project = root .. "/project"
local state_dir = root .. "/state"
local claude_projects = root .. "/claude-projects"
local codex_sessions = root .. "/codex-sessions/2026/08/03"
vim.fn.mkdir(project, "p")
vim.fn.mkdir(codex_sessions, "p")
vim.cmd.cd(vim.fn.fnameescape(project))

local cwd = vim.fs.normalize(vim.uv.fs_realpath(project) or project)
local encoded_cwd = cwd:gsub("[^%w]", "-")
local claude_project = claude_projects .. "/" .. encoded_cwd
vim.fn.mkdir(claude_project, "p")

local claude_file = claude_project .. "/session.jsonl"
local codex_file = codex_sessions .. "/rollout.jsonl"
vim.fn.writefile({ vim.json.encode({ type = "user", cwd = cwd }) }, claude_file)
vim.fn.writefile({
  vim.json.encode({ type = "session_meta", payload = { cwd = cwd } }),
}, codex_file)
vim.uv.fs_utime(claude_file, 1000, 1000)
vim.uv.fs_utime(codex_file, 2000, 2000)

local opts = {
  tools = { claude = { cmd = "claude" }, codex = { cmd = "codex" } },
  active = "claude",
  remember_active = true,
  state_dir = state_dir,
  history = { enabled = true, claude_dir = claude_projects, codex_dir = root .. "/codex-sessions" },
  keymaps = { toggle = false, switch = false, toggles = {}, add_buffer = false, send = false },
}
cc.setup(opts)
assert(cc.config.active == "codex", "newer Codex history was not selected")

-- Switching while collapsed writes Sidecar's higher-priority remembered choice.
assert(cc.switch() == "claude", "switch did not select Claude")
vim.uv.fs_utime(codex_file, 3000, 3000)
cc.setup(opts)
assert(cc.config.active == "claude", "session history overrode remembered Sidecar state")
print("ok")
