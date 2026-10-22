package.path = "mods/crystalminer/?.lua;tests/?.lua;" .. package.path
local N = loadfile("mods/crystalminer/exhibit_notice.lua")()
local T = require("testlib")

print("exhibit notice")

T.run("stages build readable status lines", function()
	local title, line = N.lines("searching", 7)
	T.eq(title, "Loading a random crystal structure")
	T.eq(line, "Searching the Materials Project.. 7 s")
	local _, checking = N.lines("checking", 3, "Checking record 3 of up to 60")
	T.eq(checking, "Checking record 3 of up to 60 3 s")
	local _, building = N.lines("building", 4)
	T.eq(building, "4 s")
end)

T.run("dots and elapsed text cycle", function()
	T.eq(N.dots(0), "."); T.eq(N.dots(1), ".."); T.eq(N.dots(2), "..."); T.eq(N.dots(3), ".")
	T.eq(N.elapsed(7.9), "7 s"); T.eq(N.elapsed(-1), "0 s")
end)

T.run("success and failure text", function()
	local title, line = N.success("MgMn4O8-0", 3)
	T.eq(title, "Structure ready: MgMn4O8-0"); T.eq(line, "Entering exhibit room 3")
	local fail_title, fail_line = N.failure("Could not load a new structure; showing fallback")
	T.eq(fail_title, "Loading crystal structure"); T.eq(fail_line, "Could not load a new structure; showing fallback")
end)

T.run("long display names are bounded", function()
	local long = N.display_name(string.rep("x", 100))
	T.ok(#long <= 48, "name length")
	T.ok(long:sub(-3) == "...", "ellipsis")
end)

T.finish()
