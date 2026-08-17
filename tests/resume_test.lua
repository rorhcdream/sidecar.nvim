-- Regression check: the first launch resumes the latest directory session for
-- Claude and Codex when matching history exists.
-- Run: nvim --headless -l tests/resume_test.lua
package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path
local cc = require("sidecar")

local root = vim.fn.tempname()
local project = root .. "/project"
local claude_projects = root .. "/claude-projects"
local codex_sessions = root .. "/codex-sessions/2026/08/03"
vim.fn.mkdir(project, "p")
vim.fn.mkdir(codex_sessions, "p")
vim.cmd.cd(vim.fn.fnameescape(project))

local cwd = vim.fs.normalize(vim.uv.fs_realpath(project) or project)
local claude_project = claude_projects .. "/" .. cwd:gsub("[^%w]", "-")
vim.fn.mkdir(claude_project, "p")
vim.fn.writefile({ vim.json.encode({ type = "user", cwd = cwd }) }, claude_project .. "/session.jsonl")
vim.fn.writefile({
  vim.json.encode({ type = "session_meta", payload = { cwd = cwd } }),
}, codex_sessions .. "/rollout.jsonl")

cc.setup({
  tools = { claude = { cmd = "claude" }, codex = { cmd = { "codex" } } },
  active = "codex",
  remember_active = false,
  history = { enabled = true, resume = true, claude_dir = claude_projects, codex_dir = root .. "/codex-sessions" },
  keymaps = { toggle = false, switch = false, toggles = {}, add_buffer = false, send = false },
})

local commands = {}
local termopen = vim.fn.termopen
vim.fn.termopen = function(cmd)
  commands[#commands + 1] = cmd
  return #commands
end

cc.toggle("codex")
cc.toggle("codex") -- collapse without relaunching
cc.toggle("claude")
vim.fn.termopen = termopen

assert(vim.deep_equal(commands[1], { "codex", "resume", "--last" }), "Codex did not resume with cwd filtering")
assert(commands[2] == "claude " .. vim.fn.shellescape("--continue"), "Claude did not continue its directory session")
assert(#commands == 2, "an existing terminal was unexpectedly relaunched")
print("ok")
