# sidecar.nvim

Keep a CLI coding agent one keystroke away in a Neovim terminal split. Toggle the
active agent with one key, switch agents with another, and push the current file
or a selected line range into whichever agents are running. Terminal-only — no
websocket/MCP protocol — so any CLI behaves the same.

Adapted from [`coder/claudecode.nvim`](https://github.com/coder/claudecode.nvim)'s
native terminal provider, minus the IDE protocol, plus fixes for the
focus-scroll-jump and crash-hidden-error bugs.

## Keymaps

| Key   | Mode  | Action                                                                        |
| ----- | ----- | ----------------------------------------------------------------------------- |
| `,ac` | n / t | Toggle / focus the active agent (**claude** or **codex**)                      |
| `,at` | n / t | Switch the active agent; replace the panel when it is visible                  |
| `,ab` | n     | Send file (`@path`) to every running agent — node under cursor in nvim-tree/oil, else current buffer |
| `,as` | v     | Send the selected file + line range (`@path#start-end`) to every running agent |

`,ab`/`,as` broadcast to all running agents at once (if only one is running, just
that one; if none are running, the default agent is started). Both reopen hidden
agent terminals and focus the active one. They never auto-submit — text lands in
the prompt so you can review and hit enter yourself. Control characters in
filenames are stripped so crafted paths can't sneak a submit through.

The agent last selected through Sidecar is remembered per working directory and
restored the next time Sidecar loads there. If Sidecar has no state yet, it
compares the latest Claude Code and Codex session files for that directory and
selects whichever agent was used more recently. This is best-effort because the
CLIs do not expose a stable shared history API. Sidecar state filenames use a
hash of the directory, so project paths are not written to the state file.

On the first terminal launch, matching history is resumed automatically:
`claude --continue` for Claude Code and `codex resume --last` for Codex. No
history keeps the normal fresh-session command, and an already-running terminal
is always reused. Set `history.resume = false` to disable automatic resume, or
set a tool's `resume_args = false` to disable it for that tool only.

**Scrolling** an agent's history is native: press your terminal-normal-mode key
(e.g. `<C-\><C-n>`) then `k`/`j`, `<C-u>`/`<C-d>`, `gg`/`G`. Both Claude and Codex
run non-fullscreen, so their output lives in Neovim's scrollback.

## Requirements

- Neovim >= 0.10
- A terminal CLI agent on `$PATH` (e.g. `claude`, `codex`)

## Install (lazy.nvim)

```lua
{
  "rorhcdream/sidecar.nvim",
  event = "VeryLazy",
  opts = {
    tools = {
      claude = { cmd = "~/.local/bin/claude" },
      codex = { cmd = "codex" },
    },
  },
  config = function(_, opts) require("sidecar").setup(opts) end,
}
```

## Config defaults

```lua
require("sidecar").setup({
  tools = { claude = { cmd = "claude" }, codex = { cmd = "codex" } },
  active = "claude",      -- default agent, opened when a send happens with none open
  remember_active = true, -- restore the last selected agent for this directory
  history = {
    enabled = true, -- otherwise infer from local Claude/Codex sessions
    resume = true,  -- resume matching history on the first terminal launch
  },
  split_side = "right",   -- "right" | "left"
  split_width = 0.40,     -- fraction of columns
  file_mention = "@%s ",  -- how ,ab/,as reference files and line ranges
  keymaps = {
    toggle = "<leader>ac", -- toggle the active agent
    switch = "<leader>at", -- cycle agents; replace the panel if visible
    toggles = {},           -- optional direct per-agent toggle keys
    add_buffer = "<leader>ab",
    send = "<leader>as",
  },
})
```

Any terminal CLI works. The `tools` table **replaces** the default set rather
than extending it, so `tools = { aider = { cmd = "aider" } }` gives you *only*
aider. `,at` cycles configured tools alphabetically; use `keymaps.toggles` only
if you also want direct keys for particular agents.

## Fixes over the original

- **Focus-scroll jump.** Entering terminal-*insert* mode always snaps a terminal
  to its newest output (a Neovim invariant). If you collapse a terminal while
  typing, reopening follows new output and resumes insert mode at the live input.
  If you collapse while reading scrollback in normal mode, reopening preserves
  that scroll and cursor position instead.
- **Crash-hidden errors.** A non-zero exit keeps the terminal buffer visible (and
  notifies) instead of the window vanishing, so auth errors and crashes are
  readable rather than a flash-and-gone.

## Tests

```sh
nvim --headless -l tests/pure_test.lua        # text helpers
nvim --headless -l tests/scroll_test.lua      # scroll-preservation on refocus
nvim --headless -l tests/toggle_view_test.lua # scroll/cursor preserved across toggle
nvim --headless -l tests/toggle_insert_test.lua # insert mode follows hidden output
nvim --headless -l tests/send_selection_test.lua # line reference + reveal on send
nvim --headless -l tests/switch_test.lua      # shared toggle + agent switching
nvim --headless -l tests/remember_active_test.lua # per-directory active agent
nvim --headless -l tests/history_detection_test.lua # history fallback precedence
```
