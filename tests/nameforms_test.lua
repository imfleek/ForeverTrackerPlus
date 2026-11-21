-- R106-109: the other spellings tried for a guide's pick-up / NPC name (Rows.lua nameForms), from a scan of the
-- guides' pick-up names against the object and item names
local dir = arg[1]
local pass = true
local function check(l, c) print((c and "ok   " or "FAIL ") .. l); pass = pass and c end
local src = io.open(dir .. "/Objectives/tracker/Rows.lua"):read("a")
local from = src:find("local SMALL_WORDS", 1, true)
local to = select(2, src:find("\nfunction nameForms%(name%).-\n\treturn forms\nend\n", from))
assert(from and to, "nameForms not found")
local nameForms = assert(load("local nameForms\n" .. src:sub(from, to) .. "\nreturn nameForms"))()
local function has(name, want)
	for _, f in ipairs(nameForms(name)) do if f == want then return true end end
	return false
end
check("the name itself first", nameForms("Un'Goro Soil")[1] == "Un'Goro Soil")
check("plural: Potions -> Potion", has("Potions", "Potion"))
check("plural: Berries -> Berry", has("Berries", "Berry"))
check("loose pages: the first page", has("Green Hills of Stranglethorn - Pages", "Green Hills of Stranglethorn - Page 1"))
check("Sacks of Oats -> Sack of Oats", has("Sacks of Oats", "Sack of Oats"))
check("Bundles Of Wood -> Bundle of Wood", has("Bundles Of Wood", "Bundle of Wood"))
check("Eggs of Onyxia -> Egg of Onyxia", has("Eggs of Onyxia", "Egg of Onyxia"))
check("mound of dirt -> Mound of Dirt", has("mound of dirt", "Mound of Dirt"))
check("bonfire -> Bonfire", has("bonfire", "Bonfire"))
check("Kim'Jael's Equipment -> Kim'jael's Equipment", has("Kim'Jael's Equipment", "Kim'jael's Equipment"))
check("Rolf's Corpse -> Rolf's corpse", has("Rolf's Corpse", "Rolf's corpse"))
check("a ::id ending dropped", has("Bloodstained Satchel::581822", "Bloodstained Satchel"))
local forms = nameForms("Un'Goro Soil")
local seen, dup = {}, false
for _, f in ipairs(forms) do if seen[f] then dup = true end seen[f] = true end
check("no form twice", not dup)
print(pass and "PASSED" or "FAILED")
