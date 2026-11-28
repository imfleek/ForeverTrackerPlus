-- Dev check (not a test, not shipped): fits PATH_SPEED in Tracker/Helpers.lua to real flight times.
-- Run: texlua flight_fit.lua ../Tracker/FlightData.lua <RXPGuides>/DB/forever/flightData.lua
local ns = {}
assert(loadfile(arg[1]))("x", { tracker = ns })
local addon = { game = "FOREVER" }
assert(loadfile(arg[2]))("RXPGuides", addon)
local waits = ns.flightPathWaits or {}
local rows = {}
for key, yd in pairs(ns.flightPathYards) do
	local a, b = key // 10000, key % 10000
	for _, fac in ipairs({ "Horde", "Alliance" }) do
		local L = addon.FPDB[fac] or {}
		local t = L[a] and L[a][b] or L[b] and L[b][a]
		if t then rows[#rows + 1] = { yd, t, waits[key] or 0 } break end
	end
end
-- least squares t = yd/s + c  (fit 1/s and c)
local n, sx, sy, sxx, sxy = 0, 0, 0, 0, 0
for _, r in ipairs(rows) do local x, y = r[1], r[2] - r[3]; n = n + 1; sx = sx + x; sy = sy + y; sxx = sxx + x * x; sxy = sxy + x * y end
local k = (n * sxy - sx * sy) / (n * sxx - sx * sx); local c = (sy - k * sx) / n
print("pairs", n, "speed", 1 / k, "offset", c)
local function err(speed, off)
	local e, worst = 0, 0
	for _, r in ipairs(rows) do local d = math.abs(r[1] / speed + off + r[3] - r[2]); e = e + d; worst = math.max(worst, d) end
	return e / n, worst
end
print("now 30.5/0", err(30.5, 0))
print("fit", err(1 / k, c))
local s2 = 0; for _, r in ipairs(rows) do s2 = s2 + r[1] / (r[2] - r[3]) end
print("mean speed", s2 / n, err(s2 / n, 0))
