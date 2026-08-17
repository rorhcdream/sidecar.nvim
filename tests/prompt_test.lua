-- Regression check: startup commands open the active tool, seed its prompt,
-- and submit only when invoked with a bang.
-- Run: nvim --headless -l tests/prompt_test.lua
package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path
local cc = require("sidecar")

local root = vim.fn.tempname()
local prompt_file = root .. "/task prompt.md"
vim.fn.mkdir(root, "p")
vim.fn.writefile({ "first line", "second line" }, prompt_file)
vim.env.SIDECAR_TEST_PROMPT_FILE = prompt_file

cc.setup({
  tools = { test = { cmd = { "test-agent" } } },
  active = "test",
  remember_active = false,
  prompt_delay_ms = 20,
  prompt_submit_delay_ms = 10,
  history = { enabled = false, resume = false },
  keymaps = { toggle = false, switch = false, toggles = {}, add_buffer = false, send = false },
})

local commands = {}
local sent = {}
local termopen = vim.fn.termopen
local chan_send = vim.api.nvim_chan_send
vim.fn.termopen = function(cmd)
  commands[#commands + 1] = cmd
  return 42
end
vim.api.nvim_chan_send = function(jobid, payload)
  sent[#sent + 1] = { jobid = jobid, payload = payload }
end

vim.cmd("SidecarPrompt review this task")
assert(#sent == 0, "prompt was sent before the fresh terminal initialization delay")
vim.cmd("SidecarPrompt! start this task")
vim.cmd("SidecarPromptFile! $SIDECAR_TEST_PROMPT_FILE")
vim.cmd("SidecarPromptFile " .. vim.fn.fnameescape(prompt_file))
assert(vim.wait(1000, function() return #sent == 6 end, 5), "queued prompts were not sent after initialization")

vim.cmd("SidecarPrompt terminal is ready")
assert(#sent == 7 and sent[7].payload == "terminal is ready", "ready terminal prompt was unexpectedly delayed")

vim.fn.termopen = termopen
vim.api.nvim_chan_send = chan_send
vim.env.SIDECAR_TEST_PROMPT_FILE = nil

assert(#commands == 1, "prompt commands relaunched an existing terminal")
assert(vim.deep_equal(commands[1], { "test-agent" }), "prompt command launched the wrong tool")
assert(#sent == 7, "unexpected number of terminal sends")
assert(sent[1].jobid == 42 and sent[1].payload == "review this task", "inline prompt was not prefilled")
assert(sent[2].payload == "start this task", "submitted inline prompt was not pasted")
assert(sent[3].payload == "\r", "inline prompt Enter was not sent separately")
assert(
  sent[4].payload == "\27[200~first line\nsecond line\27[201~",
  "prompt file was not sent as multiline paste"
)
assert(sent[5].payload == "\r", "prompt-file Enter was not sent separately")
assert(sent[6].payload == "\27[200~first line\nsecond line\27[201~", "escaped prompt-file path failed")
print("ok")
