-- GearScout / Buffs.lua
-- Works out which group buffs you are missing that somebody standing next to
-- you could actually give you, and which of those your spec has any use for.
--
-- Three filters, and a buff has to survive all three before it is mentioned:
--
--   1. Somebody present can cast it. The classes actually on the roster are
--      read every time the group changes. Telling a hunter they are missing a
--      paladin blessing when there is no paladin in the group is noise.
--   2. That person is high enough level to have learned it. A level 27 group
--      is never asked for a spell that is trained at 60.
--   3. Your spec wants it. A Beast Mastery hunter is pointed at Blessing of
--      Might and never at Blessing of Wisdom. A Holy paladin gets the exact
--      opposite answer. That judgement comes out of the stat weights in
--      Data/StatWeights.lua where the spec has them, and out of the role on
--      the Profiles.lua profile where it does not, rather than out of a
--      fourth hand written opinion about who wants what. Two of those five
--      roles turn out to be one label covering two different jobs, and both
--      are split finer here. See the role section further down for which.
--
-- Burning Crusade rules this file exists to respect, all of which differ from
-- vanilla, from retail, or from both:
--
--   Blessings are one per paladin per target. A paladin who has given you
--   Might cannot also give you Wisdom, so asking for both when one paladin is
--   present is asking for something that cannot happen. The number worth
--   asking for is the number of paladins present, minus the blessings already
--   on you, best first.
--
--   Totems, shouts, paladin auras and the imp's Blood Pact only reach the
--   caster's own party. In a raid that means your own subgroup, so the roster
--   scan works out which subgroup you are in and only counts those people for
--   party scoped buffs. Blessings are single target and reach the whole raid,
--   so they are not restricted that way.
--
--   Totems occupy one slot per element. A shaman running Windfury cannot also
--   be running Grace of Air, so those two are never both requested, and
--   whichever one your spec actually benefits from is the one named. The
--   paladin's single aura works the same way.
--
--   Shamans are Horde and Draenei only and paladins are Alliance and Blood
--   Elf only, but none of that is hardcoded here. The roster is read for who
--   is actually standing there, which is correct on either faction and stays
--   correct whatever the client decides in future.
--
--   Feral Combat is one talent tree covering two entirely different jobs, the
--   bear who tanks and the cat who does damage, where retail splits them into
--   two specialisations you can read off the character. No arrangement of
--   talent points separates them, so the tree is not asked. The form is.
--
-- Nothing here scans auras on a timer. The answer is rebuilt only when your
-- auras or the roster actually change, coalesced, and never more than four
-- times a second. See the caching section at the bottom.

local ADDON, ns = ...

local UnitClass, UnitLevel, UnitName, UnitExists = UnitClass, UnitLevel, UnitName, UnitExists
local UnitIsUnit, UnitIsConnected = UnitIsUnit, UnitIsConnected
local IsInRaid, IsInGroup = IsInRaid, IsInGroup
local GetNumGroupMembers, GetNumSubgroupMembers = GetNumGroupMembers, GetNumSubgroupMembers
local GetRaidRosterInfo = GetRaidRosterInfo
local InCombatLockdown, GetTime = InCombatLockdown, GetTime
local C_Timer = C_Timer
local ipairs, pairs, next, wipe, pcall = ipairs, pairs, next, wipe, pcall
local format, sort, concat = string.format, table.sort, table.concat
local L = ns.L

-- ---------------------------------------------------------------------------
-- what a buff hands you
--
-- Every buff below declares what it gives in this vocabulary, and the want
-- table further down scores each tag for the current spec. A buff is judged
-- by the best thing it gives rather than the sum of them, because Mark of the
-- Wild handing a caster five points of strength does not make it a strength
-- buff.
-- ---------------------------------------------------------------------------
--   attackPower   melee and ranged attack power
--   strength      strength specifically
--   agility       agility specifically
--   stamina       health
--   intellect     mana pool, and spell crit for the classes that scale it
--   spirit        spirit specifically
--   manaRegen     mana coming back over time
--   spellPower    spell damage or healing done
--   spellHit      spell hit chance
--   crit          critical strike chance on swings and shots
--   spellCrit     critical strike chance on spells, which is a different
--                 thing entirely: Totem of Wrath does nothing for a bow
--   meleeWeapon   only does anything to a weapon swing, never to a shot or a spell
--   allStats      every primary stat at once
--   armor         armor or flat damage reduction
--   threatDown    less threat made, which is wrong for whoever is tanking
--   tankThreat    threat made by being hit, which is only useful to a tank
--   healingTaken  heals landing on you for more
--   healing       raw healing arriving on its own
--   resistance    school resistance

-- ---------------------------------------------------------------------------
-- the catalogue
--
-- key         stable, never localized, safe for a WeakAura to switch on
-- minLevel    the level the caster learns rank 1, not the level you need
-- scope       "party" the caster has to be in your own subgroup
--             "raid"  anybody on the roster can do it
-- gives       what it hands you, in the vocabulary above
-- ids         every spell that produces this buff, single target and group
--             version and every rank, because the group version has a
--             different name in every language and only the name is matched
-- slot        optional, a thing the caster can only run one of at a time
-- talent      optional, the caster needs a talent point for it
-- situational optional, only right on some fights or for some roles
-- why         one plain sentence, written for somebody who has read no guides
--
-- talent and situational entries never appear as something you are simply
-- missing. There is no way from here to know whether the paladin ever spent
-- the point, or whether this is the fight where shadow resistance matters, so
-- they go out on a second list that a display can choose to show.
-- ---------------------------------------------------------------------------
local BUFF_SOURCES = {
    PRIEST = {
        { key = "fort", minLevel = 1, scope = "raid",
          gives = { "stamina" },
          ids = { 1243, 21562 },
          why = "Extra health. There is no reason to fight without it." },
        -- Spirit only, not manaRegen. Spirit regen is switched off for five
        -- seconds every time you spend mana, so it is worth what a healer's
        -- spirit weight says it is worth and close to nothing to anybody who
        -- never stops spending. Tagging it as mana coming back was putting it
        -- level with Blessing of Wisdom in front of a tank, which it is not:
        -- Wisdom keeps paying while you cast and this does not. The sentence
        -- below already said so.
        { key = "spirit", minLevel = 30, scope = "raid",
          gives = { "spirit" },
          ids = { 14752, 27681 },
          why = "Regenerates your mana faster between casts." },
        { key = "shadowprot", minLevel = 30, scope = "raid", situational = true,
          gives = { "resistance" },
          ids = { 976, 27683 },
          why = "Shadow resistance. Worth asking for on a fight that throws shadow damage at you and worth nothing on any other." },
    },

    MAGE = {
        { key = "int", minLevel = 1, scope = "raid",
          gives = { "intellect", "manaRegen" },
          ids = { 1459, 23028 },
          why = "More mana, and more chance to land a critical spell." },
    },

    DRUID = {
        { key = "motw", minLevel = 1, scope = "raid",
          gives = { "allStats", "resistance" },
          ids = { 1126, 21849 },
          why = "Raises every one of your stats and your resistances at once." },
        { key = "thorns", minLevel = 6, scope = "raid", situational = true,
          gives = { "tankThreat" },
          ids = { 467 },
          why = "Hurts anything that hits you, which helps whoever is tanking hold a group and does nothing for anyone else." },
        { key = "lotp", minLevel = 40, scope = "party", talent = true,
          gives = { "crit" },
          ids = { 17007 },
          why = "Critical strike chance for the druid's party, if they are feral and have spent the talent point." },
        { key = "moonkin", minLevel = 40, scope = "party", talent = true,
          gives = { "spellCrit" },
          ids = { 24907 },
          why = "Spell critical strike chance for the druid's party, if they are balance and standing in moonkin form." },
    },

    PALADIN = {
        { key = "might", minLevel = 4, scope = "raid", slot = "blessing",
          gives = { "attackPower" },
          ids = { 19740, 25782 },
          why = "Straight attack power, so every hit lands harder." },
        { key = "wisdom", minLevel = 14, scope = "raid", slot = "blessing",
          gives = { "manaRegen" },
          ids = { 19742, 25894 },
          why = "Gives mana back steadily, even while you are casting." },
        -- Talents open at level 10 and this one sits at the top of the
        -- Protection tree, so 20 is a practical floor rather than a hard one.
        -- It is on the talent list either way, so the level only decides
        -- whether it is worth mentioning at all.
        { key = "kings", minLevel = 20, scope = "raid", slot = "blessing", talent = true,
          gives = { "allStats" },
          ids = { 20217, 25898 },
          why = "Ten percent to every stat you have, which is the best blessing in the game for almost everybody. The paladin has to have spent the talent point on it." },
        { key = "salvation", minLevel = 40, scope = "raid", slot = "blessing", situational = true,
          gives = { "threatDown" },
          ids = { 1038, 25895 },
          why = "Cuts the threat you make, so you can hit harder without pulling things off the tank. Never ask for it while you are the one tanking." },
        { key = "blight", minLevel = 38, scope = "raid", slot = "blessing", situational = true,
          gives = { "healingTaken" },
          ids = { 19977, 25890 },
          why = "Makes a paladin's heals land on you for more. A tanking blessing and nothing to anybody else." },
        { key = "sanctuary", minLevel = 30, scope = "raid", slot = "blessing", talent = true,
          gives = { "armor" },
          ids = { 20911, 25899 },
          why = "Less damage taken, and some of it thrown back. A tanking blessing, and it needs a talent point." },
        -- A paladin runs exactly one aura and it only reaches their own party,
        -- so this is an any of these check rather than a demand for a specific
        -- one. Which aura they picked is their call. Having none at all is not.
        { key = "aura", minLevel = 1, scope = "party", slot = "paladinAura", situational = true,
          gives = { "armor", "resistance" },
          ids = { 465, 7294, 19746, 19876, 19888, 19891, 32223 },
          why = "A paladin runs one aura at a time and it only reaches their own party. Any of them beats standing there with none." },
    },

    WARRIOR = {
        { key = "bshout", minLevel = 1, scope = "party",
          gives = { "attackPower" },
          ids = { 6673 },
          why = "Attack power for everyone standing near the warrior." },
        { key = "cshout", minLevel = 68, scope = "party",
          gives = { "stamina" },
          ids = { 469 },
          why = "Extra health for the warrior's party, and it stacks with a priest's Fortitude." },
    },

    WARLOCK = {
        { key = "bloodpact", minLevel = 10, scope = "party",
          gives = { "stamina" },
          ids = { 6307 },
          why = "Extra health from the warlock's imp, for as long as the imp is the demon they have out." },
    },

    HUNTER = {
        { key = "trueshot", minLevel = 40, scope = "party", talent = true,
          gives = { "attackPower" },
          ids = { 19506 },
          why = "Attack power for the hunter's party, if they are marksmanship and have spent the talent point." },
    },

    -- Totems reach the shaman's own party and only one per element can be
    -- planted, so each element is a slot. Whichever totem in that slot your
    -- spec actually gains from is the one named, and any totem from that
    -- element already on you counts the slot as used.
    SHAMAN = {
        { key = "strengthofearth", minLevel = 10, scope = "party", slot = "earthTotem",
          gives = { "strength" },
          ids = { 8075 },
          why = "Strength for the shaman's party, out of a totem that has to stay planted near you." },
        { key = "stoneskin", minLevel = 4, scope = "party", slot = "earthTotem", situational = true,
          gives = { "armor" },
          ids = { 8071 },
          why = "Armor instead of strength out of the earth slot. A tanking choice." },
        { key = "windfury", minLevel = 32, scope = "party", slot = "airTotem",
          gives = { "meleeWeapon" },
          ids = { 8512 },
          why = "Extra windfury hits on weapon swings. It does nothing at all for a bow, a gun or a spell." },
        { key = "graceofair", minLevel = 42, scope = "party", slot = "airTotem",
          gives = { "agility" },
          ids = { 8835 },
          why = "Agility for the shaman's party, which is attack power and crit for anyone who scales off it." },
        { key = "wrathofair", minLevel = 64, scope = "party", slot = "airTotem",
          gives = { "spellPower" },
          ids = { 3738 },
          why = "Spell damage and healing for the shaman's party." },
        { key = "manaspring", minLevel = 26, scope = "party", slot = "waterTotem",
          gives = { "manaRegen" },
          ids = { 5675 },
          why = "A steady trickle of mana back to everyone near the totem." },
        { key = "healingstream", minLevel = 20, scope = "party", slot = "waterTotem", situational = true,
          gives = { "healing" },
          ids = { 5394 },
          why = "A small heal every few seconds to the shaman's party, instead of the mana one." },
        { key = "totemofwrath", minLevel = 60, scope = "party", slot = "fireTotem", talent = true,
          gives = { "spellCrit", "spellHit" },
          ids = { 30706 },
          why = "Spell crit and spell hit for the party, from an elemental shaman deep enough in the tree to have it." },
    },
}

local CLASS_LABEL = {
    WARRIOR = "warrior", PALADIN = "paladin", HUNTER = "hunter", ROGUE = "rogue",
    PRIEST = "priest", SHAMAN = "shaman", MAGE = "mage", WARLOCK = "warlock",
    DRUID = "druid",
}

-- ---------------------------------------------------------------------------
-- what this spec wants
--
-- Two sources, and the higher of the two wins.
--
--   Stat weights, Data/StatWeights.lua, are the sharp instrument. They exist
--   for nine specs and they say things a role never could: Beast Mastery
--   weighs intellect at 0.05, which is exactly what stops this file asking a
--   paladin for Wisdom on a hunter's behalf.
--
--   Role, off the Profiles.lua profile and refined below, covers the other
--   eighteen specs and also sits under the weights as a floor, so a shadow
--   priest whose weight table lists no mana stat at all is still told that
--   Wisdom is worth having.
--
-- The floor is why a spec with weights can still be told about a buff its
-- weights are silent on. A weight answers "how good is one point of this on
-- an item", which is a different question from "do you want this buff", and
-- it has nothing at all to say about armor, threat, or heals landing harder.
-- Where the two disagree the buff question wins, because that is the question
-- being asked.
--
-- Both are read live, so respeccing changes the answer without a reload, and
-- so does shifting form.
-- ---------------------------------------------------------------------------
local WANT_THRESHOLD = 0.25   -- below this the buff is not worth the line of text
local UNKNOWN_WANT   = 0.5    -- no profile built yet: say everything rather than nothing
local MAX_OPTIONAL   = 5

-- Which stat weight keys speak for each tag. Best of them wins, never the sum.
local WEIGHT_KEYS = {
    attackPower = { "ITEM_MOD_ATTACK_POWER_SHORT", "ITEM_MOD_STRENGTH_SHORT", "ITEM_MOD_AGILITY_SHORT" },
    strength    = { "ITEM_MOD_STRENGTH_SHORT" },
    agility     = { "ITEM_MOD_AGILITY_SHORT" },
    stamina     = { "ITEM_MOD_STAMINA_SHORT" },
    intellect   = { "ITEM_MOD_INTELLECT_SHORT" },
    spirit      = { "ITEM_MOD_SPIRIT_SHORT" },
    manaRegen   = { "ITEM_MOD_MANA_REGENERATION_SHORT", "ITEM_MOD_SPIRIT_SHORT", "ITEM_MOD_INTELLECT_SHORT" },
    spellPower  = { "ITEM_MOD_SPELL_POWER_SHORT", "ITEM_MOD_SPELL_DAMAGE_DONE_SHORT", "ITEM_MOD_SPELL_HEALING_DONE_SHORT" },
    spellHit    = { "ITEM_MOD_HIT_SPELL_RATING_SHORT" },
    -- Kept apart on purpose. Reading a hunter's melee crit weight as an
    -- answer about spell crit is what put Totem of Wrath in front of a Beast
    -- Mastery hunter, and it does nothing whatsoever for a bow.
    crit        = { "ITEM_MOD_CRIT_RATING_SHORT" },
    spellCrit   = { "ITEM_MOD_CRIT_SPELL_RATING_SHORT" },
    allStats    = { "ITEM_MOD_STRENGTH_SHORT", "ITEM_MOD_AGILITY_SHORT", "ITEM_MOD_STAMINA_SHORT",
                    "ITEM_MOD_INTELLECT_SHORT", "ITEM_MOD_SPIRIT_SHORT" },
    -- armor, meleeWeapon, threatDown, tankThreat, healingTaken, healing and
    -- resistance have no honest stat weight key on this client, so they are
    -- decided by role alone. StatWeights.lua deliberately dropped
    -- ITEM_MOD_ARMOR for the same reason, see audit finding 6 in that file.
}

-- Roles come from Profiles.lua and cover all 27 specs. Two of the five are
-- one label covering two different jobs, so this table carries seven rows and
-- ResolveRole below picks between them. Profiles.lua itself is left alone:
-- other files read its role for other questions and the API hands it back
-- verbatim, so the refinement lives here and nothing outside this file sees
-- it.
--
--   tank        Protection warrior, and the safe answer for anything else
--               that tanks. Rage, weapon swings, and being hit.
--   spellTank   Protection paladin. Threat is holy spell damage out of Holy
--               Shield, Consecration, Avenger's Shield and Judgement, not out
--               of the weapon, which is StatWeights.lua's own conclusion in
--               its Protection paladin hard rules. Wrath of Air is therefore
--               a threat buff to them, Windfury very nearly is not, and
--               Blessing of Might is the wrong thing to spend a paladin's one
--               blessing on. Mana is the other half: a Protection paladin out
--               of mana stops making threat entirely.
--   bearTank    A feral druid in bear form. Rage powered like the warrior,
--               but agility is the avoidance stat, no weapon effect ever
--               procs off a form, and nothing in bear form costs mana.
local ROLE_WANTS = {
    melee = {
        attackPower = 1,   strength = 0.9,  agility = 0.85, stamina = 0.6,
        intellect = 0.25,  spirit = 0.1,    manaRegen = 0.3, spellPower = 0,
        spellHit = 0,      crit = 0.8,      spellCrit = 0,  meleeWeapon = 1,
        allStats = 1,      armor = 0.3,     threatDown = 0.6, tankThreat = 0,
        healingTaken = 0.1, healing = 0.3,  resistance = 0.3,
    },
    ranged = {  -- hunters, and only hunters
        attackPower = 1,   strength = 0.05, agility = 1,    stamina = 0.5,
        intellect = 0.3,   spirit = 0.05,   manaRegen = 0.2, spellPower = 0,
        spellHit = 0,      crit = 0.8,      spellCrit = 0,  meleeWeapon = 0,
        allStats = 1,      armor = 0.2,     threatDown = 0.6, tankThreat = 0,
        healingTaken = 0.1, healing = 0.3,  resistance = 0.3,
    },
    tank = {  -- Protection warrior, and the fallback for any other tank
        attackPower = 0.5, strength = 0.7,  agility = 0.6,  stamina = 1,
        intellect = 0.4,   spirit = 0.1,    manaRegen = 0.6, spellPower = 0.2,
        spellHit = 0.1,    crit = 0.4,      spellCrit = 0.1, meleeWeapon = 0.8,
        allStats = 1,      armor = 1,       threatDown = 0,  tankThreat = 0.7,
        healingTaken = 1,  healing = 0.6,   resistance = 0.6,
    },
    -- Protection paladin. Attack power sits under the threshold on purpose:
    -- it moves only the small white damage share of paladin threat, and
    -- leaving it above the line is what put Blessing of Might in front of a
    -- tank. Mana outranks spell damage because a paladin with an empty bar
    -- casts nothing at all, and spell damage outranks every avoidance stat a
    -- buff can hand out because it is the threat stat.
    spellTank = {
        attackPower = 0.2, strength = 0.3,  agility = 0.4,  stamina = 1,
        intellect = 0.5,   spirit = 0.15,   manaRegen = 0.7, spellPower = 0.6,
        spellHit = 0.35,   crit = 0.3,      spellCrit = 0.35, meleeWeapon = 0.2,
        allStats = 1,      armor = 1,       threatDown = 0,  tankThreat = 0.7,
        healingTaken = 1,  healing = 0.6,   resistance = 0.6,
    },
    -- Feral druid in bear form. Threat is attack power and rage, so Might is
    -- the right blessing here and Wisdom is not, which is the exact opposite
    -- of the paladin above. Agility is the avoidance stat rather than a
    -- damage one, and mana only ever pays for shifting back out.
    bearTank = {
        attackPower = 0.55, strength = 0.6, agility = 0.9,  stamina = 1,
        intellect = 0.15,  spirit = 0.05,   manaRegen = 0.15, spellPower = 0,
        spellHit = 0,      crit = 0.5,      spellCrit = 0,  meleeWeapon = 0,
        allStats = 1,      armor = 1,       threatDown = 0,  tankThreat = 0.7,
        healingTaken = 1,  healing = 0.6,   resistance = 0.5,
    },
    healer = {
        attackPower = 0,   strength = 0,    agility = 0.05, stamina = 0.5,
        intellect = 0.9,   spirit = 0.9,    manaRegen = 1,  spellPower = 1,
        spellHit = 0.1,    crit = 0.05,     spellCrit = 0.5, meleeWeapon = 0,
        allStats = 0.9,    armor = 0.2,     threatDown = 0.5, tankThreat = 0,
        healingTaken = 0.1, healing = 0.3,  resistance = 0.3,
    },
    caster = {
        attackPower = 0,   strength = 0,    agility = 0.05, stamina = 0.5,
        intellect = 0.7,   spirit = 0.5,    manaRegen = 0.7, spellPower = 1,
        spellHit = 1,      crit = 0.05,     spellCrit = 0.7, meleeWeapon = 0,
        allStats = 0.9,    armor = 0.2,     threatDown = 0.6, tankThreat = 0,
        healingTaken = 0.1, healing = 0.3,  resistance = 0.3,
    },
}

-- Hard class facts, applied over the top of any weighting. No amount of role
-- guessing should ever put a mana buff in front of a rogue.
local NO_MANA     = { WARRIOR = true, ROGUE = true }
local NO_PHYSICAL = { MAGE = true, WARLOCK = true, PRIEST = true }
local MANA_TAGS     = { manaRegen = true, intellect = true, spirit = true,
                        spellPower = true, spellHit = true, spellCrit = true }
local PHYSICAL_TAGS = { attackPower = true, strength = true, meleeWeapon = true }

-- A feral druid swings in a form, and a form does not proc a weapon effect,
-- so Windfury is worth nothing to them however melee their role looks.
local CLASS_TAG_ZERO = {
    DRUID = { meleeWeapon = true },
}

-- ---------------------------------------------------------------------------
-- which role this character is really playing
--
-- Profiles.lua hands back one of five roles for all 27 specs and it is right
-- about 25 of them. The two it cannot be right about are resolved here.
--
--   A Protection paladin and a Protection warrior are both "tank" and want
--   almost opposite things out of a shaman and a paladin. That one is settled
--   by the class, which is never in doubt.
--
--   Feral Combat is one tree doing two jobs, so Profiles.lua calls the whole
--   tree "melee" and a bear tank was being handed a cat's answer. There is no
--   honest way to read tanking intent out of talent points, so the form is
--   used instead. It is the thing the druid actually did rather than a guess
--   about what they meant, it is already in the list of buffs this file
--   scans, and shifting fires UNIT_AURA, which is the same event that
--   invalidates this answer. So the advice follows a druid in and out of bear
--   with no extra plumbing and no timer.
--
--   A feral druid standing in caster form has said nothing either way, and
--   the honest answer to that is the tree's own, so nothing is overridden.
--   That is a real limit rather than a solved problem: buff a druid while
--   they are out of form and they get the cat answer, which is the one the
--   tree supports.
-- ---------------------------------------------------------------------------
local BEAR_FORM_IDS = { 5487, 9634 }   -- Bear Form, Dire Bear Form

local bearFormNames
local function BearFormNames()
    if bearFormNames then return bearFormNames end
    local t = {}
    for i = 1, #BEAR_FORM_IDS do
        local n = ns.SpellName(BEAR_FORM_IDS[i])
        if n then t[n] = true end
    end
    -- Only cached once something resolved, so a spell API that was not ready
    -- yet is asked again next time instead of being remembered as empty.
    if next(t) then bearFormNames = t end
    return t
end

-- Set once per rebuild, from the same buff list the rest of the check uses.
local activeRole

local function ResolveRole(have)
    local prof = ns.activeProfile
    local role = prof and prof.role
    if not role then return nil end

    local cls = ns.playerClass
    if role == "tank" and cls == "PALADIN" then return "spellTank" end
    if role == "melee" and cls == "DRUID" then
        for name in pairs(BearFormNames()) do
            if have[name] then return "bearTank" end
        end
    end
    return role
end

local function WeightScore(tag)
    local sw = ns.STAT_WEIGHTS
    local prof = ns.activeProfile
    local cls = ns.playerClass
    if not sw or not prof or not cls then return 0 end
    local perClass = sw[cls]
    if not perClass then return 0 end
    local spec = perClass[prof.tabIndex or 1]
    local weights = spec and spec.weights
    if not weights then return 0 end
    local keys = WEIGHT_KEYS[tag]
    if not keys then return 0 end
    local best = 0
    for i = 1, #keys do
        local w = weights[keys[i]]
        if w and w > best then best = w end
    end
    return best
end

-- No profile yet, or a role with no table behind it, means nothing is known
-- rather than nothing is wanted, so the permissive answer stands.
local function RoleScore(tag)
    local t = activeRole and ROLE_WANTS[activeRole]
    if not t then return UNKNOWN_WANT end
    return t[tag] or 0
end

local function TagScore(tag)
    local cls = ns.playerClass
    if cls then
        if NO_MANA[cls] and MANA_TAGS[tag] then return 0 end
        if NO_PHYSICAL[cls] and PHYSICAL_TAGS[tag] then return 0 end
        local zero = CLASS_TAG_ZERO[cls]
        if zero and zero[tag] then return 0 end
    end
    local a, b = WeightScore(tag), RoleScore(tag)
    return a > b and a or b
end

-- A buff is worth as much as the best thing it gives.
local function WantScore(def)
    local best = 0
    for i = 1, #def.gives do
        local s = TagScore(def.gives[i])
        if s > best then best = s end
    end
    return best
end

-- ---------------------------------------------------------------------------
-- roster
--
-- Rebuilt only when the group changes. Two levels are kept per class: the
-- best anywhere on the roster, for blessings, and the best inside your own
-- subgroup, for everything that only reaches a party.
-- ---------------------------------------------------------------------------
local present = {}   -- [classFile] = { level, name, partyLevel, partyName, count }

-- GetRaidRosterInfo comes back nil past the end of the roster and does not
-- exist at all on some clients, so it is asked rather than assumed.
local function RaidSubgroup(index)
    if not GetRaidRosterInfo then return nil end
    local ok, _, _, sub = pcall(GetRaidRosterInfo, index)
    if not ok then return nil end
    return sub
end

local function NoteUnit(unit, inParty)
    if not UnitExists(unit) then return end
    -- Somebody offline cannot buff anybody.
    if UnitIsConnected and UnitIsConnected(unit) == false then return end

    local _, classFile = UnitClass(unit)
    if not classFile or not BUFF_SOURCES[classFile] then return end

    -- A raid member too far away reports level -1. Groups are normally level
    -- matched, so their own level is the least wrong guess available, and it
    -- keeps the level 27 case honest instead of silently demanding nothing.
    local lvl = UnitLevel(unit) or 0
    if lvl <= 0 then lvl = ns.playerLevel or 0 end

    local e = present[classFile]
    if not e then
        e = { level = 0, partyLevel = 0, count = 0 }
        present[classFile] = e
    end
    e.count = e.count + 1
    if lvl > e.level then
        e.level, e.name = lvl, UnitName(unit)
    end
    if inParty and lvl > e.partyLevel then
        e.partyLevel, e.partyName = lvl, UnitName(unit)
    end
end

local function ScanRoster()
    wipe(present)
    if not (IsInGroup() or IsInRaid()) then return end

    if IsInRaid() then
        local n = GetNumGroupMembers() or 0

        -- Which subgroup you are standing in. Without it, party scoped buffs
        -- are dropped rather than guessed at, which is the conservative half
        -- of being wrong.
        local mySub
        for i = 1, n do
            if UnitIsUnit("raid" .. i, "player") then
                mySub = RaidSubgroup(i)
                break
            end
        end

        for i = 1, n do
            local sub = RaidSubgroup(i)
            NoteUnit("raid" .. i, mySub ~= nil and sub == mySub)
        end
    else
        -- A party is one subgroup, so everyone in it counts for everything,
        -- and you count for yourself: a paladin with no blessing of their own
        -- on is the most common paladin mistake there is.
        NoteUnit("player", true)
        for i = 1, GetNumSubgroupMembers() do
            NoteUnit("party" .. i, true)
        end
    end
end

-- How many things can occupy this slot at once.
local function SlotCapacity(slot)
    if slot == "blessing" then
        -- One blessing per paladin, so two paladins is two blessings.
        local pal = present.PALADIN
        return (pal and pal.count) or 0
    end
    -- One totem per element, one aura per paladin, and a second shaman
    -- planting the same element does not stack with the first.
    return 1
end

-- ---------------------------------------------------------------------------
-- your auras
-- No PLAYER filter, because the whole point is to find what other people gave
-- you. Matching is by name, which makes every rank and every locale the same
-- buff, exactly as Profiles.lua and Rotation.lua already do it.
-- ---------------------------------------------------------------------------
local buffScratch = {}

local function PlayerBuffNames(out)
    wipe(out)
    for i = 1, 40 do
        local name = ns.GetAuraName("player", i, "HELPFUL")
        if not name then break end
        out[name] = true
    end
    return out
end

-- ---------------------------------------------------------------------------
-- the check
-- ---------------------------------------------------------------------------
local slotFilled, poolScratch, slotUsed = {}, {}, {}

local function Build()
    local missing, optional = {}, {}
    if not (IsInGroup() or IsInRaid()) then return missing, optional end
    -- Nobody present can give you anything, so the aura scan is skipped
    -- entirely rather than run to prove it.
    if not next(present) then return missing, optional end

    local have = PlayerBuffNames(buffScratch)
    -- Settled once, before anything is scored, because a druid's form is one
    -- of the buffs that was just read and every score below depends on it.
    activeRole = ResolveRole(have)
    wipe(slotFilled)
    wipe(slotUsed)
    wipe(poolScratch)

    for classFile, who in pairs(present) do
        local defs = BUFF_SOURCES[classFile]
        for i = 1, #defs do
            local def = defs[i]

            -- Resolve every name this buff can appear under. An id that will
            -- not resolve on this client is dropped quietly rather than
            -- breaking the entry, same as Profiles.lua.
            local label, icon, spellID, found
            for j = 1, #def.ids do
                local id = def.ids[j]
                local n, ic = ns.SpellName(id)
                if n then
                    if not label then label, icon, spellID = n, ic, id end
                    if have[n] then found = true break end
                end
            end

            if label then
                -- Something already on you occupies its slot whoever put it
                -- there, so this is counted before the level check and before
                -- any judgement about whether you wanted it.
                if found and def.slot then
                    slotFilled[def.slot] = (slotFilled[def.slot] or 0) + 1
                end

                if not found then
                    local level, from
                    if def.scope == "party" then
                        level, from = who.partyLevel, who.partyName
                    else
                        level, from = who.level, who.name
                    end

                    if from and level >= def.minLevel then
                        local score = WantScore(def)
                        if score >= WANT_THRESHOLD then
                            poolScratch[#poolScratch + 1] = {
                                key         = def.key,
                                label       = label,
                                icon        = icon,
                                spellID     = spellID,
                                why         = def.why,
                                from        = from,
                                fromClass   = CLASS_LABEL[classFile] or classFile:lower(),
                                classFile   = classFile,
                                scope       = def.scope,
                                slot        = def.slot,
                                talent      = def.talent or false,
                                situational = def.situational or false,
                                score       = score,
                                isSelf      = (from == ns.playerName) and true or false,
                            }
                        end
                    end
                end
            end
        end
    end

    -- Most wanted first, so a display that only has room for one line shows
    -- the line that matters.
    sort(poolScratch, function(a, b)
        if a.score ~= b.score then return a.score > b.score end
        return a.label < b.label
    end)

    for i = 1, #poolScratch do
        local e = poolScratch[i]
        if e.talent or e.situational then
            if #optional < MAX_OPTIONAL then optional[#optional + 1] = e end
        elseif not e.slot then
            missing[#missing + 1] = e
        else
            -- One blessing per paladin, one totem per element. Asking for a
            -- second thing out of a slot that is already spoken for is asking
            -- for something the game will not do.
            local slot = e.slot
            local taken = (slotFilled[slot] or 0) + (slotUsed[slot] or 0)
            if taken < SlotCapacity(slot) then
                slotUsed[slot] = (slotUsed[slot] or 0) + 1
                missing[#missing + 1] = e
            end
        end
    end

    return missing, optional
end

-- ---------------------------------------------------------------------------
-- caching
--
-- Rotation.lua samples auras four times a second, but only while a fight is
-- running and only because uptime cannot be measured any other way. Nothing
-- here needs that. The answer only changes when your auras change or the
-- group changes, so those two events set a flag and one coalesced rebuild
-- runs behind them.
--
-- Three separate guards keep it cheap:
--   the aura handler does nothing at all while you are on your own,
--   rebuilds are batched, 0.3 seconds out of combat and a full second inside
--     it, because nobody is going to re-buff you mid pull,
--   and a rebuild asked for directly is refused if the last one was under a
--     quarter of a second ago, which is the same ceiling the rotation sampler
--     runs at.
--
-- A caller that arrives between a change and the rebuild behind it gets an
-- answer at most a quarter of a second stale, which is nothing next to the
-- ten minutes a blessing lasts.
-- ---------------------------------------------------------------------------
local MIN_INTERVAL = 0.25

local missingCache, optionalCache = {}, {}
local buffStamp, lastCompute = 0, -1
local dirty, rosterDirty, pendingRefresh = true, true, false
local lastSignature = ""
local sigScratch = {}

local function Signature(missing, optional)
    wipe(sigScratch)
    for i = 1, #missing do sigScratch[#sigScratch + 1] = missing[i].key end
    sigScratch[#sigScratch + 1] = "/"
    for i = 1, #optional do sigScratch[#sigScratch + 1] = optional[i].key end
    return concat(sigScratch, ",")
end

local function Recompute()
    if rosterDirty then
        ScanRoster()
        rosterDirty = false
    end

    -- Fresh tables every time rather than a wipe, so anything holding the
    -- previous answer keeps a consistent snapshot instead of watching it
    -- change under its own feet mid draw.
    local missing, optional = Build()
    missingCache, optionalCache = missing, optional
    lastCompute = GetTime()
    dirty = false

    local sig = Signature(missing, optional)
    if sig ~= lastSignature then
        lastSignature = sig
        buffStamp = buffStamp + 1
        ns:Emit("BUFFS_UPDATED", missing, optional)
    end
end

local function EnsureFresh()
    if not dirty then return end
    if GetTime() - lastCompute < MIN_INTERVAL then return end
    Recompute()
end

local function ScheduleRefresh()
    if pendingRefresh then return end
    pendingRefresh = true
    C_Timer.After(InCombatLockdown() and 1.0 or 0.3, function()
        pendingRefresh = false
        if dirty then Recompute() end
    end)
end

local function Invalidate(rosterToo)
    if rosterToo then rosterDirty = true end
    dirty = true
    ScheduleRefresh()
end

-- Auras churn constantly in a fight, so this handler does the cheapest thing
-- there is and sets a flag. The client filters the event down to the player
-- before Lua ever runs, and the whole path is dead while you are ungrouped.
ns:On("UNIT_AURA", function()
    if not (IsInGroup() or IsInRaid()) then return end
    Invalidate(false)
end, "player")

ns:On("GROUP_ROSTER_UPDATE", function() Invalidate(true) end)
ns:On("PLAYER_ENTERING_WORLD", function() Invalidate(true) end)
ns:On("PLAYER_LEVEL_UP", function() Invalidate(true) end)

-- UNIT_LEVEL also fires for a target or a mouseover whose level just became
-- known, which has nothing to do with this, so anything that is not a group
-- member is dropped on the first comparison.
ns:On("UNIT_LEVEL", function(unit)
    if type(unit) ~= "string" then return end
    if unit:sub(1, 5) ~= "party" and unit:sub(1, 4) ~= "raid" then return end
    Invalidate(true)
end)

-- A respec changes what you want without changing what you have.
ns:Sub("PROFILE_UPDATED", function() Invalidate(false) end)

-- ---------------------------------------------------------------------------
-- public
-- ---------------------------------------------------------------------------

-- Returns two arrays.
--
--   missing   buffs worth asking for right now, best first
--   optional  the ones that hang on a talent the caster may not have, or on
--             the fight being the right one. Kings, Salvation, Thorns, a
--             paladin aura.
--
-- Both are arrays of { key, label, icon, spellID, why, from, fromClass,
-- classFile, scope, slot, talent, situational, score, isSelf }. Callers
-- written before the second list existed take the first return and are
-- unaffected.
function ns.GetMissingGroupBuffs()
    EnsureFresh()
    return missingCache, optionalCache
end

-- A plain number that only moves when the answer moves. Polling this is free.
function ns.GetBuffStamp()
    EnsureFresh()
    return buffStamp
end

-- Names joined the way a person would say them.
local function JoinNames(list)
    local n = #list
    if n == 0 then return "" end
    if n == 1 then return list[1] end
    if n == 2 then return list[1] .. L[" and "] .. list[2] end
    return concat(list, ", ", 1, n - 1) .. L[" and "] .. list[n]
end

-- Formats the result as a single issue suitable for either the gear list or a
-- fight report. Returns nil when there is nothing to say. Only the confident
-- list is used here: the gear score is not the place to accuse a paladin of
-- not having taken a talent.
function ns.GetBuffIssue()
    local missing = ns.GetMissingGroupBuffs()
    if #missing == 0 then return nil end

    local names, sources, ownWork = {}, {}, false
    for _, m in ipairs(missing) do
        names[#names + 1] = m.label
        if m.isSelf then
            ownWork = true
        else
            sources[m.from] = true
        end
    end

    local people = {}
    for n in pairs(sources) do people[#people + 1] = n end
    sort(people)

    -- m.label is the spell's own name as the client spells it, and m.from is a
    -- player name. Both go into the sentence exactly as they arrived; only the
    -- words around them move. m.why is GearScout's own one line explanation
    -- and is translated.
    local detail
    if #missing == 1 then
        local m = missing[1]
        if m.isSelf then
            detail = format(L["You can put %s on yourself right now. %s"], m.label, L[m.why])
        else
            detail = format(L["%s is in your group and can give you %s. %s"], m.from, m.label, L[m.why])
        end
    else
        detail = format(L["Your group can give you %d buffs you do not have: %s."],
            #missing, concat(names, ", "))
    end

    local tail = L["Buffs are free, they last a long time, and they are the cheapest power you will ever get."]
    local fix
    if #people == 0 then
        fix = L["Cast them on yourself."] .. " " .. tail
    elseif ownWork then
        fix = format(L["Ask %s for them, and cast the rest on yourself. %s"], JoinNames(people), tail)
    else
        fix = format(L["Ask %s for them. %s"], JoinNames(people), tail)
    end

    return {
        sev    = ns.SEVERITY.WARN,
        title  = #missing == 1 and L["You are missing 1 group buff"]
                 or format(L["You are missing %d group buffs"], #missing),
        detail = detail,
        fix    = fix,
        count  = #missing,
        buffs  = missing,
    }
end
