-- Runnable check for the pure text helpers: `nvim -l tests/pure_test.lua`
-- Covers the two bits with real logic — paste wrapping + mention formatting;
-- terminal/window behavior is exercised interactively, not here.
vim.opt.runtimepath:append(vim.fn.fnamemodify("lua/../", ":p"))
package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local cc = require("sidecar")

local paste = cc._wrap_paste("a\nb")
assert(paste == "\27[200~a\nb\27[201~", "bracketed paste wrap failed: " .. vim.inspect(paste))

-- Embedded paste delimiters must be stripped so they can't end paste mode early
-- and let the trailing newline auto-submit.
local evil = cc._wrap_paste("a\27[201~\nrm -rf\27[200~b")
assert(evil == "\27[200~a\nrm -rfb\27[201~", "paste delimiter strip failed: " .. vim.inspect(evil))

cc.config.file_mention = "@%s "
assert(cc._mention("src/x.lua") == "@src/x.lua ", "mention format failed")

-- Control chars in a path (newline, ESC) are stripped: an unwrapped mention must
-- not be able to inject a submit.
assert(cc._mention("a\nb.lua") == "@ab.lua ", "mention newline strip failed")
assert(cc._mention("a\27[201~b.lua") == "@a[201~b.lua ", "mention esc strip failed")

cc.config.file_mention = "read %s"
assert(cc._mention("a/b.py") == "read a/b.py", "mention format (custom) failed")

print("ok")
