# sidecar.nvim

Keep a CLI coding agent one keystroke away in a Neovim terminal split. Give each
agent its own toggle key, and push the current file or a visual selection into
whichever agents are open. Terminal-only — no websocket/MCP protocol — so any
CLI behaves the same.

Adapted from [`coder/claudecode.nvim`](https://github.com/coder/claudecode.nvim)'s
native terminal provider, minus the IDE protocol, plus fixes for the
focus-scroll-jump and crash-hidden-error bugs.

## Keymaps

| Key   | Mode  | Action                                                                        |
| ----- | ----- | ----------------------------------------------------------------------------- |
| `,ac` | n / t | Toggle / focus the **claude** terminal                                        |
| `,ax` | n / t | Toggle / focus the **codex** terminal                                         |
| `,ab` | n     | Send file (`@path`) to every open agent — node under cursor in nvim-tree/oil, else current buffer |
| `,as` | v     | Send the visual selection as a pasted block to every open agent               |

`,ab`/`,as` broadcast to all open agents at once (if only one is open, just that
one; if none are open, the default agent is started). They never auto-submit —
text lands in the prompt so you can review and hit enter yourself. Selections are
sent as a bracketed-paste block and control characters (embedded paste
delimiters, newlines in filenames) are stripped so crafted content can't sneak a
submit through.

**Scrolling** an agent's history is native: press your terminal-normal-mode key
(e.g. `<C-\><C-n>`) then `k`/`j`, `<C-u>`/`<C-d>`, `gg`/`G`. Both Claude and Codex
run non-fullscreen, so their output lives in Neovim's scrollback.

## Requirements

- Neovim >= 0.10 (`vim.fn.getregion()`, used for visual-selection sends, was
  added in 0.10)
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
  split_side = "right",   -- "right" | "left"
  split_width = 0.40,     -- fraction of columns
  file_mention = "@%s ",  -- how ,ab references the current file
  keymaps = {
    toggles = { claude = "<leader>ac", codex = "<leader>ax" }, -- per-agent toggle
    toggle = false,        -- optional single key that toggles the default agent
    add_buffer = "<leader>ab",
    send = "<leader>as",
  },
})
```

Any terminal CLI works. The `tools` table **replaces** the default set rather
than extending it, so `tools = { aider = { cmd = "aider" } }` gives you *only*
aider — list every agent you want, and give each one a toggle via `keymaps.toggles`.

## Fixes over the original

- **Focus-scroll jump.** Entering terminal-*insert* mode always snaps a terminal
  to its newest output (a Neovim invariant). `focus_win` only starts insert mode
  when the view is already at the bottom; if you scrolled up in normal mode,
  refocus keeps your position. Toggling away and back preserves scroll + cursor.
- **Crash-hidden errors.** A non-zero exit keeps the terminal buffer visible (and
  notifies) instead of the window vanishing, so auth errors and crashes are
  readable rather than a flash-and-gone.

## Tests

```sh
nvim --headless -l tests/pure_test.lua        # text helpers
nvim --headless -l tests/scroll_test.lua      # scroll-preservation on refocus
nvim --headless -l tests/toggle_view_test.lua # scroll/cursor preserved across toggle
```
