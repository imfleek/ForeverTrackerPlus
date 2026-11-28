-- ForeverTrackerPlus: our own tracker, phase 5 (OWN_TRACKER_PLAN.md): the Professions section (tracked recipes).
--
-- Blizzard's tracker is invisible with our own tracker, so its Professions section is too (user: "I don't see the
-- professions/tracked recipes"). This file reads the tracked recipes and their reagents; Frame.lua draws them under
-- the quests, with a "Professions" header as on Blizzard's tracker.
--
--   data      C_TradeSkillUI.GetRecipesTracked (recipes and recrafts) and GetRecipeSchematic: the recipe's name and
--             its basic reagents (each slot: the count you have of all its items, the count it needs).
--   clicks    left: open the recipe in its profession window. Shift+left: stop tracking it (as on Blizzard's tracker).
--             Right: a menu with both. Hover a reagent: its item tooltip.
--
-- RULE (tests/own_tracker_rules_test.lua): nothing here touches Blizzard's tracker; reads only.
local ADDON, root = ...; local ns = root.tracker
if not ns or ns.disabled then return end
local api = ns.api

local function itemName(id)
	local name
	if C_Item and C_Item.GetItemNameByID then
		local ok, n = pcall(C_Item.GetItemNameByID, id)
		if ok then name = n end
	end
	if not name and GetItemInfo then
		local ok, n = pcall(GetItemInfo, id)
		if ok then name = n end
	end
	if C_Item and C_Item.RequestLoadItemDataByID and not name then pcall(C_Item.RequestLoadItemDataByID, id) end
	return name
end

-- what you carry, with the reagent bank (as Blizzard's tracker counts it)
local function itemCount(id)
	if ItemUtil and ItemUtil.GetCraftingReagentCount then
		local ok, n = pcall(ItemUtil.GetCraftingReagentCount, id)
		if ok and type(n) == "number" then return n end
	end
	if C_Item and C_Item.GetItemCount then
		local ok, n = pcall(C_Item.GetItemCount, id, false, false, true)
		if ok and type(n) == "number" then return n end
	end
	if GetItemCount then
		local ok, n = pcall(GetItemCount, id)
		if ok and type(n) == "number" then return n end
	end
	return 0
end

local function basicType()
	return Enum and Enum.CraftingReagentType and Enum.CraftingReagentType.Basic or 1
end

-- { { id, recraft, name, icon, reagents = { { itemID, name, have, need } } } }
function api.ownRecipes()
	local out = {}
	local ui = C_TradeSkillUI
	if not (ui and ui.GetRecipesTracked and ui.GetRecipeSchematic) then return out end
	for _, recraft in ipairs({ false, true }) do
		local ok, ids = pcall(ui.GetRecipesTracked, recraft)
		for _, id in ipairs(ok and type(ids) == "table" and ids or {}) do
			local okS, s = pcall(ui.GetRecipeSchematic, id, recraft)
			if okS and type(s) == "table" then
				local r = { id = id, recraft = recraft, name = s.name or ("Recipe " .. id), icon = s.icon, reagents = {} }
				for _, slot in ipairs(s.reagentSlotSchematics or {}) do
					if slot.reagentType == basicType() and type(slot.reagents) == "table" and slot.reagents[1] then
						local have, first = 0, nil
						for _, reagent in ipairs(slot.reagents) do
							if reagent.itemID then
								first = first or reagent.itemID
								have = have + itemCount(reagent.itemID)
							end
						end
						if first then
							r.reagents[#r.reagents + 1] = { itemID = first, name = itemName(first) or "...", have = have,
								need = tonumber(slot.quantityRequired) or 1 }
						end
					end
				end
				out[#out + 1] = r
			end
		end
	end
	return out
end

---------------------------------------------------------------------------------------------------------------------
-- Clicks and tooltips
local function untrack(self)
	if C_TradeSkillUI and C_TradeSkillUI.SetRecipeTracked then
		pcall(C_TradeSkillUI.SetRecipeTracked, self.recipeID, false, self.recraft and true or false)
	end
end
local function open(self)
	if C_TradeSkillUI and C_TradeSkillUI.OpenRecipe then pcall(C_TradeSkillUI.OpenRecipe, self.recipeID) end
end
local function onClick(self, button)
	if not self.recipeID then return end
	if button == "LeftButton" then
		if IsShiftKeyDown and IsShiftKeyDown() then untrack(self) else open(self) end
		return
	end
	if button == "RightButton" and MenuUtil and MenuUtil.CreateContextMenu then
		MenuUtil.CreateContextMenu(self, function(_, root)
			root:CreateTitle(self.title or "")
			root:CreateButton(PROFESSIONS_OPEN_RECIPE or "Open recipe", function() open(self) end)
			root:CreateButton(PROFESSIONS_UNTRACK_RECIPE or "Stop tracking", function() untrack(self) end)
		end)
	end
end
api.ownRecipeClick = onClick -- for tests
local function onEnter(self)
	GameTooltip:SetOwner(self, "ANCHOR_LEFT")
	if self.itemID and GameTooltip.SetItemByID then
		GameTooltip:SetItemByID(self.itemID)
	else
		GameTooltip:SetText(self.title or "", 1, 1, 1, 1, true)
		GameTooltip:AddLine("Click: open the recipe. Shift-click: stop tracking. Right-click: its menu.", 0.6, 0.6, 0.6, true)
	end
	GameTooltip:Show()
end
local function onLeave(self)
	if GameTooltip:GetOwner() == self then GameTooltip:Hide() end
end

local clickers, used = {}, 0
-- a hover button over fs (a recipe title or a reagent line)
function api.ownRecipeClicker(parent, fs, recipe, itemID)
	used = used + 1
	local b = clickers[used]
	if not b then
		b = CreateFrame("Button", nil, parent)
		b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		b:SetScript("OnClick", onClick)
		b:SetScript("OnEnter", onEnter)
		b:SetScript("OnLeave", onLeave)
		clickers[used] = b
	end
	b.recipeID, b.recraft, b.title, b.itemID = recipe.id, recipe.recraft, recipe.name, itemID
	b:ClearAllPoints()
	b:SetPoint("TOPLEFT", fs, "TOPLEFT")
	b:SetPoint("BOTTOMRIGHT", fs, "BOTTOMRIGHT")
	b:Show()
	return b
end
function api.ownRecipeClickersReset() used = 0 end
function api.ownRecipeClickersDone() for i = used + 1, #clickers do clickers[i]:Hide() end end
