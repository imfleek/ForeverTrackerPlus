-- ForeverTrackerPlus: RestedXP guide steps in the objective tracker (the AllObjectives RXP half, Objectives/) and a
-- scrollable tracker with zone sorting, rewards and tooltips (the tracker half, Tracker/), in one addon.
-- Each half keeps its own private namespace so their fields (both use ns.db, ns.say, ...) never collide:
--   root.objectives  every file under Objectives/
--   root.tracker     every file under Tracker/
local ADDON, root = ...
root.objectives, root.tracker = {}, {}
root.BRAND = "ForeverTrackerPlus"

-- 3.2 (user): every sound of the addon goes through here, so one switch mutes them all (Settings: "Sounds",
-- db.sounds; on by default). Called as (root.playSound or pcall)(PlaySound, id): the files work without it too.
-- 3.2 (user's BugSack: "ForeverTrackerPlus tried to call the protected function" in SendChatMessage): text for the
-- chat box goes only into a chat box you opened yourself (Enter). Opening it from addon code (ChatFrame_OpenChat)
-- left the box tainted, and your own Enter press was then blocked. Returns true when the text went in; otherwise
-- it says to press Enter first, as the game's own item links do.
function root.chatInsert(text)
	if type(text) ~= "string" or text == "" then return false end
	local get = (ChatFrameUtil and ChatFrameUtil.GetActiveWindow) or ChatEdit_GetActiveWindow
	local box = type(get) == "function" and get() or nil
	if box and box.Insert then
		box:Insert(text)
		return true
	end
	if UIErrorsFrame and UIErrorsFrame.AddMessage then
		UIErrorsFrame:AddMessage("Press Enter to open the chat box, then Shift-click again.", 1, 0.82, 0)
	end
	return false
end

function root.playSound(play, id, ...)
	local t = root.tracker
	if t and t.db and t.db.sounds == false then return end
	if type(play) == "function" and id ~= nil then return pcall(play, id, ...) end
end
