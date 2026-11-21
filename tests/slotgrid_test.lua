-- R106-107: a step's action buttons do not push its next lines below the whole grid; the row still reaches down to
-- the grid's bottom, and a later line with its own buttons starts below the earlier grid
local dir = arg[1]
local pass = true
local function check(l, c) print((c and "ok   " or "FAIL ") .. l); pass = pass and c end
local src = io.open(dir .. "/Objectives/tracker/Rows.lua"):read("a")
local slots = src:match("local function placeSlots.-\nend\n")
check("the line keeps its own height (no line:SetHeight for the grid)", slots and not slots:find("line:SetHeight", 1, true))
check("the grid's bottom remembered on the row", slots and slots:find("row.slotsEnd = math.max(tonumber(row.slotsEnd) or 0, row.height + need - height)", 1, true))
check("the row reaches down to the grid's bottom", src:find("if tonumber(row.slotsEnd) and row.slotsEnd > row.height then row.height = row.slotsEnd end", 1, true) ~= nil)
check("a later line with its own buttons starts below the earlier grid",
	src:find("spacing = spacing + (row.slotsEnd - row.height)", 1, true) ~= nil)
check("reset for each row", src:find("row.slotsEnd = nil\n\tfor key, objective in ipairs(entry.lines)", 1, true) ~= nil)
print(pass and "PASSED" or "FAILED")
