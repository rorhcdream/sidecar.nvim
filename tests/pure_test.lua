-- Runnable check for the pure text helpers: `nvim -l tests/pure_test.lua`
-- Covers the pure mention, line-range, and path-sanitizing helpers;
-- terminal/window behavior is exercised interactively, not here.
vim.opt.runtimepath:append(vim.fn.fnamemodify("lua/../", ":p"))
package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local cc = require("sidecar")

cc.config.file_mention = "@%s "
assert(cc._mention("src/x.lua") == "@src/x.lua ", "mention format failed")
assert(cc._line_reference("src/x.lua", 3, 7) == "@src/x.lua#3-7 ", "line range failed")
assert(cc._line_reference("src/x.lua", 7, 3) == "@src/x.lua#3-7 ", "reversed line range failed")
assert(cc._line_reference("src/x.lua", 4, 4) == "@src/x.lua#4 ", "single-line reference failed")

-- Control chars in a path (newline, ESC) are stripped: an unwrapped mention must
-- not be able to inject a submit.
assert(cc._mention("a\nb.lua") == "@ab.lua ", "mention newline strip failed")
assert(cc._mention("a\27[201~b.lua") == "@a[201~b.lua ", "mention esc strip failed")

cc.config.file_mention = "read %s"
assert(cc._mention("a/b.py") == "read a/b.py", "mention format (custom) failed")
assert(cc._line_reference("a/b.py", 2, 5) == "read a/b.py#2-5", "line range (custom) failed")

print("ok")
